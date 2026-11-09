#!/usr/bin/env python3
"""Webcams for Settings → Webcam: what's plugged in, their picture settings, and who's using them.

Usage:
  webcam.py list                  the cameras and their controls, as JSON (see below)
  webcam.py set DEVICE NAME VALUE set one control (e.g. /dev/video0 brightness 10) and remember it
  webcam.py reset DEVICE          every control back to the camera's default (and forget them)
  webcam.py apply                 put the remembered settings back on every camera plugged in
                                  (cameras forget them when unplugged or restarted; Slate runs
                                  this at login)
  webcam.py users                 the apps using a camera right now, as JSON

Talks to the cameras with v4l2-ctl (v4l-utils). Settings are remembered per camera, by its
name and USB path, in $XDG_STATE_HOME/slate/webcam.json.

list prints [{"device": "/dev/video0", "name": "ASUS FHD webcam", "key": "…",
              "controls": [{"name": "brightness", "type": "int", "min": -64, "max": 64,
                            "step": 1, "default": 0, "value": 0, "inactive": false,
                            "options": [[0, "Disabled"], …] (menus only)}, …]}, …]
Only colour cameras that capture video are listed (not infrared ones, not metadata nodes).
"""
import json
import os
import re
import shutil
import subprocess
import sys

STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "slate", "webcam.json")
SYS = os.environ.get("SLATE_V4L_SYS", "/sys/class/video4linux")      # (tests point this at a fixture)
DEV = os.environ.get("SLATE_V4L_DEV", "/dev")
# Controls Settings shows, in the order it shows them (anything else a camera has is left alone)
SHOWN = ["brightness", "contrast", "saturation", "sharpness", "gain", "gamma",
         "white_balance_automatic", "white_balance_temperature",
         "auto_exposure", "exposure_time_absolute", "power_line_frequency", "backlight_compensation"]
GREY_ONLY = {"GREY", "Y10", "Y12", "Y16", "Y8I", "Y12I", "Z16"}      # infrared and depth sensors


def ctl(*args, timeout=10):
    try:
        p = subprocess.run(["v4l2-ctl", *args], capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, str(e)


def cameras():
    """[(device, name, key)] for every video capture node that's a colour camera."""
    out = []
    try:
        nodes = sorted(os.listdir(SYS), key=lambda n: int(re.sub(r"\D", "", n) or 0))
    except OSError:
        return out
    for node in nodes:
        base = os.path.join(SYS, node)
        name = read(os.path.join(base, "name")).strip()
        device = os.path.join(DEV, node)
        code, caps = ctl("-d", device, "--all")
        if code != 0 or "Video Capture" not in caps.split("Device Caps")[-1]:
            continue        # metadata nodes and the like
        code, fmts = ctl("-d", device, "--list-formats")
        found = set(re.findall(r"'(\w+)'", fmts))
        if not found or found <= GREY_ONLY:
            continue        # infrared (face login) and depth cameras
        # One key per physical camera: its name and where it's plugged in, stable across reboots
        path = os.path.realpath(os.path.join(base, "device"))
        out.append((device, name.split(":")[0].strip() or name, name + "@" + re.sub(r".*/usb\d+/", "", path)))
    return out


def read(p):
    try:
        with open(p) as f:
            return f.read()
    except OSError:
        return ""


def controls(device):
    """The camera's controls Settings shows, from v4l2-ctl --list-ctrls-menus."""
    code, text = ctl("-d", device, "--list-ctrls-menus")
    found, current = {}, None
    for line in text.splitlines():
        m = re.match(r"\s*(\w+) 0x[0-9a-f]+ \((\w+)\)\s*:(.*)$", line)
        if m:
            name, kind, rest = m.groups()
            current = None
            if name not in SHOWN or kind not in ("int", "bool", "menu"):
                continue
            c = {"name": name, "type": kind, "inactive": "inactive" in rest}
            for k in ("min", "max", "step", "default", "value"):
                v = re.search(r"\b%s=(-?\d+)" % k, rest)
                if v:
                    c[k] = int(v.group(1))
            if kind == "menu":
                c["options"] = []
            found[name] = current = c
            continue
        o = re.match(r"\s+(\d+): (.+)$", line)
        if o and current is not None and current["type"] == "menu":
            current["options"].append([int(o.group(1)), o.group(2).strip()])
    return [found[n] for n in SHOWN if n in found]


def load():
    try:
        with open(STATE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save(d):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
    os.replace(tmp, STATE)


def key_of(device):
    return next((k for d, n, k in cameras() if d == device), None)


def set_control(device, name, value):
    if name not in SHOWN:
        return "unknown control " + name
    code, out = ctl("-d", device, "--set-ctrl", "%s=%d" % (name, int(value)))
    if code != 0:
        return out.strip() or "couldn't set " + name
    key = key_of(device)
    if key:
        d = load()
        d.setdefault(key, {})[name] = int(value)
        save(d)
    return None


def apply_saved(device, saved):
    """Put remembered values back: the automatic switches first, so the manual values they
    unlock (temperature, exposure) can be set."""
    order = sorted(saved, key=lambda n: SHOWN.index(n) if n in SHOWN else 99)
    autos = [n for n in order if n in ("white_balance_automatic", "auto_exposure")]
    for name in autos + [n for n in order if n not in autos]:
        if name in SHOWN:
            ctl("-d", device, "--set-ctrl", "%s=%d" % (name, int(saved[name])))


def users():
    """Apps with a camera open: [{"pid", "name", "device"}], from /proc (your own processes)."""
    devs = {os.path.realpath(d): d for d, n, k in cameras()}
    found = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        fd_dir = "/proc/%s/fd" % pid
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target in devs:
                name = read("/proc/%s/comm" % pid).strip()
                found.append({"pid": int(pid), "name": name, "device": devs[target]})
                break
    return found


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if not shutil.which("v4l2-ctl"):
        print(json.dumps({"error": "v4l2-ctl isn't installed (v4l-utils)"}))
        return 3
    cmd = args[0]
    if cmd == "list":
        print(json.dumps([{"device": d, "name": n, "key": k, "controls": controls(d)} for d, n, k in cameras()]))
    elif cmd == "set" and len(args) == 4:
        err = set_control(args[1], args[2], args[3])
        if err:
            print(err)
            return 1
    elif cmd == "reset" and len(args) == 2:
        for c in controls(args[1]):
            if "default" in c:
                ctl("-d", args[1], "--set-ctrl", "%s=%d" % (c["name"], c["default"]))
        key = key_of(args[1])
        d = load()
        if key and key in d:
            del d[key]
            save(d)
    elif cmd == "apply":
        saved = load()
        for d, n, k in cameras():
            if saved.get(k):
                apply_saved(d, saved[k])
    elif cmd == "users":
        print(json.dumps(users()))
    else:
        sys.exit(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
