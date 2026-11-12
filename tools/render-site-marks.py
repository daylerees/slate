#!/usr/bin/env python3
"""Render the site's two pictures of Slate's mark, from the shape Slate itself draws
(SlateMark.qml, on its 18 × 18 grid: a slab of slate with the accent along its top edge),
the same mark that's on the wallpapers, the bar and the dock:

    site/assets/logo.png   the header: the mark seen straight on, beside "slate" in Geist
    site/assets/mark.png   the hero: the mark tilted up to the right, lit from the upper right,
                           with a soft shadow under it

    tools/render-site-marks.py [site/assets]

Needs Pillow and numpy."""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "site", "assets")

BODY = (0x56, 0x61, 0x73)        # SlateMark's body
ACCENT = (0x8f, 0xb3, 0xe8)      # Slate's default accent (the site's --accent)
INK = (0xee, 0xf1, 0xf5)         # the wordmark, light on the site's dark header

# SlateMark.qml's shape: the slab's corners (outlined 1.6 wide with round joins, which rounds
# them) and its top edge (2.4 wide, round ends), straight on and tilted
SHAPES = {
    "flat": {"slab": [(3.4, 5.7), (14.6, 5.7), (14.6, 14.1), (3.4, 14.1)], "edge": [(3.3, 4.1), (14.7, 4.1)]},
    "tilted": {"slab": [(3.4, 7.6), (14.6, 4.6), (14.6, 13.4), (3.4, 16.4)], "edge": [(3.3, 6.4), (14.7, 3.4)]},
}
SS = 4                           # drawn this many times the size, then scaled down, for smooth edges


def masks(shape, unit, pad):
    """The slab's and the edge's coverage (0…1), cropped to what's drawn plus `pad` px."""
    pts = shape["slab"] + shape["edge"]
    left = min(p[0] for p in pts) - 1.2
    top = min(p[1] for p in pts) - 1.2
    right = max(p[0] for p in pts) + 1.2
    bottom = max(p[1] for p in pts) + 1.2
    w = round((right - left) * unit) + 2 * pad
    h = round((bottom - top) * unit) + 2 * pad

    def at(p):
        return ((pad + (p[0] - left) * unit) * SS, (pad + (p[1] - top) * unit) * SS)

    def stroke(d, points, width):
        r = width * unit * SS / 2
        for a, b in zip(points, points[1:]):
            d.line([at(a), at(b)], fill=255, width=round(2 * r))
        for q in points:
            cx, cy = at(q)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    slab = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(slab)
    d.polygon([at(q) for q in shape["slab"]], fill=255)
    stroke(d, shape["slab"] + shape["slab"][:1], 1.6)
    edge = Image.new("L", (w * SS, h * SS), 0)
    stroke(ImageDraw.Draw(edge), shape["edge"], 2.4)

    def small(im):
        return np.asarray(im.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255

    return small(slab), small(edge)


def compose(slab, edge, body, accent):
    """The mark in RGBA: the edge over the slab. `body` and `accent` are colours, or arrays of
    colours (one per pixel)."""
    body = np.broadcast_to(np.asarray(body, dtype=np.float32), slab.shape + (3,))
    accent = np.broadcast_to(np.asarray(accent, dtype=np.float32), slab.shape + (3,))
    e = edge[..., None]
    alpha = np.clip(slab + edge * (1 - slab), 0, 1)
    # colour: the edge over the slab, weighted by their coverage
    rgb = (accent * e + body * slab[..., None] * (1 - e)) / np.maximum(alpha[..., None], 1e-6)
    return np.dstack([rgb, alpha * 255])


def to_image(a):
    return Image.fromarray(np.clip(np.round(a), 0, 255).astype(np.uint8), "RGBA")


# ---- The header: straight on, beside the wordmark ----------------------------------------
MARK_SHARE = 0.84                # the mark's height, of the logo's
def logo(H=160):
    shape = SHAPES["flat"]
    pts = shape["slab"] + shape["edge"]
    span = max(p[1] for p in pts) - min(p[1] for p in pts) + 2.4      # what's drawn, top to bottom
    unit = H / span
    slab, edge = masks(shape, unit, 0)
    icon = to_image(compose(slab, edge, BODY, ACCENT))
    icon = icon.crop(icon.getchannel("A").getbbox())
    # The mark a little shorter than the picture (about the size the old 3D slab was), centred
    ih = round(H * MARK_SHARE)
    icon = icon.resize((round(icon.width * ih / icon.height), ih), Image.LANCZOS)
    top = (H - ih) // 2

    # "slate" in Geist SemiBold, lower case, a little open tracking (as tools/render-logo.py)
    font = ImageFont.truetype(os.path.join(here, "..", "shell", "fonts", "Geist-Variable.ttf"), round(H * 0.56))
    font.set_variation_by_axes([600])
    word, track = "slate", round(H * 0.012)
    widths = [font.getlength(c) for c in word]
    text_w = round(sum(widths) + track * (len(word) - 1))
    # Spaced as the old logo was: the word's letters about 0.27 of the height after the mark, and the
    # word's x-height (not its ascenders) centred on the mark
    gap = round(H * 0.24)
    img = Image.new("RGBA", (icon.width + gap + text_w + round(H * 0.04), H), (0, 0, 0, 0))
    img.alpha_composite(icon, (0, top))
    x0, y0, x1, y1 = font.getbbox("ase")
    y = round(top + ih / 2 - (y0 + y1) / 2)
    d = ImageDraw.Draw(img)
    x = icon.width + gap
    for c, w in zip(word, widths):
        d.text((x, y), c, font=font, fill=INK + (255,))
        x += w + track
    return img


# ---- The hero: tilted, lit, with a shadow -----------------------------------------------
def hero(H=396):
    shape = SHAPES["tilted"]
    pts = shape["slab"] + shape["edge"]
    span = max(p[1] for p in pts) - min(p[1] for p in pts) + 2.4
    pad = round(H * 0.10)
    unit = (H - 2 * pad) / span
    slab, edge = masks(shape, unit, pad)
    h, w = slab.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # As on the wallpapers: lit from the upper right, 0 at the bottom left to 1 at the top right
    lit = np.clip(((xx - pad) / (w - 2 * pad) + 1 - (yy - pad) / (h - 2 * pad)) / 2, 0, 1)[..., None]
    along = np.clip((xx - pad) / (w - 2 * pad), 0, 1)[..., None]
    body = np.asarray(BODY, dtype=np.float32)
    body = body * (0.78 + 0.34 * lit)                             # darker low left, brighter up right
    accent = np.asarray(ACCENT, dtype=np.float32)
    accent = accent * (0.92 + 0.08 * along) + (255 - accent) * 0.30 * along   # brightening along it
    mark = compose(slab, edge, body, accent)
    # The shadow: the whole mark, blurred, a little below
    both = np.clip(slab + edge, 0, 1)
    shadow = Image.fromarray((both * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(unit * 0.9))
    shadow = np.roll(np.asarray(shadow, dtype=np.float32) / 255, round(unit * 0.7), axis=0) * 0.55
    under = np.dstack([np.zeros((h, w, 3), np.float32), shadow * 255])
    img = to_image(under)
    img.alpha_composite(to_image(mark))
    return img.crop(img.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox())


for name, im in (("logo.png", logo()), ("mark.png", hero())):
    path = os.path.join(out_dir, name)
    im.save(path, optimize=True)
    print(path, im.size)
