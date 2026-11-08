#!/usr/bin/env python3
# Print an accent colour (#rrggbb) taken from a wallpaper image.
# Picks the most prominent vivid colour, then sets its lightness and saturation
# to suit the dark slate theme (similar to the default #8fb3e8).
import colorsys, re, subprocess, sys

img = sys.argv[1]
out = subprocess.run(["magick", img + "[0]", "-resize", "96x96!", "-colors", "12",
                      "-format", "%c", "histogram:info:"], capture_output=True, text=True).stdout
best, best_score = None, -1
import math
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
    if l < 0.08 or l > 0.95:
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
