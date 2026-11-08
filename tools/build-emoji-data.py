#!/usr/bin/env python3
"""Rebuild shell/data/emoji.json (the emoji picker's list) from Unicode's own data.

    tools/build-emoji-data.py <emoji-test.txt> <annotations.json> <annotationsDerived.json> <out.json>

Sources (Unicode License v3):
  https://unicode.org/Public/emoji/latest/emoji-test.txt
  https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json
  https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-derived-full/annotationsDerived/en/annotations.json

Writes [[emoji, name, keywords, category], ...] for fully-qualified emoji, without skin-tone
variants."""
import json, re, sys

test, ann, ann2, out = sys.argv[1:5]
keywords = {}
for f in (ann, ann2):
    d = json.load(open(f, encoding="utf-8"))
    top = d.get("annotations") or d.get("annotationsDerived")
    for e, v in top["annotations"].items():
        keywords.setdefault(e, v.get("default", []))
# Unicode's groups → the picker's categories
GROUPS = {"Smileys & Emotion": "people", "People & Body": "people", "Animals & Nature": "animals",
          "Food & Drink": "food", "Travel & Places": "travel", "Activities": "activity",
          "Objects": "objects", "Symbols": "symbols", "Flags": "flags"}
NATURE = ("plant", "flower")                      # subgroups of Animals & Nature
SKIN = re.compile("[\U0001F3FB-\U0001F3FF]")

rows, group, sub = [], "", ""
for line in open(test, encoding="utf-8"):
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip(); continue
    if line.startswith("# subgroup:"):
        sub = line.split(":", 1)[1].strip(); continue
    if not line.strip() or line.startswith("#"):
        continue
    m = re.match(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E[\d.]+\s+(.+)$", line.strip())
    if not m or group not in GROUPS:
        continue
    emoji, name = m.group(2), m.group(3).strip()
    if SKIN.search(emoji):
        continue
    cat = GROUPS[group]
    if cat == "animals" and sub.startswith(NATURE):
        cat = "nature"
    words = [w for w in keywords.get(emoji, keywords.get(emoji.replace("️", ""), [])) if w.lower() != name.lower()]
    rows.append([emoji, name, " ".join(words), cat])

json.dump(rows, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(rows), "emoji written to", out)
