"""What reaches Slate over IPC is checked before it's kept or handed to Hyprland: a workspace's
mode is only ever one of Slate's (it's written into Lua that Hyprland runs), `config set`
stores only a value of the kind the setting holds, and text put into Lua goes through
Config.luaString, whatever it has in it."""
import json
import os

from live import LiveCase


class WorkspaceMode(LiveCase):
    def test_only_a_mode_slate_has(self):
        mark = os.path.join(self.s.h.dir, "lua-ran")
        self.addCleanup(lambda: self.ipc("workspacemode", "set", "7", ""))
        # (what the old "${mode}" would have let through: the string closed, then Lua of its own)
        hostile = 'x") end; local f = io.open("%s", "w"); if f then f:close() end; if false then setWorkspaceMode(7, "' % mark
        for mode in (hostile, "nonsense", 'tiling"'):
            with self.subTest(mode):
                self.ipc("workspacemode", "set", "7", mode)
                self.s.settle(0.6)
                self.assertEqual(self.ipc("workspacemode", "get", "7"), "", "kept a mode that isn't one")
        self.assertFalse(os.path.exists(mark), "Hyprland ran what was in the mode")
        modes = os.path.join(self.s.h.runtime, "slate", "workspace-modes-%s.json" % self.s.env["HYPRLAND_INSTANCE_SIGNATURE"])
        if os.path.exists(modes):
            with open(modes) as f:
                self.assertNotIn("7", json.load(f))

    def test_a_real_mode_still_sets(self):
        self.addCleanup(lambda: self.ipc("workspacemode", "set", "7", ""))
        self.ipc("workspacemode", "set", "7", "scrolling")
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "scrolling")
        self.ipc("workspacemode", "set", "7", "")
        self.assertEqual(self.ipc("workspacemode", "get", "7"), "")


class ConfigSet(LiveCase):
    def unchanged(self, key, *values):
        before = self.setting(key)
        for value in values:
            with self.subTest(key=key, value=value):
                self.ipc("config", "set", key, value)
                self.s.settle(0.3)
                self.assertEqual(self.setting(key), before)

    def test_a_list_takes_only_a_list(self):
        """Stored as text, every place reading the list stopped with an error."""
        saved = lambda: json.load(open(os.path.join(self.s.slate_dir, "settings.json"))).get("startupApps", [])
        self.assertEqual(self.setting("startupApps"), "")
        # (a space first: `qs ipc call` itself takes "[…]" apart)
        self.addCleanup(lambda: self.ipc("config", "set", "startupApps", " []"))
        self.unchanged("startupApps", "foot.desktop", "", '{"foot.desktop": true}', '"foot.desktop"', "7", "null", " [")
        self.s.settle(1.0)
        self.assertEqual(saved(), [])
        self.ipc("config", "set", "startupApps", ' ["foot.desktop", "kitty.desktop"]')
        for _ in range(40):
            if saved() == ["foot.desktop", "kitty.desktop"]:
                break
            self.s.settle(0.1)
        self.assertEqual(saved(), ["foot.desktop", "kitty.desktop"])
        self.assertEqual(self.setting("startupApps"), "foot.desktop,kitty.desktop")

    def test_a_number_takes_only_a_number(self):
        self.keep_setting("dockIconSize")
        self.unchanged("dockIconSize", "abc", "", " ", "NaN", "Infinity", "12px")
        self.config("dockIconSize", "40")
        self.config("dockIconSize", "52")

    def test_a_switch_takes_only_true_or_false(self):
        self.keep_setting("barClockDate")
        self.config("barClockDate", "true")
        self.unchanged("barClockDate", "yes", "", "0", "False")
        self.config("barClockDate", "false")
        self.unchanged("barClockDate", "1", "True")

    def test_a_setting_that_isnt_one(self):
        self.ipc("config", "set", "noSuchSetting", "1")
        self.assertEqual(self.setting("noSuchSetting"), "undefined")


class LuaString(LiveCase):
    def test_hyprland_reads_back_what_went_in(self):
        """Each piece of text, written as Slate writes it into Lua, is the same text once
        Hyprland's Lua has read it: nothing ends the string early."""
        out = os.path.join(self.s.h.dir, "lua-string.txt")
        for text in ("Dell Inc. U2720Q 7XJ5T13", "]==]", "]]", "x]=", 'say "hi"', "back\\slash", "it's",
                     "tab\there", "two\nlines", '"); os.exit(); ("', "café ü 日本", ""):
            with self.subTest(text):
                literal = self.ipc("test", "luaString", text)
                if os.path.exists(out):
                    os.remove(out)
                self.s.hyprctl("eval", 'local f = io.open("%s", "w"); f:write(%s); f:close()' % (out, literal))
                for _ in range(30):
                    if os.path.exists(out):
                        break
                    self.s.settle(0.1)
                self.assertTrue(os.path.exists(out), "Hyprland couldn't read %s" % literal)
                with open(out, encoding="utf-8") as f:
                    self.assertEqual(f.read(), text)
