"""Every Settings page loads, search lands on its settings, and every setting can be
changed and changed back from the command line (as Settings does) without errors."""
import json
import re

import slate
from live import LiveCase


def page_ids():
    src = slate.read("shell", "SettingsIndex.qml")
    block = src.split("readonly property var pages:")[1].split("\n    ]")[0]
    return re.findall(r"\{\s*id:\s*\"(\w+)\"", block)


def settings_types():
    src = slate.read("shell", "SettingsData.qml")
    return re.findall(r"^\s*property\s+([\w<>]+)\s+(\w+)\s*:", src, re.M)


# Settings that are lists or objects (set as JSON by their pages), or that move things a
# separate test covers
SKIP_ROUNDTRIP = {"themedApps", "startupApps", "barPosition", "dockPosition", "gameMode", "welcomeShown"}


class Settings(LiveCase):
    def test_every_page_loads(self):
        self.ipc("settings", "open")
        self.wait(lambda st: st["settings"]["open"], "Settings to open")
        for page in page_ids():
            with self.subTest(page):
                self.ipc("settings", "page", page)
                self.wait(lambda st: st["settings"]["section"] == page, f"the {page} page")
                self.s.settle(0.4)
                errors = self.s.new_log_errors()
                self.assertFalse(errors, errors[0][:200] if errors else "")
        self.ipc("settings", "close")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close")

    def test_the_sidebar_fits_without_scrolling(self):
        """At the window's usual height (620: SettingsWindow's fitSize), every page in the sidebar
        shows without scrolling: the sidebar has that less its margins. It scrolled by 12 pixels
        until Notifications and Power moved to All Settings (2026-11-19)."""
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "open")
        st = self.wait(lambda st: st["settings"]["open"] and st["settings"]["sidebar"].get("needs"), "Settings to open")
        needs = st["settings"]["sidebar"]["needs"]
        self.assertLessEqual(needs, 620 - 2 * 14, f"the sidebar's pages need {needs} pixels")

    def test_find_lands_on_page(self):
        """settings find <page> <label> (what the launcher's settings search does) opens the
        page for the last setting on each page."""
        code, out = slate.run(["python3", slate.path("shell", "scripts", "settings-index.py"),
                               slate.path("shell", "SettingsWindow.qml")])
        last = {}
        for it in json.loads(out):
            last[it["page"]] = it["label"]
        for page, label in sorted(last.items()):
            with self.subTest(page):
                self.ipc("settings", "find", page, label)
                self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == page,
                          f"{page} → {label}")
        self.ipc("settings", "close")

    def test_page_asked_for_twice_in_a_row_stays(self):
        """Settings opened on one page and straight away asked for another: it stays on the
        second. Showing the window can report "visible" again a moment later (longer on a busy
        machine), and that used to send it back to All Settings."""
        for attempt in range(6):
            with self.subTest(attempt=attempt):
                self.ipc("settings", "close")
                self.wait(lambda st: not st["settings"]["open"], "Settings to close")
                self.ipc("settings", "page", "about")
                self.ipc("settings", "page", "appearance")
                self.s.settle(1.5)
                self.assertEqual(self.s.state()["settings"]["section"], "appearance")
        self.ipc("settings", "close")

    def test_config_roundtrip(self):
        """Each setting changed and put back (config set/get), keeping its type."""
        for typ, key in settings_types():
            if key in SKIP_ROUNDTRIP or typ == "var":
                continue
            with self.subTest(key):
                old = self.setting(key)
                if typ == "bool":
                    self.assertIn(old, ("true", "false"), f"a bool read back as {old!r}")
                    new = "false" if old == "true" else "true"
                elif typ in ("int", "real"):
                    float(old)
                    new = str(int(float(old)) + 1) if typ == "int" else str(round(float(old) + 0.1, 3))
                else:
                    new = old       # strings are choices: set back as they are
                self.ipc("config", "set", key, new)
                got = self.setting(key)
                if typ == "real":
                    self.assertAlmostEqual(float(got), float(new), places=3)
                else:
                    self.assertEqual(got, new)
                self.ipc("config", "set", key, old)
                self.assertEqual(self.setting(key), old, "didn't go back")
                self.s.settle(0.1)
                errors = self.s.new_log_errors()
                self.assertFalse(errors, errors[0][:200] if errors else "")

    def test_back_on_its_page_after_a_reload(self):
        """Open when Slate reloads: Settings comes back on the page it was on (it used to read
        its saved place before that had loaded, and came back on All Settings)."""
        self.ipc("settings", "page", "dock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock")
        self.s.settle(1)                        # (its place is saved a moment after a change)
        self.ipc("shell", "reload")
        self.s.settle(4)
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock", "Settings back on Dock", timeout=10)
        self.ipc("settings", "close")

    def test_built_when_first_wanted(self):
        """Settings, the welcome and the bar's arranging panel aren't built at start: after a
        reload with Settings closed they're not there, and Settings is made by the first thing
        that wants it (here, `settings page`), then opens on that page."""
        self.ipc("settings", "close")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close")
        self.s.settle(1)                        # (so no place is left saved for the reload to reopen)
        self.ipc("shell", "reload")
        self.s.settle(4)
        st = self.wait(lambda st: st["popout"] == "" and st, "Slate after the reload", timeout=10)
        self.assertFalse(st["settings"]["built"], "Settings was built at start")
        self.assertFalse(st["welcome"]["built"], "the welcome was built at start")
        self.assertFalse(st["bar"]["editorBuilt"], "the arranging panel was built at start")
        self.ipc("settings", "close")           # (nothing to close, and no error)
        self.assertFalse(self.s.state()["settings"]["built"], "closing Settings built it")
        self.ipc("settings", "page", "dock")
        self.wait(lambda st: st["settings"]["built"] and st["settings"]["open"] and st["settings"]["section"] == "dock",
                  "Settings built and open on Dock")
        self.ipc("settings", "close")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close")

    def test_welcome_built_while_it_shows(self):
        self.addCleanup(lambda: self.ipc("welcome", "close"))
        self.ipc("welcome", "open")
        self.wait(lambda st: st["welcome"]["open"] and st["welcome"]["built"], "the welcome, built")
        self.ipc("welcome", "close")
        self.wait(lambda st: not st["welcome"]["built"], "the welcome to be let go")


