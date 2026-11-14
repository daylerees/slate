"""Lists keep their rows: when one thing in a list changes, comes or goes, the other rows stay
as they are (what's typed in them, where the list had scrolled to, their fades) and aren't made
again. Each list was once handed a new list whenever anything changed, and made every row again:
a Wi-Fi password half typed went when another network's signal changed. Bug, 2026-11-14.

Slate counts the rows each list makes (state's lists), so a row kept shows as a count that
didn't move."""
import json
import os
import subprocess

import slate
from live import LiveCase


class Lists(LiveCase):
    def lists(self):
        return self.s.state()["lists"]

    def panel(self):
        return self.lists()["panel"]

    def made(self, name):
        return self.panel()["rows"].get(name, 0)

    def open_panel(self, name):
        self.addCleanup(lambda: self.ipc("popout", "close"))
        self.ipc("bar", "panel", name)
        self.wait(lambda st: st["popout"] == name, f"the {name} panel")
        self.s.settle(0.4)


class WifiPassword(Lists):
    """The Wi-Fi panel, with pretend networks (the tests' computer has no Wi-Fi)."""
    def nets(self, **signals):
        self.ipc("test", "wifi", json.dumps(signals))

    def test_password_survives_another_networks_signal(self):
        self.keep_setting("barShowWifi")
        self.config("barShowWifi", "true")
        self.addCleanup(lambda: self.ipc("test", "wifi", ""))
        self.nets(Home=0.9, Cafe=0.6, Library=0.3)
        self.open_panel("wifi")
        self.wait(lambda st: st["lists"]["panel"]["count"] == 3, "the three networks")
        self.assertEqual(self.panel()["order"], ["Home", "Cafe", "Library"])
        self.ipc("test", "wifiPassword", "Cafe")
        self.wait(lambda st: st["lists"]["panel"]["typing"], "Cafe's password field, ready to type in")
        # Half a password, typed with real key presses (a key can be lost before Slate has
        # wtype's keymap: -s waits a moment first, and what arrived says whether to go again)
        for _ in range(5):
            self.s.run(["wtype", "-s", "300", "hunter"], check=True)
            self.s.settle(0.3)
            if self.panel()["typed"]:
                break
        self.assertEqual(self.panel()["typed"], "hunter", f"the typing didn't reach the field: {self.panel()}")
        rows = self.made("wifi")

        with self.subTest("another network's signal changes, the order doesn't"):
            self.nets(Library=0.35)
            got = self.steady(self.panel, floor=0.4)
            self.assertEqual(got["order"], ["Home", "Cafe", "Library"])
            self.assertEqual(got["typed"], "hunter", "the half-typed password went")
            self.assertTrue(got["typing"], "the password field lost the keyboard")
            self.assertEqual(got["cursor"], 6)
            self.assertEqual(self.made("wifi"), rows, "rows were made again")

        with self.subTest("the order changes under it"):
            self.nets(Library=0.95)
            got = self.steady(self.panel, floor=0.4)
            self.assertEqual(got["order"], ["Library", "Home", "Cafe"], "strongest first, as ever")
            self.assertEqual(got["typed"], "hunter", "the half-typed password went as its row moved")
            self.assertTrue(got["typing"], "the password field lost the keyboard as its row moved")
            self.assertEqual(self.made("wifi"), rows, "rows were made again")

        with self.subTest("and the rest can still be typed"):
            self.s.run(["wtype", "-s", "300", "2"], check=True)
            self.wait(lambda st: st["lists"]["panel"]["typed"] == "hunter2", "the rest of the password")

        with self.subTest("a network that turns up gets a row, the others keep theirs"):
            self.nets(Station=0.1)
            self.wait(lambda st: st["lists"]["panel"]["count"] == 4, "the fourth network")
            self.assertEqual(self.made("wifi"), rows + 1)
            self.assertEqual(self.panel()["typed"], "hunter2")


