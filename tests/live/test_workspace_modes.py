"""Each workspace's own window mode (the menu bar's workspace indicator; Settings → Windows sets
the default): its layout, floating new windows, re-tiling when it's put back, and the default
for the rest."""
import time

from live import LiveCase


def bare(address):
    """A window's address as Slate's test state has it (without the 0x)."""
    return address[2:] if address.startswith("0x") else address


class Waits:
    """Waiting for what Hyprland and Slate have done, in place of set pauses."""

    def until(self, read, what, timeout=10, step=0.1):
        """read()'s answer once it's true (for Hyprland, and anything else outside Slate's state)."""
        end = time.monotonic() + timeout
        while True:
            got = read()
            if got:
                return got
            if time.monotonic() >= end:
                self.fail(f"timed out waiting for {what}")
            time.sleep(step)

    def lua(self, expr):
        """Whether expr is true in Hyprland's Lua config (eval answers an error when the assert fails)."""
        code, _ = self.s.run(["hyprctl", "eval", f"assert({expr})"])
        return code == 0

    def go(self, ws):
        """Workspace ws in front, in Hyprland and as Slate sees it (the overview opens on the one
        Slate believes is in front)."""
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.until(lambda: self.s.hyprctl("activeworkspace", json_out=True)["id"] == ws, f"Hyprland to be on workspace {ws}")
        self.wait(lambda st: st["overview"]["focused"] == ws, f"Slate to see workspace {ws} in front")

    def mode_in_hyprland(self, ws):
        """Hyprland has the window mode Slate has for workspace ws (Slate sends it a moment
        after it changes, with hyprctl)."""
        want = self.ipc("workspacemode", "get", str(ws)) or self.setting("windowMode")
        self.until(lambda: self.lua(f'modeOf({ws}) == "{want}"'), f"Hyprland to have workspace {ws} in {want} mode")

    def client(self, address):
        return next((c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == address), None)

    def opened_since(self, before):
        return [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before and c.get("mapped")]

    def new_window(self, before, timeout=15):
        """The window opened since `before` (the addresses there were), once opening it is over:
        on screen, where its rules and Slate's put it (floating, Solo moving it on), and Slate
        knows of it there."""
        new = self.until(lambda: self.opened_since(before), "a new window", timeout=timeout, step=0.2)
        address = new[0]["address"]
        where = lambda: (lambda c: c and (c["floating"], c["workspace"]["id"], c["at"], c["size"]))(self.client(address))
        self.steady(where)
        c = self.client(address)
        self.wait(lambda st: any(w["address"] == bare(address) and w["workspace"] == c["workspace"]["id"] for w in st["windows"]),
                  "Slate to know of the new window, where it is")
        return c


