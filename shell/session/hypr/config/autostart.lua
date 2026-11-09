-- Started with the Slate session. Your own startup commands go in ~/.config/slate/hypr/autostart.lua
-- (or Settings → Startup Apps)

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("hyprctl setcursor " .. CURSOR_THEME .. " " .. CURSOR_SIZE)   -- the cursor theme (variables.lua)
    -- The tray's register, before Slate, so it outlives Slate's restarts (scripts/tray-watcher.py)
    hl.exec_cmd(SLATE_DIR .. "/scripts/tray-watcher.py")
    hl.exec_cmd(SLATE)   -- Slate: the whole desktop shell (bar, dock, wallpaper, panels, lock screen…)
end)
