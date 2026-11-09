"""scripts/image-sizes.py: the pixel size of each wallpaper-to-be in a folder (Settings →
Appearance hides the ones too small). The images are made at test time."""
import json
import os
import unittest

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "image-sizes.py")


class ImageSizes(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        try:
            from PIL import Image
        except ImportError:
            raise unittest.SkipTest("Pillow isn't installed")
        self.Image = Image
        self.folder = self.h("Pictures", "Wallpapers")
        os.makedirs(self.folder)

    def make(self, name, size, fmt):
        self.Image.new("RGB", size, (30, 60, 90)).save(os.path.join(self.folder, name), fmt)

    def sizes(self, folder=None):
        code, out = run(["python3", SCRIPT, folder or self.folder], env=self.h.env, timeout=20)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def test_sizes(self):
        self.make("wide.png", (64, 36), "PNG")
        self.make("photo.jpg", (40, 30), "JPEG")
        self.make("tall.jpeg", (9, 16), "JPEG")
        self.make("tiny.webp", (4, 3), "WEBP")
        # The extension's case doesn't matter, nor whether it matches what's inside
        self.make("SHOUT.PNG", (12, 10), "PNG")
        self.make("really-a-png.jpg", (20, 10), "PNG")
        self.assertEqual(self.sizes(), {
            "wide.png": [64, 36], "photo.jpg": [40, 30], "tall.jpeg": [9, 16], "tiny.webp": [4, 3],
            "SHOUT.PNG": [12, 10], "really-a-png.jpg": [20, 10],
        })

    def test_left_out(self):
        """Other kinds of file, and files that can't be read, are left out (so they're shown)."""
        self.make("ok.png", (8, 8), "PNG")
        self.make("anim.gif", (8, 8), "GIF")         # not a type it looks at
        self.make("pic.bmp", (8, 8), "BMP")
        with open(os.path.join(self.folder, "broken.png"), "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\nnot really")
        with open(os.path.join(self.folder, "empty.jpg"), "wb"):
            pass
        with open(os.path.join(self.folder, "notes.txt"), "w") as f:
            f.write("hi")
        os.makedirs(os.path.join(self.folder, "folder.png"))
        self.assertEqual(self.sizes(), {"ok.png": [8, 8]})

    def test_not_recursive(self):
        os.makedirs(os.path.join(self.folder, "more"))
        self.Image.new("RGB", (5, 5)).save(os.path.join(self.folder, "more", "inner.png"))
        self.assertEqual(self.sizes(), {})

    def test_empty_folder(self):
        self.assertEqual(self.sizes(), {})

    def test_only_reads_headers(self):
        """The size comes from the header, without decoding the image (it's quick): a big
        image cut off just after its header still has one."""
        self.make("big.png", (8000, 6000), "PNG")
        p = os.path.join(self.folder, "big.png")
        with open(p, "rb") as f:
            head = f.read(64)
        with open(p, "wb") as f:
            f.write(head)
        self.assertEqual(self.sizes(), {"big.png": [8000, 6000]})

    def test_missing_folder(self):
        code, out = run(["python3", SCRIPT, self.h("nope")], env=self.h.env, timeout=20)
        self.assertNotEqual(code, 0)
        self.assertNotIn("{", out)