class WorkspaceModes(Waits, LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        self.keep_setting("windowMode")
        self.config("windowMode", "tiling")
        self.addCleanup(lambda: [self.ipc("workspacemode", "set", str(i), "") for i in range(1, 21)])

    def layout(self, ws):
        w = next((w for w in self.s.hyprctl("workspaces", json_out=True) if w["id"] == ws), None)
        return w and w.get("tiledLayout")

    def foot_on(self, ws):
        self.go(ws)
        self.mode_in_hyprland(ws)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        return self.new_window(before)

    def test_layout_of_its_own(self):
        self.ipc("workspacemode", "set", "7", "scrolling")
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "scrolling")
        self.foot_on(7)
        self.assertEqual(self.layout(7), "scrolling")
        # put back to the default
        self.ipc("workspacemode", "set", "7", "")
        self.until(lambda: self.layout(7) == "dwindle", "workspace 7 to go back to the default layout")
        self.assertEqual(self.layout(7), "dwindle")

    def test_floating_workspace_among_tiled(self):
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")      # (floating without needing hyprbars)
        self.ipc("workspacemode", "set", "8", "floating")
        floated = self.foot_on(8)
        self.assertTrue(floated["floating"], "a new window on a floating workspace should float")
        tiled = self.foot_on(7)
        self.assertFalse(tiled["floating"], "the default (tiling) workspace shouldn't float it")
        # back to the default: workspace 8's window is tiled again
        self.ipc("workspacemode", "set", "8", "")
        self.mode_in_hyprland(8)
        c = self.steady(lambda: self.client(floated["address"]), floor=0.1)
        self.assertFalse(c["floating"], "not re-tiled when the workspace went back to the default")

    def test_solo_one_window_per_workspace(self):
        """Solo: a second window opening on the workspace moves on to a new one of its own, which
        is Solo too; dialogs (floating) would stay."""
        self.ipc("workspacemode", "set", "9", "solo")
        first = self.foot_on(9)
        second = self.foot_on(9)
        by = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
        self.assertEqual(by[first["address"]]["workspace"]["id"], 9)
        moved_to = by[second["address"]]["workspace"]["id"]
        self.assertNotEqual(moved_to, 9, "the second window stayed on the Solo workspace")
        on_nine = [c for c in by.values() if c["workspace"]["id"] == 9 and not c["floating"]]
        self.assertEqual(len(on_nine), 1)
        # (Hyprland's config tells Slate the new workspace is Solo too, a moment after the move)
        self.until(lambda: self.ipc("workspacemode", "get", str(moved_to)) == "solo", "Slate to hear the new workspace is Solo")
        self.assertEqual(self.ipc("workspacemode", "get", str(moved_to)), "solo", "its new workspace isn't Solo")

    def test_switching_to_solo_spreads_every_window(self):
        """Switching a workspace to Solo gives every window on it a workspace of its own, filling
        it: floating ones are tiled first (dialogs would stay floating with their app)."""
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")
        self.ipc("workspacemode", "set", "10", "floating")
        a, b = self.foot_on(10), self.foot_on(10)
        self.assertTrue(a["floating"] and b["floating"])
        self.ipc("workspacemode", "set", "10", "solo")
        self.mode_in_hyprland(10)
        by = self.steady(lambda: {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}, floor=0.1)
        self.assertNotEqual(by[a["address"]]["workspace"]["id"], by[b["address"]]["workspace"]["id"], "both still on one workspace")
        for w in (a, b):
            self.assertFalse(by[w["address"]]["floating"], "still floating: it wouldn't fill its workspace")
        moved = by[b["address"]]["workspace"]["id"] if by[a["address"]]["workspace"]["id"] == 10 else by[a["address"]]["workspace"]["id"]
        # (Hyprland's config tells Slate the new workspace is Solo too, a moment after the move)
        self.until(lambda: self.ipc("workspacemode", "get", str(moved)) == "solo", "Slate to hear the new workspace is Solo")
        self.assertEqual(self.ipc("workspacemode", "get", str(moved)), "solo")

    # ---- Changing the default with windows open (Settings asks: tidy up, or leave them) ----
    def window(self, w):
        return next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])

    def default_in_hyprland(self, mode, own):
        """Hyprland has the new default, and each workspace in `own` ({workspace: mode, or None
        for following the default}) as Slate has it: Slate sends them with hyprctl, a moment
        after the change, and rearranges the open windows in the same go."""
        expr = " and ".join([f'WINDOW_MODE == "{mode}"'] + [f"WORKSPACE_MODES[{ws}] == " + (f'"{m}"' if m else "nil") for ws, m in own.items()])
        self.until(lambda: self.lua(expr), f"Hyprland to have {mode} as the default")

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
        self.default_in_hyprland("floating", {6: None, 7: None, 8: None})
        # (Slate's regular push of its settings to Hyprland can land a moment before the one that
        # rearranges the windows: this waits for that one)
        self.until(lambda: self.window(follows)["floating"] and self.window(own)["floating"], "the open windows to float")
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
        self.default_in_hyprland("floating", {6: "tiling", 7: "scrolling"})
        # (nothing must happen to the open window. Slate's regular push of its settings can reach
        # Hyprland a moment before the one that would rearrange it, so this gives that one time)
        self.s.settle(0.5)
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
        self.default_in_hyprland("scrolling", {7: None})
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "")
        self.assertEqual(self.steady(lambda: self.layout(7), floor=0.1), "scrolling")

    def test_empty_workspaces_are_not_pinned(self):
        self.go(8)
        self.assertEqual(self.ipc("workspacemode", "notIn", "master"), "")
        self.ipc("workspacemode", "setDefault", "master", "false")
        self.default_in_hyprland("master", {8: None})
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
        # close it: the note's back, unless Hyprland has put the empty secret workspace away.
        # (Which, it decides a moment after the window goes: asked once, straight away, the answer
        # could be from before, and the toggle below then hid it instead of showing it again)
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{new[0]["address"]}" }})) end')
        showing = self.steady(self.showing, floor=0.5)
        self.wait(lambda st: len(st["secretEmpty"]) == (1 if showing else 0), "the note to match the workspace")
        if not showing:
            self.toggle()
            self.wait(lambda st: len(st["secretEmpty"]) == 1, "the note when it's shown again, empty")


