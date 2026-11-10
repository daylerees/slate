-- Hyprbars: optional title bars for floating windows (Settings → Windows → Title bars), from a
-- Hyprland plugin. Slate's own title bars are the default and need none of this. Slate builds
-- hyprbars with `slate build-hyprbars` (into ~/.local/share/slate/plugins); a distro package
-- of it works too. Shown only on floating workspaces with Hyprbars chosen (windowrules.lua);
-- Slate keeps the bar colour, title colour, font and size in step with its theme.

local dataHome = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
local plugins = dataHome .. "/slate/plugins/"
local system = {
    "/usr/lib/hyprland-plugins/hyprbars.so",
    "/usr/lib/hyprland/plugins/hyprbars.so",
    "/usr/local/lib/hyprland/plugins/hyprbars.so",
}

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end
local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function loaded()
    for _, p in ipairs(hl.get_loaded_plugins() or {}) do
        if p.name == "hyprbars" then return true end
    end
    return false
end

-- The Hyprland that's running: its version, and its commit (the start of its instance
-- signature), which is what a plugin has to match
local version = tostring(hl.version() or "")
local signature = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""
local commit = signature:match("^(%x+)_") or ""
-- Where the file this Hyprland loaded hyprbars from is noted
local runtime = os.getenv("XDG_RUNTIME_DIR")
local note = runtime and signature ~= "" and (runtime .. "/hypr/" .. signature .. "/slate-hyprbars") or nil

-- A plugin only loads in the exact Hyprland it was built for (asking for another's makes
-- Hyprland show error notices at login), so only a build made for this one is asked for:
--  - Slate's builds are named for their Hyprland: hyprbars-<version>-<commit>.so
--  - a build from before they were named (hyprbars.so): when its record (hyprbars.json, which
--    Slate writes once it's seen it loaded) says it's for this Hyprland; with no record yet,
--    as before
--  - a distro's package, which its package manager keeps in step
-- Nothing after "Remove Hyprbars" (the `removed` mark), until it's built again.
local function choose()
    if not exists(plugins .. "removed") then
        local named = {
            plugins .. "hyprbars-" .. version .. "-" .. commit:sub(1, 12) .. ".so",
            plugins .. "hyprbars-" .. version .. ".so",
        }
        for _, path in ipairs(named) do
            if version ~= "" and exists(path) then return path end
        end
        local old = plugins .. "hyprbars.so"
        if exists(old) then
            local record = read(plugins .. "hyprbars.json")
            if not record then return old end
            local forCommit = record:match('"commit"%s*:%s*"(%x*)"') or ""
            local forVersion = record:match('"version"%s*:%s*"([^"]*)"') or ""
            if forCommit ~= "" and commit ~= "" then
                if forCommit == commit then return old end
            elseif forVersion == version then
                return old
            end
            print("[slate] hyprbars was built for Hyprland " .. forVersion .. ", this is " .. version .. "; not loading it (Slate Bars are used)")
        end
    end
    for _, path in ipairs(system) do
        if exists(path) then return path end
    end
    return nil
end

-- Ask for the plugin on every config pass, even when it's already loaded. Hyprland treats
-- the loads a config asks for as the list it should have: skipping the call once hyprbars
-- is in makes Hyprland unload it and reload the config, which loads it again and reloads,
-- forever (a stack overflow that crashes Hyprland). So once it's loaded, the same file is
-- asked for again on every pass for as long as this Hyprland runs, whatever has been built
-- or removed since; the file is noted for that.
local path = nil
if loaded() then
    path = note and read(note) or nil
    if path then path = path:gsub("%s+$", "") end
    if not path or path == "" or not exists(path) then
        -- (loaded before the file was noted: the old build first, as it was chosen then)
        path = exists(plugins .. "hyprbars.so") and (plugins .. "hyprbars.so") or choose()
    end
else
    path = choose()
end
if path then
    local ok, err = pcall(hl.plugin.load, path)
    if not ok then
        print("[slate] hyprbars at " .. path .. " didn't load (rebuild it: slate build-hyprbars): " .. tostring(err))
    elseif note and loaded() then
        local f = io.open(note, "w")
        if f then f:write(path); f:close() end
    end
end
HYPRBARS_LOADED = loaded()

-- The title bar's maximise button (and double-click): maximise the window to the workspace
-- area, or put it back. A floating window's own size can be as big as the screen (an app
-- that opened that big, or one floated from a tile), which puts its title bar under Slate's
-- bar and off the top edge, so restoring would look like fullscreen with no button to get
-- back. When the restored window doesn't fit the area beside Slate's bar, it's shrunk to fit
-- and centred.
function slateToggleMaximize()
    local w = hl.get_active_window()
    if not w then return end
    local target = "address:" .. w.address
    if (w.fullscreen or 0) ~= 0 then
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = target }))
    else
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = target }))
        return
    end

    w = hl.get_window(target)
    local m = w and w.monitor
    if not (w and w.floating and m) then return end
    local r = m.reserved or {}
    local scale = m.scale or 1
    local barH = 0
    local okBar, h = pcall(hl.get_config, "plugin.hyprbars.bar_height")
    if okBar and type(h) == "number" then barH = h end
    local margin = 24
    local ax = m.x + (r.left or 0)
    local ay = m.y + (r.top or 0)
    local aw = math.floor(m.width / scale) - (r.left or 0) - (r.right or 0)
    local ah = math.floor(m.height / scale) - (r.top or 0) - (r.bottom or 0)
    local x, y, sw, sh = w.at.x, w.at.y - barH, w.size.x, w.size.y + barH
    if x >= ax and y >= ay and x + sw <= ax + aw and y + sh <= ay + ah then return end

    local nw = math.min(sw, aw - 2 * margin)
    local nh = math.min(sh, ah - 2 * margin)
    local nx = ax + math.floor((aw - nw) / 2)
    local ny = ay + math.floor((ah - nh) / 2)
    hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh - barH, window = target }))
    hl.dispatch(hl.dsp.window.move({ x = nx, y = ny + barH, window = target }))
