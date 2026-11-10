"""Hyprbars, the optional title-bar plugin (HyprbarsWatch.qml, Settings → Windows → Title bars).
Slate's own title bars are the default; Hyprbars has to be rebuilt after every Hyprland
update, and until it is, Slate's are used. The session runs with a stand-in for
bin/slate-build-hyprbars (tests/fixtures/live/hyprbars-tool): each test says what it reports,
so nothing is built and no plugin is loaded."""
import os

from live import LiveCase

BASE = {"running": "0.57.2", "runningCommit": "aaaa", "installed": "0.57.2", "installedCommit": "aaaa",
        "loaded": "no", "build": "no", "next": "no", "any": "no", "system": "no", "removed": "no",
        "state": "", "stateFor": "", "error": ""}
LOADED = dict(loaded="yes", build="yes", any="yes")
STALE = dict(any="yes")                      # built, but for another Hyprland


class Hyprbars(LiveCase):
    def setUp(self):
        super().setUp()
        self.dir = os.path.join(self.s.h.state, "slate-test-hyprbars")
        os.makedirs(self.dir, exist_ok=True)
        self.notes = os.path.join(self.s.h.state, "slate", "hyprbars-notes.json")
        for key in ("windowMode", "titleBarStyle"):
            self.keep_setting(key)
        self.addCleanup(self.clean)
        self.clean()

    def clean(self):
        """Nothing built, nothing noted, nothing being asked."""
        self.ipc("power", "cancel")
        self.ipc("config", "set", "titleBarStyle", "slate")
        for name in ("status", "build-result", "calls"):
            p = os.path.join(self.dir, name)
            if os.path.exists(p):
                os.remove(p)
        self.report()
        # (notes are Slate's: cleared the way Remove does it, then that question answered)
        self.ipc("test", "hyprbars", "remove")
        self.s.wait(lambda st: st["asking"] == "Remove Hyprbars?", timeout=8, what="the remove question")
        self.ipc("test", "answer", "true")
        self.s.wait(lambda st: st["asking"] == "" and not st["hyprbarsFallback"], what="a clean start")
        self.s.settle(0.5)
        if os.path.exists(os.path.join(self.dir, "calls")):
            os.remove(os.path.join(self.dir, "calls"))

    def report(self, name="status", **changes):
        """What the stand-in reports from now on; then have Slate look."""
        with open(os.path.join(self.dir, name), "w") as f:
            f.write("".join(f"{k}={v}\n" for k, v in dict(BASE, **changes).items()))
        if name == "status":
            self.ipc("test", "hyprbars", "check")
            self.s.settle(0.6)

    def calls(self):
        p = os.path.join(self.dir, "calls")
        if not os.path.exists(p):
            return []
        with open(p) as f:
            return [l.strip() for l in f if l.strip() and l.strip() not in ("--status", "--adopt")]

    def asking(self, title, timeout=10):
        self.s.wait(lambda st: st["asking"] == title, timeout=timeout, what=f'"{title}" to be asked')

    def answer(self, yes):
        self.ipc("test", "answer", "true" if yes else "false")
        self.s.wait(lambda st: st["asking"] == "", what="the question to close")

    def float_with_hyprbars(self):
        """Hyprbars chosen and in use, on a floating desktop."""
        self.report(**LOADED)
        self.config("windowMode", "floating")
        self.ipc("test", "hyprbars", "choose")
        self.wait(lambda st: st["titleBars"] == "hyprbars", "Hyprbars in use")

    # ---- The default, and choosing Hyprbars ---------------------------------------------
    def test_slates_by_default(self):
        """Nothing built: Slate's title bars, floating works, nothing is asked or built."""
        self.config("windowMode", "floating")
        st = self.s.state()
        self.assertEqual((st["titleBars"], st["hyprbars"], st["asking"]), ("slate", "none", ""))
        self.assertEqual(self.ipc("config", "get", "windowMode"), "floating")
        self.assertEqual(self.calls(), [])

    def test_choosing_asks_then_builds_then_switches(self):
        self.ipc("test", "hyprbars", "choose")
        self.asking("Use Hyprbars?")
        self.assertEqual(self.s.state()["titleBarStyle"], "slate", "switched before it was built")
        self.report("build-result", build="yes", any="yes", state="built", stateFor="0.57.2")
        self.answer(True)
        self.s.wait(lambda st: st["hyprbars"] == "ready", timeout=12, what="the build to finish")
        self.assertEqual(self.calls(), ["build"])
        self.s.wait(lambda st: st["notifications"]["latest"] == "Hyprbars is ready", what="the reload notification")
        self.assertEqual(self.s.state()["titleBars"], "slate", "Hyprbars isn't loaded yet")
        # Hyprland reloads and loads it: the choice takes effect by itself
        self.report(**LOADED)
        self.ipc("test", "hyprbars", "reload")
        self.s.wait(lambda st: st["titleBarStyle"] == "hyprbars" and st["titleBars"] == "hyprbars", what="Hyprbars in use")
        self.assertEqual(self.s.state()["asking"], "", "asked again after it was chosen")

    def test_cancelling_changes_nothing(self):
        self.ipc("test", "hyprbars", "choose")
        self.asking("Use Hyprbars?")
        self.answer(False)
        self.s.settle(1.0)
        st = self.s.state()
        self.assertEqual((st["titleBarStyle"], st["hyprbars"]), ("slate", "none"))
        self.assertEqual(self.calls(), [])

    def test_choosing_when_loaded_switches_at_once(self):
        self.report(**LOADED)
        self.ipc("test", "hyprbars", "choose")
        self.wait(lambda st: st["titleBarStyle"] == "hyprbars", "Hyprbars chosen")
        self.assertEqual(self.s.state()["asking"], "")
        self.assertEqual(self.calls(), [])

    def test_existing_user_keeps_hyprbars(self):
        """Settings from before there was a choice, with Hyprbars working: it stays."""
        self.ipc("test", "hyprbars", "unset")
        self.report(**LOADED)
        self.wait(lambda st: st["titleBarStyle"] == "hyprbars", "Hyprbars kept")

    def test_existing_user_without_a_build(self):
        self.ipc("test", "hyprbars", "unset")
        self.report()
        self.assertEqual(self.s.state()["titleBarStyle"], "slate")

    # ---- After a Hyprland update ----------------------------------------------------------
    def test_out_of_date_falls_back_and_asks(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.s.wait(lambda st: st["titleBars"] == "slate" and st["titleBarStyle"] == "slate" and st["hyprbarsFallback"],
                    what="the switch to Slate's title bars")
        self.assertEqual(self.s.state()["hyprbars"], "stale")
        self.asking("Hyprbars needs rebuilding")
        self.assertEqual(self.calls(), [], "built without being asked")

    def test_rebuild_then_reload_then_switch_back(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.asking("Hyprbars needs rebuilding")
        self.report("build-result", build="yes", any="yes", state="built", stateFor="0.57.2")
        self.answer(True)
        self.s.wait(lambda st: st["hyprbars"] == "ready", timeout=12, what="the build to finish")
        self.assertEqual(self.calls(), ["build"])
        self.s.wait(lambda st: st["notifications"]["latest"] == "Hyprbars is ready", what="the reload notification")
        self.report(**LOADED)
        self.ipc("test", "hyprbars", "reload")
        self.asking("Switch back to Hyprbars?")
        self.assertEqual(self.s.state()["titleBarStyle"], "slate", "switched without asking")
        self.answer(True)
        self.s.wait(lambda st: st["titleBarStyle"] == "hyprbars" and not st["hyprbarsFallback"], what="Hyprbars back")
        # asked once
        self.ipc("test", "hyprbars", "check")
        self.s.settle(2.0)
        self.assertEqual(self.s.state()["asking"], "")

    def test_keep_slates_after_rebuild(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.asking("Hyprbars needs rebuilding")
        self.report("build-result", build="yes", any="yes", state="built", stateFor="0.57.2")
        self.answer(True)
        self.s.wait(lambda st: st["hyprbars"] == "ready", timeout=12, what="the build to finish")
        self.report(**LOADED)
        self.asking("Switch back to Hyprbars?")
        self.answer(False)
        self.s.wait(lambda st: not st["hyprbarsFallback"], what="the fallback to be forgotten")
        self.ipc("test", "hyprbars", "check")
        self.s.settle(2.0)
        st = self.s.state()
        self.assertEqual((st["titleBarStyle"], st["asking"]), ("slate", ""))

    def test_not_now_is_not_asked_again(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.asking("Hyprbars needs rebuilding")
        self.answer(False)
        self.assertEqual(self.calls(), [])
        # Hyprbars chosen again by hand (a restored Space, an edited file): Slate's are used,
        # and the question for this Hyprland isn't repeated
        self.ipc("config", "set", "titleBarStyle", "hyprbars")     # (switched straight back: it never sticks)
        self.s.settle(2.5)
        st = self.s.state()
        self.assertEqual((st["titleBars"], st["titleBarStyle"], st["asking"]), ("slate", "slate", ""))

    def test_out_of_date_but_tiling_asks_nothing(self):
        self.report(**LOADED)
        self.ipc("test", "hyprbars", "choose")
        self.wait(lambda st: st["titleBarStyle"] == "hyprbars", "Hyprbars chosen")
        self.report(**STALE)
        self.s.settle(2.0)
        st = self.s.state()
        self.assertEqual((st["titleBarStyle"], st["asking"], st["hyprbarsFallback"]), ("hyprbars", "", False))
        self.assertEqual(self.calls(), [])
        # …until something floats
        self.config("windowMode", "floating")
        self.asking("Hyprbars needs rebuilding")
        self.assertEqual(self.s.state()["titleBarStyle"], "slate")

    def test_setting_says_hyprbars_but_never_built(self):
        self.config("windowMode", "floating")
        self.ipc("config", "set", "titleBarStyle", "hyprbars")     # (switched straight back: it never sticks)
        self.s.wait(lambda st: st["titleBarStyle"] == "slate", what="Slate's title bars")
        self.s.settle(2.0)
        self.assertEqual(self.s.state()["asking"], "")

    def test_failed_build(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.asking("Hyprbars needs rebuilding")
        self.report("build-result", any="yes", state="failed", stateFor="0.57.2", error="Needs g++, which isn't installed")
        before = self.s.state()["notifications"]["history"]
        self.answer(True)
        self.s.wait(lambda st: st["hyprbars"] == "failed", timeout=12, what="the build to fail")
        self.s.wait(lambda st: st["notifications"]["latest"] == "Hyprbars couldn't be built", what="the failure notification")
        self.assertEqual(self.s.state()["notifications"]["history"], before + 1, "more than one notification")
        self.assertEqual(self.s.state()["titleBars"], "slate")
        # no retry by itself, and no asking again
        self.ipc("test", "hyprbars", "check")
        self.s.settle(2.5)
        self.assertEqual(self.calls(), ["build"])
        self.assertEqual(self.s.state()["asking"], "")

    def test_updated_but_not_restarted_offers_a_rebuild(self):
        self.float_with_hyprbars()
        self.report(installed="0.58.0", installedCommit="bbbb", **LOADED)
        self.s.wait(lambda st: st["notifications"]["latest"] == "Hyprland was updated", what="the offer to rebuild")
        st = self.s.state()
        self.assertEqual((st["titleBars"], st["asking"]), ("hyprbars", ""), "Hyprbars still works until the restart")
        self.assertEqual(self.calls(), [])
        # offered once for that Hyprland
        before = st["notifications"]["history"]
        self.ipc("test", "hyprbars", "check")
        self.s.settle(1.5)
        self.assertEqual(self.s.state()["notifications"]["history"], before)

    def test_waits_for_game_mode(self):
        self.float_with_hyprbars()
        self.report(**STALE)
        self.asking("Hyprbars needs rebuilding")
        self.report("build-result", build="yes", any="yes", state="built", stateFor="0.57.2")
        self.keep_setting("gameMode")
        self.config("gameMode", "true")
        self.wait(lambda st: st["gameMode"], "game mode")
        self.answer(True)
        self.s.settle(2.0)
        self.assertEqual(self.calls(), [], "built during game mode")
        self.config("gameMode", "false")
        self.s.wait(lambda st: st["hyprbars"] == "ready", timeout=12, what="the build after game mode")
        self.assertEqual(self.calls(), ["build"])

    def test_questions_queue(self):
        """A question asked while another shows waits for it, instead of replacing it."""
        self.ipc("test", "hyprbars", "choose")
        self.asking("Use Hyprbars?")
        self.ipc("test", "hyprbars", "remove")
        self.s.settle(2.0)
        self.assertEqual(self.s.state()["asking"], "Use Hyprbars?")
        self.answer(False)
        self.asking("Remove Hyprbars?")
        self.answer(False)

    # ---- Removing ---------------------------------------------------------------------------
    def test_remove_switches_to_slates_at_once(self):
        self.float_with_hyprbars()
        self.ipc("test", "hyprbars", "remove")
        self.asking("Remove Hyprbars?")
        self.assertEqual(self.s.state()["titleBars"], "hyprbars", "switched before the answer")
        self.answer(True)
        self.s.wait(lambda st: st["titleBars"] == "slate" and st["titleBarStyle"] == "slate" and st["hyprbars"] == "none",
                    what="Slate's title bars, and Hyprbars gone")
        self.assertEqual(self.calls(), ["--remove"])
        st = self.s.state()
        self.assertEqual((st["hyprbarsFallback"], st["asking"]), (False, ""), "a switch-back question was left behind")
