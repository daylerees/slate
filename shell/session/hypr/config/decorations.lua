-- Look and feel: gaps, borders, rounding, opacity, dimming and blur.
-- Your own changes go in ~/.config/slate/hypr/hyprland.lua, which loads after this file.
-- (Animations are in animations.lua; colours in colors.lua.)

hl.config({
    general = {
        gaps_in = 3,                       -- between windows
        gaps_out = 8,                      -- between windows and the screen edge
        border_size = BORDER_SIZE,         -- only shown with more than one window (windowrules.lua)
        extend_border_grab_area = 10,      -- grab a window edge from a little outside it
        resize_on_border = true,
        col = {
            active_border = ACTIVE_BORDER,
            inactive_border = INACTIVE_BORDER,
        },
    },
    -- Window groups (tabbed windows)
    group = {
        col = {
            border_active = SLATE_ACCENT,
            border_inactive = SLATE_DIM,
            border_locked_active = SLATE_DEEP,
            border_locked_inactive = SLATE_DIM,
        },
        groupbar = {
            col = {
                active = SLATE_ACCENT,
                inactive = SLATE_SURFACE,
                locked_active = SLATE_DEEP,
                locked_inactive = SLATE_SURFACE,
            },
        },
    },
    decoration = {
        rounding = 10,
        active_opacity = 0.95,             -- slightly see-through, so the blur shows
        inactive_opacity = 0.85,
        fullscreen_opacity = 1,
        -- Dim the windows that don't have focus, so the focused one stands out
        dim_inactive = true,
        dim_strength = 0.5,
        dim_special = 0.3,                 -- dim what's behind the secret workspace
        blur = {
            size = 5,
            passes = 4,
            special = true,                -- blur behind the secret workspace too
        },
        -- A soft drop shadow under floating windows (settings, dialogs); tiled windows
        -- have none (windowrules.lua)
        -- (Slate's one shadow at its default settings, the same as under its own surfaces;
        -- Slate sets it from Settings → Appearance → Shadows: Config.hyprShadow)
        shadow = {
            range = 22,
            render_power = 2,
            offset = { 0, 2 },
            color = "rgba(0a0c10ac)",
        },
    },
})
