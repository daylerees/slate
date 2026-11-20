"""A screen dropping off and coming back, as many DisplayPort monitors do going into standby:
for a second or so there's no screen at all, then the same one again. Everything Slate shows
has to come back on it without a restart. The menu bar, the dock and the notifications are
single windows that follow a screen (not one per screen, like the wallpaper), and once stayed on
the stand-in screen Qt makes while there's none, leaving only the wallpaper and the corners.
A session of its own, since taking its screen away would upset the shared one."""
import atexit
import unittest

from live import LiveCase
from session import Session, OUTPUT, in_container

# What has to be back on the screen afterwards (the panels' window and the notifications' are
# made only when a panel opens or a notification shows)
LAYERS = ("slate-wallpaper", "slate-bar", "slate-dock")


class ScreenStandby(LiveCase):
    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session()
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def on_screen(self):
        """Slate's kinds of window Hyprland has on the test screen."""
        out = set()
        for mon, v in self.s.hyprctl("layers", json_out=True).items():
            if mon != OUTPUT:
                continue
            for level in v.get("levels", {}).values():
                out |= {l.get("namespace") for l in level}
        return out

    def standby(self, away=1.5):
        """The screen gone, then back, as a monitor going into standby does."""
        self.s.hyprctl("output", "remove", OUTPUT)
        self.s._until(lambda: OUTPUT not in {m["name"] for m in self.s.monitors()}, 10, f"{OUTPUT} to go")
        self.s.settle(away)
        self.s.hyprctl("output", "create", "headless", OUTPUT)
        self.s._until(lambda: OUTPUT in {m["name"] for m in self.s.monitors()}, 10, f"{OUTPUT} to come back")

    def wait_back(self, what):
        got = set()
        for _ in range(50):
            got = self.on_screen()
            if set(LAYERS) <= got:
                return
            self.s.settle(0.2)
        every = {mon: sorted({l.get("namespace") for lv in v.get("levels", {}).values() for l in lv})
                 for mon, v in self.s.hyprctl("layers", json_out=True).items()}
        self.fail(f"{what}: missing {sorted(set(LAYERS) - got)} (Hyprland's layers: {every})")

    def test_everything_comes_back(self):
        self.wait_back("before")
        self.standby()
        self.wait_back("after the screen came back")
        st = self.s.state()
        self.assertEqual([b["screen"] for b in st["bars"]], [OUTPUT], "one bar, on the screen")

    def test_again_and_again(self):
        """It does it every time it sleeps, sometimes twice in a row (seen: two drops two
        seconds apart)."""
        for i in range(3):
            self.standby(away=0.6)
            self.wait_back(f"after standby {i + 1}")
