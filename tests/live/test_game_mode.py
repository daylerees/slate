"""Game mode turns Hyprland's effects off, and turning it off puts them back."""
import os

from live import LiveCase

OPTIONS = ("decoration:blur:enabled", "decoration:shadow:enabled")


class GameMode(LiveCase):
    def option(self, name):
        o = self.s.hyprctl("getoption", name, json_out=True)
        for k in ("bool", "int", "float", "str"):
            if k in o:
                return int(o[k]) if k == "bool" else o[k]
        return None

    def test_on_and_off(self):
        self.keep_setting("gameMode")
        self.config("gameMode", "false")
        self.s.settle(1.5)
        before = {o: self.option(o) for o in OPTIONS}
        self.config("gameMode", "true")
        self.wait(lambda st: st["gameMode"], "game mode")
        self.s.settle(1.5)
        for o in OPTIONS:
            with self.subTest(o):
                self.assertEqual(self.option(o), 0, f"{o} still on in game mode")
        self.config("gameMode", "false")
        self.wait(lambda st: not st["gameMode"])
        self.s.settle(2.5)        # Hyprland reloads its config, then Slate's settings go back on
        for o in OPTIONS:
            with self.subTest(o + " restored"):
                self.assertEqual(self.option(o), before[o])

    def lua(self, expression):
        """What this Lua comes to in Hyprland's config, as text."""
        out = os.path.join(self.s.h.runtime, "game-mode-lua")
        if os.path.exists(out):
            os.remove(out)
        self.s.hyprctl("dispatch", f'function() local f = io.open("{out}", "w"); f:write(tostring({expression})); f:close() end')
        for _ in range(20):
            if os.path.exists(out):
                return open(out).read()
            self.s.settle(0.1)
        self.fail(f"couldn't read {expression} from Hyprland")

    def arrived(self, after=-1):
        """Wait for Slate's settings to reach Hyprland, all of them: the count of pushes is the
        last thing in what Slate sends, so it only arrives if nothing before it went wrong."""
        st = self.wait(lambda st: not st["hypr"]["busy"] and st["hypr"]["pushes"] > after,
                       "Slate's settings to go to Hyprland", timeout=15)
        for _ in range(50):
            if self.lua("SLATE_TEST_PUSHES") == str(self.s.state()["hypr"]["pushes"]):
                return
            self.s.settle(0.2)
        self.fail(f"Hyprland didn't run all of Slate's settings (push {st['hypr']['pushes']}): an error in them?")

    def test_terminals_go_solid(self):
        """Game mode's rule that makes terminals solid (slate-game-opaque) is made from the
        session's one list of terminals, TERMINAL_CLASSES, and made again when that changes.
        (Slate had a list of its own, longer than the session's.)"""
        self.keep_setting("gameMode")
        self.keep_setting("wrapWorkspaces")
        made = "SLATE_GAME_OPAQUE ~= nil and SLATE_GAME_OPAQUE_FOR == TERMINAL_CLASSES"
        self.config("gameMode", "false")
        self.arrived()
        self.assertEqual(self.lua(made), "true", "no rule for the session's terminals")
        self.assertEqual(self.lua('TERMINAL_CLASSES:find("foot", 1, true) ~= nil'), "true")
        pushes = self.s.state()["hypr"]["pushes"]
        self.config("gameMode", "true")
        self.wait(lambda st: st["gameMode"], "game mode")
        self.arrived(after=pushes)
        self.assertEqual(self.lua(made), "true")
        # The list changes under a Hyprland that's still running: the rule follows it
        self.s.hyprctl("dispatch", 'function() TERMINAL_CLASSES = TERMINAL_CLASSES .. "|slate-test-terminal" end')
        pushes = self.s.state()["hypr"]["pushes"]
        self.config("wrapWorkspaces", "false" if self.setting("wrapWorkspaces") == "true" else "true")
        self.arrived(after=pushes)
        self.assertEqual(self.lua(made), "true", "the rule wasn't made again for the changed list")
        self.assertEqual(self.lua('SLATE_GAME_OPAQUE_FOR:find("slate-test-terminal", 1, true) ~= nil'), "true")
        # Game mode off reloads Hyprland's config, which puts the list back
        pushes = self.s.state()["hypr"]["pushes"]
        self.config("gameMode", "false")
        self.wait(lambda st: not st["gameMode"])
        self.arrived(after=pushes)
        self.s.settle(2.5)
        self.arrived()
        self.assertEqual(self.lua('TERMINAL_CLASSES:find("slate-test-terminal", 1, true) == nil'), "true")
        self.assertEqual(self.lua(made), "true", "no rule for the session's terminals after game mode")
