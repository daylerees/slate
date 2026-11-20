"""tests/lib/runner.py --shuffle and --busy (tests/run --shuffle [seed], --busy [n]): its files in
an order of the seed's, each file's own tests still in theirs; busy loops beside the tests,
gone when the run ends. And tests/run keeps --busy to the container and says the seed."""
import os
import subprocess
import sys
import time

import slate
from slate import Case, run

RUNNER = slate.path("tests", "lib", "runner.py")
TESTS_RUN = slate.path("tests", "run")


def runner_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("slate_runner", RUNNER)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, slate.path("tests", "lib"))
    spec.loader.exec_module(mod)
    return mod


class Shuffle(Case):
    def order(self, seed):
        names = []
        for t in runner_module().load_tier("static", None, seed):
            for c in getattr(t, "_tests", [t]):
                n = type(c).__module__ if not hasattr(c, "_tests") else next(iter(c._tests), None).__class__.__module__ if c._tests else None
                if n and n not in names:
                    names.append(n)
        return names

    def test_the_same_seed_the_same_order(self):
        self.assertEqual(self.order(5), self.order(5))

    def test_a_seed_changes_the_order(self):
        plain = self.order(None)
        self.assertEqual(plain, sorted(plain), "without a seed: by name, as always")
        self.assertTrue(any(self.order(s) != plain for s in (1, 2, 3)), "no seed changed the order")


class Busy(Case):
    def test_its_loops_run_and_end_with_it(self):
        """A run with --busy 2: two loops while it runs, none once it's ended."""
        code = ("import sys, time; sys.path.insert(0, %r); sys.argv = ['runner']; import runner\n"
                "runner.busy(2); time.sleep(1.5)\n") % slate.path("tests", "lib")
        p = subprocess.Popen([sys.executable, "-c", code])
        time.sleep(0.8)
        spinning = lambda: subprocess.run(["pgrep", "-f", "-P", str(p.pid), "while True: pass"],
                                          capture_output=True, text=True).stdout.split()
        self.assertEqual(len(spinning()), 2, "the busy loops aren't running")
        kids = spinning()
        p.wait(timeout=10)
        time.sleep(0.3)
        left = [k for k in kids if os.path.exists(f"/proc/{k}")]
        self.assertEqual(left, [], "busy loops outlived the run")


class TestsRun(Case):
    def test_busy_only_in_the_container(self):
        code, out = run([TESTS_RUN, "--busy", "--no-container"], timeout=20)
        self.assertEqual(code, 2)
        self.assertIn("--busy only runs in the container", out)

    def test_bad_values_are_turned_down(self):
        for args in (["--busy", "200"], ["--shuffle", "1x"]):
            with self.subTest(args):
                self.assertEqual(run([TESTS_RUN, *args], timeout=20)[0], 2)
