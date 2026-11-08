-- Keyboard and mouse shortcuts for the Slate session.
-- Sections: helpers · windows · launching apps · hardware keys · utilities ·
-- workspaces & monitors. Many shortcuts talk to Slate via `slate ipc call …` (see
-- `slate ipc show` for everything it accepts). Add or override shortcuts in
-- ~/.config/slate/hypr/binds.lua; it's loaded after this file.
--
-- Three sets to choose from (Settings → Shortcuts): Slate's own (the default), Hyprland's
-- default shortcuts, or Hyprland's with Slate's added on the keys they leave free. Each
-- part below says which sets it's in; the hardware keys and mouse are in all of them.

-----------------
---- HELPERS ----
-----------------

local mainMod = "SUPER"

-- Which set (Settings → Shortcuts). Slate saves it in ~/.local/state/slate/keyset.lua and
-- reloads this config when you change it:
--   "slate"            Slate's own shortcuts
--   "hyprland"         Hyprland's default shortcuts (as in its example config)
--   "hyprland-extras"  Hyprland's defaults, plus Slate's shortcuts on keys they leave free
KEYSET = "slate"
do
    local path = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/slate/keyset.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, path)
        if not ok then print("[slate] error in " .. path .. ": " .. tostring(err)) end
    end
end
local SLATE_KEYS = KEYSET ~= "hyprland" and KEYSET ~= "hyprland-extras"
local HYPR_KEYS = not SLATE_KEYS
local EXTRAS = KEYSET == "hyprland-extras"


