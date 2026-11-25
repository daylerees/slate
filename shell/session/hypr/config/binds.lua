-- Keyboard and mouse shortcuts for the Slate session.
-- Sections: helpers · shortcuts in more than one set · windows · zoom · apps & Slate's panels ·
-- Nova · hardware keys · utilities · workspaces & monitors · Hyprland's own · Hyprland + Slate Extras. Many shortcuts talk to Slate via `slate ipc call …` (see
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
    local path = SLATE_STATE_HOME .. "/slate/keyset.lua"
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
-- one of your own (in ~/.config/slate/hypr/binds.lua) on the same keys doesn't take
-- Slate's description; give it its own with { description = "Group: what it does" }.
local inSlateBinds = true
local SHORTCUT_DESCRIPTIONS = {
    ["SUPER + SUPER_L"]            = "Apps: Tap Super on its own: the app launcher",
    ["SUPER + Space"]              = "Apps: The app launcher",
    ["SUPER + Return"]             = "Apps: A terminal",
    ["SUPER + grave"]              = "Apps: Show or hide the drop-down terminal",
    ["SUPER + E"]                  = "Apps: Files",
    ["SUPER + T"]                  = "Apps: Text editor",
    ["SUPER + C"]                  = "Apps: Calculator",
    ["CONTROL + SHIFT + Escape"]   = "Apps: System monitor (btop)",
    ["SUPER + Z"]                  = "Slate: Settings",
    ["SUPER + X"]                  = "Slate: Control center",
    ["SUPER + A"]                  = "Slate: Notifications",
    ["SUPER + ALT + C"]            = "Slate: Power menu",
    ["SUPER + L"]                  = "Slate: Lock the screen",
    ["SUPER + V"]                  = "Slate: Clipboard history",
    ["SUPER + period"]             = "Slate: Emoji",
    ["SUPER + SHIFT + W"]          = "Slate: Change the wallpaper",
    ["SUPER + ALT + W"]            = "Slate: Wallpaper switcher (Left and Right to look, Enter to keep one)",
    ["SUPER + P"]                  = "Slate: Pick a color from the screen (copied)",
    ["Print"]                      = "Slate: Screenshot of an area",
    ["SUPER + Print"]              = "Slate: Screenshot of the screen",
    ["SUPER + SHIFT + Print"]      = "Slate: Record an area of the screen, or stop recording",
    ["SUPER + Minus"]              = "Slate: Zoom out",
    ["SUPER + Plus"]               = "Slate: Zoom in",
    ["SUPER + equal"]              = "Slate: Zoom in (the + and = key)",
    ["SUPER + code:82"]            = "Slate: Zoom out (keypad -)",
    ["SUPER + code:86"]            = "Slate: Zoom in (keypad +)",
    ["SUPER + ALT + Z"]            = "Slate: Zoom on or off",
    ["SUPER + ALT + P"]            = "Slate: Show where the pointer is",
    ["SUPER + ALT + K"]            = "Slate: On-screen keyboard",
    ["SUPER + ALT + S"]            = "Slate: Screen reader on or off",
    ["SUPER + ALT + B"]            = "Slate: The menu bar by keyboard",
    ["SUPER + ALT + D"]            = "Slate: The dock by keyboard",
    ["SUPER + ALT + mouse_up"]     = "Slate: Zoom in (scroll)",
    ["SUPER + ALT + mouse_down"]   = "Slate: Zoom out (scroll)",
    ["SUPER + Q"]                  = "Windows: Close the window",
    ["SUPER + Escape"]             = "Windows: Force-quit an app (click its window)",
    ["SUPER + Tab"]                = "Windows: Switch windows (hold Super)",
    ["SUPER + SHIFT + Tab"]        = "Windows: Switch windows, going backwards (hold Super)",
    ["SUPER + SHIFT + mouse_up"]   = "Monitors: Move the window to the previous monitor (scroll)",
    ["SUPER + SHIFT + mouse_down"] = "Monitors: Move the window to the next monitor (scroll)",
    ["SUPER + CONTROL + SHIFT + mouse_up"]   = "Workspaces: Move the window to this monitor's previous workspace (scroll)",
    ["SUPER + CONTROL + SHIFT + mouse_down"] = "Workspaces: Move the window to this monitor's next workspace (scroll)",
    ["SUPER + mouse_up"]           = "Workspaces: This monitor's previous workspace (scroll)",
    ["SUPER + mouse_down"]         = "Workspaces: This monitor's next workspace (scroll)",
    ["SUPER + CONTROL + mouse_up"]   = "Workspaces: This monitor's previous workspace (scroll)",
    ["SUPER + CONTROL + mouse_down"] = "Workspaces: This monitor's next workspace (scroll)",
    ["XF86Calculator"]             = "Apps: The calculator (the calculator key)",
    ["ALT + Tab"]                  = "Windows: Next window",
    ["SUPER + ALT + Space"]        = "Windows: Float or tile the window",
    ["SUPER + D"]                  = "Windows: Maximize",
    ["SUPER + F"]                  = "Windows: Full screen",
    ["SUPER + J"]                  = "Windows: Split the other way (Side Stack: make it the main window; Scrolling: change the column's width; Stacking: the next window)",
    ["SUPER + R"]                  = "Windows: Resize with the arrow keys",
    ["SUPER + ALT + Left"]         = "Windows: Focus the window to the left (Stacking: the previous window)",
    ["SUPER + ALT + Right"]        = "Windows: Focus the window to the right (Stacking: the next window)",
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
    ["SUPER + Right"]              = "Workspaces: Next workspace (in a switcher: the next window, wallpaper or workspace)",
    ["SUPER + Left"]               = "Workspaces: Previous workspace (in a switcher: the previous one)",
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
    ["SUPER + J"]                  = "Windows: Split the other way (Side Stack: make it the main window; Scrolling: change the column's width; Stacking: the next window)",
    ["SUPER + Left"]               = "Windows: Focus the window to the left (Stacking: the previous window)",
    ["SUPER + Right"]              = "Windows: Focus the window to the right (Stacking: the next window)",
    ["SUPER + Up"]                 = "Windows: Focus the window above",
    ["SUPER + Down"]               = "Windows: Focus the window below",
    ["SUPER + M"]                  = "Slate: Log out (asks first)",
    ["SUPER + S"]                  = "Workspaces: Show or hide the secret workspace",
    ["SUPER + SHIFT + S"]          = "Workspaces: Move the window to the secret workspace",
    ["SUPER + mouse_down"]         = "Workspaces: Next workspace",
    ["SUPER + mouse_up"]           = "Workspaces: Previous workspace",
    ["SUPER + mouse:272"]          = "Windows: Move a window (drag)",
    ["SUPER + mouse:273"]          = "Windows: Resize a window (right-drag)",
    ["XF86Calculator"]             = "Apps: The calculator (the calculator key)",
}
-- Slate's shortcuts that move to other keys in "Hyprland + Slate Extras" (theirs are taken)
local EXTRA_DESCRIPTIONS = {
    ["SUPER + SHIFT + V"]          = "Slate: Clipboard history",
    ["SUPER + SHIFT + P"]          = "Slate: Pick a color from the screen (copied)",
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
-- A command that needs a tool not every distro installs with Slate (hyprpicker, btop): run
-- through scripts/need.sh, which runs it as it is when the tool is there, and otherwise says
-- what to install in a notification, so the shortcut never just does nothing. `what` is how
-- the notification starts ("The color picker"); no quotes in it
local function needing(tool, what, cmd)
    return SLATE_DIR .. "/scripts/need.sh " .. tool .. " '" .. what .. "' -- " .. cmd
end

-- Start a default app (Settings → Default Apps, or variables.lua). When it's one of the apps Slate
-- itself offers (KNOWN_APPS) and isn't installed, say what to install, the way `needing` does,
-- rather than running a command that isn't there. A command line you wrote yourself is run as
-- it is. `what` is how the notification starts ("The terminal"); no quotes in it
local function app(cmd, what)
    local bin = cmd:match("^(%S+)")
    if bin and (KNOWN_APPS or {})[bin] then return needing(bin, what, launchPrefix .. cmd) end
    return launchPrefix .. cmd
end

-- The drop-down terminal (Super+`): shown over whatever you're doing, or hidden again. Started
-- the first time (windowrules.lua puts it on its special workspace and places it), then kept
-- running while hidden. (A global, so the tests can call it)
function dropdownTerminal()
    for _, w in ipairs(hl.get_windows() or {}) do
        if w.class == DROPDOWN_CLASS then
            if not (w.workspace and w.workspace.name == "special:dropdown" and w.visible) then placeDropdown() end
            hl.dispatch(hl.dsp.workspace.toggle_special("dropdown"))
            return
        end
    end
    local bin, cmd = DROPDOWN_COMMAND()
    hl.exec_cmd(needing(bin, "The drop-down terminal", launchPrefix .. cmd))
end

-- Is one of Slate's overlays open and holding the keyboard? (by layer name, e.g. "slate-launcher";
-- gestures.lua asks too)
function slateOverlayOpen(name)
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
        -- the keys (code:10 is the 1 key … code:19 the 0 key; other codes, like the keypad's
        -- + and -, have their own entry above)
        local desc = inSlateBinds and DESCRIPTIONS[keys] or nil
        if inSlateBinds and not desc then
            local mods, code = keys:match("^(.-) %+ code:(%d+)$")
            local what = mods and DIGIT_DESCRIPTIONS[mods]
            if what and tonumber(code) >= 10 and tonumber(code) <= 19 then desc = string.format(what, tonumber(code) == 19 and 10 or tonumber(code) - 9) end
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
-- The window switcher (Super+Tab) is open: Super+Left/Right move through it, not the workspaces
local function switcherIsOpen() return slateOverlayOpen("slate-switcher") end
local function sw(cmd) hl.exec_cmd(slate("switcher " .. cmd)) end
-- The wallpaper switcher (Super+Alt+W) is open: Super+Left/Right move through it too
local function wallSwitcherIsOpen() return slateOverlayOpen("slate-wallpaper-switcher") end
local function wsw(cmd) hl.exec_cmd(slate("wallpaperSwitcher " .. cmd)) end

-- AZERTY fix: the number-row keys emit symbols (& é " ' ...) without Shift, so
-- binding to the digit characters fails. Bind by physical keycode instead.
-- Digit d -> evdev keycode: 1..9 => 10..18, 0 => 19
local function digitCode(d)
    return "code:" .. (d == 0 and 19 or (9 + d))
end

----------------------------------------
---- SHORTCUTS IN MORE THAN ONE SET ----
----------------------------------------

-- What a shortcut does, written once here when more than one set has it, so the sets can't
-- come to differ: each set below puts these on its own keys (Slate's set and Hyprland + Slate
-- Extras mostly on the same ones; clipboard history, the colour picker and the workspace
-- overview move in the Extras, where Hyprland's defaults have their keys).
-- To change what one of them does in your own binds.lua, bind its keys again there.
local shared = {
    -- Apps. They're read when pressed, so Settings → Default Apps applies straight away
    launcher = hl.dsp.exec_cmd(slate("launcher toggle")),
    -- A terminal; or, while the workspace overview is open, go to the workspace picked there;
    -- or, while the app launcher is open, open the selected app on a new workspace
    terminal = function()
        if overviewIsOpen() then ov("go"); return end
        if slateOverlayOpen("slate-launcher") then hl.exec_cmd(slate("launcher launchOnNewWorkspace")); return end
        hl.exec_cmd(app(TERMINAL, "The terminal"))
    end,
    dropdown = function() dropdownTerminal() end,
    files         = function() hl.exec_cmd(app(FILE_MANAGER, "The file manager")) end,
    editor        = function() hl.exec_cmd(app(EDITOR, "The text editor")) end,
    calculator    = function() hl.exec_cmd(app(CALCULATOR, "The calculator")) end,
    systemMonitor = function() hl.exec_cmd(needing("btop", "The system monitor", launchPrefix .. TERMINAL_RUN("btop"))) end,

    -- Slate's windows and panels
    settings      = hl.dsp.exec_cmd(slate("settings toggle")),
    controlCentre = hl.dsp.exec_cmd(slate("bar panel control")),
    notifications = hl.dsp.exec_cmd(slate("bar panel notifications")),
    powerMenu     = hl.dsp.exec_cmd(slate("bar panel session")),
    lock          = hl.dsp.exec_cmd(slate("lock lock")),
    emoji         = hl.dsp.exec_cmd(slate("picker toggle emoji")),
    clipboard     = hl.dsp.exec_cmd(slate("picker toggle clipboard")),

    -- Utilities: the colour picker (copies the colour), screenshots, and the wallpaper (Slate
    -- Settings → Wallpaper) and its switcher
    colourPicker      = hl.dsp.exec_cmd(needing("hyprpicker", "The color picker", "hyprpicker -a -n")),
    screenshotArea    = hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh region"),
    screenshotScreen  = hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/screenshot.sh screen"),
    recordToggle      = hl.dsp.exec_cmd(slate("record toggle region")),
    wallpaper         = hl.dsp.exec_cmd(slate("settings page wallpaper")),
    wallpaperSwitcher = hl.dsp.exec_cmd(slate("wallpaper switcher")),

    -- Windows (maximiseSmart is under WINDOWS, below)
    -- (a chooser, then scripts/force-quit.sh: never Slate's own windows, which hyprctl kill took the
    -- whole desktop with)
    forceQuit  = hl.dsp.exec_cmd(SLATE_DIR .. "/scripts/force-quit.sh --pick"),
    maximise   = function() maximiseSmart() end,
    fullScreen = hl.dsp.window.fullscreen(),
    nextWindow = hl.dsp.window.cycle_next(),
    -- Moving the window around its workspace; left and right move it between workspaces
    -- instead while the workspace overview is open
    moveUp     = hl.dsp.window.move({ direction = "u" }),
    moveDown   = hl.dsp.window.move({ direction = "d" }),
    moveLeft   = function()
        if overviewIsOpen() then ov("moveLeft") else hl.dispatch(hl.dsp.window.move({ direction = "l" })) end
    end,
    moveRight  = function()
        if overviewIsOpen() then ov("moveRight") else hl.dispatch(hl.dsp.window.move({ direction = "r" })) end
    end,

    -- Workspaces: the focused window to the next or previous one, or to a new one at the end
    -- (newWorkspace in workspaces.lua)
    toNextWorkspace     = hl.dsp.window.move({ workspace = "m+1" }),
    toPreviousWorkspace = hl.dsp.window.move({ workspace = "m-1" }),
    toNewWorkspace      = function()
        local win = hl.get_active_window()
        if win then hl.dispatch(hl.dsp.window.move({ workspace = newWorkspace(win.address) })) end
    end,
    -- The workspace overview; or, if the secret workspace is showing, leave that
    overview = function()
        if hl.get_active_special_workspace() then hl.dispatch(hl.dsp.workspace.toggle_special())
        elseif not overviewIsOpen() then hl.exec_cmd(slate("overview open")) end
    end,
}

-----------------
---- WINDOWS ----
-----------------

-- Closing, floating, maximising and focusing windows, the window switcher, moving and
-- resizing them. First what the shortcuts call, then the shortcuts.

-- Close the active window; if it was the last one on its workspace, jump back to the
-- previously focused workspace once it has actually closed (apps may cancel the close).
-- Matches on the closed window's address so helper windows (Electron) and apps that hide
-- to tray instead of exiting (Steam) still trigger it
local pendingClose = nil
-- (by name, unique to each workspace: a named one has no id in Hyprland 0.57, and every
-- named one's nil would have matched every other's)
local function otherWindowsOn(wsName, exceptAddr)
    local n = 0
    for _, w in ipairs(hl.get_windows()) do
        if w.mapped and w.address ~= exceptAddr and w.workspace and w.workspace.name == wsName and not slateIsPinned(w) then
            n = n + 1
        end
    end
    return n
end
function closeWindowSmart()
    local win = hl.get_active_window()
    pendingClose = nil
    if win and win.workspace and not tostring(win.workspace.name):find("^special")
        and otherWindowsOn(win.workspace.name, win.address) == 0 then
        pendingClose = { addr = win.address, ws = win.workspace.name }
    end
    hl.dispatch(hl.dsp.window.close())
end
hl.on("window.close", function(win)
    if not (pendingClose and win and win.address == pendingClose.addr) then return end
    local p = pendingClose
    pendingClose = nil
    local ws = hl.get_active_workspace()
    if ws and ws.name == p.ws and otherWindowsOn(p.ws, p.addr) == 0 then
        hl.dispatch(hl.dsp.focus({ workspace = "previous" }))
    end
end)

-- The window mode (Settings → Windows): tiling, master (Side Stack), scrolling, monocle
-- (Stacking), solo or floating. Slate
-- sets it with Hyprland's layout (shell.qml), so a shortcut can do the matching job in each
-- layout: Super+J splits the other way in tiling, and does the nearest thing in the others
WINDOW_MODE = WINDOW_MODE or "tiling"
-- (the focused workspace's mode: each can have its own, windowrules.lua)
local function currentMode() return activeMode and activeMode() or WINDOW_MODE end
function layoutAction()
    local mode = currentMode()
    if mode == "master" then hl.dispatch(hl.dsp.layout("swapwithmaster"))
    elseif mode == "scrolling" then hl.dispatch(hl.dsp.layout("colresize +conf"))
    elseif mode == "monocle" then hl.dispatch(hl.dsp.layout("cyclenext"))
    else hl.dispatch(hl.dsp.layout("togglesplit")) end
end
-- Focus left or right; in monocle the other windows are hidden behind the one shown, so it
-- goes to the previous or next one instead
function focusSideways(dir)
    if currentMode() == "monocle" then
        hl.dispatch(hl.dsp.layout(dir == "left" and "cycleprev" or "cyclenext"))
    else
        hl.dispatch(hl.dsp.focus({ direction = dir }))
    end
end

-- Maximise: a floating window with Slate's own title bars is maximised by Slate, leaving room
-- for its bar (titlebar maximise, TitleBar.qml); otherwise Hyprland's (which the bar can't sit on).
-- Out here with the other functions, not inside Slate's set: Hyprland + Slate Extras binds
-- Super+D to it too, and did nothing while it was only made for Slate's own set
function maximiseSmart()
    local w = hl.get_active_window()
    if SLATE_TITLEBARS and w and w.floating then
        hl.exec_cmd(slate("titlebar maximise " .. w.address))
    else
        hl.dispatch(hl.dsp.window.fullscreen({ mode = 1 }))
    end
end

-- (Slate's set)
if SLATE_KEYS then
    -- Closing, floating, maximising, splitting
    hl.bind(mainMod .. " + Escape",      shared.forceQuit)
    hl.bind(mainMod .. " + Q",           function() closeWindowSmart() end)
    hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + D",           shared.maximise)
    hl.bind(mainMod .. " + F",           shared.fullScreen)
    hl.bind(mainMod .. " + J",           function() layoutAction() end)

    -- Change focus
    hl.bind(mainMod .. " + ALT + Left",  function() focusSideways("left") end)
    hl.bind(mainMod .. " + ALT + Right", function() focusSideways("right") end)
    hl.bind(mainMod .. " + ALT + Up",    hl.dsp.focus({ direction = "up" }))
    hl.bind(mainMod .. " + ALT + Down",  hl.dsp.focus({ direction = "down" }))
    hl.bind("ALT + Tab",                 shared.nextWindow)
end

-- (Slate's set, and Hyprland + Slate Extras)
if SLATE_KEYS or EXTRAS then
    -- Window switcher (Slate): hold Super, press Tab / Shift+Tab, let go of Super to switch
    hl.bind(mainMod .. " + Tab",         hl.dsp.exec_cmd(slate("switcher next")))
    hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.exec_cmd(slate("switcher prev")))
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

-- The window to, or you to, the first, second or third monitor (MONITOR_NTH, variables.lua)
function toMonitor(n)
    local m = MONITOR_NTH(n)
    if m then hl.dispatch(hl.dsp.window.move({ monitor = m })) end
end
function focusMonitor(n)
    local m = MONITOR_NTH(n)
    if m then hl.dispatch(hl.dsp.focus({ monitor = m })) end
end

-- (Slate's set)
if SLATE_KEYS then
    -- Move the window: around its workspace, to another monitor, to another of this
    -- monitor's workspaces
    hl.bind(mainMod .. " + SHIFT + Up",                   shared.moveUp)
    hl.bind(mainMod .. " + SHIFT + Right",                shared.moveRight)
    hl.bind(mainMod .. " + SHIFT + Left",                 shared.moveLeft)
    hl.bind(mainMod .. " + SHIFT + Down",                 shared.moveDown)
    hl.bind(mainMod .. " + SHIFT + " .. digitCode(1),     function() toMonitor(1) end)
    hl.bind(mainMod .. " + SHIFT + " .. digitCode(2),     function() toMonitor(2) end)
    hl.bind(mainMod .. " + SHIFT + " .. digitCode(3),     function() toMonitor(3) end)
    hl.bind(mainMod .. " + SHIFT + mouse_up",             hl.dsp.window.move({ monitor   = "-1" }))
    hl.bind(mainMod .. " + SHIFT + mouse_down",           hl.dsp.window.move({ monitor   = "+1" }))
    hl.bind(mainMod .. " + CONTROL + Right",              shared.toNextWorkspace)
    hl.bind(mainMod .. " + CONTROL + Left",               shared.toPreviousWorkspace)
    hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up",   hl.dsp.window.move({ workspace = "m-1" }))
    hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }))
    -- To this monitor's workspace 1, 2, 3…: going with the window, then staying here
    for i = 1, NUM_WPM do
        local key = i % 10
        hl.bind(mainMod .. " + SHIFT + CONTROL + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i }))
    end
    for i = 1, NUM_WPM do
        local key = i % 10
        hl.bind(mainMod .. " + SHIFT + ALT + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i, follow = false }))
    end
end

-- (every set)
-- Move and resize with the mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize())
-- A drag ended (the left button let go, however the window was moved): a floating window
-- dropped above or under the menu bar goes back below it (windowrules.lua). Never takes the
-- click from anything; looked at a moment later, once the move has settled
hl.bind("mouse:272", function()
    local w = hl.get_active_window()
    if not (w and w.floating) then return end
    local address = w.address
    hl.timer(function() slateKeepUnderBar(address) end, { timeout = 60, type = "oneshot" })
end, { release = true, non_consuming = true, ignore_mods = true })

-- Resize mode: SUPER + R, then arrows to resize; Escape, Return or SUPER + R to exit
-- (Slate's set: Super+R is the app launcher in Hyprland's)
if SLATE_KEYS then
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

--------------
---- ZOOM ----
--------------

-- Zooming the whole screen around the pointer, between 1× and 5× (Settings → Accessibility →
-- Zoom). The keys zoom here at once, then tell Slate where they got to ("zoom note"), which keeps
-- Settings in step and puts the zoom back after a reload; Settings tells Hyprland through
-- setZoom (Config.qml, with its other settings)
SLATE_ZOOM_LEVEL = SLATE_ZOOM_LEVEL or 2
local function zoomTo(value)
    value = math.max(1, math.min(5, value))
    hl.config({ cursor = { zoom_factor = value } })
    hl.exec_cmd(slate("zoom note " .. string.format("%.2f", value)))
end
local function zoomBy(step)
    zoomTo(hl.get_config("cursor:zoom_factor") + step)
end
-- On (at the level last chosen) or off
local function zoomToggle()
    if hl.get_config("cursor:zoom_factor") > 1.001 then zoomTo(1) else zoomTo(SLATE_ZOOM_LEVEL) end
end
-- From Slate: on or off, how far, and whether the pointer stays in the middle (rigid)
function setZoom(on, level, rigid)
    SLATE_ZOOM_LEVEL = math.max(1.25, math.min(5, level or 2))
    hl.config({ cursor = { zoom_factor = on and SLATE_ZOOM_LEVEL or 1, zoom_rigid = rigid == true } })
end

-- (Slate's set, and Hyprland + Slate Extras)
if SLATE_KEYS or EXTRAS then
    hl.bind(mainMod .. " + Minus", function() zoomBy(-0.25) end, { repeating = true })
    hl.bind(mainMod .. " + Plus", function() zoomBy(0.25) end, { repeating = true })
    -- (and the key + shares with =: on US and UK keyboards + is Shift and =, and Hyprland matches
    -- a bind's key without its Shift, so Plus alone never fired there)
    hl.bind(mainMod .. " + equal", function() zoomBy(0.25) end, { repeating = true })

    -- Zoom with the keypad's - and +
    hl.bind(mainMod .. " + code:82", function() zoomBy(-0.25) end, { repeating = true })
    hl.bind(mainMod .. " + code:86", function() zoomBy(0.25) end, { repeating = true })
    -- Zoom on or off
    hl.bind(mainMod .. " + ALT + Z", zoomToggle)
    -- The screen reader on or off (Accessibility)
    hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd(slate("screenreader toggle")))
    -- The on-screen keyboard: shown or put away (Accessibility)
    hl.bind(mainMod .. " + ALT + K", hl.dsp.exec_cmd(slate("keyboard toggle")))
    -- The menu bar or the dock by keyboard: the arrow keys move, Enter presses, Escape leaves
    hl.bind(mainMod .. " + ALT + B", hl.dsp.exec_cmd(slate("keys bar")))
    hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd(slate("keys dock")))
    -- Where's the pointer? Rings round it for a moment (Accessibility)
    hl.bind(mainMod .. " + ALT + P", hl.dsp.exec_cmd(slate("pointer locate")))
    -- ...and with the scroll wheel: up to zoom in, down to zoom out
    hl.bind(mainMod .. " + ALT + mouse_up", function() zoomBy(0.25) end)
    hl.bind(mainMod .. " + ALT + mouse_down", function() zoomBy(-0.25) end)
end

--------------------------------
---- APPS & SLATE'S PANELS ----
--------------------------------

-- Opening apps, and Slate's own windows and panels (Settings, the control centre, the app
-- launcher, emoji, the lock screen, the power menu). What each does is in `shared`, above.

-- (Slate's set)
if SLATE_KEYS then
    hl.bind(mainMod .. " + Return",     shared.terminal)
    hl.bind(mainMod .. " + grave",      shared.dropdown)
    hl.bind(mainMod .. " + E",          shared.files)
    hl.bind(mainMod .. " + T",          shared.editor)
    hl.bind(mainMod .. " + C",          shared.calculator)
    hl.bind("XF86Calculator",           shared.calculator)
    hl.bind(mainMod .. " + W",          shared.toNewWorkspace)
    hl.bind("CONTROL + SHIFT + Escape", shared.systemMonitor)
    hl.bind(mainMod .. " + Z",          shared.settings)
    hl.bind(mainMod .. " + X",          shared.controlCentre)
    hl.bind(mainMod .. " + Space",      shared.launcher)
    hl.bind(mainMod .. " + period",     shared.emoji)
    hl.bind(mainMod .. " + L",          shared.lock)
    hl.bind(mainMod .. " + ALT + C",    shared.powerMenu)
end

--------------
---- NOVA ----
--------------

-- Nova, Slate's assistant, in every key set: Super+K; a keyboard's own assistant key; and
-- the Copilot key on recent laptops, which has no key of its own: it presses Left Super,
-- Left Shift and F23 together (keycode 201, bound by code as keyboard tables name it
-- differently). Switched off, they open its window saying so, never a dead key.
-- Super+K can also be held to talk to Nova (Settings → Assistant → Voice, NovaVoice.qml): a
-- quick press opens Nova (or closes it, if it was the window you're in, as it's let go); held past NOVA_HOLD
-- ms, Slate listens until K is let go, then sends what was said. The let-go is caught by a
-- release bind on K alone with any modifiers (Super is often let go first), which does
-- nothing unless Super+K started it, and never takes the key from anything
local NOVA_HOLD = 350
local novaHeld, novaListening, novaWasOpen, novaTimer = false, false, false, nil
-- (Nova's window is a real one of Slate's, slateIsNova in windowrules.lua: a tap closes it only
-- when it's the window you're in; open behind something, the press brings it to the front)
-- (global, so the tests can press and let go through hyprctl: a virtual keyboard's keys
-- don't reach binds)
function novaKeyDown()
    if novaHeld then return end
    novaHeld, novaListening = true, false
    novaWasOpen = slateIsNova(hl.get_active_window()) and true or false
    if not novaWasOpen then hl.exec_cmd(slate("assistant open")) end
    if novaTimer then novaTimer:set_enabled(false) end
    novaTimer = hl.timer(function()
        novaTimer = nil
        if novaHeld then
            novaListening = true
            hl.exec_cmd(slate("voice hold"))
        end
    end, { timeout = NOVA_HOLD, type = "oneshot" })
end
function novaKeyUp()
    if not novaHeld then return end
    novaHeld = false
    if novaTimer then novaTimer:set_enabled(false); novaTimer = nil end
    if novaListening then
        novaListening = false
        hl.exec_cmd(slate("voice release"))
    elseif novaWasOpen then
        hl.exec_cmd(slate("assistant close"))
    end
end

-- (every set)
hl.bind(mainMod .. " + K", function() novaKeyDown() end, { description = "Slate: Ask Nova (hold to talk)" })
hl.bind("K", function() novaKeyUp() end, { release = true, non_consuming = true, ignore_mods = true })
hl.bind("XF86Assistant",            hl.dsp.exec_cmd(slate("assistant toggle")), { description = "Slate: Ask Nova (assistant key)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd(slate("assistant toggle")), { description = "Slate: Ask Nova (Copilot key)" })

-----------------------
---- HARDWARE KEYS ----
-----------------------

-- The keyboard's own volume, media and brightness keys; they work on the lock screen too
-- (every set)

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

-------------------
---- UTILITIES ----
-------------------

-- The colour picker, screenshots, the wallpaper, clipboard history and notifications. What
-- each does is in `shared`, above.

-- (Slate's set)
if SLATE_KEYS then
    -- Colour picker (copies the colour) and screenshots
    hl.bind(mainMod .. " + P",     shared.colourPicker)
    hl.bind("Print",               shared.screenshotArea)
    hl.bind(mainMod .. " + Print", shared.screenshotScreen)
    hl.bind(mainMod .. " + SHIFT + Print", shared.recordToggle)

    -- Wallpaper (opens Slate Settings → Wallpaper), and the wallpaper switcher
    hl.bind(mainMod .. " + SHIFT + W", shared.wallpaper)
    hl.bind(mainMod .. " + ALT + W",   shared.wallpaperSwitcher)

    -- Clipboard
    hl.bind(mainMod .. " + V", shared.clipboard)
    -- Notifications
    hl.bind(mainMod .. " + A", shared.notifications)
end

-------------------------------
---- WORKSPACES & MONITORS ----
-------------------------------

-- Going to a monitor or a workspace, moving through this monitor's workspaces, the secret
-- workspace and the workspace overview. (Moving a window to one is under WINDOWS.)

-- Move to the next (step 1) or previous (step -1) workspace on this monitor.
-- Hyprland picks the slide direction from workspace IDs, which is ambiguous with only two
-- workspaces, so only enable wraparound animation when this press actually wraps
function cycleWorkspace(step)
    local current = hl.get_active_workspace()
    -- On a named workspace (one made by your own rules): it has no number to step from, so
    -- Hyprland's own next or previous, with nothing worked out
    if not current or not current.id then
        hl.dispatch(hl.dsp.focus({ workspace = step > 0 and "m+1" or "m-1" }))
        hl.exec_cmd(slate("osd workspace"))
        return
    end
    local monitor = current.monitor.name
    local minId, maxId = current.id, current.id
    local nextId, prevId = nil, nil
    for _, ws in ipairs(hl.get_workspaces()) do
        -- (only numbered ones: a named workspace has no id in Hyprland 0.57)
        if ws.id and ws.monitor and ws.monitor.name == monitor and not tostring(ws.name):find("^special") then
            minId = math.min(minId, ws.id)
            maxId = math.max(maxId, ws.id)
            if ws.id > current.id and (not nextId or ws.id < nextId) then nextId = ws.id end
            if ws.id < current.id and (not prevId or ws.id > prevId) then prevId = ws.id end
        end
    end
    local wraps = (step > 0 and current.id == maxId) or (step < 0 and current.id == minId)
    -- Wrapping turned off (Settings → Workspaces): stay on the last (or first) one
    if wraps and WRAP_WORKSPACES == false then
        hl.exec_cmd(slate("osd workspace"))
        return
    end
    hl.config({ animations = { workspace_wraparound = wraps } })
    -- Where it's going (round to the other end when it wraps), with the usual animation, or
    -- the windows sliding away where that wouldn't look right (switchWorkspace, animations.lua)
    local target = step > 0 and (nextId or minId) or (prevId or maxId)
    local go = hl.dsp.focus({ workspace = step > 0 and "m+1" or "m-1" })
    if switchWorkspace then switchWorkspace(go, current.id, target) else hl.dispatch(go) end
    hl.exec_cmd(slate("osd workspace"))     -- big workspace dots, like the bar's
end

-- Go to workspace id as Super+Left/Right do (the menu bar's dots): the same animation, sliding
-- the windows away to an empty workspace, and in the direction of the numbers (never wrapping)
function goToWorkspace(id)
    local current = hl.get_active_workspace()
    local go = hl.dsp.focus({ workspace = id })
    hl.config({ animations = { workspace_wraparound = false } })
    if current and switchWorkspace then switchWorkspace(go, current.id, id) else hl.dispatch(go) end
end

-- (Slate's set)
if SLATE_KEYS then
    -- Focus a monitor (the one you've named, or the first, second, third in use: MONITOR_NTH)
    hl.bind(mainMod .. " + " .. digitCode(1), function() focusMonitor(1) end)
    hl.bind(mainMod .. " + " .. digitCode(2), function() focusMonitor(2) end)
    hl.bind(mainMod .. " + " .. digitCode(3), function() focusMonitor(3) end)

    -- Go to a workspace by number
    -- Absolute: workspace 1, 2, 3…
    for i = 1, NUM_WPM do
        local key = i % 10
        hl.bind(mainMod .. " + ALT + " .. digitCode(key), hl.dsp.focus({ workspace = i }))
    end
    -- Relative: this monitor's first, second, third…
    for i = 1, NUM_WPM do
        local key = i % 10
        hl.bind(mainMod .. " + CONTROL + " .. digitCode(key), hl.dsp.focus({ workspace = "m~" .. i }))
    end

    -- The next and previous workspace on this monitor; while a switcher or the workspace
    -- overview is open, they move through that instead
    hl.bind(mainMod .. " + Right", function()
        if switcherIsOpen() then sw("next") elseif wallSwitcherIsOpen() then wsw("next") elseif overviewIsOpen() then ov("next") else cycleWorkspace(1) end
    end)
    hl.bind(mainMod .. " + Left", function()
        if switcherIsOpen() then sw("prev") elseif wallSwitcherIsOpen() then wsw("prev") elseif overviewIsOpen() then ov("prev") else cycleWorkspace(-1) end
    end)

    -- Scroll through this monitor's workspaces
    hl.bind(mainMod .. " + mouse_down",           hl.dsp.focus({ workspace = "m+1" }))
    hl.bind(mainMod .. " + mouse_up",             hl.dsp.focus({ workspace = "m-1" }))
    hl.bind(mainMod .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m-1" }))
    hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }))

    -- The secret workspace (Hyprland's name for it is the special workspace): move the
    -- window to it, and show or hide it
    hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special" }))
    hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special())
    -- Super+Up: go to the highlighted workspace if the overview is open, otherwise
    -- show or hide the secret workspace
    hl.bind(mainMod .. " + Up", function()
        if overviewIsOpen() then hl.exec_cmd(slate("overview go"))
        else hl.dispatch(hl.dsp.workspace.toggle_special()) end
    end)
    -- Super+Down: leave the secret workspace if it's showing, otherwise open the workspace overview
    hl.bind(mainMod .. " + Down", shared.overview)
end

----------------------------------
---- HYPRLAND'S OWN SHORTCUTS ----
----------------------------------

-- Hyprland's default shortcuts (its example hyprland.conf), with Slate's launcher for its app
-- menu and Slate's log-out question for its exit.

-- (Hyprland Defaults, and Hyprland + Slate Extras)
if HYPR_KEYS then
    hl.bind(mainMod .. " + Q", function() hl.exec_cmd(app(TERMINAL, "The terminal")) end)
    hl.bind(mainMod .. " + C", hl.dsp.window.close())
    hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(slate("power confirm logout")))
    hl.bind(mainMod .. " + E", shared.files)
    hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(slate("launcher toggle")))
    hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
    hl.bind(mainMod .. " + J", function() layoutAction() end)
    -- Focus; with Slate's extras, they drive the window switcher, wallpaper switcher or workspace overview while open
    hl.bind(mainMod .. " + Left", function()
        if EXTRAS and switcherIsOpen() then sw("prev")
        elseif EXTRAS and wallSwitcherIsOpen() then wsw("prev")
        elseif EXTRAS and overviewIsOpen() then ov("prev") else focusSideways("left") end
    end)
    hl.bind(mainMod .. " + Right", function()
        if EXTRAS and switcherIsOpen() then sw("next")
        elseif EXTRAS and wallSwitcherIsOpen() then wsw("next")
        elseif EXTRAS and overviewIsOpen() then ov("next") else focusSideways("right") end
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
    -- The secret workspace (Hyprland's name for it is the special workspace), and scrolling
    -- through workspaces
    hl.bind(mainMod .. " + S",          hl.dsp.workspace.toggle_special())
    hl.bind(mainMod .. " + SHIFT + S",  hl.dsp.window.move({ workspace = "special" }))
    hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
    hl.bind("XF86Calculator",           shared.calculator)
end

---------------------------------
---- HYPRLAND + SLATE EXTRAS ----
---------------------------------

-- Slate's shortcuts where Hyprland's leave the keys free, each doing what it does in Slate's
-- set (`shared`, above). The tap of Super, Super+Tab and zoom are earlier on, with Slate's own
-- set. Three are on other keys here, as Hyprland's defaults have theirs; they're marked.

-- (Hyprland + Slate Extras)
if EXTRAS then
    hl.bind("ALT + Tab",                shared.nextWindow)
    hl.bind(mainMod .. " + Space",      shared.launcher)
    hl.bind(mainMod .. " + Return",     shared.terminal)
    hl.bind(mainMod .. " + grave",      shared.dropdown)
    hl.bind(mainMod .. " + T",          shared.editor)
    hl.bind(mainMod .. " + W",          shared.toNewWorkspace)
    hl.bind("CONTROL + SHIFT + Escape", shared.systemMonitor)
    hl.bind(mainMod .. " + Escape",     shared.forceQuit)
    hl.bind(mainMod .. " + D",          shared.maximise)
    hl.bind(mainMod .. " + F",          shared.fullScreen)
    hl.bind(mainMod .. " + Z",          shared.settings)
    hl.bind(mainMod .. " + X",          shared.controlCentre)
    hl.bind(mainMod .. " + A",          shared.notifications)
    hl.bind(mainMod .. " + ALT + C",    shared.powerMenu)
    hl.bind(mainMod .. " + L",          shared.lock)
    hl.bind(mainMod .. " + period",     shared.emoji)
    hl.bind(mainMod .. " + SHIFT + V",  shared.clipboard)       -- moved: Super+V in Slate's set
    hl.bind(mainMod .. " + SHIFT + P",  shared.colourPicker)    -- moved: Super+P in Slate's set
    hl.bind(mainMod .. " + SHIFT + W",  shared.wallpaper)
    hl.bind(mainMod .. " + ALT + W",    shared.wallpaperSwitcher)
    hl.bind("Print",                    shared.screenshotArea)
    hl.bind(mainMod .. " + Print",      shared.screenshotScreen)
    hl.bind(mainMod .. " + SHIFT + Print", shared.recordToggle)
    -- Moving the window: around its workspace, and to the next or previous workspace
    hl.bind(mainMod .. " + SHIFT + Up",      shared.moveUp)
    hl.bind(mainMod .. " + SHIFT + Down",    shared.moveDown)
    hl.bind(mainMod .. " + SHIFT + Right",   shared.moveRight)
    hl.bind(mainMod .. " + SHIFT + Left",    shared.moveLeft)
    hl.bind(mainMod .. " + CONTROL + Right", shared.toNextWorkspace)
    hl.bind(mainMod .. " + CONTROL + Left",  shared.toPreviousWorkspace)
    hl.bind(mainMod .. " + CONTROL + Down",  shared.overview)   -- moved: Super+Down in Slate's set
end

-- Slate's shortcuts are done: descriptions from here on are only ones given explicitly
inSlateBinds = false
