-- Window rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Add your own in ~/.config/slate/hypr/rules.lua.

-- Floating windows remember their size
hl.window_rule({ match = { float = true }, persistent_size = true })

-- Picture-in-Picture
hl.window_rule({
    match             = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
    float             = true,
    keep_aspect_ratio = true,
    size              = { "max(monitor_w, monitor_h)*0.25", "min(monitor_w, monitor_h)*0.25" },
    pin               = true,
})

-- Games: Steam games and gamescope go to the "gaming" workspace (workspaces.lua), fullscreen
local gamingApps = "^(steam_app.*|gamescope)$"
local gamingWorkspace = "name:gaming"

hl.window_rule({ match = { content = "game" }, workspace = gamingWorkspace })
hl.window_rule({ match = { xdg_tag = "^(.*game.*)$" }, workspace = gamingWorkspace, fullscreen_state = 2, content = "game", sync_fullscreen = true })
hl.window_rule({ match = { class = gamingApps }, workspace = gamingWorkspace })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, float = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Launching\\.{3})$" }, float = true, center = true, workspace = gamingWorkspace })
hl.window_rule({
    match = {
        class         = gamingApps,
        title         = "^(.+)$",
        initial_title = "negative:^(.*\\\\home\\\\.*)$",
    },
    content          = "game",
    decorate         = false,
    fullscreen_state = 2,
    size             = { "monitor_w", "monitor_h" },
    sync_fullscreen  = true,
})
hl.window_rule({
    match = {
        class         = "^(steam_app.*)$",
        initial_title = "^$",
    },
    center           = true,
    float            = true,
    fullscreen       = false,
    fullscreen_state = 0,
    workspace        = gamingWorkspace,
})

-- Apps: launchers, Windows apps and chat on the main monitor; sizes for a few utilities
hl.window_rule({ match = { class = "^(.*\\.exe)$", float = true }, monitor = PRIMARY_MONITOR, center = true, fullscreen_state = 0 })
hl.window_rule({ match = { class = "^(.*[Ll]auncher.*)$" }, float = true, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(vesktop|discord)$" }, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(.*[Cc]alc.*)$" }, float = true, size = { "max(monitor_w, monitor_h)*0.17", "min(monitor_w, monitor_h)*0.43" } })
hl.window_rule({ match = { class = "^(org\\.kde\\.keditfiletype)$" }, float = true })
hl.window_rule({ match = { class = "^(org\\.kde\\.ark)$" }, size = { "max(monitor_w, monitor_h)*0.40", "min(monitor_w, monitor_h)*0.40" } })
hl.window_rule({ match = { class = "^(.*swash)$", title = "^(Swash)$" }, min_size = { "max(monitor_w, monitor_h)*0.35", "min(monitor_w, monitor_h)*0.35" }, float = true })
hl.window_rule({
    match = {
        class = "^(org\\.kde\\.dolphin)$",
        title = "negative:^(Moving.*|Create New.*|Extract.*|Compress.*|Copying.*|Progress.*|Configure.*|Properties.*|Choose\\sApplication.*)$",
    },
    float = true,
    size = { "max(monitor_w, monitor_h)*0.50", "min(monitor_w, monitor_h)*0.55" },
    move = {
        "max(20, min(cursor_x - (window_w*0.50), monitor_w - window_w + 20))", -- X axis clamping
        "max(20, min(cursor_y - 50, monitor_h - window_h + 20))" -- Y axis clamping
    },
})

-- Godot: never float the editor or the game it runs (tile them like normal windows)
hl.window_rule({ match = { class = "^([Gg]odot.*)$" }, tile = true })

-- Fully opaque: browsers, terminals (they handle their own transparency) and video players
local terminals = "^(" .. TERMINAL_CLASSES .. ")$"     -- (variables.lua)

hl.window_rule({ match = { class = "^(firefox|zen)$" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = terminals }, opacity = "1.0 override" })
hl.window_rule({ match = { class = "^(mpv|org.kde.haruna|.*plex.*|org\\.kde\\.gwenview|.*vlc.*)$" }, opacity = "1.0 override" })

-- Slate's Settings window never dims when it isn't focused (Settings → Windows → Dim inactive
-- windows), so you can see a change you make in it take effect on another window
hl.window_rule({ name = "slate-settings-no-dim", match = { class = "^(slate-settings)$" }, no_dim = true })