-- What each shortcut does, shown in Settings → Shortcuts ("Group: what it does"). Looked
-- up by the exact keys given to hl.bind below, and only for the shortcuts in this file:
-- one of your own (in ~/.config/slate/hypr/hyprland.lua) on the same keys doesn't take
-- Slate's description; give it its own with { description = "Group: what it does" }.
local inSlateBinds = true
local SHORTCUT_DESCRIPTIONS = {
    ["SUPER + SUPER_L"]            = "Apps: Tap Super on its own: the app launcher",
    ["SUPER + Space"]              = "Apps: The app launcher",
    ["SUPER + Return"]             = "Apps: A terminal",
    ["SUPER + E"]                  = "Apps: Files",
    ["SUPER + T"]                  = "Apps: Text editor",
    ["SUPER + C"]                  = "Apps: Calculator",
    ["CONTROL + SHIFT + Escape"]   = "Apps: System monitor (btop)",
    ["SUPER + Z"]                  = "Slate: Settings",
    ["SUPER + X"]                  = "Slate: Control centre",
    ["SUPER + A"]                  = "Slate: Notifications",
    ["SUPER + ALT + C"]            = "Slate: Power menu",
    ["SUPER + L"]                  = "Slate: Lock the screen",
    ["SUPER + V"]                  = "Slate: Clipboard history",
    ["SUPER + period"]             = "Slate: Emoji",
    ["SUPER + SHIFT + W"]          = "Slate: Change the wallpaper",
    ["SUPER + P"]                  = "Slate: Pick a colour from the screen (copied)",
    ["Print"]                      = "Slate: Screenshot of an area",
    ["SUPER + Print"]              = "Slate: Screenshot of the screen",
    ["SUPER + Minus"]              = "Slate: Zoom out",
    ["SUPER + Plus"]               = "Slate: Zoom in",
    ["SUPER + Q"]                  = "Windows: Close the window",
    ["SUPER + Escape"]             = "Windows: Force-quit an app (click its window)",
    ["SUPER + Tab"]                = "Windows: Switch windows (hold Super)",
    ["ALT + Tab"]                  = "Windows: Next window",
    ["SUPER + ALT + Space"]        = "Windows: Float or tile the window",
    ["SUPER + D"]                  = "Windows: Maximise",
    ["SUPER + F"]                  = "Windows: Full screen",
    ["SUPER + J"]                  = "Windows: Split the other way",
    ["SUPER + R"]                  = "Windows: Resize with the arrow keys",
    ["SUPER + ALT + Left"]         = "Windows: Focus the window to the left",
    ["SUPER + ALT + Right"]        = "Windows: Focus the window to the right",
    ["SUPER + ALT + Up"]           = "Windows: Focus the window above",
    ["SUPER + ALT + Down"]         = "Windows: Focus the window below",
    ["SUPER + SHIFT + Left"]       = "Windows: Move the window left",
    ["SUPER + SHIFT + Right"]      = "Windows: Move the window right",
    ["SUPER + SHIFT + Up"]         = "Windows: Move the window up",
    ["SUPER + SHIFT + Down"]       = "Windows: Move the window down",
    ["SUPER + mouse:272"]          = "Windows: Move a window (drag)",
    ["SUPER + mouse:273"]          = "Windows: Resize a window (right-drag)",
    ["SUPER + W"]                  = "Workspaces: Move the window to a new workspace at the end",
    ["SUPER + CONTROL + Right"]    = "Workspaces: Move the window to the next workspace",
    ["SUPER + CONTROL + Left"]     = "Workspaces: Move the window to the previous workspace",
    ["SUPER + Right"]              = "Workspaces: Next workspace",
    ["SUPER + Left"]               = "Workspaces: Previous workspace",
    ["SUPER + Down"]               = "Workspaces: Workspace overview",
    ["SUPER + Up"]                 = "Workspaces: Show or hide the secret workspace",
    ["SUPER + S"]                  = "Workspaces: Show or hide the secret workspace",
    ["SUPER + SHIFT + S"]          = "Workspaces: Move the window to the secret workspace",
}
-- Hyprland's default shortcuts (the "Hyprland Defaults" and "Hyprland + Slate Extras" sets)
local HYPRLAND_DESCRIPTIONS = {
    ["SUPER + Q"]                  = "Apps: A terminal",
    ["SUPER + E"]                  = "Apps: Files",
    ["SUPER + R"]                  = "Apps: The app launcher",
    ["SUPER + C"]                  = "Windows: Close the window",
    ["SUPER + V"]                  = "Windows: Float or tile the window",
    ["SUPER + P"]                  = "Windows: Pseudo-tile the window",
    ["SUPER + J"]                  = "Windows: Split the other way",
    ["SUPER + Left"]               = "Windows: Focus the window to the left",
    ["SUPER + Right"]              = "Windows: Focus the window to the right",
    ["SUPER + Up"]                 = "Windows: Focus the window above",
    ["SUPER + Down"]               = "Windows: Focus the window below",
    ["SUPER + M"]                  = "Slate: Log out (asks first)",
    ["SUPER + S"]                  = "Workspaces: Show or hide the secret workspace",
    ["SUPER + SHIFT + S"]          = "Workspaces: Move the window to the secret workspace",
    ["SUPER + mouse_down"]         = "Workspaces: Next workspace",
    ["SUPER + mouse_up"]           = "Workspaces: Previous workspace",
    ["SUPER + mouse:272"]          = "Windows: Move a window (drag)",
    ["SUPER + mouse:273"]          = "Windows: Resize a window (right-drag)",
}
-- Slate's shortcuts that move to other keys in "Hyprland + Slate Extras" (theirs are taken)
local EXTRA_DESCRIPTIONS = {
    ["SUPER + SHIFT + V"]          = "Slate: Clipboard history",
    ["SUPER + SHIFT + P"]          = "Slate: Pick a colour from the screen (copied)",
    ["SUPER + CONTROL + Down"]     = "Workspaces: Workspace overview",
}
-- The descriptions for the set in use; the number-key ones are worked out from the keys
local DESCRIPTIONS, DIGIT_DESCRIPTIONS
if SLATE_KEYS then
    DESCRIPTIONS = SHORTCUT_DESCRIPTIONS
    DIGIT_DESCRIPTIONS = {
        ["SUPER + ALT"]             = "Workspaces: Go to workspace %d",
        ["SUPER + CONTROL"]         = "Workspaces: Go to this monitor's workspace %d",
        ["SUPER + SHIFT + CONTROL"] = "Workspaces: Move the window to this monitor's workspace %d",
        ["SUPER + SHIFT + ALT"]     = "Workspaces: Send the window to this monitor's workspace %d (staying here)",
        ["SUPER"]                   = "Monitors: Focus monitor %d",
        ["SUPER + SHIFT"]           = "Monitors: Move the window to monitor %d",
    }
