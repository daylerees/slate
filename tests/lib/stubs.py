"""Fake commands for unit tests: put first on PATH, each replays a fixture and logs how it
was called, so Slate's scripts can be run without Hyprland, NetworkManager, CUPS…

    with Stubs(home) as s:
        s.add("hyprctl", stdout=open(fixture("hyprctl/clients.json")).read())
        s.add("lpstat", by_args={"-v": "device for X: ipp://…", "-d": "system default destination: X"})
        s.add("magick", missing=True)          # as if it isn't installed at all
        code, out = run([script, …], env=s.env)
        s.calls("hyprctl")                     # [["-j", "clients"], …]

A stub's reply can depend on its arguments: `by_args` maps a string to look for in the
joined arguments (first match wins; "" matches anything) to the output.
"""
import json
import os
import shlex
import stat
import sys

import slate

STUB = """#!{python}
import json, os, sys
spec = json.load(open({spec!r}))
with open({log!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
args = " ".join(sys.argv[1:])
out, code = spec["stdout"], spec["code"]
for key, reply in spec["by_args"]:
    if key in args:
        out, code = (reply, 0) if isinstance(reply, str) else (reply[0], reply[1])
        break
if spec["stdin_to"]:
    open(spec["stdin_to"], "a").write(sys.stdin.read())
sys.stdout.write(out)
sys.exit(code)
"""


class Stubs:
    # Commands hidden by default, so a script under test can never reach the real one (and
    # the real desktop) through them, even when a test forgets to stub it
    BLOCKED = ("hyprctl", "notify-send", "qs", "quickshell", "systemctl", "loginctl", "gsettings",
               "nmcli", "bluetoothctl", "wpctl", "pactl", "busctl", "gdbus", "dbus-send", "xdg-open",
               "wl-copy", "wl-paste", "pw-play", "brightnessctl", "powerprofilesctl", "lpadmin",
               "pkexec", "sudo")

    def __init__(self, home):
        self.home = home
        self.dir = os.path.join(home.dir, "stubs")
        self.logdir = os.path.join(home.dir, "stub-calls")
        os.makedirs(self.dir, exist_ok=True)
        os.makedirs(self.logdir, exist_ok=True)
        self.hidden = set()
        for name in self.BLOCKED:
            self.add(name, stdout="", code=127, stderr_note=True)
        self.env = dict(home.env)
        self.env["PATH"] = self.dir + ":" + home.env["PATH"]

    def add(self, name, stdout="", code=0, by_args=None, missing=False, stdin_to=None, stderr_note=False):
        """Make `name` a fake command (or, with missing=True, hide it as if not installed)."""
        p = os.path.join(self.dir, name)
        if missing:
            # A stub that says "not found", and is skipped by `command -v`/shutil.which
            self.hidden.add(name)
            if os.path.exists(p):
                os.remove(p)
            self._hide_real(name)
            return
        spec = os.path.join(self.logdir, name + ".spec.json")
        with open(spec, "w") as f:
            json.dump({"stdout": stdout, "code": code, "by_args": list((by_args or {}).items()),
                       "stdin_to": stdin_to}, f)
        with open(p, "w") as f:
            f.write(STUB.format(python=sys.executable, spec=spec, log=self._log(name)))
        os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    def _log(self, name):
        return os.path.join(self.logdir, name + ".calls")

    def _hide_real(self, name):
        """Rebuild PATH without the directories that hold the real `name`, linking every other
        program from them into a private folder so nothing else goes missing."""
        keep = os.path.join(self.home.dir, "path-without")
        os.makedirs(keep, exist_ok=True)
        parts = self.env["PATH"].split(":") if hasattr(self, "env") else self.home.env["PATH"].split(":")
        new = []
        for d in parts:
            if d in (self.dir, keep) or not os.path.exists(os.path.join(d, name)):
                new.append(d)
                continue
            for n in os.listdir(d):
                src, dst = os.path.join(d, n), os.path.join(keep, n)
                if n not in self.hidden and not os.path.lexists(dst):
                    try:
                        os.symlink(src, dst)
                    except OSError:
                        pass
            if keep not in new:
                new.append(keep)
        for n in self.hidden:
            if os.path.lexists(os.path.join(keep, n)):
                os.remove(os.path.join(keep, n))
        self.env["PATH"] = ":".join(new)

    def calls(self, name):
        """Each call to the stub, as its argument list."""
        try:
            with open(self._log(name)) as f:
                return [json.loads(l) for l in f if l.strip()]
        except FileNotFoundError:
            return []

    def shell_line(self, name):
        return [" ".join(shlex.quote(a) for a in c) for c in self.calls(name)]

    def __enter__(self):
        return self

    def __exit__(self, *a):
        pass


def fixture(*parts):
    return os.path.join(slate.FIXTURES, *parts)


def fixture_text(*parts):
    with open(fixture(*parts), encoding="utf-8") as f:
        return f.read()
