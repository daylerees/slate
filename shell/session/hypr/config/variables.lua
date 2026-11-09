-- Default apps, monitors and workspaces for the Slate session. Each one keeps a value
-- already set in ~/.config/slate/hypr/variables.lua (made for you, with instructions), so
-- change them there.

-- Terminals' window classes (a pattern): they're never made see-through by Slate, as they have
-- their own transparency (windowrules.lua), and they "swallow" apps started from them (misc.lua)
TERMINAL_CLASSES = "kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal"

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
TERMINAL     = TERMINAL     or firstInstalled({ "kitty", "foot", "alacritty", "ghostty", "wezterm", "konsole",
                                                "gnome-terminal", "kgx", "ptyxis", "xfce4-terminal" })                  -- Super+Return
FILE_MANAGER = FILE_MANAGER or firstInstalled({ "dolphin", "nautilus", "thunar", "nemo", "pcmanfm-qt", "pcmanfm", "caja" })  -- Super+E
BROWSER      = BROWSER      or firstInstalled({ "firefox", "chromium", "google-chrome-stable", "brave", "librewolf", "epiphany" })
EDITOR       = EDITOR       or firstInstalled({ "gnome-text-editor --new-window", "kate", "kwrite", "mousepad", "gedit",
                                                "xed", "pluma", "code" })                                               -- Super+T
CALCULATOR   = CALCULATOR   or firstInstalled({ "gnome-calculator", "kcalc", "qalculate-gtk", "galculator", "mate-calc" })  -- Super+C

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
