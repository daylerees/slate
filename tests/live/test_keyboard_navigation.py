"""Accessibility → the menu bar and the dock by keyboard (Super+Alt+B, Super+Alt+D; slate ipc
call keys bar|dock): the bar or the dock takes the keyboard, the arrow keys move along it, Enter
presses what's focused (a panel opened from the bar has the keyboard; Escape closes it and the
bar has it back) and Escape gives the keyboard back.

Keys are typed for real with wtype, each sequence in one run (in the background, watched as it
goes): every wtype run is a new keyboard, and the old one going away takes the keyboard's focus
with it, which a real keyboard never does."""
import shutil
import subprocess

from live import LiveCase


class KeyboardNavigation(LiveCase):
    def type_keys(self, *keys, gap=500):
        """The keys, gap ms apart, in one wtype run (after a moment for its keymap)."""
        args = ["wtype", "-s", "1000"]
        for k in keys:
            args += ["-k", k, "-s", str(gap)]
        p = subprocess.Popen(args, env=self.s.env)
        self.addCleanup(p.kill)
        return p

    def until(self, cond, what, timeout=8):
        """wait(), saying where the keys and the panel were if it doesn't happen."""
        try:
            return self.wait(cond, what, timeout=timeout)
        except AssertionError:
            st = self.s.state()
            self.fail(f"{what}: keys {st['keys']}, panel {st['popout']!r}")

    def setUp(self):
        super().setUp()
        if not shutil.which("wtype"):
            self.skipTest("wtype isn't installed")
        self.addCleanup(lambda: self.ipc("keys", "stop"))

    def test_the_bar_moves_along(self):
        self.ipc("keys", "bar")
        first = self.wait(lambda st: st["keys"]["bar"] and st["keys"]["barFocus"] != "", "the bar's first thing focused")["keys"]["barFocus"]
        self.type_keys("Right", "Right", "Left").wait(timeout=15)
        path = self.wait(lambda st: len(st["keys"]["barPath"]) >= 4, "three moves")["keys"]["barPath"]
        self.assertEqual(path[0], first)
        self.assertEqual(path[1], path[3], f"Left didn't go back: {path}")
        self.assertEqual(len(set(path[:3])), 3, f"Right didn't move along: {path}")

    def test_enter_opens_its_panel_and_escape_comes_back(self):
        self.ipc("keys", "bar")
        first = self.wait(lambda st: st["keys"]["bar"] and st["keys"]["barFocus"] != "", "the bar's first thing focused")["keys"]["barFocus"]
        self.assertEqual(first, "control", "the bar's first stop isn't the control center")
        self.type_keys("Return", "Escape", "Escape", gap=1500)
        self.until(lambda st: st["popout"] == "control" and not st["keys"]["bar"], "Enter to open the control center")
        st = self.until(lambda st: st["popout"] == "" and st["keys"]["bar"], "Escape closes it, back on the bar")
        self.assertEqual(st["keys"]["barFocus"], "control", "not back on what opened it")
        self.until(lambda st: not st["keys"]["bar"], "Escape gives the keyboard back")

    def test_the_dock(self):
        self.ipc("keys", "dock")
        first = self.wait(lambda st: st["keys"]["dock"] and st["keys"]["dockIndex"] >= 0, "the dock's first icon")["keys"]["dockIndex"]
        self.type_keys("Right", "Home", "Escape")
        self.until(lambda st: not st["keys"]["dock"], "Escape gives the keyboard back", timeout=12)
        path = self.s.state()["keys"]["dockPath"]
        self.assertEqual(path[0], first)
        self.assertGreater(path[1], first, f"Right didn't move along: {path}")
        self.assertEqual(path[2], first, f"Home didn't go back to the first: {path}")
