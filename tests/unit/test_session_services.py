"""scripts/session-services.sh, run as the Slate session starts: hands Hyprland's environment
to D-Bus (and to systemd where it runs), and, without systemd, starts sound (PipeWire and its
companions), which systemd's user session otherwise does. Never starts a second copy."""
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "session-services.sh")


class SessionServices(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.root = os.path.join(self.h.dir, "root")
        os.makedirs(self.root)
        self.env = dict(self.s.env, PATH=self.s.dir, SLATE_INIT_ROOT=self.root)
        for c in ("dbus-update-activation-environment", "pipewire", "wireplumber", "pipewire-pulse", "id", "sleep"):
            self.s.add(c)
        self.s.add("pgrep", code=1)          # nothing's running

    def go(self):
        code, out = run(["/bin/sh", SCRIPT], env=self.env, timeout=20)
        self.assertEqual(code, 0, out)

    def test_with_systemd(self):
        os.makedirs(os.path.join(self.root, "run", "systemd", "system"))
        self.go()
        self.assertEqual(self.s.calls("dbus-update-activation-environment"), [["--systemd", "--all"]])
        for c in ("pipewire", "wireplumber", "pipewire-pulse"):
            self.assertEqual(self.s.calls(c), [], f"{c} is systemd's to start")

    def test_without_systemd_starts_sound(self):
        self.go()
        self.assertEqual(self.s.calls("dbus-update-activation-environment"), [["--all"]])
        for c in ("pipewire", "wireplumber", "pipewire-pulse"):
            self.assertEqual(len(self.s.calls(c)), 1, c)

    def test_already_running_left_alone(self):
        self.s.add("pgrep", code=0)
        self.go()
        for c in ("pipewire", "wireplumber", "pipewire-pulse"):
            self.assertEqual(self.s.calls(c), [], f"a second {c} was started")

    def test_no_pipewire_installed(self):
        for c in ("pipewire", "wireplumber", "pipewire-pulse"):
            os.remove(os.path.join(self.s.dir, c))
        self.go()
