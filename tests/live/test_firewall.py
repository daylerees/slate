"""Settings → Security → Firewall: the switch. Turning it off asks first (Slate's red
confirmation), and No leaves it as it was; turning it on asks nothing more than the password.
The firewall shown is a pretend one (scripts/firewall.py's answer, given by the test): the
test computer has none, so nothing real is ever switched."""
import json

from live import LiveCase

NONE_OPEN = {"kdeconnect": False, "samba": False, "ssh": False, "steam": False}


class FirewallSwitch(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.addCleanup(lambda: self.ipc("test", "settingsPoll", "firewall", ""))
        self.addCleanup(lambda: self.ipc("power", "cancel"))

    def show(self, on, allow=None):
        self.ipc("settings", "page", "lock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "lock", "Settings → Security")
        self.ipc("test", "settingsPoll", "firewall", json.dumps({"kind": "ufw", "on": on, "allow": dict(NONE_OPEN, **(allow or {})),
                                                                  "install": "", "canChange": True}))
        self.wait(lambda st: st["settings"].get("checking", 0) == 0, "the firewall looked at")
        self.s.settle(0.4)

    def test_turning_it_off_asks_first(self):
        self.show(True)
        self.assertEqual(self.ipc("test", "settingsToggle", "Firewall"), "pressed")
        st = self.wait(lambda st: st["asking"] != "", "the question")
        self.assertEqual(st["asking"], "Turn the firewall off?")
        self.assertIn("You can turn it back on here at any time", st["askingBody"])
        self.ipc("power", "cancel")
        self.wait(lambda st: st["asking"] == "", "the question to go")

    def test_turning_it_on_asks_nothing_more(self):
        self.show(False)
        self.assertEqual(self.ipc("test", "settingsToggle", "Firewall"), "pressed")
        self.s.settle(1.0)
        self.assertEqual(self.s.state()["asking"], "")

    def test_no_switch_where_slate_cant_change_it(self):
        for kind in ("none", "nixos"):
            with self.subTest(kind):
                self.ipc("settings", "page", "lock")
                self.wait(lambda st: st["settings"]["section"] == "lock", "Settings → Security")
                self.ipc("test", "settingsPoll", "firewall", json.dumps({"kind": kind, "on": kind == "nixos", "allow": NONE_OPEN,
                                                                          "install": "ufw" if kind == "none" else "", "canChange": False}))
                self.wait(lambda st: st["settings"].get("checking", 0) == 0, "the firewall looked at")
                self.s.settle(0.4)
                self.assertEqual(self.ipc("test", "settingsToggle", "Firewall"), "none")

    def test_an_allowance_needs_the_firewall_on(self):
        """While it's off, what it lets in doesn't count: the rows are grayed out, saying so,
        with no switch to press. On, they switch without asking anything more."""
        self.show(False)
        for label in ("KDE Connect", "File sharing", "Remote login", "Game streaming"):
            self.assertEqual(self.ipc("test", "settingsToggle", label), "none", label)
        waiting = {w["label"]: w["needs"] for w in self.s.state()["settings"]["waiting"]}
        self.assertEqual(waiting.get("Remote login"), "Needs the firewall to be on")
        self.show(True, {"ssh": True})
        self.assertEqual(self.ipc("test", "settingsToggle", "Remote login"), "pressed")
        self.s.settle(1.0)
        self.assertEqual(self.s.state()["asking"], "")
