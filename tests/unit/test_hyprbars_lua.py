"""session/hypr/config/hyprbars.lua: which hyprbars build the Slate session asks Hyprland to
load. A plugin built for another Hyprland doesn't load and makes Hyprland show error notices
at login, so only a build made for the running Hyprland may be asked for. Run under plain Lua
with a stand-in for Hyprland's `hl`, which notes every hl.plugin.load call."""
import json
import os

import slate
from slate import Case, run

CONFIG = slate.path("shell", "session", "hypr", "config", "hyprbars.lua")
COMMIT = "11cbc6c577b84ffb1edf4df3fc5b6128c3ae6947"
OTHER = "acc1aa0000000000000000000000000000000000"

# A stand-in `hl`: version(), the loaded plugins, and plugin.load, which notes the path in
# STUB_CALLS and (unless STUB_REFUSE is set) counts hyprbars as loaded from then on
STUB = r'''
local loaded = os.getenv("STUB_LOADED") == "1"
local anything
anything = setmetatable({}, { __index = function() return anything end, __call = function() return anything end })
hl = setmetatable({
    version = function() return os.getenv("STUB_VERSION") end,
    get_loaded_plugins = function()
        if loaded then return { { name = "hyprbars" } } end
        return {}
    end,
    get_config = function() return nil end,
    config = function() end,
    plugin = setmetatable({
        load = function(path)
            local f = io.open(os.getenv("STUB_CALLS"), "a")
            f:write(path .. "\n"); f:close()
            if os.getenv("STUB_REFUSE") == "1" then error("API version mismatch") end
            loaded = true
        end,
    }, { __index = function() return anything end }),
}, { __index = function() return anything end })
dofile(os.getenv("STUB_CONFIG"))
print("LOADED=" .. tostring(HYPRBARS_LOADED))
'''


def text(path):
    with open(path) as f:
        return f.read()


class HyprbarsLua(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "luajit", "lua5.1")
        self.plugins = os.path.join(self.h.dir, "data", "slate", "plugins")
        os.makedirs(self.plugins)
        self.sig = COMMIT + "_1794313951_949994311"
        self.runtime = os.path.join(self.h.dir, "run")
        os.makedirs(os.path.join(self.runtime, "hypr", self.sig))
        self.note = os.path.join(self.runtime, "hypr", self.sig, "slate-hyprbars")
        self.calls = os.path.join(self.h.dir, "calls")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)
        self.env = dict(self.h.env, XDG_DATA_HOME=os.path.join(self.h.dir, "data"), XDG_RUNTIME_DIR=self.runtime,
                        XDG_STATE_HOME=os.path.join(self.h.dir, "state"),
                        HYPRLAND_INSTANCE_SIGNATURE=self.sig, STUB_VERSION="0.57.2",
                        STUB_CALLS=self.calls, STUB_CONFIG=CONFIG)

    def build(self, name, record=None):
        p = os.path.join(self.plugins, name)
        with open(p, "w") as f:
            f.write("not really a plugin")
        if record is not None:
            with open(p[:-3] + ".json", "w") as f:
                json.dump(record, f)
        return p

    def passes(self, **env):
        """One pass of the config: the paths it asked Hyprland to load, and what it printed."""
        if os.path.exists(self.calls):
            os.remove(self.calls)
        code, out = run([self.lua, self.stub], env=dict(self.env, **env))
        self.assertEqual(code, 0, out)
        asked = text(self.calls).split("\n")[:-1] if os.path.exists(self.calls) else []
        return asked, out

    def test_named_build_for_this_hyprland(self):
        p = self.build("hyprbars-0.57.2-11cbc6c577b8.so")
        self.build("hyprbars-0.57.1-acc1aa000000.so")
        asked, out = self.passes()
        self.assertEqual(asked, [p])
        self.assertIn("LOADED=true", out)
        self.assertEqual(text(self.note), p, "the loaded file wasn't noted")

    def test_named_build_without_commit(self):
        p = self.build("hyprbars-0.57.2.so")
        self.assertEqual(self.passes()[0], [p])

    def test_stale_build_is_never_asked_for(self):
        """The login error: a build for another Hyprland must not reach hl.plugin.load."""
        self.build("hyprbars-0.57.1-acc1aa000000.so")
        self.build("hyprbars.so", {"version": "0.57.1", "commit": OTHER})
        asked, out = self.passes()
        self.assertEqual(asked, [])
        self.assertIn("LOADED=false", out)
        self.assertIn("not loading it", out)

    def test_same_version_other_commit(self):
        """Two -git builds of Hyprland with the same version: told apart by commit."""
        self.build("hyprbars-0.57.2-acc1aa000000.so")
        self.build("hyprbars.so", {"version": "0.57.2", "commit": OTHER})
        self.assertEqual(self.passes()[0], [])

    def test_old_build_with_matching_record(self):
        p = self.build("hyprbars.so", {"version": "0.57.2", "commit": COMMIT})
        self.assertEqual(self.passes()[0], [p])

    def test_old_build_with_version_only_record(self):
        p = self.build("hyprbars.so", {"version": "0.57.2", "commit": ""})
        self.assertEqual(self.passes()[0], [p])

    def test_old_build_without_record(self):
        """From before builds were named: loaded as it was, so nobody loses a working one."""
        p = self.build("hyprbars.so")
        self.assertEqual(self.passes()[0], [p])

    def test_named_build_wins_over_old(self):
        self.build("hyprbars.so")
        p = self.build("hyprbars-0.57.2-11cbc6c577b8.so")
        self.assertEqual(self.passes()[0], [p])

    def test_nothing_built(self):
        asked, out = self.passes()
        self.assertEqual(asked, [])
        self.assertIn("LOADED=false", out)

    def test_removed(self):
        """After Remove Hyprbars, the build Hyprland still had loaded isn't loaded again."""
        self.build("hyprbars-0.57.2-11cbc6c577b8.so")
        self.build("removed")
        self.assertEqual(self.passes()[0], [])

    def test_loaded_keeps_asking_for_the_same_file(self):
        """Once loaded, the same file on every pass (skipping it makes Hyprland unload it and
        reload in a loop), even when a newer build or the removed mark has appeared since."""
        p = self.build("hyprbars-0.57.2-11cbc6c577b8.so")
        self.assertEqual(self.passes()[0], [p])
        self.build("removed")
        self.build("hyprbars-0.58.0-ffffffffffff.so")
        self.assertEqual(self.passes(STUB_LOADED="1")[0], [p])

    def test_loaded_before_notes(self):
        """A session that loaded the old build before this file noted paths: the old build."""
        p = self.build("hyprbars.so")
        self.build("hyprbars-0.57.2-11cbc6c577b8.so")
        self.assertEqual(self.passes(STUB_LOADED="1")[0], [p])
        self.assertEqual(text(self.note), p)

    def test_refused_load_is_survived(self):
        p = self.build("hyprbars.so")
        asked, out = self.passes(STUB_REFUSE="1")
        self.assertEqual(asked, [p])
        self.assertIn("didn't load", out)
        self.assertIn("LOADED=false", out)
        self.assertFalse(os.path.exists(self.note))

    def test_without_instance_signature(self):
        """Hyprland started some other way: the version alone decides."""
        p = self.build("hyprbars-0.57.2.so")
        self.build("hyprbars-0.57.1.so")
        self.assertEqual(self.passes(HYPRLAND_INSTANCE_SIGNATURE="")[0], [p])
