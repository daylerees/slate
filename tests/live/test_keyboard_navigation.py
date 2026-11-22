"""Accessibility → the menu bar and the dock by keyboard (Super+Alt+B, Super+Alt+D; slate ipc
call keys bar|dock): the bar or the dock takes the keyboard, the arrow keys move along it, Enter
presses what's selected (a panel opened from the bar has the keyboard, and the bar's selection
ends), and Escape or the shortcut again gives the keyboard back.

Keys are typed for real with wtype, each sequence in one run (in the background, watched as it
goes): every wtype run is a new keyboard that goes away when it ends. The test session keeps one
more that never types (tests/lib/session.py), as a real keyboard stays plugged in: without it a
panel opened between runs could be left without the keyboard."""
import json
import os
import shutil
import subprocess

from live import LiveCase


class KeyboardNavigation(LiveCase):
    def type_keys(self, *keys, gap=500):
        """The keys, gap ms apart, in one wtype run (after a moment for its keymap)."""
        args = ["wtype", "-s", "1000"]
        for k in keys:
            args += ["-k", k, "-s", str(gap)]
        p = subprocess.Popen(args, env=self.s.env)
        self.addCleanup(p.kill)
        return p

    def until(self, cond, what, timeout=8):
        """wait(), saying where the keys and the panel were if it doesn't happen."""
        try:
            return self.wait(cond, what, timeout=timeout)
        except AssertionError:
            st = self.s.state()
            self.fail(f"{what}: keys {st['keys']}, panel {st['popout']!r} (has the keyboard: {st.get('popoutActive')}), "
                      f"panel keys {st.get('popoutKeyPath')}")

    def setUp(self):
        super().setUp()
        if not shutil.which("wtype"):
            self.skipTest("wtype isn't installed")
        self.addCleanup(lambda: self.ipc("keys", "stop"))

    def test_the_bar_moves_along(self):
        self.ipc("keys", "bar")
        first = self.until(lambda st: st["keys"]["bar"] and st["keys"]["barFocus"] != "", "the first thing selected")["keys"]["barFocus"]
        self.type_keys("Right", "Right", "Left", "Escape").wait(timeout=15)
        path = self.until(lambda st: len(st["keys"]["barPath"]) >= 4, "three moves")["keys"]["barPath"]
        self.assertEqual(path[0], first)
        self.assertEqual(path[1], path[3], f"Left didn't go back: {path}")
        self.assertEqual(len(set(path[:3])), 3, f"Right didn't move along: {path}")

    def test_enter_opens_its_panel_and_the_selection_ends(self):
        self.ipc("keys", "bar")
        first = self.until(lambda st: st["keys"]["bar"] and st["keys"]["barFocus"] != "", "the bar's first thing selected")["keys"]["barFocus"]
        self.assertEqual(first, "control", "the bar's first stop isn't the control center")
        self.type_keys("Return", "Escape", gap=1500)
        self.until(lambda st: st["popout"] == "control" and not st["keys"]["bar"], "Enter to open the control center")
        self.until(lambda st: st["popout"] == "", "Escape closes it")
        self.s.settle(0.5)
        self.assertFalse(self.s.state()["keys"]["bar"], "the bar took the keyboard back after its panel closed")

    def test_a_panel_opened_by_keyboard_has_its_first_control_chosen(self):
        """Super+Alt+B, Enter on the control center: its first control has the keyboard, and Down
        moves on, without Tab first (the arrow keys did nothing until then)."""
        self.ipc("keys", "bar")
        self.until(lambda st: st["keys"]["barFocus"] == "control", "the control center selected")
        self.type_keys("Return", "Down", "Up", "Escape", gap=1200)
        first = self.until(lambda st: st["popout"] == "control" and st["popoutKeyFocus"] != "", "its first control chosen as it opens")["popoutKeyFocus"]
        self.until(lambda st: st["popoutKeyFocus"] not in ("", first), "Down to the next control")
        self.until(lambda st: st["popoutKeyFocus"] == first, "Up back to the first")
        self.until(lambda st: st["popout"] == "", "Escape closes it")

    def test_down_goes_down_a_list_in_the_order_shown(self):
        """The Wi-Fi list: Down walks the networks top to bottom, as shown, even after they've
        been reordered (a list's rows are made and reused out of order, and Down used to follow
        that: it jumped up and down the list)."""
        self.keep_setting("barShowWifi")
        self.config("barShowWifi", "true")
        self.addCleanup(lambda: self.ipc("test", "wifi", ""))
        self.ipc("test", "wifi", json.dumps({"Home": 0.9, "Cafe": 0.6, "Library": 0.3, "Station": 0.2}))
        self.ipc("bar", "panel", "wifi")
        self.until(lambda st: st["popout"] == "wifi" and st["lists"]["panel"]["count"] == 4, "the four networks")
        # (reordered while open: Station to the top, Home to the bottom)
        self.ipc("test", "wifi", json.dumps({"Home": 0.1, "Cafe": 0.6, "Library": 0.3, "Station": 0.95}))
        order = self.until(lambda st: st["lists"]["panel"]["order"] == ["Station", "Cafe", "Library", "Home"], "the new order")["lists"]["panel"]["order"]
        self.type_keys(*(["Down"] * 12), gap=250).wait(timeout=30)
        st = self.s.state()
        path = st["popoutKeyPath"]
        seen = []
        for step in path:
            for name in order:
                if name in step and name not in seen:
                    seen.append(name)
        self.assertEqual(seen, order, f"Down didn't walk the networks in the order shown: {path} "
                                      f"(the panel has the keyboard: {st['popoutActive']})")

    def test_no_keys_coming_lets_go(self):
        """If no key reaches the bar or the dock at all, it doesn't keep the keyboard: after ten
        seconds the apps have it back by themselves."""
        for target in ("bar", "dock"):
            with self.subTest(target):
                self.ipc("keys", target)
                self.until(lambda st: st["keys"][target], "the keyboard to the " + target)
                self.s.settle(8)
                self.assertTrue(self.s.state()["keys"][target], "let go too soon")
                self.until(lambda st: not st["keys"][target], "let go with no keys coming", timeout=5)

    def test_zz_keys_coming_keep_it(self):
        # (last: it ends with its wtype keyboard gone while the bar still holds the keyboard)
        """Once keys arrive there's no time limit."""
        self.ipc("keys", "bar")
        self.until(lambda st: st["keys"]["bar"] and st["keys"]["barFocus"] != "", "the bar's first thing selected")
        self.type_keys("Right").wait(timeout=15)
        self.until(lambda st: len(st["keys"]["barPath"]) >= 2, "the key to arrive")
        self.s.settle(11)
        self.assertTrue(self.s.state()["keys"]["bar"], "let go while being used")

    def test_the_shortcut_again_leaves(self):
        for target in ("bar", "dock"):
            with self.subTest(target):
                self.ipc("keys", target)
                self.until(lambda st: st["keys"][target], "the keyboard to the " + target)
                self.ipc("keys", target)
                self.until(lambda st: not st["keys"][target], "the shortcut again to leave")

    def test_the_dock(self):
        self.ipc("keys", "dock")
        first = self.wait(lambda st: st["keys"]["dock"] and st["keys"]["dockIndex"] >= 0, "the dock's first icon")["keys"]["dockIndex"]
        self.type_keys("Right", "Home", "Escape")
        self.until(lambda st: not st["keys"]["dock"], "Escape gives the keyboard back", timeout=12)
        path = self.s.state()["keys"]["dockPath"]
        self.assertEqual(path[0], first)
        self.assertGreater(path[1], first, f"Right didn't move along: {path}")
        self.assertEqual(path[2], first, f"Home didn't go back to the first: {path}")


