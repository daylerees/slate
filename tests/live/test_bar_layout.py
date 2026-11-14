"""Arranging the menu bar (Settings → Menu Bar → Edit layout): what a drag, a click on the bar
or a button on the panel comes to, through the test hook (the session has no pointer)."""
import json
import os
import time

from PIL import Image

import imgdiff
import slate
from live import LiveCase

SHOWN = ["barShowControl", "barShowApps", "barShowSpaces", "barShowAssistant", "barShowWindowMode", "barShowWorkspaces", "barShowWorkspaceName",
         "barShowTray", "barShowNotifications", "barShowClipboard", "barShowScreenshot", "barShowCamera", "barShowGameMode",
         "barShowKeyboard", "barShowBluetooth", "barShowVolume", "barShowWifi", "barShowBattery", "barShowClock",
         "barShowPower", "barShowTitle", "barShowTitleIcon", "barStatusCollapsed"]
# Things that never show here, on the bar or not: the tests' computer has no tray apps, one
# keyboard layout and no Bluetooth
NEVER_HERE = ("tray", "keyboard", "bluetooth")


class BarLayout(LiveCase):
    def setUp(self):
        super().setUp()
        for key in SHOWN:                       # (put back after the arrangement is: cleanups run last first)
            self.keep_setting(key)
        self.addCleanup(lambda: (self.ipc("test", "arrange", "done", "", "", ""), self.ipc("test", "arrange", "reset", "", "", "")))
        self.do("reset")
        self.wait(lambda st: st["bar"]["isDefault"] and not st["bar"]["arranging"], "the bar as Slate's own")

    def until(self, read, check, timeout=10):
        """read() once check() is true of it (a Hyprland query, say), or as it is at `timeout`."""
        end = time.monotonic() + timeout
        while True:
            now = read()
            if check(now) or time.monotonic() > end:
                return now
            self.s.settle(0.1)

    def do(self, what, a="", b="", c=""):
        self.ipc("test", "arrange", what, str(a), str(b), str(c))
        self.steady(self.bar, floor=0.3)

    def bar(self):
        return json.loads(self.ipc("test", "state"))["bar"]

    def layout(self):
        return self.bar()["layout"]

    def where(self, item):
        for i, e in enumerate(self.layout()):
            if not isinstance(e, str) and item in e["items"]:
                return i
        self.fail(f"{item} isn't in the arrangement")

    def strip(self, name):
        """A picture of the bar's edge of the screen."""
        path = self.screenshot(name)
        img = Image.open(path)
        img.crop((0, 0, img.size[0], 64)).save(path)
        return path

    # ---- the arrangement ---------------------------------------------------------------
    def test_starts_as_slates_own(self):
        st = self.bar()
        self.assertTrue(st["isDefault"])
        # (Apps with Nova, and Spaces with the window mode and the workspace dots)
        self.assertEqual([e if isinstance(e, str) else e["items"] for e in st["layout"]][:5],
                         [["control"], ["apps", "nova"], ["spaces", "windowmode", "workspaces", "workspacename"],
                          ["windowicon", "windowtitle"], "space"])

    def test_an_old_layout_with_chalk_shows_nova(self):
        """An arrangement saved before the assistant was renamed names its button "chalk": it's
        read as Nova's (Config.barId), so the button stays where it was put."""
        import json as _json
        old = [{"items": ["control"]}, {"items": ["apps", "chalk"]}, {"items": ["spaces", "windowmode", "workspaces"]},
               "space", {"items": ["clock"]}, {"items": ["power"]}]
        self.do("load", _json.dumps(old))
        self.steady(self.bar, floor=0.5)
        boxes = [e["items"] for e in self.layout() if not isinstance(e, str)]
        self.assertIn(["apps", "nova"], boxes, boxes)
        self.assertNotIn("chalk", [i for b in boxes for i in b])

    def test_an_item_joins_a_container(self):
        to = self.where("clock")
        self.do("moveItem", "wifi", to, 0)
        self.assertEqual(self.layout()[self.where("clock")]["items"], ["wifi", "clock"])
        self.assertFalse(self.bar()["isDefault"])

    def test_an_item_gets_a_container_of_its_own(self):
        self.do("moveItem", "wifi", 0, -1)
        self.assertEqual(self.layout()[0]["items"], ["wifi"])
        self.assertEqual(self.layout()[1]["items"], ["control"])

    def test_a_container_left_empty_goes(self):
        # (the power button is alone in its container: moved out, that container has nothing left)
        before = len(self.layout())
        self.do("moveItem", "power", self.where("control"), 1)
        self.assertEqual(len(self.layout()), before - 1)
        self.assertEqual(self.layout()[0]["items"], ["control", "power"])

    def test_a_container_moves_whole(self):
        at = self.where("clock")
        self.do("moveEntry", at, 0)
        self.assertEqual(self.layout()[0]["items"], ["clock"])

    def test_split_up(self):
        at = self.where("windowmode")
        self.assertEqual(self.layout()[at]["items"], ["spaces", "windowmode", "workspaces", "workspacename"])
        self.do("split", at)
        self.assertEqual([e["items"] for e in self.layout()[at:at + 4]], [["spaces"], ["windowmode"], ["workspaces"], ["workspacename"]])

    def test_flexible_spaces(self):
        n = self.layout().count("space")
        self.do("addSpace", 0)
        self.assertEqual(self.layout()[0], "space")
        self.assertEqual(self.layout().count("space"), n + 1)
        self.do("remove", 0)
        self.assertEqual(self.layout().count("space"), n)

    def test_the_last_flexible_space_stays(self):
        at = self.layout().index("space")
        self.assertEqual(self.layout().count("space"), 1)
        self.do("remove", at)
        self.assertEqual(self.layout().count("space"), 1, "the bar's only flexible space was taken away")
        self.do("addSpace", 0)
        self.do("remove", self.layout().index("space", 1))
        self.assertEqual(self.layout().count("space"), 1)

    def test_shortcuts_stand_down_while_arranging(self):
        """Hyprland's shortcuts are off while the bar's arranged (a set of keys of its own), and
        back after."""
        self.assertIn("default", self.s.hyprctl("submap"))
        self.do("start")
        self.assertIn("slate-arranging", self.until(lambda: self.s.hyprctl("submap"), lambda v: "slate-arranging" in v))
        self.ipc("bar", "edit", "done")             # (what Escape runs there)
        self.s.wait(lambda st: not st["bar"]["arranging"], what="arranging to end")
        self.assertIn("default", self.until(lambda: self.s.hyprctl("submap"), lambda v: "default" in v))

    def test_an_empty_container_stays_only_while_arranging(self):
        self.do("start")
        self.do("addBox", 0)
        self.assertEqual(self.layout()[0]["items"], [])
        self.do("moveItem", "wifi", 0, 0)
        self.assertEqual(self.layout()[0]["items"], ["wifi"])
        self.do("addBox", 0)
        self.assertEqual(self.layout()[0]["items"], [])
        self.do("done")
        self.assertEqual(self.layout()[0]["items"], ["wifi"])

    # ---- the collapse button -------------------------------------------------------------
    def test_collapse_button(self):
        at = self.where("wifi")
        self.do("tuck", at, "true")
        box = self.layout()[at]
        self.assertTrue(box["tuck"])
        self.assertEqual(box["items"][-1], "tuck")
        self.do("tuckFrom", at, "start")
        self.assertEqual(self.layout()[at]["items"][0], "tuck")
        self.assertEqual(self.layout()[at]["tuckFrom"], "start")
        self.do("tuck", at, "", "ea95")
        self.assertEqual(self.layout()[at]["tuckIcon"], "ea95")
        # An item dropped at its very start goes after the button, which keeps its end
        self.do("moveItem", "clock", at, 0)
        self.assertEqual(self.layout()[at]["items"][:2], ["tuck", "clock"])

    def test_collapse_button_moves_between_containers(self):
        a, b = self.where("wifi"), self.where("windowmode")
        self.do("tuck", a, "true")
        self.do("moveTuck", a, b, 0)
        self.assertFalse(self.layout()[a]["tuck"])
        self.assertEqual(self.layout()[b]["items"][0], "tuck")
        self.do("moveTuck", b, -1, 0)              # dropped outside any container: gone
        self.assertFalse(self.layout()[b]["tuck"])

    # ---- the pool ----------------------------------------------------------------------------
    def test_the_pool_and_back(self):
        self.do("shown", "wifi", "false")
        self.assertEqual(self.setting("barShowWifi"), "false")
        at = self.where("wifi")                     # (it keeps its place)
        self.do("carry", "item", "wifi", json.dumps({"join": False, "to": 0, "slot": -1}))
        self.assertEqual(self.setting("barShowWifi"), "true")
        self.assertEqual(self.layout()[0]["items"], ["wifi"])
        self.assertNotEqual(at, 0)

    def test_back_from_the_pool_a_thing_has_its_text_on_again(self):
        self.keep_setting("barValueWifi")
        self.config("barValueWifi", "false")
        self.do("shown", "wifi", "false")
        self.assertEqual(self.setting("barValueWifi"), "false")
        self.do("shown", "wifi", "true")
        self.assertEqual(self.setting("barValueWifi"), "true", "put back on the bar, Wi-Fi's text stayed off")

    def test_carrying_a_space_a_container_and_a_collapse_button(self):
        self.do("start")
        self.do("carry", "space", "", json.dumps({"join": False, "to": 0, "slot": -1}))
        self.assertEqual(self.layout()[0], "space")
        self.do("carry", "box", "", json.dumps({"join": False, "to": 0, "slot": -1}))
        self.assertEqual(self.layout()[0]["items"], [])
        at = self.where("wifi")
        self.do("carry", "tuck", "", json.dumps({"join": True, "to": at, "slot": 0}))
        self.assertEqual(self.layout()[at]["items"][0], "tuck")
        self.do("done")

    # ---- the panel, and picking ----------------------------------------------------------------
    def test_the_panel_shows_while_arranging(self):
        self.do("start")
        self.s.wait(lambda st: st["bar"]["editor"], what="the arranging panel")
        self.assertIn("namespace: slate-bar-editor", self.s.hyprctl("layers"))
        at = self.where("wifi")
        self.do("pick", at, "wifi")
        self.assertEqual((self.bar()["picked"], self.bar()["pickedItem"]), (at, "wifi"))
        self.do("pick", at, "wifi")                  # again: let go
        self.assertEqual(self.bar()["picked"], -1)
        self.do("pick", at, "")
        self.do("done")
        self.s.wait(lambda st: not st["bar"]["editor"], what="the panel to go")
        self.assertEqual(self.bar()["picked"], -1)

    def test_windows_are_dimmed_while_arranging(self):
        """A dark wash lies over the windows and the desktop, under the bar (which goes up a
        layer meanwhile) and its panel; everything's back as it was after."""
        def level(namespace):
            for mon in self.s.hyprctl("layers", json_out=True).values():
                for lvl, layers in mon["levels"].items():
                    if any(l["namespace"] == namespace for l in layers):
                        return int(lvl)
            return -1
        self.assertEqual((level("slate-wallpaper"), level("slate-bar"), level("slate-bar-dim")), (0, 2, -1))
        def levels():
            return (level("slate-wallpaper"), level("slate-bar"), level("slate-bar-dim"))
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.until(lambda: [c for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped") and c.get("class") == "foot"],
                   bool, timeout=20)
        self.do("start")
        self.s.wait(lambda st: st["bar"]["editor"], what="the arranging panel")
        self.assertEqual(self.until(levels, lambda v: v == (0, 3, 2)), (0, 3, 2))
        self.screenshot("bar-arranging-over-a-window")
        self.do("done")
        self.assertEqual(self.until(levels, lambda v: v == (0, 2, -1)), (0, 2, -1))
        self.close_windows()

    def test_settings_steps_aside(self):
        self.ipc("settings", "open")
        self.s.wait(lambda st: st["settings"]["open"], what="Settings")
        self.do("start")
        self.s.wait(lambda st: not st["settings"]["open"], what="Settings to step aside")
        self.do("done")
        self.s.wait(lambda st: st["settings"]["open"], what="Settings to come back")
        self.ipc("settings", "close")

    def test_the_outermost_buttons_panel_meets_the_screen_edge(self):
        self.ipc("bar", "panel", "session")
        self.s.wait(lambda st: st["popout"] == "session")
        self.assertEqual(self.bar()["edge"], "end")
        self.ipc("popout", "close")
        self.do("moveEntry", self.where("clock"), len(self.layout()))     # the clock last now
        self.wait(lambda st: max((t for t in st["bar"]["line"].values() if t["visible"]), key=lambda t: t["x"])
                  == st["bar"]["line"]["clock"], "the clock to be the bar's last")
        self.ipc("bar", "panel", "calendar")
        self.s.wait(lambda st: st["popout"] == "calendar")
        self.assertEqual(self.bar()["edge"], "end")
        self.ipc("popout", "close")
        self.ipc("bar", "panel", "session")
        self.s.wait(lambda st: st["popout"] == "session")
        self.assertEqual(self.bar()["edge"], "")
        self.ipc("popout", "close")

    # ---- the bar's right-click menu -----------------------------------------------------------------
    def test_right_click_menu(self):
        self.keep_setting("barAutoHide")
        self.ipc("test", "barMenu", "open")
        self.s.wait(lambda st: st["bar"]["menu"] == ["Auto-hide", "Position", "Clock", "Edit layout", None, "Menu bar settings"],
                    what="the bar's menu")
        self.assertIn("namespace: slate-desktop-menu", self.s.hyprctl("layers"))
        was = self.setting("barAutoHide")
        self.ipc("test", "barMenu", "Auto-hide")
        self.s.wait(lambda st: st["bar"]["menu"] == [], what="the menu to close")
        self.assertNotEqual(self.setting("barAutoHide"), was)
        self.ipc("test", "barMenu", "open")
        self.ipc("test", "barMenu", "Edit layout")
        self.s.wait(lambda st: st["bar"]["editor"], what="the arranging panel, straight from the menu")
        self.do("done")

    # ---- nothing left blank ---------------------------------------------------------------------
    def blanks(self, name):
        """The things showing on the bar that have nothing drawn where they are. (Pictured once
        the bar has stopped moving: a thing still sliding into its place after a drag was looked
        for where it was going, under a heavily loaded test run, and found blank.)"""
        line = None
        for _ in range(25):
            now = self.bar()["line"]
            if now == line:
                break
            line = now
            self.s.settle(0.2)
        path = self.strip(name)
        img = Image.open(path).convert("RGB")
        self.assertEqual(self.bar()["line"], line, "the bar moved while it was being pictured")
        out = []
        for thing, t in line.items():
            if not t["visible"] or t["w"] < 4:
                continue
            box = img.crop((t["x"] + 2, t["y"] + 2, t["x"] + t["w"] - 2, t["y"] + t["h"] - 2))
            if len(box.getcolors(100000) or [0] * 99) <= 3:
                out.append(thing)
        return out

    def test_taking_each_thing_off_leaves_nothing_blank(self):
        """Dragged off the bar, a thing goes and the rest close up; Defaults brings it back,
        drawn. (One left an empty place between two dividers, which Defaults didn't mend.)"""
        self.do("start")
        for item in ("control", "apps", "spaces", "windowmode", "workspaces", "tray", "notifications", "clipboard", "screenshot",
                     "gamemode", "keyboard", "bluetooth", "volume", "wifi", "battery", "clock", "power"):
            with self.subTest(item):
                usual = self.bar()["line"][item]["visible"]     # (as Slate has it, before it's shown)
                self.do("shown", item, "true")
                self.wait(lambda st: st["bar"]["line"][item]["visible"] or item in NEVER_HERE, f"{item} on the bar")
                self.do("shown", item, "false")
                self.wait(lambda st: not st["bar"]["line"][item]["visible"], f"{item} to leave the bar")
                self.assertEqual(self.blanks("bar-off-" + item), [], f"with {item} off the bar")
                self.assertFalse(self.bar()["line"][item]["visible"], f"{item} still has a place on the bar")
                self.do("reset")
                self.wait(lambda st: st["bar"]["isDefault"] and st["bar"]["line"][item]["visible"] == usual,
                          f"{item} back as Slate has it")
                self.assertEqual(self.blanks("bar-back-" + item), [], f"after Defaults, having taken {item} off")
        self.do("done")

    def test_dragging_each_thing_off_leaves_nothing_blank(self):
        """The same with a real drag: picked up where it is and let go well below the bar."""
        self.do("start")
        self.wait(lambda st: st["bar"]["editor"], "the arranging panel")
        for item in ("control", "apps", "spaces", "windowmode", "workspaces", "notifications", "volume", "wifi", "clock", "power"):
            with self.subTest(item):
                t = self.bar()["line"][item]
                self.assertTrue(t["visible"], f"{item} isn't on the bar to drag")
                x, y = t["x"] + t["w"] // 2, t["y"] + t["h"] // 2
                self.do("drag", x, y, f"{x + 30},{y + 200}")
                self.steady(self.bar, floor=0.8)
                self.assertFalse(self.bar()["line"][item]["visible"], f"{item} is still on the bar")
                self.assertEqual(self.blanks("bar-dragged-" + item), [], f"with {item} dragged off")
                self.do("reset")
                self.steady(self.bar, floor=0.8)
                self.assertTrue(self.bar()["line"][item]["visible"], f"{item} didn't come back")
                self.assertEqual(self.blanks("bar-undragged-" + item), [], f"after Defaults, having dragged {item} off")
        self.do("done")

    def test_dragging_a_thing_into_another_container(self):
        self.do("start")
        self.steady(self.bar, floor=0.6)
        line = self.bar()["line"]
        a, b = line["wifi"], line["clock"]
        self.do("drag", a["x"] + a["w"] // 2, a["y"] + a["h"] // 2, f"{b['x'] + b['w'] // 2},{b['y'] + b['h'] // 2}")
        self.steady(self.bar, floor=0.8)
        self.assertIn("wifi", self.layout()[self.where("clock")]["items"])
        self.assertEqual(self.blanks("bar-dragged-into"), [])
        self.do("done")

    # ---- defaults ---------------------------------------------------------------------------------
    def test_defaults_put_everything_back_and_draw_it(self):
        """Restoring the defaults left gaps where some icons should be: they had their room on
        the bar and were never drawn."""
        before = self.strip("bar-layout-before")
        self.do("shown", "wifi", "false")
        self.do("shown", "volume", "false")
        self.do("shown", "power", "false")
        self.do("moveItem", "clock", 0, -1)
        self.do("moveItem", "notifications", self.where("apps"), 0)
        self.wait(lambda st: st["bar"]["layout"][0]["items"] == ["clock"]
                  and not any(st["bar"]["line"][t]["visible"] for t in ("wifi", "volume", "power")),
                  "the bar rearranged")
        self.do("reset")
        self.steady(self.bar, floor=1)
        self.assertTrue(self.bar()["isDefault"])
        after = self.strip("bar-layout-after")
        # (and each thing that's showing has something drawn in its place)
        img = Image.open(after).convert("RGB")
        for name, t in self.bar()["line"].items():
            if not t["visible"] or t["w"] < 4:
                continue
            box = img.crop((t["x"] + 2, t["y"] + 2, t["x"] + t["w"] - 2, t["y"] + t["h"] - 2))
            self.assertGreater(len(box.getcolors(100000) or [0] * 99), 3, f"nothing is drawn where {name} is")
        result = imgdiff.compare(before, after)
        if not result.ok:
            imgdiff.save_diff(before, after, os.path.join(slate.OUT, "live", "bar-layout-diff.png"))
        self.assertTrue(result.ok, "the bar after Defaults isn't the bar before: " + result.reason)
