-- Minimal Hyprland for the Slate login screen (run by greetd as the "greeter" user).
-- It only shows the greeter, then exits so greetd can start your session.

hl.config({
    input = {
        kb_layout = "__KB_LAYOUT__",
    },
    general = { border_size = 0, gaps_in = 0, gaps_out = 0 },
    decoration = { rounding = 0 },
    animations = { enabled = false },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        background_color = 0xff0f1216,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- ---- Your displays, as your desktop has them --------------------------------------------
-- A monitor changing mode goes black for a few seconds while it catches up. In a mode of its own
-- (the monitor's recommended one), the login screen meant that twice at every login, once at
-- the start and again as your desktop changed it back, and a face could be recognized while it
-- was black, so the login screen was never seen. So each monitor starts as your desktop shows it:
-- slate-greeter-sync writes them to the login screen's folder, one a line, tab separated
-- (description, mode, scale, rotation, x, y, HDR, SDR brightness, SDR saturation). It's data
-- from your account, so every field is checked and anything that isn't right is skipped. A
-- monitor that isn't listed (a new one) gets Hyprland's own choice, as before.
local function num(s, lo, hi)
    local n = tonumber(s)
    if n and n == n and n >= lo and n <= hi then return n end
end
function slateGreeterDisplays(path)
    local out = {}
    local f = io.open(path, "r")
    if not f then return out end
    for line in f:lines() do
        local p = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(p, field) end
        local desc, mode, hdr = p[1] or "", p[2] or "", p[7] or ""
        local scale, transform = num(p[3], 0.25, 10), num(p[4], 0, 7)
        local x, y = num(p[5], -100000, 100000), num(p[6], -100000, 100000)
        local w, h, r = mode:match("^(%d+)x(%d+)@(%d+%.?%d*)$")
        if desc ~= "" and #desc <= 200 and not desc:find("%c") and w and num(w, 1, 20000) and num(h, 1, 20000)
            and num(r, 1, 1000) and scale and transform and transform % 1 == 0 and x and y
            and (hdr == "" or hdr == "on" or hdr == "off" or hdr == "auto") then
            local spec = { output = "desc:" .. desc, disabled = false, mode = mode, scale = scale, transform = transform,
                           position = string.format("%dx%d", math.floor(x), math.floor(y)) }
            -- (as Settings → Displays writes them: Displays.qml's luaFor)
            if hdr == "on" then
                spec.cm, spec.bitdepth, spec.supports_hdr = "hdr", 10, 0
                spec.sdrbrightness, spec.sdrsaturation = num(p[8], 0, 5) or 1, num(p[9], 0, 5) or 1
            elseif hdr == "off" then
                spec.cm, spec.bitdepth, spec.supports_hdr = "auto", 8, -1
            elseif hdr == "auto" then
                spec.cm, spec.supports_hdr = "auto", 0
            end
            table.insert(out, spec)
        end
    end
    f:close()
    return out
end

-- A mode that doesn't take (the cable or the card can't carry it now, and Hyprland falls back):
-- the next slower rate at that size, as your desktop does
local function sizeOf(m)
    local mode = type(m.mode) == "table" and m.mode or m
    return mode.width or m.width, mode.height or m.height, mode.refresh_rate or m.refresh_rate or 0
end
local function settle(spec)
    hl.timer(function()
        for _, m in ipairs(hl.get_monitors() or {}) do
            if m.description and "desc:" .. m.description == spec.output then
                local w, h, r = sizeOf(m)
                local ww, wh, wr = spec.mode:match("^(%d+)x(%d+)@([%d.]+)$")
                ww, wh, wr = tonumber(ww), tonumber(wh), tonumber(wr)
                if w == ww and h == wh and math.abs(r - wr) < 0.5 then return end
                local slower
                for _, am in ipairs(m.available_modes or {}) do
                    local ar = am.refresh_rate or 0
                    if am.width == ww and am.height == wh and ar < wr - 0.5 and (not slower or ar > slower) then slower = ar end
                end
                if not slower then return end
                spec.mode = string.format("%dx%d@%.2f", ww, wh, slower)
                hl.monitor(spec)
                settle(spec)
            end
        end
    end, { timeout = 2500, type = "oneshot" })
end

local yourDisplays = slateGreeterDisplays(SLATE_GREETER_DISPLAYS or "/var/lib/slate-greeter/displays")
for _, spec in ipairs(yourDisplays) do hl.monitor(spec) end

hl.on("hyprland.start", function ()
    hl.exec_cmd("/usr/local/share/slate-greeter/run-greeter.sh")
    for _, spec in ipairs(yourDisplays) do settle(spec) end
end)