class SettingsWindowGoesWithYou(LiveCase):
    """Settings is pinned (windowrules.lua): open, it goes with you to every workspace, and
    asking for it (Super+Z: settings toggle) brings it to the front when you're elsewhere and
    closes it when you're in it."""

    def client(self):
        for c in self.s.hyprctl("clients", json_out=True):
            if c.get("title") == "Settings" and c.get("mapped"):
                return c
        return None

    def go(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.s._until(lambda: self.s.monitor()["activeWorkspace"]["id"] == ws, 5, f"workspace {ws}")

    def focused(self):
        return (self.s.hyprctl("activewindow", json_out=True) or {}).get("title") == "Settings"

    def test_pinned_and_with_you(self):
        self.go(1)
        self.addCleanup(lambda: self.go(1))
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "open")
        self.wait(lambda st: st["settings"]["open"], "Settings")
        self.s._until(lambda: self.client() is not None, 8, "the Settings window")
        c = self.client()
        self.assertTrue(c["floating"], "Settings isn't floating")
        self.assertTrue(c["pinned"], "Settings isn't pinned")
        self.go(2)
        self.s._until(lambda: self.client()["workspace"]["id"] == 2, 5, "Settings to come along to workspace 2")
        self.assertTrue(self.s.state()["settings"]["open"], "Settings closed going to another workspace")
        # ...and like Nova, it doesn't make the workspace it's on look in use (its dot), nor
        # count there (a new or spare workspace)
        if not self.s.hyprctl("clients", json_out=True) or all(c.get("workspace", {}).get("id") != 2 or c.get("title") == "Settings"
                                                               for c in self.s.hyprctl("clients", json_out=True)):
            self.assertNotIn(2, self.s.state()["bar"]["dots"]["occupied"], "Settings made the workspace it's on look in use")
        # Asked for again when it's open: brought to the front with the keyboard, not closed;
        # asked for when it's the window you're in: closed
        self.ipc("settings", "open")
        self.s._until(lambda: self.focused(), 5, "Settings to have the keyboard")
        self.assertTrue(self.s.state()["settings"]["open"])
        self.ipc("settings", "toggle")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close when you're in it")


