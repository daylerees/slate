#!/usr/bin/env python3
"""Each display's brightness, for Settings → Displays (DisplayBrightness.qml): which displays
Slate can set, and how bright each one is now. Prints one line of JSON per display as it's
known (the built-in screen first: it's quick), then a last line saying it's done:

    {"display": "eDP-1", "kind": "backlight", "percent": 52}
    {"display": "DP-1", "kind": "ddc", "bus": 4, "max": 100, "percent": 70}
    {"display": "HDMI-A-1", "kind": "none", "why": "silent"}
    {"done": true, "ddcutil": "ok"}

kind: "backlight" (the laptop's own screen, set with brightnessctl as the brightness keys do),
"ddc" (a monitor's own brightness control, VCP feature 0x10 over DDC/CI, through ddcutil) or
"none", with why: "missing" (ddcutil isn't installed), "access" (it is, but can't reach the
monitors: the i2c-dev module isn't loaded, or you're not allowed to use it) or "silent" (the
monitor doesn't answer: some don't have DDC/CI, or have it switched off in their own menu).

Which ddcutil display is which of Hyprland's outputs: ddcutil (2.0 and later) names the DRM
connector each I2C bus belongs to ("card1-DP-1"), which is Hyprland's output name with the
card in front; that's the match. Older ddcutil doesn't say, so then it's the EDID's model and
serial, which Hyprland reports too; a model alone only when there's one of it on each side.
The built-in screen is the one the backlight's device belongs to in /sys (intel_backlight's is
"card0-eDP-1"); where it doesn't say (AMD's and ACPI's belong to the graphics card), the
output that's a laptop panel: eDP, LVDS or DSI.

Nothing here changes anything: Slate sets what you choose itself (DisplayBrightness.qml)."""
import concurrent.futures
import glob
import json
import os
import re
import subprocess
import sys

# A laptop's own panel, by Hyprland's (the kernel's) connector name
BUILT_IN = re.compile(r"^(eDP|LVDS|DSI)-")
DETECT_TIMEOUT = 30         # ddcutil detect: a second or two, longer with many monitors
READ_TIMEOUT = 10           # one getvcp


def sys_root():
    return os.environ.get("SLATE_SYS", "/sys")


def dev_root():
    return os.environ.get("SLATE_DEV", "/dev")


def say(obj):
    print(json.dumps(obj), flush=True)


def run(args, timeout):
    """(exit status, output); 127 when the command isn't there at all."""
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except FileNotFoundError:
        return 127, ""
    except (OSError, subprocess.SubprocessError):
        return 1, ""


def connector(name):
    """A DRM connector as Hyprland names the output: "card1-DP-1" → "DP-1"."""
    return re.sub(r"^card\d+-", "", (name or "").strip())


# ---- The built-in screen (brightnessctl) -----------------------------------------------------
def backlight():
    """(device, percent) of the screen's backlight, as the brightness keys see it, or None."""
    code, out = run(["brightnessctl", "-m", "-c", "backlight", "info"], 5)
    if code != 0:
        return None
    try:
        parts = out.strip().splitlines()[-1].split(",")
        if int(parts[4]) <= 0:
            return None
        return parts[0], int(parts[3].rstrip("%"))
    except (ValueError, IndexError):
        return None


def built_in_output(device, monitors):
    """Which of Hyprland's outputs the backlight lights: the connector its /sys device is, or
    else the one laptop panel there is."""
    names = [m.get("name", "") for m in monitors]
    try:
        link = os.readlink(os.path.join(sys_root(), "class", "backlight", device, "device"))
        name = connector(os.path.basename(link))
        if name in names:
            return name
    except OSError:
        pass
    panels = [n for n in names if BUILT_IN.match(n)]
    return panels[0] if len(panels) == 1 else None


