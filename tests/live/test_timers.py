"""The timers (Settings → Timers; Timers.qml): the drink reminder and the focus timer (a
Pomodoro), on the menu bar, the dock or both. Time is moved on with `timers testAhead`, so
nothing waits a real 25 minutes."""
import json

from live import LiveCase


class Timers(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("drinkReminder", "drinkMinutes", "barShowDrink", "dockShowDrink", "focusTimer", "focusMinutes",
                    "focusBreakMinutes", "focusLongBreakMinutes", "focusRounds", "focusQuiet", "barShowFocus", "dockShowFocus"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("popout", "close"))

    def timers(self):
        return json.loads(self.ipc("timers", "state"))

    def ahead(self, minutes):
        self.ipc("timers", "testAhead", str(int(minutes * 60)))

    def test_a_drink_reminder(self):
        self.config("drinkMinutes", "45")
        self.config("drinkReminder", "true")
        t = self.timers()["drink"]
        self.assertTrue(t["on"])
        self.assertAlmostEqual(t["left"], 45 * 60, delta=5)
        self.assertFalse(t["overdue"])
        self.wait(lambda st: st["bar"]["line"]["drink"]["visible"], "the droplet on the bar")
        self.ahead(46)
        t = self.timers()
        self.assertTrue(t["drink"]["overdue"], "not due after the wait")
        self.assertEqual(t["said"], "Time for a drink")
        # I've had a drink: the next wait
        self.ipc("timers", "drink")
        t = self.timers()["drink"]
        self.assertFalse(t["overdue"])
        self.assertEqual(t["today"], 1)
        self.assertAlmostEqual(t["left"], 45 * 60, delta=5)
        # Off: gone from the bar
        self.config("drinkReminder", "false")
        self.wait(lambda st: not st["bar"]["line"]["drink"]["visible"], "the droplet gone")

    def test_a_focus_round_and_its_breaks(self):
        self.config("focusMinutes", "25")
        self.config("focusBreakMinutes", "5")
        self.config("focusLongBreakMinutes", "15")
        self.config("focusRounds", "2")
        self.config("focusQuiet", "true")
        self.config("focusTimer", "true")
        self.wait(lambda st: st["bar"]["line"]["focus"]["visible"], "the focus timer on the bar")
        self.ipc("timers", "focus", "start")
        t = self.timers()["focus"]
        self.assertEqual(t["phase"], "focus")
        self.assertAlmostEqual(t["left"], 25 * 60, delta=5)
        # Do Not Disturb while focusing, saying why
        st = self.wait(lambda st: st["notifications"]["dnd"], "Do Not Disturb while focusing")
        self.assertEqual(st["notifications"]["dndSays"], "while you focus")
        # Paused: the time holds
        self.ipc("timers", "focus", "pause")
        left = self.timers()["focus"]["left"]
        self.ahead(10)
        self.assertEqual(self.timers()["focus"]["left"], left, "the time moved on while paused")
        self.ipc("timers", "focus", "start")
        # The round ends: a short break, by itself, and Do Not Disturb off
        self.ahead(26)
        t = self.timers()
        self.assertEqual(t["focus"]["phase"], "break")
        self.assertEqual(t["said"], "Time for a break")
        self.wait(lambda st: not st["notifications"]["dnd"], "Do Not Disturb off on the break")
        # The break ends: it waits for you
        self.ahead(6)
        t = self.timers()
        self.assertEqual(t["focus"]["phase"], "idle")
        self.assertEqual(t["said"], "Break's over")
        # The second round of two: a long break
        self.ipc("timers", "focus", "start")
        self.ahead(26)
        t = self.timers()
        self.assertEqual(t["focus"]["phase"], "long")
        self.assertEqual(t["said"], "Time for a longer break")
        self.ipc("timers", "focus", "reset")
        self.assertEqual(self.timers()["focus"]["phase"], "idle")

    def test_on_the_dock_too(self):
        self.config("drinkReminder", "true")
        self.config("focusTimer", "true")
        self.config("dockShowDrink", "true")
        self.config("dockShowFocus", "true")
        kinds = self.wait(lambda st: {"drink", "focus"} <= {s["kind"] for s in st["dock"]["slots"]}, "the timers on the dock")
        # A click: a drink had, and focus started then paused
        self.ahead(50)
        self.assertTrue(self.timers()["drink"]["overdue"])
        self.ipc("test", "dockClick", "drink", "false")
        self.assertFalse(self.timers()["drink"]["overdue"], "a click on the tile didn't count the drink")
        self.ipc("test", "dockClick", "focus", "false")
        self.assertEqual(self.timers()["focus"]["phase"], "focus")
        self.ipc("test", "dockClick", "focus", "false")
        self.assertTrue(self.timers()["focus"]["paused"])
        self.ipc("timers", "focus", "reset")
        # Only on the bar: off the dock
        self.config("dockShowDrink", "false")
        self.wait(lambda st: "drink" not in {s["kind"] for s in st["dock"]["slots"]}, "off the dock")

    def test_the_panels_open(self):
        self.config("drinkReminder", "true")
        self.config("focusTimer", "true")
        for name in ("drink", "focus"):
            with self.subTest(name):
                self.ipc("bar", "panel", name)
                self.wait(lambda st: st["popout"] == name, f"the {name} panel")
                self.ipc("popout", "close")
                self.wait(lambda st: st["popout"] == "", "closed")
