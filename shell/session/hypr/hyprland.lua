-- Hyprland config for the Slate session (picked as "Slate" on the login screen and
-- started by slate-session). It is separate from ~/.config/hypr, so your normal
-- Hyprland session is left alone.
--
-- Your own settings go in ~/.config/slate/hypr/, which this never overwrites. Slate creates
-- each file with instructions in it (scripts/user-files.sh) and reloads this config when
-- you save one (UserFiles.qml). In the order they load:
--   env.lua         first: environment variables for apps
--   variables.lua   default apps, monitor names, cursor (Slate's config uses these)
--   … Slate's own config …
--   monitors.lua    monitor modes and positions (after Settings → Displays)
--   binds.lua       keyboard shortcuts
--   rules.lua       window and workspace rules
--   autostart.lua   commands to run at login
--   hyprland.lua    last: anything else; wins over everything above
-- A mistake in one is skipped (the rest still loads) and noted in
-- $XDG_RUNTIME_DIR/slate-hypr-errors.txt, which Slate shows in a notification.

hl.env("SLATE_SESSION", "1")
-- Where Slate lives, and its `slate` command (used by autostart.lua and binds.lua)
SLATE_DIR = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/slate"
SLATE = SLATE_DIR .. "/bin/slate"

local userDir = SLATE_DIR .. "/hypr"         -- your own files (see the top of this file)
-- Mistakes in them, for Slate to show (started empty on each load of the config)
local errorsPath = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/slate-hypr-errors.txt"
do local e = io.open(errorsPath, "w"); if e then e:close() end end
local function userFile(name)
    local path = userDir .. "/" .. name
    local f = io.open(path, "r")
    if not f then return end
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then
        print("[slate] error in " .. path .. ": " .. tostring(err))
        local e = io.open(errorsPath, "a")
        if e then e:write(name .. ": " .. tostring(err) .. "\n"); e:close() end
    end
end

userFile("env.lua")
userFile("variables.lua")

require("config.colors")
require("config.variables")
require("config.animations")
require("config.autostart")
require("config.decorations")
require("config.hyprbars")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.monitors")
require("config.windowrules")
require("config.workspaces")
require("config.slate")         -- settings made in Slate's Settings window (slateApply)

userFile("monitors.lua")
userFile("binds.lua")
userFile("rules.lua")
userFile("autostart.lua")
userFile("hyprland.lua")
