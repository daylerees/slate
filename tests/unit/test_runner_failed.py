"""tests/run --failed: every run keeps the ids of what failed in tests/out/failed.txt, and
--failed runs only those again. A scratch checkout holds the runner and a made-up test file
whose tests fail until a file says they're fixed, so nothing real is run."""
import os
import shutil
import sys

import slate
from slate import Case, run

# The made-up tests: "Bad" and one of "Sub"'s subtests fail until <out>/fixed exists, and
# "Broken"'s setUpClass until <out>/fixed-class does. Each test notes that it ran
FAKE = r'''
import os
import unittest

OUT = os.environ["SLATE_TEST_OUT"]


def ran(name):
    with open(os.path.join(OUT, "ran.txt"), "a") as f:
        f.write(name + "\n")


def fixed(what="fixed"):
    return os.path.exists(os.path.join(OUT, what))


class Good(unittest.TestCase):
    def test_passes(self):
        ran("good")


class Bad(unittest.TestCase):
    def test_fails(self):
        ran("bad")
        self.assertTrue(fixed(), "it broke")


class Sub(unittest.TestCase):
    def test_some(self):
        ran("sub")
        for n in ("one", "two"):
            with self.subTest(n):
                self.assertTrue(n == "one" or fixed(), "two broke")


class Broken(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not fixed("fixed-class"):
            raise RuntimeError("couldn't set up")

    def test_inside(self):
        ran("inside")
'''


class Failed(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.root = os.path.join(self.h.dir, "slate")
        lib = os.path.join(self.root, "tests", "lib")
        os.makedirs(lib)
        os.makedirs(os.path.join(self.root, "tests", "unit"))
        for f in ("runner.py", "slate.py", "parallel.py"):
            shutil.copy(slate.path("tests", "lib", f), lib)
        shutil.copy(slate.path("tests", "run"), os.path.join(self.root, "tests"))
        with open(os.path.join(self.root, "tests", "unit", "test_fake.py"), "w") as f:
            f.write(FAKE)
        self.out = os.path.join(self.h.dir, "out")
        os.makedirs(self.out)
        self.env = dict(self.h.env, SLATE_TEST_OUT=self.out)

    def runner(self, *args):
        return run([sys.executable, os.path.join(self.root, "tests", "lib", "runner.py"), "--tier", "unit", *args],
                   env=self.env, timeout=60)

    def slate_run(self, *args):
        return run([os.path.join(self.root, "tests", "run"), "--no-container", *args], env=self.env, timeout=60)

    def failed(self):
        with open(os.path.join(self.out, "failed.txt")) as f:
            return f.read().splitlines()

    def ran(self):
        p = os.path.join(self.out, "ran.txt")
        if not os.path.exists(p):
            return []
        with open(p) as f:
            names = f.read().split()
        os.remove(p)
        return sorted(names)

    def fix(self, what="fixed"):
        open(os.path.join(self.out, what), "w").close()

    def test_a_run_keeps_what_failed(self):
        code, out = self.runner("-q")
        self.assertEqual(code, 1, out)
        self.assertEqual(self.failed(), [
            "tests.unit.test_fake.Bad.test_fails",
            "tests.unit.test_fake.Broken",              # (its setUpClass: the whole class again)
            "tests.unit.test_fake.Sub.test_some",       # (a subtest: its whole test again)
        ])

    def test_failed_runs_only_those_and_keeps_what_still_fails(self):
        self.runner()
        self.ran()
        self.fix()
        code, out = self.runner("--failed", "-v")
        self.assertEqual(self.ran(), ["bad", "sub"], out)
        self.assertNotIn("good", out)
        self.assertEqual(code, 1, out)
        self.assertEqual(self.failed(), ["tests.unit.test_fake.Broken"])
        self.fix("fixed-class")
        code, out = self.runner("--failed", "-q")
        self.assertEqual((code, self.ran()), (0, ["inside"]), out)
        self.assertEqual(self.failed(), [], "a run with no failures empties the file")

    def test_tests_run_failed(self):
        code, out = self.slate_run("--tier", "unit", "-q")
        self.assertEqual(code, 1, out)
        self.ran()
        self.fix()
        self.fix("fixed-class")
        code, out = self.slate_run("--failed", "-q")
        self.assertEqual((code, self.ran()), (0, ["bad", "inside", "sub"]), out)
        self.assertEqual(out.strip().splitlines()[-1].split(" (")[0], "PASS 4/4")

    def test_json_too(self):
        self.runner("--json")
        self.assertEqual(len(self.failed()), 3)
        self.fix()
        code, out = self.slate_run("--failed", "--json")
        self.assertIn('"summary"', out.splitlines()[-1])
        self.assertEqual(self.failed(), ["tests.unit.test_fake.Broken"])

    def test_nothing_recorded(self):
        for prepare in (lambda: None, lambda: open(os.path.join(self.out, "failed.txt"), "w").close()):
            prepare()
            code, out = self.slate_run("--failed", "-q")
            self.assertEqual(code, 0, out)
            self.assertEqual(out, "Nothing to run again: the last run had no failures.\n")
            self.assertEqual(self.ran(), [])
