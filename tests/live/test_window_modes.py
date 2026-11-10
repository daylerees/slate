"""Settings → Windows → Window mode picks Hyprland's layout: dwindle for tiling (and floating,
underneath), master, scrolling or monocle. An unknown mode falls back to dwindle. Super+J and
focusing left/right (binds.lua) do the matching job in each layout."""
from live import LiveCase

LAYOUTS = {"master": "master", "scrolling": "scrolling", "monocle": "monocle", "tiling": "dwindle",
           "nonsense": "dwindle"}


class WindowModes(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()

    def layout(self):
        return self.s.hyprctl("getoption", "general:layout", json_out=True).get("str")

    def wait_layout(self, want):
        for _ in range(40):
            if self.layout() == want:
                return
            self.s.settle(0.1)
        self.fail(f"Hyprland's layout is {self.layout()!r}, not {want!r}")

    def test_each_mode_sets_the_layout(self):
        self.keep_setting("windowMode")
        for mode, layout in LAYOUTS.items():
            with self.subTest(mode):
                self.config("windowMode", mode)
                self.wait_layout(layout)

    def test_layout_comes_back_after_a_hyprland_reload(self):
        """Hyprland's own config says dwindle; Slate puts the chosen layout back after a reload."""
        self.keep_setting("windowMode")
        self.config("windowMode", "scrolling")
        self.wait_layout("scrolling")
        self.s.hyprctl("reload")
        self.s.settle(1.0)
        self.wait_layout("scrolling")

    # ---- the shortcuts in each mode (binds.lua's layoutAction and focusSideways) ----------
    def two_windows(self):
        """At least two windows on the current workspace; returns them."""
        ws = self.s.hyprctl("activeworkspace", json_out=True)["id"]
        mine = lambda: [c for c in self.s.hyprctl("clients", json_out=True) if c["workspace"]["id"] == ws]
        for _ in range(2 - min(len(mine()), 2)):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            if len(mine()) >= 2:
                break
            self.s.settle(0.2)
        self.assertGreaterEqual(len(mine()), 2, "couldn't open two windows")
        self.s.settle(0.5)
        return mine()

    def lua(self, code):
        self.s.hyprctl("dispatch", f"function() {code} end")
        self.s.settle(0.4)

    def active(self):
        return self.s.hyprctl("activewindow", json_out=True).get("address")

    def test_master_super_j_makes_the_main_window(self):
        self.keep_setting("windowMode")
        self.config("windowMode", "master")
        self.wait_layout("master")
        wins = self.two_windows()
        # Focus a window that isn't the main one (the main one is furthest left)
        side = max(wins, key=lambda c: c["at"][0])
        self.lua(f'hl.dispatch(hl.dsp.focus({{ window = "address:{side["address"]}" }}))')
        self.lua("layoutAction()")
        now = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
        left = min((now[c["address"]] for c in wins if c["address"] in now), key=lambda c: c["at"][0])
        self.assertEqual(left["address"], side["address"], "Super+J didn't make it the main window")

    def test_monocle_switches_windows(self):
        self.keep_setting("windowMode")
        self.config("windowMode", "monocle")
        self.wait_layout("monocle")
        self.two_windows()
        first = self.active()
        self.lua("layoutAction()")
        second = self.active()
        self.assertNotEqual(second, first, "Super+J didn't show the next window")
        self.lua('focusSideways("left")')
        self.assertEqual(self.active(), first, "focusing left didn't go back to the previous window")
