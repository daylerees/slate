"""Slate's own title bars (Settings → Windows → Title bars, the default): a bar on the
focused floating window only, which can move it (TitleBar.qml, slateDragMove in animations.lua)."""
import time

from live import LiveCase


class TitleBars(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        for key in ("windowMode", "titleBarStyle"):
            self.keep_setting(key)

    def foot(self):
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            new = [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before]
            if new:
                return new[0]
            self.s.settle(0.2)
        self.fail("no new window")

    def client(self, address):
        return next((c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == address), None)

    def until(self, read, ok, timeout=8):
        """read() once ok(it) holds, polling (a Hyprland query); the last read if it never does,
        for the test's own check to say what's wrong."""
        end = time.monotonic() + timeout
        while True:
            v = read()
            if ok(v) or time.monotonic() > end:
                return v
            time.sleep(0.1)

    def floating_foot(self):
        """A new window, once Hyprland has mapped it, floating (the floating mode's rule), and
        it's where it'll stay."""
        w = self.foot()
        c = self.until(lambda: self.client(w["address"]), lambda c: c and c["mapped"] and c["floating"])
        self.assertTrue(c and c["mapped"] and c["floating"], f"the new window didn't open floating: {c}")
        # A new floating window is fitted to the screen again 350 ms after it opens
        # (slateFitFloating, windowrules.lua), as apps set their size just after they appear;
        # nothing says when that's done, so the floor covers it, then its place has to stop changing
        self.steady(lambda: (lambda c: (c["at"], c["size"]))(self.client(w["address"])), floor=0.5)
        return self.client(w["address"])

    def bar_on(self, w):
        """Wait for Slate's title bar on window w, and for Slate to have looked at the window
        where Hyprland says it is now (it looks a few times a second, and acts on what it saw)."""
        def caught_up(st):
            c = self.client(w["address"])
            return st["titleBar"] == w["address"] and st["titleBarSeen"] == ",".join(map(str, [c["address"], *c["at"], *c["size"]]))
        self.wait(caught_up, "the title bar on the new window, and Slate knowing where it is", timeout=10)

    def test_floating_without_hyprbars(self):
        """Slate's title bars: floating mode works with no plugin built."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.foot()
        w = self.until(lambda: self.client(w["address"]), lambda c: c and c["mapped"] and c["floating"])
        self.assertTrue(w["floating"], "new windows should float")

    def test_bar_on_the_focused_window(self):
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.foot()
        self.wait(lambda st: st["titleBar"] == w["address"], "the title bar on the new window")
        # back to tiling: no bar
        self.config("windowMode", "tiling")
        self.wait(lambda st: st["titleBar"] == "", "the title bar to go")

    def test_bar_on_the_topmost_window(self):
        """The bar goes on the floating window in front, which isn't always the focused one
        (focus following the pointer can focus a window behind): the last floating window on
        the workspace in Hyprland's list, which runs bottom to top."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        first, second = self.foot(), self.foot()
        ws = self.s.hyprctl("activeworkspace", json_out=True)["id"]

        def topmost():
            fl = [c for c in self.s.hyprctl("clients", json_out=True)
                  if c["mapped"] and not c["hidden"] and c["floating"] and c["workspace"]["id"] == ws]
            return fl[-1]["address"] if fl else ""
        self.wait(lambda st: st["titleBar"] == topmost(), "the bar on the window in front")
        # focus the other one (whether that raises it or not, the bar follows what's in front)
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.focus({{ window = "address:{first["address"]}" }})) end')
        # Slate looks again since (the second look started after the focus moved: the first
        # may have been under way already), so a bar that wrongly followed focus would show
        looks = self.s.state()["titleBarLooks"]
        self.wait(lambda st: st["titleBarLooks"] >= looks + 2, "Slate to look at the windows since the focus moved")
        self.wait(lambda st: st["titleBar"] == topmost(), "the bar on the window in front")

    def test_drag_moves_the_window(self):
        """What dragging a bar does: the window goes to the place asked for, and the move
        animation comes back afterwards."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.s.hyprctl("dispatch", f'function() slateDragMove("{w["address"]}", 200, 300) end')
        self.s.hyprctl("dispatch", "function() slateDragEnd() end")
        for _ in range(30):
            at = next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])["at"]
            if at == [200, 300]:
                break
            self.s.settle(0.1)
        self.assertEqual(at, [200, 300])

    def test_corner_resize(self):
        """What dragging a bar's corner does: the window gets exactly the place and size asked for."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.s.hyprctl("dispatch", f'function() slateDragResize("{w["address"]}", 150, 200, 500, 320) end')
        self.s.hyprctl("dispatch", "function() slateDragEnd() end")
        for _ in range(30):
            c = next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])
            if c["at"] == [150, 200] and c["size"] == [500, 320]:
                break
            self.s.settle(0.1)
        self.assertEqual((c["at"], c["size"]), ([150, 200], [500, 320]))

    def test_maximise_keeps_room_for_the_bar(self):
        """Slate maximises a window with its own title bar on itself: it fills the usable screen
        less the bar's height, so the bar stays (Hyprland's maximise would hide it); maximising
        again puts the window back."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.bar_on(w)
        get = lambda: next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])
        before = get()
        mon = next(m for m in self.s.hyprctl("monitors", json_out=True) if m["id"] == before["monitor"])
        self.ipc("titlebar", "maximise", w["address"])
        for _ in range(30):
            now = get()
            if now["size"][0] > before["size"][0]:
                break
            self.s.settle(0.1)
        self.assertGreater(now["size"][0], before["size"][0], "not maximised")
        self.assertEqual(now["fullscreen"], 0, "Hyprland's maximise: the bar can't show")
        self.assertGreaterEqual(now["at"][1], mon["y"] + mon["reserved"][1] + 30, "no room left for the bar")
        # the whole usable width and down to its bottom: no gap or border round it
        sc = mon["scale"] or 1
        usable_w = round(mon["width"] / sc) - mon["reserved"][0] - mon["reserved"][2]
        usable_bottom = mon["y"] + round(mon["height"] / sc) - mon["reserved"][3]
        self.assertLessEqual(abs(now["size"][0] - usable_w), 2, "not the full width")
        self.assertLessEqual(abs(now["at"][1] + now["size"][1] - usable_bottom), 2, "not down to the bottom")
        self.wait(lambda st: st["titleBar"] == w["address"], "the bar still there")
        self.ipc("titlebar", "maximise", w["address"])
        for _ in range(30):
            now = get()
            if (now["at"], now["size"]) == (before["at"], before["size"]):
                break
            self.s.settle(0.1)
        self.assertEqual((now["at"], now["size"]), (before["at"], before["size"]), "not put back")

    def test_maximise_twice_in_quick_succession_puts_it_back(self):
        """Asked again before Slate has next looked up where the window is (it looks a few times
        a second), the second ask went by the old place and maximised again: the window stayed
        maximised. (It failed the test above now and then, for the same reason.)"""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.bar_on(w)              # (where it opened is known)
        get = lambda: next(c for c in self.s.hyprctl("clients", json_out=True) if c["address"] == w["address"])
        before = get()
        self.ipc("titlebar", "maximise", w["address"])
        self.ipc("titlebar", "maximise", w["address"])
        for _ in range(30):
            now = get()
            if (now["at"], now["size"]) == (before["at"], before["size"]):
                break
            self.s.settle(0.1)
        self.assertEqual((now["at"], now["size"]), (before["at"], before["size"]), "maximised twice over, not put back")

    def test_steps_away_while_moved_elsewhere(self):
        """Moved by something other than the bar (its own header, Super+drag), the bar fades
        away until the window's been still a moment."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.foot()
        self.wait(lambda st: st["titleBar"] == w["address"], "the title bar on the new window")
        for i in range(8):
            self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.move({{ x = {100 + i * 20}, y = 200, window = "address:{w["address"]}" }})) end')
            self.s.settle(0.06)     # (stays: a drag's pace, a move every frame or so)
        self.wait(lambda st: st["titleBarAway"], "the bar to step away while the window moves", timeout=3)
        self.wait(lambda st: not st["titleBarAway"], "the bar back once it's still", timeout=3)

    def test_click_to_focus(self):
        """With Slate's title bars, a window takes focus when clicked (the bar would otherwise sit
        on a window you're not using); the setting itself isn't changed, and applies again after."""
        self.keep_setting("focusFollowsMouse")
        self.config("focusFollowsMouse", "on")
        follow = lambda: self.s.hyprctl("getoption", "input:follow_mouse", json_out=True)["int"]
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        for _ in range(30):
            if follow() == 2:
                break
            self.s.settle(0.1)
        self.assertEqual(follow(), 2, "focus still follows the pointer")
        self.assertEqual(self.setting("focusFollowsMouse"), "on", "the setting itself was changed")
        self.config("windowMode", "tiling")
        for _ in range(30):
            if follow() == 1:
                break
            self.s.settle(0.1)
        self.assertEqual(follow(), 1, "the setting didn't apply again")

    def test_dropped_window_goes_back_under_the_bar(self):
        """A floating window dropped with its top above the menu bar slides back below it, its
        title bar in view (slateKeepUnderBar, run as the mouse button is let go)."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        addr = w["address"]
        mon = self.s.hyprctl("monitors", json_out=True)[0]
        top = mon["reserved"][1]                     # (the bar's height, reserved at the top)
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.window.move({{ x = 200, y = 0, window = 'address:{addr}' }})) end")
        y = self.until(lambda: self.client(addr)["at"][1], lambda y: y < top)
        self.assertLess(y, top, "the window wasn't moved up over the menu bar")
        self.s.hyprctl("dispatch", f"function() slateKeepUnderBar('{addr.replace('0x', '')}') end")
        self.s.hyprctl("dispatch", f"function() slateKeepUnderBar('{addr}') end")
        y = self.until(lambda: self.client(addr)["at"][1], lambda y: y >= top + 20)
        self.assertGreater(top, 0)
        self.assertGreaterEqual(y, top + 20, f"the window's top is at {y}, under the bar (bottom {top}) and its title bar")
        # (and somewhere you can drag it: not pushed past the bottom)
        self.assertLess(y, mon["height"] / mon["scale"] - 40)
