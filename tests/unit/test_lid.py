"""session/hypr/config/slate.lua: closing the lid (Settings → Power). With another screen plugged
in it only turns the laptop's own screen off; a screen that's switched off (in Settings →
Displays, or the tests' virtual one) counted as one, so the lid only blanked the panel instead of
suspending or locking (a bug). Run under plain Lua with a stand-in for Hyprland's `hl`."""
import os

import slate
from slate import Case, run

CONFIG = slate.path("shell", "session", "hypr", "config", "slate.lua")
STUB = r'''
local binds, did = {}, {}
local function noop() end
local anything = setmetatable({}, { __index = function() return noop end, __call = function() return {} end })
hl = setmetatable({
    bind = function(keys, fn) binds[keys] = fn end,
    exec_cmd = function(cmd) did[#did + 1] = "exec " .. cmd end,
    dispatch = function(d) did[#did + 1] = "dispatch" end,
    dsp = setmetatable({}, { __index = function() return function() return {} end end }),
    get_monitors = function() return MONITORS end,
}, { __index = function() return noop end })
SLATE_DIR, SLATE = "/slate", "/slate/bin/slate"
dofile(os.getenv("STUB_CONFIG"))
LID_ACTION = "suspend"
MONITORS = load("return " .. os.getenv("STUB_MONITORS"))()
binds["switch:on:Lid Switch"]()
print(table.concat(did, "\n"))
'''


class Lid(Case):
    scratch = True

    def close_lid(self, monitors):
        lua = slate.need("lua", "luajit", "lua5.4")
        stub = os.path.join(self.h.dir, "stub.lua")
        with open(stub, "w") as f:
            f.write(STUB)
        code, out = run([lua, stub], env=dict(self.h.env, STUB_CONFIG=CONFIG, STUB_MONITORS=monitors))
        self.assertEqual(code, 0, out)
        return out

    def test_a_switched_off_screen_isnt_another_screen(self):
        out = self.close_lid('{ { name = "eDP-1" }, { name = "DP-1", enabled = false } }')
        self.assertIn("exec /slate/bin/slate-init suspend", out, "the lid only blanked the screen")

    def test_another_screen_in_use_only_blanks_the_panel(self):
        out = self.close_lid('{ { name = "eDP-1" }, { name = "DP-1" } }')
        self.assertNotIn("suspend", out)
        self.assertIn("dispatch", out)