-- Float settings and utility windows
local floatApps = {
    { class = "^(kvantummanager|qt[56]ct|nwg-look)$" },
    { class = "^(org.pulseaudio.pavucontrol|blueman-manager|nm-applet|nm-connection-editor)$" },
    { title = "^(Winetricks.*|Protontricks.*)$" },
}
for _, m in ipairs(floatApps) do hl.window_rule({ match = m, float = true }) end

-- Float and centre common dialogs (file pickers, prompts, progress)
local modalMatches = {
    { title = "^(Open|Authentication Required|Add Folder to Workspace|Choose Files|Save As|Confirm to replace files|File Operation Progress)$" },
    { initial_title = "^(Open File)$" },
    { class = "^([Xx]dg-desktop-portal-gtk)$" },
    { title = "^(File Upload|Choose wallpaper|Library)(.*)$" },
    { class = "^(.*dialog.*)$" },
    { title = "^(.*dialog.*)$" },
    { class = "^(hyprland-share-picker)$"},
}
for _, m in ipairs(modalMatches) do hl.window_rule({ match = m, float = true, center = true }) end

-- Keep floating windows (file pickers etc.) within the screen
hl.window_rule({ match = { float = true }, max_size = { "monitor_w*0.90", "monitor_h*0.90" } })

-- Ignore apps asking to maximise themselves (tiling decides window sizes)
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- XWayland drag-and-drop: don't let the invisible drag window take focus
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- No border when a window is alone on the workspace (or maximized)
hl.window_rule({ name = "no-border-single", match = { float = false, workspace = "w[tv1]" }, border_size = 0 })
hl.window_rule({ name = "no-border-maximized", match = { float = false, workspace = "f[1]" }, border_size = 0 })
-- ...and square corners while it fills the screen: the fixed screen corners and bar
-- curves round it, so nothing moving shows past them during workspace slides. Slate
-- turns the lone-window one off when Settings → Windows pads lone windows, so they keep
-- their curves. Maximised windows always fill the screen.
SOLO_SQUARE_RULE = hl.window_rule({ name = "square-single", match = { float = false, workspace = "w[tv1]" }, rounding = 0 })
hl.window_rule({ name = "square-maximized", match = { float = false, workspace = "f[1]" }, rounding = 0 })
-- ...and every window is square for the length of a workspace switch that slides
-- (squareWhileSliding, animations.lua, switches this on and off again)
SLIDE_SQUARE_RULE = hl.window_rule({ name = "square-sliding", match = { class = ".*" }, rounding = 0 })
SLIDE_SQUARE_RULE:set_enabled(false)
-- No drop shadow on tiled windows: against the accent border it reads as a second,
-- dark outline. Floating windows keep theirs.
hl.window_rule({ name = "no-shadow-tiled", match = { float = false }, no_shadow = true })

-- Slate's overlays (launcher, switcher, overview, panels, menus, notifications…)
-- animate themselves, so Hyprland shouldn't add its own fade on top
hl.layer_rule({
  name = "slate-overlays",
  match = { namespace = "^slate-(bar|bar-editor|bar-dim|reloading|dock|dock-drag|dock-previews|launcher|assistant|switcher|overview|popout|dock-menu|tray-menu|desktop-menu|notifications|corners|osd|lock-preview|confirm|picker|polkit|wallpaper|space-badge|welcome|fade-in|fade-out|titlebar)$" },
  no_anim = true,
})
-- Slate's own title bars (TitleBar.qml) are a little see-through: what's behind them (windows
-- included) is blurred, but only where they're drawn (their layer covers the whole screen,
-- the rest of it clear)
hl.layer_rule({ name = "slate-titlebar-blur", match = { namespace = "^slate-titlebar$" }, blur = true, ignore_alpha = 0.3 })

-- Slate Settings (Super+Z): floats in the middle of the screen, at the size it asks for
-- (880×620 times the interface size), kept within the screen by the floating-window limit above
hl.window_rule({ match = { title = "^(Slate Settings)$" }, float = true, center = true })
-- Choosing your account picture (Settings → General): a dialog of Slate's own
hl.window_rule({ match = { class = "^(slate-settings)$", title = "^(Choose a picture)$" }, float = true, center = true })

