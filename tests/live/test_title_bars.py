"""Slate's own title bars (Settings → Windows → Title bars, the default): a bar on the
focused floating window only, which can move it (TitleBar.qml, slateDragMove in animations.lua)."""
import atexit
import json
import math
import time
import unittest

from live import LiveCase
from session import Session, in_container


class TitleBarChecks:
    """What the title bar tests share (and tests/live/test_two_screens.py borrows): opening a
    floating window, waiting for its bar, and checking the bar against the window Hyprland has.
    `scale` is the Interface size the session runs at: Slate's own units are Hyprland's pixels
    divided by it, and the bar is drawn in the first on a window placed in the second."""
    scale = 1

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

    def monitor_of(self, c):
        return next(m for m in self.s.hyprctl("monitors", json_out=True) if m["id"] == c["monitor"])

    def bar(self, what="", x=0, y=0):
        """The title bar that's showing, as Slate draws it (Slate's units on its screen), after a
        pretend pointer on it if asked (the `test` target's titleBar)."""
        return json.loads(self.ipc("test", "titleBar", what, x, y))

    def bar_height(self):
        """In Hyprland's pixels: what Slate tells Hyprland to keep clear above a floating window
        (SLATE_TITLEBAR_HEIGHT, shell.qml), which the bar it draws has to match."""
        return math.floor(13 * 2.6 * self.scale + 0.5)

    def assertBarOnWindow(self, address):
        """The bar, brought to Hyprland's pixels, is exactly on the window's top edge: as wide
        as the window and its border, its bottom on the border's top."""
        c = self.client(address)
        mon, border, k = self.monitor_of(c), int(self.setting("windowBorderSize")), self.scale
        want = {"x": c["at"][0] - mon["x"] - border, "y": c["at"][1] - mon["y"] - border - self.bar_height(),
                "w": c["size"][0] + 2 * border, "h": self.bar_height()}
        st = self.wait(lambda st: st["titleBar"] == address, "the title bar on the window") and self.bar()
        self.assertEqual(st["address"], address)
        self.assertEqual(st["screen"], mon["name"], "the bar's on another screen than its window")
        got = {key: round(st[key] * k, 2) for key in want}
        self.assertEqual(got, want, f"the bar isn't on its window (Hyprland's pixels, on {mon['name']}; "
                                    f"Interface size {k}, window at {c['at']} {c['size']})")

    def check_drag(self, w, to=(520, 430)):
        """Dragging the bar: past a few pixels the pointer jumps to the window's middle, and the
        window then follows it, centred on it. `to`: where the pointer's dragged to, in
        Hyprland's pixels on the window's screen."""
        addr, k = w["address"], self.scale
        mon = self.monitor_of(w)
        st = self.bar()
        px, py = st["x"] + st["w"] / 2, st["y"] + st["h"] / 2
        self.bar("press", px, py)
        self.addCleanup(lambda: self.bar("release"))
        st = self.bar("move", px + 10, py)
        self.assertTrue(st["moved"], "ten pixels along and it still isn't a drag")
        middle = [w["at"][0] + w["size"][0] / 2, w["at"][1] + w["size"][1] / 2]
        at = self.until(lambda: self.s.hyprctl("cursorpos", json_out=True),
                        lambda at: abs(at["x"] - middle[0]) <= 1 and abs(at["y"] - middle[1]) <= 1, timeout=3)
        self.assertLessEqual(max(abs(at["x"] - middle[0]), abs(at["y"] - middle[1])), 1,
                             f"the pointer went to {at}, not the window's middle {middle}")
        self.assertLessEqual(max(abs(st["handle"][0] * k - (middle[0] - mon["x"])), abs(st["handle"][1] * k - (middle[1] - mon["y"]))), 1,
                             "the move handle isn't at the window's middle")
        self.bar("move", to[0] / k, to[1] / k)
        want = [mon["x"] + to[0] - w["size"][0] / 2, mon["y"] + to[1] - w["size"][1] / 2]
        near = lambda at: abs(at[0] - want[0]) <= 1 and abs(at[1] - want[1]) <= 1
        at = self.until(lambda: self.client(addr)["at"], near, timeout=3)
        self.assertTrue(near(at), f"dragged to {to} on {mon['name']}, the window's at {at}, not centred on it at {want}")
        self.bar("release")
        self.assertEqual(self.client(addr)["size"], w["size"], "dragging changed its size")
        self.bar_on(self.client(addr))
        self.assertBarOnWindow(addr)

    def check_corner_resize(self, w, to=(700, 260)):
        """Dragging the bar's top right corner: the pointer jumps to that corner of the window,
        which then follows it, the bottom left corner staying put. `to` as for check_drag."""
        addr, k = w["address"], self.scale
        mon = self.monitor_of(w)
        st = self.bar()
        px, py = st["x"] + st["w"] - 2, st["y"] + 2
        self.bar("pressRight", px, py)
        self.addCleanup(lambda: self.bar("sizeEnd"))
        st = self.bar("size", px + 10, py)
        self.assertTrue(st["sized"], "ten pixels along and it still isn't a resize")
        corner = [w["at"][0] + w["size"][0], w["at"][1]]
        at = self.until(lambda: self.s.hyprctl("cursorpos", json_out=True),
                        lambda at: abs(at["x"] - corner[0]) <= 1 and abs(at["y"] - corner[1]) <= 1, timeout=3)
        self.assertLessEqual(max(abs(at["x"] - corner[0]), abs(at["y"] - corner[1])), 1,
                             f"the pointer went to {at}, not the window's corner {corner}")
        self.bar("size", to[0] / k, to[1] / k)
        bottom = w["at"][1] + w["size"][1]
        want = ([w["at"][0], mon["y"] + to[1]], [mon["x"] + to[0] - w["at"][0], bottom - (mon["y"] + to[1])])
        near = lambda c: all(abs(a - b) <= 1 for a, b in zip(c["at"] + c["size"], want[0] + want[1]))
        c = self.until(lambda: self.client(addr), near, timeout=3)
        self.assertTrue(near(c), f"its corner dragged to {to} on {mon['name']}, the window's {c['at']} {c['size']}, not {want}")
        self.bar("sizeEnd")
        self.bar_on(self.client(addr))
        self.assertBarOnWindow(addr)


