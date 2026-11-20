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
only = sorted({u.split("@")[0] for u in only})     # (slices of a file: the file, as the runner does)
# (the quiet part runs only the few tests marked quiet: one a file here)
each = 1 if "--quiet-tests" in a and a[a.index("--quiet-tests") + 1] == "only" else 10
tiers = {}
for u in only:
    t = tiers.setdefault(u.split("/")[0], {"ran": 0, "failed": 0, "seconds": 2.0})
    t["ran"] += each
tiers[only[0].split("/")[0]]["failed"] = failed
os.makedirs(os.path.join(out, "parts"), exist_ok=True)
with open(os.path.join(out, "parts", part + ".json"), "w") as f:
    json.dump({"passed": each * len(only) - failed, "failed": failed, "seconds": 2.0,
               "skipped": [], "tiers": tiers, "files": {u: 7.5 for u in only},
               "failed_ids": ["tests." + only[0].replace("/", ".") + ".Case.test_something"] if failed else []}, f)
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


class Shuffled(Case):
    """--shuffle: which files share a session changes with the seed, and the same seed shares
    them out the same way again, every file still in exactly one part."""
    FILES = [f"live/test_{c}" for c in "abcdefghijklmnop"]

    def share(self, seed):
        import random
        return module().share_out(list(self.FILES), 4, {}, random.Random(seed))

    def test_every_file_once(self):
        for seed in (1, 2, 3):
            self.assertEqual(sorted(u for g in self.share(seed) for u in g), sorted(self.FILES))

    def test_the_same_seed_the_same_parts(self):
        self.assertEqual(self.share(42), self.share(42))

    def test_another_seed_other_parts(self):
        seen = {tuple(tuple(g) for g in self.share(seed)) for seed in range(6)}
        self.assertGreater(len(seen), 3, "the seed barely changed which files share a session")

    def test_without_one_as_always(self):
        """No seed: longest first, as before, whatever order the files came in."""
        known = {u: 10 + i for i, u in enumerate(self.FILES)}
        groups = module().share_out(list(self.FILES), 4, known)
        self.assertEqual(groups, module().share_out(list(reversed(self.FILES)), 4, known))
        self.assertEqual(groups, [sorted(g) for g in groups], "each part's files in name order")


class Standin(Case):
    """Runs parallel.py with the stand-in runner in a scratch tests/out."""
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


class Parts(Standin):
    def test_every_file_runs_once_and_the_parts_add_up(self):
        code, out = self.go("--jobs", "3", "--tier", "all")
        asked = self.asked()
        self.assertEqual(sorted(n for n in asked if n.startswith("display")), ["display-1", "display-2", "display-3"], out)
        self.assertTrue(any(n.startswith("quick") for n in asked), out)
        files = []
        for name, line in asked.items():
            if name == "quiet":                  # (its files' quiet tests: they're in a display part too)
                continue
            words = line.split()
            only = words[words.index("--only") + 1].split(",")
            self.assertTrue(all(u.split("/")[0] in (("static", "unit") if name.startswith("quick") else ("live", "visual")) for u in only),
                            f"{name} was given {only}")
            files += only
        mod = module()
        every = [u for t in mod.TIERS for u in mod.units(t)]
        self.assertEqual(sorted(files), sorted(every), "each test file in exactly one part")
        self.assertEqual(code, 0, out)
        n = 10 * len(every) + len(mod.quiet_units(mod.units("live") + mod.units("visual")))
        self.assertIn(f"PASS {n}/{n}", out)
        self.assertIn("at once)", out, "the live tier's line says it ran in parts")

    def test_a_failure_comes_through_and_fails_the_run(self):
        code, out = self.go("--jobs", "2", "--tier", "live", "-q", display_2="fail")
        self.assertEqual(code, 1, out)
        self.assertIn("› something: it broke", out)
        n = 10 * len(module().units("live")) + len(module().quiet_units(module().units("live")))
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

    def test_quiet_tests_wait_for_the_rest_and_run_alone(self):
        """Tests marked @slate.quiet are left out of every part, and run in a part of their own
        ("quiet") once the others have all finished, from just their files."""
        code, out = self.go("--jobs", "3", "--tier", "live")
        self.assertEqual(code, 0, out)
        with open(os.path.join(self.out, "asked.txt")) as f:
            lines = f.read().splitlines()
        self.assertTrue(lines[-1].startswith("quiet "), "the quiet part didn't come last")
        quiet = lines[-1].split()
        self.assertEqual(quiet[quiet.index("--quiet-tests") + 1], "only")
        marked = module().quiet_units(module().units("live"))
        self.assertIn("live/test_launcher_scroll", marked)
        self.assertEqual(quiet[quiet.index("--only") + 1].split(","), marked)
        for line in lines[:-1]:
            self.assertIn("--quiet-tests skip", line)

    def test_shuffle_and_busy_reach_every_part(self):
        self.go("--jobs", "2", "--tier", "live", "--shuffle", "7", "--busy", "2")
        for line in self.asked().values():
            self.assertIn("--shuffle 7", line)
            self.assertIn("--busy 2", line)

    def test_json_summary(self):
        code, out = self.go("--jobs", "2", "--tier", "live", "--json", display_1="fail")
        summary = json.loads(out.strip().splitlines()[-1])["summary"]
        # (two parts, and the quiet tests' own once they've finished)
        self.assertEqual((summary["failed"], summary["parts"], summary["tiers"]), (1, 3, ["live"]))
        self.assertEqual(summary["total"], 10 * len(module().units("live")) + len(module().quiet_units(module().units("live"))))


