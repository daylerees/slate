"""Full-screen and floating parts: the launcher, picker, overview, window switcher, lock
screen preview, screensaver, power confirmation and password prompt."""
from live import LiveCase


class Overlays(LiveCase):
    def test_launcher_search(self):
        self.ipc("launcher", "open")
        self.wait(lambda st: st["launcher"]["open"], "the launcher")
        self.ipc("launcher", "search", "foot")
        st = self.wait(lambda st: st["launcher"]["query"] == "foot", "the search")
        self.assertIn("Foot", st["launcher"]["results"])
        self.ipc("launcher", "search", "zzzz-no-such-app")
        st = self.wait(lambda st: st["launcher"]["query"] == "zzzz-no-such-app")
        self.assertNotIn("Foot", st["launcher"]["results"])
        self.ipc("launcher", "close")
        self.wait(lambda st: not st["launcher"]["open"], "the launcher to close")

    def test_launcher_calculator(self):
        self.ipc("launcher", "open")
        self.ipc("launcher", "search", "2+3*4")
        self.wait(lambda st: st["launcher"]["query"] == "2+3*4")
        self.s.settle(0.3)

    def test_picker(self):
        for mode in ("clipboard", "emoji"):
            with self.subTest(mode):
                self.ipc("picker", mode)
                self.wait(lambda st: st["picker"]["open"] and st["picker"]["mode"] == mode, f"the {mode} picker")
                self.ipc("picker", "close")
                self.wait(lambda st: not st["picker"]["open"])

    def test_only_one_at_a_time(self):
        """Opening the launcher closes the picker, and the overview closes the launcher."""
        self.ipc("picker", "emoji")
        self.wait(lambda st: st["picker"]["open"])
        self.ipc("launcher", "open")
        st = self.wait(lambda st: st["launcher"]["open"])
        self.assertFalse(st["picker"]["open"])
        self.ipc("overview", "open")
        st = self.wait(lambda st: st["overview"]["open"])
        self.assertFalse(st["launcher"]["open"])

    def test_overview(self):
        self.ipc("overview", "open")
        self.wait(lambda st: st["overview"]["open"], "the overview")
        self.ipc("overview", "close")
        self.wait(lambda st: not st["overview"]["open"])

    def test_switcher(self):
        """With two windows open, the switcher shows and cancels."""
        before = len(self.s.hyprctl("clients", json_out=True))
        for _ in range(2 - min(before, 2)):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            if len(self.s.hyprctl("clients", json_out=True)) >= 2:
                break
            self.s.settle(0.2)
        self.ipc("switcher", "next")
        self.wait(lambda st: st["switcher"]["open"], "the window switcher")
        self.ipc("switcher", "cancel")
        self.wait(lambda st: not st["switcher"]["open"])

    def test_lock_preview(self):
        for mode in ("lock", "login"):
            with self.subTest(mode):
                self.ipc("lock", "preview", mode)
                self.wait(lambda st: st["lock"]["previewing"], f"the {mode} preview")
                self.ipc("lock", "closePreview")
                st = self.wait(lambda st: not st["lock"]["previewing"])
                self.assertFalse(st["lock"]["locked"])

    def test_screensaver(self):
        self.ipc("screensaver", "start")
        self.wait(lambda st: st["screensaver"]["open"], "the screensaver")
        self.ipc("screensaver", "stop")
        self.wait(lambda st: not st["screensaver"]["open"])

    def test_power_confirm_cancel(self):
        """The confirmation for each session action shows, and cancelling it does nothing."""
        for action in ("logout", "reboot", "shutdown"):
            with self.subTest(action):
                self.ipc("power", "confirm", action)
                self.wait(lambda st: st["power"]["open"], f"the {action} confirmation")
                self.ipc("power", "cancel")
                self.wait(lambda st: not st["power"]["open"])
                self.assertTrue(self.s.alive(), "the session ended")

    def test_polkit_preview(self):
        self.ipc("polkit", "preview")
        self.wait(lambda st: st["polkit"]["open"], "the password prompt")
        self.ipc("polkit", "close")
        self.wait(lambda st: not st["polkit"]["open"])

    def test_notifications(self):
        """A notification arrives and is kept in the history."""
        before = self.s.state()["notifications"]["history"]
        self.s.run(["notify-send", "-a", "Tests", "Hello", "From the test suite"])
        self.wait(lambda st: st["notifications"]["history"] == before + 1, "the notification")
