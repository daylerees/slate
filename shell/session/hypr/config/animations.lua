-- Animations: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- Slate's own overlays (launcher, switcher, panels…) animate themselves; these are for
-- windows and workspaces.

-- Curves
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })   -- fast start, gentle stop
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
-- Starts slowly then speeds up: an outgoing workspace stays visible while the new one covers it
hl.curve("lingerFade",     { type = "bezier", points = { {0.55, 0},    {0.9, 0.4}   } })
-- Stays as it is until near the end, then goes quickly: an outgoing workspace is solid under the
-- incoming one until that has all but arrived, so the desktop never shows in the strip the new
-- one hasn't reached yet
hl.curve("holdFade",       { type = "bezier", points = { {0.92, 0},    {0.98, 0.1}  } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 500, dampening = 35 })

-- Animation speed (Settings → Appearance → Animations): "normal", "fast" (about 40%
-- quicker) or "off". Every speed below goes through sp() so the setting scales them all.
local ANIM_SCALE = 1
local ANIM_OFF = false
-- (SLATE_ANIM_SLOW: the tests slow every animation down by that much, to take pictures partway)
local function sp(x) return x * ANIM_SCALE * (SLATE_ANIM_SLOW or 1) end

-- The fixed animations (windows, workspaces, the special workspace), at the current speed
local function defineLeaves()
    -- Windows
    hl.animation({ leaf = "global",              enabled = true, speed = sp(3), bezier = "quick" })
    hl.animation({ leaf = "windows",             enabled = true, speed = sp(3), spring = "easy", style = "slide" })
    -- New windows fade in while growing from the centre; closing reverses it
    hl.animation({ leaf = "windowsIn",           enabled = true, speed = sp(3), bezier = "easeOutQuint", style = "popin 85%" })
    hl.animation({ leaf = "windowsOut",          enabled = true, speed = sp(2), bezier = "easeOutQuint", style = "popin 85%" })

    -- Workspaces: the parent of workspacesIn/Out, which draw the switch itself (slideWorkspaces
    -- below: by default the incoming one slides and fades in over the outgoing one, which
    -- stays put, solid, until the new one has all but covered it, then fades away under it)
    hl.animation({ leaf = "workspaces",          enabled = true, speed = sp(5), bezier = "quick", style = "slide" })
    -- Special workspace (scratchpad): slides down from above and fades in over what's
    -- underneath; closing reverses it
    hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = sp(5), bezier = "easeOutQuint", style = "slidefadevert -100%" })
    hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = sp(5), bezier = "easeOutQuint", style = "slidefadevert -100%" })
end
defineLeaves()
-- How switching workspace looks (Settings → Workspaces → Workspace switching); Slate sets it
-- with setWorkspaceAnimation(style) when it starts, when this config reloads and when it
-- changes:
--   slidefade      the new workspace slides in over the old, which fades underneath (default)
--   slidefadevert  the same, up and down
--   slide          both slide along together, like pages
--   slidevert      the same, up and down
--   crossfade      the new one fades in over the old
--   none           straight there
WORKSPACE_ANIM = WORKSPACE_ANIM or "slidefade"
local function slideWorkspaces()
    local a = WORKSPACE_ANIM
    local function set(leaf, speed, bezier, style)
        hl.animation({ leaf = leaf, enabled = true, speed = sp(speed), bezier = bezier, style = style })
    end
    if a == "none" then
        hl.animation({ leaf = "workspacesIn",  enabled = false })
        hl.animation({ leaf = "workspacesOut", enabled = false })
    elseif a == "slide" or a == "slidevert" then
        set("workspacesIn",  5, "easeOutQuint", a)
        set("workspacesOut", 5, "easeOutQuint", a)
    elseif a == "crossfade" then
        set("workspacesIn",  3.5, "easeInOutCubic", "fade")
        set("workspacesOut", 3.5, "lingerFade", "fade")
    else
        set("workspacesIn",  5, "easeOutQuint", a == "slidefadevert" and "slidefadevert 100%" or "slidefade 100%")
        set("workspacesOut", 5, "holdFade", "fade")
    end
end
function setWorkspaceAnimation(style)
    WORKSPACE_ANIM = style or "slidefade"
    slideWorkspaces()
end
slideWorkspaces()
-- Wrapping from the last workspace to the first (and back) slides in the direction of
-- travel. binds.lua switches this per press, as it only makes sense when a press wraps.
hl.config({ animations = { workspace_wraparound = true } })

-- fadeTo(dispatcher): switch with a crossfade instead of the slide, then put the slide
-- back. Used by Slate's window switcher, launcher (Super+Return) and workspace overview:
--   hyprctl dispatch 'function() fadeTo(hl.dsp.focus({ workspace = 3 })) end'
local restoreTimer = nil
-- After one of these switches: the usual workspace animation comes back once it's done
local function restoreSlideAfter(ms)
    if restoreTimer then restoreTimer:set_enabled(false) end
    restoreTimer = hl.timer(function() restoreTimer = nil; slideWorkspaces() end, { timeout = ms, type = "oneshot" })
end
function fadeTo(dispatcher)
    -- The new workspace fades in evenly on top; the old one stays solid underneath until
    -- it's mostly covered, so there's no darkening dip halfway through
    hl.animation({ leaf = "workspacesIn",    enabled = true, speed = sp(3.5), bezier = "easeInOutCubic", style = "fade" })
    hl.animation({ leaf = "workspacesOut",   enabled = true, speed = sp(3.5), bezier = "lingerFade", style = "fade" })
    hl.dispatch(dispatcher)
    restoreSlideAfter(600)
