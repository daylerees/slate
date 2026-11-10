"""scripts/screenshot.sh: choosing an area. Pressing Print again while the chooser is still
open used to start another on top of it, each one dimming the screen further (a bug). Only
one chooser may be open; once it's done, the next screenshot starts as usual."""
import os
import subprocess
import time

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "screenshot.sh")

# A chooser that stays open a while (as if you were still deciding), then gives an area
SLURP = """#!/bin/sh
echo opened >> "%s"
sleep "${STUB_SLURP_SECONDS:-0}"
echo "10,10 100x80"
"""


class OneChooser(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        slate.need("flock")
        self.s = Stubs(self.h)
        self.opened = os.path.join(self.h.dir, "slurp-opened")
        p = os.path.join(self.s.dir, "slurp")
        with open(p, "w") as f:
            f.write(SLURP % self.opened)
        os.chmod(p, 0o755)
        self.s.add("grim")
        self.s.add("wl-copy")
        self.s.add("notify-send")
        self.s.add("hyprctl", stdout="[]")
        self.s.add("hyprpicker", missing=True)        # (no freezing: nothing to freeze here)
        self.s.add("swash", missing=True)
        self.env = self.s.env

    def choosers(self):
        if not os.path.exists(self.opened):
            return 0
        with open(self.opened) as f:
            return len(f.read().split())

    def test_second_press_does_not_open_another(self):
        first = subprocess.Popen(["/bin/sh", SCRIPT, "region"], env=dict(self.env, STUB_SLURP_SECONDS="2"),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(first.kill)
        for _ in range(40):
            if self.choosers() == 1:
                break
            time.sleep(0.05)
        self.assertEqual(self.choosers(), 1, "the chooser never opened")
        for _ in range(3):
            code, out = run(["/bin/sh", SCRIPT, "region"], env=self.env, timeout=10)
            self.assertEqual(code, 0, out)
        self.assertEqual(self.choosers(), 1, "pressing Print again opened another chooser")
        self.assertEqual(self.s.calls("grim"), [], "a second screenshot was taken")
        self.assertEqual(first.wait(timeout=10), 0)
        self.assertEqual(len(self.s.calls("grim")), 1)

    def test_next_screenshot_after_choosing(self):
        """The lock is only for choosing: once the first is saved, another can be taken."""
        for n in (1, 2):
            code, out = run(["/bin/sh", SCRIPT, "region"], env=self.env, timeout=10)
            self.assertEqual(code, 0, out)
            self.assertEqual(self.choosers(), n)
        self.assertEqual(len(self.s.calls("grim")), 2)

    def test_whole_screen_needs_no_chooser(self):
        """Super+Print takes the screen at once, even while a chooser is open."""
        first = subprocess.Popen(["/bin/sh", SCRIPT, "region"], env=dict(self.env, STUB_SLURP_SECONDS="2"),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(first.kill)
        time.sleep(0.5)
        code, out = run(["/bin/sh", SCRIPT, "screen"], env=self.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.s.calls("grim")), 1)
        first.wait(timeout=10)