else
    DESCRIPTIONS = {}
    if EXTRAS then
        for k, v in pairs(SHORTCUT_DESCRIPTIONS) do DESCRIPTIONS[k] = v end
        for k, v in pairs(EXTRA_DESCRIPTIONS) do DESCRIPTIONS[k] = v end
    end
    for k, v in pairs(HYPRLAND_DESCRIPTIONS) do DESCRIPTIONS[k] = v end
    DIGIT_DESCRIPTIONS = {
        ["SUPER"]         = "Workspaces: Go to workspace %d",
        ["SUPER + SHIFT"] = "Workspaces: Move the window to workspace %d",
    }
end
-- A Slate command, e.g. slate("launcher toggle")
local function slate(args) return SLATE .. " ipc call " .. args end
-- Start apps through uwsm when the session runs under it, otherwise directly
local launchPrefix = os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or ""

-- Is one of Slate's overlays open and holding the keyboard? (by layer name, e.g. "slate-launcher")
local function slateOverlayOpen(name)
    for _, l in ipairs(hl.get_layers({ namespace = name }) or {}) do
        if l.mapped and (l.keyboard_interactivity or 0) > 0 then return true end
    end
    return false
end

-- Tap Super on its own to open the app launcher. Every Super shortcut below marks
-- the press as "used" (via this wrapper), so finishing a shortcut never opens it.
local superUsed = false
local superTap = false
local superTapTimer = nil
do
    local bind = hl.bind
    hl.bind = function(keys, action, opts)
        -- Its description for Settings → Shortcuts. The number-key ones are worked out from
        -- the keys (code:10 is the 1 key … code:19 the 0 key)
        local desc = inSlateBinds and DESCRIPTIONS[keys] or nil
        if inSlateBinds and not desc then
            local mods, code = keys:match("^(.-) %+ code:(%d+)$")
            local what = mods and DIGIT_DESCRIPTIONS[mods]
            if what then desc = string.format(what, tonumber(code) == 19 and 10 or tonumber(code) - 9) end
        end
        if desc and not (opts and opts.description) then
            opts = opts or {}
            opts.description = desc
        end
        local isSuperCombo = keys:find("^SUPER") and not keys:find("SUPER_L")
            and not keys:find("mouse:") and not (opts and opts.drag)
        if isSuperCombo then
            local inner = action
            action = function()
                superUsed = true
                if type(inner) == "function" then return inner() end
                return hl.dispatch(inner)
            end
        end
        return bind(keys, action, opts)
    end
end

-- While the workspace overview (Super+Down) is open, Super+arrows, Super+Shift+arrows and
-- Super+Return drive it instead of their usual actions
local function overviewIsOpen() return slateOverlayOpen("slate-overview") end
local function ov(cmd) hl.exec_cmd(slate("overview " .. cmd)) end

