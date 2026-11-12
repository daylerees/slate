"""Switching workspace with the slide (Super+Left/Right): the desktop never shows between the
workspace leaving and the one arriving, and windows are square while they move."""
import os
import tempfile

from PIL import Image

import test_switcher_animations as switching     # (the module, so its tests aren't collected again here)


class WorkspaceSwitch(switching.SwitcherAnimations):
    # (only this file's tests: the ones it borrows its helpers from run in their own)
    test_overview_every_move_and_pick = None
    test_window_switcher_every_move_and_pick = None
    test_overview_grid_arrows = None

    def animations(self):
        out, leaf = {}, None
        for line in self.s.hyprctl("animations").splitlines():
            line = line.strip()
            if line.startswith("name:"):
                leaf = line.split(":", 1)[1].strip()
                out[leaf] = {}
            elif leaf and ":" in line:
                k, v = line.split(":", 1)
                out[leaf][k.strip()] = v.strip()
        return out

    def test_old_workspace_lasts_as_long_as_the_new_one_takes(self):
        a = self.animations()
        self.assertEqual(a["workspacesOut"]["bezier"], "holdFade")
        self.assertEqual(a["workspacesOut"]["speed"], a["workspacesIn"]["speed"],
                         "the old workspace is gone before the new one has arrived: the desktop shows in between")

    def test_no_desktop_between_the_workspaces_mid_slide(self):
        # (without the spare empty workspace: keeping one, Slate looks after the workspaces as
        # they change, which puts the usual animation back over this test's slowed-down one)
        self.keep_setting("keepEmptyWorkspace")
        self.config("keepEmptyWorkspace", "false")
        # (one window on each, filling it: a window left by an earlier test made one a split,
        # whose gaps at the screen's edges show the wallpaper anyway, and this failed now and then)
        self.close_windows()
        self.windows_on_two_workspaces()
        self.addCleanup(lambda: self.s.hyprctl("eval", 'hl.config({ animations = { enabled = false } }); setWorkspaceAnimation("slidefade")'))
        # The switch as it is, ten times slower, so a picture can be taken partway through
        a = self.animations()
        slow = lambda leaf: ('hl.animation({ leaf = "%s", enabled = true, speed = %s, bezier = "%s", style = "%s" })'
                             % (leaf, float(a[leaf]["speed"]) * 10, a[leaf]["bezier"], a[leaf]["style"]))
        self.s.hyprctl("eval", "hl.config({ animations = { enabled = true } }); " + slow("workspacesIn") + "; " + slow("workspacesOut"))
        self.s.settle(0.3)
        before = os.path.join(tempfile.mkdtemp(), "before.png")
        self.s.screenshot(before)
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.focus({ workspace = "m+1" })) end')
        shots = []
        for i in range(3):                       # (about half way, and on towards the end)
            self.s.settle(1.0)
            shots.append(self.s.screenshot(os.path.join(os.path.dirname(before), f"mid{i}.png")))
        self.s.settle(3.0)
        # The window fills the screen under the bar on both workspaces, so across the middle
        # there's only ever a window: the one arriving, or the one leaving under it (dimmed, and
        # a touch see-through as it starts to go). Never the bare wallpaper, which showed in the
        # strip the arriving workspace hadn't reached yet. The tests' wallpaper is a known
        # gradient (lib/session.py make_wallpaper), so "bare" is a pixel that matches it
        w, h = Image.open(before).size
        y = h // 2
        def wallpaper(x):
            t = (x / w + y / h) / 2
            return (int(28 + 40 * t), int(44 + 50 * t), int(72 + 70 * (1 - t)))
        for shot in shots:
            im = Image.open(shot).convert("RGB")
            xs = [x for x in range(w) if all(abs(a - b) <= 14 for a, b in zip(im.getpixel((x, y)), wallpaper(x)))]
            if xs:
                # (kept with the run's other output, to look at)
                keep = os.path.join(self.s.out, "slide-" + os.path.basename(shot))
                im.save(keep)
                Image.open(before).save(os.path.join(self.s.out, "slide-before.png"))
            self.assertEqual(len(xs), 0, f"the wallpaper shows across {len(xs)} px during the switch, at x {xs[:1]}…{xs[-1:]} ({shot})")

    def test_windows_are_square_while_a_switch_slides(self):
        self.windows_on_two_workspaces()
        self.addCleanup(lambda: self.s.hyprctl("eval", "SOLO_SQUARE_RULE:set_enabled(true)"))
        self.s.hyprctl("eval", "SOLO_SQUARE_RULE:set_enabled(false)")     # (a lone window is square anyway)
        self.s.settle(0.4)
        rounding = lambda: self.s.hyprctl("getprop", "active", "rounding").strip()
        usual = rounding()
        self.assertNotEqual(usual, "0")
        self.s.hyprctl("eval", "squareWhileSliding()")
        self.s.settle(0.15)
        self.assertEqual(rounding(), "0", "windows kept their rounded corners during the switch")
        self.s.settle(0.9)
        self.assertEqual(rounding(), usual, "windows didn't get their corners back")

    def test_windows_keep_their_corners_when_nothing_slides(self):
        self.windows_on_two_workspaces()
        self.addCleanup(lambda: self.s.hyprctl("eval", 'SOLO_SQUARE_RULE:set_enabled(true); setWorkspaceAnimation("slidefade")'))
        self.s.hyprctl("eval", 'SOLO_SQUARE_RULE:set_enabled(false); setWorkspaceAnimation("crossfade")')
        self.s.settle(0.4)
        usual = self.s.hyprctl("getprop", "active", "rounding").strip()
        self.s.hyprctl("eval", "squareWhileSliding()")
        self.s.settle(0.15)
        self.assertEqual(self.s.hyprctl("getprop", "active", "rounding").strip(), usual)

    def test_slide_to_an_empty_workspace_isnt_cut_short(self):
        # To an empty workspace the windows slide away. The usual animation (which holds the
        # workspace that's leaving where it was) came back before the slide was over, and the
        # windows showed again in place: an echo of them
        self.windows_on_two_workspaces()
        self.addCleanup(lambda: self.go_to_workspace(1))
        self.s.hyprctl("dispatch", "function() slideAwayTo(hl.dsp.focus({ workspace = 9 })) end")
        self.s.settle(0.43)
        self.assertTrue(self.animations()["workspacesOut"]["style"].startswith("slidefade"),
                        "the slide away was replaced while the windows were still leaving")
        self.s.settle(0.5)
        self.assertEqual(self.animations()["workspacesOut"]["style"], "fade", "the usual animation never came back")


