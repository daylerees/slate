"""Settings → Displays: a change applies straight away and waits to be kept ("Keep these
display settings?", with a countdown that puts things back). The countdown lives in the page,
so leaving the page with the question unanswered has to put things back itself: closing
Settings or choosing another page once left the change applied for good, neither kept nor
undone, which with a mode the screen can't show left no way back."""
from live import LiveCase
from session import OUTPUT

UPSIDE_DOWN = 2        # (Rotation's 180°: the screen keeps its size, so nothing else moves)


class DisplaysCase(LiveCase):
    def transform(self):
        return next(m["transform"] for m in self.s.monitors() if m["name"] == OUTPUT)

    def wait_transform(self, want, what, timeout=8):
        for _ in range(int(timeout / 0.2)):
            if self.transform() == want:
                return
            self.s.settle(0.2)
        self.fail(f"{what}: {OUTPUT}'s transform is {self.transform()}, not {want}")

    def put_back(self):
        """Whatever a failing test left: the screen the right way up, Settings closed."""
        self.ipc("settings", "close")
        if self.transform() != 0:
            self.s.hyprctl("eval", 'hl.monitor({ output = "%s", mode = "%dx%d@60", position = "0x0", scale = 1, transform = 0 })'
                           % (OUTPUT, self.s.width, self.s.height))
            self.wait_transform(0, "putting the screen back after the test")

    def turn_without_keeping(self):
        """The Displays page open, and the screen turned from it: applied, and asking."""
        self.addCleanup(self.put_back)
        self.assertEqual(self.transform(), 0)
        self.ipc("settings", "page", "displays")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "displays", "the Displays page")
        # (the page asks Hyprland for the monitors as it loads: until it has them, there's
        # nothing chosen to change)
        for _ in range(20):
            self.ipc("test", "settingsRotateDisplay", UPSIDE_DOWN)
            self.s.settle(0.3)
            if self.transform() == UPSIDE_DOWN:
                break
        self.wait_transform(UPSIDE_DOWN, "the change to apply")
        # Still on the page, it stays as changed while the countdown runs
        self.s.settle(1.0)
        self.assertEqual(self.transform(), UPSIDE_DOWN, "it went back with the page still open")

    def test_closing_settings_puts_an_unkept_change_back(self):
        self.turn_without_keeping()
        self.ipc("settings", "close")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close")
        # (well inside the 15 seconds the countdown would have taken)
        self.wait_transform(0, "the old settings to come back once Settings closed", timeout=6)

    def test_another_page_puts_an_unkept_change_back(self):
        self.turn_without_keeping()
        self.ipc("settings", "page", "dock")
        self.wait(lambda st: st["settings"]["section"] == "dock", "the Dock page")
        self.wait_transform(0, "the old settings to come back once the page was left", timeout=6)
