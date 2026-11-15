#!/usr/bin/env python3
"""What Quick Look (QuickLook.qml) needs to show a file: what it is, and for some kinds what's
in it. One file at a time, started afresh for each and stopped when the preview closes.

    quicklook.py <file> <folder for PDF pages>

Prints lines of JSON as it goes:
    {"info": {name, path, size, dir, items, modified, mime, label, kind, width, height}}
                                                  first, at once (width × height: a picture's)
    {"text": "…", "cut": bool, "code": bool}      a text file: its first 200 KB
    {"page": "<png>", "n": 1}                     a PDF: each page as it's drawn (pdftoppm)
    {"pages": n, "more": bool}                    …and when that's done
    {"missing": "pdftoppm"}                       a PDF, without poppler's pdftoppm to draw it

kind is image, text, pdf, video, audio, folder or other. Nothing is written anywhere but the
folder for the pages (made 0700, emptied of earlier pages first): never /tmp."""
import json
import mimetypes
import os
import shutil
import subprocess
import sys

TEXT_LIMIT = 200 * 1024
PAGE_LIMIT = 20
PAGE_PIXELS = 1400          # the longest side of a drawn page

IMAGE = {"png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico", "heic", "jxl"}
VIDEO = {"mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "mpg", "mpeg", "wmv"}
AUDIO = {"mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "oga", "wma"}
CODE = {"sh", "bash", "zsh", "fish", "py", "js", "mjs", "ts", "tsx", "jsx", "json", "lua", "c", "cc", "cpp",
        "h", "hpp", "rs", "go", "java", "kt", "rb", "pl", "php", "qml", "html", "htm", "css", "scss", "xml",
        "yaml", "yml", "toml", "ini", "conf", "cfg", "desktop", "service", "nix", "sql", "diff", "patch",
        "log", "csv", "tsv", "cmake", "mk", "vue", "svelte", "swift", "zig", "hs", "el", "vim"}
PLAIN = {"txt", "md", "markdown", "rst", "text", "nfo", "readme"}
NAMES = {"makefile", "dockerfile", "readme", "license", "copying", "changelog", "authors", "todo"}


def say(obj):
    print(json.dumps(obj), flush=True)


def extension(name):
    return name.rsplit(".", 1)[-1].lower() if "." in name.strip(".") else ""


def looks_like_text(path):
    """No NUL bytes in its first 8 KB, and they read as UTF-8 (a character cut off at the end
    allowed)."""
    try:
        with open(path, "rb") as f:
            head = f.read(8192)
    except OSError:
        return False
    if b"\0" in head:
        return False
    try:
        head.decode("utf-8")
        return True
    except UnicodeDecodeError as e:
        return e.start >= len(head) - 3


def content_type(path, name):
    """Its type and a description in words ("PNG image"): GLib's, the file managers' own list,
    when it's there; Python's list of extensions otherwise."""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio
        with open(path, "rb") as f:
            head = f.read(4096)
        ctype, _ = Gio.content_type_guess(name, head)
        mime = Gio.content_type_get_mime_type(ctype) or ""
        return mime, Gio.content_type_get_description(ctype) or ""
    except Exception:
        mime = mimetypes.guess_type(name)[0] or ""
        return mime, ""


def kind_of(path, name, mime, is_dir):
    if is_dir:
        return "folder"
    ext = extension(name)
    if ext in IMAGE or mime.startswith("image/"):
        return "image"
    if ext == "pdf" or mime == "application/pdf":
        return "pdf"
    if ext in VIDEO or mime.startswith("video/"):
        return "video"
    if ext in AUDIO or mime.startswith("audio/"):
        return "audio"
    if ext in CODE or ext in PLAIN or name.lower() in NAMES or mime.startswith("text/") or looks_like_text(path):
        return "text"
    return "other"


def info(path):
    name = os.path.basename(path.rstrip("/")) or path
    st = os.stat(path)
    is_dir = os.path.isdir(path)
    items = None
    if is_dir:
        try:
            items = len(os.listdir(path))
        except OSError:
            items = None
        mime, label = "inode/directory", "Folder"
    else:
        mime, label = content_type(path, name)
    kind = kind_of(path, name, mime, is_dir)
    if not label:
        label = {"image": "Picture", "pdf": "PDF document", "video": "Video", "audio": "Audio",
                 "text": "Text", "folder": "Folder"}.get(kind, (extension(name).upper() + " file") if extension(name) else "File")
    width = height = 0
    if kind == "image":
        try:
            from PIL import Image          # (only its header is read)
            with Image.open(path) as im:
                width, height = im.size
        except Exception:
            pass
    return {"name": name, "path": path, "size": 0 if is_dir else st.st_size, "dir": is_dir, "items": items,
            "modified": int(st.st_mtime), "mime": mime, "label": label, "kind": kind, "width": width, "height": height}


def text(path, name, mime):
    with open(path, "rb") as f:
        raw = f.read(TEXT_LIMIT + 1)
    cut = len(raw) > TEXT_LIMIT
    body = raw[:TEXT_LIMIT].decode("utf-8", errors="replace")
    ext = extension(name)
    plain = ext in PLAIN or name.lower() in NAMES or (ext == "" and mime in ("", "text/plain"))
    say({"text": body, "cut": cut, "code": not plain})


def pages(path, folder):
    tool = shutil.which("pdftoppm")
    if not tool:
        say({"missing": "pdftoppm"})
        return
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    for old in os.listdir(folder):
        if old.endswith(".png"):
            try:
                os.remove(os.path.join(folder, old))
            except OSError:
                pass
    # Named for this run, so a page drawn for another file is never shown from Qt's cache.
    # (The file's path is absolute, so it can't be read as one of pdftoppm's options)
    stem = os.path.join(folder, "page-%d" % os.getpid())
    n = 0
    for n in range(1, PAGE_LIMIT + 1):
        out = "%s-%d" % (stem, n)
        try:
            r = subprocess.run([tool, "-png", "-singlefile", "-f", str(n), "-l", str(n),
                                "-scale-to", str(PAGE_PIXELS), path, out],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        except subprocess.TimeoutExpired:
            break
        if r.returncode != 0 or not os.path.exists(out + ".png"):
            n -= 1
            break
        say({"page": out + ".png", "n": n})
    else:
        say({"pages": n, "more": True})
        return
    say({"pages": n, "more": False})


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: quicklook.py <file> <folder for PDF pages>\n")
        return 2
    path, folder = os.path.abspath(argv[1]), argv[2]
    try:
        about = info(path)
    except OSError:
        say({"gone": True})
        return 1
    say({"info": about})
    try:
        if about["kind"] == "text":
            text(path, about["name"], about["mime"])
        elif about["kind"] == "pdf":
            pages(path, folder)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
