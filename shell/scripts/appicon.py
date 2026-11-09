#!/usr/bin/env python3
"""Render an app icon as a "phone app" tile for Slate's dock, launcher and bar.

Usage: appicon.py --tile <app-id-or-class> <out.png> <pixels> [--shape S] [--fill|--whole]
       appicon.py --tile-all <dir> <pixels> [--shape S] [--fill|--whole]   (every installed app)
       appicon.py --preview <dir> <pixels>   (one app in every shape and style, for Settings)
       appicon.py --colours <dir> <out.json> (each drawn icon's main colour, for tiles in it)

Settings → Appearance → App icons:
  --shape  tile (default: a rounded square), squircle, circle, square, or original
           (the icon as the app ships it, with no tile)
  --fill   cut away theme drop shadows and empty margins, enlarge square icons a
           little so their own border is cropped, and grow other shapes to fill the tile on
           their main colour (for original: just trimmed and grown to fill the image)
  --whole  the whole icon, smaller, with nothing behind it: Slate draws the tile behind in
           the theme's colour (IconPlate.qml), so it follows the theme. Original: untouched.
           Slate's default (Settings → Appearance → App icons) is tile with --whole

Draws a square container (matching the bar's capsules) with a rounded inner
frame a few pixels in, and the app icon slightly oversized and cropped to that
inner frame. Slate caches the tiles in ~/.cache/slate/tiles.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

# --- Look (pixels for a 54 px tile; tiles are rendered at the size asked for and scaled) ---
SIZE = 54            # outer square = capsule height (27 logical)
OUTER_RADIUS = 12    # matches capsule_radius = 6 logical
INSET = 6            # gap between outer and inner frame (3 logical)
INNER_RADIUS = 8
ZOOM = 1.18          # square icons: size relative to the inner frame (>1 = cropped)
FILL = 1.0           # other shapes: longest side relative to the inner frame
OUTER_FILL = (0x1D, 0x22, 0x2A, 255)
INNER_FILL = (0x2A, 0x31, 0x3C, 255)
SS = 4               # supersampling for smooth edges

APP_DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    "/usr/share/applications",
]
ICON_BASES = [
    os.path.expanduser("~/.local/share/icons"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/icons"),  # Flatpak apps
    "/var/lib/flatpak/exports/share/icons",
    "/usr/share/icons",
]
THEMES = ["Papirus-Dark", "Papirus", "hicolor", "breeze-dark", "breeze", "Adwaita"]
SIZES = ["scalable", "1024x1024", "512x512", "256x256", "128x128", "96x96", "64x64",
         "48x48", "32x32", "24x24", "22x22", "16x16"]


# Reverse-domain prefixes shared by many unrelated apps: an app ID starting with one of
# these is never matched to another app just by the prefix
SHARED_PREFIXES = {"org.gnome", "org.kde", "org.freedesktop", "org.gtk", "com.github", "io.github",
                   "com.gitlab", "io.gitlab", "org.gitlab", "net.sourceforge", "app.drey", "page.tesk",
                   "io.elementary", "com.system76", "org.mozilla", "com.belmoussaoui", "de.haeckerfelix"}


def desktop_icon(cls):
    """Find the Icon= value from the app's .desktop file."""
    want = cls.lower()
    files = []
    for d in APP_DIRS:
        if os.path.isdir(d):
            files += [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".desktop")]
    by_name = {os.path.basename(f)[:-8].lower(): f for f in files}
    candidates = [by_name.get(want), by_name.get(want.split(".")[-1])]
    parts = want.split(".")
    if not any(candidates) and len(parts) >= 3 and ".".join(parts[:2]) not in SHARED_PREFIXES:
        # Same reverse-domain prefix, e.g. org.godotengine.Editor -> org.godotengine.Godot
        # (not for prefixes many unrelated apps share, like org.gnome or io.github)
        prefix = ".".join(parts[:2]) + "."
        candidates += [f for n, f in sorted(by_name.items()) if n.startswith(prefix)]
    if not any(candidates):
        for f in files:  # match StartupWMClass
            try:
                with open(f, encoding="utf-8", errors="ignore") as fh:
                    for line in fh:
                        if line.lower().startswith("startupwmclass=") and line.split("=", 1)[1].strip().lower() == want:
                            candidates.append(f)
                            break
            except OSError:
                pass
    for f in filter(None, candidates):
        icon = entry_value(f, "Icon")
        if icon:
            return icon
    return None


