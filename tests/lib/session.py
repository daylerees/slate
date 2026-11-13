"""A real Slate session for the live and visual tiers: Hyprland on a headless output, with
Slate (a copy of shell/, SLATE_TEST=1) in a scratch home. Only runs in the test container,
where tests/run passes in the vkms card it renders through (see docs/TESTING.md,
"The live and visual tiers need vkms"); it never touches the desktop you're running.

    s = Session.shared()          # started once per run, reused by every live/visual test
    s.ipc("settings", "page", "dock")
    s.wait(lambda st: st["settings"]["section"] == "dock")
    s.state()                     # the "test" IPC target's JSON
    s.screenshot(path)            # grim, of the TEST output
    s.new_log_errors()            # error lines Slate logged since the last call
"""
import atexit
import glob
import json
import os
import re
import shutil
import signal
import subprocess
import time
import unittest

import slate

WIDTH, HEIGHT = 1440, 900
OUTPUT = "TEST"
# The time Slate's clocks show (Config.clockDate, test mode only). Not libfaketime: Quickshell
# hangs at start with it preloaded
FAKE_TIME = "2026-01-05T09:41:00"

# Lines in Slate's log that only mean the container has no such service (no system bus,
# sound server, network or Bluetooth): not Slate's fault
ENVIRONMENT_NOISE = re.compile("|".join([
    r"Could not connect to DBus", r"pipewire", r"PulseAudio", r"Network will not work",
    r"polkit", r"portal", r"QSoundEffect", r"AccountsService", r"org\.freedesktop",
    r"No session for pid", r"UPower", r"bluetooth", r"Failed to create wl_display",
    r"MESA", r"libEGL", r"QDBus", r"textinput", r"Cannot open: file:///var/lib/AccountsService",
    r"Read of .* failed: File does not exist", r"xkb", r"brightnessctl", r"wpctl", r"nmcli",
    r"systemd", r"logind", r"upower",
    r"Failed to find render device",      # vkms has no render node: buffers go through shared memory
]), re.I)
# Warnings Slate is known to log today (reported, not yet fixed). Each one here is a bug to
# fix; take it off the list when it is, so it can't come back unnoticed
KNOWN_ISSUES = re.compile("|".join([
    # Not Slate's: after a wrong password Quickshell's greetd client cancels the attempt
    # itself and then calls greetd's normal reply to that "unexpected" (harmless)
    r"quickshell\.service\.greetd: Received unexpected greetd response .*success",
]))


def log_errors(text):
    """Error lines in a Quickshell log's text (environment noise and known issues left out)."""
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    return [l.strip() for l in text.splitlines()
            if LOG_ERROR.search(l) and not ENVIRONMENT_NOISE.search(l) and not KNOWN_ISSUES.search(l)]
# What counts as an error in the log
LOG_ERROR = re.compile(r"\bERROR\b|TypeError|ReferenceError|Binding loop|SyntaxError|is not a type|"
                       r"Failed to load configuration|Cannot assign|Unable to assign|is not defined")


def in_container():
    return bool(os.environ.get("SLATE_TEST_CARD"))


class SessionError(Exception):
    pass


