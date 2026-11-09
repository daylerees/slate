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
Runs until it's stopped; prints nothing until an app says something.
"""
import json
import re
import shutil
import subprocess
import sys

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


def main():
    if not shutil.which("dbus-monitor"):
        sys.exit("launcher-entries: dbus-monitor isn't installed (it comes with D-Bus)")
    proc = subprocess.Popen(["dbus-monitor", "--session", MATCH], stdout=subprocess.PIPE, text=True, bufsize=1)
    state = {}                 # app id → its properties so far
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
            app = None


if __name__ == "__main__":
    main()
