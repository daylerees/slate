-- Input defaults for the Slate session, until Slate's Settings → Input sets yours (slate.lua):
-- keyboard layouts, repeat, pointer speed and scrolling are set there. Per-device tweaks (one
-- mouse slower than the rest) go in ~/.config/slate/hypr/hyprland.lua

hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Touchpad gestures are in gestures.lua (Settings → Input → Gestures)
