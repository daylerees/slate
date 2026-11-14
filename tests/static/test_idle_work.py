"""Background work that has nothing to do doesn't run: the lock and login screens read the Caps
Lock light on key events and slowly, not four times a second, and Private Mode's portal watch
only runs where there's no systemd (where `private-capture.sh keep` does anything)."""
import re
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[2] / "shell"


class IdleWork(unittest.TestCase):
    def test_caps_lock_light_isnt_polled_quickly(self):
        src = (SHELL / "LoginScreen.qml").read_text(encoding="utf-8")
        self.assertNotIn("interval: 250", src, "a quick timer is reading the Caps Lock light again")
        self.assertIn("Keys.onPressed", src, "the password field doesn't read the light when a key goes down")

    def test_private_mode_watch_only_without_systemd(self):
        src = (SHELL / "PrivateMode.qml").read_text(encoding="utf-8")
        self.assertRegex(src, r"running: root\.on && !Config\.testMode && !root\.systemdUser",
                         "the portal watch runs where systemd already holds the portal stopped")
