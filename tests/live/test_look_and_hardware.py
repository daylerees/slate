"""Things Slate adapts to: the hardware a computer has (or hasn't), how dates are written, and
whether anything is rounded."""
import json
import os
import re
import shutil

from live import LiveCase


def lua(case, name):
    """A global of Hyprland's Lua config, as it is now."""
    out = os.path.join(case.s.h.runtime, "lua-value")
    if os.path.exists(out):
        os.remove(out)
    case.s.hyprctl("dispatch", f'function() local f = io.open("{out}", "w"); f:write(tostring({name})); f:close() end')
    for _ in range(20):
        if os.path.exists(out):
            return open(out).read()
        case.s.settle(0.1)
    case.fail(f"couldn't read {name} from Hyprland")


def settings_in_hyprland(case, after=-1):
    """Wait until Slate's settings are in Hyprland: no push or reading back still to come (and
    at least one push after `after`, a count from the state), and Hyprland has run the last push
    (it keeps the count, Config.testHypr)."""
    st = case.wait(lambda st: not st["hypr"]["busy"] and st["hypr"]["pushes"] > after,
                   "Slate's settings to go to Hyprland", timeout=15)
    want = str(st["hypr"]["pushes"])
    for _ in range(50):
        if lua(case, "SLATE_TEST_PUSHES") == want:
            return st
        case.s.settle(0.2)
    case.fail(f"Hyprland didn't get Slate's settings (push {want}; it has {lua(case, 'SLATE_TEST_PUSHES')})")


class Hardware(LiveCase):
    """The bar shows what the computer has. The tests' computer has no Wi-Fi, sound card or
    battery; it pretends the first two (Config.pretendWifi/pretendAudio), so the bar under test
    is the usual one, and these take them away again."""

    def line(self):
        return json.loads(self.ipc("test", "state"))["bar"]["line"]

    def test_no_wifi_no_wifi_item(self):
        self.addCleanup(lambda: self.ipc("test", "hardware", "wifi", "true"))
        self.assertTrue(self.line()["wifi"]["visible"])
        self.ipc("test", "hardware", "wifi", "false")
        self.wait(lambda st: not st["bar"]["line"]["wifi"]["visible"],
                  "the Wi-Fi item to go (it shows on a computer with no network hardware)")
        self.ipc("test", "hardware", "wifi", "true")
        self.wait(lambda st: st["bar"]["line"]["wifi"]["visible"], "the Wi-Fi item to come back")

    def test_no_sound_no_volume_item(self):
        self.addCleanup(lambda: self.ipc("test", "hardware", "audio", "true"))
        self.assertTrue(self.line()["volume"]["visible"])
        self.ipc("test", "hardware", "audio", "false")
        self.wait(lambda st: not st["bar"]["line"]["volume"]["visible"],
                  "the volume item to go (it shows with nothing to turn up or down)")

    def test_no_battery_still_a_way_into_the_power_panel(self):
        # (no battery here: the item stays, as a power button with no percentage)
        item = self.line()["battery"]
        self.assertTrue(item["visible"], "with no battery there's no way to the power panel from the bar")
        self.assertEqual(item["text"], "")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        self.ipc("bar", "panel", "battery")
        self.wait(lambda st: st["popout"] == "battery", "the power panel")


class Formats(LiveCase):
    def test_the_bars_date_follows_the_date_format(self):
        self.keep_setting("dateFormat")
        self.keep_setting("barClockDate")
        self.config("barClockDate", "true")
        for fmt, shape in (("dmy", r"^[A-Z][a-z]{2} \d{1,2} [A-Z][a-z]{2}  "),         # Mon 5 Jan
                           ("mdy", r"^[A-Z][a-z]{2}, [A-Z][a-z]{2} \d{1,2}  "),        # Mon, Jan 5
                           ("ymd", r"^\d{4}-\d{2}-\d{2}  ")):                          # 2026-01-05
            self.config("dateFormat", fmt)
            self.wait(lambda st: re.search(shape, st["bar"]["clock"]), f"the bar's date written {fmt}")


