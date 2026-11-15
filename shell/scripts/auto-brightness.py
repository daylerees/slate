#!/usr/bin/env python3
"""Automatic brightness (Settings → Displays): the screen, and the keyboard's backlight where
there is one, follow the light in the room, as the laptop's light sensor measures it.

The light level comes from iio-sensor-proxy over D-Bus (net.hadess.SensorProxy on the system
bus): its LightLevel property, sent as it changes, while this holds a claim on the sensor
(ClaimLight). Nothing is polled. The claim is given back (ReleaseLight) when this stops: Slate
stops it when the switch goes off, and iio-sensor-proxy also lets go when it goes away.

Brightness is set with brightnessctl, as the brightness keys do (OSD.qml): changes ease over
a second and a half, and only once the light has really changed (by about half again, held
for two seconds: a passing shadow or a flicker isn't followed).

It learns: a change you make (the keys, Nova, anything else) becomes what you want at that
light level. The curve has a few points along the light (dark, dim, indoors, bright, daylight),
each with an offset from Slate's own curve; a change moves the two points either side of that
light by the same amount, so the curve passes through your choice, and keeps it rising
(brighter rooms never get a darker screen; the keyboard's light, the other way).
After a change it waits a minute before following the light again. The offsets are kept in
$XDG_STATE_HOME/slate/auto-brightness.json, readable by you alone.

    auto-brightness.py           follow the light until stopped (stdin closing, or SIGTERM)
    auto-brightness.py --check   print what this computer has, once, and stop

Prints one line of JSON at a time for Slate: {"sensor": true, "hardware": true, "backlight":
true, "keyboard": false} first, then {"lux": 120.0, "screen": 52, "keyboard": null,
"paused": false} as it follows. Slate tells it about your own changes on stdin, one per line:
"manual screen 40" or "manual keyboard 50" (percentages)."""
import json
import glob
import math
import os
import signal
import subprocess
import sys
import time

NAME = "net.hadess.SensorProxy"
PATH = "/net/hadess/SensorProxy"
IFACE = "net.hadess.SensorProxy"

# Where the light is, as a position from 0 (dark) to TOP: log10(1 + lux). The curve's points
# sit at 0, 1, 2, 3, 4: about 0, 10, 100, 1,000 and 10,000 lux (a dark room, a dim one, indoors,
# a bright office, daylight)
TOP = 4.0
SCREEN_BASE = [15, 30, 50, 80, 100]       # % at each point, before what's been learned
KEYBOARD_BASE = [60, 30, 0, 0, 0]          # the keyboard's light: on in the dark, off in daylight
HYSTERESIS = 0.18      # how far the light has to move (in position) before it's followed: about ×1.5
SETTLE = 2.0           # seconds the new light has to last
PAUSE = 60.0           # after a change of yours, seconds before following the light again
if os.environ.get("SLATE_TEST") == "1" and os.environ.get("SLATE_AUTO_BRIGHTNESS_PAUSE"):
    PAUSE = float(os.environ["SLATE_AUTO_BRIGHTNESS_PAUSE"])     # (the tests don't wait a minute)
EASE = 1.5             # seconds a change takes
STEPS = 15             # ...in this many steps at most
SCREEN_MIN = 1         # never fully black (as the keys: brightnessctl -n1)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def position(level, unit="lux"):
    """A light reading as a position on the curve. "vendor" units (some sensors report a
    percentage of their range rather than lux) are spread over the same scale."""
    level = max(0.0, float(level))
    if unit == "vendor":
        return clamp(level / 100.0 * TOP, 0.0, TOP)
    return clamp(math.log10(1.0 + level), 0.0, TOP)


