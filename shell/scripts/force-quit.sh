#!/bin/sh
# Force quits the apps behind Hyprland windows, for apps that have stopped responding to Close:
#   force-quit.sh 0xADDRESS [0xADDRESS ...]   these windows (the dock's right-click menu → Force Quit)
#   force-quit.sh --pick                      the one you click (Super+Escape): the windows you can
#                                             see become boxes to click, as when screenshotting a
#                                             window; Esc, or a click off them, changes nothing
# Each window's process is killed outright. Slate's own windows (Settings, Nova…) are left alone,
# since killing their process would take the whole desktop with it: picked, they're boxes too, so
# a click on one can't reach the app behind it, and Slate says to close them instead.
here=$(dirname "$(readlink -f "$0")")
if [ "${1:-}" = "--pick" ]; then
    command -v slurp >/dev/null 2>&1 || {
        notify-send -a Slate -i "$here/../assets/icon/icon-64.png" "Slate couldn't force quit an app" \
            "Choosing the window needs slurp, which isn't installed. Install the \"slurp\" package, then try again." 2>/dev/null
        exit 1
    }
    # The windows on the workspaces you can see, as boxes labeled with their address (Slate's
    # own labeled "slate")
    boxes=$(hyprctl -j monitors | python3 -c '
import json, subprocess, sys
shown = {m["activeWorkspace"].get("name") for m in json.load(sys.stdin)}
for c in json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout):
    if c.get("mapped") and not c.get("hidden") and c.get("workspace", {}).get("name") in shown:
        try:
            with open("/proc/%d/comm" % c.get("pid", 0)) as f: own = f.read().strip() in ("qs", "quickshell")
        except (OSError, TypeError): own = False
        (x, y), (w, h) = c["at"], c["size"]
        print("%d,%d %dx%d %s" % (x, y, w, h, "slate" if own else c["address"]))')
    [ -n "$boxes" ] || exit 0
    picked=$(printf '%s\n' "$boxes" | slurp -r -f '%l' -b '#00000066' -c '#ffffffcc' -B '#ffffff22' -w 2 2>/dev/null) || exit 0
    case "$picked" in
        slate) notify-send -a Slate -i "$here/../assets/icon/icon-64.png" "That's one of Slate's own windows" \
                   "Slate's windows can't be force quit, since that would close the whole desktop. Close it as usual instead." 2>/dev/null
               exit 0 ;;
        0x*) set -- "$picked" ;;
        *) exit 0 ;;
    esac
fi
[ $# -gt 0 ] || { echo "usage: $0 0xADDRESS [...] | --pick" >&2; exit 1; }
hyprctl -j clients | python3 -c '
import json, os, signal, sys
want = set(sys.argv[1:])
try: clients = json.load(sys.stdin)
except ValueError: sys.exit(1)
pids = {c.get("pid") for c in clients if c.get("address") in want}
for pid in pids:
    if not isinstance(pid, int) or pid <= 1: continue
    try:
        with open(f"/proc/{pid}/comm") as f: name = f.read().strip()
    except OSError: continue
    if name in ("qs", "quickshell"): continue
    try: os.kill(pid, signal.SIGKILL)
    except OSError: pass
' "$@"
