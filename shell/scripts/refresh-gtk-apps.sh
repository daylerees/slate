#!/bin/sh
# GTK4/libadwaita apps read Slate's colours (~/.config/gtk-4.0/slate.css) only when they
# start, and some keep running in the background with no windows (Nautilus). After the
# colours change, apply-theme.py leaves a note; this restarts those apps once none of
# their windows are open, so the next window opens in the new colours. Run by
# apply-theme.py, and by Slate whenever a window closes (until it's done).
#   refresh-gtk-apps.sh
flag="${XDG_CACHE_HOME:-$HOME/.cache}/slate/gtk4-refresh"
[ -f "$flag" ] || exit 0
clients=$(hyprctl clients 2>/dev/null)
waiting=0
# app process : window class : how to quit it
for app in "nautilus:org.gnome.Nautilus:nautilus --quit"; do
    proc=${app%%:*}; rest=${app#*:}; class=${rest%%:*}; quit=${rest#*:}
    pgrep -x -u "$(id -u)" "$proc" >/dev/null || continue
    if printf '%s\n' "$clients" | grep -q "class: $class\$"; then
        waiting=1        # windows open: wait for them to close
    else
        $quit >/dev/null 2>&1
    fi
done
[ "$waiting" = 0 ] && rm -f "$flag"
exit 0
