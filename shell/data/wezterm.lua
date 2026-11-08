-- Slate's starting WezTerm config
--
-- Slate made this because you had no WezTerm config of your own (Settings → Appearance →
-- App theming). It's yours now: change anything. Switching WezTerm off in App theming
-- deletes this file if you haven't changed it, or just the colour scheme line if you have.

local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Slate's colours (colors/slate.toml), rewritten whenever Slate's theme changes
config.color_scheme = "Slate"

-- See-through, so Hyprland's blur shows behind the window
config.window_background_opacity = 0.6
-- Room between the text and the window's edges (pixels)
config.window_padding = { left = 25, right = 25, top = 25, bottom = 25 }
-- One window per terminal: Hyprland arranges the windows, so no tab bar
config.enable_tab_bar = false

return config
