"""tests/run --deps latest: once a day locally. Run again the same day, it shows that day's
result (and exits with its code) without running; --fresh, a filter, CI or a new day run it.
A fake docker stands in, so nothing is built or run."""
import os
import time

import slate
from slate import Case, run

RUNNER = slate.path("tests", "run")
DOCKER = """#!/bin/sh
echo "$*" >> "{log}"
case "$1" in
    image) exit 0 ;;
    run) echo "FAIL 9/10 [latest deps]"; exit {code} ;;
esac
"""


class LatestOnceADay(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.bin = os.path.join(self.h.dir, "bin")
        self.out = os.path.join(self.h.dir, "out")
        os.makedirs(self.bin)
        self.log = os.path.join(self.h.dir, "docker.log")
        self.docker(1)
        self.env = dict(self.h.env, PATH=self.bin + ":" + self.h.env["PATH"], SLATE_TEST_OUT=self.out)
        self.env.pop("CI", None)

    def docker(self, code):
        p = os.path.join(self.bin, "docker")
        with open(p, "w") as f:
            f.write(DOCKER.format(log=self.log, code=code))
        os.chmod(p, 0o755)

    def runs(self):
        if not os.path.exists(self.log):
            return 0
        with open(self.log) as f:
            return sum(1 for l in f if l.startswith("run "))

    def latest(self, *args, env=None):
        return run([RUNNER, "--deps", "latest", "--tier", "static", *args], env=env or self.env, timeout=60)

    def test_second_run_the_same_day_shows_the_first(self):
        code, out = self.latest()
        self.assertEqual((code, self.runs()), (1, 1))
        self.assertIn("FAIL 9/10", out)
        code, out = self.latest()
        self.assertEqual(self.runs(), 1, "ran again the same day")
        self.assertEqual(code, 1, "the day's exit code")
        self.assertIn("FAIL 9/10", out)
        self.assertIn("already ran with today's packages", out)

    def test_fresh_runs_again(self):
        self.latest()
        self.docker(0)
        code, _ = self.latest("--fresh")
        self.assertEqual((code, self.runs()), (0, 2))
        code, _ = self.latest()
        self.assertEqual((code, self.runs()), (0, 2), "the fresh result is the day's now")

    def test_a_new_day_runs_again(self):
        self.latest()
        cache = os.path.join(self.out, "latest-static.txt")
        with open(cache) as f:
            lines = f.read().split("\n", 1)
        with open(cache, "w") as f:
            f.write("2000-01-01 1\n" + lines[1])
        self.latest()
        self.assertEqual(self.runs(), 2)

    def test_always_runs(self):
        """A filtered run, CI and the pinned packages aren't kept."""
        self.latest()
        self.latest("--filter", "dock")
        self.latest(env=dict(self.env, CI="true"))
        self.assertEqual(self.runs(), 3)
        run([RUNNER, "--tier", "static"], env=self.env, timeout=60)
        self.assertEqual(self.runs(), 4)

    def test_each_tier_kept_apart(self):
        self.latest()
        run([RUNNER, "--deps", "latest", "--tier", "unit"], env=self.env, timeout=60)
        self.assertEqual(self.runs(), 2)
