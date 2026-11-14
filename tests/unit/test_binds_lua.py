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

# The stand-in `hl`. Prints one line per thing noted, tab separated (n is the bind's place in
# the order they were made, so two binds on the same keys stay apart):
#   BIND n <submap> <keys> <flags> <description> <action>   a shortcut was made
#   CALL <scenario> n <what>     pressing it did this: "exec <command>", "dispatch <dispatcher>",
#                                "config <settings>", "timer <options>", or one of the rest of the
#                                config's functions with what it was given
#   ERR  <scenario> n <message>  pressing it failed
#   ON   <event>                 something was set to happen on one of Hyprland's events
# Every shortcut is pressed once in each of SCENARIOS (nothing open, each of Slate's overlays
# open, no window, each window mode…), so what a shortcut does, everywhere it looks before
# acting, can be compared between key sets.
STUB = r"""
local scenario, pressing = "(loading)", 0
local function note(...) print(table.concat({ ... }, "\t")) end
-- A value as text, a table's keys in order, so the same thing always reads the same
local function show(v)
    if type(v) == "function" then return "function" end
    if type(v) ~= "table" then return tostring(v) end
    if rawget(v, "shown") then return v.shown end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
    return "{" .. table.concat(parts, ", ") .. "}"
end
local function shownArgs(...)
    local args = {}
    for i = 1, select("#", ...) do args[i] = show((select(i, ...))) end
    return table.concat(args, ", ")
end
local function did(what) note("CALL", scenario, tostring(pressing), what) end

-- hl.dsp.window.move({ … }) and the like: each is kept as its name and what it was given
local function dispatcher(path)
    return setmetatable({}, {
        __index = function(_, name) return dispatcher(path == "" and name or (path .. "." .. name)) end,
        __call = function(_, ...) return { shown = path .. "(" .. shownArgs(...) .. ")" } end,
    })
end

-- What's on screen, set by each scenario
local now = {}
local function window()
    if now.window == false then return nil end
    local id = now.onLast and 2 or 1
    return { address = "0xabc", floating = now.floating ~= false, mapped = true, workspace = { id = id, name = tostring(id) } }
end
local function workspaces()
    return { { id = 1, name = "1", windows = 1, monitor = { name = "DP-1" } },
             { id = 2, name = "2", windows = (now.onLast or now.nextBusy) and 1 or 0, monitor = { name = "DP-1" } } }
end

local binds, events, submap = {}, {}, ""
hl = setmetatable({
    bind = function(keys, action, opts)
        local flags, description = {}, ""
        for k, v in pairs(opts or {}) do
            if k == "description" then description = v else flags[k] = v end
        end
        binds[#binds + 1] = { keys = keys, action = action, submap = submap }
        note("BIND", tostring(#binds), submap, keys, show(flags), description, show(action))
    end,
    dispatch = function(d)
        did("dispatch " .. show(d))
        if type(d) == "function" then d() end
    end,
    exec_cmd = function(cmd) did("exec " .. tostring(cmd)) end,
    dsp = dispatcher(""),
    on = function(event, fn) note("ON", event); events[#events + 1] = { event = event, fn = fn } end,
    config = function(settings) did("config " .. show(settings)) end,
    get_config = function() return 1.0 end,
    define_submap = function(name, fn, fn2) submap = name; (fn2 or fn)(); submap = "" end,
    -- (timers fire straight away, so what they'd do later is pressed too; except in the
    -- scenarios that are there for what a quick tap does before its timer runs out)
    timer = function(fn, opts)
        did("timer " .. show(opts))
        if not now.timersWait then fn() end
        return { set_enabled = function() end }
    end,
    get_layers = function(which)
        local open = now.open == "all" or (which and now.open == which.namespace)
        return open and { { mapped = true, keyboard_interactivity = 1 } } or {}
    end,
    get_windows = function() return { window() } end,
    get_active_window = window,
    get_workspaces = workspaces,
    get_active_workspace = function() return workspaces()[now.onLast and 2 or 1] end,
    get_active_special_workspace = function() return now.special and { name = "special:special" } or nil end,
}, { __index = function(_, name) return function(...) did("hl." .. name .. "(" .. shownArgs(...) .. ")") end end })

-- What hyprland.lua, colors.lua and variables.lua set before binds.lua loads
SLATE_DIR = os.getenv("STUB_SLATE_DIR")
SLATE = SLATE_DIR .. "/bin/slate"
BORDER_SIZE, ACTIVE_BORDER, RESIZE_BORDER = 3, "the active border", "the resize border"
TERMINAL, FILE_MANAGER, EDITOR, CALCULATOR = "foot", "nautilus", "gedit", "gnome-calculator"
MONITOR1, MONITOR2, MONITOR3, NUM_WPM = "DP-1", "DP-2", "DP-3", 3
-- The functions the rest of Slate's config makes (found by the test: STUB_GLOBALS)
for name in os.getenv("STUB_GLOBALS"):gmatch("%S+") do
    _G[name] = function(...) did(name .. "(" .. shownArgs(...) .. ")"); return 1 end
end
-- (the focused workspace's window mode, windowrules.lua: asked for, nothing done)
activeMode = function() return now.mode or "tiling" end

dofile(os.getenv("STUB_CONFIG"))

local function pressAll(name, state)
    scenario, now = name, state
    SLATE_TITLEBARS, WRAP_WORKSPACES = state.titlebars, state.wrap
    for n, b in ipairs(binds) do
        pressing = n
        local ok, err = pcall(function()
            if type(b.action) == "function" then b.action() else hl.dispatch(b.action) end
        end)
        if not ok then note("ERR", scenario, tostring(n), tostring(err)) end
    end
end
for line in os.getenv("STUB_SCENARIOS"):gmatch("[^\n]+") do
    local name, settings = line:match("^(.-)\t(.*)$")
    pressAll(name, (loadstring or load)("return {" .. settings .. "}")())
end
-- Hyprland's events binds.lua waits for: a submap entered and left, and a window closing
scenario, pressing, now = "(events)", 0, {}
for _, e in ipairs(events) do
    for _, with in ipairs(e.event == "keybinds.submap" and { "resize", "" } or { window() }) do
        local ok, err = pcall(e.fn, with)
        if not ok then note("ERR", scenario, e.event, tostring(err)) end
    end
end
"""

