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
            bare = sum(1 for x in range(w) if all(abs(a - b) <= 14 for a, b in zip(im.getpixel((x, y)), wallpaper(x))))
            self.assertEqual(bare, 0, f"the wallpaper shows across {bare} px during the switch ({shot})")

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
