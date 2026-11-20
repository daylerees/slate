#!/usr/bin/env python3
"""Runs Slate's tests as several parts side by side, and reports them as one run.

Started by tests/run, which hands over the command that starts one runner in a container:
    parallel.py --jobs 4 --tier all [-q|-v|--json] [--filter text] [--failed] [--label text] -- <command…>

The parts:
  * the tiers that need no display (static, unit) are one part;
  * the files of the tiers that do (live, visual) are shared out over --jobs parts, each with
    a Hyprland + Slate session of its own. A file is never split, so its tests keep their
    order, except the ones in SPLIT (the visual scenes, a single file that took as long as a
    whole part): those are shared out in slices, "visual/test_visual@2/3" being every third
    scene from the second, still in order. The files are shared out by how long each took last
    time (tests/out/durations.json), so the parts finish at about the same moment;
  * static and unit too, over as few parts as keep them from being the last to finish.

Each part is tests/lib/runner.py with --only and --part: it prints its failures as they
happen (they come through here untouched) and leaves its totals in tests/out/parts/, which
are added up here into the usual tier lines and summary. Exit code 0 only when everything
ran and passed.

The parts' failed tests (and the files of a part that never reported) are kept together in
tests/out/failed.txt, as runner.py does for a run in one part. --failed runs only those: just
their files are shared out, and each part runs just their tests.
"""
import argparse
import json
import math
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

TESTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("SLATE_TEST_OUT") or os.path.join(TESTS, "out")
TIERS = ["static", "unit", "live", "visual"]
DISPLAY = ("live", "visual")
# Files whose tests can be shared out in slices (the test takes SLATE_TEST_SLICES: slate.in_slice)
SPLIT = {"visual/test_visual"}
QUICK_PARTS = 4          # at most, for static and unit


def base(unit):
    """The file a slice is of ("visual/test_visual@2/3" → "visual/test_visual")."""
    return unit.split("@")[0]


def units(tier):
    """The tier's files, as "live/test_dock"."""
    d = os.path.join(TESTS, tier)
    if not os.path.isdir(d):
        return []
    return [f"{tier}/{f[:-3]}" for f in sorted(os.listdir(d)) if f.startswith("test_") and f.endswith(".py")]


