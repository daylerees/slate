-- Workspace rules: https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Add your own in ~/.config/slate/hypr/hyprland.lua, e.g. workspaces on a second monitor:
--   hl.workspace_rule({ workspace = "4", monitor = MONITOR2, default = true, persistent = true })
-- or a different layout:
--   hl.workspace_rule({ workspace = "1", monitor = MONITOR1, layout = "scrolling" })

-- The "gaming" workspace games are sent to (windowrules.lua), on the main monitor
hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR, default = true })
-- The first three workspaces live on the first monitor
hl.workspace_rule({ workspace = "1", monitor = MONITOR1, default = true })
hl.workspace_rule({ workspace = "2", monitor = MONITOR1, default = true })
hl.workspace_rule({ workspace = "3", monitor = MONITOR1, default = true })

-- A lone (or maximised) window has no gaps, so it fills the screen up to the bar.
-- Slate replaces the lone-window one with the padding set in Settings → Windows
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

-- besideWorkspace(dir): an empty workspace directly to the right (dir = 1) or left
-- (dir = -1) of the current one, returned by number. Uses a free number next to the
-- current workspace if there is one; otherwise shifts the following workspaces' windows
-- up by one to make room. Used by the app launcher (Left/Right on an app), e.g.
--   hyprctl dispatch 'function() fadeTo(hl.dsp.focus({ workspace = besideWorkspace(1) })) end'
function besideWorkspace(dir)
    local cur = hl.get_active_workspace().id
    local used = {}
    local maxId = cur
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id and w.id > 0 and (w.windows or 0) > 0 then
            used[w.id] = true
            if w.id > maxId then maxId = w.id end
        end
    end
    -- Move every window on workspaces from..maxId up by one (highest first)
    local function shiftFrom(from)
        for id = maxId, from, -1 do
            for _, win in ipairs(hl.get_workspace_windows(id) or {}) do
                hl.dispatch(hl.dsp.window.move({ workspace = id + 1, window = "address:" .. win.address, follow = false }))
            end
        end
    end
    if dir > 0 then
        local target = cur + 1
        if used[target] then shiftFrom(target) end
        return target
    else
        local target = cur - 1
        if target >= 1 and not used[target] then return target end
        shiftFrom(cur)          -- the current workspace moves one along; its number is now free
        return cur
    end
end

-- newWorkspace(movingAddr): where "on a new workspace" goes (Super+W, Super+Return in the
-- launcher): the number after the last workspace with windows, so new workspaces join the
-- end rather than filling a gap earlier on. With "keep an empty workspace" on, that's the
-- spare one. When moving a window (its address given), it doesn't count; a window already
-- alone on its workspace stays there.
--   hyprctl dispatch 'function() hl.dispatch(hl.dsp.focus({ workspace = newWorkspace() })) end'
function newWorkspace(movingAddr)
    local maxId, ownId, ownAlone = 0, nil, false
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id and w.id > 0 then
            local n = w.windows or 0
            if movingAddr then
                for _, win in ipairs(hl.get_workspace_windows(w.id) or {}) do
                    if win.address == movingAddr then
                        n = n - 1
                        ownId, ownAlone = w.id, n == 0
                    end
                end
            end
            if n > 0 and w.id > maxId then maxId = w.id end
        end
    end
    if ownAlone then return ownId end
    return maxId + 1
end

-- Keep an empty workspace (Settings → Workspaces): there's always one empty workspace after the
-- last one in use, ready for a new window, like GNOME. Hyprland only keeps an empty workspace
-- that's marked persistent, so the mark moves to the number after the highest workspace with
-- windows whenever windows open, close or move. Slate turns it on and off (setSpareWorkspace).
local spareOn, spareId = false, nil
function updateSpareWorkspace()
    local want = nil
    if spareOn then
        local maxId = 0
        for _, w in ipairs(hl.get_workspaces()) do
            if w.id and w.id > 0 and (w.windows or 0) > 0 and w.id > maxId then maxId = w.id end
        end
        want = maxId + 1
        -- Always the last one: if you're on an empty workspace further along, that one is the
        -- spare (rather than leaving another empty one before it)
        local cur = hl.get_active_workspace()
        if cur and cur.id and cur.id > want and (cur.windows or 0) == 0 then want = cur.id end
    end
    if want == spareId then return end
    if spareId then hl.workspace_rule({ workspace = tostring(spareId), persistent = false }) end
    if want then hl.workspace_rule({ workspace = tostring(want), persistent = true }) end
    spareId = want
end
function setSpareWorkspace(on)
    spareOn = on
    updateSpareWorkspace()
end
-- After the change has landed (a closing window still counts for a moment)
local function spareSoon()
    if spareOn then hl.timer(updateSpareWorkspace, { timeout = 150, type = "oneshot" }) end
end
hl.on("window.open", spareSoon)
hl.on("window.close", spareSoon)
hl.on("window.destroy", spareSoon)
hl.on("window.move_to_workspace", spareSoon)
hl.on("workspace.active", spareSoon)
