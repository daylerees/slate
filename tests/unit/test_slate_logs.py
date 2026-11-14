"""bin/slate-logs: the file people attach to public bug reports. It leaves out the location,
a command of the person's own and the display's name (which has its serial number), and writes
the home folder as ~ everywhere, so none of those is in the file, while the other settings
and the log are."""
import json
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "bin", "slate-logs")


class Logs(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.env = self.s.env
        self.install = os.path.join(self.h.dir, "slate")
        os.makedirs(self.install)
        self.user = os.path.basename(self.h.dir)   # (the part of the home path that is not common)
        home = self.h.home
        settings = {
            "latitude": 51.5072, "longitude": -0.1276, "locationName": "Hidden Place",
            "assistantCommand": "my-agent --token=hunter2-s3cret",
            "mainDisplay": "Dell Inc. U2720Q SERIAL4242",
            "wallpaper": home + "/Pictures/walls/one.jpg",
            "screenshotFolder": home + "/Shots",
            "wallpaperFolder": home,
            "themedApps": [home + "/bin/app", "firefox"],
            "nested": {"folder": home + "/deep"},
            "barPosition": "top", "logLevel": "normal", "accent": "#7aa2f7",
        }
        with open(os.path.join(self.install, "settings.json"), "w") as f:
            json.dump(settings, f)
        os.makedirs(os.path.join(self.h.cache), exist_ok=True)
        with open(os.path.join(self.h.cache, "slate.log"), "w") as f:
            f.write(f"INFO: loaded {home}/.config/slate/shell.qml\nINFO: nothing else\n")
        self.env.update(SLATE_DIR=self.install)

    def export(self):
        code, out = run(["sh", SCRIPT], env=self.env)
        self.assertEqual(code, 0, out)
        path = out.strip().splitlines()[-1]
        self.assertTrue(os.path.isfile(path), out)
        with open(path) as f:
            return f.read()

    def test_nothing_private_is_in_the_file(self):
        text = self.export()
        for secret in ("Hidden Place", "51.5072", "-0.1276", "hunter2", "my-agent", "SERIAL4242", "Dell Inc."):
            self.assertNotIn(secret, text)
        self.assertNotIn(self.h.home, text)
        self.assertNotIn(self.user, text)

    def test_says_only_whether_they_are_set(self):
        text = self.export()
        self.assertIn('"assistantCommand": "(set)"', text)
        self.assertIn('"mainDisplay": "(set)"', text)

    def test_not_set_says_so(self):
        p = os.path.join(self.install, "settings.json")
        with open(p) as f:
            s = json.load(f)
        s.update(assistantCommand="", mainDisplay="")
        with open(p, "w") as f:
            json.dump(s, f)
        text = self.export()
        self.assertIn('"assistantCommand": "(not set)"', text)
        self.assertIn('"mainDisplay": "(not set)"', text)

    def test_home_becomes_a_tilde_everywhere(self):
        text = self.export()
        self.assertIn('"wallpaper": "~/Pictures/walls/one.jpg"', text)
        self.assertIn('"screenshotFolder": "~/Shots"', text)
        self.assertIn('"wallpaperFolder": "~"', text)
        self.assertIn('"~/bin/app"', text)
        self.assertIn('"folder": "~/deep"', text)
        self.assertIn("INFO: loaded ~/.config/slate/shell.qml", text)

    def test_the_rest_is_still_there(self):
        text = self.export()
        for kept in ('"barPosition": "top"', '"accent": "#7aa2f7"', '"firefox"', "INFO: nothing else", "Versions"):
            self.assertIn(kept, text)
