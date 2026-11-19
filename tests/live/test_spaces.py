"""Spaces (the bar's Spaces panel, Spaces.qml): New Space shows the workspaces as they are, each
window live on its card."""
import os

from live import LiveCase


class NewSpace(LiveCase):
    def setUp(self):
        super().setUp()
        self.close_windows()
        self.addCleanup(lambda: self.ipc("popout", "close"))

    def foot(self, ws):
        self.s.hyprctl("dispatch", f"function() hl.dispatch(hl.dsp.focus({{ workspace = {ws} }})) end")
        self.s.settle(0.3)
        before = {c["address"] for c in self.s.hyprctl("clients", json_out=True)}
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        for _ in range(50):
            new = [c for c in self.s.hyprctl("clients", json_out=True) if c["address"] not in before]
            if new:
                self.s.settle(0.4)
                return new[0]["address"]
            self.s.settle(0.2)
        self.fail("no new window")

    def open_new_space(self):
        self.ipc("bar", "panel", "spaces")
        self.wait(lambda st: st["popout"] == "spaces", "the Spaces panel")
        self.ipc("test", "newSpace")
        self.s.settle(1.5)               # (the snapshot, then the cards and their live previews)

    def test_closing_windows_it_shows(self):
        """Closing several windows at once while New Space showed them live crashed Slate (the
        Wayland connection's fatal error, seen by Dayle, 2026-11-12). It came from Quickshell's
        live capture on a real graphics card and never happened here (the static WindowPreviews
        checks guard the fix); this keeps closing windows under New Space working."""
        windows = [self.foot(2), self.foot(2), self.foot(3)]
        pid = self.s.slate_pid()
        self.open_new_space()
        self.s.hyprctl("dispatch", "function() "
                       + " ".join(f'hl.dispatch(hl.dsp.window.close({{ window = "address:{a}" }}))' for a in windows)
                       + " end")
        self.s.settle(2.0)
        self.assertFalse(self.s.died(), "Slate died (tests/out/live/slate.log and crashes/)")
        self.assertEqual(self.s.slate_pid(), pid, "Slate restarted")
        self.assertEqual(self.s.state()["popout"], "spaces", "the panel went")


class Saving(LiveCase):
    def test_the_first_space_saved_shows_in_the_list(self):
        """Saving a space when none has been saved yet (no spaces.json): the panel's list has it
        straight away. It stayed empty until Slate restarted: the list is read again when the
        file changes, and a file that wasn't there yet wasn't watched. Bug, 2026-11-19."""
        store = os.path.join(self.s.h.data, "slate", "spaces.json")
        if os.path.exists(store):
            os.remove(store)
        self.addCleanup(lambda: os.path.exists(store) and os.remove(store))
        self.s.hyprctl("eval", 'hl.exec_cmd("foot")')
        self.s.settle(1.0)
        self.ipc("test", "saveSpace", "Work", "1")
        self.wait(lambda st: st["spaces"]["saved"] == 1, "the new space in the list")
        self.assertTrue(os.path.exists(store), "it wasn't saved")
