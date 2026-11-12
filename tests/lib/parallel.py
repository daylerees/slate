#!/usr/bin/env python3
"""Runs Slate's tests as several parts side by side, and reports them as one run.

Started by tests/run, which hands over the command that starts one runner in a container:
    parallel.py --jobs 4 --tier all [-q|-v|--json] [--filter text] [--label text] -- <command…>

The parts:
  * the tiers that need no display (static, unit) are one part;
  * the files of the tiers that do (live, visual) are shared out over --jobs parts, each with
    a Hyprland + Slate session of its own. A file is never split, so its tests keep their
    order. The files are shared out by how long each took last time (tests/out/durations.json),
    so the parts finish at about the same moment.

Each part is tests/lib/runner.py with --only and --part: it prints its failures as they
happen (they come through here untouched) and leaves its totals in tests/out/parts/, which
are added up here into the usual tier lines and summary. Exit code 0 only when everything
ran and passed.
"""
import argparse
import json
import os
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


def units(tier):
    """The tier's files, as "live/test_dock"."""
    d = os.path.join(TESTS, tier)
    if not os.path.isdir(d):
        return []
    return [f"{tier}/{f[:-3]}" for f in sorted(os.listdir(d)) if f.startswith("test_") and f.endswith(".py")]


def weight(unit, known):
    """How long a file is expected to take: last time's figure, or a guess from its size."""
    if unit in known:
        return max(known[unit], 1)
    try:
        with open(os.path.join(TESTS, unit + ".py"), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return 30
    return 20 + 3 * len(re.findall(r"^\s+def test_", text, re.M))


def share_out(files, jobs, known):
    """`files` in at most `jobs` groups of about the same expected length: longest first,
    each to whichever group is shortest so far."""
    groups = [[] for _ in range(max(1, min(jobs, len(files))))]
    totals = [0] * len(groups)
    for u in sorted(files, key=lambda u: -weight(u, known)):
        i = totals.index(min(totals))
        groups[i].append(u)
        totals[i] += weight(u, known)
    return [sorted(g) for g in groups if g]


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
    ap.add_argument("--label", default="")
    a = ap.parse_args(argv[:cut])
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

    parts = []                                   # (name, its files)
    quick = [u for t in tiers if t not in DISPLAY for u in units(t)]
    if quick:
        parts.append(("quick", quick))
    shown = [u for t in tiers if t in DISPLAY for u in units(t)]
    for i, group in enumerate(share_out(shown, a.jobs, known) if shown else []):
        parts.append((f"display-{i + 1}", group))
    if not parts:
        sys.exit("parallel.py: no test files in " + ", ".join(tiers))

    partdir = os.path.join(OUT, "parts")
    shutil.rmtree(partdir, ignore_errors=True)
    os.makedirs(partdir, exist_ok=True)
    passthrough = [f for f, on in (("-q", a.quiet), ("-v", a.verbose), ("--json", a.json)) if on]
    if a.filter:
        passthrough += ["--filter", a.filter]

    lock = threading.Lock()
    procs, threads = {}, []

    def relay(p):
        for line in p.stdout:
            with lock:
                sys.stdout.write(line)
                sys.stdout.flush()

    t0 = time.monotonic()
    for name, files in parts:
        p = subprocess.Popen(command + ["--tier", ",".join(tiers), "--only", ",".join(files), "--part", name] + passthrough,
                             stdout=subprocess.PIPE, text=True, start_new_session=True)
        procs[name] = p
        th = threading.Thread(target=relay, args=(p,), daemon=True)
        th.start()
        threads.append(th)

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

    codes = {name: p.wait() for name, p in procs.items()}
    for th in threads:
        th.join(5)
    took = time.monotonic() - t0

    passed = failed = 0
    skipped, per_tier, seconds, lost = [], {}, {}, []
    for name, files in parts:
        try:
            with open(os.path.join(partdir, name + ".json"), encoding="utf-8") as f:
                r = json.load(f)
        except (OSError, ValueError):
            # (a part that never reported: the container didn't start, or the runner died)
            lost.append(name)
            reason = f"this part of the run didn't finish (exit code {codes[name]}): {', '.join(files)}"
            if mode == "json":
                print(json.dumps({"test": f"part {name}", "reason": reason, "log": None}))
            else:
                print(f"FAIL part {name}: {reason}")
            continue
        passed += r["passed"]
        failed += r["failed"]
        skipped += r["skipped"]
        seconds.update(r["files"])
        for tier, t in r["tiers"].items():
            s = per_tier.setdefault(tier, {"ran": 0, "failed": 0, "seconds": 0, "parts": 0})
            s["ran"] += t["ran"]
            s["failed"] += t["failed"]
            s["seconds"] = max(s["seconds"], t["seconds"])
            s["parts"] += 1 if t["ran"] else 0
    failed += len(lost)
    total = passed + failed

    if not a.filter and not lost:
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
