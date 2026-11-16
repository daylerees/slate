#!/bin/sh
# Set your account picture (the one AccountsService keeps for GNOME, KDE, Slate's control
# centre, lock screen and login screen). Crops the image to a centred square, scales it to
# 512px, then hands it to AccountsService over D-Bus (which may ask for your password).
# Also saved as ~/.face, which some other apps read.
#   set-avatar.sh [--] <image> [uid]
# uid: someone else's account (Settings → Users; an administrator's password): their picture
# only, no ~/.face.
set -eu
[ "${1:-}" = "--" ] && shift
src=$1
uid=${2:-$(id -u)}
case "$uid" in ''|*[!0-9]*) echo "Slate couldn't tell whose picture that is" >&2; exit 2 ;; esac
dir="${XDG_CACHE_HOME:-$HOME/.cache}/slate"
if [ "$uid" = "$(id -u)" ]; then out="$dir/avatar.png"; else out="$dir/avatar-$uid.png"; fi
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

# ~/.face first, so other apps get it even if AccountsService can't be reached (yours only)
[ "$uid" = "$(id -u)" ] && cp "$out" "$HOME/.face"
# (gdbus, from glib, rather than busctl, which only systemd has)
if ! gdbus call --system --interactive --dest org.freedesktop.Accounts --object-path "/org/freedesktop/Accounts/User$uid" \
        --method org.freedesktop.Accounts.User.SetIconFile "$out" >/dev/null 2>&1; then
    if ! gdbus introspect --system --dest org.freedesktop.Accounts --object-path /org/freedesktop/Accounts >/dev/null 2>&1; then
        echo "AccountsService isn't running (install the accountsservice package); saved as ~/.face only" >&2
    else
        echo "AccountsService didn't accept the picture (was the password prompt canceled?)" >&2
    fi
    exit 1
fi
