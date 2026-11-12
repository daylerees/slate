#!/usr/bin/env python3
"""Tell Slate when a camera starts and stops being used (OSD.qml shows it).

Prints a line of JSON whenever that changes:  {"on": true, "apps": ["Firefox"]}
("apps": what has a camera open, by name, where Slate can see it: your own apps; a camera
used through PipeWire shows as PipeWire's).

Nothing is polled: the kernel says when a camera device (/dev/video*) is opened or closed
(inotify), and only then are your processes looked at for which has one open. Devices that
come and go, or change permissions (Private Mode), are watched as they appear. Opens that
last less than a moment (the system checking what a camera can do) aren't counted.

    camera-watch.py            watch, until Slate stops
    camera-watch.py --once     print what's using a camera now, and stop
"""
import ctypes
import ctypes.util
import json
import os
import select
import struct
import sys

IN_OPEN = 0x20
IN_CLOSE_WRITE = 0x08
IN_CLOSE_NOWRITE = 0x10
IN_ATTRIB = 0x04
IN_CREATE = 0x100
IN_DELETE = 0x200
IN_IGNORED = 0x8000
SETTLE = 0.4            # seconds an open has to last to count
DEV = os.environ.get("SLATE_DEV", "/dev")
PROC = os.environ.get("SLATE_PROC", "/proc")


def is_camera(name):
    return name.startswith("video") and name[5:].isdigit()


def cameras():
    try:
        return sorted(os.path.join(DEV, n) for n in os.listdir(DEV) if is_camera(n))
    except OSError:
        return []


def app_name(pid):
    """A process's name as people know it: its command's own name, tidied."""
    try:
        exe = open(os.path.join(PROC, pid, "cmdline"), "rb").read().split(b"\0")[0].decode(errors="replace")
        name = os.path.basename(exe) or open(os.path.join(PROC, pid, "comm")).read().strip()
    except OSError:
        return ""
    for tail in ("-bin", "-wrapped", ".bin"):
        if name.endswith(tail):
            name = name[: -len(tail)]
    name = name.lstrip(".")
    known = {"pipewire": "PipeWire", "obs": "OBS Studio", "zoom": "Zoom", "chrome": "Chrome", "chromium": "Chromium",
             "firefox": "Firefox", "librewolf": "LibreWolf", "brave": "Brave", "vivaldi": "Vivaldi", "slack": "Slack",
             "discord": "Discord", "teams-for-linux": "Teams", "signal-desktop": "Signal", "cheese": "Cheese",
             "snapshot": "Camera", "guvcview": "guvcview", "qs": "Slate", "quickshell": "Slate"}
    return known.get(name.lower(), name[:1].upper() + name[1:])


def users():
    """The names of your processes that have a camera open, each once."""
    devs = set(cameras())
    if not devs:
        return []
    names = []
    try:
        pids = [p for p in os.listdir(PROC) if p.isdigit()]
    except OSError:
        return []
    for pid in pids:
        fd_dir = os.path.join(PROC, pid, "fd")
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue                    # (not yours, or gone)
        for fd in fds:
            try:
                if os.readlink(os.path.join(fd_dir, fd)) in devs:
                    n = app_name(pid)
                    if n and n not in names:
                        names.append(n)
                    break
            except OSError:
                continue
    return names


class Inotify:
    def __init__(self):
        libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        self.libc = libc
        self.fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1")
        self.watching = {}              # path → watch descriptor

    def add(self, path, mask):
        wd = self.libc.inotify_add_watch(self.fd, path.encode(), mask)
        if wd >= 0:
            self.watching[path] = wd
        return wd >= 0

    def events(self):
        out = []
        try:
            data = os.read(self.fd, 65536)
        except BlockingIOError:
            return out
        i = 0
        while i + 16 <= len(data):
            wd, mask, _cookie, length = struct.unpack_from("iIII", data, i)
            name = data[i + 16:i + 16 + length].rstrip(b"\0").decode(errors="replace")
            out.append((wd, mask, name))
            i += 16 + length
        return out


def say(on, apps):
    print(json.dumps({"on": on, "apps": apps}), flush=True)


def end_with_slate():
    """Stop when the Slate that started this stops. It's only told so when it next writes a line,
    and it only writes when a camera's opened or closed: without this, one left by a Slate that
    had stopped or restarted waited on for good (and held the test runner's output open)."""
    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)
        libc.prctl(1, 15, 0, 0, 0)          # PR_SET_PDEATHSIG: SIGTERM when the parent goes
    except (OSError, AttributeError):
        pass
    if os.getppid() == 1:                   # (it went before that was set)
        sys.exit(0)


def watch():
    end_with_slate()
    ino = Inotify()
    ino.add(DEV, IN_CREATE | IN_DELETE | IN_ATTRIB)

    def watch_cameras():
        # (a camera turned off by Private Mode can't be watched until it's back: tried again
        # whenever /dev says something about it)
        for path in cameras():
            if path not in ino.watching:
                ino.add(path, IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE | IN_ATTRIB)

    watch_cameras()
    apps = users()
    on = bool(apps)
    say(on, apps)
    pending = False
    while True:
        ready, _, _ = select.select([ino.fd], [], [], SETTLE if pending else None)
        if ready:
            for wd, mask, name in ino.events():
                if mask & IN_IGNORED:
                    for p, w in list(ino.watching.items()):
                        if w == wd:
                            del ino.watching[p]
                if name and not is_camera(name):
                    continue            # (something else in /dev)
                pending = True
            watch_cameras()
            continue
        # Quiet for a moment after something happened: look at what's open now
        pending = False
        now = users()
        if bool(now) != on or (now and now != apps):
            on, apps = bool(now), now
            say(on, apps)


if __name__ == "__main__":
    if "--once" in sys.argv:
        apps = users()
        say(bool(apps), apps)
        sys.exit(0)
    try:
        watch()
    except KeyboardInterrupt:
        pass
    except OSError as e:
        print("camera-watch: %s" % e, file=sys.stderr)
        sys.exit(1)