class SplitSlides(switching.SwitcherAnimations):
    """Every window on the workspace arriving slides in with it. Going from a workspace with one
    window to one with two side by side, only one slid; the other faded in once the slide was
    over (seen by Dayle, 2026-11-12). The windows are filled with colours of their own, and a
    picture partway through the (slowed) slide has to have both of the arriving ones in it."""
    test_overview_every_move_and_pick = None
    test_window_switcher_every_move_and_pick = None
    test_overview_grid_arrows = None

    COLOURS = {"left": (230, 30, 30), "right": (30, 200, 60), "alone": (220, 200, 40)}
    ALPHA = {}

    def coloured(self, ws, name):
        self.go_to_workspace(ws)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        r, g, b = self.COLOURS[name]
        alpha = self.ALPHA.get(name, 1.0)
        self.s.hyprctl("eval", f'hl.exec_cmd("foot -o colors-dark.background={r:02x}{g:02x}{b:02x} -o colors-dark.alpha={alpha}")')
        for _ in range(50):
            if {c["address"] for c in self.s.hyprctl("clients", json_out=True)} - before:
                return
            self.s.settle(0.2)
        self.fail("no window")

    def share(self, im, colour):
        """How much of the middle row is this window: by which colour leads, as a window that
        isn't focused is dimmed (and a touch see-through), so it's darker than it's filled."""
        w, h = im.size
        lead = max(range(3), key=lambda i: colour[i])
        hits = 0
        for x in range(0, w, 4):
            p = im.getpixel((x, h // 2))
            others = [p[i] for i in range(3) if i != lead]
            if p[lead] > 60 and p[lead] > 2 * max(others):
                hits += 1
        return hits

    def slide(self, frm, to, how="keys"):
        self.go_to_workspace(frm)
        self.s.settle(1.0)
        self.s.hyprctl("eval", 'hl.config({ animations = { enabled = true } }); SLATE_ANIM_SLOW = 10; setWorkspaceAnimation("slidefade")')
        self.s.settle(0.3)
        d = tempfile.mkdtemp()
        if how == "keys":     # as Super+Left/Right do it: with the windows squared for the slide, and so on
            self.s.hyprctl("dispatch", f"function() cycleWorkspace({1 if to > frm else -1}) end")
        else:                 # straight there, as the number keys and the bar's dots do
            self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {to} }})) end")
        shots = []
        for i in range(3):
            self.s.settle(0.7)
            shots.append(Image.open(self.s.screenshot(os.path.join(d, f"s{i}.png"))).convert("RGB"))
        self.s.settle(3.0)
        return shots

    def test_both_windows_slide_in(self):
        self.addCleanup(lambda: self.s.hyprctl("eval", 'hl.config({ animations = { enabled = false } }); SLATE_ANIM_SLOW = nil; setWorkspaceAnimation("slidefade")'))
        self.keep_setting("glass")
        self.config("glass", "true")
        self.close_windows()
        self.coloured(1, "alone")
        self.coloured(2, "left")
        self.coloured(2, "right")
        self.s.settle(1.5)
        # (3's window is opened last, so it's newer than both arriving ones: the case that went wrong)
        self.coloured(3, "alone")
        self.s.settle(1.0)
        for frm, to, how in ((1, 2, "keys"), (3, 2, "keys"), (3, 2, "straight")):
            with self.subTest(f"{frm} to {to} ({how})"):
                shots = self.slide(frm, to, how)
                mid = shots[1]
                left, right = self.share(mid, self.COLOURS["left"]), self.share(mid, self.COLOURS["right"])
                if not (left and right):
                    for i, im in enumerate(shots):
                        im.save(os.path.join(self.s.out, f"split-{frm}-{to}-{i}.png"))
                self.assertTrue(left > 0 and right > 0,
                                f"partway through, only one of the arriving windows was there (left {left}, right {right})")