class NotificationsPanel(Lists):
    def notify(self, summary):
        before = self.s.state()["notifications"]["history"]
        self.s.run(["notify-send", "-a", "Tests", "-t", "500", summary, "A few words, so the card has a body to show"], check=True)
        self.wait(lambda st: st["notifications"]["history"] == before + 1, "the notification")

    def test_one_coming_or_going_keeps_the_rest(self):
        self.keep_setting("barShowNotifications")
        self.config("barShowNotifications", "true")
        self.ipc("notifications", "clear")
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        for i in range(12):
            self.notify(f"Note {i}")
        self.open_panel("notifications")
        self.wait(lambda st: st["lists"]["panel"]["count"] == 12, "the twelve in the panel")
        self.steady(self.panel, floor=0.5)
        # (scrolled partway: there's more than the panel's height of them)
        self.ipc("test", "listScroll", 150)
        at = self.steady(self.panel, floor=0.3)
        self.assertEqual(at["scroll"], 150, "the list didn't scroll (too few to?)")
        rows = self.made("notifications")

        with self.subTest("one arrives"):
            self.notify("One more")
            self.wait(lambda st: st["lists"]["panel"]["count"] == 13, "the new one in the panel")
            got = self.steady(self.panel, floor=0.4)
            self.assertLessEqual(self.made("notifications") - rows, 1, "the rows there already were made again")
            self.assertGreaterEqual(got["scroll"], 150, "the list jumped back to its top")

        with self.subTest("one goes"):
            rows = self.made("notifications")
            self.ipc("test", "listScroll", 150)
            self.steady(self.panel, floor=0.3)
            latest = json.loads(self.ipc("notifications", "list"))
            self.assertEqual(latest[0]["summary"], "One more")
            self.ipc("test", "removeNotification", 0)
            self.wait(lambda st: st["lists"]["panel"]["count"] == 12, "the panel without it")
            got = self.steady(self.panel, floor=0.4)
            # (a row or two may come into view at the end as the rest close up; never all twelve)
            self.assertLessEqual(self.made("notifications") - rows, 3, "the rows that stayed were made again")
            self.assertGreater(got["scroll"], 0, "the list jumped back to its top")

        with self.subTest("clear all"):
            self.ipc("notifications", "clear")
            self.wait(lambda st: st["lists"]["panel"]["count"] == 0, "the panel emptied")

    def test_one_arriving_while_open_slides_in(self):
        """A notification that comes while the panel is open appears in it (sliding and fading
        in, which settles); with Animations off it's simply there, with nothing fading."""
        self.keep_setting("barShowNotifications")
        self.keep_setting("animations")
        self.config("barShowNotifications", "true")
        self.ipc("notifications", "clear")
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        self.notify("Already here")
        self.open_panel("notifications")
        self.wait(lambda st: st["lists"]["panel"]["count"] == 1, "the one in the panel")
        self.steady(self.panel, floor=0.4)
        with self.subTest("animated"):
            self.config("animations", "normal")
            self.notify("Comes in")
            self.wait(lambda st: st["lists"]["panel"]["count"] == 2, "the new one in the panel")
            self.wait(lambda st: st["lists"]["panel"]["fading"] == 0, "it to finish sliding in")
        with self.subTest("animations off"):
            self.config("animations", "off")
            self.notify("Comes in at once")
            self.wait(lambda st: st["lists"]["panel"]["count"] == 3 and st["lists"]["panel"]["fading"] == 0,
                      "the new one in the panel, already there")


class ControlTiles(Lists):
    def test_one_switch_leaves_the_other_tiles(self):
        for key in ("glass", "controlSwitches"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("test", "controlSwitches", ""))
        self.ipc("test", "controlSwitches", "glass")
        self.open_panel("control")
        self.steady(self.panel, floor=0.4)
        rows = self.made("tiles")
        self.assertGreaterEqual(rows, 8, "the eight tiles")
        for turn in ("on (or off)", "back"):
            with self.subTest(turn):
                before = self.setting("glass")
                self.ipc("test", "pressSwitch", "glass")
                for _ in range(40):
                    if self.setting("glass") != before:
                        break
                    self.s.settle(0.1)
                self.assertNotEqual(self.setting("glass"), before, "pressing Glass changed nothing")
                self.steady(self.panel, floor=0.4)
                self.assertEqual(self.made("tiles"), rows, "tiles were made again when one was switched")