-- Window mode. Settings → Windows sets the default (WINDOW_MODE), and each workspace can have
-- its own (WORKSPACE_MODES[id], from the menu bar's workspace indicator): tiling, master,
-- scrolling, monocle or floating. Slate sets both, then calls applyWorkspaceModes().
-- Floating: every new window opens floating and centred, like a traditional desktop (move with
-- Super+drag or the title bar). Done with a float rule for each workspace (1–30, then one for
-- the rest and one for the secret workspace), switched on where the mode is floating; windows
-- it floats are tagged "slate-floated", so going back to tiling only re-tiles those (apps and
-- dialogs that float anyway stay floating). The others are a layout, set per workspace.
WINDOW_MODE = WINDOW_MODE or "tiling"
WORKSPACE_MODES = WORKSPACE_MODES or {}
local LAYOUTS = { tiling = "dwindle", master = "master", scrolling = "scrolling", monocle = "monocle", floating = "dwindle", solo = "dwindle" }
local FLOAT_WS = {}
local function floatRule(name, ws)
    local r = hl.window_rule({ name = name, match = { class = ".*", workspace = ws }, float = true, center = true, tag = "+slate-floated" })
    r:set_enabled(false)
    return r
end
for i = 1, 30 do FLOAT_WS[i] = floatRule("float-ws-" .. i, tostring(i)) end
local FLOAT_REST = floatRule("float-ws-rest", "r[31-99999]")
local FLOAT_SPECIAL = floatRule("float-ws-special", "s[true]")
-- hyprbars' title bars only on floating windows (it's on for all of them otherwise). Only when
-- the plugin's loaded (hyprbars.lua, before this): without it Hyprland doesn't know the rule,
-- and reports a config error
if HYPRBARS_LOADED then
    pcall(hl.window_rule, { name = "hyprbars-tiled", match = { float = false }, ["hyprbars:no_bar"] = true })
end

-- The mode a workspace (by id) is in
function modeOf(id)
    return (id and WORKSPACE_MODES[id]) or WINDOW_MODE
end
-- The focused workspace's mode (Super+J, focusing left/right in binds.lua)
function activeMode()
    local ws = hl.get_active_workspace()
    return modeOf(ws and ws.id)
end

local layoutsSet = {}         -- workspaces given a layout of their own (to put back to the default)
function applyWorkspaceModes()
    local anyFloating = WINDOW_MODE == "floating"
    for i = 1, 30 do
        local floating = modeOf(i) == "floating"
        FLOAT_WS[i]:set_enabled(floating)
        anyFloating = anyFloating or floating
    end
    FLOAT_REST:set_enabled(WINDOW_MODE == "floating")
    FLOAT_SPECIAL:set_enabled(WINDOW_MODE == "floating")
    for id, mode in pairs(WORKSPACE_MODES) do
        if id > 30 and mode == "floating" then anyFloating = true end
    end
    -- Each workspace's layout: its own where it has one, else back to the default
    local default = LAYOUTS[WINDOW_MODE] or "dwindle"
    local now = {}
    for id, mode in pairs(WORKSPACE_MODES) do
        hl.workspace_rule({ workspace = tostring(id), layout = LAYOUTS[mode] or default })
        now[id] = true
    end
    for id in pairs(layoutsSet) do
        if not now[id] then hl.workspace_rule({ workspace = tostring(id), layout = default }) end
    end
    layoutsSet = now
    -- Title bars (hyprbars.lua) while any workspace floats, and not when Slate draws its own
    -- (SLATE_TITLEBARS, set by Slate before it calls this)
    if HYPRBARS_LOADED then pcall(hl.config, { plugin = { hyprbars = { enabled = anyFloating and not SLATE_TITLEBARS } } }) end
end

-- A floating window that's a dialog (a file picker, a save box, an app's settings): it stays
-- floating with its app when its workspace goes back to tiling or to Solo. Hyprland doesn't say which windows are dialogs, so: a smaller
-- window of an app that has a bigger one open, the desktop's file picker (a portal of its own),
-- or a title like a dialog's
local DIALOG_TITLE = { "^open", "^save", "^choose", "^select", "^print", "^export", "^import", "^rename",
                       "^upload", "^attach", "^insert", "^properties", "^preferences" }
local function isDialog(w, all)
    if not w.floating then return false end
    local class = string.lower(w.class or "")
    if class:find("portal") or class:find("kdialog") or class:find("zenity") or class:find("filechooser") then return true end
    local title = string.lower(w.title or "")
    for _, p in ipairs(DIALOG_TITLE) do if title:find(p) then return true end end
    local area = (w.size and w.size.x and w.size.x * w.size.y) or (w.size and w.size[1] and w.size[1] * w.size[2]) or 0
    for _, o in ipairs(all) do
        if o.address ~= w.address and o.pid == w.pid and o.mapped then
            local oa = (o.size and o.size.x and o.size.x * o.size.y) or (o.size and o.size[1] and o.size[1] * o.size[2]) or 0
            if oa > area then return true end
        end
    end
    return false