-- AZERTY fix: the number-row keys emit symbols (& é " ' ...) without Shift, so
-- binding to the digit characters fails. Bind by physical keycode instead.
-- Digit d -> evdev keycode: 1..9 => 10..18, 0 => 19
local function digitCode(d)
    return "code:" .. (d == 0 and 19 or (9 + d))
end

-----------------
---- WINDOWS ----
-----------------

-- Close the active window; if it was the last one on its workspace, jump back to the
-- previously focused workspace once it has actually closed (apps may cancel the close).
-- Matches on the closed window's address so helper windows (Electron) and apps that hide
-- to tray instead of exiting (Steam) still trigger it
local pendingClose = nil
local function otherWindowsOn(wsId, exceptAddr)
    local n = 0
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.address ~= exceptAddr and w.workspace and w.workspace.id == wsId then
            n = n + 1
        end
    end
    return n
end
function closeWindowSmart()
    local win = hl.get_active_window()
    pendingClose = nil
    if win and win.workspace and not tostring(win.workspace.name):find("^special")
        and otherWindowsOn(win.workspace.id, win.address) == 0 then
        pendingClose = { addr = win.address, ws = win.workspace.id }
    end
    hl.dispatch(hl.dsp.window.close())
end
hl.on("window.close", function(win)
    if not (pendingClose and win and win.address == pendingClose.addr) then return end
    local p = pendingClose
    pendingClose = nil
    local ws = hl.get_active_workspace()
    if ws and ws.id == p.ws and otherWindowsOn(p.ws, p.addr) == 0 then
        hl.dispatch(hl.dsp.focus({ workspace = "previous" }))
    end
end)

-- (Slate's set)
if SLATE_KEYS then
-- Window manipulation
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + Q",           function() closeWindowSmart() end)
hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + D",           hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + J",           hl.dsp.layout("togglesplit"))

-- Change focus
hl.bind(mainMod .. " + ALT + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + ALT + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + ALT + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + ALT + Down",  hl.dsp.focus({ direction = "down" }))
hl.bind("ALT + Tab",           hl.dsp.window.cycle_next())
end
-- (Slate's set, and Hyprland + Slate Extras)
if SLATE_KEYS or EXTRAS then
-- Window switcher (Slate): hold Super, press Tab / Shift+Tab, let go of Super to switch
hl.bind(mainMod .. " + Tab",           hl.dsp.exec_cmd(slate("switcher next")))
hl.bind(mainMod .. " + SHIFT + Tab",   hl.dsp.exec_cmd(slate("switcher prev")))
-- Super pressed: start a short "tap" window
hl.bind("SUPER_L", function()
    superUsed = false
    superTap = true
    if superTapTimer then superTapTimer:set_enabled(false) end
    superTapTimer = hl.timer(function() superTap = false; superTapTimer = nil end, { timeout = 350, type = "oneshot" })
end, { ignore_mods = true, non_consuming = true })
-- Super released: finish a window switch, or, if it was a quick tap on its own,
-- toggle the app launcher
hl.bind(mainMod .. " + SUPER_L", function()
    if slateOverlayOpen("slate-switcher") then
        hl.exec_cmd(slate("switcher commit"))
    elseif superTap and not superUsed and not slateOverlayOpen("slate-overview") then
        hl.exec_cmd(slate("launcher toggle"))
    end
    superTap = false
end, { release = true, non_consuming = true, ignore_mods = true })
end
-- (Slate's set)
if SLATE_KEYS then

-- Move active window around workspaces & monitors
hl.bind(mainMod .. " + SHIFT + Up",                   hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + Right", function()
    if overviewIsOpen() then ov("moveRight") else hl.dispatch(hl.dsp.window.move({ direction = "r" })) end
end)
hl.bind(mainMod .. " + SHIFT + Left", function()
    if overviewIsOpen() then ov("moveLeft") else hl.dispatch(hl.dsp.window.move({ direction = "l" })) end
end)
hl.bind(mainMod .. " + SHIFT + Down",                 hl.dsp.window.move({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + " .. digitCode(1),     hl.dsp.window.move({ monitor = MONITOR1 }))
hl.bind(mainMod .. " + SHIFT + " .. digitCode(2),     hl.dsp.window.move({ monitor = MONITOR2 }))
hl.bind(mainMod .. " + SHIFT + " .. digitCode(3),     hl.dsp.window.move({ monitor = MONITOR3 }))
hl.bind(mainMod .. " + SHIFT + mouse_up",             hl.dsp.window.move({ monitor   = "-1" }))
hl.bind(mainMod .. " + SHIFT + mouse_down",           hl.dsp.window.move({ monitor   = "+1" }))
hl.bind(mainMod .. " + CONTROL + Right",      hl.dsp.window.move({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + Left",       hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up",   hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }))
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + CONTROL + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i }))
end
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + ALT + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i, follow = false }))
end

end
-- Move & Resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())

-- (Slate's set)
if SLATE_KEYS then
-- Resize mode: SUPER + R, then arrows to resize; Escape, Return or SUPER + R to exit
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))
end
hl.define_submap("resize", function()
    hl.bind("Right", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })
    hl.bind("Left",  hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
    hl.bind("Down",  hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })
    hl.bind("Up",    hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
    hl.bind("Escape",            hl.dsp.submap("reset"))
    hl.bind("Return",            hl.dsp.submap("reset"))
    hl.bind(mainMod .. " + R",   hl.dsp.submap("reset"))
end)