class Session:
    _shared = None

    @classmethod
    def stop_shared(cls):
        """Stop the run's shared session, before starting one of a different kind: where a
        session gets the vkms card to itself (CI), a second one at the same time can't use it."""
        if cls._shared is not None:
            cls._shared.stop()
            cls._shared = None

    @classmethod
    def shared(cls):
        """The run's one session, started on first use. Skips the test outside the container."""
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container (tests/run, not --no-container)")
        if cls._shared is None:
            s = cls()
            atexit.register(s.stop)
            s.start()
            cls._shared = s
        elif not cls._shared.alive():
            raise SessionError("the Slate session died earlier in this run (see tests/out/live/)")
        return cls._shared

    def __init__(self, width=WIDTH, height=HEIGHT, settings=None):
        self.width, self.height = width, height
        self.h = slate.ScratchHome()
        # (each part of a parallel run keeps its own logs: tests/out/live/<part>/)
        self.out = os.path.join(slate.OUT, "live", os.environ.get("SLATE_TEST_PART", ""))
        os.makedirs(self.out, exist_ok=True)
        self.settings = settings
        self.procs = []
        self.log_offset = 0
        self.slate_dir = None
        self.env = None

    # ---- setting up ---------------------------------------------------------------------
    def _write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def _prepare(self):
        h = self.h
        self.slate_dir = h.install_slate()
        hypr = os.path.join(self.slate_dir, "hypr")
        # Slate and the apps it starts: software GL, test mode, and a fixed time on the clocks
        # Text smoothed in grey: Qt Quick smooths text in colour (subpixel) on an opaque window and
        # in grey on a see-through one, so the bar's text changed with whatever an earlier scene
        # had done to it, and screenshots depended on the order they were taken in
        envs = {"LIBGL_ALWAYS_SOFTWARE": "1", "SLATE_TEST": "1", "SLATE_TEST_TIME": FAKE_TIME, "TZ": "UTC",
                "QSG_DISTANCEFIELD_ANTIALIASING": "gray"}
        self._write(os.path.join(hypr, "env.lua"),
                    "".join(f'hl.env("{k}", "{v}")\n' for k, v in envs.items() if v))
        # One headless output, the size under test; the vkms screen itself is switched off
        # (Virtual-1 here, Virtual-2 on GitHub's runners: every number it might have)
        self._write(os.path.join(hypr, "monitors.lua"),
                    "".join(f'hl.monitor({{ output = "Virtual-{n}", disabled = true }})\n' for n in range(1, 9)) +
                    f'hl.monitor({{ output = "{OUTPUT}", mode = "{self.width}x{self.height}@60", position = "0x0", scale = 1 }})\n')
        self._write(os.path.join(hypr, "autostart.lua"),
                    'hl.on("hyprland.start", function () hl.exec_cmd("hyprctl output create headless '
                    + OUTPUT + '") end)\n')
        # No animations or pointer, so a screenshot is the same every time
        self._write(os.path.join(hypr, "hyprland.lua"),
                    "hl.config({ animations = { enabled = false }, cursor = { invisible = true },\n"
                    "            misc = { disable_hyprland_logo = true, disable_watchdog_warning = true } })\n")
        # Fixture settings (welcome done, a fixed wallpaper and accent)
        settings = json.load(open(os.path.join(slate.FIXTURES, "live", "settings.json")))
        settings.update(self.settings or {})
        wallpaper = h("Pictures", "wallpaper.png")
        make_wallpaper(wallpaper, self.width, self.height)
        settings["wallpaper"] = wallpaper
        self._write(os.path.join(self.slate_dir, "settings.json"), json.dumps(settings, indent=2))
        # The dock's pinned apps, and the files it shows
        self._write(h(".local", "state", "slate", "dock.json"), json.dumps({"pinned": ["foot"]}))
        for d in ("Downloads", "Documents", "Videos/Screensaver", ".local/share/Trash/files", ".local/share/Trash/info"):
            os.makedirs(h(d), exist_ok=True)
        self._write(h(".config", "user-dirs.dirs"), 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_PICTURES_DIR="$HOME/Pictures"\n')

        self.env = dict(h.env)
        self.env.pop("DBUS_SESSION_BUS_ADDRESS", None)    # dbus-run-session makes one
        self.env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)
        self.env.update({
            "LIBSEAT_BACKEND": "noop", "AQ_DRM_DEVICES": os.environ["SLATE_TEST_CARD"],
            "HYPRLAND_NO_CRASHREPORTER": "1", "XDG_SESSION_TYPE": "wayland",
            "SLATE_TEST": "1",
            # A stand-in for bin/slate-build-hyprbars (tests/live/test_hyprbars.py says what it
            # reports): nothing is ever built, and nothing looks at the real plugin folder
            "SLATE_HYPRBARS_TOOL": os.path.join(slate.FIXTURES, "live", "hyprbars-tool"),
        })

    def start(self):
        self._prepare()
        conf = os.path.join(self.slate_dir, "session", "hypr", "hyprland.lua")
        self.hypr_log = open(os.path.join(self.out, "hyprland.log"), "w")
        p = subprocess.Popen(["dbus-run-session", "--", "start-hyprland", "--", "-c", conf], env=self.env,
                             stdout=self.hypr_log, stderr=subprocess.STDOUT, start_new_session=True)
        self.procs.append(p)
        # Hyprland's socket, then everything else talks to it
        sig = self._until(lambda: (glob.glob(os.path.join(self.h.runtime, "hypr", "*", ".socket.sock")) or [None])[0],
                          30, "Hyprland didn't start (tests/out/live/hyprland.log)")
        self.env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(os.path.dirname(sig))
        self.env["WAYLAND_DISPLAY"] = self._until(
            lambda: next((os.path.basename(x) for x in sorted(glob.glob(os.path.join(self.h.runtime, "wayland-*")))
                          if not x.endswith(".lock")), None), 15, "no Wayland socket")
        self._until(lambda: any(m["name"] == OUTPUT for m in self.monitors()), 20, f"no {OUTPUT} output")
        self.only_test_output()
        self._until(lambda: os.path.exists(os.path.join(self.h.runtime, "slate-ready")), 90,
                    "Slate didn't load (tests/out/live/slate.log)", on_fail=self.save_logs)
        self.settle(1.5)
        self.dbus = self._session_bus()
        self.startup_errors = self.new_log_errors()

    def only_test_output(self):
        """Switch off every output but the test one (on CI the vkms screen comes up too)."""
        for m in self.monitors():
            if m["name"] != OUTPUT:
                self.hyprctl("eval", f'hl.monitor({{ output = "{m["name"]}", disabled = true }})')

    def _session_bus(self):
        """The session bus address dbus-run-session gave Hyprland (for gdbus/notify-send)."""
        pid = self.procs[0].pid
        for child in subprocess.run(["pgrep", "-P", str(pid)], capture_output=True, text=True).stdout.split():
            try:
                env = open(f"/proc/{child}/environ", "rb").read().split(b"\0")
            except OSError:
                continue
            for e in env:
                if e.startswith(b"DBUS_SESSION_BUS_ADDRESS="):
                    addr = e.split(b"=", 1)[1].decode()
                    self.env["DBUS_SESSION_BUS_ADDRESS"] = addr
                    return addr
        return None

    # ---- talking to it ------------------------------------------------------------------
    def alive(self):
        return all(p.poll() is None for p in self.procs[:1]) and bool(self.slate_pid())

    def slate_pid(self):
        r = subprocess.run(["pgrep", "-f", f"qs .*-p {self.slate_dir}"], capture_output=True, text=True)
        return r.stdout.split()[0] if r.stdout.split() else None

    def run(self, cmd, timeout=20, check=False):
        code, out = slate.run(cmd, env=self.env, timeout=timeout)
        if check and code != 0:
            raise SessionError(f"{' '.join(cmd[:4])} exited {code}: {out.strip()[:200]}")
        return code, out

    def hyprctl(self, *args, json_out=False):
        code, out = self.run(["hyprctl"] + (["-j"] if json_out else []) + list(args))
        if json_out:
            try:
                return json.loads(out)
            except ValueError:
                raise SessionError(f"hyprctl {' '.join(args)}: {out.strip()[:200]}")
        return out

    def monitors(self):
        try:
            return self.hyprctl("monitors", "all", json_out=True)
        except SessionError:
            return []

    def ipc(self, target, function, *args, timeout=20):
        """slate ipc call <target> <function> [args]; returns its output (stripped)."""
        code, out = self.run(["qs", "-p", self.slate_dir, "ipc", "call", target, function] + [str(a) for a in args],
                             timeout=timeout)
        if code != 0:
            raise SessionError(f"ipc {target} {function} {' '.join(map(str, args))}: {out.strip()[:300]}")
        return out.strip()

    def state(self):
        out = self.ipc("test", "state")
        try:
            return json.loads(out)
        except ValueError:
            raise SessionError(f"test state wasn't JSON: {out[:200]}")

    def wait(self, check, timeout=8, what="the expected state"):
        """Poll state() until check(state) is true; returns the state, or fails the test."""
        end = time.monotonic() + timeout
        st = None
        while time.monotonic() < end:
            try:
                st = self.state()
                if check(st):
                    return st
            except (KeyError, IndexError, TypeError):
                pass
            time.sleep(0.15)
        raise AssertionError(f"timed out waiting for {what}; state was: {json.dumps(st)[:400]}")

    def settle(self, seconds=0.6):
        """Let a change draw (animations are off, but loaders and images take a frame or two)."""
        time.sleep(seconds)

    def reset(self):
        """Close everything that might be open, so each test starts from the plain desktop."""
        for target, fn in (("settings", "close"), ("launcher", "close"), ("picker", "close"), ("switcher", "cancel"),
                           ("overview", "close"), ("popout", "close"), ("power", "cancel"), ("polkit", "close"),
                           ("screensaver", "stop"), ("lock", "closePreview"), ("assistant", "stop"), ("assistant", "clear"), ("assistant", "close"), ("dock", "closeMenu"),
                           ("dock", "closePreview")):
            try:
                self.ipc(target, fn)
            except SessionError:
                pass

    def screenshot(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.run(["grim", "-o", OUTPUT, path], check=True)
        return path

    # ---- the log ------------------------------------------------------------------------
    def log_path(self):
        return os.path.join(self.h.cache, "slate.log")

    def new_log_errors(self):
        """Error lines Slate logged since the last call (environment noise left out)."""
        try:
            with open(self.log_path(), encoding="utf-8", errors="replace") as f:
                f.seek(self.log_offset)
                text = f.read()
                self.log_offset = f.tell()
        except FileNotFoundError:
            return []
        return log_errors(text)

    def save_logs(self):
        try:
            shutil.copy(self.log_path(), os.path.join(self.out, "slate.log"))
        except OSError:
            pass

    # ---- helpers ------------------------------------------------------------------------
    def _until(self, fn, timeout, msg, on_fail=None):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if self.procs and self.procs[0].poll() is not None:
                break
            v = fn()
            if v:
                return v
            time.sleep(0.2)
        if on_fail:
            on_fail()
        self.save_logs()
        raise SessionError(msg)

    def stop(self):
        self.save_logs()
        for p in self.procs:
            if p.poll() is None:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                    p.wait(10)
                except (OSError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(p.pid, signal.SIGKILL)
                    except OSError:
                        pass
        self.procs = []
        self.h.cleanup()


def make_wallpaper(path, w, h):
    """A fixed wallpaper: a soft diagonal gradient (the same pixels every run)."""
    from PIL import Image
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w + y / h) / 2
            px[x, y] = (int(28 + 40 * t), int(44 + 50 * t), int(72 + 70 * (1 - t)))
    img.save(path)
