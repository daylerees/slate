#!/bin/sh
# Screen recording for Slate:  record.sh start region|window|screen  |  stop  |  toggle [mode]
#   region  drag out an area (Esc cancels)
#   window  click a window
#   screen  the monitor the pointer is on
# One recording at a time. While it runs, $RUNTIME/slate-recording holds its process, its file
# and when it started (ScreenRecorder.qml watches it: the bar's indicator, the panel's Stop);
# `stop` ends it, and the video is saved in the screenshots folder (Settings → Screenshots),
# with a notification. Sound, as switched on (the panel, or Settings → Screenshots): the
# computer's, the microphone, both (mixed: mix_sounds), or none.
# wf-recorder records; slurp is the chooser for an area or a window, as for screenshots.
set -u
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# Slate's runtime folder: $XDG_RUNTIME_DIR, or without one a folder of your own that only you
# can open, never /tmp (the rule is Config.qml's runtimeDir; tests/unit/test_runtime_dir.py)
RUNTIME="${XDG_RUNTIME_DIR:-}"
[ -n "$RUNTIME" ] || { RUNTIME="${XDG_STATE_HOME:-$HOME/.local/state}/slate/run"; mkdir -p "$RUNTIME" && chmod 700 "$RUNTIME"; }
mark="$RUNTIME/slate-recording"
icon="$here/../assets/icon/icon-64.png"

say() {  # say <title> <body>
    notify-send -a Slate -i "$icon" -h string:x-slate-page:screenshots -- "$1" "$2" 2>/dev/null
}
couldnt() { say "$1" "$2"; exit 1; }
# Slate is told when a recording starts and ends (it reads the mark again: ScreenRecorder.qml)
tell_slate() { "$here/../bin/slate" ipc call record changed >/dev/null 2>&1 & }

