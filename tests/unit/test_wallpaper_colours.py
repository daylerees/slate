"""scripts/wallpaper-colours.py: each wallpaper's colours worked out ahead for the wallpaper
switcher (by wallpaper-accent.py, with a stubbed magick), kept on disk with each file's size and
time so they're there at once next time, and worked out again when a picture changes."""
import json
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "wallpaper-colours.py")
BLUE = "   9216: (30,60,200) #1e3cc8 srgb(30,60,200)\n"


class WallpaperColours(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("magick", stdout=BLUE)
        self.folder = self.h("Pictures")
        os.makedirs(self.folder, exist_ok=True)
        self.paths = []
        for name in ("a.png", "b.png", "c.png"):
            p = os.path.join(self.folder, name)
            with open(p, "w") as f:
                f.write(name)
            self.paths.append(p)
        self.cache = self.h(".cache", "slate", "wallpaper-colours-all.json")

    def colours(self, *paths):
        code, out = run(["python3", SCRIPT, *paths], env=self.s.env, timeout=60)
        self.assertEqual(code, 0, out)
        return [json.loads(l) for l in out.splitlines() if l.startswith("{")]

    def test_worked_out_in_order_then_kept(self):
        got = self.colours(*self.paths)
        self.assertEqual([g["path"] for g in got], self.paths, "not nearest first")
        for g in got:
            self.assertRegex(g["accent"], r"^#[0-9a-f]{6}$")
            self.assertRegex(g["tone"], r"^#[0-9a-f]{6}$")
        self.assertEqual(len(self.s.calls("magick")), 3)
        # Next time: all known, nothing worked out again
        self.assertEqual(self.colours(*reversed(self.paths)), list(reversed(got)))
        self.assertEqual(len(self.s.calls("magick")), 3, "worked out again although nothing changed")
        with open(self.cache) as f:
            self.assertEqual(set(json.load(f)), set(self.paths))

    def test_a_changed_picture_is_worked_out_again(self):
        self.colours(*self.paths)
        with open(self.paths[1], "a") as f:
            f.write("more")
        self.colours(*self.paths)
        self.assertEqual(len(self.s.calls("magick")), 4)
        self.assertIn(self.paths[1], self.s.calls("magick")[-1][0])

    def test_missing_and_unreadable_left_out(self):
        self.s.add("magick", stdout="", code=1)          # (wallpaper-accent.py then gives its defaults)
        gone = os.path.join(self.folder, "gone.png")
        got = self.colours(gone, self.paths[0])
        self.assertEqual([g["path"] for g in got], [self.paths[0]], "a missing file was listed")

    def test_a_damaged_cache_is_started_again(self):
        os.makedirs(os.path.dirname(self.cache), exist_ok=True)
        with open(self.cache, "w") as f:
            f.write("{not json")
        self.assertEqual(len(self.colours(self.paths[0])), 1)
        with open(self.cache) as f:
            self.assertIn(self.paths[0], json.load(f))
