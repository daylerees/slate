"""On a small screen (853×480, like a small laptop at a big scale), the panels, Settings and
the full-screen parts still open without errors (the "fits small screens" fixes)."""
import atexit
import unittest

import slate
from live import LiveCase
from session import Session, in_container
from test_bar import PANELS
from test_settings import page_ids


class SmallScreen(LiveCase):
    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        cls.s = Session(width=853, height=480)
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_screen_size(self):
        st = self.s.state()
        self.assertEqual([(m["width"], m["height"]) for m in st["screens"]], [(853, 480)])

    def test_panels(self):
        for name in PANELS:
            with self.subTest(name):
                self.ipc("bar", "panel", name)
                self.wait(lambda st: st["popout"] == name, f"the {name} panel")
                self.ipc("popout", "close")
                self.wait(lambda st: st["popout"] == "")

    def test_settings_pages(self):
        self.ipc("settings", "open")
        self.wait(lambda st: st["settings"]["open"], "Settings")
        for page in page_ids():
            with self.subTest(page):
                self.ipc("settings", "page", page)
                self.wait(lambda st: st["settings"]["section"] == page)
                self.s.settle(0.3)
                errors = self.s.new_log_errors()
                self.assertFalse(errors, errors[0][:200] if errors else "")
        self.ipc("settings", "close")

    def test_overlays(self):
        for target, opener, closer, part in (("launcher", "open", "close", "launcher"), ("picker", "emoji", "close", "picker"),
                                             ("overview", "open", "close", "overview"), ("screensaver", "start", "stop", "screensaver"),
                                             ("polkit", "preview", "close", "polkit")):
            with self.subTest(part):
                self.ipc(target, opener)
                self.wait(lambda st: st[part]["open"], part)
                self.ipc(target, closer)
                self.wait(lambda st: not st[part]["open"])
