"""Two screens side by side: TEST (1440×900) at 0,0 and TEST2 (1280×800) to its right, a
session of its own (Session(second=…)), so every other test keeps its one screen. What Slate
keeps per screen, checked on both: a menu bar on each (the main display's the main one, the
others dimmed while they don't have focus), the bar's panels opening on the screen they were
asked from, the dock, launcher and overview going to the focused screen, each screen's own
workspace, and the main display (Settings → Displays) taking the main bar and the
notifications. Hyprland's side is checked too (`hyprctl layers`: which monitor each of Slate's
windows is really on, and where), and again at 125% Interface size, where a position taken
from Hyprland is easiest to get wrong."""
import atexit
import json
import unittest

from live import LiveCase
from session import Session, OUTPUT, SECOND, in_container
from test_bar import PANELS

SIZES = {OUTPUT: (1440, 900), SECOND: (1280, 800)}
AT = {OUTPUT: (0, 0), SECOND: (1440, 0)}          # in Hyprland's pixels
# The notifications' window reaches a little past its screen's edge: room for the cards'
# shadows (Notifications.qml, shadowPad 18 less a 12 margin), in Slate's units
SHADOW_ROOM = 18


class TwoScreensCase(LiveCase):
    settings = None
    scale = 1

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(second=SIZES[SECOND], settings=cls.settings)
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def setUp(self):
        super().setUp()
        self.focus(OUTPUT)          # each test starts on the first screen

    # ---- helpers --------------------------------------------------------------------------
    def focus(self, name):
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.focus({ monitor = "%s" })) end' % name)
        return self.wait(lambda st: st["focusedScreen"] == name, f"{name} to have focus")

    def go_to_workspace(self, ws):
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = %d })) end" % ws)

    def monitor(self, name):
        return next(m for m in self.s.monitors() if m["name"] == name)

    def layers(self, namespace):
        """Where Hyprland has Slate's windows of this kind: [(monitor, x, y, w, h)]."""
        out = []
        for mon, v in self.s.hyprctl("layers", json_out=True).items():
            for level in v.get("levels", {}).values():
                for l in level:
                    if l.get("namespace") == namespace:
                        out.append((mon, l["x"], l["y"], l["w"], l["h"]))
        return sorted(out)

    def wait_layer(self, namespace, name):
        """The one layer of this kind, once Hyprland has it on that monitor (and only there)."""
        got = []
        for _ in range(40):
            got = self.layers(namespace)
            if [l[0] for l in got] == [name]:
                return got[0]
            self.s.settle(0.15)
        self.fail(f"{namespace} isn't (only) on {name}: {got}")

    def assertInside(self, layer, name, pad=0):
        """The layer is on that monitor and inside it (Hyprland's pixels; `pad` past its edges)."""
        mon, x, y, w, h = layer
        (mx, my), (mw, mh) = AT[name], SIZES[name]
        self.assertEqual(mon, name, f"on {mon}, not {name}")
        self.assertTrue(mx - pad <= x and x + w <= mx + mw + pad and my - pad <= y and y + h <= my + mh + pad,
                        f"{layer} isn't inside {name} ({mx},{my} {mw}×{mh})")

    def bar_on(self, st, name):
        return next(b for b in st["bars"] if b["screen"] == name)

    def open_panel(self, panel, name):
        """`slate ipc call bar panel <panel>` (it goes to the focused screen's bar): open on
        that screen, from that screen's bar, and inside it as far as Hyprland's concerned."""
        self.ipc("bar", "panel", panel)
        st = self.wait(lambda st: st["popout"] == panel and st["popoutScreen"] == name, f"the {panel} panel on {name}")
        self.assertEqual([b["screen"] for b in st["bars"] if b["popoutHere"]], [name])
        width = SIZES[name][0] / self.scale        # (its button's place: from the screen's edge, Slate's units)
        self.assertTrue(0 < st["popoutAnchor"] < width, f"its button at {st['popoutAnchor']}, off a {width} wide screen")
        self.assertInside(self.wait_layer("slate-popout", name), name)
        return st

    def close_panel(self):
        self.ipc("popout", "close")
        self.wait(lambda st: st["popout"] == "", "the panel to close")

    def main_display(self, name):
        """Settings → Displays → Main display (put back after the test)."""
        self.keep_setting("mainDisplay")
        self.config("mainDisplay", name)
        return self.wait(lambda st: st["mainScreen"] == name and len(st["bars"]) == 2
                         and [b["screen"] for b in st["bars"] if b["primary"]] == [name], f"the main bar on {name}")

    def check_hot_corners(self):
        """With the main display on TEST2, what unlocking asks (HotCorners.qml: is the pointer,
        as `hyprctl cursorpos` gives it in Hyprland's pixels, still in this corner?) says yes in
        each of TEST2's corners and no anywhere else. It once took the pointer over the scale
        but TEST2's x as Hyprland has it, so at 125% the pointer resting in the corner it had
        just locked from read as elsewhere, and the corner fired again straight after unlocking."""
        (x, y), (w, h) = AT[SECOND], SIZES[SECOND]
        right, bottom = x + w - 1, y + h - 1        # (the pointer's last pixel on the screen)
        def asked(corner, px, py):
            return self.ipc("test", "hotCorner", corner, px, py) == "true"
        for corner, at in (("topLeft", (x, y)), ("topRight", (right, y)),
                           ("bottomLeft", (x, bottom)), ("bottomRight", (right, bottom))):
            with self.subTest(corner):
                self.assertTrue(asked(corner, *at), f"{at} isn't in TEST2's {corner} corner")
                self.assertTrue(asked(corner, at[0] + (1 if corner.endswith("Left") else -1), at[1]), "a pixel in")
                self.assertFalse(asked(corner, x + w // 2, y + h // 2), "the middle of TEST2 is in a corner")
                self.assertFalse(asked(corner, at[0] + (40 if corner.endswith("Left") else -40), at[1]), "40 px along")
        # TEST's corners aren't the main display's; nor is a point along TEST2's top edge that,
        # divided by the scale, lands on TEST2's x as Qt keeps it
        self.assertFalse(asked("topLeft", 0, 0), "TEST's corner counted as the main display's")
        self.assertFalse(asked("topLeft", round(x * 1.25), y), "a point along the top counted as the corner")


class TwoScreens(TwoScreensCase):
    def test_screens(self):
        """Slate sees both screens where Hyprland put them, and each shows its own workspace."""
        st = self.s.state()
        got = {s["name"]: (s["x"], s["y"], s["width"], s["height"]) for s in st["screens"]}
        self.assertEqual(got, {n: AT[n] + SIZES[n] for n in SIZES})
        self.assertEqual(st["mainScreen"], OUTPUT, "with no main display set, it's the first screen")
        shown = [self.monitor(n)["activeWorkspace"]["id"] for n in SIZES]
        self.assertEqual(len(set(shown)), 2, f"both screens show the same workspace: {shown}")

    def test_a_bar_on_every_screen(self):
        """One bar per screen, as wide as its screen; the main display's is the main one, and
        Hyprland keeps room for each bar on its own monitor. The wallpaper and the rounded
        corners cover each screen."""
        st = self.s.state()
        self.assertEqual(sorted(b["screen"] for b in st["bars"]), sorted(SIZES))
        for name, (w, h) in SIZES.items():
            with self.subTest(name):
                bar = self.bar_on(st, name)
                self.assertEqual(bar["primary"], name == OUTPUT)
                self.assertEqual(bar["width"], w)
                self.assertGreater(self.monitor(name)["reserved"][1], 0, "no room kept for the bar")
        bars = self.layers("slate-bar")
        self.assertEqual([b[0] for b in bars], sorted(SIZES), f"the bars Hyprland has: {bars}")
        for b in bars:
            with self.subTest(b[0]):
                self.assertInside(b, b[0])
                self.assertEqual((b[1], b[2], b[3]), AT[b[0]] + (SIZES[b[0]][0],), "not along the top of its screen")
        for ns in ("slate-wallpaper", "slate-corners"):
            with self.subTest(ns):
                self.assertEqual(self.layers(ns), sorted((n,) + AT[n] + SIZES[n] for n in SIZES))

    def test_focus_dims_the_other_bar_and_moves_the_dock(self):
        """The bar on the screen without focus is dimmed; the dock is on the focused screen."""
        for name in (SECOND, OUTPUT):
            with self.subTest(name):
                other = SECOND if name == OUTPUT else OUTPUT
                self.focus(name)
                self.wait(lambda st: not self.bar_on(st, name)["dimmed"] and self.bar_on(st, other)["dimmed"]
                          and st["dock"]["screen"] == name, f"the dock on {name}, the other bar dimmed")
                dock = self.wait_layer("slate-dock", name)
                self.assertInside(dock, name)
                self.assertEqual(dock[2] + dock[4], AT[name][1] + SIZES[name][1], "the dock isn't at the bottom")

    def test_panels_on_the_second_screen(self):
        """With the main display on the right-hand screen, every bar panel opens there, beside
        its button on that screen's bar (the panels' window moves over from the first screen)."""
        self.main_display(SECOND)
        self.focus(SECOND)
        for panel in PANELS:
            with self.subTest(panel):
                self.open_panel(panel, SECOND)
                self.close_panel()

    def test_panels_from_another_screens_bar(self):
        """A panel asked for from the bar of a screen that isn't the main display opens there;
        asked for again from the other screen's bar, it moves over and stays open."""
        self.focus(SECOND)
        self.open_panel("control", SECOND)
        self.focus(OUTPUT)
        self.open_panel("control", OUTPUT)
        self.close_panel()

    def test_unread_count_on_every_bar(self):
        """Every screen's bar shows the unread count beside its bell."""
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.ipc("notifications", "clear")
        self.wait(lambda st: st["notifications"]["unread"] == 0, "no unread notifications")
        self.s.run(["notify-send", "-a", "Tests", "Hello", "On every bar"])
        self.wait(lambda st: st["notifications"]["unread"] == 1, "the notification")
        self.wait(lambda st: [b["bell"] for b in st["bars"]] == ["1", "1"], "a 1 beside every bell", timeout=4)

    def test_overlays_open_on_the_focused_screen(self):
        """The launcher and the overview open on the focused screen, the overview with every
        workspace (both screens')."""
        for name in (SECOND, OUTPUT):
            with self.subTest(name):
                self.focus(name)
                self.ipc("launcher", "open")
                self.wait(lambda st: st["launcher"]["open"] and st["launcher"]["screen"] == name, f"the launcher on {name}")
                self.assertInside(self.wait_layer("slate-launcher", name), name)
                self.ipc("launcher", "close")
                self.wait(lambda st: not st["launcher"]["open"])
                self.ipc("overview", "open")
                st = self.wait(lambda st: st["overview"]["open"] and st["overview"]["screen"] == name, f"the overview on {name}")
                self.assertInside(self.wait_layer("slate-overview", name), name)
                shown = sorted(self.monitor(n)["activeWorkspace"]["id"] for n in SIZES)
                self.assertTrue(set(shown) <= set(st["overview"]["workspaces"]), f"{shown} not all in {st['overview']['workspaces']}")
                self.ipc("overview", "close")
                self.wait(lambda st: not st["overview"]["open"])

    def test_workspaces_per_screen(self):
        """Going to a new workspace on one screen leaves the other's alone; going to the other
        screen's workspace takes focus (and the dock) there. Every bar's dots show all the
        workspaces, with the marker on the focused one (the bar without focus is dimmed)."""
        first = self.monitor(OUTPUT)["activeWorkspace"]["id"]
        second = self.monitor(SECOND)["activeWorkspace"]["id"]
        self.addCleanup(lambda: (self.focus(SECOND), self.go_to_workspace(second), self.focus(OUTPUT)))

        def dots_right(st):
            ids = sorted(w["id"] for w in self.s.hyprctl("workspaces", json_out=True) if w["id"] > 0)
            focused = next(m["activeWorkspace"]["id"] for m in self.s.monitors() if m["focused"])
            return all(b["dots"]["count"] == len(ids) and b["dots"]["active"] == ids.index(focused) for b in st["bars"])
        self.focus(SECOND)
        new = max(first, second) + 3
        self.go_to_workspace(new)
        self.wait(lambda st: self.monitor(SECOND)["activeWorkspace"]["id"] == new, f"workspace {new} on TEST2")
        self.assertEqual(self.monitor(OUTPUT)["activeWorkspace"]["id"], first, "TEST's workspace changed too")
        self.wait(dots_right, "both bars' dots on the focused workspace")
        # The first screen's workspace, from the second: focus goes over, the dock with it
        self.go_to_workspace(first)
        self.wait(lambda st: st["focusedScreen"] == OUTPUT and st["dock"]["screen"] == OUTPUT, "focus and the dock on TEST")
        self.assertEqual(self.monitor(SECOND)["activeWorkspace"]["id"], new, "TEST2's workspace changed")
        self.wait(dots_right, "both bars' dots on the focused workspace")

    def test_main_display(self):
        """Settings → Displays → Main display: the main bar moves there (one bar per screen
        still), and so do the notifications' pop-ups; back again, the same."""
        self.main_display(SECOND)
        self.assertEqual([b[0] for b in self.layers("slate-bar")], sorted(SIZES))
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.s.run(["notify-send", "-a", "Tests", "-t", "20000", "Hello", "On the main display"])
        self.wait(lambda st: st["notifications"]["toasts"] >= 1, "the pop-up")
        self.assertInside(self.wait_layer("slate-notifications", SECOND), SECOND, pad=SHADOW_ROOM)
        self.ipc("notifications", "clear")
        self.wait(lambda st: st["notifications"]["toasts"] == 0)
        self.main_display(OUTPUT)
        self.assertEqual([b[0] for b in self.layers("slate-bar")], sorted(SIZES))

    def test_hot_corners_on_the_second_screen(self):
        """Hot corners on a main display that isn't at the top left, at 100%."""
        self.main_display(SECOND)
        self.check_hot_corners()


class TwoScreensAt125(TwoScreensCase):
    """The same two screens at 125% Interface size, with the main display on the right-hand
    one: Slate's own units are Hyprland's pixels divided by 1.25, so anything mixing the two
    shows here, most of all on TEST2, which starts 1440 of Hyprland's pixels in."""
    settings = {"uiScale": 1.25, "mainDisplay": SECOND}
    scale = 1.25

    def test_screen_sizes_in_slate_units(self):
        """(Qt keeps each screen's top-left corner as Hyprland has it, 1440,0 for TEST2, and
        only its size in Slate's units: so a screen's x and y can't be mixed with a position
        from Hyprland divided by the scale)"""
        st = self.s.state()
        got = {s["name"]: (s["width"], s["height"]) for s in st["screens"]}
        self.assertEqual(got, {n: (round(w / 1.25), round(h / 1.25)) for n, (w, h) in SIZES.items()})
        self.assertEqual(st["mainScreen"], SECOND)

    def test_hot_corners_on_the_second_screen(self):
        """Hot corners on the main display, TEST2, at 125%."""
        self.check_hot_corners()

    def test_carrying_from_the_pool_to_the_second_screen(self):
        """Arranging the bar on TEST2: a chip pressed in the pool, with the pointer at a place
        `hyprctl cursorpos` gives in Hyprland's pixels, is at TEST2's x as Qt keeps it plus the
        rest over the scale, as the bar counts places on the desktop (Bar.qml: carried). It
        once took the whole position over the scale, 288 short of where the pointer was."""
        (x, y) = AT[SECOND]
        got = json.loads(self.ipc("test", "barPointer", x + 560, y + 20))
        self.assertAlmostEqual(got["x"], x + 560 / 1.25, places=2)
        self.assertAlmostEqual(got["y"], y + 20 / 1.25, places=2)

    def test_bars_dock_and_panels_cover_their_screens(self):
        """Each bar spans its whole monitor; the dock and every panel opened on TEST2 are inside it."""
        bars = self.layers("slate-bar")
        self.assertEqual([b[0] for b in bars], sorted(SIZES))
        for b in bars:
            with self.subTest(b[0]):
                self.assertInside(b, b[0])
                self.assertEqual((b[1], b[3]), (AT[b[0]][0], SIZES[b[0]][0]), "not across its whole screen")
        self.focus(SECOND)
        self.wait(lambda st: st["dock"]["screen"] == SECOND, "the dock on TEST2")
        dock = self.wait_layer("slate-dock", SECOND)
        self.assertInside(dock, SECOND)
        self.assertEqual(dock[2] + dock[4], SIZES[SECOND][1], "the dock isn't at the bottom")
        for panel in PANELS:
            with self.subTest(panel):
                self.open_panel(panel, SECOND)
                self.close_panel()

    def test_bar_label_under_the_main_bar(self):
        """The label off the bar (BarLabel.qml, a window of its own) on the main bar's screen,
        TEST2: just under the bar in Hyprland's pixels too, and on screen in Slate's units."""
        self.addCleanup(lambda: self.ipc("test", "barHover", ""))
        self.ipc("test", "barHover", "clock")
        st = self.wait(lambda st: st["bar"]["label"]["shown"] and st["bar"]["label"]["text"] == "Clock"
                       and st["bar"]["label"]["opacity"] > 0.99, "the clock's label")
        lab, band = st["bar"]["label"], st["bar"]["band"]
        width = SIZES[SECOND][0] / self.scale
        self.assertTrue(0 <= lab["x"] and lab["x"] + lab["w"] <= width, f"{lab} off a {width} wide screen")
        self.assertGreaterEqual(lab["y"], band["y"] + band["h"])
        layer = self.wait_layer("slate-bar-label", SECOND)
        self.assertInside(layer, SECOND)
        self.assertEqual((layer[1], layer[3]), (AT[SECOND][0], SIZES[SECOND][0]), "not along the whole bar")
        self.assertAlmostEqual(layer[2], band["h"] * self.scale, delta=1, msg="not against the bar's edge")

    def test_notifications_on_the_main_display(self):
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.s.run(["notify-send", "-a", "Tests", "-t", "20000", "Hello", "On the main display"])
        self.wait(lambda st: st["notifications"]["toasts"] >= 1, "the pop-up")
        self.assertInside(self.wait_layer("slate-notifications", SECOND), SECOND, pad=SHADOW_ROOM * 1.25)

    def test_overview_on_the_second_screen(self):
        """The overview on TEST2 (its cards shaped from Hyprland's monitor sizes) opens there."""
        self.focus(SECOND)
        self.ipc("overview", "open")
        self.wait(lambda st: st["overview"]["open"] and st["overview"]["screen"] == SECOND, "the overview on TEST2")
        self.assertInside(self.wait_layer("slate-overview", SECOND), SECOND)
        self.ipc("overview", "close")
        self.wait(lambda st: not st["overview"]["open"])
