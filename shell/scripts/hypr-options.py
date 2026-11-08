#!/usr/bin/env python3
"""Print Hyprland options' current values as JSON {"input:kb_layout": "gb", ...}, for Settings
to show what's in use for anything not set there.   hypr-options.py <option> [option ...]
Empty strings come back as "" (Hyprland says [[EMPTY]]); unknown options are left out."""
import json, subprocess, sys

out = {}
for opt in sys.argv[1:]:
    try:
        r = subprocess.run(["hyprctl", "getoption", opt, "-j"], capture_output=True, text=True, timeout=3)
        d = json.loads(r.stdout)
    except Exception:
        continue
    for kind in ("str", "int", "float", "bool", "custom"):
        if kind in d:
            v = d[kind]
            if v == "[[EMPTY]]":
                v = ""
            out[opt] = v
            break
print(json.dumps(out))
