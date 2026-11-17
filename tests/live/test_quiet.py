"""Do Not Disturb by itself (Settings → Notifications → Quiet by itself; Notifications.qml):
on a schedule (past midnight, on the days chosen), while a window is full screen, and during
calls. It holds pop-ups back as the switch does, and says why. Switching it off by hand lets
notifications through until that reason changes. Apps on the "still let through" list pop up
anyway. (Full screen and calls are pretended here: `notifications testRule`.)"""
import json

from live import LiveCase


class Quiet(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("dndSchedule", "dndFrom", "dndTo", "dndDays", "dndFullscreen", "dndCalls"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.addCleanup(lambda: self.ipc("notifications", "dnd", "false"))
        self.addCleanup(lambda: self.ipc("notifications", "testRule", "fullscreen", "false"))
        self.addCleanup(lambda: self.ipc("notifications", "testRule", "call", "false"))

    def quiet_at(self, time, day):
        return self.ipc("notifications", "quietAt", time, str(day)) == "true"

    def test_the_schedule(self):
        self.config("dndSchedule", "true")
        self.config("dndFrom", "22:00")
        self.config("dndTo", "07:00")
        self.config("dndDays", "weekdays")
        self.assertTrue(self.quiet_at("23:00", 1), "Monday night")
        self.assertTrue(self.quiet_at("06:00", 6), "early Saturday: Friday night's")
        self.assertFalse(self.quiet_at("06:00", 1), "early Monday: Sunday night's, not a weekday's")
        self.assertFalse(self.quiet_at("12:00", 2), "midday")
        self.assertFalse(self.quiet_at("23:30", 6), "Saturday night")
        self.config("dndDays", "weekends")
        self.assertTrue(self.quiet_at("23:30", 6))
        self.config("dndDays", "every")
        self.assertTrue(self.quiet_at("23:00", 3))
        self.config("dndFrom", "09:00")
        self.config("dndTo", "17:00")
        self.assertTrue(self.quiet_at("12:00", 3), "a daytime schedule")
        self.assertFalse(self.quiet_at("18:00", 3))
        self.config("dndSchedule", "false")
        self.assertFalse(self.quiet_at("12:00", 3), "off: never")

    def test_full_screen_holds_pop_ups_back_and_says_why(self):
        self.config("dndFullscreen", "true")
        self.ipc("notifications", "testRule", "fullscreen", "true")
        st = self.wait(lambda st: st["notifications"]["dnd"], "quiet while full screen")["notifications"]
        self.assertFalse(st["dndHand"], "the switch itself was turned on")
        self.assertEqual(st["dndSays"], "while a window is full screen")
        before = st["history"]
        self.s.run(["notify-send", "-a", "Tests", "-t", "20000", "Hello", "While watching"])
        self.wait(lambda st: st["notifications"]["history"] == before + 1, "it went to the history")
        self.s.settle(0.6)
        self.assertEqual(self.s.state()["notifications"]["toasts"], 0, "it popped up while full screen")

        # Off by hand: let through, until the window leaves full screen
        self.ipc("notifications", "dnd", "false")
        self.wait(lambda st: not st["notifications"]["dnd"], "switched off by hand")
        self.ipc("notifications", "testRule", "fullscreen", "false")
        self.ipc("notifications", "testRule", "fullscreen", "true")
        self.wait(lambda st: st["notifications"]["dnd"], "on again the next time")

    def test_calls_and_apps_let_through(self):
        self.config("dndCalls", "true")
        # (a space first: qs ipc strips the brackets from an argument starting with "[")
        self.addCleanup(lambda: self.ipc("config", "set", "dndAllowed", " []"))
        self.ipc("config", "set", "dndAllowed", " " + json.dumps(["Allowed"]))
        self.wait(lambda st: "Allowed" in self.setting("dndAllowed"), "Allowed let through")
        self.ipc("notifications", "testRule", "call", "true")
        st = self.wait(lambda st: st["notifications"]["dnd"], "quiet during a call")["notifications"]
        self.assertEqual(st["dndSays"], "while you're on a call")
        self.s.run(["notify-send", "-a", "Allowed", "-t", "20000", "Hello", "Still let through"])
        self.wait(lambda st: st["notifications"]["toasts"] >= 1, "an allowed app's pop-up")
        self.ipc("notifications", "testRule", "call", "false")
        self.wait(lambda st: not st["notifications"]["dnd"], "the call over")

    def test_rules_off_change_nothing(self):
        self.config("dndFullscreen", "false")
        self.ipc("notifications", "testRule", "fullscreen", "true")
        self.s.settle(0.4)
        self.assertFalse(self.s.state()["notifications"]["dnd"], "full screen with the rule off")