class Failed(Standin):
    """What the parts failed is kept in tests/out/failed.txt, and --failed runs just that."""

    def failed(self):
        with open(os.path.join(self.out, "failed.txt")) as f:
            return f.read().splitlines()

    def test_the_parts_failures_are_kept_together(self):
        self.go("--jobs", "2", "--tier", "live", display_1="fail", display_2="fail")
        ids = self.failed()
        self.assertEqual(len(ids), 2, ids)
        self.assertTrue(all(i.startswith("tests.live.test_") and i.endswith(".Case.test_something") for i in ids), ids)

    def test_a_lost_part_runs_its_files_again(self):
        self.go("--jobs", "2", "--tier", "live", display_1="die")
        files = self.asked()["display-1"].split("--only ")[1].split()[0].split(",")
        self.assertEqual(self.failed(), sorted("tests." + u.replace("/", ".") for u in files))

    def test_no_failures_empties_it(self):
        self.go("--jobs", "2", "--tier", "live", display_1="fail")
        self.go("--jobs", "2", "--tier", "live")
        self.assertEqual(self.failed(), [])

    def test_failed_shares_out_only_their_files(self):
        with open(os.path.join(self.out, "failed.txt"), "w") as f:
            f.write("tests.live.test_dock.Dock.test_badges\ntests.live.test_bar\ntests.unit.test_spaces.S.test_x\n")
        code, out = self.go("--jobs", "3", "--tier", "unit,live", "--failed", "-q")
        self.assertEqual(code, 0, out)
        asked = self.asked()
        # (and test_bar's quiet test in the quiet part, as it has one)
        self.assertEqual(sorted(asked), ["display-1", "display-2", "quick", "quiet"], "a part for each file, and no more")
        only = sorted(f for name, line in asked.items() if name != "quiet" for f in line.split("--only ")[1].split()[0].split(","))
        self.assertEqual(only, ["live/test_bar", "live/test_dock", "unit/test_spaces"])
        self.assertIn("--only live/test_bar ", asked["quiet"])
        self.assertTrue(all("--failed" in line for line in asked.values()), "each part runs just the failed tests")
        self.assertFalse(os.path.exists(os.path.join(self.out, "durations.json")), "timings kept from a partial run")


