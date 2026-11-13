#!/usr/bin/env python3
"""tests/run --repeat N: the same tests N times over, then only what didn't pass every time.

Started by tests/run, which hands over the command for one run (itself, without --repeat):
    repeat.py --times 5 --out tests/out [-q|-v|--json] -- <command…>

Each run has a tests/out of its own, tests/out/repeat/<n>/ (its logs, screenshots and
output.txt, everything it printed), so a later run never overwrites an earlier one's. It
starts with the timings and failed.txt the runs before it found (sharing out the files the
same way, and so --failed works with --repeat). Each run reports in --json; what's printed is
a line per test that failed in any run, how many runs it failed in, and a summary:

    FLAKY live/bar › clock_opens_panel failed 2 of 5 (runs 2, 4)
    FAIL live/dock › badges failed 5 of 5
    FAIL 2 didn't pass every time (1 failed every time), 5 runs of 412 checks (41m02s)

-q prints only those lines; the default adds a line as each run ends; --json a JSON object
per test, then {"summary": …}. tests/out/failed.txt is left naming every test that failed in
any run. Exit code 0 only when every run ran and passed.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

BROKEN = "!run"     # a run that didn't finish (no summary): its own line


def display(test_id):
    """'live/bar › clock_opens_panel' from tests.live.test_bar.Bar.test_clock_opens_panel
    (a class's or file's id, from a failure outside any test, as far as it goes)."""
    parts = test_id.split(".")
    if len(parts) < 3 or parts[0] != "tests":
        return test_id
    name = f"{parts[1]}/{parts[2].removeprefix('test_')}"
    if len(parts) == 4:
        name += f" › {parts[3]} (the whole class)"
    elif len(parts) > 4:
        name += f" › {parts[-1].removeprefix('test_')}"
    else:
        name += " (the whole file)"
    return name


def tally(runs):
    """{id: [the runs it failed in]} from each run's failed ids (a list of sets, run 1 first)."""
    counts = {}
    for n, ids in enumerate(runs, 1):
        for i in ids:
            counts.setdefault(i, []).append(n)
    return counts


def duration(seconds):
    m, s = divmod(int(seconds), 60)
    return f"{m}m{s:02d}s" if m else f"{s}s"


def read_ids(path):
    try:
        with open(path, encoding="utf-8") as f:
            return {l.strip() for l in f if l.strip().startswith("tests.")}
    except OSError:
        return set()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--" not in argv:
        sys.exit("repeat.py: the command for one run goes after --")
    cut = argv.index("--")
    command = argv[cut + 1:]
    ap = argparse.ArgumentParser(description="Run Slate's tests several times over")
    ap.add_argument("--times", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv[:cut])
    mode = "json" if a.json else "quiet" if a.quiet else "verbose" if a.verbose else "normal"

    base = os.path.join(a.out, "repeat")
    shutil.rmtree(base, ignore_errors=True)
    carried = {}            # what each run starts with: last time's timings and failures
    for name in ("durations.json", "failed.txt"):
        try:
            with open(os.path.join(a.out, name), encoding="utf-8") as f:
                carried[name] = f.read()
        except OSError:
            pass

    t0 = time.monotonic()
    failed_runs, totals, broken = [], [], {}
    for n in range(1, a.times + 1):
        d = os.path.join(base, str(n))
        os.makedirs(d)
        for name, text in carried.items():
            with open(os.path.join(d, name), "w", encoding="utf-8") as f:
                f.write(text)
        tn = time.monotonic()
        with open(os.path.join(d, "output.txt"), "w", encoding="utf-8") as log:
            p = subprocess.run(command + ["--json"], env=dict(os.environ, SLATE_TEST_OUT=d),
                               stdout=subprocess.PIPE, stderr=log, text=True)
            log.write(p.stdout)
        summary = None
        for line in p.stdout.splitlines():
            try:
                summary = json.loads(line).get("summary") or summary
            except (ValueError, AttributeError):
                pass
        ids = read_ids(os.path.join(d, "failed.txt"))
        if summary is None:
            broken[n] = p.returncode
            ids.add(BROKEN)
        else:
            totals.append(summary["total"])
        failed_runs.append(ids)
        try:        # (the next run shares the files out by this one's timings)
            with open(os.path.join(d, "durations.json"), encoding="utf-8") as f:
                carried["durations.json"] = f.read()
        except OSError:
            pass
        if mode in ("normal", "verbose"):
            rel = os.path.relpath(d, os.getcwd()) if d.startswith(os.getcwd()) else d
            if summary is None:
                what = f"didn't finish (exit code {p.returncode})"
            else:
                what = f"{summary['failed']} of {summary['total']} failed" if summary["failed"] else f"all {summary['total']} passed"
            print(f"run {n} of {a.times}: {what} ({duration(time.monotonic() - tn)})  [{rel}]", flush=True)

    counts = tally(failed_runs)
    took = duration(time.monotonic() - t0)
    every = sum(1 for runs in counts.values() if len(runs) == a.times)
    total = max(totals) if totals else 0
    # Every test that failed at least once, for tests/run --failed
    with open(os.path.join(a.out, "failed.txt"), "w", encoding="utf-8") as f:
        f.write("".join(i + "\n" for i in sorted(counts) if i != BROKEN))

    order = sorted(counts, key=lambda i: (-len(counts[i]), display(i)))
    for i in order:
        runs = counts[i]
        if i == BROKEN:
            name = "the run itself (see output.txt in tests/out/repeat/<n>/)"
        else:
            name = display(i)
        if mode == "json":
            print(json.dumps({"test": name, "id": i, "failed": len(runs), "of": a.times, "runs": runs}))
            continue
        word = "FAIL" if len(runs) == a.times else "FLAKY"
        which = "" if len(runs) == a.times else f" (run{'s' if len(runs) > 1 else ''} {', '.join(map(str, runs))})"
        print(f"{word} {name} failed {len(runs)} of {a.times}{which}")
    if mode == "json":
        print(json.dumps({"summary": {"runs": a.times, "total": total, "failed": len(counts), "every_time": every,
                                      "broken_runs": sorted(broken), "seconds": round(time.monotonic() - t0, 1)}}))
    elif counts:
        also = f" ({every} failed every time)" if every else ""
        print(f"FAIL {len(counts)} didn't pass every time{also}, {a.times} runs of {total} checks ({took})")
    else:
        print(f"PASS {total}/{total} every time, {a.times} runs ({took})")
    if mode in ("normal", "verbose"):
        rel = os.path.relpath(base, os.getcwd()) if base.startswith(os.getcwd()) else base
        print(f"Each run's logs and output: {rel}/<run>/")
    return 1 if counts or not totals else 0


if __name__ == "__main__":
    sys.exit(main())
