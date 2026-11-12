#!/usr/bin/env python3
"""The cursor and icon themes installed here, for Settings (Input → Pointer style, Appearance
→ Icons).

  icon-themes.py --cursors   JSON: [{"id", "name"}] every cursor theme (a theme with cursors/)
  icon-themes.py --icons     JSON: [{"id", "name"}] every icon theme with app icons

Looked for in your own folders first, then the system's (XDG_DATA_DIRS: NixOS keeps them
outside /usr/share), the first of each name winning. Left out of the icons: themes with no
app icons (cursor-only themes, hicolor, which is every theme's fallback rather than a look
of its own), Slate's folder-colour theme (Slate-Icons: made from your icon theme, and set by
Folder colour, not chosen here) and the "default" theme (only says which cursors to use).
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
DIRS = [os.path.join(DATA, "icons"), os.path.join(HOME, ".icons")] + [
    os.path.join(d, "icons") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
SKIP = {"default", "hicolor", "Slate-Icons", "locolor"}


def index(path):
    """index.theme's [Icon Theme] section, as a dict ({} if there isn't one)."""
    out, inside = {}, False
    try:
        with open(os.path.join(path, "index.theme"), encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    inside = line == "[Icon Theme]"
                elif inside and "=" in line:
                    k, v = line.split("=", 1)
                    out.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return out


def has_app_icons(path, head):
    """Whether a theme draws app icons of its own (a folder for Applications in its index)."""
    names = [d.strip() for d in (head.get("Directories", "") + "," + head.get("ScaledDirectories", "")).split(",") if d.strip()]
    try:
        text = open(os.path.join(path, "index.theme"), encoding="utf-8", errors="ignore").read()
    except OSError:
        return False
    for d in names:
        i = text.find("[%s]" % d)
        if i < 0:
            continue
        sec = text[i:text.find("\n[", i + 1) if text.find("\n[", i + 1) > 0 else len(text)]
        if "context=applications" in sec.lower().replace(" ", "") or "context=apps" in sec.lower().replace(" ", ""):
            if os.path.isdir(os.path.join(path, d)):
                return True
    return False


def themes(kind):
    seen, out = set(), []
    for base in DIRS:
        try:
            names = sorted(os.listdir(base), key=str.lower)
        except OSError:
            continue
        for n in names:
            path = os.path.join(base, n)
            if n in seen or not os.path.isdir(path):
                continue
            head = index(path)
            if kind == "cursors":
                if not os.path.isdir(os.path.join(path, "cursors")):
                    continue
            else:
                if n in SKIP or not head or not has_app_icons(path, head):
                    continue
            seen.add(n)
            name = head.get("Name") or n
            out.append({"id": n, "name": name if name != "Default" else n})
    return sorted(out, key=lambda t: t["name"].lower())


def main():
    if sys.argv[1:] == ["--cursors"]:
        print(json.dumps(themes("cursors")))
    elif sys.argv[1:] == ["--icons"]:
        print(json.dumps(themes("icons")))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
