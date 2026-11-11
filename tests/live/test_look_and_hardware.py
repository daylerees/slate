"""Things Slate adapts to: the hardware a computer has (or hasn't), how dates are written, and
whether anything is rounded."""
import json

from live import LiveCase


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
        self.s.settle(0.6)
        self.assertFalse(self.line()["wifi"]["visible"], "the Wi-Fi item shows on a computer with no network hardware")
        self.ipc("test", "hardware", "wifi", "true")
        self.s.settle(0.6)
        self.assertTrue(self.line()["wifi"]["visible"])

    def test_no_sound_no_volume_item(self):
        self.addCleanup(lambda: self.ipc("test", "hardware", "audio", "true"))
        self.assertTrue(self.line()["volume"]["visible"])
        self.ipc("test", "hardware", "audio", "false")
        self.s.settle(0.6)
        self.assertFalse(self.line()["volume"]["visible"], "the volume item shows with nothing to turn up or down")

    def test_no_battery_still_a_way_into_the_power_panel(self):
        # (no battery here: the item stays, as a power button with no percentage)
        item = self.line()["battery"]
        self.assertTrue(item["visible"], "with no battery there's no way to the power panel from the bar")
        self.assertEqual(item["text"], "")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        self.ipc("bar", "panel", "battery")
        self.wait(lambda st: st["popout"] == "battery", "the power panel")


class Formats(LiveCase):
    def clock(self):
        return json.loads(self.ipc("test", "state"))["bar"]["clock"]

    def test_the_bars_date_follows_the_date_format(self):
        self.keep_setting("dateFormat")
        self.keep_setting("barClockDate")
        self.config("barClockDate", "true")
        self.config("dateFormat", "dmy")
        self.s.settle(0.4)
        self.assertRegex(self.clock(), r"^[A-Z][a-z]{2} \d{1,2} [A-Z][a-z]{2}  ")       # Mon 5 Jan
        self.config("dateFormat", "mdy")
        self.s.settle(0.4)
        self.assertRegex(self.clock(), r"^[A-Z][a-z]{2}, [A-Z][a-z]{2} \d{1,2}  ")      # Mon, Jan 5
        self.config("dateFormat", "ymd")
        self.s.settle(0.4)
        self.assertRegex(self.clock(), r"^\d{4}-\d{2}-\d{2}  ")                         # 2026-01-05


class Rounding(LiveCase):
    def rounding(self):
        return self.s.hyprctl("getoption", "decoration:rounding", json_out=True).get("int")

    def test_rounded_elements_off_squares_the_windows_too(self):
        self.keep_setting("roundedElements")
        self.addCleanup(lambda: self.s.settle(1.2))
        self.config("roundedElements", "true")
        self.s.settle(1.2)
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
