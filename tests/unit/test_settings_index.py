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
            self.assertEqual(set(it), {"page", "label", "detail", "group"})

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
