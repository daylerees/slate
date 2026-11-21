"""Notifications pause while the screen's locked, and for a few seconds after logging in or
unlocking (apps starting up or catching up all at once): nothing pops up or chimes, it all goes
to the history, and urgent ones held back pop up as the pause ends. (Notifications.qml: paused.
Logging in is pretended with `notifications testSettle`; the lock is the real one.) Asked for,
2026-11-21."""
from live import LiveCase
from test_lock import PASSWORD, LockCase


def notify(case, summary, urgent=False):
    case.s.run(["notify-send", "-a", "Tests", "-t", "20000"] + (["-u", "critical"] if urgent else []) + ["--", summary, "Body"])


class AfterLoggingIn(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("notifications", "clear"))

    def test_held_then_the_urgent_ones_pop_up(self):
        before = self.s.state()["notifications"]["history"]
        self.ipc("notifications", "testSettle", "2500")
        self.wait(lambda st: st["notifications"]["paused"], "paused, as just after logging in")
        notify(self, "Everyday")
        notify(self, "Warning", urgent=True)
        st = self.wait(lambda st: st["notifications"]["history"] == before + 2, "both in the history")["notifications"]
        self.assertEqual(st["toasts"], 0, "one popped up while paused")
        self.assertEqual(st["held"], 1, "the urgent one wasn't kept to show afterwards")
        st = self.wait(lambda st: not st["notifications"]["paused"], "the pause to end", timeout=10)
        st = self.wait(lambda st: st["notifications"]["toasts"] == 1, "the urgent one popping up as it ends")["notifications"]
        self.assertEqual(st["held"], 0)
        self.s.settle(0.6)
        self.assertEqual(self.s.state()["notifications"]["toasts"], 1, "the everyday one popped up afterwards too")

    def test_not_paused_otherwise(self):
        self.assertFalse(self.s.state()["notifications"]["paused"], "paused with no reason")
        notify(self, "Hello")
        self.wait(lambda st: st["notifications"]["toasts"] >= 1, "it popping up")


class WhileLocked(LockCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("notifications", "clear"))

    def test_quiet_while_locked_and_just_after(self):
        before = self.s.state()["notifications"]["history"]
        self.lock()
        self.wait(lambda st: st["notifications"]["paused"], "paused while locked")
        notify(self, "While you were away")
        st = self.wait(lambda st: st["notifications"]["history"] == before + 1, "it in the history")["notifications"]
        self.assertEqual(st["toasts"], 0)
        self.assertEqual(self.answer(PASSWORD)["locked"], False, "the lock didn't let go")
        st = self.s.state()["notifications"]
        self.assertTrue(st["paused"], "not paused just after unlocking")
        notify(self, "Catching up")
        self.wait(lambda st: st["notifications"]["history"] == before + 2, "the next one in the history")
        self.assertEqual(self.s.state()["notifications"]["toasts"], 0, "it popped up just after unlocking")
        self.wait(lambda st: not st["notifications"]["paused"], "the pause after unlocking to end", timeout=10)
        self.assertEqual(self.s.state()["notifications"]["toasts"], 0, "the everyday ones popped up afterwards")
        notify(self, "Back to normal")
        self.wait(lambda st: st["notifications"]["toasts"] >= 1, "pop-ups again")
