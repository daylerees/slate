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
