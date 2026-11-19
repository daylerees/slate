"""The lock screen for real: it locks, a wrong password is refused and the right one lets you
back in (checked by PAM, with the password tests/container/entry.sh gives the test user), a
preview left open can't get in the way, and the lockout it shows follows faillock.conf."""
import os

from live import LiveCase

PASSWORD = "slate test"            # (tests/container/entry.sh)
CODE = "246810"                    # the second answer the test's own PAM service wants
DEFAULTS = (3, 900, 600)           # pam_faillock's own: deny, fail_interval, unlock_time


class LockCase(LiveCase):
    """Locking and letting go for each test; no tests of its own."""
    def setUp(self):
        super().setUp()
        self.user = self.s.env["USER"]
        self.forget_failures()
        self.addCleanup(self.let_go)

    def forget_failures(self):
        """Wrong passwords so far, forgotten (they're kept by PAM, outside the session)."""
        self.s.run(["faillock", "--user", self.user, "--reset"])

    def let_go(self):
        """Never leave the session locked, or counting wrong passwords, for the tests after."""
        self.forget_failures()
        self.ipc("lock", "faillockConf", "")
        self.ipc("lock", "closePreview")
        if self.s.state()["lock"]["asking"]:
            self.ipc("lock", "cancel")
        self.ipc("lock", "pamService", "", "")
        self.ipc("lock", "autoService", "", "")
        if self.s.state()["lock"]["locked"]:
            self.wait(lambda st: not st["lock"]["busy"], "the last check to end", timeout=15)
            self.ipc("lock", "submit", PASSWORD)
            self.wait(lambda st: not st["lock"]["locked"], "the lock to let go afterwards", timeout=15)

    def lock(self):
        self.ipc("lock", "lock")
        return self.wait(lambda st: st["lock"]["locked"], "the lock")["lock"]

    def answer(self, password):
        """Type a password and press Enter; the lock's state once PAM has answered."""
        self.ipc("lock", "submit", password)
        return self.wait(lambda st: not st["lock"]["busy"] and (st["lock"]["message"] or not st["lock"]["locked"]),
                         "the password to be checked", timeout=15)["lock"]

    def two_questions(self):
        """A PAM service of the test's own that asks twice, as a login with a second factor
        does: the password (pam_unix), then pam_ftp, which asks again (its answer lands in
        PAM_RUSER), and a check that the second answer is CODE."""
        d = self.s.h("pam.d")
        os.makedirs(d, exist_ok=True)
        check = os.path.join(d, "check-code")
        with open(check, "w", encoding="utf-8") as f:
            f.write('#!/bin/sh\n[ "$PAM_RUSER" = "%s" ]\n' % CODE)
        os.chmod(check, 0o755)
        with open(os.path.join(d, "slate-two"), "w", encoding="utf-8") as f:
            f.write("auth required pam_unix.so\n"
                    f"auth required pam_ftp.so users={self.user}\n"
                    f"auth required pam_exec.so quiet {check}\n"
                    "account required pam_permit.so\n")
        self.ipc("lock", "pamService", d, "slate-two")

    def conf(self, name, text):
        """A faillock.conf of the test's own, read in place of /etc/security/faillock.conf."""
        path = self.s.h(name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        self.ipc("lock", "faillockConf", path)
        return path

    def numbers(self, st=None):
        lock = (st or self.s.state())["lock"]
        return (lock["deny"], lock["interval"], lock["unlockTime"])



class Lock(LockCase):
    # ---- Locking and unlocking ----------------------------------------------------------
    def test_wrong_password_stays_locked_and_the_right_one_unlocks(self):
        self.lock()
        st = self.answer("not the password")
        self.assertTrue(st["locked"], "a wrong password unlocked the screen")
        self.assertEqual(st["message"], "That password didn't match · 2 tries left")
        wakes = self.s.state()["wakes"]
        self.ipc("lock", "submit", PASSWORD)
        st = self.wait(lambda st: not st["lock"]["locked"], "the right password to unlock", timeout=15)
        # Unlocked: the clocks that last read the time again (after sleep, the menu bar's showed
        # the old time for up to a minute: its tick is timed on a clock that stops in sleep)
        self.assertGreater(st["wakes"], wakes, "unlocking didn't tell the clocks")

    def test_a_second_question_is_asked_and_answered(self):
        """A login that asks again after the password (a one-time code): the lock shows the
        question, and the next thing typed answers it. It used to stay busy for good."""
        self.two_questions()
        self.lock()
        self.ipc("lock", "submit", PASSWORD)
        st = self.wait(lambda st: st["lock"]["asking"], "the second question", timeout=15)["lock"]
        self.assertFalse(st["busy"], "still busy while it waits for the answer")
        self.assertTrue(st["locked"])
        self.assertNotEqual(st["message"], "", "the question isn't shown")
        self.ipc("lock", "submit", CODE)
        self.wait(lambda st: not st["lock"]["locked"], "the second answer to unlock", timeout=15)

    def test_a_wrong_second_answer_is_refused_kindly(self):
        """The test's check turns a wrong code down through pam_exec, which PAM reports as a
        "System error". That's a refusal, told once: it used to show "Slate couldn't check your
        password" first, then "That password didn't match" once faillock had been read, and on
        a busy computer the first was what you saw (and the test read)."""
        self.two_questions()
        self.lock()
        self.ipc("lock", "submit", PASSWORD)
        self.wait(lambda st: st["lock"]["asking"], "the second question", timeout=15)
        shown = self.s.state()["lock"]["failuresShown"]
        st = self.answer("not the code")
        self.assertTrue(st["locked"], "a wrong second answer unlocked the screen")
        self.assertRegex(st["message"], r"^That password didn't match")
        self.s.settle(0.5)
        st = self.s.state()["lock"]
        self.assertRegex(st["message"], r"^That password didn't match")
        self.assertEqual(st["failuresShown"] - shown, 1, "one wrong answer was told more than once")
        self.assertFalse(self.s.state()["lock"]["asking"])
        # and a fresh attempt starts from the password again
        self.ipc("lock", "submit", PASSWORD)
        self.wait(lambda st: st["lock"]["asking"], "the question again", timeout=15)

    def test_cancelling_the_question_goes_back_to_a_fresh_password(self):
        self.two_questions()
        self.lock()
        self.ipc("lock", "submit", PASSWORD)
        self.wait(lambda st: st["lock"]["asking"], "the second question", timeout=15)
        self.ipc("lock", "cancel")
        st = self.wait(lambda st: not st["lock"]["asking"], "the question to go away")["lock"]
        self.assertFalse(st["busy"])
        self.assertEqual(st["message"], "")
        self.ipc("lock", "pamService", "", "")
        self.ipc("lock", "submit", PASSWORD)
        self.wait(lambda st: not st["lock"]["locked"], "a fresh password to unlock", timeout=15)

    def test_a_preview_left_open_doesnt_take_the_password(self):
        """With a preview open when the screen really locked, the first right password only
        closed the preview ("Welcome back"): the lock stayed, and it had to be typed again."""
        for mode in ("lock", "login"):
            with self.subTest(mode):
                self.ipc("lock", "preview", mode)
                self.wait(lambda st: st["lock"]["previewing"], f"the {mode} preview")
                self.lock()
                self.ipc("lock", "submit", PASSWORD)
                self.wait(lambda st: not st["lock"]["locked"], "one right password to unlock", timeout=10)

    def test_locking_ends_a_preview_and_none_opens_while_locked(self):
        self.ipc("lock", "preview", "lock")
        self.wait(lambda st: st["lock"]["previewing"], "the preview")
        self.assertFalse(self.lock()["previewing"], "the preview was still open under the lock")
        for mode in ("lock", "login"):
            self.ipc("lock", "preview", mode)
        self.s.settle(0.3)
        st = self.s.state()["lock"]
        self.assertFalse(st["previewing"], "a preview opened while the screen was locked")
        self.assertTrue(st["locked"])
        # (and a wrong password is still wrong, a right one still the way out)
        self.assertTrue(self.answer("not the password")["locked"])
        self.ipc("lock", "submit", PASSWORD)
        self.wait(lambda st: not st["lock"]["locked"], "the right password to unlock", timeout=15)
        self.assertFalse(self.s.state()["lock"]["previewing"])

    # ---- Lockout: the numbers are faillock.conf's ------------------------------------------
    def test_lockout_numbers_come_from_faillock_conf(self):
        """Slate once had pam_faillock's defaults written in (3 tries, 15 minutes, 10 minutes):
        where the system set others, the tries left were wrong, and it shut the field and
        counted down a lockout PAM wasn't keeping."""
        self.assertEqual(self.numbers(), DEFAULTS, "the container's faillock.conf sets nothing")
        self.conf("faillock-a.conf", "# deny = 9\n\n  deny = 5   # five tries\nfail_interval=120\n"
                                     "unlock_time = 90\nsilent\ndir = /tmp\ndeny = lots\nfail_interval = 0\n")
        self.wait(lambda st: self.numbers(st) == (5, 120, 90), "faillock.conf's numbers")
        self.conf("faillock-b.conf", "unlock_time = never\n")
        self.wait(lambda st: self.numbers(st) == (3, 900, 0), "unlock_time = never, the rest as they were")
        self.conf("faillock-c.conf", "deny = 0\nunlock_time = 0\n")
        self.wait(lambda st: self.numbers(st) == (0, 900, 0), "deny = 0")
        self.ipc("lock", "faillockConf", self.s.h("no-such-faillock.conf"))
        self.wait(lambda st: self.numbers(st) == DEFAULTS, "the defaults, with no file to read")

    def test_tries_left_and_lockout_follow_faillock_conf(self):
        # (in the preview: the same check, with nothing locked. PAM itself still has the
        # container's own 3 tries, so two wrong passwords is as far as this goes)
        self.conf("faillock-five.conf", "deny = 5\nunlock_time = 90\n")
        self.wait(lambda st: self.numbers(st) == (5, 900, 90), "faillock.conf's numbers")
        self.ipc("lock", "preview", "lock")
        self.wait(lambda st: st["lock"]["previewing"], "the preview")
        st = self.answer("not the password")
        self.assertEqual(st["message"], "That password didn't match · 4 tries left")
        self.assertFalse(st["lockedOut"])

        # Two tries allowed: the second wrong one is a lockout, counted down from 90 seconds
        self.conf("faillock-two.conf", "deny = 2\nunlock_time = 90\n")
        self.wait(lambda st: self.numbers(st) == (2, 900, 90), "faillock.conf's numbers")
        self.ipc("lock", "submit", "still not the password")
        st = self.wait(lambda st: st["lock"]["lockedOut"], "two wrong passwords with deny = 2 to be a lockout", timeout=15)["lock"]
        self.assertRegex(st["message"], r"^Too many tries · you can try again in 1:[0-2]\d$")

        # No lockout at all (deny = 0): the field is back the next time the screen comes up
        self.conf("faillock-none.conf", "deny = 0\n")
        self.wait(lambda st: self.numbers(st) == (0, 900, 600), "faillock.conf's numbers")
        self.ipc("lock", "closePreview")
        self.ipc("lock", "preview", "lock")
        self.wait(lambda st: not st["lock"]["lockedOut"], "no lockout with deny = 0", timeout=15)

        # Never unlocks by itself: no countdown, and the field comes back once an administrator
        # has reset the count
        self.conf("faillock-never.conf", "deny = 2\nunlock_time = 0\n")
        self.wait(lambda st: self.numbers(st) == (2, 900, 0), "faillock.conf's numbers")
        self.ipc("lock", "closePreview")
        self.ipc("lock", "preview", "lock")
        st = self.wait(lambda st: st["lock"]["lockedOut"], "the lockout that never ends by itself")["lock"]
        self.assertEqual(st["message"], "Too many tries · an administrator needs to unlock this account")
        self.forget_failures()
        self.wait(lambda st: not st["lock"]["lockedOut"] and st["lock"]["message"] == "",
                  "the field back after a reset", timeout=15)


class AnotherWayIn(LockCase):
    """A face, a finger or a key (SLT-248's first step): a PAM service of the test's own stands in
    for one, a pam_exec script that says what it's waiting for (as pam_howdy does), waits, then
    lets you in or doesn't. It starts by itself as the screen locks, its words show under the
    field, and the password still works at any moment."""
    def method(self, wait, ok, says="Attempting facial authentication"):
        d = self.s.h("pam.d")
        os.makedirs(d, exist_ok=True)
        script = os.path.join(d, "fake-face")
        with open(script, "w", encoding="utf-8") as f:
            f.write(f'#!/bin/sh\necho "{says}"\nsleep {wait}\nexit {0 if ok else 1}\n')
        os.chmod(script, 0o755)
        with open(os.path.join(d, "slate-face"), "w", encoding="utf-8") as f:
            f.write(f"auth required pam_exec.so stdout {script}\naccount required pam_permit.so\n")
        self.ipc("lock", "autoService", d, "slate-face")

    def test_it_lets_you_in_without_typing(self):
        self.method(wait=2, ok=True)
        self.lock()
        st = self.wait(lambda st: st["lock"]["hint"] != "", "what it's waiting for", timeout=10)["lock"]
        self.assertEqual(st["hint"], "Looking for your face… or type your password")
        self.wait(lambda st: not st["lock"]["locked"], "it to let you in", timeout=15)

    def test_the_password_works_while_it_waits(self):
        self.method(wait=60, ok=True)
        self.lock()
        self.wait(lambda st: st["lock"]["hint"] != "", "it to start looking", timeout=10)
        self.ipc("lock", "submit", PASSWORD)
        st = self.wait(lambda st: not st["lock"]["locked"], "the password to unlock", timeout=15)["lock"]
        self.assertEqual(st["hint"], "", "it was still looking after the password let you in")

    def test_not_you_stays_locked_and_looks_again_when_youre_back(self):
        self.method(wait=1, ok=False)
        refused = self.s.state()["lock"]["failuresShown"]
        st = self.lock()
        st = self.wait(lambda st: st["lock"]["autoGaveUp"], "it to give up", timeout=15)["lock"]
        self.assertTrue(st["locked"])
        self.assertEqual(st["hint"], "")
        self.assertEqual(st["message"], "", "a face that wasn't you said something")
        self.assertEqual(st["failuresShown"], refused, "it counted as a wrong password")
        self.s.settle(3.2)                     # (it looks again no more than every few seconds)
        self.ipc("lock", "activity")
        self.wait(lambda st: st["lock"]["hint"] != "" and not st["lock"]["autoGaveUp"], "it to look again", timeout=10)

    def test_its_words_for_each_way_in(self):
        for says, want in (("Place your finger on the fingerprint reader", "Touch the fingerprint reader, or type your password"),
                           ("Please touch the device.", "Touch your security key, or type your password"),
                           ("Something else entirely", "Something else entirely")):
            with self.subTest(says):
                self.method(wait=30, ok=False, says=says)
                self.lock()
                self.wait(lambda st: st["lock"]["hint"] == want, f"{want!r}", timeout=10)
                self.let_go()
                self.method(wait=30, ok=False, says=says)

    def test_nothing_changes_without_one(self):
        st = self.lock()
        self.s.settle(1.5)
        st = self.s.state()["lock"]
        self.assertEqual((st["hint"], st["autoGaveUp"]), ("", False))