# ---- Monitors (ddcutil) ----------------------------------------------------------------------
def parse_detect(text):
    """`ddcutil detect --terse` → [{"valid": True, "bus": 4, "connector": "DP-1", "mfg": "DEL",
    "model": "DELL U2720Q", "serial": "ABC123"}, …]. "Display N" blocks answer DDC/CI; "Invalid
    display" ones don't; "Phantom display" ones are another way to the same monitor (a dock's),
    and are left out."""
    out, cur = [], None
    for line in text.splitlines():
        if not line.strip():
            continue
        if not line[0].isspace():
            head = line.strip().lower()
            if head.startswith("display "):
                cur = {"valid": True}
            elif head.startswith("invalid display"):
                cur = {"valid": False}
            else:
                cur = None          # (phantom displays, and anything ddcutil adds later)
            if cur is not None:
                out.append(cur)
            continue
        if cur is None:
            continue
        key, _, value = line.strip().partition(":")
        key, value = key.strip().lower(), value.strip()
        if key == "i2c bus":
            m = re.search(r"i2c-(\d+)", value)
            if m:
                cur["bus"] = int(m.group(1))
        elif key == "drm connector":
            cur["connector"] = connector(value)
        elif key == "monitor":
            # mfg:model:serial (the model may itself have a colon in it)
            mfg, _, rest = value.partition(":")
            model, _, serial = rest.rpartition(":")
            cur.update(mfg=mfg.strip(), model=model.strip(), serial=serial.strip())
    return [d for d in out if "bus" in d]


def same(a, b):
    return (a or "").strip().lower() == (b or "").strip().lower()


def match(found, monitors):
    """{output name: ddcutil display} for the outputs ddcutil found: by connector, else by EDID
    model and serial, else by a model there's only one of on each side."""
    names = {m.get("name") for m in monitors}
    out, used = {}, set()
    for i, d in enumerate(found):
        if d.get("connector") in names and d["connector"] not in out:
            out[d["connector"]] = d
            used.add(i)
    rest = [m for m in monitors if m.get("name") not in out]
    for i, d in enumerate(found):
        if i in used or not d.get("model"):
            continue
        if d.get("serial"):
            hits = [m for m in rest if same(m.get("model"), d["model"]) and same(m.get("serial"), d["serial"])]
        else:
            hits = [m for m in rest if same(m.get("model"), d["model"])]
            if sum(1 for e in found if same(e.get("model"), d["model"])) != 1:
                hits = []
        if len(hits) == 1:
            out[hits[0]["name"]] = d
            used.add(i)
            rest.remove(hits[0])
    return out


def parse_vcp(text):
    """`ddcutil getvcp 10 --brief` → (current, max), or None. It prints "VCP 10 C 70 100"."""
    m = re.search(r"^VCP\s+10\s+C\s+(\d+)\s+(\d+)\s*$", text, re.M | re.I)
    if not m or int(m.group(2)) <= 0:
        return None
    return int(m.group(1)), int(m.group(2))


def i2c_reachable():
    """Whether there are I2C devices this account can use (ddcutil needs read and write)."""
    devices = glob.glob(os.path.join(dev_root(), "i2c-*"))
    return any(os.access(d, os.R_OK | os.W_OK) for d in devices)


def read(bus):
    code, out = run(["ddcutil", "--bus", str(bus), "getvcp", "10", "--brief"], READ_TIMEOUT)
    return parse_vcp(out) if code == 0 else None


def monitors_now():
    code, out = run(["hyprctl", "monitors", "all", "-j"], 5)
    try:
        return [m for m in json.loads(out) if isinstance(m, dict) and m.get("name")] if code == 0 else []
    except ValueError:
        return []


def main():
    monitors = monitors_now()
    builtin = None
    light = backlight()
    if light:
        builtin = built_in_output(light[0], monitors)
        if builtin:
            say({"display": builtin, "kind": "backlight", "percent": light[1]})
    others = [m["name"] for m in monitors if m["name"] != builtin]

    code, text = run(["ddcutil", "detect", "--terse"], DETECT_TIMEOUT)
    if code == 127:
        status = "missing"
        found = []
    else:
        found = [d for d in parse_detect(text) if d["valid"]] if code == 0 else []
        status = "ok" if found or i2c_reachable() else "access"
    matched = match(found, [m for m in monitors if m["name"] in others])
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        values = dict(zip(matched, pool.map(lambda d: read(d["bus"]), matched.values())))
    for name in others:
        v = values.get(name)
        if v:
            say({"display": name, "kind": "ddc", "bus": matched[name]["bus"], "max": v[1],
                 "percent": max(0, min(100, round(v[0] * 100 / v[1])))})
        else:
            say({"display": name, "kind": "none", "why": "silent" if status == "ok" else status})
    say({"done": True, "ddcutil": status})


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.stderr.write(__doc__)
        sys.exit(2)
    main()
