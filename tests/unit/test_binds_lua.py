"""session/hypr/config/binds.lua and scripts/need.sh: every shortcut does something.

Two ways a shortcut has done nothing at all (both bugs):
- Super+D in "Hyprland + Slate Extras" called maximiseSmart(), which was only made inside
  Slate's own key set, so every press called nil.
- Super+P (hyprpicker) and Ctrl+Shift+Esc (btop) started tools that are optional on several
  distros, with nothing said when they aren't installed.

binds.lua is run under plain Lua for each key set with a stand-in for Hyprland's `hl` that
notes every bind; then every bound function is pressed (with nothing open, and again with
Slate's overlays open and a floating window), and nothing may fail. The only globals handed to
it are the ones the rest of Slate's Hyprland config really defines."""
import os
import re

import slate
from slate import Case, run
from stubs import Stubs

CONFIG_DIR = slate.path("shell", "session", "hypr", "config")
BINDS = os.path.join(CONFIG_DIR, "binds.lua")
NEED = slate.path("shell", "scripts", "need.sh")
KEYSETS = ("slate", "hyprland", "hyprland-extras")

# The stand-in `hl`. Prints one line per thing noted, tab separated:
#   BIND <keys>            a shortcut was made (top level, not inside a submap)
#   EXEC <keys> <command>  pressing it started this command
#   ERR  <keys> <message>  pressing it failed
STUB = r'''
local overlays = false      -- are Slate's overlays (launcher, switcher, overview…) "open"?
local pressing = "(loading)"
local function note(kind, a, b) print(kind .. "\t" .. a .. (b and ("\t" .. b) or "")) end
local anything
anything = setmetatable({}, { __index = function() return anything end, __call = function() return anything end })
local binds, inSubmap = {}, false
local window = { address = "0xabc", floating = true, mapped = true, workspace = { id = 1, name = "1" } }
local workspace = { id = 1, name = "1", windows = 1, monitor = { name = "DP-1" } }
local function started(cmd) note("EXEC", pressing, tostring(cmd)) end
hl = setmetatable({
    bind = function(keys, action, opts)
        if inSubmap then return end
        note("BIND", keys)
        binds[#binds + 1] = { keys = keys, action = action }
    end,
    dispatch = function(d) if type(d) == "table" and rawget(d, "exec") then started(d.exec) end end,
    exec_cmd = started,
    dsp = setmetatable({ exec_cmd = function(cmd) return { exec = cmd } end }, { __index = function() return anything end }),
    on = function() end,
    env = function() end,
    config = function() end,
    get_config = function() return 1.0 end,
    define_submap = function(name, fn) inSubmap = true; fn(); inSubmap = false end,
    -- (timers fire straight away, so what they'd do later is pressed too)
    timer = function(fn) fn(); return { set_enabled = function() end } end,
    get_layers = function() return overlays and { { mapped = true, keyboard_interactivity = 1 } } or {} end,
    get_windows = function() return { window } end,
    get_active_window = function() return window end,
    get_workspaces = function() return { workspace, { id = 2, name = "2", windows = 0, monitor = { name = "DP-1" } } } end,
    get_active_workspace = function() return workspace end,
    get_active_special_workspace = function() return nil end,
}, { __index = function() return anything end })

-- What hyprland.lua and variables.lua set before binds.lua loads
SLATE_DIR = os.getenv("STUB_SLATE_DIR")
SLATE = SLATE_DIR .. "/bin/slate"
TERMINAL, FILE_MANAGER, EDITOR, CALCULATOR = "foot", "nautilus", "gedit", "gnome-calculator"
MONITOR1, MONITOR2, MONITOR3, NUM_WPM = "", "", "", 3
-- The functions the rest of Slate's config makes (found by the test: STUB_GLOBALS)
for name in os.getenv("STUB_GLOBALS"):gmatch("%S+") do
    _G[name] = function() return 1 end
end

dofile(os.getenv("STUB_CONFIG"))

local function pressAll()
    for _, b in ipairs(binds) do
        pressing = b.keys
        if type(b.action) == "function" then
            local ok, err = pcall(b.action)
            if not ok then note("ERR", b.keys, tostring(err)) end
        else
            hl.dispatch(b.action)
        end
    end
end
pressAll()
overlays, SLATE_TITLEBARS = true, true
pressAll()
'''


def other_config_functions():
    """Global functions made by Slate's Hyprland config outside binds.lua (windowrules.lua's
    slateKeepUnderBar, workspaces.lua's newWorkspace…): the only ones binds.lua may lean on."""
    names = set()
    for n in os.listdir(CONFIG_DIR):
        if n.endswith(".lua") and n != "binds.lua":
            with open(os.path.join(CONFIG_DIR, n)) as f:
                names.update(re.findall(r"^function ([A-Za-z_]\w*)\(", f.read(), re.M))
    return sorted(names)


