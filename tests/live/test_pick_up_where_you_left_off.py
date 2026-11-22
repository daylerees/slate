"""Your apps from last time (Settings → Startup Apps; Config.pickUpAtLogin, scripts/spaces.py
session-save / session-restore): the apps kept as you left come back at the next login. With
Always they reopen by themselves; with Ask a notification asks first (Reopen / Not now); with
Never nothing is kept or offered. Logging in is pretended: the apps are kept, marked as kept in
an earlier session, closed, and `test pickUpAtLogin` runs what a login would. Asked for,
2026-11-22."""
import json
import os

from live import LiveCase

TITLE = "Pick up where you left off?"


class PickUp(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("reopenApps", "reopenAppsAfterRestart", "startupApps"):
            self.keep_setting(key)
        self.session = os.path.join(self.s.h.state, "slate", "session.json")
        self.addCleanup(lambda: os.path.exists(self.session) and os.remove(self.session))
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.restored()
        self.close_windows()
        self.addCleanup(self.close_windows)
        self.addCleanup(self.restored)

    def restored(self):
        """Wait for any reopening still going (spaces.py session-restore runs on its own, after the
        test has seen what it wanted): left running, it put windows into the next test's count."""
        for _ in range(150):
            if self.s.run(["pgrep", "-f", "spaces.py session-restore"])[0] != 0:
                return
            self.s.settle(0.2)
        self.fail("a reopening was still going after 30 seconds")

    def where(self):
        """The terminals open, by workspace: {workspace: how many}. (By workspace, not title: an app
        comes back as its launcher entry starts it, a terminal without the title it had.)"""
        out = {}
        for c in self.s.hyprctl("clients", json_out=True):
            if c.get("mapped") and c.get("class") == "foot":
                out[c["workspace"]["id"]] = out.get(c["workspace"]["id"], 0) + 1
        return out

    def kept_from_last_time(self):
        """Two apps on workspaces 2 and 3, kept as if leaving, then closed: a new login's view."""
        for title, ws in (("Kept A", 2), ("Kept B", 3)):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot -T \'%s\' sleep 300", { workspace = "%d silent" })' % (title, ws))
        for _ in range(100):
            if self.where() == {2: 1, 3: 1}:
                break
            self.s.settle(0.2)
        self.assertEqual(self.where(), {2: 1, 3: 1}, "the two apps, on workspaces 2 and 3")
        code, out = self.s.run(["python3", os.path.join(self.s.slate_dir, "scripts", "spaces.py"), "session-save"])
        self.assertEqual(code, 0, out)
        with open(self.session) as f:
            data = json.load(f)
        data["instance"] = "an-earlier-session"
        with open(self.session, "w") as f:
            json.dump(data, f)
        self.close_windows()
        self.assertEqual(self.where(), {})

    def asked(self):
        return any(n["summary"] == TITLE for n in json.loads(self.ipc("notifications", "list") or "[]"))

    def test_always(self):
        self.config("reopenApps", "always")
        self.kept_from_last_time()
        self.ipc("test", "pickUpAtLogin")
        self.wait(lambda st: self.where() == {2: 1, 3: 1}, "the apps back where they were", timeout=40)
        self.assertFalse(self.asked(), "Always asked first")
        self.assertFalse(os.path.exists(self.session), "kept to reopen again")

    def test_ask_then_reopen(self):
        self.config("reopenApps", "ask")
        self.kept_from_last_time()
        self.ipc("test", "pickUpAtLogin")
        self.wait(lambda st: self.asked(), "the question", timeout=15)
        self.s.settle(1.5)
        self.assertEqual(self.where(), {}, "something reopened before you said so")
        self.assertEqual(self.ipc("notifications", "testAct", TITLE, "reopen"), "pressed")
        self.wait(lambda st: self.where() == {2: 1, 3: 1}, "the apps back where they were", timeout=40)

    def test_ask_then_not_now(self):
        self.config("reopenApps", "ask")
        self.kept_from_last_time()
        self.ipc("test", "pickUpAtLogin")
        self.wait(lambda st: self.asked(), "the question", timeout=15)
        self.assertEqual(self.ipc("notifications", "testAct", TITLE, "later"), "pressed")
        self.wait(lambda st: not os.path.exists(self.session), "the kept apps forgotten", timeout=10)
        self.s.settle(1.5)
        self.assertEqual(self.where(), {})

    def test_never(self):
        self.config("reopenApps", "never")
        self.kept_from_last_time()
        self.ipc("test", "pickUpAtLogin")
        self.wait(lambda st: not os.path.exists(self.session), "the kept apps forgotten", timeout=10)
        self.s.settle(1.5)
        self.assertFalse(self.asked(), "Never asked")
        self.assertEqual(self.where(), {})

    def test_the_old_restart_switch_off_is_never(self):
        self.config("reopenApps", "ask")
        self.config("reopenAppsAfterRestart", "false")
        self.kept_from_last_time()
        self.ipc("test", "pickUpAtLogin")
        self.wait(lambda st: not os.path.exists(self.session), "the kept apps forgotten", timeout=10)
        self.assertFalse(self.asked())
