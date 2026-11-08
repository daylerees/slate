#!/usr/bin/env python3
"""List keyboard layouts and their variants as JSON, for Settings → Keyboard & mouse:
[{"value": "gb", "label": "English (UK)"}, {"value": "gb:extd", "label": "English (UK, extended, with Win keys)"}, ...]
A value is "layout" or "layout:variant". Read from xkb's own list (evdev.lst)."""
import json

PATH = "/usr/share/X11/xkb/rules/evdev.lst"
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
