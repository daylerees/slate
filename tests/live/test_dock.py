"""The dock: its slots in order for each setting, app badges, the Waste Basket's count."""
import atexit
import json
import os
import time
import unittest

from live import LiveCase
from session import Session, in_container


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

    def test_preview_delay_and_switch(self):
        """Settings → Dock: Window previews (a switch), and how long to rest on an app before
        they show, down to Instant. (0 used to mean off: now it's at once, and the switch is off.)"""
        for key in ("dockPreviews", "dockPreviewDelay", "dockHoverEffect"):
            self.keep_setting(key)
        self.config("dockHoverEffect", "magnify")
        self.addCleanup(lambda: (self.ipc("test", "dockHover", "-1"), self.ipc("dock", "closePreview")))
        if not any(c["class"] == "foot" for c in self.s.hyprctl("clients", json_out=True)):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        st = self.wait(lambda st: any(x["kind"] == "app" and x["key"] == "foot" and x["windows"] > 0 for x in st["dock"]["slots"]),
                       "a foot window on the dock")
        foot = next(i for i, x in enumerate(st["dock"]["slots"]) if x["kind"] == "app" and x["key"] == "foot")

        def rest():
            self.ipc("test", "dockHover", "-1")
            self.ipc("dock", "closePreview")
            self.wait(lambda st: not st["dock"]["preview"], "no preview")
            self.s.settle(0.5)
            self.ipc("test", "dockHover", str(foot))

        # a long wait: nothing yet after a second
        self.config("dockPreviews", "true")
        self.config("dockPreviewDelay", "3")
        rest()
        self.steady(self.s.state, floor=1.2)
        self.assertFalse(self.s.state()["dock"]["preview"], "the preview came before its 3 seconds")
        # Instant: there as the pointer arrives
        self.config("dockPreviewDelay", "0")
        rest()
        self.s.wait(lambda st: st["dock"]["preview"], timeout=1.5, what="the preview at once")
        # switched off: never, however short the wait
        self.config("dockPreviews", "false")
        rest()
        self.steady(self.s.state, floor=1.2)
        self.assertFalse(self.s.state()["dock"]["preview"], "a preview with previews switched off")

    def test_preview_fades_away(self):
        """An app's window preview opens, and once closed it fades and its window goes (it used
        to vanish at once, with no fade)."""
        if not any(c["class"] == "foot" for c in self.s.hyprctl("clients", json_out=True)):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.wait(lambda st: any(x["kind"] == "app" and x["key"] == "foot" and x["windows"] > 0 for x in st["dock"]["slots"]),
                  "a foot window on the dock")
        self.ipc("dock", "preview", "foot")
        st = self.wait(lambda st: st["dock"]["preview"], "foot's preview")
        self.assertTrue(st["dock"]["previewOnScreen"])
        self.ipc("dock", "closePreview")
        self.wait(lambda st: not st["dock"]["preview"], "the preview to close")
        self.wait(lambda st: not st["dock"]["previewOnScreen"], "the preview to fade away", timeout=3)

    def test_hover_effects(self):
        """Settings → Dock → Hover effect: magnify grows the icon under the pointer; tilt turns
        the icons towards the pointer while it's on the dock (upright otherwise), the one under it
        straight and not grown; fade fades the far icons while the pointer's on the dock."""
        self.keep_setting("dockHoverEffect")
        self.addCleanup(lambda: self.ipc("test", "dockHover", "-1"))
        slots = self.s.state()["dock"]["slots"]
        apps = [i for i, x in enumerate(slots) if x["kind"] == "app"]
        parts = [i for i, x in enumerate(slots) if x["kind"] != "divider"]
        self.assertTrue(apps and len(parts) >= 2, "needs an app and something else on the dock")
        first = apps[0]
        last = max(parts, key=lambda i: abs(i - first))        # the part furthest from it

        self.config("dockHoverEffect", "tilt")
        self.ipc("test", "dockHover", "-1")
        # pointer away: upright
        st = self.wait(lambda st: st["dock"]["hoverEffect"] == "tilt" and all(a == 0 for a in st["dock"]["tilt"]),
                       "the icons upright with the pointer away")
        self.ipc("test", "dockHover", str(first))
        st = self.wait(lambda st: abs(st["dock"]["tilt"][first]) <= 1, "the icon under the pointer to straighten")
        self.assertEqual(st["dock"]["scale"][first], 1, "tilt alone shouldn't grow it")
        self.assertNotEqual(st["dock"]["tilt"][last], 0, "the far icons should still lean")

        self.config("dockHoverEffect", "magnify")
        st = self.wait(lambda st: st["dock"]["scale"][first] > 1.2, "the icon under the pointer to grow")
        self.assertTrue(all(a == 0 for a in st["dock"]["tilt"]), "magnify alone shouldn't tilt")

        # Fade: the far icons fade while the pointer's on the dock, the one under it clear
        self.config("dockHoverEffect", "fade")
        st = self.wait(lambda st: st["dock"]["fade"][last] < 0.6, "the far icons to fade")
        self.assertEqual(st["dock"]["fade"][first], 1)
        self.assertEqual(st["dock"]["scale"][first], 1, "fade alone shouldn't grow it")
        self.config("dockHoverEffect", "fademagnify")
        st = self.wait(lambda st: st["dock"]["scale"][first] > 1.2, "fade and magnify to grow it")
        self.assertLess(st["dock"]["fade"][last], 0.6)
        self.ipc("test", "dockHover", "-1")
        self.wait(lambda st: all(f == 1 for f in st["dock"]["fade"]), "all clear once the pointer leaves")
        self.ipc("test", "dockHover", str(first))

        # Glow: round the icon under the pointer, not the far ones; with magnify it grows too
        self.config("dockHoverEffect", "glow")
        st = self.wait(lambda st: st["dock"]["glow"][first] > 0.9, "the icon under the pointer to glow")
        self.assertEqual(st["dock"]["glow"][last], 0)
        self.assertEqual(st["dock"]["scale"][first], 1, "glow alone shouldn't grow it")
        self.config("dockHoverEffect", "glowmagnify")
        st = self.wait(lambda st: st["dock"]["scale"][first] > 1.2, "glow and magnify to grow it")
        self.assertGreater(st["dock"]["glow"][first], 0.9)
        self.ipc("test", "dockHover", "-1")
        self.wait(lambda st: all(g == 0 for g in st["dock"]["glow"]), "no glow once the pointer leaves")
        self.ipc("test", "dockHover", str(first))

        # Raise: only the icon under the pointer lifts, nothing grows
        self.config("dockHoverEffect", "raise")
        st = self.wait(lambda st: st["dock"]["lift"][first] > 0, "the icon under the pointer to lift")
        self.assertTrue(all(l == 0 for i, l in enumerate(st["dock"]["lift"]) if i != first), "others lifted too")
        self.assertTrue(all(sc == 1 for sc in st["dock"]["scale"]), "raise shouldn't grow anything")

        # Dividers keep still in every effect, even with the pointer on one
        dividers = [i for i, x in enumerate(slots) if x["kind"] == "divider"]
        if dividers:
            for effect in ("raise", "tilt", "fade", "glow"):
                with self.subTest(dividers=effect):
                    self.config("dockHoverEffect", effect)
                    self.ipc("test", "dockHover", str(dividers[0]))
                    self.steady(self.s.state, floor=0.5)
                    d = self.s.state()["dock"]
                    for i in dividers:
                        self.assertEqual((d["lift"][i], d["tilt"][i], d["fade"][i], d["glow"][i]), (0, 0, 1, 0),
                                         f"divider {i} moved with {effect}")
            self.ipc("test", "dockHover", str(first))

        self.config("dockHoverEffect", "none")
        st = self.wait(lambda st: st["dock"]["scale"][first] == 1, "nothing to grow")
        self.assertTrue(all(a == 0 for a in st["dock"]["tilt"]))
        self.assertTrue(all(f == 1 for f in st["dock"]["fade"]))

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
        self.steady(self.s.state, floor=0.5)
        self.assertEqual(self.foot_badge(self.s.state()), before + 1, "opening the panel cleared the badge")
        # Going to the app does
        self.go("window = [=[address:%s]=]" % foot["address"])
        self.wait(lambda st: self.foot_badge(st) == 0, "the badge to clear when foot is in front")
        # And while you're in it, its notifications don't badge it
        self.s.run(["notify-send", "-a", "foot", "Another", "While you're in foot"])
        self.steady(self.s.state, floor=1)
        self.assertEqual(self.foot_badge(self.s.state()), 0)
        self.go("workspace = 9")
        self.steady(self.s.state, floor=0.5)
        self.assertEqual(self.foot_badge(self.s.state()), 0, "the one that came while you were there counts as seen")


