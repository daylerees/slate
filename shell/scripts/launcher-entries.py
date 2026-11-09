#!/usr/bin/env python3
"""Badges and progress that apps publish for their dock icons, for Slate's dock.

Usage: launcher-entries.py

Apps such as Telegram, Discord, Thunderbird and file managers say how many unread items they
have, and how far a download or copy has got, with the Unity launcher API: a D-Bus signal,
com.canonical.Unity.LauncherEntry.Update(app_uri, properties), on the session bus. This
watches for it (with dbus-monitor, part of D-Bus everywhere) and prints one JSON line per
change, each app's whole state so far:

  {"app": "org.telegram.desktop", "count": 3, "countVisible": true,
   "progress": 0.4, "progressVisible": false, "urgent": false}

"app" is the desktop entry's id (application://org.telegram.desktop.desktop → org.telegram.desktop).
Runs until it's stopped, or until Slate (whatever started it) has gone.

Apps only say something when a count changes, so the latest state is kept for the session
($XDG_RUNTIME_DIR/slate/launcher-entries.json, emptied at logout) and printed first when it
starts: Slate restarting doesn't lose the badges until each app speaks again.
"""
import ctypes
import json
import os
import re
import shutil
import signal
import subprocess
import sys

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "slate", "launcher-entries.json")

MATCH = "type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'"
KEYS = {"count": "count", "count-visible": "countVisible", "progress": "progress",
        "progress-visible": "progressVisible", "urgent": "urgent"}


def value(line):
    """The value on one of dbus-monitor's "variant <type> <value>" lines."""
    m = re.search(r"(int64|int32|uint32|uint64|double|boolean|string)\s+(.+)$", line.strip())
    if not m:
        return None
    kind, raw = m.groups()
    if kind == "boolean":
        return raw == "true"
    if kind == "double":
        return float(raw)
    if kind == "string":
        return raw.strip('"')
    return int(raw)


def stop_with_parent():
    """Be stopped when whatever started this goes (Slate, killed by a restart), rather than
    running on unseen. (Linux's PR_SET_PDEATHSIG; the dbus-monitor below gets it too.)"""
    try:
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)      # 1: PR_SET_PDEATHSIG
    except (OSError, AttributeError):
        pass


def load():
    try:
        with open(STATE, encoding="utf-8") as f:
            d = json.load(f)
        return {k: v for k, v in d.items() if isinstance(v, dict)} if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save(state):
    try:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(state, f)
        os.replace(tmp, STATE)
    except OSError:
        pass


def main():
    parent = os.getppid()
    stop_with_parent()
    if os.getppid() != parent:          # it went before that took hold
        return
    if not shutil.which("dbus-monitor"):
        sys.exit("launcher-entries: dbus-monitor isn't installed (it comes with D-Bus)")
    state = load()             # app id → its properties so far (this session's, from before)
    for entry in state.values():
        print(json.dumps(entry), flush=True)
    proc = subprocess.Popen(["dbus-monitor", "--session", MATCH], stdout=subprocess.PIPE, text=True, bufsize=1,
                            preexec_fn=stop_with_parent)
    app = None                 # the app the signal being read is about
    key = None                 # the property whose value comes next
    for line in proc.stdout:
        s = line.strip()
        if s.startswith("signal ") and "member=Update" in s:
            app, key = "", None
        elif app == "" and s.startswith("string ") and "application://" in s:
            app = s.split("application://", 1)[1].strip('"').removesuffix(".desktop")
            state.setdefault(app, {"app": app})
        elif app and s.startswith("string "):
            key = KEYS.get(s[len("string "):].strip('"'))
        elif app and key and s.startswith("variant"):
            v = value(s)
            if v is not None:
                state[app][key] = v
            key = None
        elif app and s == "]":                 # the end of its properties: one line for them all
            print(json.dumps(state[app]), flush=True)
            save(state)
            app = None


if __name__ == "__main__":
    main()
