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

    Session(second=(1280, 800))   # two screens: TEST, and TEST2 to its right. A kind of its own
                                  # (tests/live/test_two_screens.py), so the shared one stays as it is
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
# A two-screen session's second output: to the right of TEST, their top edges level
SECOND = "TEST2"
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
    r"(?!)",    # (none today: matches nothing)
]))


def log_errors(text):
    """Error lines in a Quickshell log's text (environment noise and known issues left out)."""
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    return [l.strip() for l in text.splitlines()
            if LOG_ERROR.search(l) and not ENVIRONMENT_NOISE.search(l) and not KNOWN_ISSUES.search(l)]
# What counts as an error in the log
# (and a crash: bin/slate's keeper starts Slate again and notes it, so a test that crashed
# Slate would otherwise pass once it's back)
LOG_ERROR = re.compile(r"\bERROR\b|TypeError|ReferenceError|Binding loop|SyntaxError|is not a type|"
                       r"Failed to load configuration|Cannot assign|Unable to assign|is not defined|"
                       r"Slate stopped unexpectedly")


def in_container():
    return bool(os.environ.get("SLATE_TEST_CARD"))


# What `qs ipc call` says, still exiting 0, when nothing answered the call
IPC_MISSED = {"Target not found.", "Function not found."}


class SessionError(Exception):
    pass