class BindsLua(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "luajit", "lua5.1")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)
        self.state = os.path.join(self.h.dir, "state")
        os.makedirs(os.path.join(self.state, "slate"))

    def press_all(self, keyset):
        """Load binds.lua with this key set and press everything: (keys bound, {keys: commands
        started}, [failures])."""
        with open(os.path.join(self.state, "slate", "keyset.lua"), "w") as f:
            f.write(f'KEYSET = "{keyset}"\n')
        env = dict(self.h.env, XDG_STATE_HOME=self.state, STUB_CONFIG=BINDS, STUB_SLATE_DIR=slate.SHELL,
                   STUB_GLOBALS=" ".join(other_config_functions()))
        env.pop("UWSM_FINALIZE_VARNAMES", None)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        bound, started, failed = [], {}, []
        for line in out.splitlines():
            kind, _, rest = line.partition("\t")
            keys, _, what = rest.partition("\t")
            if kind == "BIND":
                bound.append(keys)
            elif kind == "EXEC":
                started.setdefault(keys, []).append(what)
            elif kind == "ERR":
                failed.append(f"{keys}: {what}")
        return bound, started, failed

    def test_every_shortcut_can_be_pressed(self):
        """No shortcut, in any key set, calls something that key set doesn't have."""
        for keyset in KEYSETS:
            with self.subTest(keyset=keyset):
                bound, _, failed = self.press_all(keyset)
                self.assertGreater(len(bound), 30, "the binds weren't made")
                self.assertEqual(failed, [])

    def test_super_d_maximises_in_slates_set_and_the_extras(self):
        for keyset, there in (("slate", True), ("hyprland-extras", True), ("hyprland", False)):
            with self.subTest(keyset=keyset):
                bound, started, failed = self.press_all(keyset)
                self.assertEqual("SUPER + D" in bound, there)
                self.assertEqual([f for f in failed if f.startswith("SUPER + D:")], [])
                if there:
                    # (the second press is with Slate's title bars on and a floating window)
                    self.assertEqual(started.get("SUPER + D"),
                                     [slate.SHELL + "/bin/slate ipc call titlebar maximise 0xabc"])

    def test_optional_tools_go_through_need(self):
        """The colour picker and the system monitor say what's missing rather than doing nothing."""
        for keyset, picker in (("slate", "SUPER + P"), ("hyprland-extras", "SUPER + SHIFT + P")):
            with self.subTest(keyset=keyset):
                _, started, _ = self.press_all(keyset)
                self.assertEqual(set(started[picker]),
                                 {NEED + " hyprpicker 'The colour picker' -- hyprpicker -a -n"})
                self.assertEqual(set(started["CONTROL + SHIFT + Escape"]),
                                 {NEED + " btop 'The system monitor' -- foot -e btop"})

    def test_no_optional_tool_is_started_directly(self):
        """Nothing a shortcut starts is a tool some distro's package list marks optional ("?"),
        unless it goes through need.sh."""
        optional = set()
        for n in os.listdir(slate.path("packaging")):
            if n.endswith(".txt"):
                with open(slate.path("packaging", n)) as f:
                    optional.update(re.findall(r"^\?(?:[\w-]+/)?([\w.+-]+)", f.read(), re.M))
        self.assertIn("btop", optional)
        self.assertIn("hyprpicker", optional)
        for keyset in KEYSETS:
            with self.subTest(keyset=keyset):
                _, started, _ = self.press_all(keyset)
                direct = [f"{keys}: {cmd}" for keys, cmds in started.items() for cmd in cmds
                          if not cmd.startswith(NEED + " ")
                          and optional & set(os.path.basename(w) for w in cmd.split())]
                self.assertEqual(direct, [])


class Need(Case):
    """scripts/need.sh, run as the shortcuts run it (through sh -c, as Hyprland does)."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("notify-send")
        self.s.add("foot")

    def press(self, tool, what, command):
        code, out = run(["/bin/sh", "-c", f"{NEED} {tool} '{what}' -- {command}"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)

    def test_is_executable(self):
        self.assertTrue(os.access(NEED, os.X_OK), "scripts/need.sh isn't executable, so the shortcuts can't run it")

    def test_installed_runs_the_command_as_it_was(self):
        self.s.add("hyprpicker")
        self.press("hyprpicker", "The colour picker", "hyprpicker -a -n")
        self.assertEqual(self.s.calls("hyprpicker"), [["-a", "-n"]])
        self.assertEqual(self.s.calls("notify-send"), [])

    def test_installed_runs_it_in_the_terminal(self):
        self.s.add("btop")
        self.press("btop", "The system monitor", "foot -e btop")
        self.assertEqual(self.s.calls("foot"), [["-e", "btop"]])
        self.assertEqual(self.s.calls("notify-send"), [])

    def test_missing_says_what_to_install_and_runs_nothing(self):
        self.s.add("btop", missing=True)
        self.press("btop", "The system monitor", "foot -e btop")
        self.assertEqual(self.s.calls("foot"), [], "a terminal was opened for a tool that isn't there")
        calls = self.s.calls("notify-send")
        self.assertEqual(len(calls), 1)
        said = calls[0]
        self.assertEqual(said[said.index("-a") + 1], "Slate")
        self.assertTrue(os.path.isfile(said[said.index("-i") + 1]), "the notification's icon isn't there")
        self.assertEqual(said[-2], "The system monitor needs btop")
        self.assertIn("btop isn't installed yet", said[-1])
        self.assertNotIn("!", said[-2] + said[-1])

    def test_missing_colour_picker(self):
        self.s.add("hyprpicker", missing=True)
        self.press("hyprpicker", "The colour picker", "hyprpicker -a -n")
        self.assertEqual(self.s.calls("notify-send")[0][-2], "The colour picker needs hyprpicker")

    def test_wrong_use_runs_nothing(self):
        code, out = run(["/bin/sh", NEED, "btop", "foot", "-e", "btop"], env=self.s.env, timeout=10)
        self.assertEqual(code, 2, out)
        self.assertEqual(self.s.calls("foot"), [])
