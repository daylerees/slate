#!/usr/bin/env python3
"""Render Slate's logo: the slate mark (tools/render-settings-icon.py, without its tile) beside
"slate" set in Geist, in dark slate: made for light backgrounds (GitHub's light theme).

    tools/render-logo.py <out.png> [height px] [wordmark #rrggbb] [--flat]

--flat uses the straight-on mark (for small sizes, where it lines up with the text).

Needs Pillow."""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

here = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
flat = "--flat" in sys.argv
out = args[0]
H = int(args[1]) if len(args) > 1 else 160          # logo height (2× the README's 80)
ink = args[2] if len(args) > 2 else "#1d222a"
ink = tuple(int(ink.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) + (255,)

# The mark, from the same renderer as the Settings / app icon (without the tile), cropped to
# what's drawn and scaled to the logo's height
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable, os.path.join(here, "render-settings-icon.py"), tmp, "--mark-only"] + (["--flat"] if flat else []),
                   check=True, stdout=subprocess.DEVNULL)
    mark = Image.open(os.path.join(tmp, "settings-512.png")).convert("RGBA")
mark = mark.crop(mark.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
icon = mark.resize((round(mark.width * H / mark.height), H), Image.LANCZOS)

# The wordmark: Geist SemiBold, lower case, a little open tracking, centred on the tile
font = ImageFont.truetype(os.path.join(here, "..", "shell", "fonts", "Geist-Variable.ttf"), round(H * 0.56))
font.set_variation_by_axes([600])
word, track = "slate", round(H * 0.012)
widths = [font.getlength(c) for c in word]
text_w = round(sum(widths) + track * (len(word) - 1))
gap = round(H * 0.16)
W = icon.width + gap + text_w + round(H * 0.04)
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
img.alpha_composite(icon, (0, 0))
d = ImageDraw.Draw(img)
# Vertically: centre the x-height on the tile's middle (ignores the ascender of "l" and "t").
# Straight on (--flat), the slab reads as a block, so the whole word is centred on the solid
# slab instead (not its soft shadow)
if flat:
    solid = icon.getchannel("A").point(lambda a: 255 if a > 200 else 0).getbbox()
    mid = (solid[1] + solid[3]) / 2
    x0, y0, x1, y1 = font.getbbox("slate")
    y = round(mid - (y0 + y1) / 2)
else:
    x0, y0, x1, y1 = font.getbbox("ase")
    y = round(H / 2 - (y0 + y1) / 2)
x = icon.width + gap
for c, w in zip(word, widths):
    d.text((x, y), c, font=font, fill=ink)
    x += w + track
img.save(out, optimize=True)
print(out, img.size)