end

if HYPRBARS_LOADED then
    local ok, err = pcall(function()
        hl.config({
            plugin = {
                hyprbars = {
                    enabled = false,                   -- floating mode turns them on
                    bar_height = 34,                   -- Slate scales it with its font size
                    bar_padding = 12,
                    bar_button_padding = 8,
                    bar_text_size = 13,               -- Slate matches its font size setting
                    bar_text_weight = "medium",
                    bar_text_font = "Geist",           -- Slate sets its interface font
                    bar_text_align = "center",
                    bar_buttons_alignment = "right",   -- Settings → Windows → Title bar buttons
                    bar_part_of_window = true,         -- one shape with the window (shadow, corners)
                    -- The window's edge comes first: its top edge and top corners resize like the
                    -- others (Hyprland's grab area reaches over the bar's top); lower on the bar moves it
                    bar_precedence_over_border = false,
                    bar_blur = false,
                    bar_color = "rgb(0f1216)",         -- Slate sets these from its theme
                    col = { text = "rgb(eef1f5)" },
                    inactive_button_color = "rgb(3a424e)",
                    -- Double-click the bar: maximise (or restore)
                    on_double_click = [[hyprctl dispatch 'function() slateToggleMaximize() end']],
                },
            },
        })
        -- Buttons are plain dots in a dull theme colour (idle_button_color, below) that light
        -- up when hovered. Outermost first: close (red), then maximise (the theme's accent),
        -- sized from Slate's font size. hyprbars only takes button colours and sizes when the
        -- config loads, so Slate writes them to ~/.local/state/slate/hyprbars.lua and reloads
        -- Hyprland when they change.
        local theme = { accent = "rgb(8b94a3)", accent_text = "rgb(12151a)", button_size = 16 }
        local stateHome = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
        local okTheme, t = pcall(dofile, stateHome .. "/slate/hyprbars.lua")
        if okTheme and type(t) == "table" then
            for k, v in pairs(t) do theme[k] = v end
        end
        hl.plugin.hyprbars.add_button({
            bg_color = "rgb(e5534b)", fg_color = "rgb(ffffff)", size = theme.button_size, icon = "",
            action = "hyprctl dispatch 'hl.dsp.window.close()'",
        })
        hl.plugin.hyprbars.add_button({
            bg_color = theme.accent, fg_color = theme.accent_text, size = theme.button_size, icon = "",
            action = [[hyprctl dispatch 'function() slateToggleMaximize() end']],
        })
    end)
    if not ok then print("[slate] hyprbars settings: " .. tostring(err)) end
    -- From Slate's patch to hyprbars (data/hyprbars-idle-button-color.patch); a hyprbars
    -- without it doesn't know this setting (and setting it anyway is a config error). Slate
    -- sets it from its theme
    HYPRBARS_IDLE = hl.get_config("plugin.hyprbars.idle_button_color") ~= nil
    if HYPRBARS_IDLE then pcall(hl.config, { plugin = { hyprbars = { idle_button_color = "rgb(5a6372)" } } }) end
end