# What's on screen for each press of everything: its name, then the stand-in's settings (as
# Lua). The first two are the plain cases the older tests here look at
PLAIN, OPEN = "nothing open", "everything open"
SCENARIOS = (
    (PLAIN, ""),
    (OPEN, 'open = "all", titlebars = true'),
    ("the launcher open", 'open = "slate-launcher"'),
    ("the window switcher open", 'open = "slate-switcher"'),
    ("the wallpaper switcher open", 'open = "slate-wallpaper-switcher"'),
    ("the overview open", 'open = "slate-overview"'),
    ("Nova open", 'open = "slate-assistant"'),
    ("a quick tap", "timersWait = true"),
    ("a quick tap with Nova open", 'timersWait = true, open = "slate-assistant"'),
    ("a tiled window with Slate's title bars", "floating = false, titlebars = true"),
    ("no window", "window = false"),
    ("the secret workspace showing", "special = true"),
    ("the secret workspace and the overview", 'special = true, open = "slate-overview"'),
    ("Side Stack", 'mode = "master"'),
    ("Scrolling", 'mode = "scrolling"'),
    ("Stacking", 'mode = "monocle"'),
    ("windows on the next workspace", "nextBusy = true"),
    ("on the last workspace", "onLast = true"),
    ("on the last workspace, no wrapping", "onLast = true, wrap = false"),
)


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

    def load(self, keyset):
        """Load binds.lua with this key set and press everything in every scenario: the
        stand-in's lines, split at their tabs."""
        with open(os.path.join(self.state, "slate", "keyset.lua"), "w") as f:
            f.write(f'KEYSET = "{keyset}"\n')
        env = dict(self.h.env, XDG_STATE_HOME=self.state, STUB_CONFIG=BINDS, STUB_SLATE_DIR=slate.SHELL,
                   STUB_GLOBALS=" ".join(other_config_functions()),
                   STUB_SCENARIOS="\n".join(f"{name}\t{settings}" for name, settings in SCENARIOS))
        env.pop("UWSM_FINALIZE_VARNAMES", None)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        return [line.split("\t") for line in out.splitlines()]

    def press_all(self, keyset):
        """Load binds.lua with this key set and press everything: (keys bound, {keys: commands
        started, with nothing open and then with everything open}, [failures])."""
        bound, keys_of, started, failed = [], {}, {}, []
        for kind, *rest in self.load(keyset):
            if kind == "BIND":
                n, submap, keys = rest[:3]
                keys_of[n] = keys
                if not submap:
                    bound.append(keys)
            elif kind == "CALL":
                scenario, n, what = rest
                command = re.match(r"exec (.*)$|dispatch exec_cmd\((.*)\)$", what)
                if command and scenario in (PLAIN, OPEN):
                    started.setdefault(keys_of[n], []).append(command.group(1) or command.group(2))
            elif kind == "ERR":
                scenario, n, what = rest
                failed.append(f"{keys_of.get(n, n)} ({scenario}): {what}")
        return bound, started, failed

    def shortcuts(self, keyset):
        """This key set's shortcuts (outside the submaps) by their keys: for each, a list, in
        the order they were made, of (description, what it does). What it does is its flags,
        what was bound, and everything pressing it did in each scenario."""
        made, did, by_keys = {}, {}, {}
        for kind, *rest in self.load(keyset):
            if kind == "BIND":
                made[rest[0]] = rest[1:]
            elif kind in ("CALL", "ERR") and rest[1] in made:
                did.setdefault(rest[1], []).append((kind, rest[0], rest[2]))
        for n, (submap, keys, flags, description, action) in made.items():
            if not submap:
                by_keys.setdefault(keys, []).append((description, (flags, action, tuple(did.get(n, ())))))
        return by_keys

    def test_every_shortcut_can_be_pressed(self):
        """No shortcut, in any key set, calls something that key set doesn't have."""
        for keyset in KEYSETS:
            with self.subTest(keyset=keyset):
                bound, _, failed = self.press_all(keyset)
                self.assertGreater(len(bound), 30, "the binds weren't made")
                self.assertEqual(failed, [])

    def test_a_shortcut_in_two_sets_does_the_same_in_both(self):
        """Hyprland + Slate Extras is Hyprland's shortcuts plus Slate's on the keys they leave
        free: what a shared shortcut does is written once in binds.lua, and this keeps a
        copy from drifting (Super+D once did nothing in the Extras)."""
        slates, hyprlands, extras = (self.shortcuts(k) for k in KEYSETS)
        # Slate's switchers also listen to these three in the Extras
        also_drive_switchers = {"SUPER + Left", "SUPER + Right", "SUPER + Up"}
        # Shortcuts that sit on another key in the Extras, because Hyprland's set uses this one
        moved = {"SUPER + SHIFT + V": "SUPER + V", "SUPER + SHIFT + P": "SUPER + P",
                 "SUPER + CONTROL + Down": "SUPER + Down"}
        for keys, binds in hyprlands.items():
            if keys not in also_drive_switchers:
                self.assertEqual(extras.get(keys), binds, f"{keys}: Hyprland's own, changed in the Extras")
        # The keypad zoom keys are given a number-key description, a different wrong one in each
        # set (a known bug in the description lookup, not in what the keys do): compare only
        # what they do.
        keypad = {"SUPER + code:82", "SUPER + code:86"}
        what = lambda keys, binds: [b[1] for b in binds] if keys in keypad else binds
        slates_in_extras = 0
        for keys, binds in extras.items():
            if keys in hyprlands:
                continue
            slate_keys = moved.get(keys, keys)
            self.assertIn(slate_keys, slates, f"{keys}: in the Extras but not in Slate's set")
            if keys in moved:
                self.assertIn(slate_keys, hyprlands, f"{keys}: moved, but its place isn't Hyprland's")
            self.assertEqual(what(keys, binds), what(keys, slates[slate_keys]), f"{keys}: differs from Slate's set")
            slates_in_extras += 1
        self.assertGreater(slates_in_extras, 25)

    def test_super_d_maximises_in_slates_set_and_the_extras(self):
        for keyset, there in (("slate", True), ("hyprland-extras", True), ("hyprland", False)):
            with self.subTest(keyset=keyset):
                bound, started, failed = self.press_all(keyset)
                self.assertEqual("SUPER + D" in bound, there)
                self.assertEqual([f for f in failed if f.startswith("SUPER + D ")], [])
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
