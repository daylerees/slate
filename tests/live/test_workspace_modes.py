"""Each workspace's own window mode (the menu bar's workspace indicator; Settings → Windows sets
the default): its layout, floating new windows, re-tiling when it's put back, and the default
for the rest."""
from live import LiveCase


class WorkspaceModes(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        self.keep_setting("windowMode")
        self.config("windowMode", "tiling")
        self.addCleanup(lambda: [self.ipc("workspacemode", "set", str(i), "") for i in range(1, 21)])

    def go(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.s.settle(0.4)

    def layout(self, ws):
        w = next((w for w in self.s.hyprctl("workspaces", json_out=True) if w["id"] == ws), None)
        return w and w.get("tiledLayout")

    def foot_on(self, ws):
        self.go(ws)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            new = [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before]
            if new:
                self.s.settle(0.5)
                return next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == new[0]["address"])
            self.s.settle(0.2)
        self.fail("no new window")

    def test_layout_of_its_own(self):
        self.ipc("workspacemode", "set", "7", "scrolling")
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "scrolling")
        self.foot_on(7)
        self.assertEqual(self.layout(7), "scrolling")
        # put back to the default
        self.ipc("workspacemode", "set", "7", "")
        for _ in range(20):
            if self.layout(7) == "dwindle":
                break
            self.s.settle(0.1)
        self.assertEqual(self.layout(7), "dwindle")

    def test_floating_workspace_among_tiled(self):
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")      # (floating without needing hyprbars)
        self.ipc("workspacemode", "set", "8", "floating")
        self.s.settle(0.5)
        floated = self.foot_on(8)
        self.assertTrue(floated["floating"], "a new window on a floating workspace should float")
        tiled = self.foot_on(7)
        self.assertFalse(tiled["floating"], "the default (tiling) workspace shouldn't float it")
        # back to the default: workspace 8's window is tiled again
        self.ipc("workspacemode", "set", "8", "")
        for _ in range(20):
            c = next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == floated["address"])
            if not c["floating"]:
                break
            self.s.settle(0.1)
        self.assertFalse(c["floating"], "not re-tiled when the workspace went back to the default")

    def test_solo_one_window_per_workspace(self):
        """Solo: a second window opening on the workspace moves on to a new one of its own, which
        is Solo too; dialogs (floating) would stay."""
        self.ipc("workspacemode", "set", "9", "solo")
        self.s.settle(0.4)
        first = self.foot_on(9)
        second = self.foot_on(9)
        by = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
        self.assertEqual(by[first["address"]]["workspace"]["id"], 9)
        moved_to = by[second["address"]]["workspace"]["id"]
        self.assertNotEqual(moved_to, 9, "the second window stayed on the Solo workspace")
        on_nine = [c for c in by.values() if c["workspace"]["id"] == 9 and not c["floating"]]
        self.assertEqual(len(on_nine), 1)
        self.assertEqual(self.ipc("workspacemode", "get", str(moved_to)), "solo", "its new workspace isn't Solo")

    def test_switching_to_solo_spreads_every_window(self):
        """Switching a workspace to Solo gives every window on it a workspace of its own, filling
        it: floating ones are tiled first (dialogs would stay floating with their app)."""
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")
        self.ipc("workspacemode", "set", "10", "floating")
        self.s.settle(0.4)
        a, b = self.foot_on(10), self.foot_on(10)
        self.assertTrue(a["floating"] and b["floating"])
        self.ipc("workspacemode", "set", "10", "solo")
        for _ in range(30):
            by = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
            if by[a["address"]]["workspace"]["id"] != by[b["address"]]["workspace"]["id"]:
                break
            self.s.settle(0.1)
        self.assertNotEqual(by[a["address"]]["workspace"]["id"], by[b["address"]]["workspace"]["id"], "both still on one workspace")
        for w in (a, b):
            self.assertFalse(by[w["address"]]["floating"], "still floating: it wouldn't fill its workspace")
        moved = by[b["address"]]["workspace"]["id"] if by[a["address"]]["workspace"]["id"] == 10 else by[a["address"]]["workspace"]["id"]
        # (Hyprland's config tells Slate the new workspace is Solo too, a moment after the move)
        for _ in range(40):
            if self.ipc("workspacemode", "get", str(moved)) == "solo":
                break
            self.s.settle(0.1)
        self.assertEqual(self.ipc("workspacemode", "get", str(moved)), "solo")

    # ---- Changing the default with windows open (Settings asks: tidy up, or leave them) ----
    def window(self, w):
        return next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])

    def test_tidy_moves_every_workspace_to_the_new_default(self):
        """Tidy up: the workspaces following the default and the ones with a mode of their own."""
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")
        follows = self.foot_on(6)
        self.ipc("workspacemode", "set", "7", "scrolling")
        own = self.foot_on(7)
        self.ipc("workspacemode", "set", "8", "master")          # (empty, with its own mode)
        self.assertEqual(self.ipc("workspacemode", "notIn", "floating"), "6,7")
        self.ipc("workspacemode", "setDefault", "floating", "true")
        self.s.settle(1.5)
        self.assertEqual(self.setting("windowMode"), "floating")
        for ws in (6, 7, 8):
            self.assertEqual(self.ipc("workspacemode", "get", str(ws)), "", f"workspace {ws} should follow the default")
        self.assertTrue(self.window(follows)["floating"], "the window on the workspace following the default")
        self.assertTrue(self.window(own)["floating"], "the window on the workspace with its own mode")
        self.assertEqual(self.ipc("workspacemode", "notIn", "floating"), "")

    def test_leave_keeps_each_workspace_in_its_mode(self):
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")
        follows = self.foot_on(6)
        self.ipc("workspacemode", "set", "7", "scrolling")
        self.foot_on(7)
        self.ipc("workspacemode", "setDefault", "floating", "false")
        self.s.settle(1.5)
        self.assertEqual(self.setting("windowMode"), "floating")
        self.assertEqual(self.ipc("workspacemode", "get", "6"), "tiling", "it should keep the old default as its own")
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "scrolling")
        self.assertFalse(self.window(follows)["floating"], "the open window was rearranged")
        self.assertEqual(self.layout(7), "scrolling")
        # a window opened there still tiles; one on a new workspace floats
        self.assertFalse(self.foot_on(6)["floating"])
        self.assertTrue(self.foot_on(9)["floating"])

    def test_own_mode_matching_the_new_default_follows_it(self):
        self.ipc("workspacemode", "set", "7", "scrolling")
        self.foot_on(7)
        self.assertEqual(self.ipc("workspacemode", "notIn", "scrolling"), "", "nothing to tidy: Settings wouldn't ask")
        self.ipc("workspacemode", "setDefault", "scrolling", "false")
        self.s.settle(0.8)
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "")
        self.assertEqual(self.layout(7), "scrolling")

    def test_empty_workspaces_are_not_pinned(self):
        self.go(8)
        self.assertEqual(self.ipc("workspacemode", "notIn", "master"), "")
        self.ipc("workspacemode", "setDefault", "master", "false")
        self.s.settle(0.6)
        self.assertEqual(self.ipc("workspacemode", "get", "8"), "")


