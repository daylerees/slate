"""The dock: its slots in order for each setting, app badges, the Waste Basket's count."""
import os
import time

from live import LiveCase


def kinds(st):
    return [x["kind"] if x["kind"] != "app" else "app:" + x["key"] for x in st["dock"]["slots"]]


class Dock(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("dockShowLauncher", "dockDivider", "dockShowDownloads", "dockShowTrash", "dockBadges"):
            self.keep_setting(key)
            self.config(key, "true")

    def test_default_order(self):
        st = self.wait(lambda st: "trash" in kinds(st), "the dock")
        k = kinds(st)
        self.assertEqual(k[0], "launcher")
        self.assertIn("app:foot", k)
        self.assertEqual(k[-2:], ["downloads", "trash"])
        # dividers only between groups, never two together or at an end
        for a, b in zip(k, k[1:]):
            self.assertFalse(a == b == "divider", f"two dividers together: {k}")
        self.assertNotIn(k[-1], ("divider",))

    def test_each_part_switches_off(self):
        for key, kind in (("dockShowLauncher", "launcher"), ("dockShowDownloads", "downloads"),
                          ("dockShowTrash", "trash"), ("dockDivider", "divider")):
            with self.subTest(key):
                self.config(key, "false")
                st = self.wait(lambda st: kind not in kinds(st), f"{kind} to leave the dock")
                self.config(key, "true")
                self.wait(lambda st: kind in kinds(st), f"{kind} to come back")

    def test_trash_count(self):
        trash = self.s.h(".local", "share", "Trash")
        made = []
        for i in range(3):
            p = os.path.join(trash, "files", f"old-{i}.txt")
            open(p, "w").close()
            with open(os.path.join(trash, "info", f"old-{i}.txt.trashinfo"), "w") as f:
                f.write(f"[Trash Info]\nPath=/tmp/old-{i}.txt\nDeletionDate=2026-01-05T09:00:00\n")
            made.append(p)
        self.wait(lambda st: st["dock"]["trash"] == 3, "the Waste Basket to count 3", timeout=10)
        for p in made:
            os.remove(p)
            os.remove(os.path.join(trash, "info", os.path.basename(p) + ".trashinfo"))
        self.wait(lambda st: st["dock"]["trash"] == 0, "the Waste Basket to empty", timeout=10)

    def test_badge_from_launcher_entry(self):
        """An app's count (com.canonical.Unity.LauncherEntry) shows on its dock icon."""
        if not self.s.env.get("DBUS_SESSION_BUS_ADDRESS"):
            self.skipTest("no session bus found")
        self.s.settle(1.0)      # launcher-entries.py listening

        def emit(count, visible):
            self.s.run(["gdbus", "emit", "--session", "--object-path", "/", "--signal",
                        "com.canonical.Unity.LauncherEntry.Update", "application://foot.desktop",
                        f"{{'count': <int64 {count}>, 'count-visible': <{str(visible).lower()}>}}"])

        def foot(st):
            return next(x for x in st["dock"]["slots"] if x["kind"] == "app" and x["key"] == "foot")
        emit(4, True)
        self.wait(lambda st: foot(st)["badge"]["count"] == 4, "foot's badge to show 4")
        emit(0, False)
        self.wait(lambda st: foot(st)["badge"]["count"] == 0, "foot's badge to clear")

    def test_menu_and_downloads(self):
        self.ipc("dock", "menu", "foot")
        self.wait(lambda st: st["dock"]["menu"] == "foot", "foot's menu")
        self.ipc("dock", "closeMenu")
        self.wait(lambda st: st["dock"]["menu"] == "")
        self.ipc("dock", "downloads")
        self.wait(lambda st: st["dock"]["menu"] == "other", "the Downloads grid")
        self.ipc("dock", "closeMenu")

    def test_positions(self):
        old = self.keep_setting("dockPosition")
        for edge in ("left", "right", "bottom"):
            with self.subTest(edge):
                self.config("dockPosition", edge)
                self.wait(lambda st: st["dockEdge"] == edge)
                time.sleep(0.5)
        self.config("dockPosition", old)


class Badges(LiveCase):
    """An app's notifications badge its dock icon until you go to the app (opening the
    notification panel used to clear them, so a mail app's count vanished unseen)."""

    def foot_badge(self, st):
        return next(x for x in st["dock"]["slots"] if x["kind"] == "app" and x["key"] == "foot")["badge"]["count"]

    def go(self, what):
        self.s.hyprctl("eval", "hl.dispatch(hl.dsp.focus({ %s }))" % what)
        self.s.settle(0.5)

    def test_until_you_go_to_the_app(self):
        self.keep_setting("dockBadges")
        self.config("dockBadges", "true")
        # A foot window to go to, then away to an empty workspace (no app in front)
        clients = self.s.hyprctl("clients", json_out=True)
        if not any(c["class"] == "foot" for c in clients):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
            for _ in range(50):
                clients = self.s.hyprctl("clients", json_out=True)
                if any(c["class"] == "foot" for c in clients):
                    break
                self.s.settle(0.2)
        foot = next(c for c in clients if c["class"] == "foot")
        self.go("workspace = 9")
        before = self.foot_badge(self.s.state())
        self.s.run(["notify-send", "-a", "foot", "New mail", "From the test suite"])
        self.wait(lambda st: self.foot_badge(st) == before + 1, "foot's badge to count the notification")
        # Opening the notification panel no longer clears it
        self.ipc("bar", "panel", "notifications")
        self.wait(lambda st: st["popout"] == "notifications")
        self.ipc("popout", "close")
        self.s.settle(0.5)
        self.assertEqual(self.foot_badge(self.s.state()), before + 1, "opening the panel cleared the badge")
        # Going to the app does
        self.go("window = [=[address:%s]=]" % foot["address"])
        self.wait(lambda st: self.foot_badge(st) == 0, "the badge to clear when foot is in front")
        # And while you're in it, its notifications don't badge it
        self.s.run(["notify-send", "-a", "foot", "Another", "While you're in foot"])
        self.s.settle(1)
        self.assertEqual(self.foot_badge(self.s.state()), 0)
        self.go("workspace = 9")
        self.s.settle(0.5)
        self.assertEqual(self.foot_badge(self.s.state()), 0, "the one that came while you were there counts as seen")
