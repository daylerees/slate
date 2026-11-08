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
        middle_click_paste = false,
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
