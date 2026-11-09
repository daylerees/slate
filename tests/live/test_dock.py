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
