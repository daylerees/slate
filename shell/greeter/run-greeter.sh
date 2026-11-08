#!/bin/sh
# Start the Slate greeter inside the greeter Hyprland; when it finishes (after a
# successful login), close Hyprland so greetd can start the chosen session.
# If this copy fails to load (Quickshell exits with an error straight away), it tries the
# last copy someone logged in with (.good), then the basic emergency login screen, so a
# broken update never leaves you without a way to log in.
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
try() {   # try <dir>: run the login screen in it; fails if it didn't load
    [ -f "$1/shell.qml" ] || return 1
    echo "--- starting $1 ---" >>"$LOG"
    start=$(date +%s)
    qs -p "$1" >>"$LOG" 2>&1
    code=$?
    [ "$code" -eq 0 ] && return 0
    echo "--- exited with $code ---" >>"$LOG"
    [ $(( $(date +%s) - start )) -ge 10 ]     # ran for a while: it loaded, then stopped
}
: >"$LOG"
try "$DIR" || try "$DIR.good" || try "$DIR/emergency" || try "$DIR.good/emergency" || true
hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1
