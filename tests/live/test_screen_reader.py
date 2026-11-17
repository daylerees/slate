"""Accessibility → Screen reader: with it on, Slate starts with Qt's accessibility on (bin/slate),
and what Orca reads is there on the accessibility bus (AT-SPI): Settings' switches as check
boxes by their labels, its buttons by theirs. Read here as Orca reads it, through Atspi, in a
Slate of its own (the test never starts Orca or speaks)."""
import atexit
import json
import subprocess
import textwrap
import unittest

from live import LiveCase
from session import Session, in_container

READ = textwrap.dedent("""
import json, gi; gi.require_version('Atspi', '2.0'); from gi.repository import Atspi
d = Atspi.get_desktop(0); found = []
def walk(o, depth=0):
    if depth > 40 or len(found) > 4000: return
    try:
        found.append([o.get_role_name(), o.get_name() or "",
                      o.get_state_set().contains(Atspi.StateType.CHECKED)])
        for i in range(o.get_child_count()): walk(o.get_child_at_index(i), depth + 1)
    except Exception:
        return
for i in range(d.get_child_count()):
    a = d.get_child_at_index(i)
    if a.get_name() in ("qs", "quickshell"): walk(a)
print(json.dumps(found))
""")


class ScreenReader(LiveCase):
    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"screenReader": True})
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def tree(self):
        r = subprocess.run(["python3", "-c", READ], env=self.s.env, capture_output=True, text=True, timeout=60)
        return json.loads(r.stdout or "[]")

    def test_settings_reads_as_it_should(self):
        self.ipc("settings", "page", "accessibility")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "accessibility", "Settings → Accessibility")
        self.s.settle(1.5)
        tree = self.tree()
        named = {(role, name) for role, name, _ in tree}
        self.assertIn(("check box", "Reduce motion"), named, "Reduce motion isn't a check box Orca can read")
        self.assertIn(("check box", "Screen reader"), named)
        self.assertIn(("button", "Show me"), named,
                      "a button isn't read by its label: " + repr([x for x in named if "Show" in x[1] or "button" in x[0]][:15]))
        self.assertIn(("combo box", "Text size"), named, "a dropdown isn't read by its label")
        on = [c for role, name, c in tree if role == "check box" and name == "Screen reader"]
        self.assertTrue(on and on[0], "the screen reader's own switch doesn't read as on")