class SubPages(LiveCase):
    """Wallpaper and Icons are pages of their own (from Appearance's top): opened by name over
    IPC (the desktop's "Change wallpaper…" and the dock's menu use it), and searchable."""
    def test_open_by_name(self):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        for page in ("wallpaper", "icons"):
            with self.subTest(page):
                self.ipc("settings", "page", page)
                self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == page, f"the {page} page")

    def test_search_fills_the_box(self):
        """slate ipc call settings search: as typing into the search box showing."""
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "search", "dock")
        self.wait(lambda st: st["settings"]["open"], "Settings to open")


class Search(LiveCase):
    """What you'd type finds the setting itself: the result is the real row (or its heading),
    and choosing it scrolls there and lights it up. The curated entries in SettingsIndex.qml
    once drifted from the rows they were for (other names, settings that had gone), leaving
    results that opened the page and stopped at the top."""

    # What's typed → the result it must give: (label, page, whether it has to come first)
    FINDS = {
        "sound effects": ("Sound effects", "sound", True),
        "clicks sound": ("Clicks", "sound", True),
        "volume keys sound": ("Volume keys", "sound", True),
        "dark": ("Theme", "appearance", False),
        "dark mode": ("Theme", "appearance", True),
        "theme presets": ("Preset", "appearance", True),
        "tiling": ("Default window mode", "windows", True),
        "idle": ("When you're away", "lock", False),
        "idle and sleep": ("When you're away", "lock", False),
        "account picture": ("Account", "general", True),
        "alt tab": ("Window switcher (Super+Tab)", "windows", False),
        "workspace overview": ("Workspace overview (Super+Down)", "workspaces", True),
        # Game mode has no row of its own: it's a quick switch, and a button to add to the bar
        "game mode": ("Quick switches", "control", False),
        "gaming": ("Arrange the menu bar", "bar", True),
    }

    def results(self, text):
        """SettingsIndex.search(text), as Settings' search box shows it (once the rows are read)."""
        for _ in range(60):
            out = self.ipc("test", "settingsSearch", text)
            if out:
                return json.loads(out)
            self.s.settle(0.25)
        self.fail("Settings' rows were never read (scripts/settings-index.py)")

    def test_words_find_their_setting(self):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        for text, (label, page, first) in self.FINDS.items():
            with self.subTest(text):
                found = [(r["label"], r["page"]) for r in self.results(text)]
                self.assertIn((label, page), found[:1] if first else found, f'"{text}" found {found}')
                # ...and choosing it goes to it, rather than only to its page
                self.ipc("settings", "find", page, label)
                self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == page
                          and st["settings"]["found"] == label, f"{label} gone to and lit up on {page}")

    def test_gone_settings_are_not_found(self):
        """Results for settings that no longer exist are gone, not left pointing at a page."""
        for text, label in (("sound effects volume", "Sound effects volume"), ("game mode", "Game mode")):
            with self.subTest(text):
                self.assertNotIn(label, [r["label"] for r in self.results(text)])


