-- Layout, behaviour and rendering settings that don't fit elsewhere.

hl.config({
    dwindle = {
        preserve_split = true,             -- keep a split's direction when windows close
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    misc = {
        col = {
            splash = SLATE_ACCENT,
        },
        -- While Slate starts, show a plain dark background (the login screen's colour)
        -- rather than Hyprland's (or the distro's) default wallpaper and logo
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = 0xff0f1216,
        middle_click_paste = false,
        -- An app that asks to be brought forward (a browser handed a link by another app, a
        -- file opened in an app that's already running) is switched to, on its workspace
        focus_on_activate = true,
        -- A terminal that launches a GUI app hides while the app is open ("swallowing")
        enable_swallow = true,
        swallow_regex = "(kitty|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)",
        vrr = 3,                           -- variable refresh rate for fullscreen games and video
        -- If Slate restarts while the screen is locked, it can take the lock back over
        allow_session_lock_restore = true,
    },
    render = {
        direct_scanout = 2,                -- for fullscreen games
        -- If games black-screen for a moment when direct scanout switches on or off:
        -- non_shader_cm = 0,
    },
    xwayland = {
        force_zero_scaling = false,
    },
})
