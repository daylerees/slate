"""Case.spawn (tests/lib/slate.py): a process a test starts is stopped when the test ends, with
everything it started. Cleanups that killed only the process left what it had started running:
a stand-in screen recorder kept going on the desktop after a failed run."""
import os
import subprocess
import time
import unittest

from slate import Case


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # (a zombie, waiting for its parent to collect it, is as good as gone)
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().split(")")[-1].split()[0] != "Z"
    except OSError:
        return False


class Spawn(Case):
    def test_what_it_started_goes_too(self):
        inner = unittest.TestCase()          # (a test of its own, to run its cleanups here)
        p = Case.spawn(inner, ["sh", "-c", "sleep 600 & echo $!; wait"], stdout=subprocess.PIPE, text=True)
        child = int(p.stdout.readline())
        self.assertTrue(alive(p.pid) and alive(child))
        inner.doCleanups()
        for _ in range(50):
            if not alive(child):
                break
            time.sleep(0.05)
        self.assertFalse(alive(p.pid), "the process itself was left running")
        self.assertFalse(alive(child), "what it started was left running")

    def test_already_gone_is_fine(self):
        inner = unittest.TestCase()
        p = Case.spawn(inner, ["true"])
        p.wait(timeout=5)
        inner.doCleanups()
