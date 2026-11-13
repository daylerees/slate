"""tests/run --repeat N (tests/lib/repeat.py): the chosen tests N times over, then only what
didn't pass every time, with how many runs it failed in. A scratch checkout holds the runner and
a made-up test file, so nothing real is run."""
import importlib.util
import json
import os
import shutil
import sys

import slate
from slate import Case, run

REPEAT = slate.path("tests", "lib", "repeat.py")

# "Flaky" fails in the runs FAIL_ON names (it counts its runs in COUNT), "Bad" whenever BAD is set
FAKE = r'''
import os
import unittest


class Steady(unittest.TestCase):
    def test_passes(self):
        pass


class Flaky(unittest.TestCase):
    def test_sometimes(self):
        with open(os.environ["COUNT"], "a") as f:
            f.write("x")
        with open(os.environ["COUNT"]) as f:
            n = len(f.read())
        self.assertNotIn(str(n), os.environ.get("FAIL_ON", "").split(","), f"run {n} broke")


class Bad(unittest.TestCase):
    def test_always(self):
        self.assertFalse(os.environ.get("BAD"), "it broke")
'''


def module():
    spec = importlib.util.spec_from_file_location("slate_repeat", REPEAT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Names(Case):
    def test_display(self):
        d = module().display
        self.assertEqual(d("tests.live.test_bar.Bar.test_clock_opens"), "live/bar › clock_opens")
        self.assertEqual(d("tests.live.test_bar.Bar"), "live/bar › Bar (the whole class)")
        self.assertEqual(d("tests.live.test_bar"), "live/bar (the whole file)")

    def test_tally(self):
        self.assertEqual(module().tally([{"a"}, set(), {"a", "b"}]), {"a": [1, 3], "b": [3]})


class Repeat(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.root = os.path.join(self.h.dir, "slate")
        lib = os.path.join(self.root, "tests", "lib")
        os.makedirs(lib)
        os.makedirs(os.path.join(self.root, "tests", "unit"))
        for f in ("runner.py", "slate.py", "parallel.py", "repeat.py"):
            shutil.copy(slate.path("tests", "lib", f), lib)
        shutil.copy(slate.path("tests", "run"), os.path.join(self.root, "tests"))
        with open(os.path.join(self.root, "tests", "unit", "test_fake.py"), "w") as f:
            f.write(FAKE)
        self.out = os.path.join(self.h.dir, "out")
        os.makedirs(self.out)
        self.env = dict(self.h.env, SLATE_TEST_OUT=self.out, COUNT=os.path.join(self.h.dir, "count"))

    def repeat(self, *args, **env):
        return run([os.path.join(self.root, "tests", "run"), "--no-container", "--tier", "unit", *args],
                   env=dict(self.env, **env), timeout=120)

    def failed(self):
        with open(os.path.join(self.out, "failed.txt")) as f:
            return f.read().splitlines()

    def test_quiet_lists_only_what_failed_and_a_summary(self):
        code, out = self.repeat("--repeat", "3", "-q", FAIL_ON="2", BAD="1")
        self.assertEqual(code, 1, out)
        lines = out.splitlines()
        self.assertEqual(lines[:2], ["FAIL unit/fake › always failed 3 of 3",
                                     "FLAKY unit/fake › sometimes failed 1 of 3 (run 2)"], out)
        self.assertRegex(lines[2], r"^FAIL 2 didn't pass every time \(1 failed every time\), 3 runs of 3 checks \(\d+s\)$")
        self.assertEqual(len(lines), 3, "-q stays short")
        self.assertEqual(self.failed(), ["tests.unit.test_fake.Bad.test_always", "tests.unit.test_fake.Flaky.test_sometimes"],
                         "failed.txt names whatever failed in any run, for --failed")

    def test_each_run_keeps_its_own_output(self):
        self.repeat("--repeat", "2", "-q", FAIL_ON="1")
        for n, verdict in ((1, '"failed": 1'), (2, '"failed": 0')):
            with open(os.path.join(self.out, "repeat", str(n), "output.txt")) as f:
                self.assertIn(verdict, f.read())
            self.assertTrue(os.path.exists(os.path.join(self.out, "repeat", str(n), "failed.txt")))

    def test_everything_passing_every_time(self):
        code, out = self.repeat("--repeat", "3")
        self.assertEqual(code, 0, out)
        self.assertIn("run 2 of 3: all 3 passed", out)
        self.assertRegex(out, r"PASS 3/3 every time, 3 runs \(\d+s\)\n")
        self.assertIn("Each run's logs and output: ", out)
        self.assertEqual(self.failed(), [])

    def test_filter_reaches_each_run(self):
        code, out = self.repeat("--repeat", "2", "-q", "--filter", "steady", BAD="1")
        self.assertEqual(code, 0, out)
        self.assertRegex(out, r"^PASS 1/1 every time, 2 runs")

    def test_failed_and_repeat(self):
        """--failed --repeat: each run runs what failed before the repeat started."""
        self.repeat("-q", BAD="1")
        code, out = self.repeat("--failed", "--repeat", "2", "-q")
        self.assertEqual(code, 0, out)
        self.assertRegex(out, r"^PASS 1/1 every time, 2 runs")

    def test_json(self):
        code, out = self.repeat("--repeat", "2", "--json", FAIL_ON="2")
        lines = [json.loads(l) for l in out.splitlines()]
        self.assertEqual(lines[0], {"test": "unit/fake › sometimes", "id": "tests.unit.test_fake.Flaky.test_sometimes",
                                    "failed": 1, "of": 2, "runs": [2]})
        s = lines[1]["summary"]
        self.assertEqual((s["runs"], s["total"], s["failed"], s["every_time"]), (2, 3, 1, 0))

    def test_a_number(self):
        code, out = self.repeat("--repeat", "lots")
        self.assertEqual(code, 2)
        self.assertIn("--repeat is a number", out)
