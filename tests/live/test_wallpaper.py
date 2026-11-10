"""The wallpapers that come with Slate (shell/wallpapers; Settings → Appearance → Slate's
wallpapers): offered beside the images in your own folder, and so part of "Next wallpaper" and
changing by itself, unless switched off."""
import os

import numpy as np
from PIL import Image

from live import LiveCase


class SlateWallpapers(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("wallpaperFolder", "wallpaperShowSlate"):
            self.keep_setting(key)
        old = self.ipc("wallpaper", "get")
        self.addCleanup(lambda: self.ipc("wallpaper", "set", old))
        # A folder with no pictures of its own
        self.empty = self.s.h("Pictures", "none-here")
        os.makedirs(self.empty, exist_ok=True)
        self.config("wallpaperFolder", self.empty)
        self.own = os.path.join(self.s.slate_dir, "wallpapers")

    def test_shipped(self):
        names = sorted(os.listdir(self.own))
        self.assertGreaterEqual(len(names), 4)
        self.assertTrue(all(n.startswith("slate-") and n.endswith(".png") for n in names), names)

    def test_next_uses_slates_own(self):
        self.config("wallpaperShowSlate", "true")
        self.s.settle(0.8)
        seen = set()
        for _ in range(3):
            before = self.ipc("wallpaper", "get")
            self.ipc("wallpaper", "next")
            self.s.wait(lambda st: self.ipc("wallpaper", "get") != before, what="another wallpaper")
            now = self.ipc("wallpaper", "get")
            self.assertEqual(os.path.dirname(now), self.own, "not one of Slate's wallpapers")
            self.assertNotIn(now, seen, "repeated before each had its turn")
            seen.add(now)

    def test_switched_off(self):
        self.config("wallpaperShowSlate", "false")
        self.s.settle(0.8)
        before = self.ipc("wallpaper", "get")
        self.ipc("wallpaper", "next")
        self.s.settle(2.0)
        self.assertEqual(self.ipc("wallpaper", "get"), before, "changed with nothing to change to")

    def test_no_banding_on_screen(self):
        """Slate's wallpapers are smooth colour, which shows as bands if the picture is scaled
        to the screen and rounded plainly (it was: a bug). Drawn through shaders/dither.frag,
        every small patch of the screen averages out to the picture's own colour there.
        Measured between the bar and the dock, in 32 px patches, against the picture scaled
        without rounding."""
        self.close_windows()                 # (the picture itself, with nothing over it)
        path = os.path.join(self.own, "slate-graphite.png")
        self.ipc("wallpaper", "set", path)
        self.s.wait(lambda st: self.ipc("wallpaper", "get") == path, what="the wallpaper")
        self.s.settle(2.0)                                   # (the crossfade)
        shot = Image.open(self.screenshot("wallpaper-banding")).convert("RGB")
        w, h = shot.size
        # As Wallpaper.qml draws it: filling an area 4 px larger than the screen all round
        src = Image.open(path).convert("RGB")
        fit = max((w + 8) / src.width, (h + 8) / src.height)
        sw, sh = round(src.width * fit), round(src.height * fit)
        left, top = (sw - w) // 2, (sh - h) // 2
        area = (0, 150, w - w % 32, 150 + (h - 300) // 32 * 32)      # whole 32 px patches, clear of the bar and dock
        worst = 0.0
        for ch_shot, ch_src in zip(shot.split(), src.split()):
            want = ch_src.convert("F").resize((sw, sh), Image.BILINEAR).crop((left, top, left + w, top + h)).crop(area)
            got = ch_shot.convert("F").crop(area)
            patches = (want.width // 32, want.height // 32)
            diff = np.asarray(got.resize(patches, Image.BOX)) - np.asarray(want.resize(patches, Image.BOX))
            worst = max(worst, float(np.abs(diff).max()))
        # Rounded plainly, patches are out by up to half a step (0.5); dithered, a few hundredths
        self.assertLess(worst, 0.2, f"patches of the screen are {worst:.2f} colour steps out: banding")