PANELS = ["control", "volume", "wifi", "bluetooth", "battery", "keyboard", "clipboard", "screenshot",
          "notifications", "calendar", "session", "gamemode", "windowmode", "drink", "focus", "spaces", "more"]


class EveryPanelControl(LiveCase):
    """Accessibility → every control in every bar panel can take the keyboard: nothing that
    takes a click is left out of Tab and the arrow keys (Popouts.unreachable lists any that
    are, by what they say and where). The panels are shown with something in them: a
    notification with an action, Wi-Fi networks, clipboard history."""

    def test_nothing_takes_a_click_but_not_the_keyboard(self):
        self.addCleanup(lambda: self.ipc("test", "wifi", ""))
        self.ipc("test", "wifi", json.dumps({"Home": 0.9, "Cafe": 0.6}))
        # (an urgent notification's pop-up stays until it's dismissed: left, it sat over whatever
        # the next tests in this session showed, and a picture of a panel's shadow under it changed)
        self.addCleanup(lambda: self.ipc("notifications", "clear"))
        # (this one only: an earlier one in the history let the wait end before it came)
        self.ipc("notifications", "clear")
        self.wait(lambda st: st["notifications"]["history"] == 0, "the notifications cleared")
        self.s.run(["notify-send", "-u", "critical", "-A", "open=Open", "--", "A note", "with an action"])
        self.wait(lambda st: st["notifications"]["history"] == 1, "the notification")
        # (a window, for New Space's workspace cards, and a space saved with it for the Spaces
        # panel's list)
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.s.settle(1.0)
        saved = os.path.join(self.s.h.data, "slate", "spaces.json")
        self.addCleanup(lambda: os.path.exists(saved) and os.remove(saved))
        spaces_before = self.s.state()["spaces"]["saved"]
        self.ipc("test", "saveSpace", "Keyboard walk", str(self.s.hyprctl("activeworkspace", json_out=True)["id"]))
        self.wait(lambda st: st["spaces"]["saved"] == spaces_before + 1, "the space saved")
        gaps = {}
        for name in PANELS + ["new space"]:
            panel = "spaces" if name == "new space" else name
            self.ipc("bar", "panel", panel)
            if not self.wait_or_none(lambda st: st["popout"] == panel):
                gaps[name] = ["(didn't open)"]
                continue
            if name == "new space":
                self.ipc("test", "newSpace")
            self.s.settle(0.8)
            found = json.loads(self.ipc("test", "panelWalk"))["gaps"]
            if found:
                gaps[name] = found
            self.ipc("popout", "close")
            self.wait(lambda st: st["popout"] == "", f"the {name} panel to close")
        self.assertEqual(gaps, {}, "controls the keyboard can't reach:\n" + json.dumps(gaps, indent=1))

    def test_delete_dismisses_a_notification_card(self):
        """In the bell panel, Down reaches a notification's card (with its close button showing)
        and Delete dismisses it."""
        if not shutil.which("wtype"):
            self.skipTest("wtype isn't installed")
        self.addCleanup(lambda: self.ipc("popout", "close"))
        self.addCleanup(lambda: self.ipc("notifications", "clear"))   # (if Delete didn't: see above)
        self.ipc("notifications", "clear")
        self.s.run(["notify-send", "-u", "critical", "--", "To dismiss", "by keyboard"])
        self.wait(lambda st: st["notifications"]["history"] == 1, "the notification")
        self.ipc("bar", "panel", "notifications")
        self.wait(lambda st: st["popout"] == "notifications", "the bell panel")
        self.s.settle(0.8)
        p = subprocess.Popen(["wtype", "-s", "1000", "-k", "Down", "-s", "400", "-k", "Down", "-s", "400", "-k", "Down",
                              "-s", "800", "-k", "Delete", "-s", "600"], env=self.s.env)
        self.addCleanup(p.kill)
        st = self.wait(lambda st: "To dismiss" in st["popoutKeyFocus"], "Down to the card", timeout=12)
        self.wait(lambda st: st["notifications"]["history"] == 0, "Delete to dismiss it", timeout=8)

    def wait_or_none(self, check, timeout=5):
        try:
            return self.wait(check, timeout=timeout)
        except AssertionError:
            return None