class RestoreDefaults(LiveCase):
    """A page's Restore defaults (the button by its title), the way you use it: it asks in
    Slate's confirmation window, and yes puts every setting on that page back to how Slate
    starts out, leaving the other pages alone."""

    # Settings on each page to change, and what to change them to. Dock's position goes through
    # its own path (moving the dock), so it's one of them
    CHANGES = {
        "dock": {"dockAutoHide": "false", "dockIconSize": "52", "dockBadges": "false", "dockPosition": "left"},
        "launcher": {"launcherLayout": "grid", "launcherColumns": "4", "launcherFuzzy": "false"},
        # (Scenery quality showed as changed but was missing from the page's list, so Restore
        # defaults neither counted it nor put it back)
        "screensaver": {"screensaverVideoQuality": "1080p", "screensaverClock": "false"},
    }
    # A setting on another page, which a page's Restore defaults must leave as it is
    ELSEWHERE = ("notificationSeconds", "9")

    def open_page(self, page):
        self.ipc("settings", "page", page)
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == page, f"the {page} page")

    def restore(self, page):
        """Press Restore defaults on the page and say yes; returns what the question asked about."""
        self.ipc("test", "settingsRestoreDefaults")
        st = self.wait(lambda st: st["power"]["open"], "the Restore defaults question")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: not st["power"]["open"], "the question to close")
        return self.wait(lambda st: st["settings"]["changed"] == 0, f"{page}'s settings to be back at their defaults")

    def test_restore_defaults(self):
        for page, changes in self.CHANGES.items():
            with self.subTest(page):
                for key in changes:
                    self.keep_setting(key)
                key, value = self.ELSEWHERE
                self.keep_setting(key)
                self.addCleanup(lambda: self.ipc("settings", "close"))

                # From the defaults (another test may have left something changed here)
                self.open_page(page)
                if self.s.state()["settings"]["changed"]:
                    self.restore(page)
                defaults = {k: self.setting(k) for k in changes}
                self.assertTrue(all(defaults[k] != v for k, v in changes.items()),
                                f"a change is the default already: {defaults}")

                for k, v in changes.items():
                    self.config(k, v)
                self.config(key, value)
                self.wait(lambda st: st["settings"]["changed"] == len(changes),
                          f"{len(changes)} settings changed on {page}")

                # No: nothing changes
                self.ipc("test", "settingsRestoreDefaults")
                self.wait(lambda st: st["power"]["open"], "the Restore defaults question")
                self.ipc("test", "answer", "false")
                self.wait(lambda st: not st["power"]["open"], "the question to close")
                self.s.settle(0.3)
                self.assertEqual(self.s.state()["settings"]["changed"], len(changes), "No restored the defaults anyway")

                # Yes: back to the defaults, and the other page's setting stays
                self.restore(page)
                for k in changes:
                    self.assertEqual(self.setting(k), defaults[k], f"{k} didn't go back")
                self.assertEqual(self.setting(key), value, f"{key} (another page) was put back too")


