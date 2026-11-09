#!/usr/bin/env python3
"""Folder colour for file managers (Nautilus, Dolphin…), for the Papirus icon themes.
Settings → Appearance → Folder colour.

  folder-colour.py --list          JSON: {"supported", "base", "current", "colours": [{"name", "hex"}]}
  folder-colour.py <colour>        use that colour (a Papirus folder colour, e.g. "teal")
  folder-colour.py default         back to the icon theme's own folders
  folder-colour.py --auto <#hex>   the colour closest to <#hex> (the wallpaper's); prints its name
  folder-colour.py --icon-theme <name>   set the icon theme for GTK, Qt and KDE apps (the installer
                                   uses this to make Papirus-Dark the default)

Papirus draws every folder icon in ~25 colours. Instead of changing the system's copy
(papirus-folders needs root), this makes a small icon theme of your own,
~/.local/share/icons/Slate-Icons, that inherits your Papirus theme and only swaps the
folder icons, then points GTK, Qt and KDE apps at it. Nothing outside your home changes.
"""
import colorsys
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
CFG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
NAME = "Slate-Icons"
OURS = os.path.join(DATA, "icons", NAME)
# Icon themes: yours, then the system's (XDG_DATA_DIRS: NixOS keeps them outside /usr/share)
ICON_DIRS = [os.path.join(DATA, "icons"), os.path.join(HOME, ".icons")] + [
    os.path.join(d, "icons") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
COLOURS = ["adwaita", "black", "blue", "bluegrey", "breeze", "brown", "carmine", "cyan", "darkcyan",
           "deeporange", "green", "grey", "indigo", "magenta", "nordic", "orange", "palebrown",
           "paleorange", "pink", "red", "teal", "violet", "white", "yaru", "yellow"]
# Default names (folder.svg, folder-documents.svg, user-home.svg…) are links to a colour's
# icon, e.g. folder-blue-documents.svg; swap the colour in that name
LINKED = re.compile(r"^(folder|user)-(%s)(-[\w-]+)?\.svg$" % "|".join(COLOURS))


# ---- The current icon theme ------------------------------------------------------------
@functools.lru_cache(maxsize=None)
def gsettings_get(key):
    """A GNOME interface setting. Read once per run: every read comes before this script sets
    anything (use_theme), so the answer can't change in between."""
    try:
        return subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", key],
                              capture_output=True, text=True, timeout=5).stdout.strip().strip("'")
    except (OSError, subprocess.SubprocessError):
        return ""

def theme_dir(name):
    for d in ICON_DIRS:
        p = os.path.join(d, name)
        if os.path.isfile(os.path.join(p, "index.theme")):
            return p
    return None

def ini_value(path, key):
    try:
        for line in open(path):
            m = re.match(r"\s*%s\s*=\s*(.*)" % re.escape(key), line)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return ""

def base_theme():
    """The theme ours sits on (the current one, unless ours is in use)"""
    cur = gsettings_get("icon-theme")
    if cur == NAME:
        return ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Base") or "Papirus-Dark"
    return cur

def papirus_root(base):
    """The folder holding the coloured folder icons (Papirus itself), or None"""
    seen, todo = set(), [base]
    while todo:
        name = todo.pop(0)
        if not name or name in seen:
            continue
        seen.add(name)
        d = theme_dir(name)
        if not d:
            continue
        if os.path.exists(os.path.join(d, "64x64", "places", "folder-teal.svg")):
            return os.path.realpath(d)
        todo += [t.strip() for t in ini_value(os.path.join(d, "index.theme"), "Inherits").split(",")]
    return None

def face(svg):
    """The colour of a folder's front (the third fill in Papirus's drawings)"""
    try:
        fills = re.findall(r'fill[:=]"?(#[0-9a-fA-F]{6})', open(svg).read())
    except OSError:
        return "#888888"
    if "yaru" in os.path.basename(svg):
        return fills[1] if len(fills) > 1 else "#ff7446"
    return fills[2] if len(fills) > 2 else (fills[0] if fills else "#888888")

def colour_names(root):
    """The folder colours this Papirus has (each a places/folder-<colour>.svg)."""
    places = os.path.join(root, "64x64", "places")
    return [c for c in COLOURS if os.path.exists(os.path.join(places, "folder-%s.svg" % c))]

def colours(root):
    """Each folder colour with the colour it's drawn in (read from its SVG)."""
    places = os.path.join(root, "64x64", "places")
    return [{"name": c, "hex": face(os.path.join(places, "folder-%s.svg" % c))} for c in colour_names(root)]


# ---- Pointing apps at a theme ------------------------------------------------------------
def set_ini(path, section, key, value, create=False):
    if not os.path.exists(path):
        if not create:
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").close()
    lines = open(path).read().splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == "[%s]" % section), None)
    if start is None:
        lines += ([""] if lines else []) + ["[%s]" % section, "%s=%s" % (key, value)]
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
        for i in range(start + 1, end):
            if re.match(r"\s*%s\s*=" % re.escape(key), lines[i]):
                lines[i] = "%s=%s" % (key, value)
                break
        else:
            lines.insert(end, "%s=%s" % (key, value))
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")