def weight(unit, known):
    """How long a file is expected to take: last time's figure, or a guess from its size (a
    slice: its share of the file's)."""
    if "@" in unit:
        return max(weight(base(unit), known) / int(unit.split("/")[-1]), 1)
    if unit in known:
        return max(known[unit], 1)
    try:
        with open(os.path.join(TESTS, unit + ".py"), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return 30
    return 20 + 3 * len(re.findall(r"^\s+def test_", text, re.M))


def quiet_units(units_):
    """Of these live and visual files, the ones with a test marked @slate.quiet: those tests wait
    for every other part to finish, then run in a part of their own ("quiet"), on a computer
    that's quiet by then."""
    out = []
    for u in sorted({base(u) for u in units_}):
        try:
            with open(os.path.join(TESTS, u + ".py"), encoding="utf-8") as f:
                if re.search(r"^\s*@slate\.quiet\b", f.read(), re.M):
                    out.append(u)
        except OSError:
            pass
    return out


def share_out(files, jobs, known, rng=None):
    """`files` in at most `jobs` groups of about the same expected length: longest first,
    each to whichever group is shortest so far. With `rng` (--shuffle), in that random order
    instead, so which files share a session changes from seed to seed (the groups only roughly
    even), and each group keeps the order they came in."""
    groups = [[] for _ in range(max(1, min(jobs, len(files))))]
    totals = [0] * len(groups)
    if rng is not None:
        order = sorted(files)
        rng.shuffle(order)
    else:
        order = sorted(files, key=lambda u: -weight(u, known))
    for u in order:
        i = totals.index(min(totals))
        groups[i].append(u)
        totals[i] += weight(u, known)
    return [g if rng is not None else sorted(g) for g in groups if g]


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--" not in argv:
        sys.exit("parallel.py: the runner's command goes after --")
    cut = argv.index("--")
    command = argv[cut + 1:]
    ap = argparse.ArgumentParser(description="Run Slate's tests in parallel parts")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--tier", default="all")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--filter", default="")
    ap.add_argument("--failed", action="store_true")
    ap.add_argument("--label", default="")
    ap.add_argument("--shuffle", type=int, default=None)
    ap.add_argument("--busy", type=int, default=0)
    a = ap.parse_args(argv[:cut])
    rng = random.Random(a.shuffle) if a.shuffle is not None else None
    tiers = TIERS if a.tier == "all" else [t.strip() for t in a.tier.split(",") if t.strip()]
    bad = [t for t in tiers if t not in TIERS]
    if bad:
        ap.error(f"unknown tier: {', '.join(bad)}")
    mode = "json" if a.json else "quiet" if a.quiet else "verbose" if a.verbose else "normal"

    try:
        with open(os.path.join(OUT, "durations.json"), encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}

    again = None
    if a.failed:
        # (the file runner.py reads and writes: tests.live.test_dock… → live/test_dock)
        try:
            with open(os.path.join(OUT, "failed.txt"), encoding="utf-8") as f:
                again = {"/".join(l.strip().split(".")[1:3]) for l in f if l.startswith("tests.")}
        except OSError:
            again = set()

    def chosen(t):
        return [u for u in units(t) if again is None or u in again]

    parts = []                                   # (name, its files)
    quick = [u for t in tiers if t not in DISPLAY for u in chosen(t)]
    shown = [u for t in tiers if t in DISPLAY for u in chosen(t)]
    # About how long each display part will take: what a part may take without holding up the rest
    each = max(sum(weight(u, known) for u in shown) / max(a.jobs, 1), 60) if shown else 0
    if again is None and not a.filter:
        # (the failed tests run again from whole files, as they were found; and a filtered run's
        # few tests in one session, not a session for each slice of a file the filter mostly skips)
        def slices(u):
            n = max(1, min(a.jobs, math.ceil(weight(u, known) / each))) if u in SPLIT else 1
            return [f"{u}@{k}/{n}" for k in range(1, n + 1)] if n > 1 else [u]
        shown = [s for u in shown for s in slices(u)]
    if quick:
        n = 1 if not each else max(1, min(QUICK_PARTS, math.ceil(sum(weight(u, known) for u in quick) / each)))
        groups = share_out(quick, n, known, rng)
        for i, group in enumerate(groups):
            parts.append(("quick" if len(groups) == 1 else f"quick-{i + 1}", group))
    for i, group in enumerate(share_out(shown, a.jobs, known, rng) if shown else []):
        parts.append((f"display-{i + 1}", group))
    if not parts:
        sys.exit("parallel.py: no test files in " + ", ".join(tiers))

    partdir = os.path.join(OUT, "parts")
    shutil.rmtree(partdir, ignore_errors=True)
    os.makedirs(partdir, exist_ok=True)
    # The tests marked quiet: left out of every part, and run once they've all finished
    quiet = quiet_units(shown)
    passthrough = [f for f, on in (("-q", a.quiet), ("-v", a.verbose), ("--json", a.json)) if on]
    if a.filter:
        passthrough += ["--filter", a.filter]
    if a.failed:
        passthrough += ["--failed"]
    if a.shuffle is not None:
        passthrough += ["--shuffle", str(a.shuffle)]
    if a.busy:
        passthrough += ["--busy", str(a.busy)]

    lock = threading.Lock()
    procs, threads = {}, []

    def relay(p):
        for line in p.stdout:
            with lock:
                sys.stdout.write(line)
                sys.stdout.flush()

    def start(name, files, extra=()):
        p = subprocess.Popen(command + ["--tier", ",".join(tiers), "--only", ",".join(files), "--part", name]
                             + passthrough + list(extra), stdout=subprocess.PIPE, text=True, start_new_session=True)
        procs[name] = p
        th = threading.Thread(target=relay, args=(p,), daemon=True)
        th.start()
        threads.append(th)

    t0 = time.monotonic()
    for name, files in parts:
        start(name, files, ["--quiet-tests", "skip"] if quiet and name.startswith("display") else [])

    def stop_all(*_):
        for p in procs.values():
            if p.poll() is None:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except OSError:
                    pass
        sys.exit(130)
    signal.signal(signal.SIGINT, stop_all)
    signal.signal(signal.SIGTERM, stop_all)

    codes = {name: p.wait() for name, p in list(procs.items())}
    if quiet:
        parts.append(("quiet", quiet))
        start("quiet", quiet, ["--quiet-tests", "only"])
        codes["quiet"] = procs["quiet"].wait()
    for th in threads:
        th.join(5)
    took = time.monotonic() - t0

    passed = failed = 0
    skipped, per_tier, seconds, lost, failed_ids = [], {}, {}, [], set()
    for name, files in parts:
        try:
            with open(os.path.join(partdir, name + ".json"), encoding="utf-8") as f:
                r = json.load(f)
        except (OSError, ValueError):
            # (a part that never reported: the container didn't start, or the runner died)
            lost.append(name)
            failed_ids.update("tests." + base(u).replace("/", ".") for u in files)   # (its files run again)
            reason = f"this part of the run didn't finish (exit code {codes[name]}): {', '.join(files)}"
            if mode == "json":
                print(json.dumps({"test": f"part {name}", "reason": reason, "log": None}))
            else:
                print(f"FAIL part {name}: {reason}")
            continue
        passed += r["passed"]
        failed += r["failed"]
        skipped += r["skipped"]
        failed_ids.update(r.get("failed_ids", []))
        for u, t in r["files"].items():
            # (a file run in slices took all of theirs together, and one with quiet tests its
            # part's time and the quiet part's)
            seconds[u] = seconds.get(u, 0) + t if u in SPLIT or u in quiet else t
        for tier, t in r["tiers"].items():
            s = per_tier.setdefault(tier, {"ran": 0, "failed": 0, "seconds": 0, "parts": 0})
            s["ran"] += t["ran"]
            s["failed"] += t["failed"]
            s["seconds"] = max(s["seconds"], t["seconds"])
            s["parts"] += 1 if t["ran"] else 0
    failed += len(lost)
    total = passed + failed

    # What failed, for tests/run --failed (empty when nothing did)
    with open(os.path.join(OUT, "failed.txt.tmp"), "w", encoding="utf-8") as f:
        f.write("".join(i + "\n" for i in sorted(failed_ids)))
    os.replace(os.path.join(OUT, "failed.txt.tmp"), os.path.join(OUT, "failed.txt"))

    if not a.filter and not a.failed and not lost:
        known.update(seconds)
        with open(os.path.join(OUT, "durations.json"), "w", encoding="utf-8") as f:
            json.dump(known, f, indent=1, sort_keys=True)

    label = f" {a.label}" if a.label else ""
    if mode == "json":
        print(json.dumps({"summary": {"passed": passed, "failed": failed, "total": total, "skipped": len(skipped),
                                      "seconds": round(took, 1), "tiers": tiers, "label": a.label,
                                      "parts": len(parts)}}))
    else:
        if mode == "normal":
            for tier in tiers:
                t = per_tier.get(tier)
                if t:
                    side = f", {t['parts']} at once" if t["parts"] > 1 else ""
                    print(f"{tier:7} {t['ran'] - t['failed']}/{t['ran']} passed ({t['seconds']:.1f}s{side})")
        if skipped and mode != "quiet":
            for name, why in skipped[:20]:
                print(f"skip {name}: {why}")
        verdict = "FAIL" if failed else "PASS"
        extra = f", {len(skipped)} skipped" if skipped else ""
        print(f"{verdict} {passed}/{total}{label} ({took:.0f}s{extra})")
    return 1 if failed or total == 0 else 0


if __name__ == "__main__":
    sys.exit(main())
