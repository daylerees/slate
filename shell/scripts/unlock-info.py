#!/usr/bin/env python3
"""What Settings → Face, Fingerprint & Keys shows, as you, with no password: whether Howdy (face
unlock) is installed, the cameras here and which are infrared, and which ways in the lock screen
takes now (Slate's own PAM service, /etc/pam.d/slate-lock, which anyone can read).

  unlock-info.py            all of it, as JSON:
      {"howdy": bool, "cameras": [{"path", "name", "ir"}], "methods": ["face", …]}

A camera is asked which picture formats it gives (V4L2's VIDIOC_ENUM_FMT, as v4l2-ctl
--list-formats does), which doesn't turn it on. Infrared ones give only greyscale: Howdy is
much safer with one (a photo or a screen can't fool infrared), so the page says which.
SLATE_UNLOCK_TEST points it at a scratch /dev, /sys and /etc (the tests).
"""
import fcntl
import glob
import json
import os
import struct
import sys

ROOT = os.environ.get("SLATE_UNLOCK_TEST", "")
SECURITY = ["/usr/lib/security", "/usr/lib64/security", "/lib/security", "/lib64/security",
            "/usr/lib/x86_64-linux-gnu/security", "/lib/x86_64-linux-gnu/security", "/usr/lib/aarch64-linux-gnu/security"]
HOWDY = ["/usr/bin/howdy", "/usr/local/bin/howdy"]

VIDIOC_ENUM_FMT = 0xC0405602            # _IOWR('V', 2, struct v4l2_fmtdesc), 64 bytes
CAPTURE = 1                             # V4L2_BUF_TYPE_VIDEO_CAPTURE
# Greyscale formats (fourcc): what an infrared camera gives
GREY = {b"GREY", b"Y10 ", b"Y12 ", b"Y16 ", b"Y8I ", b"Y10B", b"Y12I", b"Y16I"}


def at(path):
    return ROOT + path


def formats(device):
    """The fourcc codes a video device captures in ([] for none, or when it can't be asked)."""
    out = []
    try:
        fd = os.open(device, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return out
    try:
        for i in range(64):
            buf = bytearray(struct.pack("II", i, CAPTURE) + bytes(56))
            try:
                fcntl.ioctl(fd, VIDIOC_ENUM_FMT, buf)
            except OSError:
                break
            out.append(bytes(buf[44:48]))
    finally:
        os.close(fd)
    return out


def is_ir(fourccs):
    """Infrared: it captures, and only in greyscale."""
    return bool(fourccs) and all(f in GREY for f in fourccs)


def cameras(read_formats=formats):
    """Each video device that captures: its stable path (by-id where there is one), name, and
    whether it's infrared. Metadata nodes (no capture formats) are left out."""
    stable = {}
    for link in sorted(glob.glob(at("/dev/v4l/by-id/*"))) + sorted(glob.glob(at("/dev/v4l/by-path/*"))):
        target = os.path.realpath(link)
        stable.setdefault(target, link[len(ROOT):])
    out = []
    for dev in sorted(glob.glob(at("/dev/video*")), key=lambda d: int("0" + "".join(c for c in os.path.basename(d) if c.isdigit()))):
        fourccs = read_formats(dev)
        if not fourccs:
            continue
        try:
            with open(at("/sys/class/video4linux/%s/name" % os.path.basename(dev))) as f:
                name = f.read().strip()
        except OSError:
            name = os.path.basename(dev)
        out.append({"path": stable.get(os.path.realpath(dev), dev[len(ROOT):]), "name": name, "ir": is_ir(fourccs)})
    return out


def howdy():
    """Howdy Next (pam_howdy.so) or Howdy 2 (its pam_python script), with its command."""
    pam = any(os.path.isfile(at(d + "/pam_howdy.so")) or os.path.isfile(at(d + "/howdy/pam.py")) for d in SECURITY)
    return pam and any(os.path.isfile(at(h)) for h in HOWDY)


def methods():
    """The ways in Slate's lock screen takes now, as slate-unlock wrote them."""
    try:
        with open(at("/etc/pam.d/slate-lock")) as f:
            return [l[len("# slate-unlock: "):].strip() for l in f if l.startswith("# slate-unlock: ")]
    except OSError:
        return []


def main():
    print(json.dumps({"howdy": howdy(), "cameras": cameras(), "methods": methods()}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
