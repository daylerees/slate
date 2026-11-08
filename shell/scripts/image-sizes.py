#!/usr/bin/env python3
"""Print the pixel size of each image in a folder, as JSON {"name": [width, height], …}.
Only reads each file's header, so it's quick. Used by Settings → Appearance to hide images
too small to be wallpapers.    image-sizes.py <folder>"""
import json, os, sys
from PIL import Image

folder = sys.argv[1]
exts = (".jpg", ".jpeg", ".png", ".webp")
sizes = {}
for name in os.listdir(folder):
    if not name.lower().endswith(exts):
        continue
    try:
        with Image.open(os.path.join(folder, name)) as im:
            sizes[name] = list(im.size)
    except Exception:
        pass                      # unreadable: leave it out (it's shown, not hidden)
print(json.dumps(sizes))
