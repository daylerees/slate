"""Touchpad gestures (Settings → Input → Gestures, session/hypr/config/gestures.lua):
Slate makes them in Hyprland with the fingers chosen, leaves free the directions set to do
nothing, takes them away when they're off, and what each one does works in a real session. (The container has no touchpad to swipe on, so the
gestures' own functions are called, as Hyprland calls them when one ends.)"""
from live import LiveCase

DIRECTIONS = ("horizontal", "up", "down", "pinchin", "pinchout")
# Made to start with, in Hyprland's names (pinching out does nothing until chosen; Slate's pinch
# in, fingers coming together, is Hyprland's "pinchout", as it names them by zoom)
DEFAULT = ("horizontal", "up", "down", "pinchout")


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

    def made(self, fingers, directions=DEFAULT):
        return all(self.has(fingers, d) for d in directions)

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

    def test_each_direction_as_chosen(self):
        """"Nothing" leaves a direction free; choosing something for pinch out makes it; Switch
        workspace one way only is Hyprland's swipe on that direction alone."""
        for key in ("gestureFingers", "gestureLeft", "gestureRight", "gestureUp", "gesturePinchOut"):
            self.keep_setting(key)
        self.config("gestureFingers", "3")
        self.config("gestureLeft", "workspace")
        self.config("gestureRight", "workspace")
        self.until(lambda: self.made(3) and not self.has(3, "pinchin"), "Slate's gestures, pinch out left free")
        self.config("gestureRight", "none")
        self.config("gestureUp", "none")
        self.config("gesturePinchOut", "desktop")
        self.until(lambda: not self.has(3, "horizontal") and not self.has(3, "right") and not self.has(3, "up")
                   and self.made(3, ("left", "down", "pinchin", "pinchout")),
                   "only left switching workspace, right and up left free, pinch out made")
        self.config("gestureRight", "launcher")
        self.until(lambda: self.made(3, ("left", "right")) and self.lua('GESTURE_ACTIONS.right == "launcher"'),
                   "swiping right for the launcher")
        self.s.hyprctl("dispatch", 'function() gesture("right") end')
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.wait(lambda st: st["launcher"]["open"], "the launcher to open")

    def test_up_opens_the_overview_and_again_closes_it(self):
        self.keep_setting("gestureUp")
        self.config("gestureUp", "overview")
        self.addCleanup(lambda: self.ipc("overview", "close"))
        self.until(lambda: self.lua('GESTURE_ACTIONS.up == "overview"'), "Hyprland to have the setting")
        self.s.hyprctl("dispatch", 'function() gesture("up") end')
        self.wait(lambda st: st["overview"]["open"], "the overview to open")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", 'function() gesture("up") end')
        self.wait(lambda st: not st["overview"]["open"], "the overview to close")

    def test_pinch_opens_the_launcher_and_another_gesture_closes_it(self):
        self.keep_setting("gesturePinchIn")
        self.config("gesturePinchIn", "launcher")
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.until(lambda: self.lua('GESTURE_ACTIONS.pinchin == "launcher"'), "Hyprland to have the setting")
        self.s.hyprctl("dispatch", 'function() gesture("pinchin") end')
        self.wait(lambda st: st["launcher"]["open"], "the launcher to open")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", 'function() gesture("down") end')
        self.wait(lambda st: not st["launcher"]["open"], "the launcher to close")

    def test_down_opens_the_launcher_when_chosen(self):
        self.keep_setting("gestureDown")
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.config("gestureDown", "launcher")
        self.until(lambda: self.lua('GESTURE_ACTIONS.down == "launcher"'), "Hyprland to have the setting")
        self.s.hyprctl("dispatch", 'function() gesture("down") end')
        self.wait(lambda st: st["launcher"]["open"], "the launcher to open")

    def test_show_the_desktop_and_back(self):
        """Swiping down moves the workspace's windows out of sight; swiping down again brings
        them back to their workspace."""
        self.keep_setting("gestureDown")
        self.config("gestureDown", "desktop")
        self.until(lambda: self.lua('GESTURE_ACTIONS.down == "desktop"'), "Hyprland to have the setting")
        self.close_windows()
        self.addCleanup(self.close_windows)
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() showDesktop(false) end"))
        for _ in range(2):
            self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        apps = lambda: [c for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped") and c.get("class") == "foot"]
        self.until(lambda: len(apps()) == 2, "two windows")
        self.s.settle(0.5)
        self.s.hyprctl("dispatch", 'function() gesture("down") end')
        self.until(lambda: all(c["workspace"]["name"] == "special:slate-desktop" for c in apps()), "the windows to go aside")
        self.assertTrue(self.lua("desktopShowing()"))
        self.assertEqual(self.s.hyprctl("activeworkspace", json_out=True)["id"], 1, "the workspace changed")
        self.s.hyprctl("dispatch", 'function() gesture("down") end')
        self.until(lambda: all(c["workspace"]["id"] == 1 for c in apps()), "the windows to come back")
        self.assertTrue(self.lua("not desktopShowing()"))
