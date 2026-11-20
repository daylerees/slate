"""bin/slate-factory-reset's turning off of unlocking without the password: with Slate's own PAM
service there (/etc/pam.d/slate-lock; a scratch file here), it asks to take it away (slate-system
--root slate-unlock remove, your password) before Slate stops, since Slate is what asks; without
one it asks nothing; turned down, it says so once Slate's back. Run from a scratch Slate folder
whose slate and slate-system are stand-ins writing to one log, so their order shows."""
import os
import shutil

import slate
from slate import Case, run
from stubs import Stubs


class FactoryResetUnlock(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.dir = os.path.join(self.h.dir, "slate")
        for d in ("bin", "scripts", "assets/icon"):
            os.makedirs(os.path.join(self.dir, d))
        self.unlock_file = os.path.join(self.h.dir, "pam.d", "slate-lock")
        os.makedirs(os.path.dirname(self.unlock_file))
        src = slate.read("shell", "bin", "slate-factory-reset")
        self.assertIn("/etc/pam.d/slate-lock", src)
        self.script = os.path.join(self.dir, "bin", "slate-factory-reset")
        with open(self.script, "w") as f:
            f.write(src.replace("/etc/pam.d/slate-lock", self.unlock_file).replace("sleep 6;", "sleep 0;"))
        os.chmod(self.script, 0o755)
        self.log = os.path.join(self.h.dir, "steps")
        for name, body in (("bin/slate", f'echo "slate $*" >> {self.log}'),
                           ("bin/slate-system", f'echo "slate-system $*" >> {self.log}; exit ${{STUB_REFUSE:-0}}'),
                           ("scripts/user-files.sh", "exit 0")):
            p = os.path.join(self.dir, name)
            with open(p, "w") as f:
                f.write("#!/bin/sh\n" + body + "\n")
            os.chmod(p, 0o755)
        with open(os.path.join(self.dir, "scripts", "apply-theme.py"), "w") as f:
            f.write("")
        self.s.add("hyprctl", stdout="")
        self.s.add("notify-send", stdout="")

    def reset(self, refuse=False):
        code, out = run([self.script], env=dict(self.s.env, STUB_REFUSE="1" if refuse else "0"), timeout=30)
        self.assertEqual(code, 0, out)
        with open(self.log) as f:
            return f.read().splitlines()

    def test_turned_off_before_slate_stops(self):
        open(self.unlock_file, "w").close()
        steps = self.reset()
        self.assertEqual(steps[:2], ["slate-system --root slate-unlock remove", "slate stop"], steps)
        self.assertEqual(self.s.calls("notify-send"), [])

    def test_nothing_asked_without_one(self):
        steps = self.reset()
        self.assertNotIn("slate-system --root slate-unlock remove", steps)

    def test_turned_down_says_so(self):
        open(self.unlock_file, "w").close()
        self.reset(refuse=True)
        for _ in range(50):
            if self.s.calls("notify-send"):
                break
            import time
            time.sleep(0.1)
        said = " ".join(self.s.calls("notify-send")[0])
        self.assertIn("Unlocking without your password is still on", said)
        self.assertIn("Settings → Security", said)
