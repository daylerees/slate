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

freeze_screen() {
    # Freeze the picture while choosing, so menus and video hold still
    freeze=""
    if command -v hyprpicker >/dev/null 2>&1; then hyprpicker -r -z >/dev/null 2>&1 & freeze=$!; sleep 0.15; fi
}
unfreeze() { [ -n "$freeze" ] && kill "$freeze" 2>/dev/null; sleep 0.05; }

case "${1:-region}" in
    region)
        freeze_screen
        geom=$(slurp -d -b '#00000066' -c '#ffffffcc' -w 2 2>/dev/null); ok=$?
        unfreeze
        [ $ok -eq 0 ] && [ -n "$geom" ] || exit 0
        grim -g "$geom" "$tmp" || exit 1 ;;
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
        freeze_screen
        geom=$(printf '%s\n' "$boxes" | slurp -r -b '#00000066' -c '#ffffffcc' -B '#ffffff22' -w 2 2>/dev/null); ok=$?
        unfreeze
        [ $ok -eq 0 ] && [ -n "$geom" ] || exit 0
        grim -g "$geom" "$tmp" || exit 1 ;;
    screen)
        mon=$(hyprctl monitors -j | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m["focused"]), ""))')
        grim ${mon:+-o "$mon"} "$tmp" || exit 1 ;;
    *) echo "usage: $0 region|window|screen" >&2; exit 1 ;;
esac

# Save it where Settings says, and copy it
mkdir -p "$folder"
file="$folder/$name"
cp "$tmp" "$file" || exit 1
wl-copy --type image/png < "$tmp"
if [ "$after" = "edit" ] && command -v swash >/dev/null 2>&1; then
    swash "$file"                    # saving there updates the same file
else
    notify-send -a Slate -i "$file" "Screenshot saved" "$file (also copied)"
fi