class Dragging(LiveCase):
    """Dragging apps on the dock: a running app pinned by dropping it among the pinned ones,
    moved along them, and unpinned by pulling it well up off the dock (it stays, running)."""
    KEY = "slate-test-app"

    def setUp(self):
        super().setUp()
        self.s.hyprctl("eval", 'hl.exec_cmd("foot --app-id %s")' % self.KEY)
        self.wait(lambda st: self.slot(st) is not None, "the app on the dock", timeout=10)

    def tearDown(self):
        # (unpinned again, and closed)
        st = self.s.state()
        if self.KEY in st["dock"]["pinned"]:
            self.ipc("test", "dockDrag", self.KEY, 0, 400)
            self.ipc("test", "dockDrop")
        for c in self.s.hyprctl("clients", json_out=True):
            if c["class"] == self.KEY:
                self.s.hyprctl("eval", "hl.dispatch(hl.dsp.window.close({ window = [=[address:%s]=] }))" % c["address"])
        super().tearDown()

    def slot(self, st):
        return next((x for x in st["dock"]["slots"] if x["kind"] == "app" and x["key"] == self.KEY), None)

    def at(self, st, key):
        return next(x["at"] if "at" in x else i for i, x in enumerate(st["dock"]["slots"]) if x.get("key") == key)

    def test_pin_move_unpin(self):
        st = self.s.state()
        self.assertFalse(self.slot(st)["pinned"])
        foot = self.at(st, "foot")
        # Held over foot (before its middle): it'd go first, and the dock makes room
        self.ipc("test", "dockDrag", self.KEY, foot, 0)
        st = self.wait(lambda st: st["dock"]["dragging"] == self.KEY and st["dock"]["dropIndex"] == 0, "a place among the pinned apps")
        self.assertIsNone(self.slot(st), "the app being dragged leaves its slot")
        self.ipc("test", "dockDrop")
        self.wait(lambda st: st["dock"]["pinned"][:2] == [self.KEY, "foot"] and st["dock"]["dragging"] == "", "it pinned, first")
        # Moved past foot
        st = self.s.state()
        self.ipc("test", "dockDrag", self.KEY, self.at(st, "foot") + 1, 0)
        self.ipc("test", "dockDrop")
        self.wait(lambda st: st["dock"]["pinned"][:2] == ["foot", self.KEY], "it moved after foot")
        # Pulled well up off the dock: unpinned, but still on the dock as it's running
        self.ipc("test", "dockDrag", self.KEY, 0, 400)
        self.wait(lambda st: st["dock"]["dragAway"], "far enough to unpin")
        self.ipc("test", "dockDrop")
        st = self.wait(lambda st: self.KEY not in st["dock"]["pinned"] and st["dock"]["dragging"] == "", "it unpinned")
        self.assertIsNotNone(self.slot(st), "a running app stays on the dock")
        self.assertFalse(self.slot(st)["pinned"])

    def test_running_app_beside_the_dock_goes_back(self):
        self.ipc("test", "dockDrag", self.KEY, -1, 0)
        st = self.wait(lambda st: st["dock"]["dragging"] == self.KEY)
        self.assertEqual(st["dock"]["dropIndex"], -1, "not over the pinned apps")
        self.ipc("test", "dockDrop")
        st = self.wait(lambda st: st["dock"]["dragging"] == "" and self.slot(st) is not None, "it back in its place")
        self.assertFalse(self.slot(st)["pinned"])


