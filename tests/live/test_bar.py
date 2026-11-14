"""The bar's panels open under their buttons and close again."""
import json
import os
import subprocess

import slate
from live import LiveCase

# Each panel, and the setting that puts its button on the bar (None: always there)
PANELS = {
    "control": None, "spaces": "barShowSpaces", "notifications": "barShowNotifications", "session": "barShowPower",
    "volume": "barShowVolume", "wifi": "barShowWifi", "clipboard": "barShowClipboard",
    "screenshot": "barShowScreenshot", "keyboard": "barShowKeyboard", "bluetooth": "barShowBluetooth",
    "battery": "barShowBattery", "gamemode": "barShowGameMode", "calendar": None, "windowmode": "barShowWindowMode",
}


# The test session's day (FAKE_TIME), as the clock's label says it
DATE = "Monday, 5 January 2026"


class Bar(LiveCase):
    def test_panels_open_and_close(self):
        for name, setting in PANELS.items():
            with self.subTest(name):
                if setting:
                    self.keep_setting(setting)
                    self.config(setting, "true")
                self.ipc("bar", "panel", name)
                self.wait(lambda st: st["popout"] == name, f"the {name} panel to open")
                self.ipc("popout", "close")
                self.wait(lambda st: st["popout"] == "", f"the {name} panel to close")

    def test_one_panel_at_a_time(self):
        self.ipc("bar", "panel", "control")
        self.wait(lambda st: st["popout"] == "control")
        self.ipc("bar", "panel", "calendar")
        self.wait(lambda st: st["popout"] == "calendar", "the calendar to replace the control centre")

    def test_bar_positions(self):
        """The bar moves to each edge and back, staying on screen as a layer."""
        old = self.keep_setting("barPosition")
        for edge in ("bottom", "left", "right", "top"):
            with self.subTest(edge):
                self.config("barPosition", edge)
                self.s.settle(0.8)
                self.wait(lambda st: st["barEdge"] == edge)
                self.assertIn("namespace: slate-bar", self.s.hyprctl("layers"))
        self.config("barPosition", old)

    def test_window_mode_panel(self):
        """The window mode panel (before the workspace dots): a mode for this workspace only;
        picking the default's mode puts it back to following the default."""
        self.keep_setting("windowMode")
        self.config("windowMode", "tiling")
        ws = self.s.hyprctl("activeworkspace", json_out=True)["id"]
        self.addCleanup(lambda: self.ipc("workspacemode", "set", str(ws), ""))
        self.ipc("bar", "panel", "windowmode")
        self.wait(lambda st: st["popout"] == "windowmode", "the window mode panel")
        # (what its rows and tiles do)
        self.ipc("workspacemode", "set", str(ws), "scrolling")
        self.assertEqual(self.ipc("workspacemode", "get", str(ws)), "scrolling")
        self.ipc("workspacemode", "set", str(ws), "tiling")        # the default's mode: follows it again
        self.assertEqual(self.ipc("workspacemode", "get", str(ws)), "")
        self.ipc("popout", "close")


