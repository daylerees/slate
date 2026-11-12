"""Private Mode's helpers: scripts/private-capture.sh (the desktop portal's screen sharing off,
and back) and bin/slate-private-camera (the camera off for every app, run as root). Nothing
real is stopped: systemctl and pkill are stand-ins, and the camera helper is only run as
yourself, where it must refuse to change anything."""
import os

import slate
from slate import Case, run
from stubs import Stubs

CAPTURE = slate.path("shell", "scripts", "private-capture.sh")
CAMERA = slate.path("shell", "bin", "slate-private-camera")
BACKENDS = ["xdg-desktop-portal-hyprland", "xdg-desktop-portal-wlr"]


class Capture(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("pkill", code=1)

    def systemd(self, there=True):
        self.s.add("systemctl", code=0 if there else 1)

    def test_off_masks_the_portal_backends(self):
        """With systemd: each backend masked (until you log out) and stopped."""
        self.systemd()
        code, out = run(["/bin/sh", CAPTURE, "off"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        masked = [c for c in self.s.calls("systemctl") if "mask" in c]
        self.assertEqual(masked, [["--user", "mask", "--runtime", "--now", b + ".service"] for b in BACKENDS])
        self.assertEqual([c[-1] for c in self.s.calls("pkill")], BACKENDS)

    def test_on_unmasks_them(self):
        self.systemd()
        code, out = run(["/bin/sh", CAPTURE, "on"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        unmasked = [c for c in self.s.calls("systemctl") if "unmask" in c]
        self.assertEqual(unmasked, [["--user", "unmask", "--runtime", b + ".service"] for b in BACKENDS])
        self.assertEqual(self.s.calls("pkill"), [], "turning it back on stopped something")

    def test_keep_without_systemd(self):
        """Without systemd nothing holds a backend stopped, so `keep` stops it again."""
        self.systemd(there=False)
        code, out = run(["/bin/sh", CAPTURE, "keep"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual([c[-1] for c in self.s.calls("pkill")], BACKENDS)
        # (by the whole command line: the names are longer than a process name can be)
        self.assertTrue(all("-f" in c for c in self.s.calls("pkill")))

    def test_keep_with_systemd_leaves_it(self):
        self.systemd()
        run(["/bin/sh", CAPTURE, "keep"], env=self.s.env, timeout=10)
        self.assertEqual(self.s.calls("pkill"), [])

    def test_unknown(self):
        code, out = run(["/bin/sh", CAPTURE, "sideways"], env=self.s.env, timeout=10)
        self.assertEqual(code, 2)
        self.assertIn("usage", out)


class Camera(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        if os.getuid() == 0:
            self.skipTest("run as root: the helper would change the real system")
        self.s = Stubs(self.h)
        self.s.add("udevadm")
        self.s.add("setfacl")

    def test_needs_root(self):
        """As yourself it changes nothing: install, off and on are for pkexec."""
        for what in ("install", "off", "on"):
            with self.subTest(what):
                code, out = run(["/bin/sh", CAMERA, what], env=self.s.env, timeout=10)
                self.assertEqual(code, 1, out)
                self.assertIn("run as root", out)
        self.assertEqual(self.s.calls("udevadm"), [])
        self.assertEqual(self.s.calls("setfacl"), [])

    def test_status(self):
        code, out = run(["/bin/sh", CAMERA, "status"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertIn(out.strip(), ("on", "off"))

    def test_unknown(self):
        code, out = run(["/bin/sh", CAMERA], env=self.s.env, timeout=10)
        self.assertEqual(code, 2)
        self.assertIn("usage", out)

    def test_the_rule_comes_before_seat_access(self):
        """The udev rule has to run before 73-seat-late (which gives the seat its access), and
        live in /run, so a restart always brings the camera back."""
        src = open(CAMERA).read()
        self.assertIn("RULES=/run/udev/rules.d/72-", src)
        self.assertIn('TAG-="uaccess"', src)
        self.assertIn('MODE="0000"', src)

    def test_polkit_rule_only_for_the_installed_copy(self):
        """No password only for the root-owned copy, and only at the computer: never for the
        one in your home folder, which anything you run could change."""
        src = open(CAMERA).read()
        self.assertIn('action.lookup("program") == "$TARGET"', src)
        self.assertIn("subject.local && subject.active", src)
        self.assertIn("TARGET=/usr/local/libexec/", src)
