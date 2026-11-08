#!/bin/sh
# Session actions for Slate:  session.sh logout|reboot|shutdown
# Log out ends Hyprland (through uwsm when it manages the session, so it can stop the
# session's services cleanly); restart and shut down go to systemd.
case "$1" in
    logout)
        if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then exec uwsm stop; fi
        exec hyprctl dispatch 'hl.dsp.exit()' ;;
    reboot)   exec systemctl reboot ;;
    shutdown|poweroff) exec systemctl poweroff ;;
    *) echo "usage: $0 logout|reboot|shutdown" >&2; exit 1 ;;
esac