def use_theme(name, refresh):
    run = lambda *c: subprocess.run(list(c), capture_output=True, timeout=5)
    for v in ("gtk-3.0", "gtk-4.0"):
        set_ini(os.path.join(CFG, v, "settings.ini"), "Settings", "gtk-icon-theme-name", name, create=True)
    set_ini(os.path.join(CFG, "qt6ct", "qt6ct.conf"), "Appearance", "icon_theme", name, create=True)
    set_ini(os.path.join(CFG, "qt5ct", "qt5ct.conf"), "Appearance", "icon_theme", name)
    set_ini(os.path.join(CFG, "kdeglobals"), "Icons", "Theme", name)
    try:
        if refresh and gsettings_get("icon-theme") == name:
            # Same name, new icons: switch away and back so running GTK apps reload them
            run("gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "hicolor")
            time.sleep(0.3)
        run("gsettings", "set", "org.gnome.desktop.interface", "icon-theme", name)
        # KDE/Qt apps: icons changed (all groups)
        run("dbus-send", "--session", "--type=signal", "/KIconLoader", "org.kde.KIconLoader.iconChanged", "int32:0")
    except (OSError, subprocess.SubprocessError):
        pass


# ---- Building our theme ------------------------------------------------------------------
def build(root, base, colour):
    """~/.local/share/icons/Slate-Icons: the base theme, with folders in this colour"""
    if os.path.isdir(OURS):
        shutil.rmtree(OURS)
    index = open(os.path.join(root, "index.theme")).read()
    dirs = []
    for size in sorted(os.listdir(root)):
        places = os.path.join(root, size, "places")
        if not os.path.isdir(places):
            continue
        out = os.path.join(OURS, size, "places")
        os.makedirs(out)
        for fn in os.listdir(places):
            path = os.path.join(places, fn)
            if not os.path.islink(path):
                continue
            m = LINKED.match(os.readlink(path))
            if not m:
                continue
            want = "%s-%s%s.svg" % (m.group(1), colour, m.group(3) or "")
            target = os.path.join(places, want if os.path.exists(os.path.join(places, want)) else os.readlink(path))
            os.symlink(target, os.path.join(out, fn))
        dirs.append(size + "/places")
    sections = []
    for d in dirs:
        m = re.search(r"(?ms)^\[%s\]\n(.*?)(?=^\[|\Z)" % re.escape(d), index)
        if m:
            sections.append("[%s]\n%s" % (d, m.group(1).strip()))
    with open(os.path.join(OURS, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=%s\nComment=%s with %s folders (made by Slate)\n"
                "Inherits=%s\nDirectories=%s\nX-Slate-Base=%s\nX-Slate-Colour=%s\n\n%s\n"
                % (NAME, base, colour, base, ",".join(dirs), base, colour, "\n\n".join(sections)))


def nearest(hexc, options):
    """The folder colour closest to a colour: by hue for colourful ones, else a grey"""
    def hls(h):
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return colorsys.rgb_to_hls(r, g, b)
    h0, l0, s0 = hls(hexc)
    pool = [o for o in options if o["name"] not in ("yaru",)]
    greys = {"black", "grey", "white", "bluegrey"}
    if s0 < 0.18:
        pool = [o for o in pool if o["name"] in greys]
    else:
        pool = [o for o in pool if o["name"] not in greys]
    def dist(o):
        h, l, s = hls(o["hex"])
        dh = min(abs(h - h0), 1 - abs(h - h0))
        return dh * 4 + abs(l - l0) + abs(s - s0) * 0.5
    return min(pool, key=dist)["name"]


def main():
    args = sys.argv[1:]
    base = base_theme()
    root = papirus_root(base)
    if args == ["--list"]:
        cur = ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Colour") if gsettings_get("icon-theme") == NAME else ""
        print(json.dumps({"supported": bool(root), "base": base, "current": cur,
                          "colours": colours(root) if root else []}))
        return
    if not args:
        sys.exit(__doc__)
    if args[0] == "--icon-theme" and len(args) == 2:
        if not theme_dir(args[1]):
            sys.exit("folder-colour: no icon theme called %s" % args[1])
        use_theme(args[1], False)
        return
    if args[0] == "default":
        if gsettings_get("icon-theme") == NAME:
            use_theme(base, False)
        if os.path.isdir(OURS):
            shutil.rmtree(OURS)
        return
    if not root:
        sys.exit("folder-colour: the icon theme (%s) isn't Papirus, which has the coloured folders" % base)
    if args[0] == "--auto":
        if len(args) < 2 or not re.fullmatch(r"#[0-9a-fA-F]{6}", args[1]):
            sys.exit("folder-colour: --auto needs a colour like #4a90d9")
        colour = nearest(args[1], colours(root))
    else:
        colour = args[0]          # (a name: only whether it's there matters, not its SVG's colour)
    if colour not in colour_names(root):
        sys.exit("folder-colour: no '%s' folders in %s" % (colour, root))
    # Already like this: nothing to do (so apps don't flicker on every start)
    if gsettings_get("icon-theme") == NAME and ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Colour") == colour:
        print(colour)
        return
    build(root, base, colour)
    use_theme(NAME, True)
    print(colour)


if __name__ == "__main__":
    main()
