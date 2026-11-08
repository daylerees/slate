#!/bin/sh
# Start the Slate greeter inside the greeter Hyprland; when it finishes (after a
# successful login), close Hyprland so greetd can start the chosen session.
# If this copy fails to load (Quickshell exits with an error straight away), use the
# previous install instead, so a broken update never leaves you without a login screen.
DIR=/usr/local/share/slate-greeter         # code (root-owned)
export XDG_CACHE_HOME=/var/cache/slate-greeter/cache
export XDG_STATE_HOME=/var/cache/slate-greeter/state
export FONTCONFIG_FILE="$DIR/fonts.conf"     # adds /var/lib/slate-greeter/fonts
export QT_QPA_PLATFORM=wayland
# Settings → Appearance → Interface size, from your synced settings
scale=$(sed -n 's/.*"uiScale": *\([0-9.]*\).*/\1/p' /var/lib/slate-greeter/settings.json 2>/dev/null | head -n 1)
case "$scale" in ""|1|1.0|1.00) ;; *) export QT_SCALE_FACTOR="$scale" ;; esac
LOG=/var/cache/slate-greeter/greeter.log
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
start=$(date +%s)
qs -p "$DIR" >"$LOG" 2>&1
code=$?
if [ "$code" -ne 0 ] && [ $(( $(date +%s) - start )) -lt 10 ] && [ -f "$DIR.previous/shell.qml" ]; then
    echo "--- failed to start (exit $code); using the previous install ---" >>"$LOG"
    qs -p "$DIR.previous" >>"$LOG" 2>&1
fi
hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1