class SecretWorkspace(LiveCase):
    """The secret (special) workspace showing with nothing on it: a note in the middle of the
    screen says it's empty (SecretEmpty.qml), and goes once a window is there or it's hidden."""

    def toggle(self):
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.workspace.toggle_special()) end")

    def showing(self):
        return self.s.hyprctl("monitors", json_out=True)[0]["specialWorkspace"]["name"] != ""

    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(lambda: self.showing() and self.toggle())

    def test_note_while_empty(self):
        self.assertEqual(self.s.state()["secretEmpty"], [])
        self.toggle()
        self.wait(lambda st: len(st["secretEmpty"]) == 1, "the note that it's empty")
        self.screenshot("secret-empty")
        self.toggle()
        self.wait(lambda st: st["secretEmpty"] == [], "the note to go with the workspace")

    def test_no_note_with_a_window(self):
        self.toggle()
        self.wait(lambda st: len(st["secretEmpty"]) == 1, "the note that it's empty")
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot", { workspace = "special silent" })')
        self.wait(lambda st: st["secretEmpty"] == [], "the note to go once a window's there")
        new = [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before]
        self.assertTrue(new and new[0]["workspace"]["name"].startswith("special"), "the window isn't on the secret workspace")
        # close it: the note's back, unless Hyprland has put the empty secret workspace away
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{new[0]["address"]}" }})) end')
        self.wait(lambda st: len(st["secretEmpty"]) == (1 if self.showing() else 0), "the note to match the workspace")
        if not self.showing():
            self.toggle()
            self.wait(lambda st: len(st["secretEmpty"]) == 1, "the note when it's shown again, empty")