class TrayIcons(Lists):
    def app(self, name):
        app = subprocess.Popen(["python3", os.path.join(slate.FIXTURES, "live", "fake_tray_app.py"), name, name.title()],
                               env=self.s.env, stdout=subprocess.PIPE, text=True)
        self.addCleanup(lambda: self.wait(lambda st: name not in st["tray"], f"{name}'s icon to go", timeout=10))
        self.addCleanup(app.kill)
        self.assertEqual(app.stdout.readline().strip(), "registered")
        self.wait(lambda st: name in st["tray"], f"{name}'s icon in the tray")
        return app

    def tray(self):
        return self.lists()["tray"]

    def test_one_arriving_leaves_the_others(self):
        for key in ("barShowTray", "barTrayCollapsed"):
            self.keep_setting(key)
        self.config("barShowTray", "true")
        self.config("barTrayCollapsed", "false")
        self.app("firstapp")
        self.app("secondapp")
        before = self.steady(self.tray, floor=1.0)
        there = len(self.s.state()["tray"])
        self.assertGreaterEqual(there, 2)
        third = self.app("thirdapp")
        after = self.steady(self.tray, floor=1.0)
        self.assertEqual(after["made"] - before["made"], 1, "the icons there already were made again")
        self.assertLessEqual(after["measured"] - before["measured"], 1, "the icons there already were measured again")
        with self.subTest("and one leaving"):
            third.kill()
            self.wait(lambda st: "thirdapp" not in st["tray"], "the third icon to go", timeout=10)
            gone = self.steady(self.tray, floor=1.0)
            self.assertEqual(gone["made"], after["made"], "the icons left were made again")
            self.assertEqual(gone["measured"], after["measured"], "the icons left were measured again")


class SettingsPolls(Lists):
    """Settings → Printers and Network look again every 5 seconds: a look that finds what the
    last one did makes no rows, and one that finds a change makes only the row that's new."""
    def rows(self):
        return self.lists()["settings"]

    def looks(self, name, more, timeout=20):
        """Wait for `more` more looks of this kind; returns the rows made by then."""
        start = self.rows().get(name, 0)
        self.wait(lambda st: st["lists"]["settings"].get(name, 0) >= start + more, f"{more} more of {name}", timeout=timeout)
        return self.rows()

    def page(self, name):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", name)
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == name, f"the {name} page")

    def printers(self, *names, jobs=0):
        return json.dumps({"service": "on", "configTool": "", "printers": [
            {"name": n, "status": "idle", "info": n.title(), "uri": "ipp://" + n, "default": i == 0, "accepting": True,
             "jobs": jobs if i == 0 else 0} for i, n in enumerate(names)]})

    def test_printers(self):
        self.addCleanup(lambda: self.ipc("test", "settingsPoll", "printers", ""))
        self.page("printers")
        self.ipc("test", "settingsPoll", "printers", self.printers("office", "study"))
        self.wait(lambda st: st["lists"]["settings"].get("printers", 0) >= 2, "the two printers' rows", timeout=15)
        made = self.rows()["printers"]
        with self.subTest("the same again"):
            self.assertEqual(self.looks("printerLooks", 2)["printers"], made, "rows were made again though nothing changed")
        with self.subTest("one printer changes"):
            self.ipc("test", "settingsPoll", "printers", self.printers("office", "study", jobs=2))
            self.assertEqual(self.looks("printerLooks", 2)["printers"], made, "a job waiting made the rows again")
        with self.subTest("one more printer"):
            self.ipc("test", "settingsPoll", "printers", self.printers("office", "study", "attic"))
            self.assertEqual(self.looks("printerLooks", 2)["printers"], made + 1, "the rows there already were made again")
        with self.subTest("one fewer"):
            self.ipc("test", "settingsPoll", "printers", self.printers("study", "attic"))
            self.assertEqual(self.looks("printerLooks", 2)["printers"], made + 1)

    def test_network(self):
        self.addCleanup(lambda: self.ipc("test", "settingsPoll", "network", ""))
        self.page("wifi")
        self.ipc("test", "settingsPoll", "network", "wired=eth0\nip=10.0.0.5/24\ngateway=10.0.0.1\n")
        self.wait(lambda st: st["lists"]["settings"].get("facts", 0) >= 2, "the connection's two rows", timeout=15)
        self.looks("networkLooks", 1)
        made = self.rows()["facts"]
        with self.subTest("the same again"):
            self.assertEqual(self.looks("networkLooks", 2)["facts"], made, "rows were made again though nothing changed")
        with self.subTest("one more fact"):
            self.ipc("test", "settingsPoll", "network", "wired=eth0\nip=10.0.0.5/24\ngateway=10.0.0.1\nrate=1000 Mb/s\n")
            self.assertEqual(self.looks("networkLooks", 2)["facts"], made + 1, "the rows there already were made again")
