-- Started with the Slate session. Your own startup apps go in ~/.config/slate/hypr/hyprland.lua

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("hyprctl setcursor " .. CURSOR_THEME .. " " .. CURSOR_SIZE)   -- the cursor theme (variables.lua)
    hl.exec_cmd(SLATE)   -- Slate: the whole desktop shell (bar, dock, wallpaper, panels, lock screen…)
end)
