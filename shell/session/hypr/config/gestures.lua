-- Touchpad gestures (Settings → Input → Gestures), with three or four fingers:
--   left, right, up, down, pinch in, pinch out
--              each one of: "overview" (the workspace overview), "desktop" (show the desktop),
--              "launcher", or "none" (no gesture of Slate's there, so it's free for your own);
--              left and right can also be "workspace": Hyprland's own workspace swipe, which
--              follows your fingers. With both, it's one gesture both ways ("horizontal"); with
--              one, Hyprland's swipe starts only that way (with its usual direction, left goes to
--              the next workspace and right to the previous one), and the other is free.
--              Up and down don't offer it: Hyprland would slide the workspaces sideways under
--              fingers moving up and down, with Slate's usual sideways animation
-- Each opens its own thing and, done again, closes it. While the overview or the launcher is
-- open, or the desktop is showing, any of them puts that away first.
--
-- Pinches take as many fingers as swipes do (three or four): two-finger pinches are left to
-- your apps, for zooming. Some touchpads can't tell three fingers pinching from swiping.
--
-- Slate makes them with setGestures({ on, fingers, left, right, up, down, pinchin, pinchout }),
-- called by slateApply (slate.lua) when Slate starts, when this config reloads and when they
-- change in Settings. Where a gesture of your own (in ~/.config/slate/hypr/hyprland.lua) uses
-- the same fingers and direction, yours is kept and Slate's is left out (see "Making them").

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
-- What each direction does (Settings → Input → Swipe up…): "overview", "desktop", "launcher" or
-- "none", and for left and right "workspace" too
GESTURE_ACTIONS = GESTURE_ACTIONS or { left = "workspace", right = "workspace", up = "overview", down = "desktop",
                                       pinchin = "launcher", pinchout = "none" }
-- Put away whatever a gesture opened: true if something was
local function putAway()
    if hidden then showDesktop(false); return true end
    if isOpen("slate-overview") then slateCall("overview close"); return true end
    if isOpen("slate-launcher") then slateCall("launcher close"); return true end
    return false
end
-- gestureDo(action): what a gesture does, as Hyprland calls it when the gesture ends
function gestureDo(action)
    if action == nil or action == "none" or action == "workspace" then return end
    if putAway() then return end
    if action == "overview" then slateCall("overview open")
    elseif action == "launcher" then slateCall("launcher open")
    elseif action == "desktop" then showDesktop(true) end
end
-- gesture(direction): the gesture in that direction ("left", "up", "pinchin"…). ("workspace" is
-- Hyprland's own, never one of these)
function gesture(direction) gestureDo(GESTURE_ACTIONS[direction]) end

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
    left       = { "left", "horizontal", "swipe" },
    right      = { "right", "horizontal", "swipe" },
    up         = { "up", "vertical", "swipe" },
    down       = { "down", "vertical", "swipe" },
    pinchin    = { "pinchin", "pinch" },
    pinchout   = { "pinchout", "pinch" },
}
-- Slate's pinch in is fingers coming together; Hyprland names pinches by zoom, so its "pinchin" is
-- fingers spreading apart. Anything handed to Hyprland (or compared with yours) goes through this.
local HYPR_DIRECTION = { pinchin = "pinchout", pinchout = "pinchin" }
local function hyprDirection(d) return HYPR_DIRECTION[d] or d end
local function clashes(fingers, direction)
    for _, d in ipairs(CLASHES[direction]) do
        if theirs[fingers] and theirs[fingers][d] then return true end
    end
    return false
end

-- Which Slate made (fingers, direction), so they can be taken away again without touching
-- yours, and what they were made for, so they're only made again when that changes
local made, madeFor = {}, nil
local ACTIONS = { overview = true, desktop = true, launcher = true, none = true }
local DIRECTIONS = { "left", "right", "up", "down", "pinchin", "pinchout" }
local SIDEWAYS = { left = true, right = true }
function setGestures(t)
    t = t or {}
    local fingers = t.fingers == 4 and 4 or 3
    for _, d in ipairs(DIRECTIONS) do
        if ACTIONS[t[d]] or (SIDEWAYS[d] and t[d] == "workspace") then GESTURE_ACTIONS[d] = t[d] end
    end
    -- Which directions get one of Slate's, and what each does there: Hyprland's workspace swipe
    -- (one "horizontal" when both left and right have it, unless one of yours is in the way),
    -- or Slate's own; "none" gets nothing
    local wanted = {}
    if t.on then
        local a = GESTURE_ACTIONS
        local both = a.left == "workspace" and a.right == "workspace" and not clashes(fingers, "horizontal")
        if both then wanted[#wanted + 1] = { "horizontal", "workspace" } end
        for _, d in ipairs(DIRECTIONS) do
            if not (both and SIDEWAYS[d]) and a[d] ~= "none" and not clashes(fingers, hyprDirection(d)) then
                wanted[#wanted + 1] = { d, a[d] == "workspace" and "workspace" or "slate" }
            end
        end
    end
    local key = {}
    for _, w in ipairs(wanted) do key[#key + 1] = w[1] .. "=" .. w[2] end
    local want = fingers .. ":" .. table.concat(key, ",")
    if want == madeFor then return end
    madeFor = want
    for _, g in ipairs(made) do
        SLATE_HL_GESTURE({ fingers = g.fingers, direction = g.direction, action = "unset" })
    end
    made = {}
    -- (Slate's own look up what to do when they happen, so changing between those needs nothing
    -- made again; only "none" or "workspace", which change what Hyprland has)
    for _, w in ipairs(wanted) do
        local d = w[1]
        local action = w[2] == "workspace" and "workspace" or function() gesture(d) end
        SLATE_HL_GESTURE({ fingers = fingers, direction = hyprDirection(d), action = action })
        made[#made + 1] = { fingers = fingers, direction = hyprDirection(d) }
    end
end
