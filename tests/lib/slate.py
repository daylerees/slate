"""Shared helpers for Slate's tests: where things are, running commands, scratch homes."""
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHELL = os.path.join(ROOT, "shell")
TESTS = os.path.join(ROOT, "tests")
FIXTURES = os.path.join(TESTS, "fixtures")
OUT = os.environ.get("SLATE_TEST_OUT") or os.path.join(TESTS, "out")


def path(*parts):
    """A path inside the repo."""
    return os.path.join(ROOT, *parts)


def read(*parts):
    with open(path(*parts), encoding="utf-8") as f:
        return f.read()


def files(top, *exts, skip=()):
    """Every file under `top` (repo-relative) ending in one of `exts`, repo-relative, sorted."""
    out = []
    for d, dirs, names in os.walk(path(top)):
        dirs[:] = sorted(x for x in dirs if x not in ("__pycache__", ".git", "out"))
        rel = os.path.relpath(d, ROOT)
        if any(rel == s or rel.startswith(s + "/") for s in skip):
            continue
        out += [os.path.join(rel, n) for n in sorted(names) if n.endswith(exts)]
    return out


def tool(name, *fallbacks):
    """The first of these programs that's installed, or None."""
    for n in (name,) + fallbacks:
        if os.path.isabs(n) and os.access(n, os.X_OK):
            return n
        found = shutil.which(n)
        if found:
            return found
    return None


def need(name, *fallbacks):
    """Like tool(), but skips the test when none is installed."""
    found = tool(name, *fallbacks)
    if not found:
        raise unittest.SkipTest(f"{name} isn't installed")
    return found


def run(cmd, env=None, cwd=None, timeout=120, input=None):
    """Run a command; returns (exit code, stdout+stderr as text)."""
    try:
        p = subprocess.run(cmd, env=env, cwd=cwd, timeout=timeout, input=input,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return 124, out + f"\n(timed out after {timeout}s)"


class ScratchHome:
    """A throwaway HOME with every XDG_* directory inside it, so nothing a test runs can touch
    the real one. `env` is a clean environment pointing at it."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="slate-test-")
        self.home = os.path.join(self.dir, "home")
        os.makedirs(self.home, mode=0o700)
        # Short, straight under /tmp: sockets in it (Hyprland's, Quickshell's) have a 108 byte limit
        self.runtime = tempfile.mkdtemp(prefix="sr", dir="/tmp")
        self.config = os.path.join(self.home, ".config")
        self.cache = os.path.join(self.home, ".cache")
        self.data = os.path.join(self.home, ".local", "share")
        self.state = os.path.join(self.home, ".local", "state")
        for d in (self.config, self.cache, self.data, self.state):
            os.makedirs(d)
        self.env = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": self.home, "USER": os.environ.get("USER", "test"),
            "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "TZ": "UTC",
            "XDG_CONFIG_HOME": self.config, "XDG_CACHE_HOME": self.cache,
            "XDG_DATA_HOME": self.data, "XDG_STATE_HOME": self.state,
            "XDG_RUNTIME_DIR": self.runtime,
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=/nonexistent",
            "PYTHONDONTWRITEBYTECODE": "1",
        }

    def __call__(self, *parts):
        return os.path.join(self.home, *parts)

    def install_slate(self):
        """A copy of shell/ at $XDG_CONFIG_HOME/slate, like an install. Returns its path."""
        dest = os.path.join(self.config, "slate")
        # Your own files (settings, hypr/, user/) only at the top, like the installer
        mine = {"settings.json", "hypr", "user", "install.log", "VERSION", ".manifest"}

        def ignore(d, names):
            top = os.path.samefile(d, SHELL)
            return [n for n in names if n == "__pycache__" or (top and n in mine)]
        shutil.copytree(SHELL, dest, ignore=ignore)
        return dest

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)
        shutil.rmtree(self.runtime, ignore_errors=True)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.cleanup()


class Case(unittest.TestCase):
    """Base for Slate's tests: a scratch home per test (self.h), cleaned up after."""
    maxDiff = 4000
    longMessage = False         # a test's own message alone, without "False is not true :"
    scratch = False

    def setUp(self):
        if self.scratch:
            self.h = ScratchHome()
            self.addCleanup(self.h.cleanup)

    def log(self, name, text):
        """Save longer output under tests/out/logs; returns the path, for a failure message."""
        d = os.path.join(OUT, "logs")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, name.replace("/", "_"))
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        return os.path.relpath(p, os.getcwd()) if p.startswith(os.getcwd()) else p

    def ok(self, cmd, msg=None, logname=None, **kw):
        """Run a command and fail with its first lines of output if it doesn't exit 0."""
        code, out = run(cmd, **kw)
        if code != 0:
            first = next((l.strip() for l in out.splitlines() if l.strip()), "(no output)")
            where = f" (log: {self.log(logname, out)})" if logname else ""
            self.fail(f"{msg or os.path.basename(cmd[0])} exited {code}: {first}{where}")
        return out