class WorkspaceNames(LiveCase):
    """A workspace's own name (the pencil on the window mode panel): shown in place of
    "Workspace 3", asked for in Slate's confirmation window, dropped when the workspace goes."""

    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(lambda: [self.ipc("workspacename", "set", str(i), "") for i in range(1, 12)])
        self.addCleanup(lambda: self.ipc("power", "cancel"))

    def go(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.s.settle(0.4)

    def foot(self):
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            new = [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before]
            if new:
                self.s.settle(0.5)
                return new[0]
            self.s.settle(0.2)
        self.fail("no new window")

    def test_set_and_get(self):
        self.go(5)
        self.foot()
        self.assertEqual(self.ipc("workspacename", "label", "5"), "Workspace 5")
        self.ipc("workspacename", "set", "5", "  Coding   things ")
        self.wait(lambda st: st["workspaceNames"].get("5") == "Coding things", "the name (trimmed)")
        self.assertEqual(self.ipc("workspacename", "label", "5"), "Coding things")
        self.assertEqual(self.ipc("workspacename", "label", "6"), "Workspace 6")
        # an empty name: the number again
        self.ipc("workspacename", "set", "5", "")
        self.wait(lambda st: "5" not in st["workspaceNames"], "the name to go")

    def test_cut_to_the_limit(self):
        self.go(5)
        self.foot()
        self.ipc("workspacename", "set", "5", "A" * 40)
        self.wait(lambda st: st["workspaceNames"].get("5") == "A" * 20, "the name cut to 20")

    def test_rename_dialog(self):
        self.go(5)
        self.foot()
        self.ipc("test", "renameWorkspace")
        st = self.wait(lambda st: st["asking"] == "Name this workspace", "the rename question")
        self.assertEqual(st["popout"], "", "the panel should close")
        self.assertEqual(self.ipc("test", "typed"), "")
        self.ipc("test", "type", "Music")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["workspaceNames"].get("5") == "Music", "the name")
        # again: it opens with the name in it, and says so
        self.ipc("test", "renameWorkspace")
        self.wait(lambda st: st["asking"] == "Rename \u201cMusic\u201d", "the rename question, naming it")
        self.assertEqual(self.ipc("test", "typed"), "Music")
        # cancelling leaves it alone
        self.ipc("test", "type", "Something else")
        self.ipc("test", "answer", "false")
        self.s.settle(0.6)
        self.assertEqual(self.s.state()["workspaceNames"].get("5"), "Music")
        # emptied: back to the number
        self.ipc("test", "renameWorkspace")
        self.wait(lambda st: st["asking"] != "", "the question")
        self.ipc("test", "type", "")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: "5" not in st["workspaceNames"], "the number again")

    def test_dropped_when_the_workspace_goes(self):
        self.go(7)
        w = self.foot()
        self.ipc("workspacename", "set", "7", "Scratch")
        self.wait(lambda st: st["workspaceNames"].get("7") == "Scratch", "the name")
        # still there while the workspace is
        self.go(1)
        self.s.settle(2.5)
        self.assertEqual(self.s.state()["workspaceNames"].get("7"), "Scratch")
        # its last window closes: Hyprland removes the workspace, and the name goes with it
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{w["address"]}" }})) end')
        self.s.wait(lambda st: "7" not in st["workspaceNames"], timeout=10, what="the name to go with the workspace")
