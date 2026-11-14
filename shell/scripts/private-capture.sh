#!/bin/sh
# Private Mode (PrivateMode.qml): screen sharing and recording through the desktop portal off,
# and back. The portal's screen capture is the compositor's portal backend (Hyprland's, or the
# wlroots one), which apps reach through D-Bus: stopped, and held stopped, it can't be started.
#   private-capture.sh off    stop it, and keep it from starting (systemd: masked until you log out)
#   private-capture.sh on     let it start again (the next app that asks starts it)
#   private-capture.sh keep   while off, without systemd: stop it again if something started it
set -u
backends="xdg-desktop-portal-hyprland xdg-desktop-portal-wlr"

have_systemd() { command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; }

# (by its whole command line: a process name stops at 15 characters. Only the program itself,
# at the start of the line with or without its folder: the bare name matched anything of yours
# that mentioned it, like an editor open on its config or `journalctl -fu` following it. The
# dot and "-wrapped" are how NixOS names a program it wraps)
stop_all() { for b in $backends; do pkill -u "$(id -u)" -f "^([^ ]*/)?\\.?$b(-wrapped)?( |\$)" 2>/dev/null; done; }

case "${1:-}" in
    off)
        if have_systemd; then
            for b in $backends; do systemctl --user mask --runtime --now "$b.service" >/dev/null 2>&1; done
        fi
        stop_all
        ;;
    on)
        if have_systemd; then
            for b in $backends; do systemctl --user unmask --runtime "$b.service" >/dev/null 2>&1; done
        fi
        ;;
    keep)
        have_systemd || stop_all
        ;;
    *)
        echo "usage: private-capture.sh off | on | keep" >&2
        exit 2
        ;;
esac
exit 0