class DraggingTheOnlyPin(LiveCase):
    def test_gap_where_it_was(self):
        """The only pinned app picked up (nothing running, so the dividers go): its gap opens where
        it was, after the Apps button, not past the trash (as it did)."""
        st = self.s.state()
        launcher = next(i for i, x in enumerate(st["dock"]["slots"]) if x["kind"] == "launcher")
        self.ipc("test", "dockDrag", "foot", launcher + 1, 0)
        try:
            st = self.wait(lambda st: st["dock"]["dragging"] == "foot")
            self.assertEqual(st["dock"]["dropIndex"], 0)
            self.assertEqual(st["dock"]["gapAt"], launcher + 1)
        finally:
            self.ipc("test", "dockDrag", "foot", launcher + 1, 0)
            self.ipc("test", "dockDrop")
            self.wait(lambda st: st["dock"]["dragging"] == "" and st["dock"]["pinned"] == ["foot"], "foot back")


class DockMenu(LiveCase):
    """The dock's own menu (a right-click on its empty space): its submenus set their settings
    and tick the choice in use."""
    def menu(self):
        return self.s.state()["dockMenu"]

    def item(self, label):
        return next(i for i in self.menu()["items"] if i and i["label"] == label)

    def test_items(self):
        self.ipc("test", "dockMenu", "open")
        self.wait(lambda st: st["dockMenu"]["open"], "the dock's menu")
        labels = [i and i["label"] for i in self.menu()["items"]]
        for want in ("Auto-hide", "Position", "Hover effect", "Icon size", "Show", "Dock settings"):
            self.assertIn(want, labels)
        self.ipc("test", "dockMenu", "Dock settings")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock", "Dock settings from its menu")
        self.ipc("settings", "close")

    def test_icon_size_ticks_the_choice(self):
        self.keep_setting("dockIconSize")
        for label, size in (("Large", "52"), ("Small", "32")):
            with self.subTest(label):
                self.ipc("test", "dockMenu", "Icon size/" + label)
                for _ in range(20):
                    if self.setting("dockIconSize") == size:
                        break
                    self.s.settle(0.1)
                self.assertEqual(self.setting("dockIconSize"), size)
                ticked = [j["label"] for j in self.item("Icon size")["sub"] if j and j["ticked"]]
                self.assertEqual(ticked, [label])

    def test_auto_hide_and_position(self):
        self.keep_setting("dockAutoHide")
        self.keep_setting("dockPosition")
        was = self.setting("dockAutoHide")
        self.ipc("test", "dockMenu", "Auto-hide")
        for _ in range(20):
            if self.setting("dockAutoHide") != was:
                break
            self.s.settle(0.1)
        self.assertNotEqual(self.setting("dockAutoHide"), was)
        self.assertEqual(self.item("Auto-hide")["ticked"], self.setting("dockAutoHide") == "true")
        self.ipc("test", "dockMenu", "Position/Left")
        self.wait(lambda st: st["dockEdge"] == "left", "the dock to move left from its menu")


