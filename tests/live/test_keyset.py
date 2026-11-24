"""The shortcut set Hyprland uses follows the setting however it changed: only the dropdown
(and Welcome) wrote the file binds.lua reads, so Restore defaults, an import or the assistant
changed Settings' set while Hyprland kept the old keys."""
import os

from live import LiveCase


class Keyset(LiveCase):
    def path(self):
        return os.path.join(self.s.h.state, "slate", "keyset.lua")

    def file(self):
        try:
            with open(self.path()) as f:
                return f.read()
        except OSError:
            return ""

    def binds(self):
        return {(b.get("modmask"), b.get("key")) for b in self.s.hyprctl("binds", json_out=True)}

    def test_the_setting_alone_changes_hyprlands_keys(self):
        self.keep_setting("keyset")
        self.config("keyset", "slate")
        self.wait(lambda st: self.file() in ("", 'KEYSET = "slate"\n'), "Slate's set")
        self.s.settle(1.5)
        slates = self.binds()
        # As Restore defaults and an import do it: the setting, not the dropdown
        self.config("keyset", "hyprland")
        self.wait(lambda st: self.file() == 'KEYSET = "hyprland"\n', "the file to follow the setting", timeout=10)
        self.wait(lambda st: self.binds() != slates, "Hyprland's keys to change", timeout=10)
        self.config("keyset", "slate")
        self.wait(lambda st: self.file() == 'KEYSET = "slate"\n', "back to Slate's set", timeout=10)
        self.wait(lambda st: self.binds() == slates, "Slate's keys back", timeout=10)
