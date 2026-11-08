#!/bin/sh
# Set your account picture (the one AccountsService keeps for GNOME, KDE, Slate's control
# centre, lock screen and login screen). Crops the image to a centred square, scales it to
# 512px, then hands it to AccountsService over D-Bus (which may ask for your password).
# Also saved as ~/.face, which some other apps read.
#   set-avatar.sh <image>
set -eu
src=$1
dir="${XDG_CACHE_HOME:-$HOME/.cache}/slate"
out="$dir/avatar.png"
mkdir -p "$dir"

python3 -I - "$src" "$out" <<'PY'
import sys
from PIL import Image, ImageOps
src, out = sys.argv[1], sys.argv[2]
with Image.open(src) as im:
    im = ImageOps.exif_transpose(im).convert("RGBA")
    side = min(im.size)
    im = ImageOps.fit(im, (side, side), Image.LANCZOS)   # centred square crop
    if side > 512:
        im = im.resize((512, 512), Image.LANCZOS)
    im.save(out, "PNG")
PY

busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
    org.freedesktop.Accounts.User SetIconFile s "$out"
cp "$out" "$HOME/.face"
