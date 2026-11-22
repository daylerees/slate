"""scripts/session.sh: leaving the session (log out, restart, shut down). With "reopen"
(Settings → Startup Apps → Your apps from last time: Ask or Always) the open apps are kept first
for the next login, whichever way you leave; without it (Never) any kept earlier are forgotten.
It used to keep them only on a restart. Nothing here reaches the real session: spaces.py,
slate-init and hyprctl are stand-ins."""
import os
import shutil

import slate
from slate import Case, run
from stubs import Stubs

SPACES = """#!/usr/bin/env python3
import sys
with open(%r, "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
"""


class LeavingKeepsYourApps(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("uwsm", missing=True)
        self.s.add("pw-play")
        self.s.add("hyprctl")
        root = os.path.join(self.h.dir, "slate")
        os.makedirs(os.path.join(root, "scripts"))
        os.makedirs(os.path.join(root, "bin"))
        self.script = os.path.join(root, "scripts", "session.sh")
        shutil.copy(slate.path("shell", "scripts", "session.sh"), self.script)
        self.said = os.path.join(self.h.dir, "spaces-said")
        with open(os.path.join(root, "scripts", "spaces.py"), "w") as f:
            f.write(SPACES % self.said)
        init = os.path.join(root, "bin", "slate-init")
        with open(init, "w") as f:
            f.write("#!/bin/sh\necho \"slate-init $*\" >> %s\n" % self.said)
        os.chmod(init, 0o755)

    def leave(self, *args):
        if os.path.exists(self.said):
            os.remove(self.said)
        code, out = run(["/bin/sh", self.script, *args], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        with open(self.said) as f:
            return f.read().split("\n")[0]

    def test_each_way_out(self):
        for action in ("logout", "reboot", "shutdown"):
            with self.subTest(action):
                self.assertEqual(self.leave(action, "0", "reopen"), "session-save")
                self.assertEqual(self.leave(action, "0"), "session-forget", "Never still kept them")

    def test_then_it_goes(self):
        self.leave("reboot", "0", "reopen")
        with open(self.said) as f:
            self.assertEqual(f.read().split("\n")[1], "slate-init reboot")
        self.leave("logout", "0", "reopen")
        self.assertEqual(self.s.calls("hyprctl"), [["dispatch", "hl.dsp.exit()"]])
