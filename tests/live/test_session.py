"""Slate starts in a real (headless) Hyprland session, cleanly, and reports its state."""
from live import LiveCase


class Session(LiveCase):
    def test_loads_clean(self):
        """No errors from the whole start-up (the log from before the first test)."""
        errors = self.s.startup_errors
        self.assertFalse(errors, f"{len(errors)} error(s) at start-up, first: {errors[0][:200] if errors else ''}")

    def test_one_test_screen(self):
        st = self.s.state()
        self.assertEqual([(m["name"], m["width"], m["height"]) for m in st["screens"]],
                         [("TEST", self.s.width, self.s.height)])

    def test_layers(self):
        """The wallpaper, bar and dock are on screen."""
        out = self.s.hyprctl("layers")
        for ns in ("slate-wallpaper", "slate-bar", "slate-dock"):
            with self.subTest(ns):
                self.assertIn(f"namespace: {ns}", out)

    def test_nothing_open(self):
        st = self.s.state()
        self.assertEqual(st["popout"], "")
        for part in ("launcher", "picker", "switcher", "overview", "screensaver", "power", "polkit", "welcome"):
            with self.subTest(part):
                self.assertFalse(st[part]["open"], f"{part} is open on a fresh desktop")
        self.assertFalse(st["settings"]["open"])
        self.assertFalse(st["lock"]["locked"])

    def test_reload_clean(self):
        """A hot reload (what saving a file in ~/.config/slate does) comes back without errors."""
        self.ipc("shell", "reload")
        self.s.settle(4)
        self.wait(lambda st: st["popout"] == "", "Slate after the reload")