class WorkspaceNames(Waits, LiveCase):
    """A workspace's own name (the pencil on the window mode panel): shown in place of
    "Workspace 3", asked for in Slate's confirmation window, dropped when the workspace goes."""

    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(lambda: [self.ipc("workspacename", "set", str(i), "") for i in range(1, 12)])
        self.addCleanup(lambda: self.ipc("power", "cancel"))

    def foot(self):
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        return self.new_window(before)

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
        self.steady(self.s.state, floor=0.6)
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
        self.steady(self.s.state, floor=2.5)
        self.assertEqual(self.s.state()["workspaceNames"].get("7"), "Scratch")
        # its last window closes: Hyprland removes the workspace, and the name goes with it
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{w["address"]}" }})) end')
        self.s.wait(lambda st: "7" not in st["workspaceNames"], timeout=10, what="the name to go with the workspace")


class OpeningWindows(WorkspaceModes):
    """A window as it opens: in its own workspace's mode whichever workspace is in front, and,
    floating, no bigger than nine tenths of the screen and all of it on the screen."""

    def start_then_go(self, started_on, go_to, cmd="foot"):
        """Start an app on one workspace and be on another by the time its window arrives."""
        self.go(started_on)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("sh -c \'sleep 1.5; exec %s\'")' % cmd)
        self.go(go_to)
        return self.new_window(before)

    def floating_workspace(self, ws):
        self.keep_setting("titleBarStyle")
        self.config("titleBarStyle", "slate")      # (floating without needing hyprbars)
        self.ipc("workspacemode", "set", str(ws), "floating")
        self.mode_in_hyprland(ws)

    def test_floats_on_a_floating_workspace_with_a_tiled_one_in_front(self):
        self.floating_workspace(8)
        self.foot_on(7)                             # (something on the tiled one, to be in front of)
        w = self.start_then_go(8, 7)
        self.assertEqual(w["workspace"]["id"], 8)
        self.assertTrue(w["floating"], "it went by the tiled workspace in front, and opened tiled on a floating one")

    def test_tiles_on_a_tiled_workspace_with_a_floating_one_in_front(self):
        """Started on a tiled workspace, arriving once a floating one is in front: it opened
        floating, over the tiled windows."""
        self.floating_workspace(8)
        self.foot_on(7)
        w = self.start_then_go(7, 8)
        self.assertEqual(w["workspace"]["id"], 7)
        self.assertFalse(w["floating"], "it went by the floating workspace in front, and floated on a tiled one")

    def usable(self, w):
        m = next(m for m in self.s.hyprctl("monitors", json_out=True) if m["id"] == w["monitor"])
        sc = m["scale"] or 1
        left, top, right, bottom = m["reserved"]
        return (m["x"] + left, m["y"] + top, round(m["width"] / sc) - left - right, round(m["height"] / sc) - top - bottom)

    def test_a_window_opening_too_big_is_kept_to_nine_tenths(self):
        self.floating_workspace(8)
        self.go(8)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot --app-id=slate-test-big --window-size-pixels=3000x2000")')
        w = self.new_window(before)
        ax, ay, aw, ah = self.usable(w)
        # (Slate fits it as it opens, and again a moment later, once its size is known: windowrules.lua)
        fits = lambda c: c["size"][0] <= aw * 0.9 + 1 and c["size"][1] <= ah * 0.9 + 1
        self.until(lambda: fits(self.client(w["address"])), "the window to be made to fit")
        w = self.now(w)
        self.assertTrue(w["floating"])
        self.assertLessEqual(w["size"][0], aw * 0.9 + 1, "wider than nine tenths of the screen")
        self.assertLessEqual(w["size"][1], ah * 0.9 + 1, "taller than nine tenths of the screen")
        self.assertGreater(w["size"][0], aw * 0.6, "made far smaller than it needed to be")
        # ...and all of it on the screen
        self.assertGreaterEqual(w["at"][0], ax)
        self.assertGreaterEqual(w["at"][1], ay)
        self.assertLessEqual(w["at"][0] + w["size"][0], ax + aw)
        self.assertLessEqual(w["at"][1] + w["size"][1], ay + ah)

    def floating_foot(self):
        self.floating_workspace(8)
        self.go(8)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        w = self.new_window(before)
        # (Slate fits a floating window again 350 ms after it opens, windowrules.lua: a timer in
        # Hyprland that nothing shows, so this waits it out, or it could move the window back
        # while the test has it off the edge)
        self.s.settle(0.6)
        return w

    def now(self, w):
        """The window, once its size and place have stopped changing."""
        return self.steady(lambda: self.client(w["address"]), floor=0.1)

    def fit(self, w):
        """What Slate does to a floating window as it opens (slateFitFloating, windowrules.lua)."""
        self.s.hyprctl("eval", 'slateFitFloating("%s")' % w["address"])
        return self.now(w)

    def test_a_small_window_keeps_its_size(self):
        """Only a window that's too big is made smaller."""
        w = self.floating_foot()
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.resize({ x = 520, y = 340, window = "address:%s" })) end' % w["address"])
        small = self.now(w)
        self.assertLess(small["size"][0], 600, small["size"])
        after = self.fit(w)
        self.assertEqual(after["size"], small["size"], "a window smaller than the limit was resized")
        self.assertEqual(after["at"], small["at"], "a window wholly on the screen was moved")

    def test_a_window_off_the_edge_is_brought_onto_the_screen(self):
        w = self.floating_foot()
        ax, ay, aw, ah = self.usable(w)
        for x, y in ((ax - 300, ay + 60), (ax + aw - 200, ay + ah - 100), (ax + 40, ay - 200)):
            self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.resize({ x = 520, y = 340, window = "address:%s" })); hl.dispatch(hl.dsp.window.move({ x = %d, y = %d, window = "address:%s" })) end' % (w["address"], x, y, w["address"]))
            moved = self.now(w)
            self.assertEqual(moved["at"], [x, y], "the test couldn't put the window off the edge")
            c = self.fit(w)
            with self.subTest(at=(x, y)):
                self.assertEqual(c["size"], moved["size"])
                self.assertGreaterEqual(c["at"][0], ax)
                self.assertGreaterEqual(c["at"][1], ay)
                self.assertLessEqual(c["at"][0] + c["size"][0], ax + aw)
                self.assertLessEqual(c["at"][1] + c["size"][1], ay + ah)