class NeedsAnother(LiveCase):
    """A setting greyed out because another one is off says which one ("Needs … to be on"),
    and its line goes to that setting (SettingRow's needs)."""

    def waiting(self, st):
        return {r["label"]: r["needs"] for r in st["settings"]["waiting"]}

    def test_says_what_it_needs_and_goes_there(self):
        self.keep_setting("accentFromWallpaper")
        self.keep_setting("iconFill")
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.config("accentFromWallpaper", "false")
        self.ipc("settings", "page", "appearance")
        st = self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "appearance"
                       and "Accent boldness" in self.waiting(st), "Accent boldness grayed out on Appearance")
        self.assertEqual(self.waiting(st)["Accent boldness"], "Needs Accent color from wallpaper to be on")
        self.assertNotIn("Accent color", self.waiting(st), "your own accent color grayed out with the wallpaper's off")

        # The other way round: the wallpaper's colour on, your own colour waits instead
        self.config("accentFromWallpaper", "true")
        st = self.wait(lambda st: "Accent color" in self.waiting(st), "Accent color grayed out")
        self.assertEqual(self.waiting(st)["Accent color"], "Needs Accent color from wallpaper to be off")
        self.assertNotIn("Accent boldness", self.waiting(st))

        # Its line leads to what it needs: on the same page...
        self.ipc("test", "settingsFollowNeeds", "Accent color")
        self.wait(lambda st: st["settings"]["section"] == "appearance" and st["settings"]["found"] == "Accent color from wallpaper",
                  "Accent color from wallpaper gone to and lit up")

        # ...and on another (Icons, from its own row)
        self.config("iconFill", "true")
        self.ipc("settings", "page", "icons")
        st = self.wait(lambda st: st["settings"]["section"] == "icons" and "Tiles in the icon's color" in self.waiting(st),
                       "Tiles in the icon's color grayed out on Icons")
        self.assertEqual(self.waiting(st)["Tiles in the icon's color"], "Needs Fill the shape to be off")
        self.ipc("test", "settingsFollowNeeds", "Tiles in the icon's color")
        self.wait(lambda st: st["settings"]["found"] == "Fill the shape", "Fill the shape gone to and lit up")


class TabBetweenBoxes(LiveCase):
    """Tab moves from one text box in Settings to the next, and Shift+Tab back: from the
    search box at the top to the page's own (General's location search), and back again.
    (As Qt moves it for the Tab key: the tests' key presses come from a keyboard that comes and
    goes, which takes the keyboard away from the window each time.)"""
    def focus_is(self, name, what):
        import time
        end = time.monotonic() + 10
        while time.monotonic() < end:
            got = self.s.state()["settings"]["focusedBox"]
            if got == name:
                return
            time.sleep(0.2)
        self.fail(f"{what}: the keyboard was in {got!r}, not {name!r}")

    def test_tab_and_back(self):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "general")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "general", "Settings on General")
        self.ipc("settings", "search", "")          # (the search box takes the keyboard)
        self.focus_is("pageFind", "the search box with the keyboard")
        # Tab on through the page's controls (each one takes the keyboard now: the back button, your
        # picture…) to its own box, then Shift+Tab the same steps back to the search box
        import time
        steps = 0
        while self.s.state()["settings"]["focusedBox"] != "locationSearch":
            self.assertLess(steps, 8, "Tab didn't reach the page's own box")
            self.ipc("test", "settingsTab", "true")
            steps += 1
            time.sleep(0.25)
        self.assertGreater(steps, 0)
        for _ in range(steps):
            self.ipc("test", "settingsTab", "false")
            time.sleep(0.25)
        self.focus_is("pageFind", "Shift+Tab back to the search box, the same steps")


