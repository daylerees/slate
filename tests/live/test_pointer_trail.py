"""Accessibility → Trailing pointer (PointerTrail.qml): dots behind the pointer as it moves,
where it is on its screen. Its place comes from Hyprland's pixels (asked over Hyprland's socket),
so the same test runs at 125% Interface size, where a missing conversion would leave the trail
in the wrong place. It's off in game mode, and a still pointer leaves no trail."""
import atexit
import unittest

from live import LiveCase
from pointer import Pointer
from session import Session, in_container


class PointerTrail(LiveCase):
    scale = 1.0

    def test_a_trail_follows_the_pointer(self):
        self.keep_setting("pointerTrail")
        self.config("pointerTrail", "true")
        self.wait(lambda st: st["pointerTrail"]["on"], "the trail on")
        with Pointer(self.s.env, self.s.width, self.s.height) as p:
            before = self.s.state()["pointerTrail"]["moves"]
            for i in range(10):
                p.move(400 + 20 * i, 300 + 10 * i)
                self.s.settle(0.03)
            st = self.wait(lambda st: st["pointerTrail"]["moves"] > before + 2 and
                           (st["pointerTrail"]["x"], st["pointerTrail"]["y"]) == (round(580 / self.scale), round(390 / self.scale)),
                           "the trail at the pointer")["pointerTrail"]
            self.assertEqual(st["screen"], self.s.state()["focusedScreen"])
            # Still: the trail fades away
            self.wait(lambda st: st["pointerTrail"]["dots"] == 0, "the trail gone once still", timeout=3)

            # Game mode: no trail at all
            self.keep_setting("gameMode")
            self.config("gameMode", "true")
            self.wait(lambda st: not st["pointerTrail"]["on"], "the trail off in game mode")
            moved = self.s.state()["pointerTrail"]["moves"]
            p.move(200, 200)
            self.s.settle(0.5)
            self.assertEqual(self.s.state()["pointerTrail"]["moves"], moved, "still asking where the pointer is in game mode")
            self.config("gameMode", "false")

        self.config("pointerTrail", "false")
        self.wait(lambda st: not st["pointerTrail"]["on"], "the trail off")


class PointerTrailAt125(PointerTrail):
    scale = 1.25

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"uiScale": 1.25})
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()
