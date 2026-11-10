"""Slate starts in a real (headless) Hyprland session, cleanly, and reports its state."""
import json
import os
import re
import shutil

from live import LiveCase


class Session(LiveCase):
    def test_loads_clean(self):
        """No errors from the whole start-up (the log from before the first test)."""
        errors = self.s.startup_errors
        self.assertFalse(errors, f"{len(errors)} error(s) at start-up, first: {errors[0][:200] if errors else ''}")

    def test_one_test_screen(self):
        st = self.s.state()
        self.assertEqual([(m["name"], m["width"], m["height"]) for m in st["screens"]],
                         [("TEST", self.s.width, self.s.height)])

    def test_layers(self):
        """The wallpaper, bar and dock are on screen."""
        out = self.s.hyprctl("layers")
        for ns in ("slate-wallpaper", "slate-bar", "slate-dock"):
            with self.subTest(ns):
                self.assertIn(f"namespace: {ns}", out)

    def test_nothing_open(self):
        st = self.s.state()
        self.assertEqual(st["popout"], "")
        for part in ("launcher", "picker", "switcher", "overview", "screensaver", "power", "polkit", "welcome"):
            with self.subTest(part):
                self.assertFalse(st[part]["open"], f"{part} is open on a fresh desktop")
        self.assertFalse(st["settings"]["open"])
        self.assertFalse(st["lock"]["locked"])

    # ---- The wallpaper's colours, cached between reloads (Config.qml, loadColourCache) ----
    def colour_cache(self):
        return os.path.join(self.s.h.cache, "slate", "wallpaper-colours.json")

    def good_cache(self):
        """The cache as Slate writes it: for the wallpaper in use, with two colours."""
        try:
            with open(self.colour_cache(), encoding="utf-8") as f:
                c = json.load(f)
        except (OSError, ValueError):
            return None
        hexc = lambda v: isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v)
        if c.get("wallpaper") == self.setting("wallpaper") and hexc(c.get("accent")):
            return c
        return None

    def test_colour_cache_written(self):
        for _ in range(50):
            if self.good_cache():
                return
            self.s.settle(0.2)
        self.fail("the wallpaper's colours weren't cached")

    def test_bad_colour_cache_is_ignored(self):
        """A damaged, wrong or missing cache doesn't stop Slate starting (no errors), and is
        written again correctly."""
        bad = {
            "damaged": "{not json",
            "empty": "",
            "another wallpaper": json.dumps({"wallpaper": "/nope.png", "accent": "#ff0000", "tone": "#00ff00"}),
            "not colours": json.dumps({"wallpaper": self.setting("wallpaper"), "accent": "red", "tone": 7}),
            "missing": None,
        }
        for name, text in bad.items():
            with self.subTest(name):
                path = self.colour_cache()
                if text is None:
                    shutil.rmtree(os.path.dirname(path), ignore_errors=True)
                else:
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(text)
                self.ipc("shell", "reload")
                self.s.settle(3)
                self.wait(lambda st: st["popout"] == "", "Slate after the reload")
                for _ in range(50):
                    if self.good_cache():
                        break
                    self.s.settle(0.2)
                self.assertTrue(self.good_cache(), "the cache wasn't written again")

    def test_reload_clean(self):
        """A hot reload (what saving a file in ~/.config/slate does) comes back without errors."""
        self.ipc("shell", "reload")
        self.s.settle(4)
        self.wait(lambda st: st["popout"] == "", "Slate after the reload")
