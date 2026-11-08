-- Settings made in Slate's Settings window: keyboard, mouse and touchpad, focus, cursor
-- size, animations, default apps, and what the lid and power button do.
--
-- Slate calls slateApply({ ... }) when it starts, when this config reloads and whenever
-- one of these changes, passing only the settings you've changed there. Anything left
-- alone keeps whatever this config (or your ~/.config/slate/hypr/hyprland.lua) sets, so
-- hand-written settings aren't overwritten until you change them in Settings.

-- What closing the lid and pressing the power button do (Settings → Power). "" = the
-- system's own handling (logind: usually suspend / power off); otherwise Slate holds the
-- system's handling back and does it here.
LID_ACTION = LID_ACTION or ""
POWER_KEY_ACTION = POWER_KEY_ACTION or ""

-- Touchpads, by device name. Device rules (like a speed set for one touchpad in your own
-- file) win over the general setting, so touchpad speed and scrolling are set on each one.
local function touchpads()
    local out = {}
    local ok, devices = pcall(hl.get_devices)
    if ok and type(devices) == "table" then
        for _, d in ipairs(devices.mice or devices) do
            local name = type(d) == "table" and d.name or nil
            if name and name:lower():find("touchpad") then table.insert(out, name) end
        end
    end
    return out
end

local appliedCursor = nil
function slateApply(t)
    -- Keyboard and pointer (input)
    local input = {}
    for _, k in ipairs({ "kb_layout", "kb_variant", "kb_options", "repeat_rate", "repeat_delay",
                         "sensitivity", "accel_profile", "natural_scroll", "follow_mouse" }) do
        if t[k] ~= nil then input[k] = t[k] end
    end
    local tp = {}
    if t.tp_natural_scroll ~= nil then tp.natural_scroll = t.tp_natural_scroll end
    if t.tp_tap ~= nil then tp["tap-to-click"] = t.tp_tap end
    if t.tp_dwt ~= nil then tp.disable_while_typing = t.tp_dwt end
    if next(tp) then input.touchpad = tp end
    if next(input) then pcall(hl.config, { input = input }) end
    -- Touchpad speed and scrolling, on each touchpad
    if t.tp_sensitivity ~= nil or t.tp_scroll ~= nil then
        for _, name in ipairs(touchpads()) do
            local rule = { name = name }
            if t.tp_sensitivity ~= nil then rule.sensitivity = t.tp_sensitivity end
            if t.tp_scroll ~= nil then rule.scroll_factor = t.tp_scroll end
            pcall(hl.device, rule)
        end
    end

    -- Cursor size: Hyprland, then apps started from now on (GTK apps follow gsettings)
    if t.cursor_size ~= nil and t.cursor_size ~= appliedCursor then
        appliedCursor = t.cursor_size
        CURSOR_SIZE = t.cursor_size
        hl.env("XCURSOR_SIZE", tostring(CURSOR_SIZE))
        hl.env("HYPRCURSOR_SIZE", tostring(CURSOR_SIZE))
        hl.exec_cmd("hyprctl setcursor " .. CURSOR_THEME .. " " .. CURSOR_SIZE)
        hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. CURSOR_SIZE)
    end

    -- Animations: "normal", "fast" or "off" (animations.lua)
    if t.animations ~= nil and setAnimationSpeed then setAnimationSpeed(t.animations) end

    -- Default apps, used by the shortcuts in binds.lua when pressed
    if t.terminal then TERMINAL = t.terminal end
    if t.file_manager then FILE_MANAGER = t.file_manager end
    if t.browser then BROWSER = t.browser end
    if t.editor then EDITOR = t.editor end
    if t.calculator then CALCULATOR = t.calculator end

    -- Lid and power button
    if t.lid_action ~= nil then LID_ACTION = t.lid_action end
    if t.power_key_action ~= nil then POWER_KEY_ACTION = t.power_key_action end
end

-- ---- Lid and power button ------------------------------------------------------
-- Only acted on when an action is chosen in Settings → Power; Slate then holds back the
-- system's own handling (systemd-inhibit) so the two don't both happen.
local function laptopPanels()
    local out = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.name and (m.name:find("^eDP") or m.name:find("^LVDS") or m.name:find("^DSI")) then table.insert(out, m.name) end
    end
    return out
end
local function externalScreens()
    local n = 0
    for _, m in ipairs(hl.get_monitors() or {}) do
        if m.name and not (m.name:find("^eDP") or m.name:find("^LVDS") or m.name:find("^DSI")) then n = n + 1 end
    end
    return n
end
local function lidClosed()
    if LID_ACTION == "" or LID_ACTION == "nothing" then return end
    -- With another screen plugged in, closing the lid just turns the laptop's own screen off
    if LID_ACTION == "screenoff" or externalScreens() > 0 then
        for _, name in ipairs(laptopPanels()) do hl.dispatch(hl.dsp.dpms({ action = "off", monitor = name })) end
        return
    end
    if LID_ACTION == "suspend" then hl.exec_cmd("systemctl suspend")
    elseif LID_ACTION == "lock" then hl.exec_cmd(SLATE .. " ipc call lock lock") end
end
local function lidOpened()
    if LID_ACTION == "" then return end
    for _, name in ipairs(laptopPanels()) do hl.dispatch(hl.dsp.dpms({ action = "on", monitor = name })) end
end
hl.bind("switch:on:Lid Switch", lidClosed, { locked = true })
hl.bind("switch:off:Lid Switch", lidOpened, { locked = true })

local function powerKey()
    local a = POWER_KEY_ACTION
    if a == "menu" then hl.exec_cmd(SLATE .. " ipc call bar panel session")
    elseif a == "suspend" then hl.exec_cmd("systemctl suspend")
    elseif a == "poweroff" then hl.exec_cmd(SLATE .. " ipc call power confirm poweroff")
    elseif a == "lock" then hl.exec_cmd(SLATE .. " ipc call lock lock") end
end
hl.bind("XF86PowerOff", powerKey, { locked = true })
