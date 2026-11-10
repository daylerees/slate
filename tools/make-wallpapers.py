#!/usr/bin/env python3
"""Make Slate's own wallpapers in shell/wallpapers/ (3840 × 2160 PNGs): soft glows of colour
over a deep base, the same looks as the colourful menu bar previews on the website
(.glass-scene in site/style.css), drawn as full-size pictures.

  slate-ember.png    warm reds and oranges, glowing like coals
  slate-iris.png     violet and blue with a blush of pink
  slate-lagoon.png   cyan and deep blue, like shallow water
  slate-blossom.png  pinks and peach, like a sky at dusk

and six more in single colours, drawn the same way:

  slate-fern.png      greens, from leaf to deep forest
  slate-cobalt.png    true blues (Lagoon is the cyan one)
  slate-ruby.png      deep reds (Ember is the orange one)
  slate-honey.png     yellows and gold
  slate-graphite.png  black and greys
  slate-mist.png      white and pale greys, the one light wallpaper

Each comes twice: with Slate's mark in the middle, see-through and in the wallpaper's own
colours (slate-ember.png), and plain (slate-ember-plain.png).

Each is a base gradient with four glows on it: two wide ones rising from the bottom corners,
two reaching down from the top edge. The glows fade out smoothly (no visible rim, which a
plain gradient shows at this size).

Colour this smooth shows bands unless care is taken: across a dark stretch a colour changes by
one step in 256 over a hundred pixels or more, and each step shows as an edge. So every pixel
is rounded up or down by a fixed fine pattern (an 8 × 8 ordered dither), which makes each
small patch average out to the exact colour in between. They're PNGs because JPEG undoes
this: it rounds colour in blocks, and its bands were three times worse than no dithering at
all. The pattern, unlike random grain, repeats, so the PNGs stay around 2.5 MB each.

Needs numpy and Pillow. Run it from anywhere; it writes next to the other wallpapers.

    tools/make-wallpapers.py            all of them
    tools/make-wallpapers.py ember mist     just these
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 3840, 2160
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell", "wallpapers")

# name: the base's top and bottom colours, then the four glows (colour, strength): bottom
# right, bottom left, top left, top right. The colours are the website previews' own.
LOOKS = {
    "ember":   ("#5a1a20", "#1e0d10", [((255, 140, 70), .85), ((220, 50, 60), .80), ((255, 200, 90), .80), ((255, 90, 80), .75)]),
    "iris":    ("#2c1f55", "#120d22", [((90, 140, 255), .75), ((255, 130, 200), .60), ((170, 120, 255), .85), ((110, 170, 255), .70)]),
    "lagoon":  ("#0f3a4f", "#08161f", [((40, 200, 220), .80), ((30, 90, 200), .75), ((120, 240, 220), .80), ((60, 150, 255), .75)]),
    "blossom": ("#4d1f3a", "#1c0c16", [((255, 150, 120), .75), ((200, 70, 150), .75), ((255, 200, 170), .80), ((255, 110, 170), .75)]),
    # Single colours, in the same manner
    "fern":     ("#14402a", "#0a1a12", [((60, 200, 110), .80), ((20, 120, 90), .75), ((160, 230, 120), .75), ((40, 180, 140), .70)]),
    "cobalt":   ("#142a66", "#0a1026", [((50, 110, 255), .80), ((30, 50, 190), .75), ((110, 170, 255), .80), ((70, 90, 240), .75)]),
    "ruby":     ("#5a1020", "#1c080c", [((230, 40, 60), .80), ((160, 20, 50), .75), ((255, 95, 100), .75), ((225, 40, 95), .70)]),
    "honey":    ("#7a5c0c", "#2e2206", [((255, 210, 40), .90), ((235, 165, 20), .80), ((255, 240, 120), .85), ((255, 195, 50), .80)]),
    "graphite": ("#2a2d33", "#0e0f12", [((120, 126, 138), .65), ((70, 74, 84), .60), ((170, 176, 188), .60), ((95, 100, 112), .60)]),
    "mist":     ("#f2f3f5", "#c9ccd2", [((255, 255, 255), .85), ((150, 156, 168), .70), ((255, 255, 255), .80), ((180, 186, 198), .70)]),
}
# Where each glow sits: its centre and its radii, as fractions of the picture's width and
# height, and how far out it reaches (a fraction of those radii)
GLOWS = [
    (0.85, 1.10, 1.20, 1.40, 0.55),      # bottom right, wide
    (0.10, 1.00, 0.90, 1.20, 0.60),      # bottom left
    (0.22, -0.10, 0.45, 1.20, 0.70),     # top left, reaching down
    (0.72, -0.15, 0.40, 1.10, 0.70),     # top right
]


# Slate's mark, in the middle of each: the slab of slate tilted up to the right with its bright
# top edge (SlateMark.qml's shape, on its 18 × 18 grid), 30% of the picture's height, in the
# wallpaper's own colours and see-through, like tinted glass: the edge is the wallpaper's
# brightest glow, the slab a pale wash of it, and the picture shows through both. Each has a
# gentle gradient, as if lit from the upper right, and a soft shadow lifts the mark off the
# picture.
MARK_HEIGHT = 0.30
SLAB = [(3.4, 7.6), (14.6, 4.6), (14.6, 13.4), (3.4, 16.4)]      # its corners (rounded by 0.8)
EDGE = [(3.3, 6.4), (14.7, 3.4)]                                  # the top edge, 2.4 thick, round ends
MARK_TOP, MARK_BOTTOM, MARK_LEFT, MARK_RIGHT = 2.2, 17.2, 2.1, 15.9   # what's drawn, on the grid
MARK_ASPECT = (MARK_RIGHT - MARK_LEFT) / (MARK_BOTTOM - MARK_TOP)
# The edge's colour where the brightest glow wouldn't do (white on white)
EDGE_COLOUR = {"mist": (104, 112, 128)}


def mark_masks():
    """How much of each pixel the slab, its top edge and its shadow cover (0…1)."""
    unit = MARK_HEIGHT * H / (MARK_BOTTOM - MARK_TOP)
    ox = W / 2 - (MARK_LEFT + MARK_RIGHT) / 2 * unit
    oy = H / 2 - (MARK_TOP + MARK_BOTTOM) / 2 * unit
    # Drawn four times the size in a box around the mark, then scaled down, for smooth edges
    ss, pad = 4, int(unit * 3)
    x0, y0 = int(ox + MARK_LEFT * unit) - pad, int(oy + MARK_TOP * unit) - pad
    bw, bh = int((MARK_RIGHT - MARK_LEFT) * unit) + 2 * pad, int((MARK_BOTTOM - MARK_TOP) * unit) + 2 * pad

    def at(p):
        return ((ox + p[0] * unit - x0) * ss, (oy + p[1] * unit - y0) * ss)

    def stroke(d, points, width):
        r = width * unit * ss / 2
        for a, b in zip(points, points[1:]):
            d.line([at(a), at(b)], fill=255, width=round(2 * r))
        for q in points:
            cx, cy = at(q)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    def small(im):
        return np.asarray(im.resize((bw, bh), Image.LANCZOS), dtype=np.float32) / 255

    slab = Image.new("L", (bw * ss, bh * ss), 0)
    d = ImageDraw.Draw(slab)
    d.polygon([at(q) for q in SLAB], fill=255)
    stroke(d, SLAB + SLAB[:1], 1.6)
    edge = Image.new("L", (bw * ss, bh * ss), 0)
    stroke(ImageDraw.Draw(edge), EDGE, 2.4)
    both = Image.fromarray(np.maximum(np.asarray(slab), np.asarray(edge)))
    # The shadow: the whole mark, blurred, a little below
    shadow = both.resize((bw, bh), Image.LANCZOS).filter(ImageFilter.GaussianBlur(unit * 0.9))
    shadow = np.roll(np.asarray(shadow, dtype=np.float32) / 255, int(unit * 0.7), axis=0)

    def full(a):
        out = np.zeros((H, W), dtype=np.float32)
        out[y0:y0 + bh, x0:x0 + bw] = np.clip(a, 0, 1)
        return out[..., None]

    return full(small(slab)), full(small(edge)), full(shadow)


def rgb(hex_colour):
    return np.array([int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


def render(name, mark=True):
    top, bottom, glows = LOOKS[name]
    x = (np.arange(W, dtype=np.float32) + 0.5) / W
    y = (np.arange(H, dtype=np.float32) + 0.5) / H
    xx, yy = np.meshgrid(x, y)
    # The base: top colour to bottom colour, leaning a little (170°, as on the website)
    lean = np.deg2rad(170)
    dx, dy = np.sin(lean) * W, -np.cos(lean) * H
    t = ((xx - 0.5) * W * dx + (yy - 0.5) * H * dy) / (abs(dx) * W + abs(dy) * H) + 0.5
    t = np.clip(t, 0, 1)[..., None]
    img = rgb(top) * (1 - t) + rgb(bottom) * t
    # The glows, the bottom ones first (the top ones lie over them)
    for (cx, cy, rx, ry, reach), (colour, strength) in zip(GLOWS, glows):
        d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2) / reach
        fade = np.clip(1 - d, 0, 1)
        fade = fade * fade * (3 - 2 * fade)              # eased at both ends: no rim, no hot spot
        a = (strength * fade)[..., None]
        img = img * (1 - a) + np.array(colour, dtype=np.float32) * a
    if mark:
        # Slate's mark over it, like tinted glass: the picture shows through both parts
        slab, edge, shadow = MARKS
        light = name == "mist"
        accent = np.array(EDGE_COLOUR.get(name) or max((c for c, _ in glows), key=sum), dtype=np.float32)
        img = img * (1 - shadow * (0.09 if light else 0.20))
        # Each part has a gentle gradient, as if lit from the upper right: across the mark's
        # box, 0 at its bottom left to 1 at its top right
        aspect = W / H
        gx = (xx - 0.5) * aspect / (MARK_HEIGHT * MARK_ASPECT) + 0.5
        gy = 0.5 - (yy - 0.5) / MARK_HEIGHT
        lit = np.clip((gx + gy) / 2, 0, 1)[..., None]
        # The slab: a wash of the edge's colour (paler; on the light wallpaper, a grey), thin at
        # the bottom left and fuller towards the top right (not under the top edge, where the
        # two would show as a paler stripe)
        wash = accent if light else accent * 0.45 + 255 * 0.55
        cover = slab * (1 - edge) * ((0.06 + 0.16 * lit) if light else (0.03 + 0.15 * lit))
        img = img * (1 - cover) + wash * cover
        # The top edge: the colour, brightening along its length, with the picture showing
        # through it too
        along = np.clip(gx, 0, 1)[..., None]
        bar = accent * (0.80 + 0.20 * along) if light else accent + (255 - accent) * 0.40 * along
        cover = edge * (0.36 + 0.26 * along)
        img = img * (1 - cover) + bar * cover
    # Round each pixel up or down by the pattern (see above)
    return Image.fromarray(np.clip(np.floor(img + DITHER), 0, 255).astype(np.uint8), "RGB")


def bayer(n):
    """The n × n ordered dither pattern, as thresholds between 0 and 1."""
    m = np.array([[0]])
    while m.shape[0] < n:
        m = np.block([[4 * m, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / m.size


DITHER = np.tile(bayer(8), (H // 8, W // 8)).astype(np.float32)[..., None]
MARKS = mark_masks()


def main():
    names = sys.argv[1:] or list(LOOKS)
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        if name not in LOOKS:
            sys.exit(f"make-wallpapers: no wallpaper called {name} (there's {', '.join(LOOKS)})")
        # With Slate's mark, and plain
        for mark, file in ((True, f"slate-{name}.png"), (False, f"slate-{name}-plain.png")):
            path = os.path.join(OUT, file)
            render(name, mark).save(path, "PNG", optimize=True)
            print(f"{os.path.relpath(path)}  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
