#!/bin/sh
# Session actions for Slate:  session.sh logout|reboot|shutdown [sound volume, 0-1] [reopen]
# Log out ends Hyprland (through uwsm when it manages the session, so it can stop the
# session's services cleanly); restart and shut down go to systemd.
# Restarting with "reopen" first keeps the open apps and where they are, so the next login
# opens them again (spaces.py session-save); anything else forgets apps kept earlier.
# With a volume, the goodbye sound (Settings → Sound) plays to the end first, so it's heard
# before the session closes (at most 3 seconds, in case the sound system is stuck).
sound="$(dirname "$0")/../sounds/goodbye.wav"
case "$1" in logout|reboot|shutdown|poweroff)
    # Keep (or forget) the open apps, then the goodbye sound
    if [ "$1" = reboot ] && [ "$3" = reopen ]; then python3 "$(dirname "$0")/spaces.py" session-save
    else python3 "$(dirname "$0")/spaces.py" session-forget; fi
    if [ -n "$2" ] && [ "$2" != "0" ] && [ -e "$sound" ]; then
        timeout 3 pw-play --volume="$2" "$sound" 2>/dev/null \
            || timeout 3 paplay --volume="$(awk -v v="$2" 'BEGIN { printf "%d", v * 65536 }')" "$sound" 2>/dev/null
    fi ;;
esac
case "$1" in
    logout)
        if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then exec uwsm stop; fi
        exec hyprctl dispatch 'hl.dsp.exit()' ;;
    reboot)   exec systemctl reboot ;;
    shutdown|poweroff) exec systemctl poweroff ;;
    *) echo "usage: $0 logout|reboot|shutdown" >&2; exit 1 ;;
esac
