-- Animations: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
-- Slate's own overlays (launcher, switcher, panels…) animate themselves; these are for
-- windows and workspaces.

-- Curves
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })   -- fast start, gentle stop
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
-- Starts slowly then speeds up: an outgoing workspace stays visible while the new one covers it
hl.curve("lingerFade",     { type = "bezier", points = { {0.55, 0},    {0.9, 0.4}   } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 500, dampening = 35 })

-- Animation speed (Settings → Appearance → Animations): "normal", "fast" (about 40%
-- quicker) or "off". Every speed below goes through sp() so the setting scales them all.
local ANIM_SCALE = 1
local function sp(x) return x * ANIM_SCALE end

-- The fixed animations (windows, workspaces, the special workspace), at the current speed
local function defineLeaves()
-- Windows
hl.animation({ leaf = "global",              enabled = true, speed = sp(3), bezier = "quick" })
hl.animation({ leaf = "windows",             enabled = true, speed = sp(3), spring = "easy", style = "slide" })
-- New windows fade in while growing from the centre; closing reverses it
hl.animation({ leaf = "windowsIn",           enabled = true, speed = sp(3), bezier = "easeOutQuint", style = "popin 85%" })
hl.animation({ leaf = "windowsOut",          enabled = true, speed = sp(2), bezier = "easeOutQuint", style = "popin 85%" })

-- Workspaces: the incoming one slides and fades in over the outgoing one, which stays put
-- and fades out underneath. The incoming one has mostly landed after ~0.2 s, so the
-- outgoing one is gone by 0.3 s; any longer and it shows through the gaps and translucent
-- borders between the new workspace's windows.
hl.animation({ leaf = "workspaces",          enabled = true, speed = sp(5), bezier = "quick", style = "slide" })
-- Special workspace (scratchpad): slides down from above and fades in over what's
-- underneath; closing reverses it
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = sp(5), bezier = "easeOutQuint", style = "slidefadevert -100%" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = sp(5), bezier = "easeOutQuint", style = "slidefadevert -100%" })
end
defineLeaves()
local function slideWorkspaces()
    hl.animation({ leaf = "workspacesIn",    enabled = true, speed = sp(5), bezier = "easeOutQuint", style = "slidefade 100%" })
    hl.animation({ leaf = "workspacesOut",   enabled = true, speed = sp(3), bezier = "lingerFade", style = "fade" })
end
slideWorkspaces()
-- Wrapping from the last workspace to the first (and back) slides in the direction of
-- travel. binds.lua switches this per press, as it only makes sense when a press wraps.
hl.config({ animations = { workspace_wraparound = true } })

-- fadeTo(dispatcher): switch with a crossfade instead of the slide, then put the slide
-- back. Used by Slate's window switcher, launcher (Super+Return) and workspace overview:
--   hyprctl dispatch 'function() fadeTo(hl.dsp.focus({ workspace = 3 })) end'
local restoreTimer = nil
function fadeTo(dispatcher)
    -- The new workspace fades in evenly on top; the old one stays solid underneath until
    -- it's mostly covered, so there's no darkening dip halfway through
    hl.animation({ leaf = "workspacesIn",    enabled = true, speed = sp(3.5), bezier = "easeInOutCubic", style = "fade" })
    hl.animation({ leaf = "workspacesOut",   enabled = true, speed = sp(3.5), bezier = "lingerFade", style = "fade" })
    hl.dispatch(dispatcher)
    if restoreTimer then restoreTimer:set_enabled(false) end
    restoreTimer = hl.timer(function() restoreTimer = nil; slideWorkspaces() end, { timeout = 600, type = "oneshot" })
end

-- instantTo(dispatcher): switch with no animation at all, for when something covering the
-- screen (like the workspace overview) fades out to reveal the new workspace
function instantTo(dispatcher)
    hl.animation({ leaf = "workspacesIn",    enabled = false })
    hl.animation({ leaf = "workspacesOut",   enabled = false })
    hl.dispatch(dispatcher)
    if restoreTimer then restoreTimer:set_enabled(false) end
    restoreTimer = hl.timer(function() restoreTimer = nil; slideWorkspaces() end, { timeout = 300, type = "oneshot" })
end

-- setAnimationSpeed(mode): "normal", "fast" or "off" (called by slateApply, slate.lua)
function setAnimationSpeed(mode)
    if mode == "off" then
        hl.config({ animations = { enabled = false } })
        return
    end
    ANIM_SCALE = mode == "fast" and 0.6 or 1
    hl.config({ animations = { enabled = true } })
    defineLeaves()
    slideWorkspaces()
end
