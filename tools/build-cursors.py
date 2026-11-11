#!/usr/bin/env python3
"""Build Slate Cursors: Bibata Modern Ice (GPL-3.0, github.com/ful1e5/Bibata_Cursor)
redrawn without colour, so every cursor matches the white pointer.

    tools/build-cursors.py [BIBATA_DIR] [OUT_DIR]
      BIBATA_DIR  an installed Bibata-Modern-Ice (default ~/.local/share/icons/Bibata-Modern-Ice)
      OUT_DIR     where to write the theme   (default shell/cursors/Slate-Cursors)

What changes (everything else is copied as it is):
  - the corner resize cursors' coloured quarter-circles become white, like the sides
  - the loading spinner's four colours become four greys (so it still visibly turns), and it
    keeps one hotspot through its frames (Bibata's alternates between two, which made it wobble)
  - the coloured badges (copy, not-allowed, link, help…) become dark grey, keeping their
    white symbols; the crosshair's red dot becomes black
Both formats are written: hyprcursors/ (SVG, used by Hyprland) and cursors/ (XCursor
images for other apps), redrawn from the recoloured SVGs at the original sizes.
Needs: rsvg-convert (librsvg) and Pillow.
"""
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image

NAME = "Slate-Cursors"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/share/icons/Bibata-Modern-Ice")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "shell", "cursors", NAME)

BADGE = "#3A3F47"
RECOLOUR = {
    # Corner resize cursors
    "#FDBE2A": "#FFFFFF", "#96C865": "#FFFFFF", "#4FADDF": "#FFFFFF", "#F1613A": "#FFFFFF",
    # Loading spinner
    "#32A0DA": "#2E333B", "#7EBA41": "#5C6470", "#F05024": "#8D96A3", "#FCB813": "#C3C9D2",
    # Badges and markers
    "#06B231": BADGE, "#179DD8": BADGE, "#5F3BE4": BADGE, "#F27400": BADGE, "#606060": BADGE,
    "#FE0000": "#000000",
}
COLOUR = re.compile("|".join(re.escape(k) for k in RECOLOUR), re.IGNORECASE)


def recolour(svg):
    return COLOUR.sub(lambda m: RECOLOUR[m.group(0).upper()], svg)


# ---- XCursor files --------------------------------------------------------------------
IMAGE = 0xFFFD0002


def read_xcursor(path):
    """[(nominal, width, height, xhot, yhot, delay)] in file order."""
    data = open(path, "rb").read()
    if data[:4] != b"Xcur":
        raise ValueError(path + ": not an XCursor file")
    hsize, _, ntoc = struct.unpack_from("<III", data, 4)
    frames = []
    for i in range(ntoc):
        typ, _, pos = struct.unpack_from("<III", data, hsize + i * 12)
        if typ != IMAGE:
            continue
        _, _, nominal, _, w, h, xh, yh, delay = struct.unpack_from("<9I", data, pos)
        frames.append((nominal, w, h, xh, yh, delay))
    return frames


def write_xcursor(path, images):
    """images: [(nominal, PIL RGBA image, xhot, yhot, delay)]"""
    head = struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(images))
    toc, chunks = b"", b""
    pos = 16 + 12 * len(images)
    for nominal, im, xh, yh, delay in images:
        raw, px = im.tobytes(), bytearray()
        for i in range(0, len(raw), 4):          # ARGB, premultiplied, little-endian
            r, g, b, a = raw[i:i + 4]
            px += struct.pack("<I", (a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
        chunk = struct.pack("<9I", 36, IMAGE, nominal, 1, im.width, im.height, xh, yh, delay) + bytes(px)
        toc += struct.pack("<III", IMAGE, nominal, pos)
        chunks += chunk
        pos += len(chunk)
    with open(path, "wb") as f:
        f.write(head + toc + chunks)


def render(svg_text, w, h):
    with tempfile.NamedTemporaryFile(suffix=".svg") as t:
        t.write(svg_text.encode())
        t.flush()
        png = subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), t.name],
                             check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


# ---- Build ----------------------------------------------------------------------------
# The diagonal double arrows' names, given to the window corner cursors instead: Qt can only ask
# for the double arrows (its SizeFDiag/SizeBDiag), so Slate's own title bar corners showed a
# different cursor from Hyprland's window corners (which use the corner ones). Moved in both the
# hyprcursor overrides and the XCursor symlinks.
REMAP = {"nwse-resize": "top_left_corner", "size_fdiag": "top_left_corner",
         "nesw-resize": "top_right_corner", "size_bdiag": "top_right_corner"}


