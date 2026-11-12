#!/usr/bin/env python3
"""A few well-made pointer and icon themes, put in with one click (Settings → Input → More
pointer styles, Appearance → More icon styles).

  theme-packs.py --list           JSON: [{"id", "kind", "name", "about", "themes", "installed"}]
  theme-packs.py --install <id>   download it, check it, and put it in ~/.local/share/icons

Each comes from its makers' own release on GitHub, pinned to one version and checked against
the fingerprint (SHA-256) it had when Slate chose it, so what arrives is what was looked at.
Nothing is run from it, and it goes in your own icons folder: no password, and the same on
every distro. Only the theme folders named are taken from each download, and only files and
links that stay inside them (no absolute paths, no "..", no devices; a link may point into
another theme of the same pack, as Kora Grey's do into Kora, but nowhere else).
A theme that's already there is replaced. Pointer style and Icons list them straight after.

Exit codes: 0 done; 1 something went wrong (said on stderr); 2 bad arguments.
SLATE_THEME_PACKS (a JSON file of packs in the same shape) replaces the list, for tests.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

HOME = os.path.expanduser("~")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
ICONS = os.path.join(DATA, "icons")
MAX_BYTES = 80 * 1024 * 1024          # (the biggest here is about 11 MB)

GH = "https://github.com/"
PACKS = [
    # ---- Pointers ----
    {"id": "phinger", "kind": "cursors", "name": "Phinger",
     "about": "Soft, rounded and quiet, in light or dark",
     "files": [{"url": GH + "phisch/phinger-cursors/releases/download/v2.2/phinger-cursors-variants.tar.bz2",
                "sha256": "46d4cfc30a38c19cada3339027b5a78f7b0bf74f3220eba7001c4fdd9d5a6e56",
                "take": {"./phinger-cursors-light": "phinger-cursors-light", "./phinger-cursors-dark": "phinger-cursors-dark"}}]},
    {"id": "apple", "kind": "cursors", "name": "Apple Cursor",
     "about": "The Mac's pointer, redrawn, in black or white",
     "files": [{"url": GH + "ful1e5/apple_cursor/releases/download/v2.0.1/macOS.tar.xz",
                "sha256": "9c6e5e13b068ce51a9e90a9abd6ce232ec7d25d4ceb05aa8ac76efbb99c76762",
                "take": {"./macOS": "macOS", "./macOS-White": "macOS-White"}}]},
    {"id": "bibata", "kind": "cursors", "name": "Bibata",
     "about": "The shape Slate's own pointer comes from, in black or amber",
     "files": [{"url": GH + "ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Classic.tar.xz",
                "sha256": "7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8",
                "take": {"Bibata-Modern-Classic": "Bibata-Modern-Classic"}},
               {"url": GH + "ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Amber.tar.xz",
                "sha256": "58b7ac00ed3cb45acb6b917cb9807a553873f1cca5c91348c4abaebe638e5884",
                "take": {"Bibata-Modern-Amber": "Bibata-Modern-Amber"}}]},
    {"id": "nordzy-cursors", "kind": "cursors", "name": "Nordzy",
     "about": "Soft and rounded, in dark or white",
     "files": [{"url": GH + "guillaumeboehm/Nordzy-cursors/releases/download/v2.4.0/Nordzy-cursors.tar.gz",
                "sha256": "3451c1221d58562a5eb647c45f3f7b5e2bbfe0aacf10d9cbc899bc36e5239e5a",
                "take": {"Nordzy-cursors": "Nordzy-cursors"}},
               {"url": GH + "guillaumeboehm/Nordzy-cursors/releases/download/v2.4.0/Nordzy-cursors-white.tar.gz",
                "sha256": "5873641192f7c89692f1335c525969879307482c0f70283142f3fa65cfa74ff6",
                "take": {"Nordzy-cursors-white": "Nordzy-cursors-white"}}]},
    {"id": "rosepine", "kind": "cursors", "name": "Rosé Pine",
     "about": "A gentle, dusky take on KDE's pointer, in dark or light (Dawn)",
     "files": [{"url": GH + "rose-pine/cursor/releases/download/v1.1.0/BreezeX-RosePine-Linux.tar.xz",
                "sha256": "b330d59ce8e0e460209f638a97ce772b78d9e6b56ccf63c8a50e9d941289a1af",
                "take": {"BreezeX-RosePine-Linux": "BreezeX-RosePine-Linux"}},
               {"url": GH + "rose-pine/cursor/releases/download/v1.1.0/BreezeX-RosePineDawn-Linux.tar.xz",
                "sha256": "85a9dfc31f68a13d536e67200abeb72956300b5388cd3c239b1ce2e198dcadd8",
                "take": {"BreezeX-RosePineDawn-Linux": "BreezeX-RosePineDawn-Linux"}}]},
    {"id": "catppuccin", "kind": "cursors", "name": "Catppuccin",
     "about": "Pastel pointers: Mocha dark, Latte light, Mocha lavender and Macchiato blue",
     "files": [{"url": GH + "catppuccin/cursors/releases/download/v2.0.0/catppuccin-%s-cursors.zip" % v,
                "sha256": h, "take": {"catppuccin-%s-cursors" % v: "catppuccin-%s-cursors" % v}}
               for v, h in (("mocha-dark", "a4d976491bdb1b1311b2de88327cad3f1c66c2d9da896e0c56362a660c802585"),
                            ("latte-light", "4c0752cfa2da6c4cbcfe9539ca92585144b34651f22acf6cecf18850cb938880"),
                            ("mocha-lavender", "9e8c67efd4c8ff75f09196fa8579ca366c5a4ea204f541edd7b49ab0cb44d9cf"),
                            ("macchiato-blue", "4c66fba0272661f03dee2e5ffefd1829e1a94625781237804bc791ca5a781c42"))]},
    # ---- Icons ----
    {"id": "kora", "kind": "icons", "name": "Kora",
     "about": "Soft, colourful and rounded, in colour or grey",
     "files": [{"url": GH + "bikass/kora/archive/refs/tags/v2.0.6.tar.gz",
                "sha256": "159bdb7a09409a12e54a71136ec8889c51b0bf7c145c8b20e3509dc1e90089bd",
                "take": {"kora-2.0.6/kora": "kora", "kora-2.0.6/kora-pgrey": "kora-pgrey"}}]},
    {"id": "morewaita", "kind": "icons", "name": "MoreWaita",
     "about": "GNOME's own look, with icons for many more apps",
     "files": [{"url": GH + "somepaulo/MoreWaita/archive/refs/tags/v50.1.tar.gz",
                "sha256": "000e858d346e64bfdb87fb305e8046e09f5554385cf9c213fe648887fe218940",
                "take": {"MoreWaita-50.1": "MoreWaita"}}]},
    {"id": "numix-circle", "kind": "icons", "name": "Numix Circle",
     "about": "Bright, round app icons, in light or dark",
     "files": [{"url": GH + "numixproject/numix-icon-theme-circle/archive/refs/tags/26.02.21.tar.gz",
                "sha256": "0a64821bc9ce005be4d2d2786bcbbfb0e908932e1c3c4cf65859da2cccd598ba",
                "take": {"numix-icon-theme-circle-26.02.21/Numix-Circle": "Numix-Circle",
                         "numix-icon-theme-circle-26.02.21/Numix-Circle-Light": "Numix-Circle-Light"}},
               # (the theme it builds on, for everything that isn't an app)
               {"url": GH + "numixproject/numix-icon-theme/archive/refs/tags/25.12.15.tar.gz",
                "sha256": "20db3921eecb024139dbf0c20b32101b48f464a56c5072cb2fd7d41581e1816d",
                "take": {"numix-icon-theme-25.12.15/Numix": "Numix", "numix-icon-theme-25.12.15/Numix-Light": "Numix-Light"}}]},
    {"id": "zafiro", "kind": "icons", "name": "Zafiro",
     "about": "Flat, soft and pastel, in dark or light",
     "files": [{"url": GH + "zayronxio/Zafiro-icons/releases/download/1.3/Zafiro-Icons-Dark.tar.xz",
                "sha256": "7780c0f824eae40cbe167a0ab2f5f2a33be41156c5ea52c789969965264db0b5",
                "take": {"Zafiro-Icons-Dark": "Zafiro-Icons-Dark"}},
               {"url": GH + "zayronxio/Zafiro-icons/releases/download/1.3/Zafiro-Icons-Light.tar.xz",
                "sha256": "eda5cad186239edbb0c8d8fb57d71be3de305f8e31eaef37e8e4cc22ebef1317",
                "take": {"Zafiro-Icons-Light": "Zafiro-Icons-Light"}}]},
    {"id": "nordzy-icons", "kind": "icons", "name": "Nordzy",
     "about": "Clean and rounded, in light or dark",
     "files": [{"url": GH + "alvatip/Nordzy-icon/releases/download/1.8.7/Nordzy.tar.gz",
                "sha256": "38c346bc4de165b79d5b678284b63cc0fa058dccea29ec1b6fabea7117d7b8ad",
                "take": {"Nordzy": "Nordzy"}},
               {"url": GH + "alvatip/Nordzy-icon/releases/download/1.8.7/Nordzy-dark.tar.gz",
                "sha256": "ad752b5ce70577408431734fc8004f928a00027a8fce6dd131ae2d0c3dc82069",
                "take": {"Nordzy-dark": "Nordzy-dark"}}]},
]
if os.environ.get("SLATE_THEME_PACKS"):
    with open(os.environ["SLATE_THEME_PACKS"], encoding="utf-8") as fh:
        PACKS = json.load(fh)


def themes_of(pack):
    return [d for f in pack["files"] for d in f["take"].values()]


def installed(pack):
    """Every one of its themes is here (yours, or the system's)."""
    places = [ICONS, os.path.join(HOME, ".icons")] + [
        os.path.join(d, "icons") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    return all(any(os.path.isdir(os.path.join(p, t)) for p in places) for t in themes_of(pack))


def fetch(url, dest):
    """Download url to dest (at most MAX_BYTES), returning its SHA-256."""
    if not (url.startswith("https://") or url.startswith("file://")):
        raise RuntimeError("only https downloads are used")
    h, got = hashlib.sha256(), 0
    req = urllib.request.Request(url, headers={"User-Agent": "Slate theme packs"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as out:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            got += len(chunk)
            if got > MAX_BYTES:
                raise RuntimeError("the download was much bigger than expected")
            h.update(chunk)
            out.write(chunk)
    return h.hexdigest()


def inside(base, path):
    base = os.path.realpath(base)
    return os.path.commonpath([base, os.path.realpath(path)]) == base


def members(archive):
    """What's in a .tar.* or .zip, as (name, kind, link, read) with kind "dir", "file",
    "link" or "other" (read() gives a file's bytes). A zip's links are files with the link
    mode, holding where they point."""
    if zipfile.is_zipfile(archive):
        z = zipfile.ZipFile(archive)
        for i in z.infolist():
            mode = (i.external_attr >> 16) & 0o170000
            name = i.filename.rstrip("/")
            if i.is_dir():
                yield name, "dir", "", None
            elif mode == 0o120000:
                yield name, "link", z.read(i).decode("utf-8", "replace"), None
            elif mode in (0, 0o100000):
                yield name, "file", "", (lambda i=i: z.read(i))
            else:
                yield name, "other", "", None
        return
    with tarfile.open(archive) as t:
        for m in t.getmembers():
            kind = "dir" if m.isdir() else "link" if m.issym() else "file" if m.isfile() else "other"
            yield m.name, kind, m.linkname, ((lambda m=m: t.extractfile(m).read()) if kind == "file" else None)


def unpack(archive, take, into, family):
    """The folders named in take (archive path → theme name), unpacked into `into`, each as
    its theme name. Only plain files, folders, and links that stay inside the pack's own
    themes (family: their names)."""
    homes = [os.path.join(into, th) for th in family]
    for name, kind, linkname, read in members(archive):
        for src, theme in take.items():
            prefix = src.rstrip("/") + "/"
            if name == src.rstrip("/"):
                rel = ""
            elif name.startswith(prefix):
                rel = name[len(prefix):]
            else:
                continue
            root = os.path.join(into, theme)
            target = os.path.normpath(os.path.join(root, rel))
            if os.path.isabs(rel) or ".." in rel.split("/") or not inside(root, target):
                raise RuntimeError("the download has a file that would land outside its theme")
            if kind == "dir":
                os.makedirs(target, exist_ok=True)
            elif kind == "link":
                link = linkname
                to = os.path.join(os.path.dirname(target), link)
                if os.path.isabs(link) or not any(inside(h, to) for h in homes):
                    raise RuntimeError("the download has a link pointing outside its themes")
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if os.path.lexists(target):
                    os.remove(target)
                os.symlink(link, target)
            elif kind == "file":
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if os.path.islink(target):          # (never written through a link)
                    os.remove(target)
                with open(target, "wb") as out:
                    out.write(read())
                os.chmod(target, 0o644)
            # (hard links, devices and the rest: not part of a theme, left out)
            break


def install(pack):
    os.makedirs(ICONS, exist_ok=True)
    work = tempfile.mkdtemp(prefix=".slate-installing-", dir=ICONS)
    try:
        for i, f in enumerate(pack["files"]):
            path = os.path.join(work, "download-%d" % i)
            digest = fetch(f["url"], path)
            if digest != f["sha256"]:
                raise RuntimeError("the download wasn't the one Slate expected (its fingerprint didn't match), so it wasn't used")
            unpack(path, f["take"], work, themes_of(pack))
            os.remove(path)
        for theme in themes_of(pack):
            src = os.path.join(work, theme)
            if not os.path.isfile(os.path.join(src, "index.theme")) and not os.path.isdir(os.path.join(src, "cursors")):
                raise RuntimeError("the download didn't have %s in it" % theme)
        # All there: each theme in its place, replacing an older copy
        for theme in themes_of(pack):
            dest = os.path.join(ICONS, theme)
            if os.path.islink(dest) or os.path.isfile(dest):
                os.remove(dest)
            elif os.path.isdir(dest):
                shutil.rmtree(dest)
            os.replace(os.path.join(work, theme), dest)
            if pack["kind"] == "icons" and shutil.which("gtk-update-icon-cache"):
                subprocess.run(["gtk-update-icon-cache", "-q", "-f", dest], capture_output=True, timeout=60)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    args = sys.argv[1:]
    if args == ["--list"]:
        print(json.dumps([{"id": p["id"], "kind": p["kind"], "name": p["name"], "about": p["about"],
                           "themes": themes_of(p), "installed": installed(p)} for p in PACKS]))
        return 0
    if len(args) == 2 and args[0] == "--install":
        pack = next((p for p in PACKS if p["id"] == args[1]), None)
        if not pack:
            print("theme-packs: no pack called %s" % args[1], file=sys.stderr)
            return 2
        try:
            install(pack)
        except (OSError, RuntimeError, tarfile.TarError, zipfile.BadZipFile) as e:
            print("theme-packs: %s" % e, file=sys.stderr)
            return 1
        print("installed %s" % pack["id"])
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
