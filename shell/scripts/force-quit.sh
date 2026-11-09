#!/bin/sh
# Force quits the apps behind the given Hyprland windows:  force-quit.sh 0xADDRESS [0xADDRESS ...]
# (the dock's right-click menu → Force Quit). Each window's process is killed outright, for
# apps that have stopped responding to Close. Slate's own windows (Settings) are left alone,
# since killing their process would take the whole desktop with it.
[ $# -gt 0 ] || { echo "usage: $0 0xADDRESS [...]" >&2; exit 1; }
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
