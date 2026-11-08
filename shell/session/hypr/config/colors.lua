-- Colours for the Slate session's Hyprland config: Slate's palette, as hex RGBA.
-- Window borders follow the theme at runtime: Slate (shell.qml) replaces ACTIVE_BORDER and
-- INACTIVE_BORDER with the current accent and bar colour whenever the theme changes, so the
-- values here only show until Slate has started.

-- Slate's palette (the dark theme's defaults)
SLATE_ACCENT  = "rgba(8fb3e8ff)"   -- steel blue
SLATE_BG      = "rgba(0f1216ff)"   -- the bar and panels
SLATE_SURFACE = "rgba(1d222aff)"   -- cards and buttons
SLATE_DIM     = "rgba(8b94a3ff)"   -- secondary text
SLATE_DEEP    = "rgba(5f7fa8ff)"   -- a deeper accent, for locked window groups
TRANSPARENT   = "rgba(00000000)"

-- Window borders: shown only when a workspace has more than one window (see
-- windowrules.lua). Translucent, since Hyprland can't blur behind borders.
BORDER_SIZE     = 0
ACTIVE_BORDER   = { colors = { "rgba(8fb3e899)" } }   -- accent at 60%; also restored after resize mode
INACTIVE_BORDER = "rgba(0f1216d9)"                     -- bar colour at 85%
RESIZE_BORDER   = "rgba(ff1493ff)"                     -- bright pink while in resize mode (Super+R)