-- Pink active border while in resize mode (at least 3px, even when borders are off)
hl.on("keybinds.submap", function(name)
    local resizing = name == "resize"
    local border = resizing and RESIZE_BORDER or ACTIVE_BORDER
    local size = resizing and math.max(BORDER_SIZE, 3) or BORDER_SIZE
    hl.config({ general = { border_size = size, col = { active_border = border } } })
end)

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
-- (Slate's set, and Hyprland + Slate Extras)
if SLATE_KEYS or EXTRAS then
hl.bind(mainMod .. " + Minus", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + Plus", function() zoomfunction(0.3) end, { repeating = true })

-- Zoom with the keypad's - and +
hl.bind(mainMod .. " + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind(mainMod .. " + code:86", function() zoomfunction(0.3) end, { repeating = true })


end
-- (Slate's set)
if SLATE_KEYS then
------------------------
---- LAUNCHING APPS ----
------------------------

-- Super+Enter: open a terminal, or, while the app launcher is open, open the
-- selected app on an empty workspace
hl.bind(mainMod .. " + Return", function()
    if overviewIsOpen() then ov("go"); return end
    if slateOverlayOpen("slate-launcher") then hl.exec_cmd(slate("launcher launchOnNewWorkspace")); return end
    hl.exec_cmd(launchPrefix .. TERMINAL)
end)
-- The apps are read when pressed, so Settings → Default apps applies straight away
hl.bind(mainMod .. " + E",          function() hl.exec_cmd(launchPrefix .. FILE_MANAGER) end)
hl.bind(mainMod .. " + T",          function() hl.exec_cmd(launchPrefix .. EDITOR) end)
hl.bind(mainMod .. " + C",          function() hl.exec_cmd(launchPrefix .. CALCULATOR) end)
hl.bind("XF86Calculator",           function() hl.exec_cmd(launchPrefix .. CALCULATOR) end)
-- The focused window to a new workspace at the end (newWorkspace in workspaces.lua)
hl.bind(mainMod .. " + W",          function()
    local win = hl.get_active_window()
    if win then hl.dispatch(hl.dsp.window.move({ workspace = newWorkspace(win.address) })) end
end)
hl.bind("CONTROL + SHIFT + Escape", function() hl.exec_cmd(launchPrefix .. TERMINAL .. " -e btop") end)
hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(slate("settings toggle")))
hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd(slate("bar panel control")))
hl.bind(mainMod .. " + Space",       hl.dsp.exec_cmd(slate("launcher toggle")))
hl.bind(mainMod .. " + period",     hl.dsp.exec_cmd(slate("picker toggle emoji")))
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(slate("lock lock")))
hl.bind(mainMod .. " + ALT + C",    hl.dsp.exec_cmd(slate("bar panel session")))
end
---------------------------
---- HARDWARE CONTROLS ----
---------------------------

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(slate("osd volume up")),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(slate("osd volume down")), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(slate("osd volume mute")), { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(slate("osd mic mute")),    { locked = true })

-- Media
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(slate("media toggle")),   { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(slate("media toggle")),   { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(slate("media next")),     { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(slate("media previous")), { locked = true })

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(slate("osd brightness up")),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(slate("osd brightness down")), { locked = true, repeating = true })
-- Keyboard backlight
hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd(slate("osd keyboard up")),   { locked = true, repeating = true })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd(slate("osd keyboard down")), { locked = true, repeating = true })

-- (Slate's set)
if SLATE_KEYS then
-------------------
---- UTILITIES ----
-------------------

-- Colour picker (copies the colour) and screenshots
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("hyprpicker -a -n"))
hl.bind("Print",               hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh region"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh screen"))

-- Wallpaper (opens Slate Settings → Appearance, at the wallpapers)
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(slate("settings page wallpaper")))

-- Clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(slate("picker toggle clipboard")))
-- Notifications
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(slate("bar panel notifications")))
-------------------------------
---- WORKSPACES & MONITORS ----
-------------------------------

-- Focus on monitors
hl.bind(mainMod .. " + " .. digitCode(1), hl.dsp.focus({ monitor = MONITOR1 }))
hl.bind(mainMod .. " + " .. digitCode(2), hl.dsp.focus({ monitor = MONITOR2 }))
hl.bind(mainMod .. " + " .. digitCode(3), hl.dsp.focus({ monitor = MONITOR3 }))

-- Focus on workspace number
-- Absolute
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + ALT + " .. digitCode(key), hl.dsp.focus({ workspace = i }))
end
-- Relative
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + CONTROL + " .. digitCode(key), hl.dsp.focus({ workspace = "m~" .. i }))
end

