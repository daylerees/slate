-- Hyprland config for the Slate session (picked as "Slate" on the login screen and
-- started by slate-session). It is separate from ~/.config/hypr, so your normal
-- Hyprland session is left alone.
--
-- Personal settings go in two optional files, which this never overwrites:
--   ~/.config/slate/hypr/variables.lua   loaded first: TERMINAL, BROWSER, MONITOR1…
--   ~/.config/slate/hypr/hyprland.lua    loaded last: keyboard layout, monitors, extra
--                                        binds, startup apps; overrides anything here

hl.env("SLATE_SESSION", "1")
-- Where Slate lives, and its `slate` command (used by autostart.lua and binds.lua)
SLATE_DIR = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/slate"
SLATE = SLATE_DIR .. "/bin/slate"

local userDir = SLATE_DIR .. "/hypr"         -- your own files (see the top of this file)
local function userFile(name)
    local path = userDir .. "/" .. name
    local f = io.open(path, "r")
    if not f then return end
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then print("[slate] error in " .. path .. ": " .. tostring(err)) end
end

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

userFile("hyprland.lua")
