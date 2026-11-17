#!/usr/bin/env python3
"""Settings → Storage: what's using the disk.

    storage.py drives          each drive (a real filesystem that's mounted), how full: JSON
    storage.py kinds           what's using the space, by kind, and your biggest folders: JSON,
                               measured at low priority and kept (~/.cache/slate/storage.json)
    storage.py cached          the last `kinds` kept, at once ({} if there's none)
    storage.py clear-caches    thumbnails, and anything in ~/.cache not touched for 30 days

Drives come from /proc/self/mounts (SLATE_TEST_MOUNTS for the tests): disks, not the system's
own (proc, tmpfs, overlays, snaps), one line per filesystem however many places it's mounted.
"""
import json
import os
import shutil
import sys
import time

HOME = os.path.expanduser("~")
CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
KEPT = os.path.join(CACHE, "slate", "storage.json")
REAL = {"ext4", "ext3", "ext2", "btrfs", "xfs", "f2fs", "vfat", "exfat", "ntfs", "ntfs3", "fuseblk", "zfs", "bcachefs", "jfs", "reiserfs"}
OLD = 30 * 86400            # caches untouched this long are cleared


def drive_name(mount):
    if mount == "/":
        return "This computer"
    if mount == HOME or mount == "/home":
        return "Home"
    return os.path.basename(mount.rstrip("/")) or mount


def drives():
    out, seen = [], set()
    with open(os.environ.get("SLATE_TEST_MOUNTS") or "/proc/self/mounts") as f:
        lines = f.read().splitlines()
    for line in lines:
        parts = line.split()
        if len(parts) < 3:
            continue
        dev, mount, kind = parts[0], parts[1].replace("\\040", " "), parts[2]
        if kind not in REAL or mount.startswith(("/boot", "/efi", "/snap", "/var/lib/docker", "/var/lib/containers")):
            continue
        # (a folder: in a container a single file can be mounted, like docker-init)
        if not os.path.isdir(mount):
            continue
        try:
            st = os.statvfs(mount)
        except OSError:
            continue
        # (the same filesystem mounted in several places, btrfs subvolumes above all: once)
        key = (dev.split("[")[0], st.f_blocks, st.f_bsize)
        if key in seen:
            continue
        seen.add(key)
        size = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        if size <= 0:
            continue
        out.append({"mount": mount, "name": drive_name(mount), "size": size, "free": free,
                    "used": size - st.f_bfree * st.f_frsize, "removable": mount.startswith(("/run/media", "/media", "/mnt"))})
    out.sort(key=lambda d: (d["mount"] != "/", d["mount"] != "/home", d["removable"], d["mount"]))
    return out


def size_of(path, stop=None):
    """Bytes under a folder (not following links, not crossing into another filesystem)."""
    total = 0
    try:
        top = os.stat(path, follow_symlinks=False).st_dev
    except OSError:
        return 0
    stack = [path]
    while stack:
        p = stack.pop()
        try:
            with os.scandir(p) as it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if e.is_dir(follow_symlinks=False):
                        if st.st_dev == top and (stop is None or e.path not in stop):
                            stack.append(e.path)
                    else:
                        total += st.st_blocks * 512
        except OSError:
            continue
    return total


def xdg_dir(name, fallback):
    """A folder of yours by its XDG name (Pictures…), as user-dirs.dirs says, else ~/<fallback>."""
    conf = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "user-dirs.dirs")
    try:
        for line in open(conf):
            if line.startswith("XDG_%s_DIR=" % name):
                v = line.split("=", 1)[1].strip().strip('"').replace("$HOME", HOME)
                if v and v != HOME:
                    return v
    except OSError:
        pass
    return os.path.join(HOME, fallback)


def kinds():
    try:
        os.nice(19)
    except OSError:
        pass
    folders = {k: xdg_dir(k.upper(), k.capitalize()) for k in ("downloads", "pictures", "videos", "music", "documents")}
    trash = os.path.join(DATA, "Trash")
    apps_user = os.path.join(DATA, "flatpak")
    out = {k: size_of(p) for k, p in folders.items()}
    out["caches"] = size_of(CACHE)
    out["trash"] = size_of(trash)
    out["apps"] = size_of(apps_user) + size_of("/var/lib/flatpak") + (0 if os.environ.get("SLATE_TEST") else size_of("/usr"))
    counted = set(folders.values()) | {CACHE, trash, apps_user}
    home_total = size_of(HOME)
    out["other"] = max(0, home_total - sum(out[k] for k in folders) - out["caches"] - out["trash"] - size_of(apps_user))
    # Your biggest folders: each folder at the top of your home, and one level into the big ones
    big = []
    try:
        for e in os.scandir(HOME):
            if e.is_dir(follow_symlinks=False):
                big.append({"path": e.path, "name": e.name, "size": size_of(e.path)})
    except OSError:
        pass
    big.sort(key=lambda b: -b["size"])
    result = {"kinds": out, "biggest": [b for b in big if b["size"] > 0][:8], "home": home_total, "at": int(time.time())}
    try:
        os.makedirs(os.path.dirname(KEPT), exist_ok=True)
        tmp = KEPT + ".tmp"
        with open(tmp, "w") as f:
            json.dump(result, f)
        os.replace(tmp, KEPT)
    except OSError:
        pass
    return result


def cached():
    try:
        with open(KEPT) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def clear_caches():
    """Thumbnails (made again when they're needed), and files in ~/.cache untouched for 30 days.
    Nothing an app has used lately: what's in use stays. Slate's own measurements stay too."""
    freed = 0
    thumbs = os.path.join(CACHE, "thumbnails")
    freed += size_of(thumbs)
    shutil.rmtree(thumbs, ignore_errors=True)
    now = time.time()
    for root, dirs, files in os.walk(CACHE, topdown=False):
        for name in files:
            p = os.path.join(root, name)
            if p == KEPT:
                continue
            try:
                st = os.lstat(p)
                if now - max(st.st_mtime, st.st_atime) > OLD:
                    freed += st.st_blocks * 512
                    os.remove(p)
            except OSError:
                pass
        if root != CACHE:
            try:
                os.rmdir(root)          # (only once it's empty)
            except OSError:
                pass
    return {"freed": freed}


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    if what == "drives":
        print(json.dumps(drives()))
    elif what == "kinds":
        print(json.dumps(kinds()))
    elif what == "cached":
        print(json.dumps(cached()))
    elif what == "clear-caches":
        print(json.dumps(clear_caches()))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
