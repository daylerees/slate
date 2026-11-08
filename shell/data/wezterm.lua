-- Slate's starting WezTerm config, made because you had none. It's yours now: change
-- anything. The "Slate" colour scheme (colors/slate.toml) is rewritten by Slate when its
-- theme changes (Settings → Appearance → App theming).
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.color_scheme = "Slate"
config.window_background_opacity = 0.8
config.window_padding = { left = 20, right = 20, top = 20, bottom = 20 }
config.enable_tab_bar = false

return config
