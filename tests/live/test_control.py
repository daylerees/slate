"""The control centre's quick switches (Config.controlSwitches, Settings → Control Centre): the
panel always has eight, yours in your order; a switch whose hardware is missing gives up its
place; and pressing each does what it says, and back. Pressed through the test hook (the session
has no pointer); switches that need radios, speakers or a battery are left to real hardware."""
import json

from live import LiveCase


class ControlSwitches(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("test", "controlSwitches", ""))
        self.addCleanup(lambda: self.ipc("test", "switchMissing", ""))

    def control(self):
        return self.s.state()["control"]

    def order(self, ids):
        self.ipc("test", "controlSwitches", ",".join(ids))
        self.s.settle(0.3)

    def test_always_eight_in_your_order(self):
        self.order(["glass", "light", "glass", "no-such-switch"])
        got = self.control()["switches"]
        self.assertEqual(len(got), 8, got)
        self.assertEqual(got[:2], ["glass", "light"], "your order first")
        self.assertEqual(len(set(got)), 8, "a switch twice")
        self.assertNotIn("no-such-switch", got)
        self.order([])
        self.assertEqual(len(self.control()["switches"]), 8, "with none chosen, the default eight")

    def test_missing_hardware_gives_up_its_place(self):
        self.order(["wifi", "glass"])
        self.assertIn("wifi", self.control()["switches"])
        self.ipc("test", "switchMissing", "wifi")
        self.steady(self.control, floor=0.3)
        got = self.control()["switches"]
        self.assertNotIn("wifi", got)
        self.assertEqual(len(got), 8, "its place wasn't filled")
        self.assertEqual(got[0], "glass")
        self.ipc("test", "switchMissing", "")
        self.steady(self.control, floor=0.3)
        self.assertEqual(self.control()["switches"][0], "wifi", "it didn't get its place back")

    def test_laid_out_without_overlaps(self):
        rects = self.control()["rects"]
        self.assertEqual(len(rects), 8)
        for i, (x, y, w, h) in enumerate(rects):
            self.assertTrue(x >= 0 and y >= 0 and x + w <= 200.5 and y + h <= 300.5, f"switch {i} outside the column: {rects[i]}")
            for j in range(i):
                x2, y2, w2, h2 = rects[j]
                self.assertFalse(x < x2 + w2 and x2 < x + w and y < y2 + h2 and y2 < y + h, f"switches {j} and {i} overlap")

    # ---- pressing each ------------------------------------------------------------------------
    def press(self, sid):
        self.ipc("test", "pressSwitch", sid)
        self.s.settle(0.4)

    def open_panel(self):
        """Open (bar panel toggles: close it first if it's open)."""
        if self.s.state()["popout"] == "control":
            return
        self.ipc("popout", "close")
        self.wait(lambda st: st["popout"] == "")
        self.ipc("bar", "panel", "control")
        self.wait(lambda st: st["popout"] == "control", "the control centre")
        self.s.settle(0.3)

    def check_switch(self, sid, read, settings=()):
        for key in settings:
            self.keep_setting(key)
        self.order([sid])
        self.open_panel()
        before = read()
        self.press(sid)
        self.assertNotEqual(read(), before, f"pressing {sid} changed nothing")
        self.open_panel()                  # (some close it as they're pressed)
        self.press(sid)
        self.assertEqual(read(), before, f"pressing {sid} again didn't put it back")

    def test_each_switch(self):
        self.addCleanup(lambda: self.ipc("popout", "close"))
        cases = {
            "caffeine": (lambda: self.control()["caffeine"], ()),
            "night": (lambda: self.setting("nightLight"), ("nightLight",)),
            "airplane": (lambda: self.setting("airplaneMode"), ("airplaneMode", "airplaneRestore")),
            "gamemode": (lambda: self.setting("gameMode"), ("gameMode",)),
            "light": (lambda: self.setting("lightMode"), ("lightMode", "themeMode")),
            "glass": (lambda: self.setting("glass"), ("glass",)),
            "dockhide": (lambda: self.setting("dockAutoHide"), ("dockAutoHide",)),
            "barhide": (lambda: self.setting("barAutoHide"), ("barAutoHide",)),
            "clipboard": (lambda: self.setting("clipboardHistory"), ("clipboardHistory",)),
            "dnd": (lambda: self.ipc("notifications", "dndGet"), ()),
        }
        for sid, (read, settings) in cases.items():
            with self.subTest(sid):
                self.check_switch(sid, read, settings)


class AirplaneMode(LiveCase):
    """slate ipc call airplane on/off: the setting follows (the tests' computer has no radios,
    so what's switched off and back needs real hardware)."""
    def test_on_and_off(self):
        self.keep_setting("airplaneMode")
        self.keep_setting("airplaneRestore")
        for want in ("on", "off"):
            with self.subTest(want):
                self.ipc("airplane", want)
                for _ in range(30):
                    if self.setting("airplaneMode") == ("true" if want == "on" else "false"):
                        break
                    self.s.settle(0.1)
                self.assertEqual(self.setting("airplaneMode"), "true" if want == "on" else "false")
