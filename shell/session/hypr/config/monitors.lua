-- Monitors: https://wiki.hypr.land/Configuring/Basics/Monitors/
-- By default every monitor uses its best mode (below) and its preferred scale. To name your
-- monitors, set MONITOR1… in ~/.config/slate/hypr/variables.lua (`hyprctl monitors` lists
-- them); for a specific mode, position or scale, use Settings → Displays, or add hl.monitor()
-- to ~/.config/slate/hypr/monitors.lua, for example:
--   hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = "1" })

hl.monitor({
    output    = MONITOR1,
    mode      = "preferred",
    position  = "auto",
    scale     = "auto",
})

-- ---- The tests' screen -----------------------------------------------------------
-- Slate's live tests need the vkms kernel module loaded on this computer, and Hyprland sees its
-- screen too ("Virtual-1"): turned on and drawn though nobody could see it, it kept Hyprland
-- busy and the desktop lagged. So its screens are off here (the tests' own session turns on the
-- one it uses). Found by the vkms device in /sys, not by name: a virtual machine's screen is
-- called "Virtual-1" too. (SLATE_VKMS_DIRS: the tests' stand-in for where to look)
function slateTestScreens()
    local out = {}
    local p = io.popen("ls -d " .. (SLATE_VKMS_DIRS or "/sys/devices/faux/vkms/drm/card*/card*-* /sys/devices/platform/vkms/drm/card*/card*-*") .. " 2>/dev/null")
    if not p then return out end
    for line in p:lines() do
        local name = line:match("/card%d+%-([^/]+)$")
        if name then out[name] = true end
    end
    p:close()
    return out
end
local inTests = os.getenv("SLATE_TEST") == "1"
if not inTests then
    for name in pairs(slateTestScreens()) do hl.monitor({ output = name, disabled = true }) end
end

-- ---- Each monitor's best mode ------------------------------------------------------
-- A monitor's "preferred" mode is the one it recommends, which isn't always its best: some
-- recommend a smaller, slower one (an Odyssey G9 says 3840x1080 at 120 Hz, though it shows
-- 5120x1440 at 240 Hz). So until you choose one (Settings → Displays, or a rule of your own),
-- each monitor gets its largest resolution, at its fastest rate there. Never slower than it
-- recommends: a resolution is only taken if it has a rate at least that fast (a TV that
-- recommends 3840x2160 at 60 Hz but lists 4096x2160 at 24 Hz stays as it recommends).
-- The rates at that resolution, fastest first, from the fastest down to the recommended one:
-- if one doesn't take (the cable or the card can't carry it, and Hyprland falls back), the
-- next is tried.
local function sameRate(a, b) return math.abs(a - b) < 0.5 end
function slateBestModes(modes)
    if type(modes) ~= "table" or #modes == 0 then return {} end
    local pref = modes[1]
    for _, m in ipairs(modes) do if m.preferred then pref = m; break end end
    local floor = (pref.refresh_rate or 0) - 0.5
    -- The largest resolution with a rate at least as fast as the recommended one
    local w, h = 0, 0
    for _, m in ipairs(modes) do
        local area = (m.width or 0) * (m.height or 0)
        if (m.refresh_rate or 0) >= floor and (area > w * h or (area == w * h and m.width > w)) then
            w, h = m.width, m.height
        end
    end
    if w == 0 then return {} end
    -- Its rates, fastest first, down to the recommended one
    local rates = {}
    for _, m in ipairs(modes) do
        local r = m.refresh_rate or 0
        if m.width == w and m.height == h and r >= floor then
            local seen = false
            for _, x in ipairs(rates) do if sameRate(x, r) then seen = true end end
            if not seen then table.insert(rates, r) end
        end
    end
    table.sort(rates, function(a, b) return a > b end)
    -- Already its best: nothing to do
    if w == pref.width and h == pref.height and sameRate(rates[1], pref.refresh_rate or 0) then return {} end
    local out = {}
    for _, r in ipairs(rates) do table.insert(out, string.format("%dx%d@%.2f", w, h, r)) end
    return out
end

