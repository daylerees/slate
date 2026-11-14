#!/usr/bin/env python3
"""Small pictures of images, from the shared thumbnail cache (the freedesktop.org one file
managers use: ~/.cache/thumbnails/x-large, 512 px), made for any that aren't there yet or are
out of date. The wallpaper switcher's cards show these rather than reading whole wallpapers.

    thumbnails.py <image>…

Prints one line of JSON per image, {"path": …, "thumb": …}: first every one that's already
there (straight away, so the cards fill at once), then each one as it's made. An image that
can't be read is left out; the switcher then shows the image itself."""
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

SIZE = 512
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "thumbnails" / "x-large"


def uri(path):
    return Path(path).absolute().as_uri()


def thumb_of(path):
    return CACHE / (hashlib.md5(uri(path).encode()).hexdigest() + ".png")


def fresh(path, thumb):
    """There, and made from the image as it is now (its Thumb::MTime)."""
    try:
        from PIL import Image
        with Image.open(thumb) as t:
            return t.text.get("Thumb::MTime") == str(int(os.stat(path).st_mtime))
    except Exception:
        return False


def make(path, thumb):
    from PIL import Image, PngImagePlugin
    with Image.open(path) as im:
        im.draft("RGB", (SIZE, SIZE))          # (JPEG: decoded small to start with: much quicker)
        im = im.convert("RGBA" if im.mode in ("RGBA", "LA", "P") else "RGB")
        im.thumbnail((SIZE, SIZE))
        info = PngImagePlugin.PngInfo()
        st = os.stat(path)
        info.add_text("Thumb::URI", uri(path))
        info.add_text("Thumb::MTime", str(int(st.st_mtime)))
        info.add_text("Thumb::Size", str(st.st_size))
        info.add_text("Software", "Slate")
        CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, tmp = tempfile.mkstemp(dir=CACHE, suffix=".png")
        try:
            with os.fdopen(fd, "wb") as fh:
                im.save(fh, "PNG", pnginfo=info)
            os.chmod(tmp, 0o600)
            os.replace(tmp, thumb)              # (whole, never half written)
        except BaseException:
            os.unlink(tmp)
            raise


def say(path, thumb):
    print(json.dumps({"path": path, "thumb": str(thumb)}), flush=True)


def main(paths):
    todo = []
    for p in paths:
        t = thumb_of(p)
        if fresh(p, t):
            say(p, t)
        else:
            todo.append((p, t))
    for p, t in todo:
        try:
            make(p, t)
            say(p, t)
        except Exception as e:                  # (unreadable: the switcher shows the image itself)
            print("thumbnails: %s: %s" % (os.path.basename(p), e), file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
