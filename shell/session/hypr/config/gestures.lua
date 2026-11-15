-- Touchpad gestures (Settings → Input → Gestures), with three or four fingers:
--   sideways   the next or previous workspace, following your fingers (Hyprland's own swipe)
--   up         the workspace overview; with the desktop showing, the windows come back instead
--   down       shows the desktop, or opens the launcher (Settings → Input → Swiping down);
--              with the overview or the launcher open, it closes that instead
--   pinch in   the launcher; pinching out closes it again
--
-- Slate makes them with setGestures(on, fingers, down), called by slateApply (slate.lua) when
-- Slate starts, when this config reloads and when they change in Settings. Where a gesture of
-- your own (in ~/.config/slate/hypr/hyprland.lua) uses the same fingers and direction, yours
-- is kept and Slate's is left out (see "Making them", below).

-- A Slate command, e.g. slateCall("overview open")
local function slateCall(args) hl.exec_cmd(SLATE .. " ipc call " .. args) end
-- Is one of Slate's overlays open? (slateOverlayOpen is binds.lua's, there under every key set)
local function isOpen(name) return slateOverlayOpen ~= nil and slateOverlayOpen(name) end

-- ---- Show the desktop -----------------------------------------------------------
-- The windows on the workspace you're looking at go to a hidden workspace of their own, and
-- come back to it, in the same order, when you swipe again, open a window, go to another
-- workspace or pick one of them (from the dock, say). Slate's pinned windows (Nova and
-- Settings) stay where they are.
local DESKTOP = "special:slate-desktop"
local hidden = nil          -- { workspace = id, windows = { address, … } } while it's showing
local function moveTo(address, workspace)
    pcall(hl.dispatch, hl.dsp.window.move({ workspace = workspace, window = "address:" .. address, follow = false }))
end
function desktopShowing() return hidden ~= nil end
-- showDesktop(on): true shows the desktop, false brings the windows back, nil switches between them
function showDesktop(on)
    if on == nil then on = hidden == nil end
    if on and not hidden then
        local ws = hl.get_active_workspace()
        if not ws or not ws.id then return end
        local list = {}
        for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
            if w.mapped ~= false and not (slateIsPinned and slateIsPinned(w)) then list[#list + 1] = w.address end
        end
        if #list == 0 then return end
        hidden = { workspace = ws.id, windows = list }
        for _, address in ipairs(list) do moveTo(address, DESKTOP) end
    elseif not on and hidden then
        local was = hidden
        hidden = nil
        for _, address in ipairs(was.windows) do moveTo(address, was.workspace) end
    end
end
-- Anything that means you want your windows again brings them back
local function bringBack() if hidden then showDesktop(false) end end
hl.on("workspace.active", bringBack)
hl.on("workspace.special_active", bringBack)
hl.on("window.open", bringBack)
-- A reload forgets where they came from: any still hidden come back to the workspace you're on
do
    local ok, windows = pcall(hl.get_windows)
    local ws = ok and hl.get_active_workspace() or nil
    for _, w in ipairs(ok and windows or {}) do
        if ws and ws.id and w.workspace and w.workspace.name == DESKTOP then moveTo(w.address, ws.id) end
    end
end

-- ---- What each gesture does ------------------------------------------------------
GESTURE_DOWN = GESTURE_DOWN or "desktop"   -- "desktop" or "launcher" (Settings → Input → Swiping down)
function gestureUp()
    if hidden then showDesktop(false)
    elseif isOpen("slate-launcher") then slateCall("launcher close")
    elseif not isOpen("slate-overview") then slateCall("overview open") end
end
function gestureDown()
    if isOpen("slate-overview") then slateCall("overview close")
    elseif isOpen("slate-launcher") then slateCall("launcher close")
    elseif GESTURE_DOWN == "launcher" then slateCall("launcher open")
    else showDesktop() end
end
function gesturePinch(inward)
    if inward then
        if not isOpen("slate-launcher") then slateCall("launcher open") end
    elseif isOpen("slate-launcher") then slateCall("launcher close") end
end

-- ---- Making them ------------------------------------------------------------------
-- Hyprland keeps one gesture per fingers and direction, and refuses one that an earlier one
-- would hide (in a message, not a Lua error, so it can't be caught). So the gestures anything
-- else makes (your own files, which load after this one) are noted as they're made, and Slate
-- leaves out any of its own they'd clash with. SLATE_HL_GESTURE is Hyprland's own hl.gesture,
-- which Slate makes its own with.
SLATE_HL_GESTURE = SLATE_HL_GESTURE or hl.gesture
local theirs = {}           -- [fingers][direction] = true
local function directionOf(d)
    d = tostring(d or ""):lower()
    return ({ horiz = "horizontal", zoomin = "pinchin", zoomout = "pinchout" })[d] or d
end
hl.gesture = function(g, ...)
    if type(g) == "table" and tonumber(g.fingers) and not g.mods then
        local f = tonumber(g.fingers)
        theirs[f] = theirs[f] or {}
        theirs[f][directionOf(g.direction)] = g.action ~= "unset" or nil
    end
    return SLATE_HL_GESTURE(g, ...)
end
-- The directions of theirs that would clash with each of Slate's
local CLASHES = {
    horizontal = { "horizontal", "left", "right", "swipe" },
    up         = { "up", "vertical", "swipe" },
    down       = { "down", "vertical", "swipe" },
    pinchin    = { "pinchin", "pinch" },
    pinchout   = { "pinchout", "pinch" },
}
local function clashes(fingers, direction)
    for _, d in ipairs(CLASHES[direction]) do
        if theirs[fingers] and theirs[fingers][d] then return true end
    end
    return false
end

-- Which Slate made (fingers, direction), so they can be taken away again without touching
-- yours, and what they were made for, so they're only made again when that changes
local made, madeFor = {}, nil
function setGestures(on, fingers, down)
    GESTURE_DOWN = down == "launcher" and "launcher" or "desktop"
    fingers = fingers == 4 and 4 or 3
    local want = on and tostring(fingers) or "off"
    if want == madeFor then return end
    madeFor = want
    for _, g in ipairs(made) do
        SLATE_HL_GESTURE({ fingers = g.fingers, direction = g.direction, action = "unset" })
    end
    made = {}
    if not on then return end
    -- (each action looks up what to do when it happens, so a change to GESTURE_DOWN needs
    -- nothing made again)
    for _, g in ipairs({
        { "horizontal", "workspace" },
        { "up",         function() gestureUp() end },
        { "down",       function() gestureDown() end },
        { "pinchin",    function() gesturePinch(true) end },
        { "pinchout",   function() gesturePinch(false) end },
    }) do
        if not clashes(fingers, g[1]) then
            SLATE_HL_GESTURE({ fingers = fingers, direction = g[1], action = g[2] })
            made[#made + 1] = { fingers = fingers, direction = g[1] }
        end
    end
end
