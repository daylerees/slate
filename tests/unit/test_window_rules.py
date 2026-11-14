"""session/hypr/config/windowrules.lua and variables.lua: which windows Slate's rules catch.
A rule written as "any class with calc in it" floated LibreOffice Calc at a sixth of the screen,
and the terminals were listed three ways, so some got what kitty got and some didn't. The config
is run under plain Lua with a stand-in for Hyprland's `hl` that notes every rule it's given;
the rules' patterns are then tried on windows' classes and titles here (Hyprland matches the
whole of a class or title, as re.fullmatch does)."""
import json
import os
import re

import slate
from slate import Case, run

CONFIG = slate.path("shell", "session", "hypr", "config")

# What each app offered in variables.lua calls its windows (their class): the command's name is
# often not it. An app added to a list there needs its classes here, and so in the patterns.
TERMINALS = {
    "kitty": ["kitty"],
    "foot": ["foot", "footclient"],
    "alacritty": ["Alacritty"],
    "ghostty": ["com.mitchellh.ghostty", "ghostty"],
    "wezterm": ["org.wezfurlong.wezterm"],
    "konsole": ["org.kde.konsole", "konsole"],
    "gnome-terminal": ["gnome-terminal-server", "org.gnome.Terminal"],
    "kgx": ["org.gnome.Console", "kgx"],
    "ptyxis": ["org.gnome.Ptyxis"],
    "xfce4-terminal": ["xfce4-terminal"],
}
CALCULATORS = {
    "gnome-calculator": ["org.gnome.Calculator", "gnome-calculator"],
    "kcalc": ["org.kde.kcalc", "kcalc"],
    "qalculate-gtk": ["qalculate-gtk", "io.github.Qalculate"],
    "galculator": ["galculator"],
    "mate-calc": ["mate-calc"],
}
# Windows that aren't calculators, terminals or video players, whatever their names contain
LIBREOFFICE = [("libreoffice-calc", "Untitled 1 — LibreOffice Calc"), ("libreoffice-calc", "budget.ods — LibreOffice Calc"),
               ("soffice", "LibreOffice Calc"), ("libreoffice-startcenter", "LibreOffice Start Center"),
               ("firefox", "LibreOffice Calc: the spreadsheet — Mozilla Firefox")]
NOT_TERMINALS = ["firefox", "footage", "org.gnome.TextEditor", "kitty-open", "org.kde.dolphin", "libreoffice-calc"]

# A stand-in `hl`: every window and layer rule it's handed is printed as a line of JSON, and
# anything else asked of it does nothing. Then the config files named in STUB_FILES are run,
# and the Lua in STUB_CHUNK (what Slate sends through `hyprctl eval`), if there is one.
STUB = r'''
local function json(v)
    local t = type(v)
    if t == "table" then
        local parts = {}
        if #v > 0 then
            for _, x in ipairs(v) do parts[#parts + 1] = json(x) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, x in pairs(v) do parts[#parts + 1] = json(tostring(k)) .. ":" .. json(x) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "string" then
        return '"' .. v:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    end
    return "null"
end
local anything
anything = setmetatable({}, { __index = function() return anything end, __call = function() return anything end })
local function rule(kind)
    return function(r)
        print("RULE " .. json({ kind = kind, rule = r }))
        return { set_enabled = function() end }
    end
end
hl = setmetatable({ window_rule = rule("window"), layer_rule = rule("layer") },
                  { __index = function() return anything end })
for file in (os.getenv("STUB_FILES") or ""):gmatch("[^:]+") do dofile(file) end
if os.getenv("STUB_FORGET_TERMINALS") == "1" then TERMINAL_CLASSES = nil end
local chunk = os.getenv("STUB_CHUNK")
if chunk then
    local f = assert(io.open(chunk)); local src = f:read("a"); f:close()
    assert(load(src))()
    assert(load(src))()       -- (Slate sends it again with every change of a setting)
end
print("TERMINAL_CLASSES=" .. tostring(TERMINAL_CLASSES))
'''


def offered(name):
    """The commands variables.lua offers as `name` (TERMINAL, CALCULATOR): their first words."""
    src = slate.read("shell", "session", "hypr", "config", "variables.lua")
    m = re.search(r"local " + name + r"S\s*=\s*\{(.*?)\}", src, re.S)
    assert m, f"variables.lua no longer offers a list for {name}"
    return [c.split()[0] for c in re.findall(r'"([^"]+)"', m.group(1))]