class MenusClose(LiveCase):
    """An open menu closes when you go to another workspace, or the launcher opens."""
    def test_on_workspace_change_and_the_launcher(self):
        self.ipc("test", "barMenu", "open")
        self.wait(lambda st: st["barMenu"]["open"])
        self.ipc("launcher", "open")
        self.wait(lambda st: not st["barMenu"]["open"], "the menu to close as the launcher opens")
        self.ipc("launcher", "close")
        self.ipc("test", "dockMenu", "open")
        self.wait(lambda st: st["dockMenu"]["open"])
        ws = self.s.hyprctl("activeworkspace", json_out=True)["id"]
        self.addCleanup(lambda: self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end"))
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws + 1} }})) end")
        self.wait(lambda st: not st["dockMenu"]["open"], "the dock's menu to close on going to another workspace")


class Fits(LiveCase):
    """However many things are on the dock, it stays on the screen: the icons shrink to fit
    the edge, counting each thing at its real width (what's playing is several icons wide)."""
    def setUp(self):
        super().setUp()
        for key in ("dockIconSize", "dockPosition", "dockShowMedia", "dockMediaArt", "dockShowLauncher",
                    "dockShowDownloads", "dockShowTrash", "dockDivider"):
            self.keep_setting(key)
        for key in ("dockShowMedia", "dockMediaArt", "dockShowLauncher", "dockShowDownloads", "dockShowTrash", "dockDivider"):
            self.config(key, "true")
        self.config("dockPosition", "bottom")
        self.wait(lambda st: st["dockEdge"] == "bottom", "the dock along the bottom")

    def fits(self, st):
        d = st["dock"]
        # (48: the room the dock keeps at its ends for magnified icons)
        return d["length"] + 48 <= d["room"] + 1

    def test_with_something_playing(self):
        """Icons too big for the edge (as many apps would make them), with something playing:
        it used to count what's playing as one icon, and ran off the screen."""
        self.config("dockIconSize", 200)
        self.play()
        st = self.wait(lambda st: st["dock"]["media"], "what's playing on the dock")
        st = self.steady(lambda: self.s.state()["dock"]["length"]) and self.s.state()
        d = st["dock"]
        self.assertTrue(self.fits(st), f"the dock is {d['length']}px along an edge of {d['room']}px (icons {d['base']}px)")
        self.assertLess(d["base"], 200, "the icons shrank")

    def test_room_to_spare_keeps_your_size(self):
        self.config("dockIconSize", 40)
        st = self.steady(lambda: self.s.state()["dock"]["base"]) and self.s.state()
        self.assertEqual(st["dock"]["base"], 40)
        self.assertTrue(self.fits(st))


