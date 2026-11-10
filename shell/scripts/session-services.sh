#!/bin/sh
# Started with the Slate session (session/hypr/config/autostart.lua): the things systemd's user
# session starts by itself, for computers that don't have one (Artix, Void, Gentoo…).
#  - Hyprland's environment (the Wayland display and so on) goes to D-Bus, so apps started
#    through it can find the session; to systemd too where it's running.
#  - Sound: PipeWire, its session manager WirePlumber and its PulseAudio stand-in, unless
#    they're already running (another service manager, or your own autostart, may start them).
# With systemd this only does the first.
if [ -d "${SLATE_INIT_ROOT:-}/run/systemd/system" ]; then
    dbus-update-activation-environment --systemd --all
    exit 0
fi
dbus-update-activation-environment --all
running() { pgrep -u "$(id -u)" -x "$1" >/dev/null 2>&1; }
if command -v pipewire >/dev/null 2>&1; then
    running pipewire || { pipewire & sleep 0.5; }
    command -v wireplumber >/dev/null 2>&1 && { running wireplumber || wireplumber & }
    command -v pipewire-pulse >/dev/null 2>&1 && { running pipewire-pulse || pipewire-pulse & }
fi
wait