-- Move to adjacent workspaces and next empty on a given monitor
-- Hyprland picks the slide direction from workspace IDs, which is ambiguous with only two
-- workspaces, so only enable wraparound animation when this press actually wraps
local function cycleWorkspace(step)
    local current = hl.get_active_workspace()
    local monitor = current.monitor.name
    local minId, maxId = current.id, current.id
    local nextId, prevId = nil, nil
    local windows = {}
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.monitor and ws.monitor.name == monitor and not tostring(ws.name):find("^special") then
            minId = math.min(minId, ws.id)
            maxId = math.max(maxId, ws.id)
            windows[ws.id] = ws.windows or 0
            if ws.id > current.id and (not nextId or ws.id < nextId) then nextId = ws.id end
            if ws.id < current.id and (not prevId or ws.id > prevId) then prevId = ws.id end
        end
    end
    local wraps = (step > 0 and current.id == maxId) or (step < 0 and current.id == minId)
    -- Wrapping turned off (Settings → Windows): stay on the last (or first) one
    if wraps and WRAP_WORKSPACES == false then
        hl.exec_cmd(slate("osd workspace"))
        return
    end
    hl.config({ animations = { workspace_wraparound = wraps } })
    -- Where it's going (round to the other end when it wraps); to an empty workspace the
    -- windows slide away rather than fading where they are
    local target = step > 0 and (nextId or minId) or (prevId or maxId)
    local go = hl.dsp.focus({ workspace = step > 0 and "m+1" or "m-1" })
    if target ~= current.id and (windows[target] or 0) == 0 and slideAwayTo then slideAwayTo(go)
    else hl.dispatch(go) end
    hl.exec_cmd(slate("osd workspace"))     -- big workspace dots, like the bar's
end
hl.bind(mainMod .. " + Right", function() if overviewIsOpen() then ov("next") else cycleWorkspace(1) end end)
hl.bind(mainMod .. " + Left",  function() if overviewIsOpen() then ov("prev") else cycleWorkspace(-1) end end)

-- Scroll through existing workspaces & monitors
hl.bind(mainMod .. " + mouse_down",           hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + mouse_up",             hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special" }))
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special())
-- Super+Up: go to the highlighted workspace if the overview is open, otherwise
-- toggle the secret workspace
hl.bind(mainMod .. " + Up", function()
    if overviewIsOpen() then hl.exec_cmd(slate("overview go"))
    else hl.dispatch(hl.dsp.workspace.toggle_special()) end
end)
-- Super+Down: leave the secret workspace if it's showing, otherwise open the workspace overview
hl.bind(mainMod .. " + Down", function()
    if hl.get_active_special_workspace() then hl.dispatch(hl.dsp.workspace.toggle_special())
    elseif not overviewIsOpen() then hl.exec_cmd(slate("overview open")) end
end)
end

---------------------------------
---- HYPRLAND'S OWN SHORTCUTS ----
---------------------------------

-- The "Hyprland Defaults" and "Hyprland + Slate Extras" sets: Hyprland's default shortcuts
-- (its example hyprland.conf), with Slate's launcher for its app menu and Slate's log-out
-- question for its exit
if HYPR_KEYS then
    hl.bind(mainMod .. " + Q", function() hl.exec_cmd(launchPrefix .. TERMINAL) end)
    hl.bind(mainMod .. " + C", hl.dsp.window.close())
    hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(slate("power confirm logout")))
    hl.bind(mainMod .. " + E", function() hl.exec_cmd(launchPrefix .. FILE_MANAGER) end)
    hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(slate("launcher toggle")))
    hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
    hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
    -- Focus; with Slate's extras, they drive the workspace overview while it's open
    hl.bind(mainMod .. " + Left", function()
        if EXTRAS and overviewIsOpen() then ov("prev") else hl.dispatch(hl.dsp.focus({ direction = "left" })) end
    end)
    hl.bind(mainMod .. " + Right", function()
        if EXTRAS and overviewIsOpen() then ov("next") else hl.dispatch(hl.dsp.focus({ direction = "right" })) end
    end)
    hl.bind(mainMod .. " + Up", function()
        if EXTRAS and overviewIsOpen() then ov("go") else hl.dispatch(hl.dsp.focus({ direction = "up" })) end
    end)
    hl.bind(mainMod .. " + Down", hl.dsp.focus({ direction = "down" }))
    -- Workspaces 1 to 10, and moving the window to them
    for i = 1, 10 do
        hl.bind(mainMod .. " + " .. digitCode(i % 10), hl.dsp.focus({ workspace = i }))
        hl.bind(mainMod .. " + SHIFT + " .. digitCode(i % 10), hl.dsp.window.move({ workspace = i }))
    end
    -- The secret (special) workspace, and scrolling through workspaces
    hl.bind(mainMod .. " + S",          hl.dsp.workspace.toggle_special())
    hl.bind(mainMod .. " + SHIFT + S",  hl.dsp.window.move({ workspace = "special" }))
    hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
    hl.bind("XF86Calculator",           function() hl.exec_cmd(launchPrefix .. CALCULATOR) end)
