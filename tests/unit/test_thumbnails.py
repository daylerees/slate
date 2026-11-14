"""scripts/thumbnails.py: small pictures of wallpapers from the shared thumbnail cache (the
freedesktop.org one, x-large), made for any that are missing or out of date, for the wallpaper
switcher's cards. The images are made at test time."""
import hashlib
import json
import os
import unittest
from pathlib import Path

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "thumbnails.py")


class Thumbnails(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        try:
            from PIL import Image
        except ImportError:
            raise unittest.SkipTest("Pillow isn't installed")
        self.Image = Image
        self.folder = self.h("Pictures", "Wall papers")       # (a space: the URI is escaped)
        os.makedirs(self.folder)
        self.cache = self.h(".cache", "thumbnails", "x-large")

    def make(self, name, size=(1600, 1000), fmt="PNG"):
        p = os.path.join(self.folder, name)
        self.Image.new("RGB", size, (30, 60, 90)).save(p, fmt)
        return p

    def thumbs(self, *paths):
        code, out = run(["python3", SCRIPT, *paths], env=self.h.env, timeout=30)
        self.assertEqual(code, 0, out)
        return [json.loads(l) for l in out.splitlines() if l.startswith("{")]

    def test_made_as_the_spec_says(self):
        p = self.make("sky.png")
        (got,) = self.thumbs(p)
        uri = Path(p).as_uri()
        self.assertIn("%20", uri)
        want = os.path.join(self.cache, hashlib.md5(uri.encode()).hexdigest() + ".png")
        self.assertEqual(got, {"path": p, "thumb": want})
        with self.Image.open(want) as t:
            self.assertEqual(max(t.size), 512)
            self.assertEqual(t.size, (512, 320), "not the picture's own shape")
            self.assertEqual(t.text["Thumb::URI"], uri)
            self.assertEqual(t.text["Thumb::MTime"], str(int(os.stat(p).st_mtime)))
        self.assertEqual(os.stat(want).st_mode & 0o777, 0o600)
        self.assertEqual(os.listdir(self.cache), [os.path.basename(want)], "a half-written file was left behind")

    def test_made_once_and_again_when_changed(self):
        a, b = self.make("a.jpg", fmt="JPEG"), self.make("b.png")
        self.thumbs(a, b)
        made = {f: os.stat(os.path.join(self.cache, f)).st_mtime_ns for f in os.listdir(self.cache)}
        self.assertEqual(len(made), 2)
        # Already there and up to date: listed, not made again
        self.assertEqual({t["path"] for t in self.thumbs(a, b)}, {a, b})
        self.assertEqual({f: os.stat(os.path.join(self.cache, f)).st_mtime_ns for f in os.listdir(self.cache)}, made)
        # The picture changed: made again
        st = os.stat(b)
        os.utime(b, (st.st_atime, st.st_mtime + 60))
        self.thumbs(a, b)
        again = {f: os.stat(os.path.join(self.cache, f)).st_mtime_ns for f in os.listdir(self.cache)}
        self.assertEqual([f for f in again if again[f] != made[f]], [os.path.basename(self.thumbs(b)[0]["thumb"])])

    def test_ones_already_there_come_first(self):
        old = self.make("old.png")
        self.thumbs(old)
        new = self.make("new.png")
        self.assertEqual([t["path"] for t in self.thumbs(new, old)], [old, new])

    def test_unreadable_left_out(self):
        good = self.make("good.png")
        bad = os.path.join(self.folder, "broken.jpg")
        with open(bad, "w") as f:
            f.write("not a picture")
        self.assertEqual([t["path"] for t in self.thumbs(bad, good, os.path.join(self.folder, "gone.png"))], [good])

    def test_xdg_cache_home(self):
        p = self.make("sea.png")
        env = dict(self.h.env, XDG_CACHE_HOME=self.h("elsewhere"))
        code, out = run(["python3", SCRIPT, p], env=env, timeout=30)
        self.assertEqual(code, 0, out)
        self.assertTrue(json.loads(out.splitlines()[0])["thumb"].startswith(self.h("elsewhere", "thumbnails", "x-large")))