class Slices(Standin):
    """A file in SPLIT (the visual scenes, one file as long as a whole part) is shared out in
    slices, and static and unit over a few parts, so neither is the last to finish."""

    def known(self, **times):
        with open(os.path.join(self.out, "durations.json"), "w") as f:
            json.dump(times, f)

    def only(self):
        return {name: line.split("--only ")[1].split()[0].split(",") for name, line in self.asked().items()}

    def test_a_long_visual_file_is_shared_out_in_slices(self):
        mod = module()
        times = {u: 100 for u in mod.units("live")}
        times["visual/test_visual"] = 100 * len(times) // 2          # half of all live's time
        self.known(**times)
        code, out = self.go("--jobs", "4", "--tier", "live,visual", "-q")
        self.assertEqual(code, 0, out)
        slices = sorted(u for files in self.only().values() for u in files if u.startswith("visual/"))
        n = len(slices)
        self.assertGreater(n, 1, "the visual file ran in one part")
        self.assertEqual(slices, sorted(f"visual/test_visual@{k}/{n}" for k in range(1, n + 1)), "each slice once")
        with open(os.path.join(self.out, "durations.json")) as f:
            self.assertEqual(json.load(f)["visual/test_visual"], 7.5 * len({p for p, files in self.only().items()
                                                                              if any(u.startswith("visual/") for u in files)}),
                             "a sliced file's time is all its slices' together")

    def test_a_short_one_is_left_whole(self):
        self.known(**{"visual/test_visual": 5})
        self.go("--jobs", "4", "--tier", "live,visual")
        self.assertIn(["visual/test_visual"], [[u for u in f if u.startswith("visual/")] for f in self.only().values()])

    def test_failed_runs_the_whole_file(self):
        self.known(**{"visual/test_visual": 100000})
        with open(os.path.join(self.out, "failed.txt"), "w") as f:
            f.write("tests.visual.test_visual.Visual.test_scenes\n")
        self.go("--jobs", "4", "--tier", "visual", "--failed")
        self.assertEqual(list(self.only().values()), [["visual/test_visual"]])

    def test_a_filtered_run_keeps_the_file_whole(self):
        """--filter settings-general: one session for the file, not one per slice (each slice
        ran the filter, and they all shot the same scene into the same file)."""
        self.known(**{"visual/test_visual": 100000})
        self.go("--jobs", "4", "--tier", "visual", "--filter", "settings-general")
        self.assertEqual(list(self.only().values()), [["visual/test_visual"]])

    def test_a_lost_slice_runs_the_file_again(self):
        self.known(**{"visual/test_visual": 100000})
        self.go("--jobs", "2", "--tier", "visual", display_1="die")
        with open(os.path.join(self.out, "failed.txt")) as f:
            self.assertEqual(f.read(), "tests.visual.test_visual\n")

    def test_static_and_unit_share_out_when_theyd_be_last(self):
        mod = module()
        quick = [u for t in ("static", "unit") for u in mod.units(t)]
        self.known(**{u: 30 for u in quick}, **{u: 10 for u in mod.units("live")})
        self.go("--jobs", "4", "--tier", "unit,static,live")
        parts = {n: f for n, f in self.only().items() if n.startswith("quick")}
        self.assertGreater(len(parts), 1, parts.keys())
        self.assertLessEqual(len(parts), mod.QUICK_PARTS)
        self.assertEqual(sorted(u for f in parts.values() for u in f), sorted(quick), "each file once")

    def test_static_and_unit_stay_one_part_when_quick(self):
        mod = module()
        self.known(**{u: 1 for t in ("static", "unit") for u in mod.units(t)}, **{u: 100 for u in mod.units("live")})
        self.go("--jobs", "4", "--tier", "unit,static,live")
        self.assertEqual([n for n in self.only() if n.startswith("quick")], ["quick"])


class InSlice(Case):
    """slate.in_slice: which of a sliced file's tests are this part's."""

    def test_the_slices(self):
        old = os.environ.get("SLATE_TEST_SLICES")
        try:
            os.environ.pop("SLATE_TEST_SLICES", None)
            self.assertTrue(all(slate.in_slice("visual/test_visual", i) for i in range(5)), "no slices: all of them")
            os.environ["SLATE_TEST_SLICES"] = "visual/test_visual@2/3"
            self.assertEqual([i for i in range(7) if slate.in_slice("visual/test_visual", i)], [1, 4])
            self.assertTrue(slate.in_slice("live/test_dock", 0), "another file's slices don't count")
            os.environ["SLATE_TEST_SLICES"] = "visual/test_visual@1/3,visual/test_visual@3/3"
            self.assertEqual([i for i in range(7) if slate.in_slice("visual/test_visual", i)], [0, 2, 3, 5, 6])
        finally:
            if old is None:
                os.environ.pop("SLATE_TEST_SLICES", None)
            else:
                os.environ["SLATE_TEST_SLICES"] = old
