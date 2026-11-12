"""The bar's panels open under their buttons and close again."""
from live import LiveCase

# Each panel, and the setting that puts its button on the bar (None: always there)
PANELS = {
    "control": None, "spaces": "barShowSpaces", "notifications": "barShowNotifications", "session": "barShowPower",
    "volume": "barShowVolume", "wifi": "barShowWifi", "clipboard": "barShowClipboard",
    "screenshot": "barShowScreenshot", "keyboard": "barShowKeyboard", "bluetooth": "barShowBluetooth",
    "battery": "barShowBattery", "gamemode": "barShowGameMode", "calendar": None, "windowmode": "barShowWindowMode",
}


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
