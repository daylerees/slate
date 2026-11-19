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

    def show(self, on):
        self.ipc("settings", "page", "lock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "lock", "Settings → Security")
        self.ipc("test", "settingsPoll", "firewall", json.dumps({"kind": "ufw", "on": on, "allow": NONE_OPEN,
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