class TitleBars(TitleBarChecks, LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        for key in ("windowMode", "titleBarStyle"):
            self.keep_setting(key)

    def test_bar_sits_on_its_window(self):
        """The bar Slate draws is exactly on the window Hyprland has, at any Interface size
        (it once took Hyprland's pixels as its own units: right at 100%, off the window and too
        tall at any other size)."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.bar_on(w)
        self.assertBarOnWindow(w["address"])
        # (and after the window's been moved by something else, to a place that isn't a whole
        # number of Slate's units at 125%)
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.move({{ x = 333, y = 257, window = "address:{w["address"]}" }})) end')
        self.until(lambda: self.client(w["address"])["at"], lambda at: at == [333, 257])
        self.bar_on(self.client(w["address"]))
        self.assertBarOnWindow(w["address"])

    def test_looks_only_while_a_window_floats(self):
        """Slate asks Hyprland for the windows a few times a second only while there's a
        floating window for a bar to follow (it once did so all the time, every screen's bar
        for itself). With none it stops; a window opening starts it again, with its bar."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        looks = lambda: self.s.state()["titleBarLooks"]
        quiet = self.steady(looks, floor=0.6, step=0.5)
        self.s.settle(1.5)
        self.assertEqual(looks(), quiet, "still looking at the windows with none floating")
        w = self.floating_foot()
        self.bar_on(w)
        before = looks()
        # (every 150 ms: ten in a second and a half; half that still says it's following the
        # window. Waited for rather than counted in a set time: each look starts a hyprctl, which
        # under a busy run (every part's Hyprland at once) can be slow enough that a set 1.5 s held
        # fewer than five. Five within four seconds is still a look every 800 ms or better)
        self.wait(lambda st: st["titleBarLooks"] - before >= 5, "Slate to follow the floating window", timeout=4)
        # A tiled window is nothing to follow either (the bar goes, and so does the looking)
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.float({{ action = "disable", window = "address:{w["address"]}" }})) end')
        self.wait(lambda st: st["titleBar"] == "", "the bar to go with the window tiled")
        quiet = self.steady(looks, floor=0.6, step=0.5)
        self.s.settle(1.5)
        self.assertEqual(looks(), quiet, "still looking with the only window tiled")
        # ...and floated again, its bar's back as promptly as ever
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.float({{ action = "enable", window = "address:{w["address"]}" }})) end')
        self.wait(lambda st: st["titleBar"] == w["address"], "the bar back on the window floated again", timeout=3)
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{w["address"]}" }})) end')
        self.wait(lambda st: st["titleBar"] == "", "the bar to go with its window")
        quiet = self.steady(looks, floor=0.6, step=0.5)
        self.s.settle(1.5)
        self.assertEqual(looks(), quiet, "still looking after the last floating window closed")

    def test_dragging_the_bar_moves_the_window_under_the_pointer(self):
        """The drag itself, as the bar's own pointer handling does it (TitleBar.qml: dragPress,
        dragTo, dragRelease): the window ends up centred on where the pointer went."""
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.bar_on(w)
        self.check_drag(w)

    def test_dragging_a_corner_resizes_to_the_pointer(self):
        self.config("titleBarStyle", "slate")
        self.config("windowMode", "floating")
        w = self.floating_foot()
        self.bar_on(w)
        self.check_corner_resize(w)

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


class TitleBarsAt125(TitleBars):
    """All of the above at 125% Interface size, in a Slate of its own: Slate's units are then
    Hyprland's pixels over 1.25, so a bar drawn from a window's place, or a window placed from
    the pointer's, without converting shows here."""
    scale = 1.25

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"uiScale": 1.25})
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def test_at_125(self):
        self.assertEqual(float(self.ipc("config", "get", "uiScale")), 1.25)
