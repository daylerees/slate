"""Accessibility → Locate the pointer (LocatePointer.qml; Super+Alt+P, slate ipc call pointer
locate): rings round the pointer, on its screen. Its place comes from Hyprland's pixels, so the
same test runs at 125% Interface size, where Slate's units are Hyprland's pixels over 1.25 and a
missing conversion would put the rings in the wrong place."""
import atexit
import unittest

from live import LiveCase
from pointer import Pointer
from session import Session, in_container


class LocatePointer(LiveCase):
    scale = 1.0

    def test_rings_round_the_pointer(self):
        with Pointer(self.s.env, self.s.width, self.s.height) as p:
            p.move(600, 400)
            before = self.s.state()["locatePointer"]["shows"]
            self.ipc("pointer", "locate")
            st = self.wait(lambda st: st["locatePointer"]["shows"] > before, "the rings")["locatePointer"]
        self.assertTrue(st["showing"])
        self.assertEqual(st["screen"], self.s.state()["focusedScreen"])
        self.assertEqual((st["x"], st["y"]), (round(600 / self.scale), round(400 / self.scale)), "not where the pointer is")
        self.wait(lambda st: not st["locatePointer"]["showing"], "gone again", timeout=4)


class LocatePointerAt125(LocatePointer):
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
