-- Monitors: https://wiki.hypr.land/Configuring/Basics/Monitors/
-- By default the first monitor uses its preferred mode and scale. To name your monitors,
-- set MONITOR1… in ~/.config/slate/hypr/variables.lua (`hyprctl monitors` lists them);
-- for a specific mode, position or scale, use Settings → Displays, or add hl.monitor() to
-- ~/.config/slate/hypr/monitors.lua, for example:
--   hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = "1" })

hl.monitor({
    output    = MONITOR1,
    mode      = "preferred",
    position  = "auto",
    scale     = "auto",
})

-- Settings → Displays: Slate saves each monitor's mode, position, scale and rotation here
-- (by its description, so they follow the monitor between ports)
do
    local stateHome = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
    local path = stateHome .. "/slate/displays.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, path)
        if not ok then print("[slate] error in " .. path .. ": " .. tostring(err)) end
    end
end