def fits(pattern, text):
    """Does Hyprland's pattern match this class or title? ("negative:" turns it round.)"""
    if pattern.startswith("negative:"):
        return not re.fullmatch(pattern[len("negative:"):], text)
    return bool(re.fullmatch(pattern, text))


def catches(rule, cls, title):
    """Would this rule apply to a window as it opens, tiled, with this class and title? Rules
    that also ask for something such a window hasn't got (floating already, a workspace, a
    tag, being a game) don't."""
    match = rule.get("match", {})
    for key, want in match.items():
        if key == "class":
            if not fits(want, cls):
                return False
        elif key in ("title", "initial_title"):
            if not fits(want, title):
                return False
        else:
            return False
    return bool(match)


class WindowRules(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "lua5.4")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)
        self.env = dict(self.h.env, XDG_STATE_HOME=os.path.join(self.h.dir, "state"))

    def load(self, *files, chunk=None, forget_terminals=False):
        """Run these config files (and then `chunk`): the rules made, and TERMINAL_CLASSES."""
        env = dict(self.env, STUB_FILES=":".join(os.path.join(CONFIG, f) for f in files))
        if chunk is not None:
            env["STUB_CHUNK"] = os.path.join(self.h.dir, "chunk.lua")
            with open(env["STUB_CHUNK"], "w") as f:
                f.write(chunk)
        if forget_terminals:
            env["STUB_FORGET_TERMINALS"] = "1"
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        rules = [json.loads(l[5:]) for l in out.splitlines() if l.startswith("RULE ")]
        terminals = next(l.split("=", 1)[1] for l in out.splitlines() if l.startswith("TERMINAL_CLASSES="))
        return rules, terminals

    def window_rules(self):
        rules, _ = self.load("variables.lua", "windowrules.lua")
        return [r["rule"] for r in rules if r["kind"] == "window"]

    # ---- calculators -------------------------------------------------------------------

    def test_libreoffice_calc_isnt_floated(self):
        """A spreadsheet isn't a calculator: no rule floats or resizes LibreOffice Calc."""
        rules = self.window_rules()
        for cls, title in LIBREOFFICE:
            for r in rules:
                if catches(r, cls, title) and (r.get("float") or "size" in r):
                    self.fail(f"{cls} ({title}) is floated or resized by the rule matching {r['match']}")

    def test_offered_calculators_float(self):
        """Every calculator offered as CALCULATOR opens small and floating."""
        rules = self.window_rules()
        for cmd in offered("CALCULATOR"):
            self.assertIn(cmd, CALCULATORS, f"{cmd} is offered as a calculator: say here what its windows' class is")
            for cls in CALCULATORS[cmd]:
                with self.subTest(cls):
                    got = [r for r in rules if catches(r, cls, "Calculator") and r.get("float") and "size" in r]
                    self.assertTrue(got, f"{cls} ({cmd}) no longer opens small and floating")

    # ---- terminals ---------------------------------------------------------------------

    def test_offered_terminals_are_terminals(self):
        """Every terminal offered as TERMINAL is in TERMINAL_CLASSES by its windows' class, so
        it's left fully opaque, swallows what it starts, and is made solid in game mode."""
        _, classes = self.load("variables.lua")
        for cmd in offered("TERMINAL"):
            self.assertIn(cmd, TERMINALS, f"{cmd} is offered as a terminal: say here what its windows' class is")
            for cls in TERMINALS[cmd]:
                with self.subTest(cls):
                    self.assertTrue(re.fullmatch("(" + classes + ")", cls), f"{cls} ({cmd}) isn't in TERMINAL_CLASSES")
        for cls in NOT_TERMINALS:
            with self.subTest(cls):
                self.assertFalse(re.fullmatch("(" + classes + ")", cls), f"{cls} counts as a terminal")

    def test_terminals_stay_opaque(self):
        """The rule that keeps terminals fully opaque is made from TERMINAL_CLASSES."""
        rules = self.window_rules()
        for cmd, classes in TERMINALS.items():
            for cls in classes:
                with self.subTest(cls):
                    self.assertTrue([r for r in rules if catches(r, cls, "~") and r.get("opacity") == "1.0 override"],
                                    f"{cls} gets Slate's window opacity on top of its own")

    def test_swallowing_uses_the_list(self):
        misc = slate.read("shell", "session", "hypr", "config", "misc.lua")
        self.assertRegex(misc, r'swallow_regex\s*=\s*"\("\s*\.\.\s*TERMINAL_CLASSES\s*\.\.\s*"\)"')

    def game_opaque_lua(self):
        """The Lua Slate sends for game mode's solid terminals (Config.qml's hyprSettings),
        with game mode on."""
        lines = [l for l in slate.read("shell", "Config.qml").splitlines()
                 if "SLATE_GAME_OPAQUE" in l and not l.strip().startswith("//")]
        self.assertTrue(lines, "Config.qml no longer makes the slate-game-opaque rule")
        lua = "".join(part for l in lines for part in re.findall(r"`([^`]*)`", l))
        return re.sub(r"\$\{gameMode[^}]*\}", "true", lua)

    def test_game_mode_uses_the_list(self):
        """Game mode's rule for solid terminals is built from TERMINAL_CLASSES, in Lua, rather
        than from a list of Slate's own (it had a longer one than the session's)."""
        lua = self.game_opaque_lua()
        self.assertNotIn("${", lua, "something else is put into this Lua now: fill it in here")
        self.assertIn("TERMINAL_CLASSES", lua)
        for word in ("kitty", "konsole", "ghostty", "foot"):
            self.assertNotIn(word, lua, "Config.qml lists terminals itself again")
        rules, classes = self.load("variables.lua", chunk=lua)
        made = [r["rule"] for r in rules if r["rule"].get("name") == "slate-game-opaque"]
        self.assertEqual(len(made), 1, "the rule is made once, however often the settings are sent")
        self.assertEqual(made[0]["match"], {"class": "^(" + classes + ")$"})
        self.assertIs(made[0].get("force_rgbx"), True)

    def test_game_mode_without_the_session(self):
        """Under a Hyprland config that isn't Slate's (no TERMINAL_CLASSES), the Lua Slate sends
        still runs: an error there would stop every setting after it arriving."""
        rules, classes = self.load("variables.lua", chunk=self.game_opaque_lua(), forget_terminals=True)
        self.assertEqual(classes, "nil")
        self.assertEqual([r for r in rules if r["rule"].get("name") == "slate-game-opaque"], [])

    # ---- other loose patterns ----------------------------------------------------------

    def test_video_players_by_name(self):
        """VLC and Plex stay fully opaque under each of their names; an app that only has
        "plex" or "vlc" inside its name doesn't count as one."""
        rules = self.window_rules()
        opaque = lambda cls: [r for r in rules if catches(r, cls, "~") and r.get("opacity") == "1.0 override"]
        for cls in ("mpv", "vlc", "org.videolan.VLC", "Plex", "plex", "tv.plex.PlexDesktop", "plexmediaplayer",
                    "com.plexamp.Plexamp", "org.kde.haruna", "org.kde.gwenview"):
            with self.subTest(cls):
                self.assertTrue(opaque(cls), f"{cls} isn't kept fully opaque")
        for cls in ("ai.perplexity.Perplexity", "perplexity", "complexity-viewer", "org.kdexharuna"):
            with self.subTest(cls):
                self.assertFalse(opaque(cls), f"{cls} is taken for a video player")

    # ---- layers ------------------------------------------------------------------------

    def test_layer_rules_name_slates_layers(self):
        """The layers named in the session's rules are the ones Slate makes: one that's gone
        (the dock's own menu) isn't still listed, and a new one isn't left out, which would
        have Hyprland fade it in and out on top of Slate's own animation."""
        made = set()
        for f in slate.files("shell", ".qml", skip=("shell/greeter",)):      # (the login screen has its own Hyprland)
            made.update(re.findall(r'WlrLayershell\.namespace:\s*"([^"]+)"', slate.read(f)))
        self.assertIn("slate-bar", made)
        rules, _ = self.load("variables.lua", "windowrules.lua")
        layer = {r["rule"]["name"]: r["rule"]["match"]["namespace"] for r in rules if r["kind"] == "layer"}
        named = {}
        for rule, pattern in layer.items():
            m = re.fullmatch(r"\^slate-\(([^()]*)\)\$", pattern)
            named[rule] = {"slate-" + n for n in m.group(1).split("|")} if m else {pattern.strip("^$")}
        for rule, names in named.items():
            for n in sorted(names - made):
                with self.subTest(rule=rule, layer=n):
                    self.fail(f"{n} is named in the {rule} rule, but Slate makes no such layer")
        for n in sorted(made - named.get("slate-overlays", set())):
            with self.subTest(layer=n):
                self.fail(f"{n} isn't in the slate-overlays rule: Hyprland adds its own fade to it")