# The recording running now, if there is one: its process (the mark's first line)
running() {
    [ -f "$mark" ] || return 1
    pid=$(sed -n 1p "$mark" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
    rm -f "$mark"                       # (left behind by one that ended without tidying up)
    return 1
}

# Both sounds at once: wf-recorder takes one, so a private sink of Slate's own ($mix) with the
# computer's sound and the microphone looped into it, recorded from its monitor. Nothing is
# heard from it. Taken away when the recording ends (unmix, and the EXIT trap); any left from a
# recording that was killed are taken away before the next one
mix_sounds() {
    leftovers
    mix="slate-recording-$$"
    sink=$(pactl load-module module-null-sink sink_name="$mix" sink_properties=device.description=Slate-recording) || return 1
    modules="$sink"
    for from in @DEFAULT_MONITOR@ @DEFAULT_SOURCE@; do
        loop=$(pactl load-module module-loopback source="$from" sink="$mix" latency_msec=20) || return 1
        modules="$loop $modules"
    done
}
unmix() {
    for m in $modules; do pactl unload-module "$m" 2>/dev/null; done
    modules=""
}
leftovers() {
    pactl list short modules 2>/dev/null | awk '/slate-recording-/ { print $1 }' | while read -r m; do
        pactl unload-module "$m" 2>/dev/null
    done
}

stop() {
    running || exit 0
    # (wf-recorder finishes the file on an interrupt; start's wait then saves and says so)
    kill -INT "$pid" 2>/dev/null
    exit 0
}

start() {
    mode=${1:-region}
    running && exit 0                   # (one at a time: the one running is the one to stop)
    # Private Mode (PrivateMode.qml) leaves this mark while it's on: no recordings then
    if [ -e "$RUNTIME/slate-private" ]; then
        say "Screen recording is off" \
            "Private Mode is on, so Slate isn't recording the screen. Turn it off in the control center when you're ready."
        exit 0
    fi
    settings=$(python3 -c '
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
print(d.get("screenshotFolder") or "")
print("yes" if d.get("recordComputerSound") else "")
print("yes" if d.get("recordMicrophone") else "")
' "${XDG_CONFIG_HOME:-$HOME/.config}/slate/settings.json" 2>/dev/null)
    folder=$(printf '%s\n' "$settings" | sed -n 1p)
    computer=$(printf '%s\n' "$settings" | sed -n 2p)
    mic=$(printf '%s\n' "$settings" | sed -n 3p)
    [ -n "$folder" ] || folder="$HOME/Pictures/Screenshots"

    case "$mode" in screen) needed="wf-recorder" ;; region|window) needed="wf-recorder slurp" ;;
        *) echo "usage: $0 start region|window|screen" >&2; exit 1 ;; esac
    # (both sounds at once are mixed through PipeWire's PulseAudio side: mix_sounds)
    [ -n "$computer" ] && [ -n "$mic" ] && needed="$needed pactl"
    for tool in $needed; do
        case "$tool" in pactl) package='"libpulse" or "pulseaudio-utils" package (whichever your system has)' ;;
            *) package="\"$tool\" package" ;; esac
        command -v "$tool" >/dev/null 2>&1 || couldnt "Slate couldn't record the screen" \
            "It needs $tool, which isn't installed. Install the $package, then try again."
    done
    said=$(mktemp) || couldnt "Slate couldn't record the screen" \
        "There was nowhere to keep a note while recording. Check there's some free space, then try again."
    modules=""
    trap 'rm -f "$said"; unmix' EXIT

    # Where: an area, a window, or the screen the pointer's on
    case "$mode" in
        region)
            geom=$(slurp -d -b '#00000066' -c '#ffffffcc' -w 2 2>"$said") || exit 0     # (Esc: you changed your mind)
            [ -n "$geom" ] || exit 0
            where="-g" ;;
        window)
            boxes=$(hyprctl -j monitors | python3 -c '
import json, subprocess, sys
# (by name: a named workspace has no id in Hyprland 0.57)
shown = {m["activeWorkspace"].get("name") for m in json.load(sys.stdin)}
for c in json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout):
    if c.get("mapped") and not c.get("hidden") and c.get("workspace", {}).get("name") in shown:
        (x, y), (w, h) = c["at"], c["size"]
        print("%d,%d %dx%d" % (x, y, w, h))')
            [ -n "$boxes" ] || exit 0
            geom=$(printf '%s\n' "$boxes" | slurp -r -b '#00000066' -c '#ffffffcc' -B '#ffffff22' -w 2 2>"$said") || exit 0
            [ -n "$geom" ] || exit 0
            where="-g" ;;
        screen)
            geom=$(hyprctl monitors -j | python3 -c 'import json,sys; print(next((m["name"] for m in json.load(sys.stdin) if m["focused"]), ""))')
            where="-o" ;;
    esac

    # Sound, as switched on: the computer's (what's playing: the default output's monitor), the
    # microphone, or both mixed
    if [ -n "$computer" ] && [ -n "$mic" ]; then
        mix_sounds || couldnt "Slate couldn't record the sound" \
            "It couldn't mix the computer's sound with the microphone's. Try recording with just one of them, in the Screenshot panel."
        audio="--audio=$mix.monitor"
    elif [ -n "$computer" ]; then audio="--audio=@DEFAULT_MONITOR@"
    elif [ -n "$mic" ]; then audio="--audio=@DEFAULT_SOURCE@"
    else audio=""
    fi

    mkdir -p "$folder" 2>/dev/null
    file="$folder/Screen Recording $(date +'%Y-%m-%d %H.%M.%S').mp4"
    if [ -n "$geom" ]; then
        wf-recorder -y "$where" "$geom" $audio -f "$file" >/dev/null 2>"$said" &
    else
        wf-recorder -y $audio -f "$file" >/dev/null 2>"$said" &
    fi
    pid=$!
    ( umask 077; printf '%s\n%s\n%s\n' "$pid" "$file" "$(date +%s)" > "$mark" )
    tell_slate
    wait "$pid"
    unmix
    rm -f "$mark"
    tell_slate
    if [ -s "$file" ]; then
        notify-send -a Slate -i "$icon" -h string:x-slate-page:screenshots -- "Screen recording saved" "$file" 2>/dev/null
    else
        why=$(sed -n '/[^[:space:]]/h; ${ g; p; }' "$said" 2>/dev/null | cut -c 1-200)
        rm -f "$file"
        couldnt "Slate couldn't record the screen" \
            "wf-recorder, which records, stopped before anything was saved. Please try again.${why:+ It said: $why}"
    fi
}

case "${1:-}" in
    start) start "${2:-region}" ;;
    stop) stop ;;
    toggle) if running; then stop; else start "${2:-region}"; fi ;;
    *) echo "usage: $0 start region|window|screen | stop | toggle [mode]" >&2; exit 1 ;;
esac
