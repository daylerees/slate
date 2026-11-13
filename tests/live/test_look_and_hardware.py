"""Things Slate adapts to: the hardware a computer has (or hasn't), how dates are written, and
whether anything is rounded."""
import json
import os
import re

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