class Rounding(LiveCase):
    def rounding(self):
        return self.s.hyprctl("getoption", "decoration:rounding", json_out=True).get("int")

    def test_rounded_elements_off_squares_the_windows_too(self):
        self.keep_setting("roundedElements")
        # (before the next test: Slate has read the rounding back from Hyprland, Config.windowRounding)
        self.addCleanup(lambda: self.wait(lambda st: not st["hypr"]["busy"] and st["hypr"]["rounding"] == self.rounding(),
                                          "Slate to read the rounding back", timeout=15))
        self.config("roundedElements", "true")
        settings_in_hyprland(self)
        usual = self.rounding()
        self.assertGreater(usual, 0)
        self.config("roundedElements", "false")
        for _ in range(30):
            if self.rounding() == 0:
                break
            self.s.settle(0.2)
        self.assertEqual(self.rounding(), 0, "windows kept their rounded corners with Rounded UI elements off")
        self.config("roundedElements", "true")
        for _ in range(30):
            if self.rounding() == usual:
                break
            self.s.settle(0.2)
        self.assertEqual(self.rounding(), usual, "windows didn't get their corners back")


class IconColours(LiveCase):
    """Settings → Icons → Tiles in the icon's colour: each icon's colour is noted after its
    tiles are drawn, and Slate reads it, even when the style's tiles folder didn't exist yet
    (a first login, or a style never used before). The file appearing in a folder made after
    Slate began watching for it went unnoticed, so the tiles stayed in the theme's colour."""
    def test_a_new_styles_colours_arrive(self):
        self.keep_setting("iconShape")
        self.addCleanup(lambda: self.wait(lambda st: not st["icons"]["busy"], "the tiles to be drawn again", timeout=60))
        self.config("iconTileColour", "true")
        folder = os.path.join(self.s.h.cache, "slate", "tiles", "squircle-whole")
        shutil.rmtree(folder, ignore_errors=True)        # a style never used
        self.config("iconShape", "squircle")
        self.wait(lambda st: st["icons"]["busy"], "the tiles to start being drawn", timeout=10)
        st = self.wait(lambda st: not st["icons"]["busy"], "the tiles and their colors", timeout=60)
        self.assertTrue(os.path.exists(os.path.join(folder, "colours.json")), "the icons' colors weren't noted")
        self.assertGreater(st["icons"]["colours"], 0, "Slate didn't read the icons' colors for a new tile style")


