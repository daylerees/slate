"""scripts/force-quit.sh: Super+Escape force quits the app whose window you click. It ran
Hyprland's own `hyprctl kill`, so a click on Settings or Nova killed the process that owns them,
which is Slate itself, taking the whole desktop with it (a bug). Now the windows you can see
become boxes to click (slurp, as when screenshotting a window), and Slate's own are refused:
they're boxes too, so a click on one can't reach the app behind it."""
import json
import os
import shutil
import stat
import subprocess
import time

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "force-quit.sh")

# A chooser that records the boxes it was given and "clicks" the one labeled $STUB_PICK
# (nothing, as Esc, when it's empty)
SLURP = """#!/bin/sh
cat > "%s"
[ -n "${STUB_PICK:-}" ] || { echo "selection cancelled" >&2; exit 1; }
echo "$STUB_PICK"
"""


class PickToForceQuit(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.boxes = os.path.join(self.h.dir, "boxes")
        p = os.path.join(self.s.dir, "slurp")
        with open(p, "w") as f:
            f.write(SLURP % self.boxes)
        os.chmod(p, 0o755)
        self.s.add("notify-send")
        # An app, and a stand-in for Slate (a process named "qs"), each with a window
        self.app = self.process("someapp")
        self.slate = self.process("qs")
        clients = [self.client("0xa1", self.app.pid, 0, 0, 800, 600),
                   self.client("0xb2", self.slate.pid, 100, 100, 400, 300),
                   self.client("0xc3", self.app.pid, 0, 0, 800, 600, workspace="2")]
        monitors = [{"name": "DP-1", "activeWorkspace": {"id": 1, "name": "1"}}]
        self.s.add("hyprctl", by_args={"monitors": json.dumps(monitors), "clients": json.dumps(clients)})

    def process(self, name):
        exe = os.path.join(self.h.dir, name)
        shutil.copy(shutil.which("sleep"), exe)
        os.chmod(exe, os.stat(exe).st_mode | stat.S_IXUSR)
        return self.spawn([exe, "60"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @staticmethod
    def client(address, pid, x, y, w, h, workspace="1"):
        return {"address": address, "pid": pid, "at": [x, y], "size": [w, h], "mapped": True, "hidden": False,
                "workspace": {"id": int(workspace), "name": workspace}}

    def pick(self, label):
        return run([SCRIPT, "--pick"], env=dict(self.s.env, STUB_PICK=label), timeout=10)

    def gone(self, proc):
        for _ in range(40):
            if proc.poll() is not None:
                return True
            time.sleep(0.05)
        return False

    def test_the_windows_you_can_see_are_the_boxes(self):
        self.pick("")
        with open(self.boxes) as f:
            self.assertEqual(f.read().split("\n")[:2], ["0,0 800x600 0xa1", "100,100 400x300 slate"])

    def test_an_app_picked_is_force_quit(self):
        code, out = self.pick("0xa1")
        self.assertEqual(code, 0, out)
        self.assertTrue(self.gone(self.app), "the app wasn't force quit")
        self.assertIsNone(self.slate.poll())

    def test_slates_own_window_is_refused(self):
        code, out = self.pick("slate")
        self.assertEqual(code, 0, out)
        time.sleep(0.3)
        self.assertIsNone(self.slate.poll(), "Slate itself was killed")
        self.assertIsNone(self.app.poll())
        said = self.s.calls("notify-send")
        self.assertTrue(said and "Slate's own windows" in " ".join(said[0]), said)

    def test_esc_changes_nothing(self):
        code, out = self.pick("")
        self.assertEqual(code, 0, out)
        time.sleep(0.3)
        self.assertIsNone(self.app.poll())
        self.assertIsNone(self.slate.poll())
        self.assertEqual(self.s.calls("notify-send"), [])

    def test_without_slurp_it_says_so(self):
        os.remove(os.path.join(self.s.dir, "slurp"))
        self.s.add("slurp", missing=True)
        code, out = self.pick("0xa1")
        self.assertNotEqual(code, 0)
        self.assertIn("slurp", " ".join(self.s.calls("notify-send")[0]))
        self.assertIsNone(self.app.poll())


class Bound(Case):
    def test_super_escape_uses_the_chooser(self):
        src = slate.read("shell", "session", "hypr", "config", "binds.lua")
        self.assertIn('forceQuit  = hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/force-quit.sh --pick")', src)
        self.assertNotIn("hyprctl kill", src.split("forceQuit  =")[1].split("\n")[0])