class MoreCase(LiveCase):
    """A dock along the bottom with everything on it, ready to be filled until apps go to More."""
    APPS = ["slate-more-%d" % i for i in range(1, 6)]

    def setUp(self):
        super().setUp()
        for key in ("dockPosition", "dockIconSize", "dockShowMedia", "dockMediaArt", "dockShowLauncher",
                    "dockShowDownloads", "dockShowTrash", "dockDivider"):
            self.keep_setting(key)
        for key in ("dockShowMedia", "dockMediaArt", "dockShowLauncher", "dockShowDownloads", "dockShowTrash", "dockDivider"):
            self.config(key, "true")
        self.config("dockIconSize", 40)
        self.config("dockPosition", "bottom")
        self.wait(lambda st: st["dockEdge"] == "bottom", "the dock along the bottom")
        self.addCleanup(lambda: self.ipc("test", "dockRoom", 0))
        self.addCleanup(self.close_apps)

    def open_apps(self):
        # one after another, so the dock has them in this order (oldest first)
        for key in self.APPS:
            self.s.hyprctl("eval", 'hl.exec_cmd("foot --app-id %s")' % key)
            self.wait(lambda st: key in self.on_dock(st) or key in st["dock"]["more"], f"{key} on the dock", timeout=10)

    def close_apps(self):
        for c in self.s.hyprctl("clients", json_out=True):
            if c["class"] in self.APPS:
                self.s.hyprctl("eval", "hl.dispatch(hl.dsp.window.close({ window = [=[address:%s]=] }))" % c["address"])
        self.wait(lambda st: not any(k in self.on_dock(st) or k in st["dock"]["more"] for k in self.APPS), "the test apps gone")

    def on_dock(self, st):
        return [x["key"] for x in st["dock"]["slots"] if x["kind"] == "app"]

    def settled(self):
        return self.steady(lambda: json.dumps(self.s.state()["dock"], sort_keys=True)) and self.s.state()

    def assert_fits(self, st):
        d = st["dock"]
        self.assertLessEqual(d["length"] + 48, d["room"] + 1, f"the dock is {d['length']}px in {d['room']}px")
        self.assertGreaterEqual(d["base"], 24, "icons no smaller than 24px")


