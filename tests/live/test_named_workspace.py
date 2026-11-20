"""A named workspace about: Slate sends games (and Steam's "Launching…") to one called "gaming"
(windowrules.lua). In Hyprland 0.57 a named workspace has no number at all, where older versions
gave it a negative one, and Slate's workspace code assumed every workspace had one: with Steam
there, Super+Left and Super+Right failed on every press, in a red error over the screen.

Everything that goes through the workspaces is used with a window on "gaming", both from a
numbered workspace and from "gaming" itself, and nothing may fail: the keys, the menu bar's
dots, the workspace overview, the window switcher and the big workspace dots. (Any error Slate
logs fails the test too: LiveCase.)"""
from live import LiveCase

APP = "slate-test-named"
NAMED = "gaming"


class NamedWorkspace(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(self.close_windows)
        self.s.hyprctl("dispatch", 'function() hl.exec_cmd("foot --app-id %s", { workspace = "name:%s silent" }) end' % (APP, NAMED))
        self.until_true(lambda: any(c["class"] == APP and c["workspace"]["name"] == NAMED
                                    for c in self.s.hyprctl("clients", json_out=True)), "a window on the named workspace")

    def until_true(self, read, what, timeout=10):
        for _ in range(int(timeout / 0.1)):
            if read():
                return
            self.s.settle(0.1)
        self.fail(f"timed out waiting for {what}")

    def lua(self, code):
        """Run code in Hyprland's config: (ok, message). A failure is an error eval answers with."""
        code_, out = self.s.run(["hyprctl", "eval", code])
        return code_ == 0, out

    def active(self):
        return self.s.hyprctl("activeworkspace", json_out=True)

    def go_named(self):
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.focus({ workspace = "name:%s" })) end' % NAMED)
        self.until_true(lambda: self.active().get("name") == NAMED, "the named workspace")

    def step(self, n):
        """Super+Right (1) or Super+Left (-1), as the key does it."""
        ok, out = self.lua("cycleWorkspace(%d)" % n)
        self.assertTrue(ok, f"cycleWorkspace({n}) failed: {out}")

    def test_the_keys_step_past_it(self):
        self.step(1)
        self.step(-1)
        self.until_true(lambda: self.active().get("id") == 1, "back on workspace 1")

    def test_the_keys_step_off_it(self):
        self.go_named()
        self.step(1)
        self.until_true(lambda: self.active().get("name") != NAMED, "a step off the named workspace")
        self.go_named()
        self.step(-1)
        self.until_true(lambda: self.active().get("name") != NAMED, "a step back off the named workspace")

    def test_going_to_a_workspace_from_it(self):
        """The menu bar's dots (goToWorkspace), from the named workspace."""
        self.go_named()
        ok, out = self.lua("goToWorkspace(1)")
        self.assertTrue(ok, out)
        self.until_true(lambda: self.active().get("id") == 1, "workspace 1")

    def test_a_dot_of_its_own_at_the_end(self):
        """One list, as Hyprland's own order has it: the numbered workspaces, then the named one,
        with the marker on it while you're there, and its name where the workspace is named."""
        dots = lambda st: st["bar"]["dots"]
        st = self.wait(lambda st: dots(st)["names"][-1:] == [NAMED], "a dot for the named workspace, last")
        self.assertEqual(dots(st)["names"][0], "Workspace 1")
        self.go_named()
        st = self.wait(lambda st: dots(st)["active"] == len(dots(st)["names"]) - 1, "the marker on its dot")
        self.assertEqual(st["focusedWorkspace"]["label"], NAMED)

    def test_its_dot_takes_you_there(self):
        """A dot's click (WorkspaceDots.go): goToWorkspace with the workspace's name."""
        ok, out = self.lua('goToWorkspace("name:%s")' % NAMED)
        self.assertTrue(ok, out)
        self.until_true(lambda: self.active().get("name") == NAMED, "the named workspace")

    def test_its_windows_are_in_the_switcher(self):
        self.ipc("switcher", "next")
        st = self.wait(lambda st: st["switcher"]["open"], "the switcher")
        self.assertEqual(st["switcher"]["windows"], 1, "the window on the named workspace isn't in the switcher")
        self.ipc("switcher", "cancel")

    def test_slate_shows_it(self):
        """The bar, the overview, the switcher and the big dots, on and off it."""
        for where in ("numbered", "named"):
            with self.subTest(where):
                if where == "named":
                    self.go_named()
                self.s.state()
                self.ipc("osd", "workspace")
                self.ipc("overview", "open")
                self.wait(lambda st: st["overview"]["open"], "the overview")
                self.ipc("overview", "next")
                self.ipc("overview", "close")
                self.wait(lambda st: not st["overview"]["open"], "the overview to close")
                self.ipc("switcher", "next")
                self.s.settle(0.4)
                self.ipc("switcher", "cancel")
                self.s.settle(0.4)
                self.s.state()
