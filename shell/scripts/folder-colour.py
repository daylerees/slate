#!/usr/bin/env python3
"""Folder colour for file managers (Nautilus, Dolphin…), for icon themes that draw their
folders in several colours: Papirus (every kind of folder), and themes like Kora and Nordzy
(only their plain folder comes in colours: Slate repaints the rest, Desktop, Home, Documents
and so on, by swapping the plain folder's colours for the chosen colour's, see recolour).
Settings → Icons → Folder colour.

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
BUILD = "2"           # (made again when this changes: 2 repaints Kora's and Nordzy's other folders)
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

def simple_places(d):
    """In a theme like Kora or Nordzy, the folders of places icons that have the plain folder
    in colours (folder.svg beside folder-<colour>.svg), relative to the theme."""
    out = []
    for top, dirs, files in os.walk(d):
        if top[len(d):].count(os.sep) > 3:
            dirs[:] = []
            continue
        if "places" in top.split(os.sep) and "folder.svg" in files and \
                sum(1 for c in COLOURS if "folder-%s.svg" % c in files) >= 3:
            out.append(os.path.relpath(top, d))
    return sorted(out)

def simple_root(base):
    """A theme (the base, or one it builds on) whose plain folders come in colours, or None"""
    seen, todo = set(), [base]
    while todo:
        name = todo.pop(0)
        if not name or name in seen:
            continue
        seen.add(name)
        d = theme_dir(name)
        if not d:
            continue
        if simple_places(d):
            return os.path.realpath(d)
        todo += [t.strip() for t in ini_value(os.path.join(d, "index.theme"), "Inherits").split(",")]
    return None

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

def vivid(svg):
    """The colour a folder's drawn in, for a theme that isn't Papirus: its most colourful
    fill (#rrggbb or rgb()), leaving out outlines and shading. Grey for a grey folder."""
    try:
        text = open(svg).read()
    except OSError:
        return "#888888"
    found = re.findall(r"#([0-9a-fA-F]{6})\b", text)
    found += ["%02x%02x%02x" % tuple(int(x) for x in m) for m in re.findall(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", text)]
    best, score = None, -1.0
    for h in found:
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
        _, l, sat = colorsys.rgb_to_hls(r, g, b)
        k = sat * (1 - abs(l - 0.5) * 1.4) + 0.01 * (1 - abs(l - 0.5))     # (all grey: the mid-tone, not an outline)
        if k > score:
            best, score = h, k
    return "#" + best.lower() if best else "#888888"

def ref_places(root):
    """The places folder whose icons stand for the theme's colours"""
    if os.path.exists(os.path.join(root, "64x64", "places", "folder-teal.svg")):
        return os.path.join(root, "64x64", "places")          # (Papirus)
    rels = simple_places(root)
    return os.path.join(root, max(rels, key=lambda r: len(os.listdir(os.path.join(root, r))))) if rels else root

def colour_names(root):
    """The folder colours this theme has (each a places/folder-<colour>.svg)."""
    places = ref_places(root)
    return [c for c in COLOURS if os.path.exists(os.path.join(places, "folder-%s.svg" % c))]

def colours(root):
    """Each folder colour with the colour it's drawn in (read from its SVG)."""
    places = ref_places(root)
    paint = face if places.endswith(os.path.join("64x64", "places")) else vivid
    return [{"name": c, "hex": paint(os.path.join(places, "folder-%s.svg" % c))} for c in colour_names(root)]


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
COLOUR_RE = re.compile(r"#[0-9a-fA-F]{6}\b|rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)")

def as_rgb(c):
    if c.startswith("#"):
        return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(int(x) for x in re.findall(r"\d+", c))

def palette(svg):
    """An SVG's colours, each once, in the order they're first used (#hex and rgb())"""
    try:
        text = open(svg).read()
    except OSError:
        return []
    out = []
    for m in COLOUR_RE.findall(text):
        rgb = as_rgb(m)
        if rgb not in out:
            out.append(rgb)
    return out

def recolour(text, swap, shift):
    """An SVG's text with the plain folder's colours swapped for the chosen colour's (swap),
    and any other colourful one (an emblem's) moved the same way (shift: hue, lightness and
    saturation, from the folder's main colour to the chosen one's)."""
    dh, lk, sk = shift
    def one(m):
        c = m.group(0)
        rgb = as_rgb(c)
        new = swap.get(rgb)
        if new is None:
            h, l, sat = colorsys.rgb_to_hls(*(x / 255 for x in rgb))
            if sat < 0.15:
                return c                     # (greys and black stay)
            r, g, b = colorsys.hls_to_rgb((h + dh) % 1, min(1, l * lk), min(1, sat * sk))
            new = tuple(round(x * 255) for x in (r, g, b))
        return "#%02x%02x%02x" % new if c.startswith("#") else "rgb(%d,%d,%d)" % new
    return COLOUR_RE.sub(one, text)

COLOURED = re.compile(r"^(folder-(%s)(-.*)?|(%s)-folder.*)\.svg$" % ("|".join(COLOURS), "|".join(COLOURS)))

def build_simple(root, base, colour):
    """~/.local/share/icons/Slate-Icons for a theme like Kora: the base theme, with its plain
    folder (folder.svg) in this colour wherever it has one, and its other folders (Desktop,
    Home, Documents…, drawn in the plain folder's colours) repainted to match. The rest is
    left to the base."""
    if os.path.isdir(OURS):
        shutil.rmtree(OURS)
    index = open(os.path.join(root, "index.theme")).read()
    dirs = []
    for rel in simple_places(root):
        places = os.path.join(root, rel)
        src = os.path.join(places, "folder-%s.svg" % colour)
        if not os.path.exists(src):
            continue
        out = os.path.join(OURS, rel)
        os.makedirs(out)
        os.symlink(src, os.path.join(out, "folder.svg"))
        dirs.append(rel)
        # The plain folder's colours, and the chosen colour's, in the same order
        was, now = palette(os.path.join(places, "folder.svg")), palette(os.path.realpath(src))
        if not was or len(was) != len(now):
            continue
        swap = dict(zip(was, now))
        def hls(c):
            return colorsys.rgb_to_hls(*(x / 255 for x in c))
        main = max(was, key=lambda c: hls(c)[2])          # (the most colourful: the folder's own)
        (h0, l0, s0), (h1, l1, s1) = hls(main), hls(swap[main])
        shift = (h1 - h0, l1 / l0 if l0 else 1, s1 / s0 if s0 else 1)
        made = set()
        for fn in sorted(os.listdir(places)):
            path = os.path.join(places, fn)
            if not fn.endswith(".svg") or fn == "folder.svg" or COLOURED.match(fn) or not \
                    (fn.startswith("folder") or fn.startswith("user-")) or os.path.islink(path):
                continue
            try:
                text = open(path).read()
            except OSError:
                continue
            if as_rgb_in(text, main):
                with open(os.path.join(out, fn), "w") as f:
                    f.write(recolour(text, swap, shift))
                made.add(fn)
        # Other names for those (desktop.svg → user-desktop.svg): the same, in ours
        for fn in os.listdir(places):
            path = os.path.join(places, fn)
            if os.path.islink(path) and os.path.basename(os.readlink(path)) in made and not os.path.exists(os.path.join(out, fn)):
                os.symlink(os.path.basename(os.readlink(path)), os.path.join(out, fn))
    write_index(index, base, colour, dirs)

def as_rgb_in(text, rgb):
    """Whether an SVG uses this colour (#hex or rgb())"""
    return any(as_rgb(m) == rgb for m in COLOUR_RE.findall(text))


def write_index(index, base, colour, dirs):
    sections = []
    for d in dirs:
        m = re.search(r"(?ms)^\[%s\]\n(.*?)(?=^\[|\Z)" % re.escape(d), index)
        if m:
            sections.append("[%s]\n%s" % (d, m.group(1).strip()))
    with open(os.path.join(OURS, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=%s\nComment=%s with %s folders (made by Slate)\n"
                "Inherits=%s\nDirectories=%s\nX-Slate-Base=%s\nX-Slate-Colour=%s\nX-Slate-Build=%s\n\n%s\n"
                % (NAME, base, colour, base, ",".join(dirs), base, colour, BUILD, "\n\n".join(sections)))


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
    write_index(index, base, colour, dirs)


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
    # Mostly by hue: the colour Slate takes from the wallpaper has its lightness and saturation
    # set for the theme (a soft, light shade), not the wallpaper's own, so those only break ties
    # (weighed as much as hue, a light green wallpaper got Papirus's bluish dark cyan, which is
    # nearer in lightness, rather than teal, which is nearer in colour)
    def dist(o):
        h, l, s = hls(o["hex"])
        dh = min(abs(h - h0), 1 - abs(h - h0))
        return dh * 4 + abs(l - l0) * 0.25 + abs(s - s0) * 0.15
    return min(pool, key=dist)["name"]


def main():
    args = sys.argv[1:]
    base = base_theme()
    # Papirus (every kind of folder in colour), else a theme like Kora (the plain folder)
    root = papirus_root(base)
    kind = "papirus" if root else None
    if not root:
        root = simple_root(base)
        kind = "plain" if root else None
    if args == ["--list"]:
        cur = ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Colour") if gsettings_get("icon-theme") == NAME else ""
        print(json.dumps({"supported": bool(root), "base": base, "current": cur, "kind": kind or "",
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
        sys.exit("folder-colour: the icon theme (%s) has no folders in colours" % base)
    if args[0] == "--auto":
        if len(args) < 2 or not re.fullmatch(r"#[0-9a-fA-F]{6}", args[1]):
            sys.exit("folder-colour: --auto needs a colour like #4a90d9")
        colour = nearest(args[1], colours(root))
    else:
        colour = args[0]          # (a name: only whether it's there matters, not its SVG's colour)
    if colour not in colour_names(root):
        sys.exit("folder-colour: no '%s' folders in %s" % (colour, root))
    # Already like this: nothing to do (so apps don't flicker on every start)
    if gsettings_get("icon-theme") == NAME and ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Colour") == colour \
            and ini_value(os.path.join(OURS, "index.theme"), "X-Slate-Build") == BUILD:
        print(colour)
        return
    (build if kind == "papirus" else build_simple)(root, base, colour)
    use_theme(NAME, True)
    print(colour)


if __name__ == "__main__":
    main()
