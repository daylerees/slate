"""Game mode turns Hyprland's effects off, and turning it off puts them back."""
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
