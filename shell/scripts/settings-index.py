#!/usr/bin/env python3
"""List every setting in Settings, for its search: read from SettingsWindow.qml itself, so
it never falls out of date. Prints JSON [{"page", "label", "detail", "group", "key"}, …].
    settings-index.py <SettingsWindow.qml>

Each page is a `Component { id: <name>Page`; a setting is anything with `label: "…"` (its
`detail: "…"` is the next one before another label), under the latest `GroupLabel` heading.
Labels and details that are worked out in code rather than written as plain text are left
out (or, for a detail, left empty).

"key" is the setting the row changes (its name in SettingsData.qml), for the assistant's
tools (slate-mcp.py), which find a setting by what Settings calls it: the first
`Config.s.<key>` the row shows or sets (`key: "…"`, `checked:`, `value:`,
`Config.s.<key> = …`) before the next row; "" when the row isn't one setting, or sets it
some other way."""
import json, re, sys

src = open(sys.argv[1], encoding="utf-8").read()

# Which page id each component is: sourceComponent: ({ general: generalPage, … })
mapping = re.search(r"sourceComponent:\s*\(\{(.*?)\}\)", src, re.S)
pages = {comp: page for page, comp in re.findall(r"(\w+):\s*(\w+Page)\b", mapping.group(1))} if mapping else {}

out = []
page = None
group = ""
current = None
lines = src.split("\n")
for i, line in enumerate(lines):
    m = re.match(r"\s*id:\s*(\w+Page)\s*$", line)
    if m and i > 0 and "Component {" in lines[i - 1]:
        page = pages.get(m.group(1))
        group = ""
        current = None
        continue
    if page is None:
        continue
    m = re.search(r'GroupLabel\s*\{[^}]*\btext:\s*"([^"]+)"', line)
    if m:
        group = m.group(1)
        continue
    m = re.match(r'\s*label:\s*"([^"]+)"\s*$', line) or re.search(r'\blabel:\s*"([^"]+)"\s*;', line)
    if m:
        # Buttons have labels too ("Open", "Keep"…); settings sit in rows with a description
        # or are one of the setting controls, so skip lines inside Button { }
        opener = next((l for l in reversed(lines[max(0, i - 5):i + 1]) if re.search(r"\b[A-Z]\w*\s*\{", l)), "")
        if re.search(r"\bButton\s*\{", opener):
            current = None
            continue
        current = {"page": page, "label": m.group(1), "detail": "", "group": group, "key": ""}
        out.append(current)
        continue
    m = re.match(r'\s*detail:\s*"([^"]+)"\s*$', line)
    if m and current is not None and not current["detail"]:
        current["detail"] = m.group(1)
    if current is not None and not current["key"]:
        m = (re.search(r'\bkey:\s*"(\w+)"', line)                                   # ToggleSetting
             or re.search(r"\b(?:checked|value|text|current|on):\s*(?:!\s*)?Config\.s\.(\w+)", line)
             or re.search(r"\bConfig\.s\.(\w+)\s*=(?!=)", line))
        if m:
            current["key"] = m.group(1)
        else:
            m = re.search(r'\bwhich:\s*"(\w+)"', line)                               # SoundSetting
            if m:
                current["key"] = m.group(1) + "Volume"

# The same label twice on a page (a control and its menu, say): keep the first
seen, unique = set(), []
for e in out:
    key = (e["page"], e["label"])
    if key not in seen:
        seen.add(key)
        unique.append(e)
print(json.dumps(unique))
