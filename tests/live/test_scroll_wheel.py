"""A mouse wheel moves Slate's lists a comfortable distance (SmoothWheel): one notch over a
Settings page goes a quarter of what shows, at least 100 px, and a quick spin goes further
than the same notches turned slowly. One notch used to go 110 px however tall the page, which
felt slow beside a touchpad."""
from live import LiveCase


class ScrollWheel(LiveCase):
    def setUp(self):
        super().setUp()
        self.ipc("settings", "page", "appearance")      # (a long page)
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "appearance", "Appearance")
        self.addCleanup(lambda: self.ipc("settings", "close"))

    def top(self):
        """Back at the top of the page; how tall the view is."""
        self.ipc("test", "settingsWheel", "-60")
        return self.wait(lambda st: st["settings"]["scroll"] == 0, "the page back at its top", timeout=10)["settings"]["viewHeight"]

    def wheel(self, notches):
        """Turn the wheel down quickly this many notches; how far the page went, once it eased there."""
        self.ipc("test", "settingsWheel", str(notches))
        return self.steady(lambda: self.s.state()["settings"]["scroll"])

    def test_one_notch_goes_a_quarter_of_the_view(self):
        height = self.top()
        self.assertGreater(height, 300)
        want = max(100, min(240, height * 0.25))
        moved = self.wheel(1)
        self.assertGreater(moved, 110, "a notch goes no further than it used to")
        self.assertAlmostEqual(moved, want, delta=2)

    def test_a_quick_spin_goes_further(self):
        one = (self.top(), self.wheel(1))[1]
        self.top()
        five = self.wheel(5)
        self.assertGreater(five, 5 * one * 1.4, "quick notches didn't build up")