end

-- Float (or re-tile) the windows already open on the workspaces where `which(id)` is true, to
-- match their mode: after the mode's changed
local function convertWindows(which)
    for _, w in ipairs(hl.get_windows({})) do
        local id = w.workspace and w.workspace.id
        if id and which(id) and w.mapped and (w.fullscreen or 0) == 0 then
            local target = "address:" .. w.address
            local floating = modeOf(id) == "floating"
            if floating and not w.floating then
                hl.dispatch(hl.dsp.window.tag({ tag = "+slate-floated", window = target }))
                hl.dispatch(hl.dsp.window.float({ action = "enable", window = target }))
            end
        end
    end
    -- Back to tiling: only the windows Slate floated (dialogs stay floating with their apps)
    local all = hl.get_windows({})
    for _, w in ipairs(hl.get_windows({ tag = "slate-floated" })) do
        local id = w.workspace and w.workspace.id
        if id and which(id) and modeOf(id) ~= "floating" and not isDialog(w, all) then
            local target = "address:" .. w.address
            if w.floating and w.class ~= "slate-settings" then
                hl.dispatch(hl.dsp.window.float({ action = "disable", window = target }))
            end
            hl.dispatch(hl.dsp.window.tag({ tag = "-slate-floated", window = target }))
        end
    end
end

-- Solo: one window per workspace, filling it (a lone tile does: workspaces.lua). A window that
-- lands on a Solo workspace already holding one (opened there, or moved there) goes on to a new
-- workspace of its own (newWorkspace, workspaces.lua), which is Solo too. Dialogs and other
-- floating windows stay with their app; only tiled windows count
local function soloTarget(id, movingAddr)
    local target = newWorkspace(movingAddr)
    -- (when only this workspace was Solo, rather than the default: the new one is too)
    if WORKSPACE_MODES[id] == "solo" and WINDOW_MODE ~= "solo" then
        WORKSPACE_MODES[target] = "solo"
        if SLATE then hl.exec_cmd(SLATE .. " ipc call workspacemode set " .. target .. " solo") end
    end
    return target
end
local function soloSpill(win)
    if not win or not win.workspace or win.floating then return end
    local id = win.workspace.id
    if not id or id <= 0 or modeOf(id) ~= "solo" then return end
    for _, w in ipairs(hl.get_workspace_windows(id) or {}) do
        if w.address ~= win.address and w.mapped and not w.floating then
            hl.dispatch(hl.dsp.window.move({ workspace = soloTarget(id, win.address), window = "address:" .. win.address }))
            return
        end
    end
end
hl.on("window.open", soloSpill)
-- A window opening on a floating workspace is marked as one Slate floated, so going back to
-- tiling re-tiles it. (The float rules above ask for the tag too, but it doesn't reach the
-- windows they float: those stayed floating when their workspace went back to tiling.)
--
-- And it's put right as it opens, three ways:
--  * Its workspace's mode, not the one in front. Hyprland's rules go by the workspace you're
--    looking at when a window appears, and a window can open on another (an app started on one
--    workspace whose window arrives after you've gone to the next). So a window landing on a
--    floating workspace from a tiled one is floated here, and one that was floated only
--    because a floating workspace was in front, landing on a tiled one, is tiled again.
--  * No bigger than nine tenths of the screen's usable part (less its title bar): only a
--    window that opens larger is made smaller.
--  * All of it on the screen: one that would hang off an edge is moved in.
-- Looked at again a moment later, as some apps set their size just after they appear.
function slateFitFloating(address)
    local target = "address:" .. address
    local w = hl.get_window(target)
    local m = w and w.monitor
    if not (w and w.mapped and w.floating and m) or (w.fullscreen or 0) ~= 0 then return end
    local id = w.workspace and w.workspace.id
    if not id or modeOf(id) ~= "floating" then return end
    local r = m.reserved or {}
    local scale = m.scale or 1
    -- (room for the title bar above it: Slate's own, or hyprbars')
    local barH = SLATE_TITLEBARS and (SLATE_TITLEBAR_HEIGHT or 34) or 0
    if not SLATE_TITLEBARS and HYPRBARS_LOADED then
        local ok, h = pcall(hl.get_config, "plugin.hyprbars.bar_height")
        if ok and type(h) == "number" then barH = h end
    end
    local ax, ay = m.x + (r.left or 0), m.y + (r.top or 0) + barH
    local aw = math.floor(m.width / scale) - (r.left or 0) - (r.right or 0)
    local ah = math.floor(m.height / scale) - (r.top or 0) - (r.bottom or 0) - barH
    local x, y, sw, sh = w.at.x, w.at.y, w.size.x, w.size.y
    local nw, nh = math.min(sw, math.floor(aw * 0.9)), math.min(sh, math.floor(ah * 0.9))
    local nx, ny = x, y
    if nw ~= sw or nh ~= sh then
        -- (made smaller: centred again, as it would have been at that size)
        nx, ny = ax + math.floor((aw - nw) / 2), ay + math.floor((ah - nh) / 2)
    end
    nx = math.max(ax, math.min(nx, ax + aw - nw))
    ny = math.max(ay, math.min(ny, ay + ah - nh))
    if nw ~= sw or nh ~= sh then hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, window = target })) end
    if nx ~= x or ny ~= y then hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, window = target })) end