class FastSwitching(SplitSlides):
    """Switching through several workspaces quickly (Super+Right, again and again): the one you
    started on mustn't show through the others. Each workspace left held on, fully there, until
    the next had arrived, so a bright window on the first could be made out behind every one
    passed (Dayle, 2026-11-12)."""
    test_both_windows_slide_in = None
    COLOURS = {"white": (255, 255, 255), "black": (0, 0, 0)}
    ALPHA = {"black": 0.5}            # (see-through, as a terminal often is: what's behind shows)

    def test_first_workspace_gone_when_hurrying(self):
        self.addCleanup(lambda: self.s.hyprctl("eval", 'SLATE_ANIM_SLOW = nil; hl.config({ animations = { enabled = false } }); setWorkspaceAnimation("slidefade")'))
        self.keep_setting("keepEmptyWorkspace")
        self.config("keepEmptyWorkspace", "false")
        self.close_windows()
        self.coloured(1, "white")
        for ws in (2, 3, 4):
            self.coloured(ws, "black")
        self.go_to_workspace(1)
        self.s.settle(1.0)
        # Everything ten times slower, so "quickly" is easy to do and see
        self.s.hyprctl("eval", 'SLATE_ANIM_SLOW = 10; hl.config({ animations = { enabled = true } }); setWorkspaceAnimation("slidefade")')
        self.s.settle(0.3)
        for _ in range(3):
            self.s.hyprctl("dispatch", "function() cycleWorkspace(1) end")
            self.s.settle(0.5)
        # (partway through the last slide: what isn't covered yet by the workspace arriving
        # should be the one just left, black, not the first)
        shot = Image.open(self.s.screenshot(os.path.join(tempfile.mkdtemp(), "fast.png"))).convert("RGB")
        w, h = shot.size
        # Seen through the half see-through black windows, the white first workspace is a plain
        # grey; what should be there is the wallpaper behind them, which is blue
        def grey(p):
            return p[0] > 25 and abs(p[0] - p[2]) < 10 and abs(p[0] - p[1]) < 10
        white = sum(1 for x in range(0, w, 4) for y in (h // 3, h // 2, 2 * h // 3) if grey(shot.getpixel((x, y))))
        if white:
            shot.save(os.path.join(self.s.out, "fast-switch.png"))
        self.assertEqual(white, 0, f"the first workspace's white window still shows ({white} spots), 3 switches later")