end

-- instantTo(dispatcher): switch with no animation at all, for when something covering the
-- screen (like the workspace overview) fades out to reveal the new workspace
function instantTo(dispatcher)
    hl.animation({ leaf = "workspacesIn",    enabled = false })
    hl.animation({ leaf = "workspacesOut",   enabled = false })
    hl.dispatch(dispatcher)
    restoreSlideAfter(300)
end

-- squareWhileSliding(): windows lose their rounded corners for as long as a workspace switch
-- that slides takes, and get them back after, so nothing shows past a moving window's corners
-- (windowrules.lua has the rule; a crossfade and a straight switch move nothing, so they keep them)
local roundTimer = nil
function squareWhileSliding()
    if not SLIDE_SQUARE_RULE or ANIM_OFF or WORKSPACE_ANIM == "crossfade" or WORKSPACE_ANIM == "none" then return end
    SLIDE_SQUARE_RULE:set_enabled(true)
    if roundTimer then roundTimer:set_enabled(false) end
    roundTimer = hl.timer(function() roundTimer = nil; SLIDE_SQUARE_RULE:set_enabled(false) end,
                          { timeout = math.floor(sp(5) * 100 + 40), type = "oneshot" })
end

-- noteWorkspaceSwitch(): called as a slide starts. The workspace left behind holds, fully there,
-- until the new one has arrived (holdFade), so the desktop never shows between them. But switching
-- through several quickly, each held one stayed behind the next, and the first showed through every
-- workspace passed (a bright window could be made out behind each). So a switch that starts while
-- the last is still under way lets the old workspaces fade straight away; the hold comes back once
-- things have settled
local switching, switchTimer = false, nil
function noteWorkspaceSwitch()
    if ANIM_OFF or (WORKSPACE_ANIM ~= "slidefade" and WORKSPACE_ANIM ~= "slidefadevert") then return end
    if switching then
        hl.animation({ leaf = "workspacesOut", enabled = true, speed = sp(1.5), bezier = "quick", style = "fade" })
    end
    switching = true
    if switchTimer then switchTimer:set_enabled(false) end
    switchTimer = hl.timer(function() switchTimer = nil; switching = false; slideWorkspaces() end,
                           { timeout = math.floor(sp(5) * 100 + 60), type = "oneshot" })
end

-- slideAwayTo(dispatcher): to an empty workspace, the windows slide away in the direction of
-- travel. (With Slide Fade the new workspace slides in over the old, which fades underneath;
-- with nothing coming in, the windows would just fade out where they are.) The other styles
-- already move the old workspace, so they switch as usual.
function slideAwayTo(dispatcher)
    local a = WORKSPACE_ANIM
    if a ~= "slidefade" and a ~= "slidefadevert" then hl.dispatch(dispatcher); return end
    hl.animation({ leaf = "workspacesOut", enabled = true, speed = sp(5), bezier = "easeOutQuint",
                   style = a == "slidefadevert" and "slidefadevert 100%" or "slidefade 100%" })
    hl.dispatch(dispatcher)
    -- (not before the slide's over: the usual animation holds a workspace that's leaving solid
    -- where it was, so put back partway through, the windows sliding away showed again in place)
    restoreSlideAfter(math.floor(sp(5) * 100 + 80))
end

-- Slate's own title bars (TitleBar.qml): dragging one moves its window to each pointer position
-- (x, y: Hyprland coordinates), with the move animation off meanwhile so the window keeps up
-- with the pointer rather than trailing it; slateDragEnd() puts the animation back
local dragging = false
function slateDragMove(address, x, y)
    if not dragging then
        dragging = true
        hl.animation({ leaf = "windowsMove", enabled = false })
    end
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = "address:" .. address }))
end
-- Slate's maximise and restore (its own title bars): a window's top left (x, y) and size, moving
-- as windows usually do. flat: maximised, filling the screen with only Slate's bar above it, so
-- no border, rounding or shadow (false puts them back)
function slateFlat(address, flat)
    local win = "address:" .. address
    local v = flat and "0" or "unset"
    hl.dispatch(hl.dsp.window.set_prop({ prop = "border_size", value = v, window = win }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "rounding", value = v, window = win }))
    hl.dispatch(hl.dsp.window.set_prop({ prop = "no_shadow", value = flat and "1" or "unset", window = win }))
end
function slatePlace(address, x, y, w, h, flat)
    local win = "address:" .. address
    slateFlat(address, flat)
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
end

-- Resizing from a title bar's corner: its top left (x, y) and size (w, h), at once
function slateDragResize(address, x, y, w, h)
    if not dragging then
        dragging = true
        hl.animation({ leaf = "windowsMove", enabled = false })
    end
    local win = "address:" .. address
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, window = win }))
    hl.dispatch(hl.dsp.window.move({ x = x, y = y, window = win }))
end
function slateDragEnd()
    dragging = false
    hl.animation({ leaf = "windowsMove", enabled = true, speed = sp(3), spring = "easy", style = "slide" })
end

-- setAnimationSpeed(mode): "normal", "fast" or "off" (called by slateApply, slate.lua)
function setAnimationSpeed(mode)
    ANIM_OFF = mode == "off"
    if mode == "off" then
        hl.config({ animations = { enabled = false } })
        return
    end
    ANIM_SCALE = mode == "fast" and 0.6 or 1
    hl.config({ animations = { enabled = true } })
    defineLeaves()
    slideWorkspaces()
end