class Curve:
    """Brightness for a light position: base[i] + offsets[i] at point i, straight lines between.
    rising: brighter rooms get more (the screen) or less (the keyboard), never the other way."""

    def __init__(self, base, rising=True, offsets=None):
        self.base = list(base)
        self.rising = rising
        self.offsets = [0.0] * len(base)
        if offsets and len(offsets) == len(base):
            self.offsets = [float(o) for o in offsets]
        self._tidy()

    def points(self):
        return [clamp(b + o, 0, 100) for b, o in zip(self.base, self.offsets)]

    def _between(self, x):
        n = len(self.base)
        x = clamp(x, 0.0, n - 1.0)
        i = min(int(x), n - 2)
        return i, x - i

    def value(self, x):
        p = self.points()
        i, t = self._between(x)
        return p[i] * (1 - t) + p[i + 1] * t

    def learn(self, x, want):
        """Move the points either side of x by the same amount, so the curve gives want there
        (just the one point when x is on it), then keep it going the one way."""
        want = clamp(float(want), 0, 100)
        i, t = self._between(x)
        d = want - self.value(x)
        if t < 1:
            self.offsets[i] += d
        if t > 0:
            self.offsets[i + 1] += d
        # The points that moved set the rest: above them nothing lower (the screen), below
        # nothing higher, and the other way round for the keyboard. (Two that crossed each other
        # meet at what you chose: a flat stretch through it)
        p = [clamp(b + o, 0, 100) for b, o in zip(self.base, self.offsets)]
        lo, hi = (i, i) if t <= 0 else (i + 1, i + 1) if t >= 1 else (i, i + 1)
        if hi > lo and (p[lo] > p[hi] if self.rising else p[lo] < p[hi]):
            p[lo] = p[hi] = want
        for j in range(hi + 1, len(p)):
            p[j] = max(p[j], p[j - 1]) if self.rising else min(p[j], p[j - 1])
        for j in range(lo - 1, -1, -1):
            p[j] = min(p[j], p[j + 1]) if self.rising else max(p[j], p[j + 1])
        self.offsets = [pj - b for pj, b in zip(p, self.base)]

    def _tidy(self):
        """Saved offsets that would take a point past 0–100 are trimmed to it."""
        self.offsets = [clamp(b + o, 0, 100) - b for b, o in zip(self.base, self.offsets)]


