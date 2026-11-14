-- Default apps, monitors and workspaces for the Slate session. Each one keeps a value
-- already set in ~/.config/slate/hypr/variables.lua (made for you, with instructions), so
-- change them there.

-- Terminals' window classes (a pattern), the one list of them: they're never made see-through by
-- Slate, as they have their own transparency (windowrules.lua), they "swallow" apps started from
-- them (misc.lua), and game mode makes them solid (Slate's Config.qml builds its rule from this).
-- Every terminal offered as TERMINAL below is here, under the class its windows really have
-- (often not the command's name: Ghostty's is com.mitchellh.ghostty), and a few more besides.
-- A terminal added below is added here too (tests/unit/test_window_rules.py checks).
TERMINAL_CLASSES = table.concat({
    "kitty",
    "foot|footclient",
    "[Aa]lacritty",
    "com\\.mitchellh\\.ghostty|ghostty",
    "org\\.wezfurlong\\.wezterm",
    "org\\.kde\\.konsole|[Kk]onsole",
    "gnome-terminal|gnome-terminal-server|org\\.gnome\\.Terminal",
    "org\\.gnome\\.Console|kgx",
    "org\\.gnome\\.Ptyxis",
    "xfce[0-9]?-terminal",
    "com\\.raggesilver\\.BlackBox",
}, "|")

-- Apps opened by the keyboard shortcuts in binds.lua: the first of each list that's installed
-- (found on PATH here, without starting a shell), else the first. Settings → Default Apps
-- picks yours on top of these.
local function installed(cmd)
    local bin = cmd:match("^(%S+)")
    for dir in (os.getenv("PATH") or "/usr/bin"):gmatch("[^:]+") do
        local f = io.open(dir .. "/" .. bin, "r")
        if f then f:close(); return true end
    end
    return false
end
local function firstInstalled(list)
    for _, cmd in ipairs(list) do if installed(cmd) then return cmd end end
    return list[1]
end
local TERMINALS     = { "kitty", "foot", "alacritty", "ghostty", "wezterm", "konsole",
                       "gnome-terminal", "kgx", "ptyxis", "xfce4-terminal" }
local FILE_MANAGERS = { "dolphin", "nautilus", "thunar", "nemo", "pcmanfm-qt", "pcmanfm", "caja" }
local BROWSERS      = { "firefox", "chromium", "google-chrome-stable", "brave", "librewolf", "epiphany" }
local EDITORS       = { "gnome-text-editor --new-window", "kate", "kwrite", "mousepad", "gedit", "xed", "pluma", "code" }
local CALCULATORS   = { "gnome-calculator", "kcalc", "qalculate-gtk", "galculator", "mate-calc" }
TERMINAL     = TERMINAL     or firstInstalled(TERMINALS)       -- Super+Return
FILE_MANAGER = FILE_MANAGER or firstInstalled(FILE_MANAGERS)   -- Super+E
BROWSER      = BROWSER      or firstInstalled(BROWSERS)
EDITOR       = EDITOR       or firstInstalled(EDITORS)         -- Super+T
CALCULATOR   = CALCULATOR   or firstInstalled(CALCULATORS)     -- Super+C

-- The programs Slate itself offers above, by command name. binds.lua checks one is installed
-- before starting it (and says what's missing when it isn't), but only for these: a default app
-- you wrote yourself is a command line of your own, which Slate leaves alone.
KNOWN_APPS = {}
for _, list in ipairs({ TERMINALS, FILE_MANAGERS, BROWSERS, EDITORS, CALCULATORS }) do
    for _, cmd in ipairs(list) do KNOWN_APPS[cmd:match("^(%S+)")] = true end
end

-- How each terminal is told "run this command line": what goes between the terminal and the
-- command, by the terminal's command name. Most take -e (the default); a few want something
-- else. TERMINAL_RUN is the one place that puts them together: the launcher's "> command", an
-- app that runs in a terminal, Nova's sign-in, the system monitor and Spaces all use it.
TERMINAL_RUN_FLAGS = {
    ["wezterm"]        = "start --",
    ["gnome-terminal"] = "--",
    ["ptyxis"]         = "--",
    ["xfce4-terminal"] = "-x",
}
-- TERMINAL_RUN("sh -c 'htop'") is the command line that opens the default terminal running it
function TERMINAL_RUN(args)
    local bin = ((TERMINAL or "kitty"):match("^(%S+)") or "kitty"):match("([^/]+)$")
    return (TERMINAL or "kitty") .. " " .. (TERMINAL_RUN_FLAGS[bin] or "-e") .. " " .. args
end

-- Monitors, by output name ("" = whichever monitor Hyprland finds; see `hyprctl monitors`)
MONITOR1 = MONITOR1 or ""
MONITOR2 = MONITOR2 or ""
MONITOR3 = MONITOR3 or ""
PRIMARY_MONITOR = PRIMARY_MONITOR or MONITOR1   -- where games and launchers open

-- How many workspaces per monitor get number-key shortcuts (up to 10)
NUM_WPM = NUM_WPM or 3

-- Mouse cursor: Slate Cursors ships with Slate (cursors/Slate-Cursors, Bibata Modern Ice
-- without colour). Hyprland and apps all use it; Slate's theme script sets it for GTK,
-- Qt/KDE and X11 apps too
CURSOR_THEME = CURSOR_THEME or "Slate-Cursors"
CURSOR_SIZE  = CURSOR_SIZE  or 20
hl.env("XCURSOR_THEME", CURSOR_THEME)
hl.env("XCURSOR_SIZE", tostring(CURSOR_SIZE))
hl.env("HYPRCURSOR_THEME", CURSOR_THEME)
hl.env("HYPRCURSOR_SIZE", tostring(CURSOR_SIZE))

-- fzf in Slate's colours (Settings → Appearance → App Theming writes this file, and empties
-- it when fzf's theming is off). Your own FZF_DEFAULT_OPTS still apply on top.
local fzfOpts = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/slate/fzf/slate.opts"
local fzfFile = io.open(fzfOpts, "a")
if not fzfFile then
    -- Its folder isn't there yet: make it (only then, as it starts a shell while Hyprland loads)
    os.execute("mkdir -p '" .. fzfOpts:match("^(.*)/") .. "'")
    fzfFile = io.open(fzfOpts, "a")
end
if fzfFile then fzfFile:close(); hl.env("FZF_DEFAULT_OPTS_FILE", fzfOpts) end