-- Monitors with a mode chosen for them, by output as given (a name, or "desc:…"): Settings →
-- Displays (displays.lua) and your own rules, which load after this. Those are left alone.
local chosen = {}
local function isChosen(m)
    for out in pairs(chosen) do
        if out == m.name then return true end
        local d = out:match("^desc:(.*)$")
        if d and m.description and m.description:sub(1, #d) == d then return true end
    end
    return false
end
local function outputOf(m)
    return (m.description and m.description ~= "") and ("desc:" .. m.description) or m.name
end
local function sizeOf(m)
    local mode = type(m.mode) == "table" and m.mode or m
    return mode.width or m.width, mode.height or m.height, mode.refresh_rate or m.refresh_rate or 0
end
-- Give a monitor its best mode, stepping down a rate whenever one doesn't take
local trying = {}       -- output -> true while its modes are being tried
local function giveBest(m, live)
    if not m or not m.name or m.name == "" or isChosen(m) then return end
    if m.enabled == false then return end
    -- Only real screens, which say what they are (make, model, serial). One that doesn't is
    -- a virtual machine's or a test's (vkms), offering every size up to 4096x2160 or more,
    -- each one costlier to draw: it keeps the mode it recommends.
    if not m.description or m.description == "" then return end
    local modes = slateBestModes(m.available_modes)
    if #modes == 0 then return end
    local out = outputOf(m)
    -- (on a reload, one of them that's already showing stays: it's the one that took)
    if not live then
        local w, h, r = sizeOf(m)
        for _, mode in ipairs(modes) do
            local ww, wh, wr = mode:match("^(%d+)x(%d+)@([%d.]+)$")
            if w == tonumber(ww) and h == tonumber(wh) and sameRate(r, tonumber(wr)) then modes = { mode }; break end
        end
    end
    local function try(i)
        if not modes[i] then trying[out] = nil; return end
        SLATE_HL_MONITOR({ output = out, mode = modes[i], position = "auto", scale = "auto" })
        if not live then return end
        -- Check it took (Hyprland falls back to the old mode when it can't), else the next
        local want = modes[i]
        hl.timer(function()
            for _, now in ipairs(hl.get_monitors() or {}) do
                if now.name == m.name then
                    local w, h, r = sizeOf(now)
                    local ww, wh, wr = want:match("^(%d+)x(%d+)@([%d.]+)$")
                    if not (w == tonumber(ww) and h == tonumber(wh) and sameRate(r, tonumber(wr))) then try(i + 1)
                    else trying[out] = nil end
                end
            end
        end, { timeout = 2500, type = "oneshot" })
    end
    if live then
        if trying[out] then return end
        trying[out] = true
    end
    try(1)
end

-- hl.monitor itself, kept once (a reload runs this again), and a stand-in that notes which
-- monitors are given a mode from here on
SLATE_HL_MONITOR = SLATE_HL_MONITOR or hl.monitor
local function noting(spec)
    if type(spec) == "table" and spec.output and spec.output ~= "" then
        chosen[spec.output] = true
    end
    return SLATE_HL_MONITOR(spec)
end

-- The monitors already here (a reload) get theirs now, before anything chosen loads over it
for _, m in ipairs(hl.get_monitors() or {}) do giveBest(m, false) end

-- Settings → Displays: Slate saves each monitor's mode, position, scale and rotation here
-- (by its description, so they follow the monitor between ports)
hl.monitor = noting
do
    local stateHome = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
    local path = stateHome .. "/slate/displays.lua"
    local f = io.open(path, "r")
    if f then
        f:close()
        local ok, err = pcall(dofile, path)
        if not ok then print("[slate] error in " .. path .. ": " .. tostring(err)) end
    end
end

-- Monitors that arrive later (at login, or plugged in) get theirs as they come, by then
-- knowing what your own monitors.lua chose
local function arrived(m)
    -- (vkms loaded while you're logged in: its screen arrives now, and goes off now)
    if not inTests then
        local test = slateTestScreens()
        for _, now in ipairs(hl.get_monitors() or {}) do
            if test[now.name] and now.enabled ~= false and not isChosen(now) then SLATE_HL_MONITOR({ output = now.name, disabled = true }) end
        end
    end
    if type(m) == "table" and m.name then
        for _, now in ipairs(hl.get_monitors() or {}) do if now.name == m.name then giveBest(now, true) end end
    else
        for _, now in ipairs(hl.get_monitors() or {}) do giveBest(now, true) end
    end
end
hl.on("monitor.added", arrived)
hl.on("hyprland.start", function() arrived(nil) end)
