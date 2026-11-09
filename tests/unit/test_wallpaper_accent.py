"""scripts/wallpaper-accent.py: the accent colour and tone Slate takes from the wallpaper.

Checks the output is exactly what Config.qml's picker parses (two lines, each #rrggbb), the
colours it picks for images made with Pillow (through the real ImageMagick: hue ranges, not
exact values), exact values from a stubbed magick histogram, and the defaults when magick
isn't installed or can't read the image.
"""
import colorsys
import os
import re
import sys
import unittest

from PIL import Image

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "wallpaper-accent.py")
DEFAULTS = ("#8fb3e8", "#1d222a")
LINE = re.compile(r"^#[0-9a-f]{6}$")     # what Config.qml's picker accepts (it's case-blind)


def hls(hexc):
    return colorsys.rgb_to_hls(*(int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)))


def hue(hexc):
    return hls(hexc)[0] * 360


class WallpaperAccent(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)

    def image(self, name, size, colour, stripes=()):
        """A wallpaper in one colour, with (x0, x1, colour) stripes over it."""
        img = Image.new("RGB", size, colour)
        for x0, x1, c in stripes:
            img.paste(c, (x0, 0, x1, size[1]))
        p = os.path.join(self.h.dir, name)
        img.save(p)
        return p

    def accent(self, path, env=None):
        code, out = run([sys.executable, SCRIPT, path], env=env or self.s.env)
        self.assertEqual(code, 0, out)
        # Exactly two lines, each a colour Config.qml takes
        self.assertTrue(out.endswith("\n"), repr(out))
        lines = out[:-1].split("\n")
        self.assertEqual(len(lines), 2, repr(out))
        for l in lines:
            self.assertRegex(l, LINE)
        return tuple(lines)

    def assert_accent_suits_dark_theme(self, accent):
        h, l, s = hls(accent)
        self.assertAlmostEqual(l, 0.74, delta=0.01, msg=f"{accent}: lightness")
        self.assertGreaterEqual(s, 0.44, accent)
        self.assertLessEqual(s, 0.76, accent)

    # --- with ImageMagick ---
    def real(self):
        slate.need("magick")

    def test_mostly_blue(self):
        self.real()
        p = self.image("blue.png", (160, 100), (30, 60, 200), [(0, 20, (200, 40, 40))])
        accent, tone = self.accent(p)
        self.assertTrue(215 <= hue(accent) <= 245, f"accent {accent} isn't blue ({hue(accent):.0f}°)")
        self.assert_accent_suits_dark_theme(accent)
        self.assertTrue(215 <= hue(tone) <= 260, f"tone {tone} isn't blue ({hue(tone):.0f}°)")

    def test_vivid_beats_bigger_dull(self):
        """A small vivid green beats a large dull brown."""
        self.real()
        p = self.image("two.png", (200, 100), (110, 95, 80), [(0, 50, (20, 200, 60))])
        accent, tone = self.accent(p)
        self.assertTrue(110 <= hue(accent) <= 150, f"accent {accent} isn't green ({hue(accent):.0f}°)")
        self.assert_accent_suits_dark_theme(accent)

    def test_tiny_image(self):
        self.real()
        accent, tone = self.accent(self.image("tiny.png", (1, 1), (30, 160, 60)))
        self.assertTrue(110 <= hue(accent) <= 150, accent)
        self.assertTrue(110 <= hue(tone) <= 150, tone)

    def test_black(self):
        """Nothing usable (too dark): the defaults."""
        self.real()
        self.assertEqual(self.accent(self.image("black.png", (64, 64), (0, 0, 0))), DEFAULTS)

    def test_grey_tone(self):
        """A colourless wallpaper has no tone: the default."""
        self.real()
        accent, tone = self.accent(self.image("grey.png", (64, 64), (128, 128, 128)))
        self.assertEqual(tone, DEFAULTS[1])

    # A grey wallpaper used to give a pink accent: grey scored 0 (beating the start of -1) and
    # its saturation was raised to 0.45 at hue 0. It gets the default, as black does
    def test_grey_accent(self):
        self.real()
        accent, tone = self.accent(self.image("grey2.png", (64, 64), (128, 128, 128)))
        self.assertEqual(accent, DEFAULTS[0])

    def test_no_image_given(self):
        """Without an image: the usage line and exit 1, not a traceback."""
        code, out = run(["python3", SCRIPT], env=self.s.env)
        self.assertEqual(code, 1)
        self.assertNotIn("Traceback", out)
        self.assertIn("wallpaper-accent.py <image>", out)

    def test_deterministic(self):
        self.real()
        p = self.image("again.png", (120, 80), (200, 120, 30), [(0, 30, (40, 40, 160))])
        self.assertEqual(self.accent(p), self.accent(p))

    # --- with a stubbed magick ---
    def test_magick_call(self):
        """Reads the first frame, shrunk to 96×96 and 12 colours, as a histogram."""
        self.s.add("magick", stdout="")
        self.accent("/wallpapers/a b.gif")
        self.assertEqual(self.s.calls("magick"), [["/wallpapers/a b.gif[0]", "-resize", "96x96!", "-colors", "12",
                                                   "-format", "%c", "histogram:info:"]])

    def test_histogram(self):
        """Exact picks from a histogram: the vivid red over a larger dark grey; black is left out
        of the accent, and the grey adds nothing to the tone's hue."""
        self.s.add("magick", stdout="          7000: ( 80, 80, 80) #505050 gray(80)\n"
                                    "          1000: (200,40,40) #C82828 srgb(200,40,40)\n"
                                    "          1216: (  0,  0,  0) #000000 black\n")
        self.assertEqual(self.accent("x.png"), ("#e99090", "#897676"))

    def test_histogram_lower_case_and_junk(self):
        self.s.add("magick", stdout="garbage line\n   9216: (30,60,200) #1e3cc8 srgb(30,60,200)\n\n")
        accent, tone = self.accent("x.png")
        self.assertEqual(accent, "#8c9dee")

    def test_magick_fails(self):
        """magick can't read it (not an image): the defaults."""
        self.s.add("magick", stdout="", code=1)
        self.assertEqual(self.accent("broken.png"), DEFAULTS)

    def test_not_an_image(self):
        self.real()
        p = os.path.join(self.h.dir, "notes.png")
        with open(p, "w") as f:
            f.write("not an image")
        self.assertEqual(self.accent(p), DEFAULTS)
        self.assertEqual(self.accent(os.path.join(self.h.dir, "missing.png")), DEFAULTS)

    def test_no_magick(self):
        """ImageMagick not installed (and no old `convert` either): the defaults, not a crash."""
        self.s.add("magick", missing=True)
        self.s.add("convert", missing=True)
        p = self.image("blue.png", (32, 32), (30, 60, 200))
        self.assertEqual(self.accent(p), DEFAULTS)