end
hl.on("window.open", function(win)
    local id = win and win.workspace and win.workspace.id
    if not (id and win.address) then return end
    local target = "address:" .. win.address
    local w = hl.get_window(target) or win
    if (w.fullscreen or 0) ~= 0 then return end
    local wants = modeOf(id) == "floating"
    local front = hl.get_active_workspace()
    if wants and not w.floating then
        hl.dispatch(hl.dsp.window.tag({ tag = "+slate-floated", window = target }))
        hl.dispatch(hl.dsp.window.float({ action = "enable", window = target }))
    elseif not wants and w.floating and front and front.id ~= id and modeOf(front.id) == "floating"
        and w.class ~= "slate-settings" and not isDialog(w, hl.get_windows({})) then
        hl.dispatch(hl.dsp.window.float({ action = "disable", window = target }))
        hl.dispatch(hl.dsp.window.tag({ tag = "-slate-floated", window = target }))
        return
    end
    if not wants then return end
    hl.dispatch(hl.dsp.window.tag({ tag = "+slate-floated", window = target }))
    slateFitFloating(win.address)
    local address = win.address
    hl.timer(function() slateFitFloating(address) end, { timeout = 350, type = "oneshot" })
end)
hl.on("window.move_to_workspace", function(win) soloSpill(win) end)
-- A workspace becoming Solo: every window on it fills a workspace of its own. Floating ones are
-- tiled (a lone tile fills its workspace), then the first stays and each of the others goes to a
-- new workspace. (Dialogs, and Slate's own Settings window, stay as they are.) The new workspaces are worked out
-- here, one after another, rather than asking newWorkspace each time: the moves only land once
-- this has run, so it would give the same one each time
local function soloSpread(which)
    local nextWs = nil                    -- (one count for the whole change: several workspaces may spread)
    local all = hl.get_windows({})
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id and ws.id > 0 and which(ws.id) and modeOf(ws.id) == "solo" then
            local wins = {}
            for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
                if w.mapped and not w.pinned and w.class ~= "slate-settings" and not isDialog(w, all) then table.insert(wins, w) end
            end
            for i, w in ipairs(wins) do
                local target = "address:" .. w.address
                if w.floating then
                    hl.dispatch(hl.dsp.window.float({ action = "disable", window = target }))
                    hl.dispatch(hl.dsp.window.tag({ tag = "-slate-floated", window = target }))
                end
                if i > 1 then
                    nextWs = nextWs and nextWs + 1 or newWorkspace(nil)
                    -- (only this workspace was Solo, not the default: its new ones are too)
                    if WORKSPACE_MODES[ws.id] == "solo" and WINDOW_MODE ~= "solo" then
                        WORKSPACE_MODES[nextWs] = "solo"
                        if SLATE then hl.exec_cmd(SLATE .. " ipc call workspacemode set " .. nextWs .. " solo") end
                    end
                    hl.dispatch(hl.dsp.window.move({ workspace = nextWs, window = target, follow = false }))
                end
            end
        end
    end
end

-- The default changed (Settings → Windows): the workspaces without a mode of their own follow it
function setWindowMode(_, convert)
    applyWorkspaceModes()
    if convert then
        local follows = function(id) return WORKSPACE_MODES[id] == nil end
        convertWindows(follows)
        soloSpread(follows)
    end
end
-- One workspace's mode changed (the menu bar): its windows follow it
function setWorkspaceMode(id, mode)
    WORKSPACE_MODES[id] = (mode ~= "" and mode) or nil
    applyWorkspaceModes()
    local this = function(wid) return wid == id end
    convertWindows(this)
    soloSpread(this)
end
