#!/usr/bin/env python3
"""List keyboard layouts and their variants as JSON, for Settings → Keyboard & mouse:
[{"value": "gb", "label": "English (UK)"}, {"value": "gb:extd", "label": "English (UK, extended, with Win keys)"}, ...]
A value is "layout" or "layout:variant". Read from xkb's own list (evdev.lst)."""
import json
import os

# xkb's data: XKB_CONFIG_ROOT if set, else the first X11/xkb in the standard data dirs
# (XDG_DATA_DIRS: NixOS keeps it outside /usr/share)
_roots = ([os.environ["XKB_CONFIG_ROOT"]] if os.environ.get("XKB_CONFIG_ROOT") else []) + [
    os.path.join(d, "X11", "xkb") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
PATH = next((os.path.join(r, "rules", "evdev.lst") for r in _roots if os.path.isfile(os.path.join(r, "rules", "evdev.lst"))),
            "/usr/share/X11/xkb/rules/evdev.lst")
layouts, variants, section = [], [], None
try:
    for line in open(PATH, encoding="utf-8"):
        if line.startswith("! "):
            section = line[2:].strip()
            continue
        line = line.strip()
        if not line:
            continue
        if section == "layout":
            code, _, desc = line.partition(" ")
            layouts.append({"value": code, "label": desc.strip()})
        elif section == "variant":
            code, _, rest = line.partition(" ")
            parent, _, desc = rest.strip().partition(": ")
            variants.append({"value": parent + ":" + code, "label": desc.strip()})
except OSError:
    pass
print(json.dumps(sorted(layouts, key=lambda x: x["label"]) + sorted(variants, key=lambda x: x["label"])))