class OverviewReorder(WorkspaceModes):
    """Moving a workspace along in the overview (a lifted card) swaps the two workspaces'
    numbers in Hyprland: each keeps its windows laid out as they were, and its name and window
    mode go with it. It used to move the windows across, which re-tiled them (the split came out
    flipped) and blanked their previews. Bug, 2026-11-12."""
    def test_moving_a_card_keeps_its_layout_name_and_mode(self):
        self.addCleanup(lambda: [self.ipc("workspacename", "set", str(i), "") for i in (1, 2)])
        self.addCleanup(lambda: self.ipc("overview", "close"))
        left = self.foot_on(1)
        right = self.foot_on(1)
        lone = self.foot_on(2)
        self.ipc("workspacename", "set", "1", "Alpha")
        self.ipc("workspacemode", "set", "1", "master")
        self.mode_in_hyprland(1)
        pair = lambda: [(c["workspace"]["id"], c["at"], c["size"]) for c in self.s.hyprctl("clients", json_out=True)
                        if c["address"] in (left["address"], right["address"])]
        self.steady(pair)                    # (laid out again, master and stack)
        clients = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
        before = sorted((clients[a]["at"][0], a) for a in (left["address"], right["address"]))
        self.go(1)
        self.ipc("overview", "open")
        # (open, with both workspaces, and on the one in front: the card that's moved)
        self.wait(lambda st: st["overview"]["open"] and {1, 2} <= set(st["overview"]["workspaces"])
                  and st["overview"]["workspaces"][st["overview"]["selected"]] == 1, "the overview, on workspace 1")
        self.ipc("overview", "hold", "true")
        self.ipc("overview", "moveRight")
        self.until(lambda: self.client(lone["address"])["workspace"]["id"] != 2, "the two workspaces to swap in Hyprland")
        self.ipc("overview", "hold", "false")
        self.ipc("overview", "close")
        self.wait(lambda st: not st["overview"]["open"], "the overview to close")
        self.steady(pair)
        clients = {c["address"]: c for c in self.s.hyprctl("clients", json_out=True)}
        with self.subTest("the windows went together, laid out as they were"):
            self.assertEqual(clients[left["address"]]["workspace"]["id"], 2)
            self.assertEqual(clients[right["address"]]["workspace"]["id"], 2)
            self.assertEqual(clients[lone["address"]]["workspace"]["id"], 1)
            after = sorted((clients[a]["at"][0], a) for a in (left["address"], right["address"]))
            self.assertEqual([a for _, a in before], [a for _, a in after], "the two windows swapped sides")
            self.assertEqual([x for x, _ in before], [x for x, _ in after], "the split changed")
        with self.subTest("its name and mode went with it"):
            self.wait(lambda st: st["workspaceNames"].get("2") == "Alpha" and "1" not in st["workspaceNames"],
                      "the name to move to workspace 2")
            self.assertEqual(self.ipc("workspacemode", "get", "2"), "master")
            self.assertEqual(self.ipc("workspacemode", "get", "1"), "")


# (only this class's own tests: the ones it borrows its helpers from run in their own)
for _n in [n for n in dir(WorkspaceModes) if n.startswith("test_")]:
    setattr(OpeningWindows, _n, None)
    setattr(OverviewReorder, _n, None)