def entry_value(path, key):
    """Read a key from a .desktop file's [Desktop Entry] section.

    Parsed by hand because some generated files (e.g. EmuDeck's) indent every
    line, which a standard INI parser misreads."""
    section = None
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    section = line
                elif section == "[Desktop Entry]" and line.startswith(key + "="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return None


def find_icon_file(name):
    if os.path.isabs(name):
        if os.path.isfile(name):
            return name
        # Points at a file that isn't there (e.g. a theme that isn't installed):
        # look its name up in the themes instead
        name = os.path.splitext(os.path.basename(name))[0]
    for base in ICON_BASES:
        for theme in THEMES:
            for size in SIZES:
                for ext in ("svg", "png"):
                    p = os.path.join(base, theme, size, "apps", f"{name}.{ext}")
                    if os.path.isfile(p):
                        return p
    for ext in ("svg", "png"):
        p = f"/usr/share/pixmaps/{name}.{ext}"
        if os.path.isfile(p):
            return p
    return None


def flat_svg(path):
    """Return the SVG with its faint black/white layers removed.

    Icon themes like Papirus add depth with extra layers: black at ~20% opacity for
    shadows and white at 10-20% for the highlight along the top edge. Real artwork
    uses solid colours, so anything black or white and at most 35% opaque goes."""
    import xml.etree.ElementTree as ET
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    root = ET.parse(path).getroot()
    mono = ("#000", "#000000", "black", "#fff", "#ffffff", "white")

    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return 1.0

    def faint(el):
        p = dict(el.attrib)
        for part in el.attrib.get("style", "").split(";"):
            if ":" in part:
                k, v = part.split(":", 1)
                p[k.strip()] = v.strip()
        op = num(p.get("opacity"))
        fill = p.get("fill", "#000000").lower()
        stroke = p.get("stroke", "none").lower()
        if fill != "none":
            return fill in mono and op * num(p.get("fill-opacity")) <= 0.35
        if stroke != "none":
            return stroke in mono and op * num(p.get("stroke-opacity")) <= 0.35
        return False

    for parent in root.iter():
        for child in list(parent):
            if child.tag.split("}")[-1] in ("path", "circle", "rect", "ellipse", "polygon") and faint(child):
                parent.remove(child)
    return ET.tostring(root)


def load_icon(path, px):
    if path.endswith(".svg"):
        try:
            data, src = flat_svg(path), "-"
        except Exception:  # unusual SVG: render it untouched
            data, src = None, path
        png = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-a", src],
                             input=data, capture_output=True, check=True).stdout
        from io import BytesIO
        img = Image.open(BytesIO(png)).convert("RGBA")
    else:
        img = Image.open(path).convert("RGBA")
    img.thumbnail((px, px), Image.LANCZOS) if max(img.size) > px else None
    if max(img.size) < px:
        scale = px / max(img.size)
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    return img


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def pixels(img):
    # getdata() is deprecated in newer Pillow
    return img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata()


def remove_shadow(icon):
    """Drop the soft drop shadow many icon themes (e.g. Papirus) put under icons.

    The shadow is dark and mostly see-through (about 20% opaque); real artwork is
    either solid or brightly coloured, so it is left alone."""
    import numpy as np
    a = np.asarray(icon).copy()
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    a[(a[..., 3] < 102) & (lum < 60), 3] = 0
    return Image.fromarray(a, "RGBA")


def trim(icon):
    """Cut away the transparent margin around the icon's artwork."""
    bbox = icon.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return icon.crop(bbox) if bbox else icon


def is_square(icon):
    """True if the artwork already fills a square (e.g. a rounded-square app icon)."""
    w, h = icon.size
    if not (0.9 <= w / h <= 1.1):
        return False
    a = icon.getchannel("A").resize((64, 64))
    solid = sum(1 for v in pixels(a) if v > 200)
    return solid / (64 * 64) >= 0.88


