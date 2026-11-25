-- Where Slate's own state and data are, for the rest of its Hyprland config. An empty
-- variable counts as not set, as the XDG spec says and Slate's own Config.qml does
-- (`os.getenv(...) or …` took "" as a folder and wrote to /slate/...).
--   slateEnv(name)       the variable, or nil when it's unset or empty
--   SLATE_STATE_HOME     $XDG_STATE_HOME, else ~/.local/state
--   SLATE_DATA_HOME      $XDG_DATA_HOME, else ~/.local/share
-- (loaded first by hyprland.lua; the unit tests load it too, so they use the same)
function slateEnv(name)
    local v = os.getenv(name)
    if v and v ~= "" then return v end
end
SLATE_STATE_HOME = slateEnv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
SLATE_DATA_HOME = slateEnv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")