def remap_aliases(out):
    hc = os.path.join(out, "hyprcursors")
    metas = {}
    for fn in os.listdir(hc):
        if fn.endswith(".hlc"):
            with zipfile.ZipFile(os.path.join(hc, fn)) as z:
                metas[fn[:-4]] = {n: z.read(n) for n in z.namelist()}
    changed = set()
    for alias, target in REMAP.items():
        line = "define_override = %s" % alias
        for name, files in metas.items():
            meta = files["meta.hl"].decode()
            has = any(l.strip() == line for l in meta.splitlines())
            if has == (name == target):
                continue
            lines = [l for l in meta.splitlines() if l.strip() != line]
            if name == target:
                lines.append(line)
            files["meta.hl"] = ("\n".join(lines).rstrip("\n") + "\n").encode()
            changed.add(name)
        # XCursor: the name links to the corner image
        link = os.path.join(out, "cursors", alias)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(target, link)
    for name in changed:                     # (only the cursors whose names moved)
        files = metas[name]
        with zipfile.ZipFile(os.path.join(hc, name + ".hlc"), "w", zipfile.ZIP_DEFLATED) as z:
            for n, d in files.items():
                z.writestr(n, d)


def main():
    if not os.path.isdir(os.path.join(SRC, "hyprcursors")):
        sys.exit("No Bibata-Modern-Ice at %s (needs its hyprcursors/ and cursors/)" % SRC)
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(os.path.join(OUT, "hyprcursors"))
    shutil.copytree(os.path.join(SRC, "cursors"), os.path.join(OUT, "cursors"), symlinks=True)

    changed = 0
    for fn in sorted(os.listdir(os.path.join(SRC, "hyprcursors"))):
        if not fn.endswith(".hlc"):
            continue
        name = fn[:-4]
        src_zip = zipfile.ZipFile(os.path.join(SRC, "hyprcursors", fn))
        files = {n: src_zip.read(n) for n in src_zip.namelist()}
        svgs = {n: d.decode() for n, d in files.items() if n.endswith(".svg")}
        new = {n: recolour(t) for n, t in svgs.items()}
        # Repack the hyprcursor (SVGs + meta.hl)
        with zipfile.ZipFile(os.path.join(OUT, "hyprcursors", fn), "w", zipfile.ZIP_DEFLATED) as z:
            for n, d in files.items():
                z.writestr(n, new[n].encode() if n in new else d)
        if new == svgs:
            continue
        changed += 1
        # Redraw the matching XCursor file at each of its sizes, frame by frame
        xc = os.path.join(OUT, "cursors", name)
        if not os.path.isfile(xc) or os.path.islink(xc):
            continue
        meta = files.get("meta.hl", b"").decode()
        order = [m.group(1) for m in re.finditer(r"define_size\s*=\s*\d+\s*,\s*([^,\s]+\.svg)", meta)] or sorted(new)
        frames = read_xcursor(xc)
        # An animated cursor keeps one hotspot through all its frames at a size (the one most
        # of them have). Bibata's loading spinner alternates between two a pixel apart, and
        # since a cursor is placed by its hotspot, the spinner shifted left and right as it turned
        steady = {}
        for nominal in {f[0] for f in frames}:
            spots = [(f[3], f[4]) for f in frames if f[0] == nominal]
            steady[nominal] = max(sorted(set(spots)), key=spots.count)
        seen, images = {}, []
        for nominal, w, h, xh, yh, delay in frames:
            i = seen.get(nominal, 0)
            seen[nominal] = i + 1
            xh, yh = steady[nominal]
            images.append((nominal, render(new[order[i % len(order)]], w, h), xh, yh, delay))
        write_xcursor(xc, images)

    remap_aliases(OUT)

    # Theme files, renamed so it's never mistaken for (or replaced by) Bibata itself
    with open(os.path.join(OUT, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=%s\nComment=Slate's cursors: Bibata Modern Ice without colour\nInherits=hicolor\n" % NAME)
    with open(os.path.join(OUT, "cursor.theme"), "w") as f:
        f.write("[Icon Theme]\nName=%s\nInherits=%s\n" % (NAME, NAME))
    manifest = open(os.path.join(SRC, "manifest.hl")).read()
    manifest = re.sub(r"(?m)^name\s*=.*$", "name = " + NAME, manifest)
    manifest = re.sub(r"(?m)^description\s*=.*$", "description = Slate's cursors: Bibata Modern Ice without colour", manifest)
    with open(os.path.join(OUT, "manifest.hl"), "w") as f:
        f.write(manifest)
    lic = os.path.join(ROOT, "tools", "cursors", "LICENSE")
    shutil.copy(lic, os.path.join(OUT, "LICENSE"))
    shutil.copy(os.path.join(ROOT, "tools", "cursors", "README.md"), os.path.join(OUT, "README.md"))
    print("%s: %d cursors recoloured -> %s" % (NAME, changed, OUT))


if __name__ == "__main__":
    main()
