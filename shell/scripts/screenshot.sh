#!/bin/sh
# Screenshots for Slate:  screenshot.sh region | screen
#   region  freeze the screen, drag out an area (Esc cancels)
#   screen  the monitor the pointer is on
# Settings → Screenshots: after taking one, open it in swash for annotating/saving (when
# installed), or save it straight to the folder and copy it to the clipboard; the folder
# (~/Pictures/Screenshots by default) and how files are named.
set -u
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
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
tmp=$(mktemp --suffix=.png) || exit 1
trap 'rm -f "$tmp"' EXIT

case "${1:-region}" in
    region)
        # Freeze the picture while selecting, so menus and video hold still
        freeze=""
        if command -v hyprpicker >/dev/null 2>&1; then hyprpicker -r -z >/dev/null 2>&1 & freeze=$!; sleep 0.15; fi
        geom=$(slurp -d -b '#00000066' -c '#ffffffcc' -w 2 2>/dev/null); ok=$?
        [ -n "$freeze" ] && kill "$freeze" 2>/dev/null
        [ $ok -eq 0 ] && [ -n "$geom" ] || exit 0
        sleep 0.05                                  # let the freeze overlay go away first
        grim -g "$geom" "$tmp" || exit 1 ;;
    screen)
        mon=$(hyprctl monitors -j | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m["focused"]), ""))')
        grim ${mon:+-o "$mon"} "$tmp" || exit 1 ;;
    *) echo "usage: $0 region|screen" >&2; exit 1 ;;
esac

if [ "$after" = "edit" ] && command -v swash >/dev/null 2>&1; then
    swash --stdin --name "$name" < "$tmp"
else
    dir="$folder"; mkdir -p "$dir"
    cp "$tmp" "$dir/$name"
    wl-copy --type image/png < "$tmp"
    notify-send -a Slate -i "$dir/$name" "Screenshot saved" "$dir/$name (also copied)"
fi
