-- Window rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Add your own in ~/.config/slate/hypr/hyprland.lua.

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
local terminals = "^(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)$"

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
-- No drop shadow on tiled windows: against the accent border it reads as a second,
-- dark outline. Floating windows keep theirs.
hl.window_rule({ name = "no-shadow-tiled", match = { float = false }, no_shadow = true })

-- Slate's overlays (launcher, switcher, overview, panels, menus, notifications…)
-- animate themselves, so Hyprland shouldn't add its own fade on top
hl.layer_rule({
  name = "slate-overlays",
  match = { namespace = "^slate-(launcher|switcher|overview|popout|dock-menu|tray-menu|desktop-menu|notifications|corners|osd|lock-preview|confirm|picker|polkit|wallpaper|space-badge|welcome|fade-in|fade-out)$" },
  no_anim = true,
})

-- Slate Settings (Super+Z): floats in the middle of the screen, at the size it asks for
-- (880×620 times the interface size), kept within the screen by the floating-window limit above
hl.window_rule({ match = { title = "^(Slate Settings)$" }, float = true, center = true })

-- Window mode (Settings → Windows). Floating: every new window opens floating and centred,
-- like a traditional desktop (move with Super+drag or the title bar). Slate switches it
-- with setWindowMode; windows it floats are tagged "slate-floated", so switching back to
-- tiling only re-tiles those (apps and dialogs that float anyway stay floating).
FLOAT_ALL_RULE = hl.window_rule({ name = "float-all", match = { class = ".*" }, float = true, center = true, tag = "+slate-floated" })
FLOAT_ALL_RULE:set_enabled(false)
function setWindowMode(floating, convert)
    FLOAT_ALL_RULE:set_enabled(floating)
    -- Title bars (hyprbars.lua) only in floating mode
    if HYPRBARS_LOADED then pcall(hl.config, { plugin = { hyprbars = { enabled = floating } } }) end
    if not convert then return end
    if floating then
        for _, w in ipairs(hl.get_windows({ floating = false })) do
            local target = "address:" .. w.address
            if w.mapped and (w.fullscreen or 0) == 0 then
                hl.dispatch(hl.dsp.window.tag({ tag = "+slate-floated", window = target }))
                hl.dispatch(hl.dsp.window.float({ action = "enable", window = target }))
            end
        end
    else
        for _, w in ipairs(hl.get_windows({ tag = "slate-floated" })) do
            local target = "address:" .. w.address
            if w.floating and w.class ~= "slate-settings" then
                hl.dispatch(hl.dsp.window.float({ action = "disable", window = target }))
            end
            hl.dispatch(hl.dsp.window.tag({ tag = "-slate-floated", window = target }))
        end
    end
end
