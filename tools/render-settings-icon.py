#!/usr/bin/env python3
"""Render Slate's settings/app icon: the slate mark (as drawn by SlateLogo.qml: a shaded slab
with its side showing and an accent edge) on a dark rounded tile.

    tools/render-settings-icon.py <out-dir> [accent #rrggbb] [--mark-only] [--flat]

Writes settings-<size>.png for 512, 256, 128, 64, 48, 32 and 16 px. --mark-only leaves out
the tile, for the mark on its own (the logo, tools/render-logo.py). --flat draws the slab
straight on instead of at an angle (for small sizes beside text, like the site's header).
Needs Pillow."""
import sys
from PIL import Image, ImageDraw, ImageFilter

args = [a for a in sys.argv[1:] if not a.startswith("--")]
mark_only = "--mark-only" in sys.argv
flat = "--flat" in sys.argv
out = args[0]
accent = args[1] if len(args) > 1 else "#8fb3e8"
S = 2048                                  # drawn large, scaled down for smooth edges
MARK = 0.58                               # how much of the tile the mark spans

def lerp(a, b, t): return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))
def hexc(h, a=255): h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)
def lighter(c, f): return tuple(min(255, round(v + (255 - v) * f)) for v in c[:3]) + (c[3],)

def vgrad(c0, c1, y0=0, y1=S):
    g = Image.new("RGBA", (S, S)); d = ImageDraw.Draw(g)
    for y in range(S): d.line([(0, y), (S, y)], fill=lerp(c0, c1, min(1, max(0, (y - y0) / (y1 - y0)))))
    return g

# Tile: rounded square with a slate gradient and a faint rim
pad, r = round(S * 0.06), round(S * 0.23)
tile_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(tile_mask).rounded_rectangle([pad, pad, S - pad, S - pad], r, fill=255)
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
if not mark_only:
    img.paste(vgrad(hexc("#232933"), hexc("#0c0f13")), (0, 0), tile_mask)
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([pad, pad, S - pad, S - pad], r, outline=(255, 255, 255, 22), width=round(S * 0.006))
    img.alpha_composite(rim)

# The mark on its 64×64 grid (same shapes as SlateLogo.qml), centred on the tile
k = S * MARK / 50
cx, cy = 32.2, 35.8
def P(x, y): return (S / 2 + (x - cx) * k, S / 2 + (y - cy) * k)
def rounded_poly(draw, pts, rad, fill):
    draw.polygon([P(*p) for p in pts], fill=fill)
    draw.line([P(*p) for p in pts + [pts[0]]], fill=fill, width=round(rad * 2 * k), joint="curve")
    for p in pts:
        x, y = P(*p); rr = rad * k
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)
def capsule(draw, a, b, w, fill):
    draw.line([P(*a), P(*b)], fill=fill, width=round(w * k))
    for q in (a, b):
        x, y = P(*q); rr = w * k / 2
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)

if flat:
    # Straight on: the face, a sliver of its thickness below, a level grain line and the
    # accent edge along the top
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([P(13, 24), P(53, 58)], fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img.alpha_composite(shadow if mark_only else Image.composite(shadow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), tile_mask))
    R = 5.0                                   # corner radius (grid units)
    def rrect(draw, x0, y0, x1, y1, rad, fill):
        (a0, b0), (a1, b1) = P(x0, y0), P(x1, y1)
        draw.rounded_rectangle([a0, b0, a1, b1], round(rad * k), fill=fill)
    side = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rrect(ImageDraw.Draw(side), 12.6, 22.0, 51.8, 54.0, R, hexc("#20262f"))
    img.alpha_composite(side)
    face_mask = Image.new("L", (S, S), 0)
    rrect(ImageDraw.Draw(face_mask), 12.6, 18.6, 51.8, 50.6, R, 255)
    img.paste(vgrad(hexc("#66738a"), hexc("#363f4e"), P(0, 18)[1], P(0, 52)[1]), (0, 0), face_mask)
    grain = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(grain).line([P(15.0, 39.0), P(49.4, 39.0)], fill=(255, 255, 255, 40), width=round(1.0 * k))
    img.alpha_composite(grain)
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    # the edge follows the rounded top: inset so its caps sit inside the corners
    edge_mask = Image.new("L", (S, S), 0)
    rrect(ImageDraw.Draw(edge_mask), 12.6, 16.4, 51.8, 50.6, R, 255)
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(band).rectangle([P(10, 15), P(54, 21.0)], fill=hexc(accent))
    edge.paste(band, (0, 0), Image.composite(edge_mask, Image.new("L", (S, S), 0), band.getchannel("A")))
    capsule(ed, (18.0, 17.6), (46.4, 17.6), 1.4, lighter(hexc(accent), 0.45))
    img.alpha_composite(edge)
else:
    # Soft shadow under the slab, kept inside the tile
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([P(12, 30), P(52, 20), P(54, 52), P(12, 62)], fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img.alpha_composite(shadow if mark_only else Image.composite(shadow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), tile_mask))

    # Side (thickness), face (lit from the top), grain line, accent edge with a sheen
    side = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rounded_poly(ImageDraw.Draw(side), [(11.2, 26.2), (13.6, 25.6), (13.6, 55.4), (50.8, 45.4), (49.6, 48.9), (11.2, 59.2)], 1.3, hexc("#20262f"))
    img.alpha_composite(side)
    face_mask = Image.new("L", (S, S), 0)
    rounded_poly(ImageDraw.Draw(face_mask), [(15.8, 24.9), (52.4, 15.0), (52.4, 44.2), (14.6, 54.4)], 1.7, 255)
    img.paste(vgrad(hexc("#66738a"), hexc("#363f4e"), P(0, 14)[1], P(0, 56)[1]), (0, 0), face_mask)
    grain = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(grain).line([P(15.2, 42.0), P(51.8, 32.2)], fill=(255, 255, 255, 40), width=round(1.0 * k))
    img.alpha_composite(grain)
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    capsule(ed, (14.6, 22.6), (52.6, 12.4), 4.4, hexc(accent))
    capsule(ed, (18.5, 20.6), (48.5, 12.6), 1.4, lighter(hexc(accent), 0.45))
    img.alpha_composite(edge)

for size in (512, 256, 128, 64, 48, 32, 16):
    img.resize((size, size), Image.LANCZOS).save(f"{out}/settings-{size}.png")
print("rendered", out)
