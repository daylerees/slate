#!/usr/bin/env python3
"""The colours Slate takes from a wallpaper: wallpaper-accent.py <image>

Prints two lines: an accent colour (#rrggbb), the most prominent vivid colour with its
lightness and saturation set to suit the dark theme (like the default #8fb3e8), then the
wallpaper's overall tone (for tinting Slate's greys). Uses ImageMagick (magick). Copied to
the login screen too (greeter/files), so it imports nothing of Slate's own.
"""
import colorsys
import math
import re
import subprocess
import sys

if len(sys.argv) != 2:
    sys.exit(__doc__.split("\n")[0])
img = sys.argv[1]
try:
    # A huge or broken image can keep magick busy: give up after 30 s (the defaults below)
    out = subprocess.run(["magick", img + "[0]", "-resize", "96x96!", "-colors", "12",
                          "-format", "%c", "histogram:info:"], capture_output=True, text=True,
                         timeout=30).stdout
except (OSError, subprocess.SubprocessError):
    out = ""
best, best_score = None, -1
hx = hy = wsat = wtot = 0.0
for line in out.splitlines():
    m = re.match(r"\s*(\d+):.*#([0-9A-Fa-f]{6})", line)
    if not m:
        continue
    count, hexc = int(m.group(1)), m.group(2)
    r, g, b = (int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    # Overall tone: hue averaged round the colour wheel, weighted by area and colourfulness
    hx += math.cos(h * 2 * math.pi) * count * s
    hy += math.sin(h * 2 * math.pi) * count * s
    wsat += s * count
    wtot += count
    # Not near-black, near-white or grey: those give no accent (a grey would come out pink,
    # as its saturation is raised below)
    if l < 0.08 or l > 0.95 or s < 0.06:
        continue
    score = count * (s ** 1.5) * (1 - abs(l - 0.5))
    if score > best_score:
        best, best_score = (h, l, s), score
def tone():
    if wtot == 0 or (hx == 0 and hy == 0):
        return "#1d222a"
    th = (math.atan2(hy, hx) / (2 * math.pi)) % 1
    tr, tg, tb = colorsys.hls_to_rgb(th, 0.5, min(1, wsat / wtot))
    return "#%02x%02x%02x" % (round(tr * 255), round(tg * 255), round(tb * 255))
if best is None:
    print("#8fb3e8")
    print(tone())
    sys.exit()
h, l, s = best
s = min(0.75, max(0.45, s))
r, g, b = colorsys.hls_to_rgb(h, 0.74, s)
print("#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255)))
print(tone())
