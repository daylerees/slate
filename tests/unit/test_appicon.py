"""scripts/appicon.py: app icon tiles for the dock, launcher and bar (--tile, --tile-all,
--preview, --colours), drawn from a small icon theme made at test time in the scratch home.

Rendered images differ a little between Pillow/librsvg versions, so these check what the
tiles look like (size, which corners are cut away, colours, centring) rather than hashes.
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "appicon.py")
PX = 48
INNER_FILL = (0x2A, 0x31, 0x3C)
BLUE = (40, 90, 220)
RED = (208, 48, 48)


def close(a, b, tol=24):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


class AppIcon(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        h = self.h
        # Only the scratch home's icons: no system themes, apps or pixmaps
        self.sys = os.path.join(h.dir, "sys-share")
        os.makedirs(self.sys)
        h.env["XDG_DATA_DIRS"] = self.sys
        self.apps = os.path.join(h.data, "applications")
        self.icons = os.path.join(h.data, "icons", "hicolor", "256x256", "apps")
        os.makedirs(self.apps)
        os.makedirs(self.icons)
        self.make_icons()

    # --- fixtures ---
    def png(self, name, img):
        img.save(os.path.join(self.icons, name + ".png"))

    def desktop(self, app, icon, extra=""):
        with open(os.path.join(self.apps, app + ".desktop"), "w") as f:
            f.write(f"[Desktop Entry]\nType=Application\nName={app}\nIcon={icon}\n{extra}")

    def make_icons(self):
        # A full square icon (its own rounded-square artwork), red with a white dot
        sq = Image.new("RGBA", (256, 256), RED + (255,))
        ImageDraw.Draw(sq).ellipse((96, 96, 160, 160), fill=(255, 255, 255, 255))
        self.png("squareapp", sq)
        # A round icon on a transparent margin, with a soft theme-style shadow under it
        rd = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        d = ImageDraw.Draw(rd)
        d.ellipse((34, 44, 230, 240), fill=(0, 0, 0, 50))           # shadow, 20% opaque
        d.ellipse((28, 28, 228, 228), fill=BLUE + (255,))
        d.rectangle((118, 118, 138, 138), fill=(255, 255, 255, 255))  # the glyph, in the middle
        self.png("roundapp", rd)
        # A small round icon stuck in the top-left corner of its canvas
        off = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(off).ellipse((10, 10, 110, 110), fill=BLUE + (255,))
        self.png("offcentre", off)
        self.desktop("squareapp", "squareapp")
        self.desktop("roundapp", "roundapp")
        self.desktop("offcentre", "offcentre")
        self.desktop("firefox", "roundapp")

    # --- running it ---
    def tile(self, app, *style, folder="out", px=PX):
        out = os.path.join(self.h.dir, folder, app + ".png")
        self.ok([sys.executable, SCRIPT, "--tile", app, out, str(px), *style], env=self.h.env)
        img = Image.open(out)
        self.assertEqual(img.size, (px, px))
        self.assertEqual(img.mode, "RGBA")
        return img

    @staticmethod
    def alpha_at(img, x, y):
        return img.getpixel((x, y))[3]

    @staticmethod
    def transparent(img):
        return sum(1 for a in img.getchannel("A").getdata() if a < 128)

    def corners(self, img):
        w, h = img.size
        return [self.alpha_at(img, x, y) for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]

    def assert_centred(self, img, tol=1):
        l, t, r, b = img.getchannel("A").point(lambda a: 255 if a > 128 else 0).getbbox()
        w, h = img.size
        self.assertLessEqual(abs(l - (w - r)), tol, f"not centered across: {l}..{r} of {w}")
        self.assertLessEqual(abs(t - (h - b)), tol, f"not centered down: {t}..{b} of {h}")
        return l, t, r, b

    # --- shapes ---
    def test_fill_shapes(self):
        """--fill on a round icon: the tile is its main colour, cut to each shape."""
        for shape in ("tile", "squircle", "circle", "square"):
            with self.subTest(shape):
                img = self.tile("roundapp", "--shape", shape, "--fill")
                c = self.corners(img)
                if shape == "square":
                    self.assertEqual(c, [255] * 4, "a square tile has solid corners")
                else:
                    self.assertTrue(all(a == 0 for a in c), f"{shape}: corners should be cut away, got {c}")
                # Edge middles are inside every shape, in the icon's main colour (not the shadow)
                for x, y in ((PX // 2, 1), (1, PX // 2), (PX // 2, PX - 2), (PX - 2, PX // 2)):
                    p = img.getpixel((x, y))
                    self.assertEqual(p[3], 255)
                    self.assertTrue(close(p[:3], BLUE), f"{shape}: edge at {x},{y} is {p}, not the icon's blue")
                self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], (255, 255, 255), 40),
                                f"{shape}: the glyph isn't in the middle")

    def test_shapes_differ(self):
        """Each shape cuts away more of the tile: square < tile < squircle < circle."""
        cut = {s: self.transparent(self.tile("roundapp", "--shape", s, "--fill", folder="o-" + s))
               for s in ("square", "tile", "squircle", "circle")}
        self.assertEqual(cut["square"], 0)
        self.assertLess(cut["square"], cut["tile"])
        self.assertLess(cut["tile"], cut["squircle"])
        self.assertLess(cut["squircle"], cut["circle"])
        # A circle cuts away about 1 - pi/4 (21%) of the square
        self.assertAlmostEqual(cut["circle"] / PX ** 2, 0.2146, delta=0.03)
        self.assertAlmostEqual(cut["tile"] / PX ** 2, 0.0435, delta=0.02)

    def test_square_icon_fill_crops_its_border(self):
        """A square icon fills its tile (enlarged, its own edge cropped), no background around it."""
        img = self.tile("squareapp", "--shape", "tile", "--fill")
        for x, y in ((PX // 2, 0), (0, PX // 2), (6, 6)):
            self.assertTrue(close(img.getpixel((x, y))[:3], RED), f"{x},{y}: {img.getpixel((x, y))}")
        self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], (255, 255, 255), 40))
        self.assertEqual(self.corners(img), [0] * 4)

    def test_whole(self):
        """--whole: the icon at 72% with nothing behind it (Slate draws the plate)."""
        for shape in ("tile", "circle", "square"):
            with self.subTest(shape):
                img = self.tile("roundapp", "--shape", shape, "--whole")
                self.assertEqual(self.corners(img), [0] * 4)
                self.assertEqual(self.alpha_at(img, PX // 2, 1), 0, "nothing drawn at the edge")
                l, t, r, b = self.assert_centred(img)
                self.assertAlmostEqual((r - l) / PX, 0.72, delta=0.06)
                self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], (255, 255, 255), 40))

    def test_whole_is_the_same_for_every_shape(self):
        """--whole leaves the shape to Slate: the drawing doesn't change with it, bar
        the cut at the very corners (the icon is well inside them)."""
        a = self.tile("roundapp", "--shape", "tile", "--whole", folder="a")
        b = self.tile("roundapp", "--shape", "square", "--whole", folder="b")
        self.assertEqual(a.tobytes(), b.tobytes())

    def test_original(self):
        """original: no tile. --fill trims the margin and shadow and grows the icon to fill;
        --whole leaves it as the app ships it."""
        filled = self.tile("roundapp", "--shape", "original", "--fill")
        l, t, r, b = self.assert_centred(filled)
        self.assertGreaterEqual(r - l, PX - 2, "a trimmed icon fills the image")
        self.assertEqual(self.corners(filled), [0] * 4)
        whole = self.tile("roundapp", "--shape", "original", "--whole", folder="w")
        # As shipped: the 28px margin of 256 stays, and so does the shadow below the circle
        l, t, r, b = whole.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
        self.assertAlmostEqual(l / PX, 28 / 256, delta=0.03)
        self.assertGreater(b, r - 1, "the shadow (lower than the icon) is kept")

    def test_shadow_removed_with_fill(self):
        """The faint dark shadow isn't taken as the icon's colour or its size."""
        img = self.tile("roundapp", "--shape", "original", "--fill")
        self.assert_centred(img)
        for y in (2, PX - 3):
            p = img.getpixel((PX // 2, y))
            self.assertTrue(close(p[:3], BLUE), f"row {y} is {p}: the shadow or margin is still there")

    def test_off_centre_icon_is_centred(self):
        for style in (("--shape", "original", "--fill"), ("--shape", "tile", "--whole")):
            with self.subTest(" ".join(style)):
                self.assert_centred(self.tile("offcentre", *style, folder="-".join(style)))

    def test_missing_icon(self):
        """An app with no icon anywhere: a plain tile in the default colour (--fill), or
        nothing at all (original)."""
        img = self.tile("no-such-app-anywhere", "--shape", "tile", "--fill")
        self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], INNER_FILL, 2))
        self.assertTrue(close(img.getpixel((PX // 2, 1))[:3], INNER_FILL, 2))
        self.assertEqual(self.corners(img), [0] * 4)
        for style in (("--shape", "original", "--fill"), ("--shape", "original", "--whole")):
            with self.subTest(" ".join(style)):
                img = self.tile("no-such-app-anywhere", *style, folder="-".join(style))
                self.assertIsNone(img.getchannel("A").getbbox(), "an empty image")

    # With --whole and no icon, the tile used to be filled dark anyway, covering the theme's
    # plate (IconPlate.qml): a dark square in light mode. Nothing is drawn behind now
    def test_missing_icon_whole(self):
        img = self.tile("no-such-app-anywhere", "--shape", "tile", "--whole")
        self.assertIsNone(img.getchannel("A").getbbox(), "--whole draws nothing behind the icon")

    def test_deterministic(self):
        """The same app and style draw the same bytes every time."""
        for style in (("--shape", "squircle", "--fill"), ("--shape", "circle", "--whole")):
            with self.subTest(" ".join(style)):
                a = self.tile("roundapp", *style, folder="one")
                b = self.tile("roundapp", *style, folder="two")
                self.assertEqual(a.tobytes(), b.tobytes())

    def test_bad_shape_is_tile(self):
        a = self.tile("roundapp", "--shape", "hexagon", folder="a")
        b = self.tile("roundapp", "--shape", "tile", "--fill", folder="b")
        self.assertEqual(a.tobytes(), b.tobytes())

    # --- folders say the style ---
    def test_folder_wins_over_arguments(self):
        """A tile drawn into tiles/circle-whole is a whole circle-style icon, whatever the
        command line says (a style change can't put old-style icons in the new folder)."""
        img = self.tile("roundapp", "--shape", "square", "--fill", folder="tiles/circle-whole")
        self.assertEqual(self.alpha_at(img, PX // 2, 1), 0, "drawn filled, not whole")
        img = self.tile("roundapp", "--shape", "square", "--fill", folder="tiles/circle")
        self.assertEqual(self.corners(img), [0] * 4, "drawn square, not circle")
        img = self.tile("roundapp", "--shape", "circle", "--whole", folder="tiles")
        self.assertEqual(self.corners(img), [0] * 4)
        self.assertEqual(img.getpixel((PX // 2, 1))[3], 255, "tiles/ itself is the default: tile, filled")

    # --- finding the icon ---
    def test_lookup(self):
        """Apps found by desktop id, StartupWMClass, reverse-domain prefix and icon name."""
        self.desktop("com.example.Thing", "roundapp")
        self.desktop("weirdname", "roundapp", "StartupWMClass=ThingWindow\n")
        self.desktop("org.gnome.Unrelated", "roundapp")
        blue = self.tile("roundapp", "--shape", "square", "--fill", folder="ref")
        for app in ("com.example.Thing", "ThingWindow", "com.example.Editor", "ROUNDAPP"):
            with self.subTest(app):
                img = self.tile(app, "--shape", "square", "--fill", folder="look-" + app)
                self.assertEqual(img.tobytes(), blue.tobytes())
        with self.subTest("shared prefix"):
            # org.gnome is shared by many apps: never matched by prefix alone
            img = self.tile("org.gnome.Other", "--shape", "square", "--fill", folder="gnome")
            self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], INNER_FILL, 2))

    def test_absolute_icon_path_missing(self):
        """Icon=/a/path/that/isnt/there.png falls back to looking the name up in the themes."""
        self.desktop("moved", "/opt/gone/roundapp.png")
        img = self.tile("moved", "--shape", "square", "--fill")
        self.assertTrue(close(img.getpixel((PX // 2, 1))[:3], BLUE))

    def test_svg_icon(self):
        """SVGs go through rsvg-convert, with Papirus-style faint black/white layers removed."""
        slate.need("rsvg-convert")
        svg_dir = os.path.join(self.h.data, "icons", "hicolor", "scalable", "apps")
        os.makedirs(svg_dir)
        with open(os.path.join(svg_dir, "vector.svg"), "w") as f:
            f.write('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
                    '<rect x="0" y="0" width="64" height="64" fill="#000000" opacity="0.2"/>'
                    '<circle cx="32" cy="32" r="16" fill="#28a050"/></svg>')
        self.desktop("vector", "vector")
        img = self.tile("vector", "--shape", "original", "--whole")
        self.assertEqual(self.corners(img), [0] * 4, "the faint black layer is removed")
        self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], (0x28, 0xA0, 0x50), 8))
        l, t, r, b = self.assert_centred(img)
        self.assertAlmostEqual((r - l) / PX, 0.5, delta=0.05)

    # --- every app ---
    def test_tile_all(self):
        """--tile-all draws each installed app once, names files safely, keeps existing ones,
        and one broken icon doesn't stop the rest."""
        self.desktop("odd name+1", "roundapp")
        with open(os.path.join(self.icons, "broken.png"), "w") as f:
            f.write("not a png")
        self.desktop("broken", "broken")
        out = os.path.join(self.h.cache, "slate", "tiles")
        os.makedirs(out)
        with open(os.path.join(out, "squareapp.png"), "w") as f:
            f.write("already drawn")
        code, log = run([sys.executable, SCRIPT, "--tile-all", out, str(PX)], env=self.h.env)
        self.assertEqual(code, 0, log)
        self.assertIn("broken:", log)
        self.assertEqual(sorted(os.listdir(out)),
                         ["firefox.png", "odd_name_1.png", "offcentre.png", "roundapp.png", "squareapp.png"])
        with open(os.path.join(out, "squareapp.png")) as f:
            self.assertEqual(f.read(), "already drawn", "an existing tile is redrawn")
        for n in ("firefox", "odd_name_1", "roundapp"):
            self.assertEqual(Image.open(os.path.join(out, n + ".png")).size, (PX, PX))
        self.assertFalse([f for f in os.listdir(out) if f.endswith(".tmp")], "temp files left behind")

    def test_tile_files_from_given_pictures(self):
        """--tile-files (Slate Software): each app drawn from the picture given for it, in the
        style of the folder above (here: circle), once; ids that aren't app ids and
        missing pictures are passed over, and a broken one doesn't stop the rest."""
        out = os.path.join(self.h.cache, "slate", "tiles", "circle", "flathub")
        broken = os.path.join(self.icons, "broken.png")
        with open(broken, "w") as f:
            f.write("not a png")
        lines = "".join(f"{a}\t{p}\n" for a, p in (
            ("org.example.Square", os.path.join(self.icons, "squareapp.png")),
            ("org.example.Broken", broken),
            ("../escape", os.path.join(self.icons, "roundapp.png")),
            ("org.example.Missing", os.path.join(self.icons, "nothing.png")),
            ("org.example.Round", os.path.join(self.icons, "roundapp.png"))))
        code, log = run([sys.executable, SCRIPT, "--tile-files", out, str(PX)], env=self.h.env, input=lines)
        self.assertEqual(code, 0, log)
        self.assertIn("org.example.Broken:", log)
        self.assertEqual(sorted(os.listdir(out)), ["colours.json", "org.example.Round.png", "org.example.Square.png"])
        with open(os.path.join(out, "colours.json")) as f:
            noted = json.load(f)
        self.assertEqual(sorted(noted), ["org.example.Round", "org.example.Square"], "their colours (for tiles in each icon's colour)")
        sq = Image.open(os.path.join(out, "org.example.Square.png"))
        self.assertEqual(sq.size, (PX, PX))
        self.assertEqual(sq.getpixel((0, 0))[3], 0, "not drawn in the folder's style (a circle: corners cut away)")
        # Again: what's drawn is kept
        with open(os.path.join(out, "org.example.Round.png"), "w") as f:
            f.write("already drawn")
        self.ok([sys.executable, SCRIPT, "--tile-files", out, str(PX)], env=self.h.env, input=lines)
        with open(os.path.join(out, "org.example.Round.png")) as f:
            self.assertEqual(f.read(), "already drawn")

    def test_slate_settings_has_its_own_icon(self):
        """Slate Settings' icon is Slate's own file, found without any desktop entry or icon
        theme copy (someone who didn't install Slate has neither in their home)."""
        out = os.path.join(self.h.cache, "slate", "tiles")
        self.ok([sys.executable, SCRIPT, "--tile", "slate-settings", os.path.join(out, "slate-settings.png"), str(PX)], env=self.h.env)
        self.assertFalse(os.path.exists(os.path.join(out, "slate-settings.png.placeholder")), "drawn as a placeholder")
        # An old blank tile of it, with no mark, from before: drawn again
        self.desktop("slate-settings", "slate-settings")
        with open(os.path.join(out, "slate-settings.png"), "w") as f:
            f.write("an old blank tile")
        self.ok([sys.executable, SCRIPT, "--tile-all", out, str(PX)], env=self.h.env)
        self.assertEqual(Image.open(os.path.join(out, "slate-settings.png")).size, (PX, PX))

    def test_an_icon_that_arrives_later_is_drawn_then(self):
        """An app whose icon wasn't there when its tile was first drawn (Slate Settings' icon,
        put in /usr/local by the installer after someone new first logged in): the placeholder
        is drawn again at the next run, with the icon, rather than kept for good."""
        self.desktop("later", "laterapp")
        out = os.path.join(self.h.cache, "slate", "tiles")
        self.ok([sys.executable, SCRIPT, "--tile-all", out, str(PX)], env=self.h.env)
        placeholder = Image.open(os.path.join(out, "later.png")).convert("RGBA").tobytes()
        # (the icon arrives in a system folder, as the installer's shared one does)
        shared = os.path.join(self.sys, "icons", "hicolor", "256x256", "apps")
        os.makedirs(shared, exist_ok=True)
        Image.new("RGBA", (256, 256), (200, 40, 40, 255)).save(os.path.join(shared, "laterapp.png"))
        self.ok([sys.executable, SCRIPT, "--tile-all", out, str(PX)], env=self.h.env)
        drawn = Image.open(os.path.join(out, "later.png")).convert("RGBA").tobytes()
        self.assertNotEqual(drawn, placeholder, "the placeholder was kept after the icon arrived")
        self.assertFalse([f for f in os.listdir(out) if f.endswith(".placeholder")], "still marked as a placeholder")

    def test_tile_all_folder_style(self):
        out = os.path.join(self.h.cache, "slate", "tiles", "circle-whole")
        self.ok([sys.executable, SCRIPT, "--tile-all", out, str(PX), "--shape", "square"], env=self.h.env)
        img = Image.open(os.path.join(out, "roundapp.png"))
        self.assertEqual(img.getpixel((PX // 2, 1))[3], 0, "not drawn whole")

    # --- Settings' preview ---
    def test_preview(self):
        out = os.path.join(self.h.cache, "slate", "tiles", "preview")
        self.ok([sys.executable, SCRIPT, "--preview", out, str(PX)], env=self.h.env)
        want = sorted(f"{s}-{f}.png" for s in ("tile", "squircle", "circle", "square", "original")
                      for f in ("fill", "whole"))
        self.assertEqual(sorted(os.listdir(out)), sorted(want + ["colour.txt"]))
        for f in want:
            self.assertEqual(Image.open(os.path.join(out, f)).size, (PX, PX), f)
        # firefox is the first preview app, drawn with the round blue icon
        self.assertTrue(close(Image.open(os.path.join(out, "square-fill.png")).getpixel((1, 1))[:3], BLUE))
        with open(os.path.join(out, "colour.txt")) as f:
            colour = f.read()
        self.assertRegex(colour, r"^#[0-9a-f]{6}\n$")
        rgb = tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5))
        self.assertTrue(close(rgb, BLUE), f"the preview icon's color is {colour.strip()}")

    def test_preview_without_apps(self):
        """No preview app installed: blank tiles, and an empty colour."""
        os.remove(os.path.join(self.apps, "firefox.desktop"))
        out = os.path.join(self.h.dir, "preview")
        self.ok([sys.executable, SCRIPT, "--preview", out, str(PX)], env=self.h.env)
        with open(os.path.join(out, "colour.txt")) as f:
            self.assertEqual(f.read(), "\n")
        img = Image.open(os.path.join(out, "tile-fill.png"))
        self.assertTrue(close(img.getpixel((PX // 2, PX // 2))[:3], INNER_FILL, 2))

    # --- colours.json ---
    def test_colours(self):
        tiles = os.path.join(self.h.dir, "tiles")
        self.tile("roundapp", "--shape", "original", "--whole", folder="tiles")
        self.tile("squareapp", "--shape", "original", "--whole", folder="tiles")
        with open(os.path.join(tiles, "notes.txt"), "w") as f:
            f.write("ignored")
        out = os.path.join(self.h.dir, "colours.json")
        self.ok([sys.executable, SCRIPT, "--colours", tiles, out], env=self.h.env)
        with open(out) as f:
            got = json.load(f)
        self.assertEqual(sorted(got), ["roundapp", "squareapp"])
        for name, want in (("roundapp", BLUE), ("squareapp", RED)):
            c = got[name]["c"]
            self.assertTrue(close(tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)), want), f"{name}: {c}")
            self.assertEqual(got[name]["t"], int(os.path.getmtime(os.path.join(tiles, name + ".png"))))
        # Unchanged icons keep their entry (not read again)
        got["roundapp"]["c"] = "#123456"
        with open(out, "w") as f:
            json.dump(got, f)
        self.ok([sys.executable, SCRIPT, "--colours", tiles, out], env=self.h.env)
        with open(out) as f:
            self.assertEqual(json.load(f)["roundapp"]["c"], "#123456")

    def test_usage(self):
        code, out = run([sys.executable, SCRIPT], env=self.h.env)
        self.assertNotEqual(code, 0)
        self.assertIn("Usage: appicon.py --tile", out)
        code, out = run([sys.executable, SCRIPT, "--tile", "roundapp"], env=self.h.env)
        self.assertNotEqual(code, 0)


DIRS = """
import importlib.util, json, sys
out = {}
for name in sys.argv[1:]:
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), name)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    out[name] = m.data_dirs()
print(json.dumps(out))
"""


class DataDirs(unittest.TestCase):
    """Where apps and icons are looked for (data_dirs), written in appicon.py and spaces.py
    (which the assistant's app list uses): both copies agree, and both find Flatpak's exports
    where Flatpak's own FLATPAK_USER_DIR and FLATPAK_SYSTEM_DIR put them. The tests' scratch
    home moves everyone's Flatpaks away, so they never see the computer's own apps: they
    used to, from /var/lib/flatpak, which was always looked in. Bug, 2026-11-19."""
    FILES = [slate.path("shell", "scripts", "appicon.py"), slate.path("shell", "scripts", "spaces.py")]
    CASES = [
        ({}, ["/h/.local/share", "/h/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share",
              "/usr/local/share", "/usr/share"]),
        ({"XDG_DATA_HOME": "/d", "XDG_DATA_DIRS": "/nix/share:/usr/share"},
         ["/d", "/d/flatpak/exports/share", "/var/lib/flatpak/exports/share", "/nix/share", "/usr/share"]),
        ({"FLATPAK_USER_DIR": "/fu", "FLATPAK_SYSTEM_DIR": "/fs", "XDG_DATA_DIRS": "/fs/exports/share:/usr/share"},
         ["/h/.local/share", "/fu/exports/share", "/fs/exports/share", "/usr/share"]),
    ]

    def dirs(self, extra):
        # (a home of its own: spaces.py makes its folders there as it loads. "/h" in CASES)
        home = tempfile.mkdtemp(prefix="slate-test-")
        self.addCleanup(shutil.rmtree, home, True)
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "PYTHONDONTWRITEBYTECODE": "1", **extra}
        code, out = run([sys.executable, "-c", DIRS] + self.FILES, env=env)
        self.assertEqual(code, 0, out)
        return {f: [d.replace(home, "/h", 1) if d.startswith(home) else d for d in dirs]
                for f, dirs in json.loads(out).items()}

    def test_every_copy_agrees(self):
        for extra, want in self.CASES:
            with self.subTest(env=extra):
                got = self.dirs(extra)
                for f in self.FILES:
                    self.assertEqual(got[f], want, os.path.basename(f))

    def test_the_tests_never_see_the_computers_apps(self):
        h = slate.ScratchHome()
        self.addCleanup(h.cleanup)
        for f, dirs in self.dirs(h.env).items():
            self.assertFalse([d for d in dirs if d.startswith("/var/lib/flatpak")], os.path.basename(f))
