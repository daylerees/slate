"""Spaces (the bar's Spaces panel, Spaces.qml): New Space shows the workspaces as they are, each
window live on its card."""
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
        self.assertTrue(self.s.alive(), "Slate died")
        self.assertEqual(self.s.slate_pid(), pid, "Slate restarted")
        self.assertEqual(self.s.state()["popout"], "spaces", "the panel went")
