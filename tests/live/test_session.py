"""Slate starts in a real (headless) Hyprland session, cleanly, and reports its state."""
import json
import os
import re
import shutil
import signal
import time

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
        self.fail("the wallpaper's colors weren't cached")

    def test_bad_colour_cache_is_ignored(self):
        """A damaged, wrong or missing cache doesn't stop Slate starting (no errors), and is
        written again correctly."""
        bad = {
            "damaged": "{not json",
            "empty": "",
            "another wallpaper": json.dumps({"wallpaper": "/nope.png", "accent": "#ff0000", "tone": "#00ff00"}),
            "not colors": json.dumps({"wallpaper": self.setting("wallpaper"), "accent": "red", "tone": 7}),
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

    def test_reloading_cover(self):
        """The cover `slate restart` puts up ("Reloading Slate", reloading/shell.qml): it shows
        over the screen, and fades away and goes when told the new Slate is ready."""
        cover = os.path.join(self.s.slate_dir, "reloading")
        self.s.run(["sh", "-c", f'setsid qs -n -p "{cover}" >/dev/null 2>&1 </dev/null &'])
        up = lambda: "namespace: slate-reloading" in self.s.hyprctl("layers")
        for _ in range(40):
            if up():
                break
            self.s.settle(0.1)
        self.assertTrue(up(), "the cover didn't come up")
        self.s.settle(0.6)
        self.screenshot("reloading-cover")
        self.s.run(["qs", "-p", cover, "ipc", "call", "cover", "done"])
        for _ in range(40):
            if not up():
                break
            self.s.settle(0.1)
        self.assertFalse(up(), "the cover stayed up after it was told Slate was ready")

    def test_restart_says_when_its_ready(self):
        """Slate writes its ready mark as it loads, which `slate restart` waits for before
        taking the cover down."""
        self.assertTrue(os.path.exists(os.path.join(self.s.h.runtime, "slate-ready")))

    def test_the_cover_has_the_themes_colours(self):
        """Slate notes the theme's colours for the reloading cover, which runs without it."""
        path = os.path.join(self.s.h.cache, "slate", "cover.json")
        for _ in range(40):
            if os.path.exists(path):
                break
            self.s.settle(0.2)
        with open(path, encoding="utf-8") as f:
            c = json.load(f)
        for key in ("background", "text", "dim", "accent", "mark"):
            self.assertRegex(c[key], r"^#[0-9a-f]{6}$", f"{key} isn't a color")



class YourHyprlandFiles(LiveCase):
    def test_a_mistake_makes_one_notification(self):
        """Saving one of your hypr/*.lua files with a mistake in it: Hyprland's config reloads,
        and one notification says there's an error. There used to be two, from two places, with
        different names and pictures, and one of them said all was well. Fixing the file gets
        the one that says so."""
        path = os.path.join(self.s.slate_dir, "hypr", "rules.lua")
        with open(path, encoding="utf-8") as f:
            good = f.read()

        def save(text):
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)

        def put_back():
            with open(path, encoding="utf-8") as f:
                if f.read() != good:
                    save(good)
            self.ipc("notifications", "clear")
        self.addCleanup(put_back)
        history = lambda: self.s.state()["notifications"]["history"]
        before = history()
        save(good + "\nthis is not lua (\n")
        self.wait(lambda st: st["notifications"]["latest"] == "Hyprland settings have errors", "the notice of the mistake")
        # (and nothing more a moment later: the second notification came about half a second on)
        self.assertEqual(self.steady(history, floor=1.5), before + 1, "more than one notification for one mistake")
        self.assertEqual(self.s.state()["notifications"]["latest"], "Hyprland settings have errors")
        save(good)
        self.wait(lambda st: st["notifications"]["latest"] == "Hyprland settings reloaded", "the notice that it's well again")
        self.assertEqual(self.steady(history, floor=1.5), before + 2)


class ComingBack(LiveCase):
    def test_slate_comes_back_after_a_crash(self):
        """A crashed Slate is started again by itself (bin/slate's keeper), within a few seconds,
        and says so once it's back; the log says why, and a test that crashed it would fail."""
        before = self.s.slate_pid()
        ready = os.path.join(self.s.h.runtime, "slate-ready")
        os.kill(int(before), signal.SIGSEGV)
        end = time.monotonic() + 20
        while time.monotonic() < end:
            now = self.s.slate_pid()
            if now and now != before and os.path.exists(ready):
                break
            time.sleep(0.2)
        now = self.s.slate_pid()
        self.assertTrue(now and now != before and os.path.exists(ready), "Slate didn't come back after a crash")
        self.wait(lambda st: st["notifications"]["latest"] == "Slate restarted", "the notice that it's back", timeout=15)
        out = self.s.hyprctl("layers")
        for ns in ("slate-bar", "slate-dock"):
            self.assertIn(f"namespace: {ns}", out)
        errors = self.s.new_log_errors()
        self.assertTrue(any("Slate stopped unexpectedly (signal SEGV" in e for e in errors), errors)
        self.assertFalse([e for e in errors if "Slate stopped unexpectedly" not in e], errors)
        # A report of it, where Quickshell's own would have been (the backtrace only where
        # systemd-coredump has it: not in the container)
        reports = os.path.join(self.s.h.cache, "slate", "crashes")
        end = time.monotonic() + 15
        while time.monotonic() < end and not any(
                f.endswith(f"-{before}.txt") and os.path.getsize(os.path.join(reports, f)) > 0
                for f in (os.listdir(reports) if os.path.isdir(reports) else ())):
            time.sleep(0.3)
        report = next((os.path.join(reports, f) for f in os.listdir(reports) if f.endswith(f"-{before}.txt")), None) \
            if os.path.isdir(reports) else None
        self.assertTrue(report, "no crash report")
        with open(report) as f:
            self.assertIn("Slate stopped unexpectedly: signal SEGV", f.read())
        self.s.save_logs()
        self.assertTrue(os.path.isdir(os.path.join(self.s.out, "slate-crashes")))
        self.ipc("notifications", "clear")
