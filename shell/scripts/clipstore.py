#!/usr/bin/env python3
"""Slate clipboard history.

Fed by wl-paste, which runs this once per clipboard change (Slate starts it):
    wl-paste --watch python3 clipstore.py store

Other commands (used by Picker.qml):
    clipstore.py copy <id>     put an entry back on the clipboard
    clipstore.py delete <id>   forget one entry
    clipstore.py clear         forget everything

History lives in ~/.local/state/slate/clipboard/: index.json (newest first) and
one file per image. Text and images are kept; a repeat moves to the top. Entries a
password manager marks as secret are never stored.
"""
import fcntl
import hashlib
import json
import os
import subprocess
import sys
import time

DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "slate", "clipboard")
INDEX = os.path.join(DIR, "index.json")
LOCK = os.path.join(DIR, ".lock")
MAX_ENTRIES = 100
MAX_TEXT = 256 * 1024           # longer text isn't kept
MAX_IMAGE = 20 * 1024 * 1024
IMAGE_TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp"]
SECRET_HINTS = ("x-kde-passwordmanagerhint", "password")


def load():
    try:
        with open(INDEX) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return []
    # (a damaged index that isn't the expected shape starts afresh rather than failing every time)
    e = d.get("entries", []) if isinstance(d, dict) else []
    return [x for x in e if isinstance(x, dict)] if isinstance(e, list) else []


def save(entries):
    tmp = INDEX + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"entries": entries}, f, ensure_ascii=False)
    os.replace(tmp, INDEX)      # Slate watches the file; never show it half-written


def drop_files(entries):
    for e in entries:
        if e.get("file"):
            try:
                os.remove(os.path.join(DIR, e["file"]))
            except OSError:
                pass


def paste(mime):
    r = subprocess.run(["wl-paste", "--no-newline", "--type", mime], capture_output=True, timeout=5)
    return r.stdout if r.returncode == 0 else None


def image_size(data):
    """Width and height for PNG/JPEG/GIF, else (0, 0)."""
    try:
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
        if data[:6] in (b"GIF87a", b"GIF89a"):
            return int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little")
        if data[:2] == b"\xff\xd8":
            i = 2
            while i < len(data) - 9:
                if data[i] != 0xFF:
                    break
                marker, length = data[i + 1], int.from_bytes(data[i + 2:i + 4], "big")
                if marker in (0xC0, 0xC1, 0xC2):
                    return int.from_bytes(data[i + 7:i + 9], "big"), int.from_bytes(data[i + 5:i + 7], "big")
                i += 2 + length
    except Exception:
        pass
    return 0, 0


def store():
    # wl-paste hands us the content on stdin; read it so it isn't left blocked
    try:
        sys.stdin.buffer.read()
    except Exception:
        pass
    state = os.environ.get("CLIPBOARD_STATE", "data")
    if state != "data":         # cleared, or marked sensitive by a password manager
        return
    r = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=5)
    types = [t.strip() for t in r.stdout.splitlines() if t.strip()]
    if not types or any(h in t.lower() for t in types for h in SECRET_HINTS):
        return

    entry = None
    image_mime = next((m for m in IMAGE_TYPES if m in types), None)
    text_mime = next((m for m in ("text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT") if m in types), None)
    if image_mime and not text_mime:
        data = paste(image_mime)
        if not data or len(data) > MAX_IMAGE:
            return
        digest = hashlib.sha1(data).hexdigest()[:16]
        ext = image_mime.split("/")[1]
        name = digest + "." + ext
        path = os.path.join(DIR, name)
        if not os.path.exists(path):
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
        w, h = image_size(data)
        entry = {"id": digest, "kind": "image", "file": name, "mime": image_mime, "w": w, "h": h, "bytes": len(data)}
    elif text_mime:
        data = paste(text_mime)
        if data is None or len(data) > MAX_TEXT:
            return
        text = data.decode("utf-8", "replace")
        if not text.strip():
            return
        entry = {"id": hashlib.sha1(data).hexdigest()[:16], "kind": "text", "text": text}
    if not entry:
        return
    entry["time"] = int(time.time())

    entries = load()
    entries = [e for e in entries if e.get("id") != entry["id"]]
    entries.insert(0, entry)
    drop_files([e for e in entries[MAX_ENTRIES:] if e.get("file") and e["file"] != entry.get("file")])
    save(entries[:MAX_ENTRIES])


def copy(eid):
    e = next((e for e in load() if e.get("id") == eid), None)
    if not e:
        return 1
    if e.get("kind") == "image":
        try:
            f = open(os.path.join(DIR, e["file"]), "rb")
        except (OSError, KeyError):
            return 1                 # its picture has gone
        with f:
            subprocess.run(["wl-copy", "--type", e.get("mime", "image/png")], stdin=f, timeout=5)
    else:
        subprocess.run(["wl-copy", "--type", "text/plain;charset=utf-8"], input=e["text"].encode(), timeout=5)
    return 0


def delete(eid):
    entries = load()
    gone = [e for e in entries if e.get("id") == eid]
    drop_files(gone)
    save([e for e in entries if e.get("id") != eid])


def clear():
    drop_files(load())
    save([])


def main():
    os.makedirs(DIR, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)    # one change at a time
        if cmd == "store":
            store()
        elif cmd == "copy" and len(sys.argv) > 2:
            return copy(sys.argv[2])
        elif cmd == "delete" and len(sys.argv) > 2:
            delete(sys.argv[2])
        elif cmd == "clear":
            clear()
        else:
            print(__doc__)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