def main_colour(icon):
    """Most common solid colour in the icon, used to fill around non-square shapes."""
    small = icon.resize((48, 48))
    counts = {}
    for r, g, b, a in pixels(small):
        if a > 200:
            key = (r // 16, g // 16, b // 16)
            counts[key] = counts.get(key, 0) + 1
    if not counts:
        return INNER_FILL
    r, g, b = max(counts, key=counts.get)
    return (r * 16 + 8, g * 16 + 8, b * 16 + 8, 255)


def accent_colour(icon):
    """The colour an icon reads as: its most common strong colour, so a white or dark outline
    doesn't win over the colour that fills it; for a mostly grey icon, its most common colour.
    Returns "#rrggbb", or "" for an empty image."""
    import colorsys
    small = icon.convert("RGBA").resize((48, 48))
    strong, every, opaque = {}, {}, 0
    for r, g, b, a in pixels(small):
        if a <= 200:
            continue
        opaque += 1
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        key = (r // 24, g // 24, b // 24)
        for counts in ([every, strong] if s > 0.3 and 0.15 < l < 0.85 else [every]):
            n, sr, sg, sb = counts.get(key, (0, 0, 0, 0))
            counts[key] = (n + 1, sr + r, sg + g, sb + b)
    if not opaque:
        return ""
    # Strong colours win when there's a fair amount of them (8% of the icon)
    pool = strong if sum(v[0] for v in strong.values()) >= opaque * 0.08 else every
    n, sr, sg, sb = max(pool.values(), key=lambda v: v[0])
    return "#%02x%02x%02x" % (sr // n, sg // n, sb // n)


def colours(tile_dir, out):
    """Write each drawn icon's colour (accent_colour) to out as JSON, by its file name. Icons
    already listed (and unchanged) are kept, so running it again only reads new ones."""
    import json
    try:
        with open(out) as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    found = {}
    for f in sorted(os.listdir(tile_dir)):
        if not f.endswith(".png"):
            continue
        path = os.path.join(tile_dir, f)
        stamp = int(os.path.getmtime(path))
        name = f[:-4]
        old = known.get(name)
        if isinstance(old, dict) and old.get("t") == stamp:
            found[name] = old
            continue
        try:
            found[name] = {"c": accent_colour(Image.open(path)), "t": stamp}
        except Exception as e:  # one broken file shouldn't stop the rest
            print(f"{f}: {e}", file=sys.stderr)
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(found, f, separators=(",", ":"))
    os.replace(tmp, out)


def render(icon_path):
    S = SIZE * SS
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=OUTER_RADIUS * SS, fill=OUTER_FILL)
    i0, i1 = INSET * SS, S - 1 - INSET * SS
    inner = (i0, i0, i1, i1)
    if icon_path:
        inner_size = i1 - i0 + 1
        icon = trim(remove_shadow(load_icon(icon_path, inner_size * 2)))
        if is_square(icon):
            # Already a tile: enlarge a little and let the frame crop the edges
            background, target = INNER_FILL, inner_size * ZOOM
        else:
            # Any other shape: grow it to fill the frame, on its own main colour
            background, target = main_colour(icon), inner_size * FILL
        scale = target / max(icon.size)
        icon = icon.resize((max(1, round(icon.width * scale)), max(1, round(icon.height * scale))), Image.LANCZOS)
        tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(tile).rounded_rectangle(inner, radius=INNER_RADIUS * SS, fill=background)
        tile.alpha_composite(icon, ((S - icon.width) // 2, (S - icon.height) // 2))
        canvas.paste(tile, (0, 0), rounded_mask((S, S), inner, INNER_RADIUS * SS))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def icon_for(cls):
    if not cls:
        return None
    name = desktop_icon(cls) or cls
    return find_icon_file(name) or find_icon_file(cls.lower()) \
        or find_icon_file(cls.split(".")[-1].lower())


TILE_RADIUS = 0.225  # tile (rounded square): corner radius as a share of the tile size
SHAPES = ("tile", "squircle", "circle", "square", "original")
# How much of the tile other shapes grow to when filling it: less for round shapes, whose
# edges cut further in
SHAPE_FILL = {"tile": 1.0, "squircle": 0.94, "circle": 0.84, "square": 1.0}
WHOLE_SIZE = 0.72    # --whole: the icon's size within its tile (the tile itself is drawn by Slate)


def shape_mask(S, shape):
    """The tile's outline, white on black, S×S."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    box = (0, 0, S - 1, S - 1)
    if shape == "circle":
        d.ellipse(box, fill=255)
    elif shape == "square":
        d.rectangle(box, fill=255)
    elif shape == "squircle":
        # Superellipse |x|^n + |y|^n = 1: rounder corners than a rounded square, no flat-to-curve join
        import math
        n, r, c, pts = 4.5, (S - 1) / 2, (S - 1) / 2, []
        for i in range(720):
            t = 2 * math.pi * i / 720
            ct, st = math.cos(t), math.sin(t)
            pts.append((c + r * math.copysign(abs(ct) ** (2 / n), ct), c + r * math.copysign(abs(st) ** (2 / n), st)))
        d.polygon(pts, fill=255)
    else:
        d.rounded_rectangle(box, radius=TILE_RADIUS * S, fill=255)
    return m


def scaled(icon, target):
    scale = target / max(icon.size)
    return icon.resize((max(1, round(icon.width * scale)), max(1, round(icon.height * scale))), Image.LANCZOS)


def render_tile(icon_path, px, shape="tile", fill=True):
    """The app's tile, filling the whole image (dock, launcher, switcher, bar)."""
    S = px * SS
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if shape == "original":
        # No tile: the icon itself, trimmed and grown to fill (--fill) or as it comes
        if icon_path:
            icon = load_icon(icon_path, S)
            if fill:
                icon = scaled(trim(remove_shadow(icon)), S)
            out.alpha_composite(icon, ((S - icon.width) // 2, (S - icon.height) // 2))
        return out.resize((px, px), Image.LANCZOS)
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    background = INNER_FILL
    icon = None
    if icon_path:
        if fill:
            icon = trim(remove_shadow(load_icon(icon_path, px * 2)))
            if is_square(icon):
                icon = scaled(icon, S * ZOOM)          # crop its own border
            else:
                background = main_colour(icon)
                icon = scaled(icon, S * SHAPE_FILL.get(shape, FILL))
        else:
            icon = scaled(trim(load_icon(icon_path, px * 2)), S * WHOLE_SIZE)
            background = None            # Slate draws the tile behind, in the theme's colour
    if background:
        ImageDraw.Draw(tile).rectangle((0, 0, S - 1, S - 1), fill=background)
    if icon:
        tile.alpha_composite(icon, ((S - icon.width) // 2, (S - icon.height) // 2))
    out.paste(tile, (0, 0), shape_mask(S, shape))
    return out.resize((px, px), Image.LANCZOS)


def tile_main(app, out, px, shape="tile", fill=True):
    img = render_tile(icon_for(app), px, shape, fill)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out), suffix=".tmp")
    os.close(fd)
    img.save(tmp, format="PNG")
    os.replace(tmp, out)


def tile_all(out_dir, px, shape="tile", fill=True):
    """Draw a tile for every installed app that doesn't have one yet."""
    seen = set()
    for d in APP_DIRS:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".desktop"):
                continue
            app = f[:-8]
            if app in seen:
                continue
            seen.add(app)
            safe = "".join(c if (c.isascii() and c.isalnum()) or c in "._-" else "_" for c in app)
            out = os.path.join(out_dir, safe + ".png")
            if os.path.isfile(out):
                continue
            try:
                tile_main(app, out, px, shape, fill)
            except Exception as e:  # one broken icon shouldn't stop the rest
                print(f"{app}: {e}", file=sys.stderr)


PREVIEW_APPS = ["firefox", "org.mozilla.firefox", "chromium", "google-chrome", "kitty",
                "org.gnome.Nautilus", "org.kde.dolphin", "steam", "spotify-launcher"]


def preview(out_dir, px):
    """One installed app drawn in every shape, filled and whole: <shape>-fill.png, <shape>-whole.png."""
    path = next((p for p in (icon_for(a) for a in PREVIEW_APPS) if p), None)
    os.makedirs(out_dir, exist_ok=True)
    for shape in SHAPES:
        for fill in (True, False):
            img = render_tile(path, px, shape, fill)
            img.save(os.path.join(out_dir, f"{shape}-{'fill' if fill else 'whole'}.png"), format="PNG")


def style(args):
    """--shape S and --fill / --whole, from the end of the command line."""
    shape, fill = "tile", True
    if "--shape" in args:
        i = args.index("--shape")
        if i + 1 < len(args) and args[i + 1] in SHAPES:
            shape = args[i + 1]
    if "--whole" in args:
        fill = False
    return shape, fill


def style_of_folder(folder):
    """Slate keeps each style's icons in its own folder (tiles/<shape>[-whole], or tiles itself
    for the default), so a folder's name says which style belongs in it. That wins over the
    command line, so a drawing started a moment before a style change can never put icons of
    the old style in the new style's folder."""
    name = os.path.basename(os.path.normpath(folder))
    whole = name.endswith("-whole")
    shape = name[:-len("-whole")] if whole else name
    if shape in SHAPES:
        return shape, not whole
    if name == "tiles":
        return "tile", True
    return None


def main():
    args = sys.argv[1:]
    shape, fill = style(args)
    if len(args) >= 3 and args[0] == "--preview":
        preview(args[1], int(args[2]))
        return
    if len(args) >= 3 and args[0] == "--colours":
        colours(args[1], args[2])
        return
    if len(args) >= 3 and args[0] == "--tile-all":
        shape, fill = style_of_folder(args[1]) or (shape, fill)
        tile_all(args[1], int(args[2]), shape, fill)
        return
    if len(args) >= 4 and args[0] == "--tile":
        shape, fill = style_of_folder(os.path.dirname(args[2])) or (shape, fill)
        tile_main(args[1], args[2], int(args[3]), shape, fill)
        return
    sys.exit(__doc__)

if __name__ == "__main__":
    main()
