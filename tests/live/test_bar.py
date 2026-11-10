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