end

-- "Hyprland + Slate Extras": Slate's shortcuts where Hyprland's leave the keys free (the
-- tap of Super and Super+Tab are earlier on, with Slate's own set). Three move: clipboard
-- history to Super+Shift+V, the colour picker to Super+Shift+P and the workspace overview
-- to Super+Ctrl+Down
if EXTRAS then
    hl.bind("ALT + Tab",                hl.dsp.window.cycle_next())
    hl.bind(mainMod .. " + Space",      hl.dsp.exec_cmd(slate("launcher toggle")))
    hl.bind(mainMod .. " + Return", function()
        if overviewIsOpen() then ov("go"); return end
        if slateOverlayOpen("slate-launcher") then hl.exec_cmd(slate("launcher launchOnNewWorkspace")); return end
        hl.exec_cmd(launchPrefix .. TERMINAL)
    end)
    hl.bind(mainMod .. " + T",          function() hl.exec_cmd(launchPrefix .. EDITOR) end)
    hl.bind(mainMod .. " + W",          function()
        local win = hl.get_active_window()
        if win then hl.dispatch(hl.dsp.window.move({ workspace = newWorkspace(win.address) })) end
    end)
    hl.bind("CONTROL + SHIFT + Escape", function() hl.exec_cmd(launchPrefix .. TERMINAL .. " -e btop") end)
    hl.bind(mainMod .. " + Escape",     hl.dsp.exec_cmd("hyprctl kill"))
    hl.bind(mainMod .. " + D",          hl.dsp.window.fullscreen({ mode = 1 }))
    hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen())
    hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(slate("settings toggle")))
    hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd(slate("bar panel control")))
    hl.bind(mainMod .. " + A",          hl.dsp.exec_cmd(slate("bar panel notifications")))
    hl.bind(mainMod .. " + ALT + C",    hl.dsp.exec_cmd(slate("bar panel session")))
    hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(slate("lock lock")))
    hl.bind(mainMod .. " + period",     hl.dsp.exec_cmd(slate("picker toggle emoji")))
    hl.bind(mainMod .. " + SHIFT + V",  hl.dsp.exec_cmd(slate("picker toggle clipboard")))
    hl.bind(mainMod .. " + SHIFT + P",  hl.dsp.exec_cmd("hyprpicker -a -n"))
    hl.bind(mainMod .. " + SHIFT + W",  hl.dsp.exec_cmd(slate("settings page wallpaper")))
    hl.bind("Print",                    hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh region"))
    hl.bind(mainMod .. " + Print",      hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh screen"))
    -- Moving the window: around this workspace, and to the next or previous workspace
    hl.bind(mainMod .. " + SHIFT + Up",    hl.dsp.window.move({ direction = "u" }))
    hl.bind(mainMod .. " + SHIFT + Down",  hl.dsp.window.move({ direction = "d" }))
    hl.bind(mainMod .. " + SHIFT + Right", function()
        if overviewIsOpen() then ov("moveRight") else hl.dispatch(hl.dsp.window.move({ direction = "r" })) end
    end)
    hl.bind(mainMod .. " + SHIFT + Left", function()
        if overviewIsOpen() then ov("moveLeft") else hl.dispatch(hl.dsp.window.move({ direction = "l" })) end
    end)
    hl.bind(mainMod .. " + CONTROL + Right", hl.dsp.window.move({ workspace = "m+1" }))
    hl.bind(mainMod .. " + CONTROL + Left",  hl.dsp.window.move({ workspace = "m-1" }))
    -- The workspace overview (or leave the secret workspace if it's showing)
    hl.bind(mainMod .. " + CONTROL + Down", function()
        if hl.get_active_special_workspace() then hl.dispatch(hl.dsp.workspace.toggle_special())
        elseif not overviewIsOpen() then hl.exec_cmd(slate("overview open")) end
    end)
end


-- Slate's shortcuts are done: descriptions from here on are only ones given explicitly
inSlateBinds = false
