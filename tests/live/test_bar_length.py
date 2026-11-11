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
        gives = [g for g in st["gives"] if not g.startswith("tuck:")]     # (tucking comes after: its own tests)
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
        self.assertEqual([g for g in st["gives"] if not g.startswith("tuck:")][-2:], ["clock:date", "clock:seconds"])
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
        self.assertTrue(st["line"]["wifi"]["visible"], "a container set to Never tucked")
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