class BarMenu(LiveCase):
    """The bar's right-click menu (DesktopMenu.qml): the keys work it, and its submenus choose."""
    def menu(self):
        return self.s.state()["barMenu"]

    def key(self, *keys):
        for k in keys:
            self.ipc("test", "menuKey", k)
        self.s.settle(0.2)

    def test_keys(self):
        self.addCleanup(lambda: self.ipc("test", "menuKey", "Escape"))
        self.ipc("test", "barMenu", "open")
        self.wait(lambda st: st["barMenu"]["open"], "the bar's menu to open")
        items = self.menu()["items"]
        chooseable = [i for i, x in enumerate(items) if x != "-"]
        self.key("Down")
        self.assertEqual(self.menu()["hot"], chooseable[0], "Down from nothing lights the first item")
        self.key("Down")
        self.assertEqual(self.menu()["hot"], chooseable[1])
        self.assertEqual(items[chooseable[1]], "Position")
        with self.subTest("into a submenu and out"):
            self.key("Right")
            m = self.menu()
            self.assertTrue(m["inSub"] and m["sub"] == chooseable[1] and m["subHot"] == 0, m)
            self.key("Left")
            m = self.menu()
            self.assertFalse(m["inSub"], m)
            self.assertEqual(m["sub"], -1, "Left closes the submenu")
            self.assertTrue(m["open"], "Left leaves the menu open")
        with self.subTest("Home and End, separators skipped"):
            self.key("End")
            self.assertEqual(self.menu()["hot"], chooseable[-1])
            self.key("Up")
            self.assertEqual(self.menu()["hot"], chooseable[-2], "Up skips the separator")
            self.key("Home")
            self.assertEqual(self.menu()["hot"], chooseable[0])
        with self.subTest("Escape closes"):
            self.key("Escape")
            self.wait(lambda st: not st["barMenu"]["open"], "Escape to close the menu")

    def test_submenu_moves_with_its_items(self):
        """Pointing from one item with a submenu to another: the submenu showing changes after a
        moment, and stays beside its own item till then (it moved at once, so the last one's
        items showed beside the next item for a moment: seen by Dayle, 2026-11-12)."""
        self.addCleanup(lambda: self.ipc("test", "menuKey", "Escape"))
        self.ipc("test", "barMenu", "open")
        self.wait(lambda st: st["barMenu"]["open"], "the bar's menu to open")
        items = self.menu()["items"]
        first, second = items.index("Position"), items.index("Clock")
        self.ipc("test", "menuPoint", str(first), "30")
        self.wait(lambda st: st["barMenu"]["sub"] == first, "Position's submenu")
        self.ipc("test", "menuPoint", str(second), "60")
        m = self.menu()
        self.assertEqual(m["sub"], first, "the submenu changed without the wait")
        self.assertEqual(m["subRowY"], 30, "the submenu moved to the next item with the last one's items in it")
        self.wait(lambda st: st["barMenu"]["sub"] == second, "Clock's submenu")
        self.assertEqual(self.menu()["subRowY"], 60, "the submenu didn't move beside its item")

    def test_enter_chooses(self):
        self.keep_setting("barAutoHide")
        self.config("barAutoHide", "false")
        self.ipc("test", "barMenu", "open")
        self.wait(lambda st: st["barMenu"]["open"])
        items = self.menu()["items"]
        self.key(*["Down"] * (items.index("Auto-hide") + 1), "Enter")
        self.wait(lambda st: not st["barMenu"]["open"], "the menu to close once something's chosen")
        self.assertEqual(self.setting("barAutoHide"), "true", "Enter on Auto-hide didn't switch it on")

    def test_position_submenu_moves_the_bar(self):
        self.keep_setting("barPosition")
        self.config("barPosition", "top")
        self.wait(lambda st: st["barEdge"] == "top")
        self.ipc("test", "barMenu", "Position/Bottom")
        self.wait(lambda st: st["barEdge"] == "bottom", "the bar to move to the bottom from its menu's Position")


