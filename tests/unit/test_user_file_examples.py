"""The files Slate makes for your own Hyprland config (data/user-files/hypr/) say "remove the
'--' to use one". Two examples in binds.lua ended in a note outside any comment, so uncommenting
one was a Lua error that skipped the whole file (a bug). Every example line, uncommented, must
still be Lua: each file is checked with all of its examples uncommented at once."""
import os
import re
import shutil
import subprocess
import tempfile

import slate
from slate import Case

FOLDER = slate.path("shell", "data", "user-files", "hypr")
# An example line: "-- " then code (hl.…, a NAME = value, or the end of a function), not words
EXAMPLE = re.compile(r"^-- ( *(hl\.|end\)|[A-Z][A-Z0-9_]* *=).*)$")


def uncommented(text):
    return "\n".join(m.group(1) if (m := EXAMPLE.match(line)) else line for line in text.split("\n"))


class Examples(Case):
    def setUp(self):
        super().setUp()
        self.luac = shutil.which("luac") or shutil.which("luac5.4")
        if not self.luac:
            self.skipTest("needs luac")

    def test_every_example_uncommented_is_lua(self):
        files = sorted(f for f in os.listdir(FOLDER) if f.endswith(".lua"))
        self.assertGreater(len(files), 5)
        for name in files:
            with self.subTest(file=name):
                with open(os.path.join(FOLDER, name)) as f:
                    text = f.read()
                examples = [l for l in text.split("\n") if EXAMPLE.match(l)]
                self.assertTrue(examples, f"{name} has no examples (or they no longer look like code)")
                with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
                    f.write(uncommented(text))
                self.addCleanup(os.remove, f.name)
                r = subprocess.run([self.luac, "-p", f.name], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, f"{name}, uncommented, isn't Lua: {r.stderr}")

    def test_no_example_uses_the_old_games_workspace(self):
        for name in os.listdir(FOLDER):
            with open(os.path.join(FOLDER, name)) as f:
                self.assertNotIn("name:gaming", f.read(), name)
