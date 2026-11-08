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

hl.on("hyprland.start", function ()
    hl.exec_cmd("/usr/local/share/slate-greeter/run-greeter.sh")
end)
