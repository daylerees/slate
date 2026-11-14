"""The wallpaper switcher (Super+Alt+W, WallpaperSwitcher.qml): a row of the wallpapers, starting
at yours. Moving through it shows each one, with the theme's colours following, without saving
anything or re-applying App theming; Escape puts everything back as it was; Enter keeps the one
chosen, as choosing it in Settings does."""
import os
import time

from PIL import Image

from live import LiveCase

# Three wallpapers in clearly different colours (big enough not to count as small images)
COLOURS = {"a-red.png": (190, 60, 60), "b-green.png": (60, 170, 80), "c-blue.png": (60, 90, 200)}


class WallpaperSwitcher(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("wallpaperFolder", "wallpaperShowSlate", "accentFromWallpaper", "swishVolume"):
            self.keep_setting(key)
        old = self.ipc("wallpaper", "get")
        self.addCleanup(lambda: self.ipc("wallpaper", "set", old))
        self.addCleanup(lambda: self.ipc("wallpaperSwitcher", "cancel"))
        self.folder = self.s.h("Pictures", "switcher")
        os.makedirs(self.folder, exist_ok=True)
        self.paths = []
        for name, rgb in COLOURS.items():
            path = os.path.join(self.folder, name)
            if not os.path.exists(path):
                Image.new("RGB", (1600, 1000), rgb).save(path)
            self.paths.append(path)
        self.config("wallpaperFolder", self.folder)
        self.config("wallpaperShowSlate", "false")
        self.config("accentFromWallpaper", "true")
        self.config("swishVolume", "60")          # (off by default: Settings → Sound)
        self.ipc("test", "sounds")
        self.ipc("wallpaper", "set", self.paths[0])
        # The first one's colours worked out, and App theming given them, before it opens
        self.accent = self.wait(lambda st: st["wallpaperSwitcher"]["shown"] == self.paths[0] and st["wallpaperSwitcher"]["themeApplied"]
                                and st["wallpaperSwitcher"]["accent"] != "#8fb3e8", "the red wallpaper's colours", timeout=12)["wallpaperSwitcher"]["accent"]
        self.s.settle(0.5)
        self.accent = self.s.state()["wallpaperSwitcher"]["accent"]

    def open(self):
        self.ipc("wallpaper", "switcher")
        return self.wait(lambda st: st["wallpaperSwitcher"]["open"] and not st["wallpaperSwitcher"]["listing"]
                         and st["wallpaperSwitcher"]["fade"] == 1, "the wallpaper switcher")["wallpaperSwitcher"]

    def layers(self):
        """Each Slate layer's level and size: {namespace: [(level, w, h), …]}."""
        found = {}
        for mon in self.s.hyprctl("layers", json_out=True).values():
            for level, items in mon["levels"].items():
                for it in items:
                    found.setdefault(it["namespace"], []).append((int(level), it["w"], it["h"]))
        return found

    def until(self, read, check, timeout=10):
        end = time.monotonic() + timeout
        while True:
            now = read()
            if check(now) or time.monotonic() > end:
                return now
            self.s.settle(0.1)

    def test_looks_then_puts_back(self):
        # A window open behind it, which the wallpaper being looked at covers
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.until(lambda: [c for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped") and c.get("class") == "foot"],
                   bool, timeout=20)
        self.addCleanup(self.close_windows)
        ws = self.open()
        self.assertEqual(ws["walls"], self.paths, "not the folder's wallpapers, by name")
        self.assertEqual(ws["selected"], self.paths[0], "didn't start at the wallpaper in use")
        self.assertTrue(ws["switching"])
        # The wallpaper over the windows, filling the screen (top layer), with the bar and dock
        # above it (overlay), seen but taking no clicks, and the row (with the keys) on the overlay
        mon = self.s.state()["screens"][0]
        layers = self.until(self.layers, lambda l: [x[0] for x in l.get("slate-bar", [])] == [3])
        self.assertEqual(layers.get("slate-wallpaper-preview"), [(2, mon["width"], mon["height"])], layers)
        self.assertEqual([x[0] for x in layers.get("slate-wallpaper-switcher", [])], [3], layers)
        self.assertEqual([x[0] for x in layers.get("slate-bar", [])], [3], "the bar is under the switcher")
        self.assertEqual([x[0] for x in layers.get("slate-dock", [])], [3], "the dock is under the switcher")
        self.assertEqual(ws["input"], {"bar": False, "dock": False}, "the bar or dock still takes clicks")

        self.ipc("wallpaperSwitcher", "next")
        st = self.wait(lambda st: st["wallpaperSwitcher"]["shown"] == self.paths[1]
                       and st["wallpaperSwitcher"]["accent"] != self.accent, "the green one, in its colours")
        ws = st["wallpaperSwitcher"]
        self.assertEqual(ws["saved"], self.paths[0], "looking at one saved it")
        self.assertIn("swish-right", st["sounds"][-3:])
        # App theming waits: held back, not given the green one's colours
        ws = self.wait(lambda st: st["wallpaperSwitcher"]["held"] > 0, "App theming to be held back", timeout=5)["wallpaperSwitcher"]
        self.assertFalse(ws["themeApplied"], "App theming was re-applied while only looking")
        # Back past the first, round to the last
        self.ipc("wallpaperSwitcher", "prev")
        self.ipc("wallpaperSwitcher", "prev")
        self.wait(lambda st: st["wallpaperSwitcher"]["shown"] == self.paths[2], "round to the blue one")

        # Escape: everything as it was. (Through the IPC the keys call: a key press from wtype only
        # reaches a window's own keys now and then in the container, the overview's alike)
        self.ipc("wallpaperSwitcher", "cancel")
        st = self.wait(lambda st: not st["wallpaperSwitcher"]["open"] and not st["wallpaperSwitcher"]["switching"], "it to close")
        ws = st["wallpaperSwitcher"]
        self.assertEqual((ws["shown"], ws["saved"]), (self.paths[0], self.paths[0]))
        self.assertEqual(ws["accent"], self.accent, "the theme's colours weren't put back")
        self.assertEqual(self.setting("wallpaper"), self.paths[0])
        self.assertEqual(ws["held"], 0)
        # The windows in sight again, and the bar and dock back where they were, taking clicks
        layers = self.until(self.layers, lambda l: "slate-wallpaper-preview" not in l and "slate-wallpaper-switcher" not in l and [x[0] for x in l.get("slate-bar", [])] == [2])
        self.assertNotIn("slate-wallpaper-preview", layers, "still covering the windows")
        self.assertNotIn("slate-wallpaper-switcher", layers)
        self.assertEqual(([x[0] for x in layers["slate-bar"]], [x[0] for x in layers["slate-dock"]]), ([2], [2]))
        self.assertEqual(self.s.state()["wallpaperSwitcher"]["input"], {"bar": True, "dock": True})
        # Nothing to apply again: App theming already has these colours
        self.s.settle(2.0)
        self.assertTrue(self.s.state()["wallpaperSwitcher"]["themeApplied"])

    def test_enter_keeps_it(self):
        self.open()
        self.ipc("wallpaperSwitcher", "next")
        self.ipc("wallpaperSwitcher", "next")
        self.wait(lambda st: st["wallpaperSwitcher"]["shown"] == self.paths[2], "the blue one")
        self.ipc("wallpaperSwitcher", "keep")
        st = self.wait(lambda st: not st["wallpaperSwitcher"]["open"] and not st["wallpaperSwitcher"]["switching"], "it to close")
        ws = st["wallpaperSwitcher"]
        self.assertEqual((ws["shown"], ws["saved"]), (self.paths[2], self.paths[2]))
        self.assertEqual(self.setting("wallpaper"), self.paths[2])
        self.assertNotEqual(ws["accent"], self.accent)
        # The full update once it's closed: App theming given the blue one's colours
        self.wait(lambda st: st["wallpaperSwitcher"]["themeApplied"] and st["wallpaperSwitcher"]["held"] == 0,
                  "App theming to catch up", timeout=5)

    def test_shortcut_again_moves_on(self):
        """Its shortcut while it's open goes to the next one, as Super+Tab does."""
        self.open()
        self.ipc("wallpaper", "switcher")
        self.wait(lambda st: st["wallpaperSwitcher"]["selected"] == self.paths[1], "the next one")
        self.ipc("wallpaperSwitcher", "cancel")
        self.wait(lambda st: not st["wallpaperSwitcher"]["switching"], "it to close")

    def test_closes_for_the_launcher(self):
        """Only one of the overlays at a time: the launcher opening puts yours back."""
        self.open()
        self.ipc("wallpaperSwitcher", "next")
        self.wait(lambda st: st["wallpaperSwitcher"]["shown"] == self.paths[1], "the green one")
        self.ipc("launcher", "open")
        st = self.wait(lambda st: st["launcher"]["open"] and not st["wallpaperSwitcher"]["open"], "the launcher in its place")
        self.assertEqual(st["wallpaperSwitcher"]["shown"], self.paths[0])
        self.ipc("launcher", "close")
