-- Started with the Slate session. Your own startup commands go in ~/.config/slate/hypr/autostart.lua
-- (or Settings → Startup Apps)

hl.on("hyprland.start", function ()
    -- Hyprland's environment to D-Bus (and systemd), and, without systemd, sound (PipeWire):
    -- scripts/session-services.sh
    hl.exec_cmd(SLATE_DIR .. "/scripts/session-services.sh")
    hl.exec_cmd("hyprctl setcursor " .. CURSOR_THEME .. " " .. CURSOR_SIZE)   -- the cursor theme (variables.lua)
    -- The tray's register, before Slate, so it outlives Slate's restarts (scripts/tray-watcher.py)
    hl.exec_cmd(SLATE_DIR .. "/scripts/tray-watcher.py")
    hl.exec_cmd(SLATE)   -- Slate: the whole desktop shell (bar, dock, wallpaper, panels, lock screen…)
end)