class UpdatesPage(LiveCase):
    """Settings → Updates: where it says there's a new version is where its Update now button
    is, with what's new right under it; while it updates, that row says which step it's on and
    how much has downloaded. (They were far apart: the notice at the top, the button below the
    notes and the apps' updates. Asked for, 2026-11-21.)"""
    NEW = {"latest": "v9.9.9", "newer": True, "status": "idle", "how": "own", "notes": "- Something new",
           "url": "https://github.com/daylerees/slate/releases/tag/v9.9.9", "published": "2026-11-20T10:00:00Z",
           "checked": 1795300000}

    def pretend(self, **st):
        self.ipc("test", "updatesPretend", json.dumps(dict(self.NEW, **st)))

    def page(self, want, what):
        return self.wait(lambda st: st["settings"]["page"] is not None and want(st["settings"]["page"]), what)["settings"]["page"]

    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.addCleanup(lambda: self.ipc("test", "updatesPretend", "{}"))
        self.ipc("settings", "page", "updates")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "updates", "Settings → Updates")

    def test_the_button_is_where_it_says_so(self):
        self.pretend()
        self.page(lambda p: p["update"] and p["notes"], "the new version offered, with its notes")
        # (laid out: the notes are placed a frame or more after they're shown, later on a busy computer)
        p = self.steady(lambda: self.s.state()["settings"]["page"], floor=0.4)
        self.assertEqual(p["label"], "Slate v9.9.9 is available")
        self.assertFalse(p["check"], "Check now beside Update now")
        self.assertTrue(p["rowY"] <= p["buttonY"] < p["rowY"] + p["rowH"],
                        f"Update now isn't on the row that says there's a new version: {p}")
        self.assertGreater(p["notesY"], p["rowY"], "what's new isn't under it")
        self.assertLess(p["notesY"] - (p["rowY"] + p["rowH"]), 200, f"what's new is far below it: {p}")

    def test_says_how_the_update_is_going(self):
        self.pretend(status="downloading", got=3_000_000, size=12_000_000)
        p = self.page(lambda p: p["meter"] >= 0, "the download's progress")
        self.assertEqual(p["label"], "Updating to v9.9.9…")
        self.assertIn("Step 1 of 2: downloading, 3.0 MB of 12.0 MB", p["detail"])
        self.assertAlmostEqual(p["meter"], 0.25, places=2)
        self.assertFalse(p["update"] or p["check"], "a button to press while it's updating")
        self.pretend(status="installing", got=0, size=0)
        p = self.page(lambda p: "Step 2 of 2" in p["detail"], "the installing step")
        self.assertEqual(p["meter"], -1, "the download's bar stayed")
        self.pretend(status="failed", error="Slate couldn't download the update (offline). Your Slate is just as it was.")
        p = self.page(lambda p: p["update"], "Try again")
        self.assertEqual(p["label"], "The update didn't finish")
        self.assertIn("couldn't download", p["detail"])

    def test_up_to_date(self):
        self.pretend(newer=False, latest="v0.1.0")
        p = self.page(lambda p: p["check"], "Check now")
        self.assertFalse(p["update"] or p["notes"], "an update offered with none to have")
        self.assertIn("you're up to date", p["detail"])


class DropdownsByPointer(LiveCase):
    """A Settings dropdown, clicked with a real pointer: its button opens the list, and its button
    again closes it (it used to close on the press and open again on the click, so the list
    popped straight back). Reported 2026-11-22."""

    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "windows")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "windows", "Settings → Windows")
        self.s.settle(0.8)

    def click(self, at):
        """(one pointer for the whole test: a new one for each click, and the second click went nowhere)"""
        if not hasattr(self, "pointer"):
            from pointer import Pointer
            self.pointer = Pointer(self.s.env, self.s.width, self.s.height).__enter__()
            self.addCleanup(self.pointer.close)
        self.pointer.move(*at)
        self.s.settle(0.15)
        self.pointer.button(True)
        self.s.settle(0.08)
        self.pointer.button(False)

    def button(self, label):
        r = json.loads(self.ipc("test", "settingsDropButton", label))
        self.assertTrue(r, f"no dropdown called {label!r}")
        win = next(c for c in self.s.hyprctl("clients", json_out=True) if c.get("class") == "slate-settings" and c.get("title") == "Settings")
        return win["at"][0] + r["x"] + r["w"] // 2, win["at"][1] + r["y"] + r["h"] // 2

    def test_its_button_closes_it_again(self):
        at = self.button("Default window mode")
        self.click(at)
        self.wait(lambda st: st["settings"]["drop"] == "Default window mode", "the list open")
        self.click(at)
        self.wait(lambda st: st["settings"]["drop"] == "", "the list closed by its button")
        self.s.settle(0.6)
        self.assertEqual(self.s.state()["settings"]["drop"], "", "it opened again")
        self.click(at)
        self.wait(lambda st: st["settings"]["drop"] == "Default window mode", "the list open once more")
        self.click((at[0] - 300, at[1] + 200))     # (elsewhere on the page)
        self.wait(lambda st: st["settings"]["drop"] == "", "a click elsewhere closing it")
