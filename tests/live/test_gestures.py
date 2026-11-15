"""Touchpad gestures (Settings → Input → Touchpad gestures, session/hypr/config/gestures.lua):
Slate makes them in Hyprland with the fingers chosen and takes them away when they're off, and
what each one does works in a real session. (The container has no touchpad to swipe on, so the
gestures' own functions are called, as Hyprland calls them when one ends.)"""
from live import LiveCase

DIRECTIONS = ("horizontal", "up", "down", "pinchin", "pinchout")


class Gestures(LiveCase):
    def lua(self, expr):
        """Whether expr is true in Hyprland's Lua config."""
        code, _ = self.s.run(["hyprctl", "eval", f"assert({expr})"])
        return code == 0

    def has(self, fingers, direction):
        """Whether Hyprland has a gesture on these fingers and direction (asked by making one,
        which it refuses, saying so, when there is: one made to ask is taken away again).
        Through Hyprland's own hl.gesture, so gestures.lua doesn't take it for one of yours."""
        g = f'fingers = {fingers}, direction = "{direction}"'
        _, out = self.s.run(["hyprctl", "eval", f"SLATE_HL_GESTURE({{ {g}, action = function() end }})"])
        if "overshadowed" in out:
            return True
        self.s.run(["hyprctl", "eval", f'SLATE_HL_GESTURE({{ {g}, action = "unset" }})'])
        return False

    def made(self, fingers):
        return all(self.has(fingers, d) for d in DIRECTIONS)

    def none(self, fingers):
        return not any(self.has(fingers, d) for d in DIRECTIONS)

    def until(self, check, what, timeout=10):
        import time
        end = time.time() + timeout
        while time.time() < end:
            if check():
                return
            self.s.settle(0.2)
        self.fail(f"timed out waiting for {what}")

    def test_made_with_the_fingers_chosen_and_taken_away_when_off(self):
        self.keep_setting("touchpadGestures")
        self.keep_setting("gestureFingers")
        self.config("touchpadGestures", "true")
        self.config("gestureFingers", "3")
        self.until(lambda: self.made(3) and self.none(4), "Slate's three-finger gestures")
        self.config("gestureFingers", "4")
        self.until(lambda: self.made(4) and self.none(3), "the gestures to move to four fingers")
        self.config("touchpadGestures", "false")
        self.until(lambda: self.none(4) and self.none(3), "the gestures to be taken away")
        self.config("touchpadGestures", "true")
        self.until(lambda: self.made(4), "the gestures to come back")

    def test_made_again_after_a_reload(self):
        """Hyprland forgets every gesture when its config reloads: Slate makes its own again."""
        self.keep_setting("gestureFingers")
        self.config("gestureFingers", "3")
        self.until(lambda: self.made(3), "Slate's gestures")
        self.s.hyprctl("reload")
        self.s.settle(1)
        self.until(lambda: self.made(3), "Slate's gestures after a reload", timeout=15)

    def test_up_opens_the_overview_and_down_closes_it(self):
        self.addCleanup(lambda: self.ipc("overview", "close"))
        self.s.hyprctl("dispatch", "function() gestureUp() end")
        self.wait(lambda st: st["overview"]["open"], "the overview to open")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", "function() gestureDown() end")
        self.wait(lambda st: not st["overview"]["open"], "the overview to close")

    def test_pinch_opens_and_closes_the_launcher(self):
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.s.hyprctl("dispatch", "function() gesturePinch(true) end")
        self.wait(lambda st: st["launcher"]["open"], "the launcher to open")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", "function() gesturePinch(false) end")
        self.wait(lambda st: not st["launcher"]["open"], "the launcher to close")

    def test_down_opens_the_launcher_when_chosen(self):
        self.keep_setting("gestureSwipeDown")
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.config("gestureSwipeDown", "launcher")
        self.until(lambda: self.lua('GESTURE_DOWN == "launcher"'), "Hyprland to have the setting")
        self.s.hyprctl("dispatch", "function() gestureDown() end")
        self.wait(lambda st: st["launcher"]["open"], "the launcher to open")

    def test_show_the_desktop_and_back(self):
        """Swiping down moves the workspace's windows out of sight; swiping up brings them back
        to their workspace."""
        self.close_windows()
        self.addCleanup(self.close_windows)
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() showDesktop(false) end"))
        for _ in range(2):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        apps = lambda: [c for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped") and c.get("class") == "foot"]
        self.until(lambda: len(apps()) == 2, "two windows")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", "function() gestureDown() end")
        self.until(lambda: all(c["workspace"]["name"] == "special:slate-desktop" for c in apps()), "the windows to go aside")
        self.assertTrue(self.lua("desktopShowing()"))
        self.assertEqual(self.s.hyprctl("activeworkspace", json_out=True)["id"], 1, "the workspace changed")
        self.s.hyprctl("dispatch", "function() gestureUp() end")
        self.until(lambda: all(c["workspace"]["id"] == 1 for c in apps()), "the windows to come back")
        self.assertTrue(self.lua("not desktopShowing()"))
        self.assertFalse(self.s.state()["overview"]["open"], "swiping up opened the overview as well")
