"""When the menu bar's contents don't fit (plans/menubar-length.md): the line slims itself,
cheapest thing first, and takes it back when there's room to spare. Driven by squeezing the
line (the test hook), since the screen can't change size mid-session."""
import json

from live import LiveCase


class BarLength(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("barClockDate", "barClockSeconds", "barValueWifi", "barValueVolume"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.squeeze(0))
        self.squeeze(0)

    def bar(self):
        return json.loads(self.ipc("test", "state"))["bar"]

    def squeeze(self, px):
        self.ipc("test", "arrange", "squeeze", str(px), "", "")
        self.s.settle(0.35)
        return self.bar()

    def first_squeeze_giving(self, n, start=0, stop=1500, step=20):
        """The least squeeze (to the step) at which at least n things have been given up."""
        for px in range(start, stop, step):
            if len(self.squeeze(px)["gives"]) >= n:
                return px
        self.fail(f"squeezing the line by up to {stop} never gave up {n} thing(s)")

    def test_everything_fits_to_start_with(self):
        st = self.bar()
        self.assertEqual(st["gives"], [])
        self.assertNotEqual(st["line"]["wifi"]["text"], "")

    def test_text_goes_longest_first_then_the_clocks_date(self):
        self.config("barClockDate", "true")
        self.config("barClockSeconds", "false")
        st = self.squeeze(1400)             # far too short for anything to stay as it was
        gives = [g for g in st["gives"] if not g.startswith(("tuck:", "over:"))]     # (tucking and More come after: their own tests)
        texts = [g for g in gives if g.startswith("text:")]
        self.assertGreaterEqual(len(texts), 2, gives)
        self.assertEqual(gives[-1], "clock:date")
        self.assertEqual(st["gives"][:len(gives)], gives, "something tucked away before the text and the clock's date had gone")
        self.assertEqual(gives[:len(texts)], texts, "text beside icons goes before the clock's date")
        # longest first: Wi-Fi's "Offline" before the volume's "0%"
        self.assertLess(gives.index("text:wifi"), gives.index("text:volume"))
        for g in texts:
            self.assertEqual(st["line"][g[5:]]["text"], "", f"{g[5:]} still shows its text")
        self.assertNotRegex(st["clock"], r"[A-Za-z]{3} \d", "the clock still shows its date")
        self.assertRegex(st["clock"], r"\d{1,2}:\d\d")

    def test_the_window_title_goes_first(self):
        """With a window to name: its title is the first thing to go, and its icon stays."""
        self.ipc("settings", "open")
        self.s.wait(lambda st: st["settings"]["open"], what="Settings")
        self.s.settle(0.8)
        self.assertTrue(self.bar()["line"]["windowtitle"]["visible"], "no window title to begin with")
        self.first_squeeze_giving(1)
        st = self.bar()
        self.assertEqual(st["gives"], ["title"])
        self.assertFalse(st["line"]["windowtitle"]["visible"])
        self.assertTrue(st["line"]["windowicon"]["visible"], "the window's icon went with its title")
        self.squeeze(0)
        self.ipc("settings", "close")

    def test_the_clock_sheds_its_seconds_last(self):
        self.config("barClockDate", "true")
        self.config("barClockSeconds", "true")
        st = self.squeeze(1400)
        self.assertEqual([g for g in st["gives"] if not g.startswith(("tuck:", "over:"))][-2:], ["clock:date", "clock:seconds"])
        self.assertRegex(st["clock"], r"^\d{1,2}:\d\d( [AP]M)?$")

    def test_one_step_at_a_time_and_back_with_room_to_spare(self):
        px = self.first_squeeze_giving(1)
        self.assertEqual(len(self.bar()["gives"]), 1, "more than one thing went at the first step")
        first = self.bar()["gives"][0]
        # A little room back isn't enough: it stays given up (no coming and going at the edge)
        self.assertEqual(self.squeeze(px - 10)["gives"], [first])
        # Room to spare: it's back
        self.assertEqual(self.squeeze(max(0, px - 80))["gives"], [])

    def test_nothing_slims_while_arranging(self):
        self.squeeze(1400)
        self.assertNotEqual(self.bar()["gives"], [])
        self.ipc("test", "arrange", "start", "", "", "")
        self.s.settle(0.6)
        self.assertEqual(self.bar()["gives"], [])
        self.ipc("test", "arrange", "done", "", "", "")
        self.s.settle(0.6)
        self.assertNotEqual(self.bar()["gives"], [])

    # ---- collapse modes: Never, Always, When needed -------------------------------------------
    def layout(self):
        return self.bar()["layout"]

    def where(self, item):
        for i, e in enumerate(self.layout()):
            if not isinstance(e, str) and item in e["items"]:
                return i
        self.fail(f"{item} isn't in the arrangement")

    def test_containers_collapse_when_needed_to_start_with(self):
        for e in self.layout():
            if not isinstance(e, str):
                self.assertEqual(e["collapse"], "needed", e["items"])
                self.assertFalse(e["tuck"], e["items"])

    def test_a_container_tucks_when_needed_and_only_then(self):
        self.addCleanup(lambda: self.ipc("test", "arrange", "reset", "", "", ""))
        at = self.where("wifi")
        self.assertEqual(self.bar()["gives"], [])
        self.assertTrue(self.bar()["line"]["wifi"]["visible"])
        st = self.squeeze(1400)
        self.assertIn(f"tuck:{at}", st["gives"])
        # (after the text and the clock's date: tucking is the last thing the line tries)
        self.assertGreater(st["gives"].index(f"tuck:{at}"), st["gives"].index("clock:date"))
        self.s.settle(0.6)
        self.assertFalse(self.bar()["line"]["wifi"]["visible"], "the status icons didn't tuck away")
        self.squeeze(0)
        self.s.settle(0.6)
        self.assertTrue(self.bar()["line"]["wifi"]["visible"], "they didn't come back with room to spare")

    def test_never_and_always(self):
        self.addCleanup(lambda: self.ipc("test", "arrange", "reset", "", "", ""))
        at = self.where("wifi")
        self.ipc("test", "arrange", "collapse", str(at), "never", "")
        self.s.settle(0.5)
        self.assertEqual(self.layout()[at]["collapse"], "never")
        st = self.squeeze(1400)
        self.assertNotIn(f"tuck:{at}", st["gives"])
        # (what's left of it on the bar shows in full: nothing's behind a button)
        self.assertTrue(st["line"]["wifi"]["visible"] or "wifi" in st["overflowed"], "a container set to Never tucked")
        self.squeeze(0)
        self.ipc("test", "arrange", "collapse", str(at), "always", "")
        self.s.settle(0.8)
        self.assertEqual(self.layout()[at]["collapse"], "always")
        self.assertTrue(self.layout()[at]["tuck"])
        self.assertFalse(self.bar()["line"]["wifi"]["visible"], "a container set to Always shows its things with room to spare")

    def test_a_saved_arrangement_with_a_button_is_always(self):
        """From before there were modes: a container with a collapse button among its items."""
        self.addCleanup(lambda: self.ipc("test", "arrange", "reset", "", "", ""))
        at = self.where("wifi")
        self.ipc("test", "arrange", "tuck", str(at), "true", "")
        self.s.settle(0.5)
        self.assertEqual(self.layout()[at]["collapse"], "always")
        self.assertEqual(self.layout()[at]["items"][-1], "tuck")

    # ---- overflow: things leave the bar for More ------------------------------------------------
    ORDER = ["tray", "clipboard", "screenshot", "gamemode", "keyboard", "bluetooth", "windowtitle", "windowicon", "chalk",
             "spaces", "apps", "notifications", "battery", "wifi", "volume", "windowmode", "workspaces"]

    def test_more_is_only_there_when_something_is_in_it(self):
        st = self.bar()
        self.assertEqual(st["overflowed"], [])
        self.assertFalse(st["line"]["more"]["visible"], "More shows with nothing in it")
        st = self.squeeze(1400)
        self.assertNotEqual(st["overflowed"], [])
        self.assertTrue(st["line"]["more"]["visible"], "things have left the bar and there's no More to find them in")

    def test_things_leave_in_order_and_some_stay(self):
        st = self.squeeze(1400)
        over = st["overflowed"]
        self.assertGreaterEqual(len(over), 2, st["gives"])
        self.assertEqual(over, [i for i in self.ORDER if i in over], "they left out of order")
        # (one at a time: what's left is the end of the order, none skipped)
        on_bar = [i for i in self.ORDER if st["line"][i]["visible"]]
        if on_bar:
            self.assertLess(max(self.ORDER.index(i) for i in over), min(self.ORDER.index(i) for i in on_bar),
                            "something stayed on the bar while a thing minded more had left")
        for i in over:
            self.assertFalse(st["line"][i]["visible"], f"{i} is in More and on the bar")
        for i in ("power", "clock", "control"):
            self.assertNotIn(i, over)
            self.assertTrue(st["line"][i]["visible"], f"{i} left the bar")
        # ...after everything gentler has been tried
        first = st["gives"].index("over:" + over[0])
        self.assertTrue(all(not g.startswith("over:") for g in st["gives"][:first]))
        self.assertIn("clock:date", st["gives"][:first])

    def test_they_come_back_in_reverse(self):
        """With room back, the last to leave is the first to return: what's still in More is
        always the start of what was. (A single small thing rarely waits there alone: More's
        own button takes about the room it would, so the last two tend to come back together.)"""
        px = 600
        while len(self.squeeze(px)["overflowed"]) < 3:
            px += 40
            self.assertLess(px, 1500, "squeezing never sent three things to More")
        were = self.bar()["overflowed"]
        seen = {len(were)}
        while px > 0:
            px = max(0, px - 20)
            now = self.squeeze(px)["overflowed"]
            self.assertEqual(now, were[:len(now)], f"at {px}: what's left in More isn't the first of what was there ({were})")
            seen.add(len(now))
        self.assertEqual(self.bar()["overflowed"], [])
        self.assertGreater(len(seen), 2, "everything came back at once rather than as room allowed")

    def test_the_more_panel_lists_them_and_they_still_work(self):
        st = self.squeeze(1400)
        self.assertIn("volume", st["overflowed"])
        names = [r[0] for r in st["more"]]
        self.assertIn("Volume", names)
        self.assertNotIn("Clock", names)
        self.ipc("bar", "panel", "more")
        self.s.wait(lambda st: st["popout"] == "more", what="the More panel")
        # A row does what the thing does on the bar: Volume's opens its panel
        self.ipc("test", "arrange", "more", "volume", "", "")
        self.s.wait(lambda st: st["popout"] == "volume", what="the volume panel, from More")
        self.ipc("popout", "close")

    def test_more_cant_be_taken_off_the_bar(self):
        self.addCleanup(lambda: self.ipc("test", "arrange", "reset", "", "", ""))
        self.ipc("test", "arrange", "start", "", "", "")
        self.s.settle(0.6)
        self.assertTrue(self.bar()["line"]["more"]["visible"], "More isn't there to be moved while the bar's arranged")
        self.ipc("test", "arrange", "shown", "more", "false", "")
        self.s.settle(0.4)
        self.assertTrue(self.bar()["line"]["more"]["visible"])
        # (but it moves like anything else)
        self.ipc("test", "arrange", "moveItem", "more", "0", "-1")
        self.s.settle(0.5)
        self.assertEqual(self.layout()[0]["items"], ["more"])
        self.ipc("test", "arrange", "done", "", "", "")

