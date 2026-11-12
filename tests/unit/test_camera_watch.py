"""scripts/camera-watch.py: says when a camera starts and stops being used, and by what.
Tried on a pretend /dev (SLATE_DEV) holding an ordinary file named like a camera: opening it
is what an app does to a camera, and the kernel tells the watcher the same way."""
import json
import os
import subprocess
import sys
import time

import slate
from slate import Case

SCRIPT = slate.path("shell", "scripts", "camera-watch.py")

# An "app" that holds the pretend camera open for a while
HOLD = "import sys, time\nf = open(sys.argv[1])\ntime.sleep(float(sys.argv[2]))\n"


class CameraWatch(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.dev = os.path.join(self.h.dir, "dev")
        os.makedirs(self.dev)
        self.cam = os.path.join(self.dev, "video0")
        open(self.cam, "w").close()
        self.env = dict(self.h.env, SLATE_DEV=self.dev)
        self.hold = os.path.join(self.h.dir, "hold.py")
        with open(self.hold, "w") as f:
            f.write(HOLD)

    def watcher(self):
        p = subprocess.Popen([sys.executable, SCRIPT], env=self.env, stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.kill)
        self.addCleanup(p.wait)
        return p

    def line(self, p, timeout=5):
        os.set_blocking(p.stdout.fileno(), False)
        end = time.monotonic() + timeout
        buf = ""
        while time.monotonic() < end:
            chunk = p.stdout.readline()
            if chunk:
                return json.loads(chunk)
            time.sleep(0.05)
        self.fail("the watcher said nothing")

    def test_on_and_off(self):
        p = self.watcher()
        self.assertEqual(self.line(p), {"on": False, "apps": []})
        app = subprocess.Popen([sys.executable, self.hold, self.cam, "2"])
        self.addCleanup(app.kill)
        got = self.line(p)
        self.assertTrue(got["on"])
        self.assertEqual(got["apps"], ["Python3"] if "python3" in os.path.basename(sys.executable) else got["apps"])
        app.wait(timeout=10)
        self.assertEqual(self.line(p), {"on": False, "apps": []})

    def test_a_quick_look_is_not_counted(self):
        """The system opening a camera for a moment, to see what it can do, isn't a use."""
        p = self.watcher()
        self.line(p)
        for _ in range(3):
            with open(self.cam):
                pass
        time.sleep(1.0)
        os.set_blocking(p.stdout.fileno(), False)
        self.assertEqual(p.stdout.readline(), "", "a quick open was reported")

    def test_a_camera_plugged_in(self):
        """One that appears while watching is watched too."""
        os.remove(self.cam)
        p = self.watcher()
        self.line(p)
        cam = os.path.join(self.dev, "video2")
        open(cam, "w").close()
        time.sleep(0.6)
        app = subprocess.Popen([sys.executable, self.hold, cam, "1.5"])
        self.addCleanup(app.kill)
        self.assertTrue(self.line(p)["on"])

    def test_ends_with_slate(self):
        """It stops when the process that started it (Slate) stops, with no camera doing anything.
        It used to wait on until it next had something to say, so every restart left one behind
        (and one held the test runner's output open). Bug, 2026-11-12."""
        pidfile = os.path.join(self.h.dir, "pid")
        # A stand-in for Slate: starts the watcher, notes its pid, and goes after a moment
        parent = subprocess.Popen([sys.executable, "-c",
            "import subprocess, sys, time\n"
            f"p = subprocess.Popen([sys.executable, {SCRIPT!r}], stdout=subprocess.DEVNULL)\n"
            f"open({pidfile!r}, 'w').write(str(p.pid))\n"
            "time.sleep(0.8)\n"], env=self.env)
        parent.wait(timeout=10)
        pid = int(open(pidfile).read())
        for _ in range(50):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            with open(f"/proc/{pid}/stat") as f:
                if f.read().split(")")[-1].split()[0] == "Z":     # (gone, not yet reaped)
                    return
            time.sleep(0.1)
        os.kill(pid, 9)
        self.fail("the watcher kept running after the Slate that started it had gone")

    def test_once(self):
        out = subprocess.run([sys.executable, SCRIPT, "--once"], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(json.loads(out.stdout), {"on": False, "apps": []})