class More(MoreCase):
    """When the dock is too long for its edge even with the icons at 24px: what's playing goes to
    one icon, then the apps you haven't pinned go into More, the oldest first, and come back as
    room returns. The room is made short with `test dockRoom`, so a few windows fill it."""

    def test_oldest_unpinned_fold_first_and_come_back(self):
        self.ipc("test", "dockRoom", 360)
        self.open_apps()
        st = self.settled()
        more = st["dock"]["more"]
        self.assertTrue(more, "some apps went into More")
        self.assertEqual(more, self.APPS[:len(more)], "the oldest first, in their order")
        self.assertIn("foot", self.on_dock(st), "pinned apps stay")
        self.assertEqual([x["kind"] for x in st["dock"]["slots"]].count("more"), 1)
        self.assert_fits(st)
        # More's grid
        self.ipc("dock", "more")
        self.wait(lambda st: st["dock"]["menu"] == "more", "More's grid open")
        self.ipc("dock", "closeMenu")
        # Room again: they come back
        self.ipc("test", "dockRoom", 0)
        st = self.wait(lambda st: st["dock"]["more"] == [], "every app back on the dock")
        self.assertNotIn("more", [x["kind"] for x in st["dock"]["slots"]])
        self.assertEqual([k for k in self.on_dock(st) if k in self.APPS], self.APPS)

    def test_whats_playing_goes_compact_first(self):
        """With something playing and too little room: it goes to one icon before any app folds."""
        self.play()
        self.wait(lambda st: st["dock"]["media"], "what's playing on the dock")
        self.ipc("test", "dockRoom", 280)
        st = self.wait(lambda st: st["dock"]["mediaCompact"], "what's playing as one icon")
        self.assertEqual(st["dock"]["more"], [], "nothing folded while that was enough")
        self.assert_fits(self.settled())

    def test_plenty_of_room_folds_nothing(self):
        self.open_apps()
        st = self.settled()
        self.assertEqual(st["dock"]["more"], [])
        self.assertFalse(st["dock"]["mediaCompact"])

    def test_pinned_apps_fold_last(self):
        """Room for hardly anything: every app you haven't pinned goes first, then the pinned."""
        self.ipc("test", "dockRoom", 200)
        self.open_apps()
        st = self.settled()
        # (all of them, listed in More in the dock's own order: pinned first)
        self.assertEqual(st["dock"]["more"], ["foot"] + self.APPS)
        kinds = [x["kind"] for x in st["dock"]["slots"]]
        for kept in ("launcher", "downloads", "trash"):
            self.assertIn(kept, kinds, f"the {kept} stays")


