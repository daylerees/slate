-- Input defaults for the Slate session. Keyboard layout, mouse feel and per-device
-- tweaks are personal: set them in ~/.config/slate/hypr/hyprland.lua

hl.config({
    input = {
        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Gestures
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "close" })
hl.gesture({ fingers = 3, direction = "up",         action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "left",       action = "float" })