class Follower:
    """When to change the brightness, and to what. Every method takes the time (seconds, any
    steady clock), so it can be tried without waiting."""

    def __init__(self, screen, keyboard=None):
        self.screen = screen            # a Curve
        self.keyboard = keyboard        # a Curve, or None (no keyboard backlight)
        self.acted = None               # the light position last followed
        self.latest = None
        self.pending = []               # readings since a change of light was first seen
        self.since = None               # ...when that was
        self.paused_until = 0.0

    def paused(self, now):
        return now < self.paused_until

    def reading(self, x, now):
        """A new light reading. True when a change of light has just begun (decide() is due
        SETTLE seconds later); the very first reading is followed at once (decide() now)."""
        self.latest = x
        if self.since is not None:
            self.pending.append(x)
            return False
        if self.acted is not None and abs(x - self.acted) < HYSTERESIS:
            return False
        self.pending = [x]
        self.since = now
        return True

    def due(self, now):
        return self.since is not None and (self.acted is None or now - self.since >= SETTLE)

    def decide(self, now):
        """After the light has settled: the targets ({"screen": %, "keyboard": % or None}), or
        None when there's nothing to do (it went back, or a change of yours is still fresh)."""
        if self.since is None:
            return None
        readings, self.pending, self.since = self.pending, [], None
        if self.paused(now):
            return None
        # (the middle reading of those while it settled: a passing shadow or flicker among them
        # doesn't pull it)
        x = sorted(readings)[len(readings) // 2]
        if self.acted is not None and abs(x - self.acted) < HYSTERESIS:
            return None
        self.acted = x
        return self.targets(x)

    def targets(self, x):
        return {"screen": int(round(clamp(self.screen.value(x), SCREEN_MIN, 100))),
                "keyboard": int(round(self.keyboard.value(x))) if self.keyboard else None}

    def manual(self, which, percent, now):
        """You set the screen (or the keyboard) to percent: that's the brightness for this light
        from now on, and the light isn't followed for a while."""
        curve = self.screen if which == "screen" else self.keyboard
        if curve is None or self.latest is None:
            return False
        curve.learn(self.latest, percent)
        self.acted = self.latest
        self.pending, self.since = [], None
        self.paused_until = now + PAUSE
        return True


def ease(start, end, steps=STEPS):
    """The values a change goes through, eased in and out, each different from the last."""
    out = []
    for k in range(1, steps + 1):
        t = k / steps
        t = 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2
        v = int(round(start + (end - start) * t))
        if v != (out[-1] if out else start):
            out.append(v)
    return out


# ---- What's kept ----------------------------------------------------------------------------
def state_path():
    home = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(home, "slate", "auto-brightness.json")


def load():
    try:
        with open(state_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(follower):
    from slate_common import write_private_json
    data = {"screen": [round(o, 2) for o in follower.screen.offsets]}
    if follower.keyboard:
        data["keyboard"] = [round(o, 2) for o in follower.keyboard.offsets]
    try:
        write_private_json(state_path(), data)
    except OSError:
        pass


# ---- The backlights (brightnessctl) ----------------------------------------------------------
SCREEN_ARGS = ["-c", "backlight"]
KEYBOARD_ARGS = ["-d", "*kbd_backlight*"]


def run(args):
    try:
        return subprocess.run(["brightnessctl", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None


class Light:
    """One backlight: brightnessctl -m prints  device,class,current,percent%,max"""

    def __init__(self, args, lowest=0):
        self.args = args
        self.lowest = lowest
        self.max = 0
        self.set_to = None          # the raw value this last set (or heard about)
        self.read()

    def read(self):
        p = run(["-m", *self.args, "info"])
        try:
            parts = p.stdout.strip().splitlines()[-1].split(",")
            self.max = int(parts[4])
            return int(parts[2])
        except (AttributeError, ValueError, IndexError):
            self.max = 0
            return None

    def raw(self, percent):
        return clamp(int(round(percent / 100.0 * self.max)), self.lowest, self.max)

    def set(self, raw):
        self.set_to = raw
        run(["-q", *self.args, "set", str(raw)])


def keyboard_light():
    """The keyboard's backlight, when there is one brightnessctl can set."""
    p = run(["-m", *KEYBOARD_ARGS, "info"])
    if not p or p.returncode != 0 or "kbd_backlight" not in p.stdout:
        return None
    light = Light(KEYBOARD_ARGS)
    return light if light.max > 0 else None


# ---- The sensor ------------------------------------------------------------------------------
def sys_root():
    return os.environ.get("SLATE_SYS", "/sys")


def sensor_hardware():
    """Whether the kernel has a light sensor (whatever iio-sensor-proxy makes of it)."""
    base = os.path.join(sys_root(), "bus", "iio", "devices")
    return any(glob.glob(os.path.join(base, "*", pat)) for pat in ("in_illuminance*", "in_intensity_both*"))


def bus_type():
    from gi.repository import Gio
    # (the tests' Slate has no system bus: a stand-in sensor on the session bus)
    if os.environ.get("SLATE_TEST") == "1" and os.environ.get("SLATE_SENSOR_BUS") == "session":
        return Gio.BusType.SESSION
    return Gio.BusType.SYSTEM


def sensor_proxy():
    """iio-sensor-proxy's object, or None when it isn't there or has no light sensor."""
    try:
        from gi.repository import Gio, GLib
    except ImportError:
        return None
    try:
        conn = Gio.bus_get_sync(bus_type(), None)
        proxy = Gio.DBusProxy.new_sync(conn, Gio.DBusProxyFlags.NONE, None, NAME, PATH, IFACE, None)
    except GLib.Error:
        return None
    has = proxy.get_cached_property("HasAmbientLight")
    return proxy if has is not None and has.unpack() else None


def check():
    has_light = Light(SCREEN_ARGS).max > 0
    return {"sensor": sensor_proxy() is not None, "hardware": sensor_hardware(), "backlight": has_light,
            "keyboard": keyboard_light() is not None}


def say(obj):
    print(json.dumps(obj), flush=True)


def die_with_parent():
    """Stop with Slate, even if it's killed (Linux's PR_SET_PDEATHSIG)."""
    try:
        import ctypes
        ctypes.CDLL(None).prctl(1, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def follow():
    from gi.repository import GLib
    proxy = sensor_proxy()
    screen = Light(SCREEN_ARGS, SCREEN_MIN)
    kbd = keyboard_light()
    say({"sensor": proxy is not None, "hardware": sensor_hardware(), "backlight": screen.max > 0,
         "keyboard": kbd is not None})
    if proxy is None or screen.max <= 0:
        return 0
    saved = load()
    follower = Follower(Curve(SCREEN_BASE, True, saved.get("screen")),
                        Curve(KEYBOARD_BASE, False, saved.get("keyboard")) if kbd else None)
    loop = GLib.MainLoop()
    clock = time.monotonic
    easing = {"id": 0, "steps": []}
    settle = {"id": 0}
    resume = {"id": 0, "level": None}

    def unit():
        u = proxy.get_cached_property("LightLevelUnit")
        return u.unpack() if u is not None else "lux"

    def report(want=None):
        """What it's doing, for Slate: the light, what it's taking the screen and keyboard to
        (or, after a change of yours, what the curve gives now), and what it has learned."""
        lux = proxy.get_cached_property("LightLevel")
        if want is None and follower.latest is not None:
            want = follower.targets(follower.latest)
        want = want or {}
        say({"lux": round(lux.unpack(), 1) if lux is not None else None,
             "screen": want.get("screen"), "keyboard": want.get("keyboard"),
             "paused": follower.paused(clock()), "learned": [round(o, 1) for o in follower.screen.offsets]})

    def step():
        # (a change of yours made while this one was on its way stops it, before the next step
        # can undo yours: Slate's word about it comes a moment later)
        if not easing["steps"] or changed_elsewhere():
            easing["id"], easing["steps"] = 0, []
            return False
        screen.set(easing["steps"].pop(0))
        return True

    def changed_elsewhere():
        """Moved by something Slate didn't hear about (a key the laptop handles itself, another
        program) since this last set it: learned as a change of yours."""
        if screen.set_to is None:
            return False
        now = screen.read()
        if now is None or abs(now - screen.set_to) <= max(1, screen.max // 50):
            return False
        screen.set_to = now
        if follower.manual("screen", now * 100.0 / screen.max, clock()):
            save(follower)
        return True

    def resumed():
        """The pause after a change of yours is over: the light now, looked at again (the
        sensor only speaks when it changes)."""
        resume["id"] = 0
        if resume["level"] is not None:
            light(resume["level"])
        return False

    def act():
        settle["id"] = 0
        if follower.paused(clock()):
            follower.decide(clock())
            if resume["id"] == 0:
                wait = max(0.0, follower.paused_until - clock()) + 0.1
                resume["id"] = GLib.timeout_add(int(wait * 1000), resumed)
            return False
        if easing["id"] == 0 and changed_elsewhere():
            follower.decide(clock())
            report()
            return False
        want = follower.decide(clock())
        if want:
            start = screen.set_to if screen.set_to is not None else screen.read()
            if start is None:
                start = screen.raw(want["screen"])
            easing["steps"] = ease(start, screen.raw(want["screen"]))
            if easing["steps"] and easing["id"] == 0:
                easing["id"] = GLib.timeout_add(int(EASE * 1000 / STEPS), step)
            if kbd and want["keyboard"] is not None:
                level = kbd.raw(want["keyboard"])
                if level != kbd.set_to:
                    kbd.set(level)
            report(want)
        return False

    def light(level):
        now = clock()
        resume["level"] = level
        if follower.reading(position(level, unit()), now):
            if follower.due(now):
                act()
            elif settle["id"] == 0:
                settle["id"] = GLib.timeout_add(int(SETTLE * 1000), act)

    def on_props(_proxy, changed, _gone):
        level = changed.unpack().get("LightLevel")
        if level is not None:
            light(level)

    buf = {"text": b""}

    def on_input(_fd, _cond):
        try:
            chunk = os.read(sys.stdin.fileno(), 4096)
        except OSError:
            chunk = b""
        if not chunk:
            loop.quit()
            return False
        buf["text"] += chunk
        *lines, buf["text"] = buf["text"].split(b"\n")
        for line in lines:
            heard(line.decode("utf-8", "replace"))
        return True

    def heard(line):
        parts = line.split()
        if len(parts) == 3 and parts[0] == "manual" and parts[1] in ("screen", "keyboard"):
            try:
                pct = float(parts[2])
            except ValueError:
                return
            light_ = screen if parts[1] == "screen" else kbd
            if light_ is None:
                return
            if easing["id"]:                 # (yours wins over a change still on its way)
                GLib.source_remove(easing["id"])
                easing["id"], easing["steps"] = 0, []
            # (a step of that change can still land just after yours, before this is heard: then
            # yours is put back, so it's always yours that stays)
            light_.set_to = light_.raw(pct)
            now = light_.read()
            if now is not None and abs(now - light_.set_to) > max(1, light_.max // 50):
                light_.set(light_.set_to)
            if follower.manual(parts[1], pct, clock()):
                save(follower)
            report()

    proxy.connect("g-properties-changed", on_props)
    try:
        proxy.call_sync("ClaimLight", None, 0, 3000, None)
    except GLib.Error as e:
        print("auto-brightness: the light sensor couldn't be claimed: " + e.message, file=sys.stderr)
        return 1
    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_input)
    try:
        from gi.repository import GLibUnix
        signal_add = GLibUnix.signal_add
    except (ImportError, AttributeError):
        signal_add = GLib.unix_signal_add          # (an older GLib)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])
    first = proxy.get_cached_property("LightLevel")
    if first is not None:
        light(first.unpack())
    try:
        loop.run()
    finally:
        try:
            proxy.call_sync("ReleaseLight", None, 0, 2000, None)
        except GLib.Error:
            pass
    return 0


def main():
    if "--check" in sys.argv[1:]:
        say(check())
        return 0
    die_with_parent()
    return follow()


if __name__ == "__main__":
    sys.exit(main())