class Shadows(LiveCase):
    """Settings → Appearance → Shadows: off takes Hyprland's shadows under floating windows away
    too, and on puts them back."""
    def shadow(self):
        o = self.s.hyprctl("getoption", "decoration:shadow:enabled", json_out=True)
        return int(o.get("bool", o.get("int", 0)))      # (a bool option, reported as "bool")

    def until(self, want):
        for _ in range(30):
            if self.shadow() == want:
                return True
            self.s.settle(0.2)
        return False

    def test_the_switch_reaches_hyprland(self):
        self.keep_setting("shadows")
        # (before the next test: Slate's settings, and its reading back of them, are done with)
        self.addCleanup(lambda: settings_in_hyprland(self))
        self.config("shadows", "true")
        self.assertTrue(self.until(1), "Hyprland's shadows aren't on with Shadows on")
        self.config("shadows", "false")
        self.assertTrue(self.until(0), "Hyprland kept its shadows with Shadows off")
        self.config("shadows", "true")
        self.assertTrue(self.until(1), "Hyprland's shadows didn't come back")

    # Shadow.qml's shadow (shaders/shadow.frag) at d px outside the surface it's moved from, at
    # its darkest 1 (the static test Shadows.test_falloff_is_as_modelled keeps this in step)
    @staticmethod
    def slate_alpha(d, spread, soft):
        soft = max(soft, 0.5)
        t = min(1.0, max(0.0, (d - spread + soft * 0.4) / (soft * 1.4)))
        return (1 - t) ** 2

    # Hyprland's (its shadow.glsl): ((range - d) / range)^render_power, or solid to range if sharp
    @staticmethod
    def hypr_alpha(d, rng, power, sharp):
        if d >= rng:
            return 0.0
        return 1.0 if sharp else ((rng - d) / rng) ** power

    def option(self, name):
        return self.s.hyprctl("getoption", "decoration:shadow:" + name, json_out=True)

    def test_floating_windows_shadow_looks_like_slates(self):
        """Hyprland's shadow under floating windows (Settings, dialogs) is drawn to look like
        Slate's own for the same settings: as dark, as soft, as far out and moved the same way.
        It looked very different once (its own falloff, and darker than Slate's on glass)."""
        for key in ("shadowSoftness", "shadowSpread", "shadowDistance", "shadowDirection", "shadowDarkness",
                    "glass", "lightMode", "shadows"):
            self.keep_setting(key)
        self.addCleanup(lambda: settings_in_hyprland(self))
        # (the fade compared with no distance: moved, the shape itself shows, checked below)
        for key, value in (("glass", "false"), ("lightMode", "false"), ("shadows", "true"), ("shadowDarkness", "0.7"),
                           ("shadowDistance", "0"), ("shadowDirection", "90")):
            self.config(key, value)
        # (softness, spread): the defaults, all soft, a little of both, a hard edge, and a dark
        # band with a short soft edge (it was spread over the whole width, far softer than the
        # panels', 2026-11-15)
        for soft, spread in ((16, 6), (24, 0), (8, 2), (0, 6), (1, 3)):
            with self.subTest(softness=soft, spread=spread):
                self.config("shadowSoftness", str(soft))
                self.config("shadowSpread", str(spread))
                settings_in_hyprland(self)
                rng = int(self.option("range")["int"])
                power = int(self.option("render_power")["int"])
                o = self.option("sharp")
                sharp = bool(int(o.get("bool", o.get("int", 0))))
                colour = self.option("color")
                # (reported as a gradient, "aarrggbb 0deg")
                argb = int(str(colour.get("gradient", colour.get("str", "0"))).split()[0], 16) if "int" not in colour else int(colour["int"])
                alpha = ((argb >> 24) & 0xFF) / 255
                worst = max(abs(self.hypr_alpha(d / 4, rng, power, sharp) * alpha - self.slate_alpha(d / 4, spread, soft) * 0.7)
                            for d in range(0, 4 * (spread + soft + 2)) if not (sharp and abs(d / 4 - spread) < 1))
                self.assertLess(worst, 0.05, f"Hyprland's shadow (range {rng}, power {power}, sharp {sharp}, "
                                             f"alpha {alpha:.2f}) is up to {worst:.2f} off Slate's: {colour}")
                # Moved (direction 90°, 5 px to the left, as Slate's are: Config.shadowDX/DY), the
                # shape itself shows, where Slate's is at full strength: so is Hyprland's (it was
                # lowered to match the faint edge, and Settings' shadow was half the panels')
                self.config("shadowDistance", "5")
                settings_in_hyprland(self)
                c = self.option("color")
                moved = int(str(c.get("gradient", c.get("str", "0"))).split()[0], 16) if "int" not in c else int(c["int"])
                self.assertAlmostEqual(((moved >> 24) & 0xFF) / 255, 0.7, delta=0.01, msg="the moved shadow isn't at full strength")
                off = self.option("offset")
                text = off.get("custom", off.get("vec2", off.get("str", "")))
                nums = [float(n) for n in re.findall(r"-?[\d.]+", str(text))]
                self.assertEqual([round(n) for n in nums[:2]], [-5, 0], f"Hyprland's shadow isn't moved as Slate's: {off}")
                self.config("shadowDistance", "0")
        # No spread or softness, only a distance: still a shadow (the shape, moved), as Slate's
        # are; Hyprland's was switched off, and Settings had none beside panels that had one
        self.config("shadowSoftness", "0")
        self.config("shadowSpread", "0")
        self.config("shadowDistance", "5")
        settings_in_hyprland(self)
        o = self.option("enabled")
        self.assertTrue(bool(int(o.get("bool", o.get("int", 0)))), "no shadow under floating windows with only a distance")
        # With glass, Slate keeps its shadows lighter (below where Hyprland blurs behind its
        # surfaces): floating windows' too, or theirs are the darker ones
        def alpha():
            c = self.option("color")
            return int(str(c.get("gradient", "0")).split()[0], 16) >> 24
        plain = alpha()
        self.config("glass", "true")
        settings_in_hyprland(self)
        self.assertLess(alpha(), plain, "floating windows' shadows stay as dark with glass, Slate's don't")

    def test_a_panels_shadow_moves_with_the_distance(self):
        """A panel under the bar casts its shadow the way every other surface does: a distance
        straight down moves it down, and it doesn't grow at the panel's sides (it used to: the
        distance was added to the spread all round)."""
        from PIL import Image
        for key in ("shadowDistance", "shadowDirection", "glass", "shadows"):
            self.keep_setting(key)
        self.config("glass", "false")
        self.config("shadows", "true")
        self.config("shadowDirection", "0")
        self.ipc("bar", "panel", "calendar")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        shots = {}
        for distance in (0, 16):
            self.config("shadowDistance", str(distance))
            st = self.steady(lambda: json.loads(self.ipc("test", "state"))["popoutBox"], floor=0.6)
            self.assertEqual(json.loads(self.ipc("test", "state"))["popout"], "calendar")
            self.s.settle(0.4)
            shots[distance] = Image.open(self.screenshot(f"panel-shadow-distance-{distance}")).convert("L")
        box = st
        x0, x1, y0, y1 = box["x"], box["x"] + box["width"], box["y"], box["y"] + box["height"]

        def diff(points):
            return sum(abs(shots[0].getpixel(p) - shots[16].getpixel(p)) for p in points) / len(points)
        # Beside the panel, halfway down: the same with the distance as without
        side = [(x, y) for y in range(y0 + box["height"] // 3, y1 - box["height"] // 3, 4)
                for x in list(range(x0 - 40, x0 - 2)) + list(range(x1 + 2, x1 + 40)) if 0 <= x < shots[0].width]
        # Under it, past where it reaches with no distance (spread 6 + softness 16): darker
        below = [(x, y) for y in range(y1 + 24, y1 + 32) for x in range(x0 + 30, x1 - 30, 4)]
        self.assertGreater(diff(below), 3, "the distance didn't move the panel's shadow down")
        self.assertLess(diff(side), 1, "the panel's shadow grew at its sides with a distance straight down")


class HyprlandGetsSettings(LiveCase):
    """Settings that Slate hands to Hyprland's own config (slateApply in slate.lua)."""
    def lua(self, name):
        return lua(self, name)

    def until(self, name, want):
        for _ in range(40):
            if self.lua(name) == want:
                return True
            self.s.settle(0.2)
        return False

    def test_default_file_manager(self):
        """Bug, 2026-11-12: Slate handed the default apps to Hyprland before the apps' entries
        had loaded, so FILE_MANAGER stayed Hyprland's first guess. It's the chosen app's now,
        and still after Hyprland reloads its config."""
        self.keep_setting("defaultFileManager")
        self.config("defaultFileManager", "foot")
        self.assertTrue(self.until("FILE_MANAGER", "foot"), f"FILE_MANAGER is {self.lua('FILE_MANAGER')!r}")
        pushes = self.s.state()["hypr"]["pushes"]
        self.s.hyprctl("reload")
        # (Slate hears of the reload and sends its settings again: wait for them to arrive)
        settings_in_hyprland(self, after=pushes)
        self.assertTrue(self.until("FILE_MANAGER", "foot"), "FILE_MANAGER was lost when Hyprland reloaded")

    def test_pointer_style(self):
        """Settings → Input → Pointer style: Hyprland's cursor theme follows, and "" brings back
        the session's own."""
        self.keep_setting("cursorTheme")
        self.config("cursorTheme", "")
        settings_in_hyprland(self)
        own = self.lua("CURSOR_THEME")
        self.config("cursorTheme", "Adwaita")
        self.assertTrue(self.until("CURSOR_THEME", "Adwaita"), f"CURSOR_THEME is {self.lua('CURSOR_THEME')!r}")
        self.config("cursorTheme", "")
        self.assertTrue(self.until("CURSOR_THEME", own), "the session's own pointer didn't come back")
