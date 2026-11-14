#!/bin/sh
# Screenshots for Slate:  screenshot.sh region | window | screen
#   region  freeze the screen, drag out an area (Esc cancels)
#   window  freeze the screen, click a window
#   screen  the monitor the pointer is on
# Every screenshot is saved to the folder from Settings → Screenshots (~/Pictures/Screenshots
# by default), named as set there, and copied to the clipboard. Then, as set there, it opens
# in swash for annotating (when installed): saving in swash updates that same file, so it
# never asks where to save. Or Slate just shows a notification.
set -u
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# Slate's runtime folder: $XDG_RUNTIME_DIR, or without one a folder of your own that only you
# can open, never /tmp (the rule is Config.qml's runtimeDir; tests/unit/test_runtime_dir.py)
RUNTIME="${XDG_RUNTIME_DIR:-}"
[ -n "$RUNTIME" ] || { RUNTIME="${XDG_STATE_HOME:-$HOME/.local/state}/slate/run"; mkdir -p "$RUNTIME" && chmod 700 "$RUNTIME"; }

# Private Mode (PrivateMode.qml) leaves this mark while it's on: no screenshots then
if [ -e "$RUNTIME/slate-private" ]; then
    notify-send -a Slate -i "$here/../assets/icon/icon-64.png" -h string:x-slate-page:control "Screenshots are off" \
        "Private Mode is on, so Slate isn't taking screenshots. Turn it off in the control center when you're ready." 2>/dev/null
    exit 0
fi
settings=$(python3 -c '
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
print(d.get("screenshotName") or "default")
print(d.get("screenshotAfter") or "edit")
print(d.get("screenshotFolder") or "")
' "$here/../settings.json" 2>/dev/null)
naming=$(printf '%s\n' "$settings" | sed -n 1p)
after=$(printf '%s\n' "$settings" | sed -n 2p)
folder=$(printf '%s\n' "$settings" | sed -n 3p)
[ -n "$folder" ] || folder="$HOME/Pictures/Screenshots"
case "$naming" in
    compact) name="$(date +'%Y-%m-%d_%H-%M-%S').png" ;;
    gnome)   name="Screenshot from $(date +'%Y-%m-%d %H-%M-%S').png" ;;
    *)       name="Screenshot $(date +'%Y-%m-%d %H.%M.%S').png" ;;
esac

# When something stops a screenshot, say so: the panel has closed by then, so without a
# notification nothing would seem to happen at all
couldnt() {  # couldnt <title> <what happened, and what to do>
    notify-send -a Slate -i "$here/../assets/icon/icon-64.png" -h string:x-slate-page:screenshots "$1" "$2" 2>/dev/null
    exit 1
}
# grim takes the picture, and slurp is the chooser for an area or a window
case "${1:-region}" in screen) needed="grim" ;; *) needed="grim slurp" ;; esac
for tool in $needed; do
    command -v "$tool" >/dev/null 2>&1 || couldnt "Slate couldn't take the screenshot" \
        "It needs $tool, which isn't installed. Install the \"$tool\" package, then try again."
done
# The picture while it's being taken, and what grim or slurp said if they stopped (plain
# mktemp: a suffix is GNU's alone, and nothing needs one)
tmp=$(mktemp) && said=$(mktemp) || couldnt "Slate couldn't take the screenshot" \
    "There was nowhere to keep the picture while taking it. Check there's some free space, then try again."
trap 'rm -f "$tmp" "$said"' EXIT
# (the last thing a tool said, for the notification: "" when it said nothing)
last_said() { sed -n '/[^[:space:]]/h; ${ g; p; }' "$said" 2>/dev/null | cut -c 1-200; }
# The chooser ended without an area. Esc (or a click that isn't on a window) is you changing
# your mind, which is no failure and stays silent: slurp says "selection cancelled" then.
# Anything else is the chooser not working
no_area() {
    grep -qi 'cancel' "$said" 2>/dev/null && exit 0
    why=$(last_said)
    couldnt "Slate couldn't take the screenshot" \
        "The chooser for the area (slurp) stopped before you could choose. Please try again.${why:+ It said: $why}"
}
take() {  # take <grim's options>: the picture, into $tmp
    grim "$@" "$tmp" 2>"$said" && return
    why=$(last_said)
    couldnt "Slate couldn't take the screenshot" \
        "grim, which takes the picture, stopped before it was done. Please try again.${why:+ It said: $why}"
}

# One chooser at a time. Pressing Print again while the first is still waiting for you to
# drag out an area used to start another on top, each dimming the screen a little more. The
# second press now does nothing: the one that's open is the one to use. Held only while
# choosing (the lock is let go before the picture is saved or opened), so the next screenshot
# can start straight after.
choosing="$RUNTIME/slate-screenshot.lock"
one_chooser() {
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$choosing"
        flock -n 9 || exit 0
    elif pgrep -u "$(id -u)" -x slurp >/dev/null 2>&1; then
        exit 0
    fi
}
chosen() { exec 9>&- 2>/dev/null || true; }

freeze_screen() {
    # Freeze the picture while choosing, so menus and video hold still
    freeze=""
    if command -v hyprpicker >/dev/null 2>&1; then hyprpicker -r -z >/dev/null 2>&1 & freeze=$!; sleep 0.15; fi
}
unfreeze() { [ -n "$freeze" ] && kill "$freeze" 2>/dev/null; sleep 0.05; }

case "${1:-region}" in
    region)
        one_chooser
        freeze_screen
        geom=$(slurp -d -b '#00000066' -c '#ffffffcc' -w 2 2>"$said"); ok=$?
        unfreeze
        chosen
        [ $ok -eq 0 ] || no_area
        [ -n "$geom" ] || exit 0
        take -g "$geom" ;;
    window)
        # The windows on the workspaces you can see, as boxes to click
        boxes=$(hyprctl -j monitors | python3 -c '
import json, subprocess, sys
shown = {m["activeWorkspace"]["id"] for m in json.load(sys.stdin)}
for c in json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout):
    if c.get("mapped") and not c.get("hidden") and c["workspace"]["id"] in shown:
        (x, y), (w, h) = c["at"], c["size"]
        print("%d,%d %dx%d" % (x, y, w, h))')
        [ -n "$boxes" ] || exit 0
        one_chooser
        freeze_screen
        geom=$(printf '%s\n' "$boxes" | slurp -r -b '#00000066' -c '#ffffffcc' -B '#ffffff22' -w 2 2>"$said"); ok=$?
        unfreeze
        chosen
        [ $ok -eq 0 ] || no_area
        [ -n "$geom" ] || exit 0
        take -g "$geom" ;;
    screen)
        mon=$(hyprctl monitors -j | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m["focused"]), ""))')
        take ${mon:+-o "$mon"} ;;
    *) echo "usage: $0 region|window|screen" >&2; exit 1 ;;
esac

# Save it where Settings says, and copy it. If it can't be saved it's still copied, so the
# picture isn't lost
file="$folder/$name"
if ! { mkdir -p "$folder" && cp "$tmp" "$file"; } 2>/dev/null; then
    wl-copy --type image/png < "$tmp"
    couldnt "Slate couldn't save the screenshot" \
        "It couldn't be put in $folder. Check that folder is there and can be written to, or choose another in Settings → Screenshots. It's been copied, so you can still paste it."
fi
wl-copy --type image/png < "$tmp"
if [ "$after" = "edit" ] && command -v swash >/dev/null 2>&1; then
    swash "$file"                    # saving there updates the same file
else
    notify-send -a Slate -i "$file" -h string:x-slate-page:screenshots "Screenshot saved" "$file (also copied)"
fi
