"""The window switcher's and workspace overview's animations (Settings → Windows and
Workspaces): every way of moving through the cards, and every way of going to the one picked,
gets there and closes."""
from live import LiveCase

MOVES = ("slide", "hop", "wheel", "tilt", "orbit", "deck", "fan", "instant")


class SwitcherAnimations(LiveCase):
    def workspace(self):
        return self.s.hyprctl("activeworkspace", json_out=True)["id"]

    def go_to_workspace(self, ws):
        self.s.hyprctl("dispatch", f"function() instantTo(hl.dsp.focus({{ workspace = {ws} }})) end")
        for _ in range(30):
            if self.workspace() == ws:
                return
            self.s.settle(0.1)
        self.fail(f"couldn't get to workspace {ws}")

    def windows_on_two_workspaces(self):
        """A window on workspace 1 and one on workspace 2, so both switchers have somewhere to go."""
        for ws in (1, 2):
            self.go_to_workspace(ws)
            if not any(c["workspace"]["id"] == ws for c in self.s.hyprctl("clients", json_out=True)):
                self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
                for _ in range(50):
                    if any(c["workspace"]["id"] == ws for c in self.s.hyprctl("clients", json_out=True)):
                        break
                    self.s.settle(0.2)
        self.go_to_workspace(1)
        # Slate hears about a new workspace a moment after Hyprland makes it; the overview shows
        # the workspaces Slate knows of as it opens, so wait until it knows both (and the
        # switcher, the windows on them)
        self.wait(lambda st: {1, 2} <= set(st["overview"]["known"]) and st["overview"]["focused"] == 1
                  and {1, 2} <= {w["workspace"] for w in st["windows"]},
                  "Slate to know both workspaces and their windows", timeout=10)

    def open_overview_on(self, ws):
        """Open the overview once Slate knows where things stand: the overview shows the
        workspaces Slate knows of as it opens, with the one it believes is in front chosen, and
        Slate hears of both a moment after Hyprland. Opened a moment too soon (it happened now
        and then in a whole run) it had one workspace, or the wrong one chosen, and "next" had
        nowhere to go. Returns which card is chosen."""
        def knows(st):
            o = st["overview"]
            return o["focused"] == ws and ws in o["known"] and max(o["known"]) > ws
        for _ in range(8):
            self.wait(knows, f"Slate to know workspace {ws} is in front, with one after it", timeout=10)
            self.ipc("overview", "open")
            st = self.wait(lambda st: st["overview"]["open"], "the overview")["overview"]
            ids = st["workspaces"]
            if len(ids) >= 2 and ws in ids and ids[st["selected"]] == ws and st["selected"] < len(ids) - 1:
                # (opened: faded in, and moves from here animate)
                self.wait(lambda st: st["overview"]["fade"] == 1 and st["overview"]["animate"], "the overview to finish opening")
                return st["selected"]
            self.ipc("overview", "close")
            self.wait(lambda st: not st["overview"]["open"] and st["overview"]["fade"] == 0, "the overview to close")
        self.fail(f"the overview never opened on workspace {ws} with one after it: {st}")

    def test_overview_every_move_and_pick(self):
        self.keep_setting("overviewMoveAnimation")
        self.keep_setting("overviewPickAnimation")
        self.windows_on_two_workspaces()
        for move in MOVES + ("grid",):
            for pick in ("zoom", "fade", "workspace", "instant"):
                with self.subTest(move=move, pick=pick):
                    self.config("overviewMoveAnimation", move)
                    self.config("overviewPickAnimation", pick)
                    start = self.workspace()
                    was = self.open_overview_on(start)
                    self.ipc("overview", "next")
                    self.wait(lambda st: st["overview"]["selected"] != was, "the selection to move to the next workspace")
                    # The cards move to it (the animation being tried) before it's picked
                    self.steady(lambda: self.s.state()["overview"]["strip"], floor=0.1, step=0.05)
                    self.ipc("overview", "go")
                    self.wait(lambda st: not st["overview"]["open"], "the overview to close")
                    # There, and still there a moment later. (Hyprland sometimes hands focus back
                    # to the window from before just after the overview lets go of the keyboard,
                    # and Slate goes again: for an instant in between it reads as the old
                    # workspace, which isn't "didn't go")
                    held = 0
                    for _ in range(40):
                        held = held + 1 if self.workspace() != start else 0
                        if held >= 3:
                            break
                        self.s.settle(0.1)
                    self.assertGreaterEqual(held, 3, "didn't go to the next workspace")
                    # A lost switch is retried for a moment after: once that watch is over
                    self.wait(lambda st: not st["overview"]["leaving"] and not st["overview"]["zooming"],
                              "the overview to stop watching for a lost switch", timeout=10)
                    # ...and for a moment after it, nothing takes it back (kept on purpose: a
                    # "nothing happens for this long" check, which no state can say is over)
                    for _ in range(5):
                        self.assertNotEqual(self.workspace(), start, "went back to the old workspace")
                        self.s.settle(0.1)
                    self.go_to_workspace(1)

    def test_window_switcher_every_move_and_pick(self):
        self.keep_setting("switcherMoveAnimation")
        self.keep_setting("switcherPickAnimation")
        self.windows_on_two_workspaces()
        for move in MOVES:
            for pick in ("crossfade", "workspace", "instant"):
                with self.subTest(move=move, pick=pick):
                    self.config("switcherMoveAnimation", move)
                    self.config("switcherPickAnimation", pick)
                    before = self.s.hyprctl("activewindow", json_out=True).get("address")
                    self.ipc("switcher", "next")
                    self.wait(lambda st: st["switcher"]["open"], "the window switcher")
                    # (opened: faded in, and moves from here animate)
                    self.wait(lambda st: st["switcher"]["fade"] == 1 and st["switcher"]["animate"], "the window switcher to finish opening")
                    self.ipc("switcher", "commit")
                    self.wait(lambda st: not st["switcher"]["open"], "the window switcher to close")
                    for _ in range(30):
                        if self.s.hyprctl("activewindow", json_out=True).get("address") != before:
                            break
                        self.s.settle(0.1)
                    self.assertNotEqual(self.s.hyprctl("activewindow", json_out=True).get("address"), before,
                                        "didn't go to the other window")

    def test_overview_grid_arrows(self):
        """On the grid, Left/Right go one along and Up/Down a row (Settings → Workspaces: Grid)."""
        self.keep_setting("overviewMoveAnimation")
        self.keep_setting("overviewGridSize")
        self.config("overviewMoveAnimation", "grid")
        self.config("overviewGridSize", "2")
        # Four workspaces with a window each: two rows of two
        for ws in (1, 2, 3, 4):
            self.go_to_workspace(ws)
            if not any(c["workspace"]["id"] == ws for c in self.s.hyprctl("clients", json_out=True)):
                self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
                for _ in range(50):
                    if any(c["workspace"]["id"] == ws for c in self.s.hyprctl("clients", json_out=True)):
                        break
                    self.s.settle(0.2)
        self.go_to_workspace(1)
        self.ipc("overview", "open")
        st = self.wait(lambda st: st["overview"]["open"] and st["overview"]["grid"], "the overview's grid")
        self.assertEqual(st["overview"]["columns"], 2)
        self.assertEqual(st["overview"]["selected"], 0)
        self.ipc("overview", "down")
        self.wait(lambda st: st["overview"]["selected"] == 2, "Down to go a row down")
        self.ipc("overview", "next")
        self.wait(lambda st: st["overview"]["selected"] == 3, "Right to go one along")
        self.ipc("overview", "up")
        self.wait(lambda st: st["overview"]["selected"] == 1, "Up to go a row up")
        self.ipc("overview", "up")          # already on the top row: stays
        self.steady(self.s.state, floor=0.3)
        self.assertEqual(self.s.state()["overview"]["selected"], 1)
        self.ipc("overview", "close")
        self.wait(lambda st: not st["overview"]["open"])
