#!/usr/bin/env python3
"""The colours Slate takes from each of several wallpapers, worked out ahead for the wallpaper
switcher so the theme follows each one at once as you move along.

    wallpaper-colours.py <image>…        (nearest the one you're on first)

Prints a line of JSON per image, {"path", "accent", "tone"}: first the ones already known (kept
in ~/.cache/slate/wallpaper-colours-all.json, with each file's size and time, so a changed
picture is worked out again), then each as it's worked out by wallpaper-accent.py, a few at a
time, in the order given. An image whose colours can't be found is left out; the switcher then
works them out as it always did."""
import json
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "slate" / "wallpaper-colours-all.json"
KEEP = 500                       # wallpapers remembered at most (the most recently seen)
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def stamp(path):
    st = os.stat(path)
    return [st.st_size, int(st.st_mtime)]


def load():
    try:
        data = json.loads(CACHE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(known):
    if len(known) > KEEP:
        known = dict(list(known.items())[-KEEP:])
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CACHE.parent, suffix=".json")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(known, fh)
        os.replace(tmp, CACHE)
    except BaseException:
        os.unlink(tmp)
        raise


def work_out(path):
    out = subprocess.run([sys.executable, str(HERE / "wallpaper-accent.py"), path], capture_output=True,
                         text=True, timeout=40).stdout.split()
    if len(out) >= 2 and HEX.match(out[0]) and HEX.match(out[1]):
        return out[0], out[1]
    return None


def say(path, accent, tone):
    print(json.dumps({"path": path, "accent": accent, "tone": tone}), flush=True)


def main(paths):
    known = load()
    todo = []
    for p in dict.fromkeys(paths):          # (each once, in order)
        try:
            s = stamp(p)
        except OSError:
            continue
        k = known.get(p)
        if isinstance(k, dict) and k.get("stamp") == s and HEX.match(str(k.get("accent"))) and HEX.match(str(k.get("tone"))):
            say(p, k["accent"], k["tone"])
            known[p] = known.pop(p)         # (seen just now: kept longest)
        else:
            todo.append((p, s))
    if not todo:
        save(known)
        return
    # A few at a time (each is mostly ImageMagick), still nearest first
    with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as pool:
        for (p, s), got in zip(todo, pool.map(lambda t: work_out(t[0]), todo)):
            if got:
                say(p, *got)
                known.pop(p, None)
                known[p] = {"stamp": s, "accent": got[0], "tone": got[1]}
    save(known)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except BrokenPipeError:                 # (the switcher closed: nothing more wanted)
        pass
