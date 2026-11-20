"""Games (Steam's, by their steam_app_… class, and gamescope) go full screen on a workspace of
their own at the end, and you with them: a numbered one like any other, with a dot on the menu
bar, that Super+Left and Right reach. They once went to a named workspace, "gaming", which in
Hyprland 0.57 has no number at all: no dot, out of reach of the keys, and Steam's own window
was caught there too."""
from live import LiveCase

GAME = "steam_app_4000"


class GamesWorkspace(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(self.close_windows)

    def until(self, read, what, timeout=10):
        for _ in range(int(timeout / 0.1)):
            got = read()
            if got:
                return got
            self.s.settle(0.1)
        self.fail(f"timed out waiting for {what}")

    def windows(self, cls):
        return [c for c in self.s.hyprctl("clients", json_out=True) if c["class"] == cls and c["mapped"]]

    def open(self, cls, n):
        self.s.hyprctl("dispatch", 'function() hl.exec_cmd("foot --app-id %s") end' % cls)
        return self.until(lambda: len(self.windows(cls)) >= n and self.windows(cls), f"{cls} window {n}")

    def test_a_game_gets_a_numbered_workspace_at_the_end(self):
        self.open("foot", 1)                      # workspace 1 in use
        self.open(GAME, 1)
        ws = self.until(lambda: [c["workspace"] for c in self.windows(GAME) if c["workspace"].get("id") == 2],
                        "the game on workspace 2, the one after the last in use")[0]
        self.assertEqual(ws["name"], "2")
        self.until(lambda: self.s.hyprctl("activeworkspace", json_out=True).get("id") == 2, "you taken there with it")
        # A dot for it on the bar, like any other
        self.wait(lambda st: 2 in st["overview"]["known"], "Slate to know of workspace 2")

    def test_a_second_window_joins_the_first(self):
        self.open(GAME, 1)
        first = self.until(lambda: next((c["workspace"].get("id") for c in self.windows(GAME) if c["workspace"].get("id")), None),
                           "the game on a numbered workspace")
        self.open(GAME, 2)
        self.until(lambda: len({c["workspace"].get("id") for c in self.windows(GAME)}) == 1
                   and self.windows(GAME)[0]["workspace"].get("id") == first, "both of the game's windows together")

    def test_no_named_workspace(self):
        self.open(GAME, 1)
        self.s.settle(0.5)
        self.assertEqual([w["name"] for w in self.s.hyprctl("workspaces", json_out=True) if "id" not in w], [])