class DraggingFromMore(MoreCase):
    """An app dragged out of More's grid onto the dock is pinned where it's let go, through the
    dock's own drag (the gap opening there); let go anywhere else, nothing changes. The grid
    hands the dock the pointer's place on the screen (test dockMoreDrag), as its tiles do."""

    def setUp(self):
        super().setUp()
        self.addCleanup(self.unpin_test_apps)
        self.ipc("test", "dockRoom", 360)
        self.open_apps()
        st = self.settled()
        self.assertTrue(st["dock"]["more"], "some apps went into More")

    def unpin_test_apps(self):
        # (room again, so each is on the dock, then pulled well up off it)
        self.ipc("dock", "closeMenu")
        self.ipc("test", "dockRoom", 0)
        for key in self.APPS:
            if key in self.s.state()["dock"]["pinned"]:
                self.wait(lambda st: key in self.on_dock(st), f"{key} on the dock")
                self.ipc("test", "dockDrag", key, 0, 400)
                self.ipc("test", "dockDrop")
                self.wait(lambda st: key not in st["dock"]["pinned"] and st["dock"]["dragging"] == "", f"{key} unpinned")

    def open_more(self):
        self.ipc("dock", "more")
        self.wait(lambda st: st["dock"]["moreOpen"], "More's grid open")

    def at(self, st, key):
        return next(i for i, x in enumerate(st["dock"]["slots"]) if x.get("key") == key)

    def test_dropped_on_the_dock_pins_it_there(self):
        st = self.s.state()
        key = st["dock"]["more"][0]
        pinned = list(st["dock"]["pinned"])
        self.assertNotIn(key, pinned)
        self.open_more()
        # Held over foot (before its middle): the dock's own drag, a gap where it'd go, first
        self.ipc("test", "dockMoreDrag", key, self.at(st, "foot"), 0)
        st = self.wait(lambda st: st["dock"]["dragging"] == key and st["dock"]["dropIndex"] == 0, "a place among the pinned apps")
        self.assertTrue(st["dock"]["dragFromMore"])
        self.assertGreaterEqual(st["dock"]["gapAt"], 0, "a gap where it'd land")
        self.assertTrue(st["dock"]["moreOpen"] and st["dock"]["menuLifted"], "the grid out of sight, still open (it has the pointer)")
        self.assertFalse(st["dock"]["dragAway"])
        # (the grid's tiles held as they were, the one being dragged among them: remade, the
        # tile under the pointer would let go of it)
        self.assertIn(key, st["dock"]["moreGrid"])
        self.assertNotIn(key, st["dock"]["more"], "the dock's own list goes on without it")
        self.ipc("test", "dockMoreDrop")
        st = self.wait(lambda st: st["dock"]["dragging"] == "" and st["dock"]["pinned"][:1] == [key], "it pinned, first")
        self.assertEqual(st["dock"]["pinned"], [key] + pinned, "the rest as they were")
        self.assertFalse(st["dock"]["moreOpen"], "the grid closed")
        st = self.settled()
        self.assertIn(key, self.on_dock(st), "on the dock now")
        self.assertNotIn(key, st["dock"]["more"])
        # Whatever doesn't fit now goes to More by the same rule: the oldest you haven't pinned
        more = st["dock"]["more"]
        self.assertEqual(more, [k for k in self.APPS if k != key][:len(more)])
        self.assertEqual(st["dock"]["moreGrid"], more, "the grid follows the dock again")
        self.assert_fits(st)

    def test_dropped_after_the_pinned_apps(self):
        st = self.s.state()
        key = st["dock"]["more"][-1]
        self.open_more()
        # Past foot's middle: after it
        self.ipc("test", "dockMoreDrag", key, self.at(st, "foot") + 1, 0)
        self.wait(lambda st: st["dock"]["dragging"] == key and st["dock"]["dropIndex"] == 1, "a place after foot")
        self.ipc("test", "dockMoreDrop")
        st = self.wait(lambda st: st["dock"]["dragging"] == "" and key in st["dock"]["pinned"], "it pinned")
        self.assertEqual(st["dock"]["pinned"][:2], ["foot", key])

    def test_dropped_off_the_dock_changes_nothing(self):
        st = self.settled()
        key = st["dock"]["more"][0]
        before = (st["dock"]["pinned"], st["dock"]["more"])
        self.open_more()
        # Well up off the dock: nowhere to go (and not an unpin, as for a pinned app)
        self.ipc("test", "dockMoreDrag", key, self.at(st, "foot"), 400)
        st = self.wait(lambda st: st["dock"]["dragging"] == key)
        self.assertEqual(st["dock"]["dropIndex"], -1)
        self.assertEqual(st["dock"]["gapAt"], -1)
        self.assertFalse(st["dock"]["dragAway"])
        self.ipc("test", "dockMoreDrop")
        self.wait(lambda st: st["dock"]["dragging"] == "" and not st["dock"]["moreOpen"], "let go, the grid closed")
        st = self.settled()
        self.assertEqual((st["dock"]["pinned"], st["dock"]["more"]), before, "it stays in More")
        # Off the dock's start, level with it: nowhere either
        self.open_more()
        self.ipc("test", "dockMoreDrag", key, -1, 0)
        st = self.wait(lambda st: st["dock"]["dragging"] == key)
        self.assertEqual(st["dock"]["dropIndex"], -1)
        self.ipc("test", "dockMoreDrop")
        self.wait(lambda st: st["dock"]["dragging"] == "")
        st = self.settled()
        self.assertEqual((st["dock"]["pinned"], st["dock"]["more"]), before, "it stays in More")

    def test_grid_closed_mid_drag_changes_nothing(self):
        """The grid closed while an app's carried out of it (Escape, another workspace): the drag
        ends as if let go off the dock, never left hanging."""
        st = self.settled()
        key = st["dock"]["more"][0]
        before = (st["dock"]["pinned"], st["dock"]["more"])
        self.open_more()
        self.ipc("test", "dockMoreDrag", key, self.at(st, "foot"), 0)
        self.wait(lambda st: st["dock"]["dropIndex"] == 0, "over the dock")
        self.ipc("dock", "closeMenu")
        self.wait(lambda st: st["dock"]["dragging"] == "" and not st["dock"]["dragFromMore"], "the drag over")
        st = self.settled()
        self.assertEqual((st["dock"]["pinned"], st["dock"]["more"]), before)


class DraggingFromMoreAt125(DraggingFromMore):
    """The same at 125% Interface size, in a Slate of its own: the grid's window and the dock's
    both count in Slate's units, so it lands where it's let go just the same."""

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"uiScale": 1.25})
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_at_125(self):
        self.assertEqual(float(self.ipc("config", "get", "uiScale")), 1.25)
