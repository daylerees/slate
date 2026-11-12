"""tests/lib/parallel.py: a run in several parts, reported as one. A stand-in runner takes the
place of the container, so nothing is started: it leaves the totals a real part would."""
import importlib.util
import json
import os
import sys

import slate
from slate import Case, run

PARALLEL = slate.path("tests", "lib", "parallel.py")

# The stand-in: says what it was asked to run, and behaves as its part's name tells it to
RUNNER = r"""#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
part, only = a[a.index("--part") + 1], a[a.index("--only") + 1].split(",")
out = os.environ["SLATE_TEST_OUT"]
with open(os.path.join(out, "asked.txt"), "a") as f:
    f.write(part + " " + " ".join(a) + "\n")
behave = os.environ.get("BEHAVE_" + part.replace("-", "_"), "pass")
if behave == "die":
    sys.exit(125)
failed = 1 if behave == "fail" else 0
if failed:
    print(f"FAIL {only[0]} › something: it broke", flush=True)
tiers = {}
for u in only:
    t = tiers.setdefault(u.split("/")[0], {"ran": 0, "failed": 0, "seconds": 2.0})
    t["ran"] += 10
tiers[only[0].split("/")[0]]["failed"] = failed
os.makedirs(os.path.join(out, "parts"), exist_ok=True)
with open(os.path.join(out, "parts", part + ".json"), "w") as f:
    json.dump({"passed": 10 * len(only) - failed, "failed": failed, "seconds": 2.0,
               "skipped": [], "tiers": tiers, "files": {u: 7.5 for u in only}}, f)
sys.exit(failed)
"""


def module():
    spec = importlib.util.spec_from_file_location("slate_parallel", PARALLEL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SharingOut(Case):
    def test_groups_come_out_about_even(self):
        known = {"live/a": 170, "live/b": 150, "live/c": 120, "live/d": 90, "live/e": 30, "live/f": 20, "live/g": 10}
        groups = module().share_out(list(known), 3, known)
        self.assertEqual(sorted(u for g in groups for u in g), sorted(known), "every file once")
        totals = [sum(known[u] for u in g) for g in groups]
        self.assertLessEqual(max(totals) - min(totals), 30, f"uneven: {totals}")

    def test_never_more_groups_than_files(self):
        groups = module().share_out(["live/a", "live/b"], 4, {})
        self.assertEqual(groups, [["live/a"], ["live/b"]])

    def test_a_file_nobody_has_timed_gets_a_guess(self):
        self.assertGreater(module().weight("live/test_dock", {}), 20)
        self.assertEqual(module().weight("live/test_dock", {"live/test_dock": 44}), 44)


class Parts(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.out = os.path.join(self.h.dir, "out")
        os.makedirs(self.out)
        self.runner = os.path.join(self.h.dir, "runner")
        with open(self.runner, "w") as f:
            f.write(RUNNER)
        self.env = dict(self.h.env, SLATE_TEST_OUT=self.out)

    def go(self, *args, **behave):
        env = dict(self.env, **{"BEHAVE_" + k: v for k, v in behave.items()})
        return run([sys.executable, PARALLEL, *args, "--", sys.executable, self.runner], env=env, timeout=60)

    def asked(self):
        with open(os.path.join(self.out, "asked.txt")) as f:
            return {l.split()[0]: l for l in f}

    def test_every_file_runs_once_and_the_parts_add_up(self):
        code, out = self.go("--jobs", "3", "--tier", "all")
        asked = self.asked()
        self.assertEqual(sorted(asked), ["display-1", "display-2", "display-3", "quick"], out)
        files = []
        for name, line in asked.items():
            words = line.split()
            only = words[words.index("--only") + 1].split(",")
            self.assertTrue(all(u.split("/")[0] in (("static", "unit") if name == "quick" else ("live", "visual")) for u in only),
                            f"{name} was given {only}")
            files += only
        mod = module()
        every = [u for t in mod.TIERS for u in mod.units(t)]
        self.assertEqual(sorted(files), sorted(every), "each test file in exactly one part")
        self.assertEqual(code, 0, out)
        self.assertIn(f"PASS {10 * len(every)}/{10 * len(every)}", out)
        self.assertIn("at once)", out, "the live tier's line says it ran in parts")

    def test_a_failure_comes_through_and_fails_the_run(self):
        code, out = self.go("--jobs", "2", "--tier", "live", "-q", display_2="fail")
        self.assertEqual(code, 1, out)
        self.assertIn("› something: it broke", out)
        n = 10 * len(module().units("live"))
        self.assertEqual(out.strip().splitlines()[-1].split(" (")[0], f"FAIL {n - 1}/{n}")

    def test_a_part_that_dies_fails_the_run_and_names_its_files(self):
        code, out = self.go("--jobs", "2", "--tier", "live", "-q", display_1="die")
        self.assertEqual(code, 1, out)
        self.assertIn("FAIL part display-1: this part of the run didn't finish (exit code 125)", out)
        self.assertIn("live/test_", out)
        self.assertFalse(os.path.exists(os.path.join(self.out, "durations.json")),
                         "timings from a run that lost a part were kept")

    def test_timings_are_kept_for_next_time_but_not_from_a_filtered_run(self):
        self.go("--jobs", "2", "--tier", "live", "--filter", "dock")
        self.assertFalse(os.path.exists(os.path.join(self.out, "durations.json")))
        self.assertIn("--filter dock", self.asked()["display-1"], "the filter reaches each part")
        self.go("--jobs", "2", "--tier", "live")
        with open(os.path.join(self.out, "durations.json")) as f:
            self.assertEqual(json.load(f)["live/test_dock"], 7.5)

    def test_json_summary(self):
        code, out = self.go("--jobs", "2", "--tier", "live", "--json", display_1="fail")
        summary = json.loads(out.strip().splitlines()[-1])["summary"]
        self.assertEqual((summary["failed"], summary["parts"], summary["tiers"]), (1, 2, ["live"]))
        self.assertEqual(summary["total"], 10 * len(module().units("live")))