class NotReady(SessionError):
    """Slate is part way through loading (again): its IPC answers "Not ready to accept queries
    yet". wait() looks again; anything else asking for the state still fails."""


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
        elif cls._shared.died():
            raise SessionError("the Slate session died earlier in this run (see tests/out/live/)")
        return cls._shared

    def __init__(self, width=WIDTH, height=HEIGHT, settings=None, second=None):
        self.width, self.height = width, height
        # (width, height) of a second screen, to the right of the first; None: one screen
        self.second = second
        self.outputs = [OUTPUT] + ([SECOND] if second else [])
        self.h = slate.ScratchHome()
        # (each part of a parallel run keeps its own logs: tests/out/live/<part>/)
        self.out = os.path.join(slate.OUT, "live", os.environ.get("SLATE_TEST_PART", ""))
        os.makedirs(self.out, exist_ok=True)
        self.settings = settings
        self.procs = []
        self.log_offset = 0
        self.slate_dir = None
        self.slate_home = None
        self.env = None

    # ---- setting up ---------------------------------------------------------------------
    def _write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def _prepare(self):
        h = self.h
        # Slate's code in a folder of its own and your files in ~/.config/slate, as when it's
        # installed for everyone, so every live test runs with the two apart (the unit tests
        # cover an install of your own, with both in ~/.config/slate)
        self.slate_dir = h.install_slate(shared=True)
        self.slate_home = h.slate_home
        hypr = os.path.join(self.slate_home, "hypr")
        # Slate and the apps it starts: software GL, test mode, and a fixed time on the clocks
        # Text smoothed in grey: Qt Quick smooths text in colour (subpixel) on an opaque window and
        # in grey on a see-through one, so the bar's text changed with whatever an earlier scene
        # had done to it, and screenshots depended on the order they were taken in
        envs = {"LIBGL_ALWAYS_SOFTWARE": "1", "SLATE_TEST": "1", "SLATE_TEST_TIME": FAKE_TIME, "TZ": "UTC",
                "QSG_DISTANCEFIELD_ANTIALIASING": "gray",
                # A crash report's wait for systemd-coredump kept short: the host's catches a crash
                # in the container (the kernel runs it), so the container's own never has it
                "SLATE_CRASH_TRIES": "2"}
        self._write(os.path.join(hypr, "env.lua"),
                    "".join(f'hl.env("{k}", "{v}")\n' for k, v in envs.items() if v))
        # One headless output, the size under test (and a second to its right, when asked for);
        # the vkms screen itself is switched off (Virtual-1 here, Virtual-2 on GitHub's
        # runners: every number it might have)
        monitors = [(OUTPUT, self.width, self.height, "0x0")]
        if self.second:
            monitors.append((SECOND, self.second[0], self.second[1], f"{self.width}x0"))
        self._write(os.path.join(hypr, "monitors.lua"),
                    "".join(f'hl.monitor({{ output = "Virtual-{n}", disabled = true }})\n' for n in range(1, 9)) +
                    "".join(f'hl.monitor({{ output = "{name}", mode = "{w}x{h}@60", position = "{at}", scale = 1 }})\n'
                            for name, w, h, at in monitors))
        # (one after the other: made at once, either could come first, and the first is the one
        # Slate takes as the main display and Hyprland gives workspace 1)
        self._write(os.path.join(hypr, "autostart.lua"),
                    'hl.on("hyprland.start", function () hl.exec_cmd("'
                    + " && ".join(f"hyprctl output create headless {name}" for name in self.outputs)
                    + '") end)\n')
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
        self._write(os.path.join(self.slate_home, "settings.json"), json.dumps(settings, indent=2))
        # The dock's pinned apps, and the files it shows
        self._write(h(".local", "state", "slate", "dock.json"), json.dumps({"pinned": ["foot"]}))
        for d in ("Downloads", "Documents", "Videos/Screensaver", ".local/share/Trash/files", ".local/share/Trash/info"):
            os.makedirs(h(d), exist_ok=True)
        self._write(h(".config", "user-dirs.dirs"), 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\nXDG_PICTURES_DIR="$HOME/Pictures"\n')

        self.env = dict(h.env)
        # Where Slate's code is, as slate-session says it (the Hyprland config finding it by its
        # own path, should this not arrive, is static/test_configs.py's)
        self.env["SLATE_DIR"] = self.slate_dir
        self.env.pop("DBUS_SESSION_BUS_ADDRESS", None)    # dbus-run-session makes one
        self.env.pop("DBUS_SYSTEM_BUS_ADDRESS", None)
        self.env.update({
            "LIBSEAT_BACKEND": "noop", "AQ_DRM_DEVICES": os.environ["SLATE_TEST_CARD"],
            "HYPRLAND_NO_CRASHREPORTER": "1", "XDG_SESSION_TYPE": "wayland",
            "SLATE_TEST": "1",
            # A stand-in for bin/slate-build-hyprbars (tests/live/test_hyprbars.py says what it
            # reports): nothing is ever built, and nothing looks at the real plugin folder
            "SLATE_HYPRBARS_TOOL": os.path.join(slate.FIXTURES, "live", "hyprbars-tool"),
            # Stand-ins for pw-record and whisper-cli (talking to Nova, scripts/voice.py): no
            # microphone is ever opened, and what's "heard" is $HOME/.voice-transcript
            "SLATE_VOICE_TOOLS": os.path.join(slate.FIXTURES, "voice"),
            # Automatic brightness (scripts/auto-brightness.py): the light sensor looked for on the
            # session bus, where tests/lib/fake_sensor.py stands in for iio-sensor-proxy (none
            # there: no sensor), a pause after your own change of seconds rather than a minute,
            # and a stand-in brightnessctl that's a pretend laptop only once a test gives it
            # $HOME/.brightness.json (until then, no backlight, as before). Beside it a stand-in
            # ddcutil, not installed until a test gives it $HOME/.ddc.json; a pretend /sys in
            # $HOME/.sys (empty until a test says which output the backlight lights) and /dev
            # in $HOME/.dev (its I2C devices), as tests/live/test_display_brightness.py does
            "SLATE_SENSOR_BUS": "session",
            "SLATE_AUTO_BRIGHTNESS_PAUSE": "6",
            "SLATE_SYS": os.path.join(self.h.home, ".sys"),
            "SLATE_DEV": os.path.join(self.h.home, ".dev"),
            "PATH": os.path.join(slate.FIXTURES, "brightness") + ":" + self.env["PATH"],
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
        self._until(lambda: set(self.outputs) <= {m["name"] for m in self.monitors()}, 20,
                    f"no {' and '.join(self.outputs)} output")
        self.only_test_output()
        self._until(lambda: os.path.exists(os.path.join(self.h.runtime, "slate-ready")), 90,
                    "Slate didn't load (tests/out/live/slate.log)", on_fail=self.save_logs)
        self.settle(1.5)
        self.dbus = self._session_bus()
        self.startup_errors = self.new_log_errors()

    def only_test_output(self):
        """Switch off every output but the test ones (on CI the vkms screen comes up too)."""
        for m in self.monitors():
            if m["name"] not in self.outputs:
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

    def monitor(self, name=OUTPUT):
        """Hyprland's own record of one test output (reserved: the edges it keeps clear, as left,
        top, right, bottom in its pixels)."""
        return next((m for m in self.monitors() if m["name"] == name), {"reserved": [0, 0, 0, 0]})

    def ipc(self, target, function, *args, timeout=20):
        """slate ipc call <target> <function> [args]; returns its output (stripped)."""
        code, out = self.run(["qs", "-p", self.slate_dir, "ipc", "call", target, function] + [str(a) for a in args],
                             timeout=timeout)
        if code != 0:
            self.died()         # (if it's gone, keep its log and crash report before anything else runs)
            raise SessionError(f"ipc {target} {function} {' '.join(map(str, args))}: {out.strip()[:300]}")
        # (qs exits 0 when nothing answers: a call to a target that's switched off or a function
        # that isn't there was taken for done, and the test failed later, elsewhere, if at all)
        if out.strip() in IPC_MISSED:
            raise SessionError(f"ipc {target} {function} {' '.join(map(str, args))}: {out.strip()}")
        return out.strip()

    def state(self):
        out = self.ipc("test", "state")
        try:
            return json.loads(out)
        except ValueError:
            if out.startswith("Not ready to accept queries yet"):
                raise NotReady(out[:200])
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
            except NotReady:
                pass            # (Slate part way through loading again: a test that saves its files makes it)
            time.sleep(0.15)
        raise AssertionError(f"timed out waiting for {what}; state was: {json.dumps(st)[:400]}")

    def settle(self, seconds=0.6):
        """Let a change draw (animations are off, but loaders and images take a frame or two)."""
        time.sleep(seconds)

    def reset(self):
        """Close everything that might be open, so each test starts from the plain desktop."""
        for target, fn in (("settings", "close"), ("launcher", "close"), ("picker", "close"), ("switcher", "cancel"), ("wallpaperSwitcher", "cancel"),
                           ("overview", "close"), ("popout", "close"), ("power", "cancel"), ("polkit", "close"),
                           ("screensaver", "stop"), ("lock", "closePreview"), ("assistant", "stop"), ("assistant", "clear"), ("assistant", "close"), ("dock", "closeMenu"),
                           ("dock", "closePreview"), ("quicklook", "close")):
            try:
                self.ipc(target, fn)
            except SessionError:
                pass

    def windows(self):
        """The addresses of the app windows showing now."""
        try:
            return {c["address"] for c in self.hyprctl("clients", json_out=True) if c.get("mapped")}
        except (SessionError, ValueError, TypeError):
            return set()

    def tidy_after(self, before, who):
        """After a test class in the shared session: what it left on screen goes, so the next
        file starts from the same desktop (a notification pop-up left up once sat over another
        test's screenshots). The windows it opened close, notifications and their pop-ups clear,
        open panels close. What was left is noted in tests/out/live/<part>/left-behind.txt, for
        finding the tests that should tidy up after themselves."""
        try:
            st = self.state()
        except SessionError:
            return
        left = []
        new = [c for c in self.hyprctl("clients", json_out=True) if c.get("mapped") and c["address"] not in before]
        if new:
            left.append("%d window(s): %s" % (len(new), ", ".join(sorted({c.get("class") or "?" for c in new}))))
        toasts = (st.get("notifications") or {}).get("toasts") or 0
        if toasts:
            left.append("%d notification pop-up(s)" % toasts)
        if st.get("popout"):
            left.append("the %s panel open" % st["popout"])
        for c in new:
            self.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = "address:%s" })) end' % c["address"])
        try:
            self.ipc("notifications", "clear")
        except SessionError:
            pass
        self.reset()
        if new:
            self._until(lambda: not (self.windows() - set(before)), 5, "the windows it left to close")
        if left:
            with open(os.path.join(self.out, "left-behind.txt"), "a") as f:
                f.write("%s: %s\n" % (who, "; ".join(left)))

    def screenshot(self, path, output=OUTPUT):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.run(["grim", "-o", output, path], check=True)
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
        # Quickshell's own crash reports (a log with the backtrace, and the minidump): it writes
        # them under the cache, which is thrown away with the scratch home, so a crash would
        # otherwise leave nothing but "Slate died"
        # ...and the reports bin/slate's keeper writes in their place (Quickshell's own handler is
        # off under it): tests/out/live/slate-crashes
        for src, name in ((os.path.join(self.h.cache, "quickshell", "crashes"), "crashes"),
                          (os.path.join(self.h.cache, "slate", "crashes"), "slate-crashes")):
            if os.path.isdir(src):
                dest = os.path.join(self.out, name)
                shutil.rmtree(dest, ignore_errors=True)
                try:
                    shutil.copytree(src, dest)
                except OSError:
                    pass

    def died(self):
        """True (after keeping the logs and any crash report) when Slate is no longer running."""
        if self.alive():
            return False
        self.save_logs()
        # ...and under a name of its own: the next session on this display writes slate.log
        # again, and a crash seen once in a repeated run was left with nothing to say why
        try:
            shutil.copy(self.log_path(), os.path.join(self.out, time.strftime("slate-died-%H%M%S.log")))
        except OSError:
            pass
        return True

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