class WorkspaceDots(LiveCase):
    """The bar's workspace dots (WorkspaceDots.qml): six at most; with more workspaces the row
    scrolls to hold the one in use in the middle, stopping at either end."""
    def setUp(self):
        super().setUp()
        self.close_windows()

    def go(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.s.settle(0.6)

    def dots(self):
        return self.s.state()["bar"]["dots"]

    def test_scrolls_with_lots_of_workspaces(self):
        self.addCleanup(self.close_windows)
        for ws in range(1, 14):
            self.go(ws)
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
            self.s.settle(0.3)
        self.wait(lambda st: st["bar"]["dots"]["count"] >= 13, "thirteen workspaces on the bar", timeout=15)
        for ws in (1, 7, 13):
            with self.subTest(ws):
                self.go(ws)
                self.s.settle(0.6)              # (the row glides)
                d = self.dots()
                self.assertEqual(d["shown"], 6, d)
                # The one in use in the middle (third of six), the row stopping at either end
                # (with "keep an empty workspace" on, there's a spare one after the last)
                first = max(0, min(d["count"] - 6, d["active"] - 2))
                self.assertEqual(d["firstWanted"], first, d)
                if ws == 1:
                    self.assertEqual(first, 0)
                if ws == 7:
                    self.assertEqual(d["active"] - first, 2, "the one in use isn't held in the middle")
                # (the regression: setting `first` once cut its binding, so the row never moved)
                self.assertAlmostEqual(d["first"], first, delta=0.05, msg=d)


class FullDepth(LiveCase):
    """The bar's buttons take the pointer across the bar's whole depth (Bar.qml, Reach): just
    inside the screen's edge and just inside the bar's inner edge, above or below a button, it
    lights and a click opens its panel, at each edge of the screen. Along the bar nothing grows:
    the gaps between containers are still empty bar. (The session has no pointer: a pretend one,
    test barPoint, goes by the same areas the real one does.)"""
    def point(self, x, y, what="hover"):
        return json.loads(self.ipc("test", "barPoint", str(x), str(y), what))

    def tearDown(self):
        self.point(-1, -1, "leave")
        super().tearDown()

    def test_every_edge(self):
        self.keep_setting("barPosition")
        for edge in ("top", "bottom", "left", "right"):
            with self.subTest(edge):
                self.config("barPosition", edge)
                self.wait(lambda st: st["barEdge"] == edge, f"the bar at the {edge}")
                vert = edge in ("left", "right")
                read = lambda: (self.s.state()["bar"]["band"], self.s.state()["bar"]["line"])
                band, line = self.steady(read, floor=0.6)
                # (along the bar, and the two ends across it: a pixel in from each)
                along = lambda t: (t["y"] + t["h"] / 2) if vert else (t["x"] + t["w"] / 2)
                ends = (band["x"] + 1, band["x"] + band["w"] - 1) if vert else (band["y"] + 1, band["y"] + band["h"] - 1)
                at = lambda a, c: (c, a) if vert else (a, c)
                for name in ("clock", "control"):
                    t = line[name]
                    self.assertTrue(t["visible"], f"{name} isn't on the bar")
                    for c in ends:
                        got = self.point(*at(along(t), c))
                        self.assertEqual(got["thing"], name, f"{edge}: {c} across isn't on {name}: {got}")
                        self.assertTrue(got["lit"], f"{edge}: {name} isn't lit with the pointer {c} across")
                        self.assertTrue(self.s.state()["bar"]["line"][name]["lit"])
                    self.point(-1, -1, "leave")
                    self.assertFalse(self.s.state()["bar"]["line"][name]["lit"], f"{name} stayed lit")
                # A click at the screen's edge opens the clock's panel, and one at the inner edge
                # the control centre's
                self.point(*at(along(line["clock"]), ends[0]), "click")
                self.wait(lambda st: st["popout"] == "calendar", f"{edge}: the calendar from a click at the screen's edge")
                self.point(*at(along(line["control"]), ends[1]), "click")
                self.wait(lambda st: st["popout"] == "control", f"{edge}: the control centre from a click at the bar's inner edge")
                self.ipc("popout", "close")
                self.wait(lambda st: st["popout"] == "")
                # The first workspace dot, the same (8 px in from its container's end, 14 across)
                dots = line["workspaces"]
                got = self.point(*at((dots["y"] if vert else dots["x"]) + 8 + 7, ends[0]))
                self.assertEqual((got["thing"], got["dot"], got["lit"]), ("workspaces", 0, True), f"{edge}: the dot at the screen's edge: {got}")
                # Between two containers, and before the first: still empty bar
                shown = sorted((t for t in line.values() if t["visible"] and t["box"] >= 0 and (t["h"] if vert else t["w"]) > 0),
                               key=lambda t: t["y"] if vert else t["x"])
                gaps = [(a, b) for a, b in zip(shown, shown[1:]) if a["box"] != b["box"]]
                self.assertTrue(gaps, "no two containers to look between")
                a, b = gaps[0]
                end_a = (a["y"] + a["h"]) if vert else (a["x"] + a["w"])
                start_b = b["y"] if vert else b["x"]
                for c in ends:
                    got = self.point(*at((end_a + start_b) / 2, c))
                    self.assertEqual(got["thing"], "", f"{edge}: the gap between containers took the pointer: {got}")
                first = shown[0]["y"] if vert else shown[0]["x"]
                got = self.point(*at(first - 3, ends[0]))
                self.assertEqual(got["thing"], "", f"{edge}: the bar's end took the pointer: {got}")


class WorkspaceName(LiveCase):
    """The workspace's name on the bar (off to start with): the focused workspace's own name, or
    "Workspace 3" without one, following a rename and a switch; clicking it opens the window mode
    panel, where it's named."""
    def go(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")

    def shown(self, text, what):
        self.wait(lambda st: st["bar"]["line"]["workspacename"]["visible"] and st["bar"]["line"]["workspacename"]["text"] == text,
                  f"the bar to say {text!r} ({what})")

    def test_follows_the_workspace(self):
        self.keep_setting("barShowWorkspaceName")
        self.wait(lambda st: not st["bar"]["line"]["workspacename"]["visible"], "it to be off the bar to start with")
        ws = self.s.hyprctl("activeworkspace", json_out=True)["id"]
        self.addCleanup(lambda: (self.go(ws), self.ipc("workspacename", "set", str(ws), "")))
        # (put on the bar as Edit layout's pool does)
        self.ipc("test", "arrange", "shown", "workspacename", "true", "")
        self.shown(f"Workspace {ws}", "no name of its own")
        self.ipc("workspacename", "set", str(ws), "Coding")
        self.shown("Coding", "renamed")
        other = ws + 1
        self.go(other)
        self.shown(f"Workspace {other}", "switched to another workspace")
        self.ipc("workspacename", "set", str(other), "Music")
        self.shown("Music", "the other one renamed")
        self.go(ws)
        self.shown("Coding", "switched back")
        # Clicked: the window mode panel, where it's named
        t = self.s.state()["bar"]["line"]["workspacename"]
        got = json.loads(self.ipc("test", "barPoint", str(t["x"] + t["w"] // 2), str(t["y"] + t["h"] // 2), "click"))
        self.ipc("test", "barPoint", "-1", "-1", "leave")
        self.assertEqual(got["thing"], "workspacename", got)
        self.wait(lambda st: st["popout"] == "windowmode", "the window mode panel from a click on the name")
        self.ipc("popout", "close")
        self.ipc("workspacename", "set", str(ws), "")
        self.shown(f"Workspace {ws}", "its name taken away")


class Label(LiveCase):
    """The label just off the bar saying what the pointer's over (BarLabel.qml): Edit layout's
    name for Slate's own things, which workspace a dot is, a tray app's name. It shows after a
    rest, under the thing (beside it on a side bar) and on screen, changes at once going
    straight to the next thing, and never shows while the bar's arranged or a panel's open. A
    click puts it away quickly, and it stays away until the pointer leaves and comes back. (The
    session has no pointer: test barPoint's pretend one goes by the same areas.)"""
    def point(self, x, y, what="hover"):
        return json.loads(self.ipc("test", "barPoint", str(int(x)), str(int(y)), what))

    def label(self):
        return self.s.state()["bar"]["label"]

    def tearDown(self):
        self.point(-1, -1, "leave")
        super().tearDown()

    def centre(self, name):
        t = self.s.state()["bar"]["line"][name]
        self.assertTrue(t["visible"], f"{name} isn't on the bar")
        return t["x"] + t["w"] / 2, t["y"] + t["h"] / 2

    def showing(self, text, what):
        st = self.wait(lambda st: st["bar"]["label"]["shown"] and st["bar"]["label"]["text"] == text
                       and st["bar"]["label"]["opacity"] > 0.99, f"the label to say {text!r} ({what})")
        return st["bar"]["label"]

    def gone(self, what, timeout=8):
        self.wait(lambda st: not st["bar"]["label"]["shown"] and st["bar"]["label"]["opacity"] < 0.01,
                  f"the label to go ({what})", timeout=timeout)

    def at(self, edge):
        self.keep_setting("barPosition")
        self.config("barPosition", edge)
        self.wait(lambda st: st["barEdge"] == edge, f"the bar at the {edge}")
        self.steady(lambda: self.s.state()["bar"]["line"], floor=0.4)

    def test_says_what_it_is_under_it(self):
        self.at("top")
        st = self.s.state()
        band, width = st["bar"]["band"], st["screens"][0]["width"]
        x, y = self.centre("clock")
        self.point(x, y)
        lab = self.showing(DATE, "over the clock")
        # Just under the bar, centred on the clock (or held in from the screen's end), on screen
        self.assertGreaterEqual(lab["y"], band["y"] + band["h"], f"not below the bar: {lab} {band}")
        self.assertLessEqual(lab["y"], band["y"] + band["h"] + 12, f"not just under the bar: {lab} {band}")
        self.assertGreaterEqual(lab["x"], 0, lab)
        self.assertLessEqual(lab["x"] + lab["w"], width, lab)
        self.assertTrue(abs(lab["x"] + lab["w"] / 2 - x) <= 1.5 or lab["x"] + lab["w"] >= width - 10, f"not under the clock ({x}): {lab}")
        # Straight on to the next thing: it changes at once, under that
        cx, cy = self.centre("control")
        self.point(cx, cy)
        lab = self.label()
        self.assertTrue(lab["shown"], "it went, going straight from one thing to the next")
        self.assertEqual(lab["text"], "Control centre")
        self.assertTrue(abs(lab["x"] + lab["w"] / 2 - cx) <= 1.5 or lab["x"] <= 10, f"not under the control centre ({cx}): {lab}")
        # A workspace dot: which workspace it is, as the overview says it
        dots = self.s.state()["bar"]["line"]["workspaces"]
        got = self.point(dots["x"] + 8 + 7, dots["y"] + dots["h"] / 2)
        self.assertEqual((got["thing"], got["dot"]), ("workspaces", 0), got)
        first = min(w["id"] for w in self.s.hyprctl("workspaces", json_out=True) if w["id"] > 0)
        self.assertEqual(self.label()["text"], self.ipc("workspacename", "label", str(first)))
        # Off the bar: gone
        self.point(-1, -1, "leave")
        self.gone("the pointer off the bar")

    def test_says_more_than_a_name(self):
        """The clock says the whole date, as Settings → Region writes dates; a status icon says
        how it is, not only what it is."""
        self.at("top")
        self.addCleanup(lambda: self.ipc("test", "barHover", ""))
        self.ipc("test", "barHover", "clock")
        self.showing(DATE, "the clock's whole date")
        self.keep_setting("dateFormat")
        self.config("dateFormat", "mdy")
        self.showing("Monday, January 5, 2026", "the date as Region writes it")
        self.keep_setting("barShowGameMode")
        self.config("barShowGameMode", "true")
        self.wait(lambda st: st["bar"]["line"]["gamemode"]["visible"], "game mode on the bar")
        self.ipc("test", "barHover", "gamemode")
        self.showing("Game mode: off", "game mode's state")

    def test_beside_a_side_bar(self):
        self.at("left")
        st = self.s.state()
        band, height = st["bar"]["band"], st["screens"][0]["height"]
        x, y = self.centre("clock")
        self.point(x, y)
        lab = self.showing(DATE, "over the clock on a side bar")
        self.assertGreaterEqual(lab["x"], band["x"] + band["w"], f"not beside the bar: {lab} {band}")
        self.assertLessEqual(lab["x"], band["x"] + band["w"] + 12, lab)
        self.assertGreaterEqual(lab["y"], 0, lab)
        self.assertLessEqual(lab["y"] + lab["h"], height, lab)
        self.assertTrue(abs(lab["y"] + lab["h"] / 2 - y) <= 1.5 or lab["y"] + lab["h"] >= height - 10, f"not beside the clock ({y}): {lab}")

    def test_not_while_arranging(self):
        self.at("top")
        self.addCleanup(lambda: self.wait(lambda st: not st["bar"]["arranging"], "arranging to end"))
        self.addCleanup(lambda: self.ipc("bar", "edit", "done"))
        self.ipc("bar", "edit", "start")
        self.wait(lambda st: st["bar"]["arranging"], "arranging")
        self.steady(lambda: self.s.state()["bar"]["line"], floor=0.4)
        self.point(*self.centre("clock"))
        lab = self.steady(self.label, floor=1.0)
        self.assertFalse(lab["shown"], f"a label while the bar's arranged: {lab}")

    def test_not_with_a_panel_open(self):
        self.at("top")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        self.ipc("bar", "panel", "calendar")
        self.wait(lambda st: st["popout"] == "calendar", "the calendar")
        self.point(*self.centre("control"))
        lab = self.steady(self.label, floor=1.0)
        self.assertFalse(lab["shown"], f"a label with a panel open: {lab}")

    def test_a_click_puts_it_away(self):
        self.at("top")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        x, y = self.centre("clock")
        self.point(x, y)
        self.showing(DATE, "over the clock")
        self.point(x, y, "click")
        self.assertFalse(self.label()["shown"], "the label didn't go at the click itself")
        self.gone("clicked", timeout=1)
        self.wait(lambda st: st["popout"] == "calendar", "the calendar from the click")
        lab = self.steady(self.label, floor=1.0)
        self.assertFalse(lab["shown"], f"back with the panel open: {lab}")
        # The panel closed, the pointer still on the clock: still away, till it leaves and comes back
        self.ipc("popout", "close")
        self.wait(lambda st: st["popout"] == "", "the calendar to close")
        lab = self.steady(self.label, floor=1.0)
        self.assertFalse(lab["shown"], f"back without the pointer leaving the clock: {lab}")
        self.point(-1, -1, "leave")
        self.point(x, y)
        self.showing(DATE, "the pointer back on the clock")

    def test_tray_app_name(self):
        self.at("top")
        for key in ("barShowTray", "barTrayCollapsed"):
            self.keep_setting(key)
        self.config("barShowTray", "true")
        self.config("barTrayCollapsed", "false")
        # An app whose tray icon has only a raw id: tidied to a name
        app = subprocess.Popen(["python3", os.path.join(slate.FIXTURES, "live", "fake_tray_app.py"), "chrome_status_icon_1", ""],
                               env=self.s.env, stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: self.wait(lambda st: "chrome_status_icon_1" not in st["tray"], "the pretend app's icon to go", timeout=10))
        self.addCleanup(app.kill)
        self.assertEqual(app.stdout.readline().strip(), "registered")
        self.wait(lambda st: "chrome_status_icon_1" in st["tray"] and st["bar"]["line"]["tray"]["visible"], "the icon in the tray")
        self.steady(lambda: self.s.state()["bar"]["line"], floor=0.4)
        got = self.point(*self.centre("tray"))
        self.assertEqual(got["thing"], "tray", got)
        self.showing("Chrome", "over the tray icon")

    def test_tray_names_tidied(self):
        """What a tray icon is called: its title, then its tooltip's, then its id; a raw id tidied."""
        for (id_, title, tip), want in {
            ("chrome_status_icon_1", "", ""): "Chrome",
            ("steam", "", ""): "Steam",
            ("nm-applet", "", ""): "Nm",
            ("org.kde.kdeconnect", "", ""): "Kdeconnect",
            ("StatusNotifierItem-1234-1", "", ""): "",
            ("telegram-desktop", "", ""): "Telegram desktop",
            ("discord", "Discord", ""): "Discord",
            ("whatever_1", "", "Fake tray app"): "Fake tray app",
            ("whatever_1", "spotify", "Spotify Premium"): "Spotify",
        }.items():
            with self.subTest(id_):
                self.assertEqual(self.ipc("test", "trayName", id_, title, tip), want)
