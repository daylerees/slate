"""scripts/settings-index.py: the list Settings search is built from."""
import json
import re

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "settings-index.py")


def index():
    code, out = run(["python3", SCRIPT, slate.path("shell", "SettingsWindow.qml")])
    assert code == 0, out
    return json.loads(out)


class SettingsIndex(Case):
    @classmethod
    def setUpClass(cls):
        cls.items = index()

    def test_shape(self):
        self.assertGreater(len(self.items), 100, "far fewer settings found than Settings has")
        for it in self.items[:5]:
            self.assertEqual(set(it), {"page", "label", "detail", "group", "key"})

    def test_keys(self):
        """Each row names the setting it changes (for the assistant's tools, slate-mcp.py):
        only real settings, the well-known ones right, and most rows linked."""
        keys = set(re.findall(r"^\s*property \w+ (\w+):", slate.read("shell", "SettingsData.qml"), re.M))
        by = {(it["page"], it["label"]): it["key"] for it in self.items}
        for it in self.items:
            if it["key"]:
                with self.subTest(it["page"] + ": " + it["label"]):
                    self.assertIn(it["key"], keys, f"{it['key']} isn't a setting in SettingsData.qml")
        for (page, label), key in {("appearance", "Glass"): "glass", ("dock", "Icon size"): "dockIconSize",
                                   ("appearance", "Interface size"): "uiScale", ("input", "Caps Lock key"): "capsLock",
                                   ("sound", "Volume keys"): "tickVolume", ("hotcorners", "Delay"): "hotCornerDelay",
                                   # Rows that aren't one setting, or set it some other way
                                   ("screensaver", "Videos folder"): "", ("appearance", "Theme"): "",
                                   ("sound", "Mute"): "", ("debug", "Factory reset"): ""}.items():
            with self.subTest(page + ": " + label):
                self.assertEqual(by.get((page, label)), key)
        linked = {it["key"] for it in self.items if it["key"]}
        self.assertGreater(len(linked), 160, "far fewer settings linked to their rows than before")

    def test_every_page_has_settings(self):
        """Each Settings page (bar the overview) has something search can find on it."""
        src = slate.read("shell", "SettingsIndex.qml")
        pages = re.findall(r"\{\s*id:\s*\"(\w+)\"", src.split("readonly property var pages:")[1].split("\n    ]")[0])
        found = {it["page"] for it in self.items}
        for p in pages:
            with self.subTest(p):
                self.assertIn(p, found, f"search finds nothing on the {p} page")

    def test_labels_unique_per_page(self):
        seen = {}
        for it in self.items:
            key = (it["page"], it["label"])
            seen[key] = seen.get(key, 0) + 1
        dupes = [f"{p}: {l}" for (p, l), n in seen.items() if n > 1]
        self.assertFalse(dupes, f"the same label twice on a page (search can't tell them apart): {dupes[:5]}")

    def test_no_code_in_labels(self):
        """Labels are plain text, not expressions the script failed to leave out."""
        bad = [it["label"] for it in self.items if re.search(r"[{}]|\$\{|\?\s.*:|\+\s*\"|\bConfig\.|\bqsTr\(", it["label"])]
        self.assertFalse(bad, f"labels that look like code: {bad[:5]}")
