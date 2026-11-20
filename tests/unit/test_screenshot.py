"""scripts/screenshot.sh: choosing an area. Pressing Print again while the chooser is still
open used to start another on top of it, each one dimming the screen further (a bug). Only
one chooser may be open; once it's done, the next screenshot starts as usual."""
import os
import shutil
import subprocess
import time

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "screenshot.sh")

# A chooser that stays open a while (as if you were still deciding), then gives an area
SLURP = """#!/bin/sh
echo opened >> "%s"
sleep "${STUB_SLURP_SECONDS:-0}"
echo "10,10 100x80"
"""


class OneChooser(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        slate.need("flock")
        self.s = Stubs(self.h)
        self.opened = os.path.join(self.h.dir, "slurp-opened")
        p = os.path.join(self.s.dir, "slurp")
        with open(p, "w") as f:
            f.write(SLURP % self.opened)
        os.chmod(p, 0o755)
        self.s.add("grim")
        self.s.add("wl-copy")
        self.s.add("notify-send")
        self.s.add("hyprctl", stdout="[]")
        self.s.add("hyprpicker", missing=True)        # (no freezing: nothing to freeze here)
        self.s.add("swash", missing=True)
        self.env = self.s.env

    def choosers(self):
        if not os.path.exists(self.opened):
            return 0
        with open(self.opened) as f:
            return len(f.read().split())

    def test_second_press_does_not_open_another(self):
        first = subprocess.Popen(["/bin/sh", SCRIPT, "region"], env=dict(self.env, STUB_SLURP_SECONDS="2"),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(first.kill)
        for _ in range(40):
            if self.choosers() == 1:
                break
            time.sleep(0.05)
        self.assertEqual(self.choosers(), 1, "the chooser never opened")
        for _ in range(3):
            code, out = run(["/bin/sh", SCRIPT, "region"], env=self.env, timeout=10)
            self.assertEqual(code, 0, out)
        self.assertEqual(self.choosers(), 1, "pressing Print again opened another chooser")
        self.assertEqual(self.s.calls("grim"), [], "a second screenshot was taken")
        self.assertEqual(first.wait(timeout=10), 0)
        self.assertEqual(len(self.s.calls("grim")), 1)

    def test_next_screenshot_after_choosing(self):
        """The lock is only for choosing: once the first is saved, another can be taken."""
        for n in (1, 2):
            code, out = run(["/bin/sh", SCRIPT, "region"], env=self.env, timeout=10)
            self.assertEqual(code, 0, out)
            self.assertEqual(self.choosers(), n)
        self.assertEqual(len(self.s.calls("grim")), 2)

    def test_whole_screen_needs_no_chooser(self):
        """Super+Print takes the screen at once, even while a chooser is open."""
        first = subprocess.Popen(["/bin/sh", SCRIPT, "region"], env=dict(self.env, STUB_SLURP_SECONDS="2"),
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(first.kill)
        time.sleep(0.5)
        code, out = run(["/bin/sh", SCRIPT, "screen"], env=self.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.s.calls("grim")), 1)
        first.wait(timeout=10)


class PrivateMode(Case):
    """Private Mode (PrivateMode.qml) leaves a mark in the runtime folder while it's on: no
    screenshot is taken then, and a notification says why."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        for name in ("slurp", "grim", "wl-copy", "notify-send"):
            self.s.add(name, stdout="10,10 100x80\n" if name == "slurp" else "")
        self.s.add("hyprctl", stdout="[]")
        self.s.add("hyprpicker", missing=True)
        self.s.add("swash", missing=True)

    def test_no_screenshots_while_private(self):
        open(os.path.join(self.h.runtime, "slate-private"), "w").close()
        for mode in ("region", "window", "screen"):
            with self.subTest(mode):
                code, out = run(["/bin/sh", SCRIPT, mode], env=self.s.env, timeout=10)
                self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("grim"), [], "a screenshot was taken in Private Mode")
        self.assertEqual(self.s.calls("slurp"), [], "the chooser opened in Private Mode")
        said = self.s.calls("notify-send")
        self.assertEqual(len(said), 3)
        self.assertTrue(all("Screenshots are off" in c for c in said), said)

    def test_back_when_it_is_off(self):
        code, out = run(["/bin/sh", SCRIPT, "screen"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.s.calls("grim")), 1)


class Failures(Case):
    """A screenshot that can't be taken or saved says so in a notification: the panel has
    closed by then, so it used to look as if nothing had happened. Pressing Esc in the chooser
    is not a failure, and stays silent."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.mktemp = shutil.which("mktemp")
        self.s = Stubs(self.h)
        for name in ("grim", "wl-copy", "notify-send"):
            self.s.add(name)
        self.s.add("slurp", stdout="10,10 100x80\n")
        self.s.add("hyprctl", stdout="[]")
        self.s.add("hyprpicker", missing=True)
        self.s.add("swash", missing=True)
        self.folder = self.h("Pictures", "Screenshots")

    def tool(self, name, text):
        """A stand-in written here, for what Stubs can't do (saying something on stderr)."""
        p = os.path.join(self.s.dir, name)
        with open(p, "w") as f:
            f.write("#!/bin/sh\necho called >> '%s.called'\n%s\n" % (p, text))
        os.chmod(p, 0o755)

    def shot(self, mode):
        return run(["/bin/sh", SCRIPT, mode], env=self.s.env, timeout=10)

    def said(self):
        """The notifications sent, as (title, body)."""
        return [tuple(c[-2:]) for c in self.s.calls("notify-send")]

    def saved(self):
        return os.listdir(self.folder) if os.path.isdir(self.folder) else []

    def test_a_window_with_a_named_workspace_about(self):
        """Choosing a window, with a window on a named workspace (Hyprland 0.57 gives it no id):
        the list of windows stopped with a KeyError, and the chooser never opened."""
        self.tool("hyprctl", "case \"$*\" in\n"
                  "  *monitors*) echo '[{\"activeWorkspace\": {\"id\": 1, \"name\": \"1\"}}]' ;;\n"
                  "  *clients*) echo '[{\"mapped\": true, \"workspace\": {\"name\": \"games\"}, \"at\": [0, 0], \"size\": [9, 9]},"
                  " {\"mapped\": true, \"workspace\": {\"id\": 1, \"name\": \"1\"}, \"at\": [10, 10], \"size\": [100, 80]}]' ;;\n"
                  "esac")
        code, out = self.shot("window")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.s.calls("slurp")), 1, "the chooser didn't open")
        self.assertEqual(len(self.saved()), 1)

    def test_all_well_says_saved(self):
        code, out = self.shot("region")
        self.assertEqual(code, 0, out)
        self.assertEqual([t for t, b in self.said()], ["Screenshot saved"])
        self.assertEqual(len(self.saved()), 1)

    def test_grim_not_installed(self):
        self.s.add("grim", missing=True)
        for mode in ("region", "window", "screen"):
            with self.subTest(mode):
                self.assertEqual(self.shot(mode)[0], 1)
        self.assertEqual(self.s.calls("slurp"), [], "the chooser opened with nothing to take the picture")
        said = self.said()
        self.assertEqual([t for t, b in said], ["Slate couldn't take the screenshot"] * 3)
        self.assertTrue(all('Install the "grim" package' in b for t, b in said), said)

    def test_slurp_not_installed(self):
        """No chooser: an area or a window can't be picked, and the whole screen still can."""
        self.s.add("slurp", missing=True)
        for mode in ("region", "window"):
            with self.subTest(mode):
                self.assertEqual(self.shot(mode)[0], 1)
        self.assertEqual(self.s.calls("grim"), [])
        said = self.said()
        self.assertEqual([t for t, b in said], ["Slate couldn't take the screenshot"] * 2)
        self.assertTrue(all('Install the "slurp" package' in b for t, b in said), said)
        code, out = self.shot("screen")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.saved()), 1)

    def test_escape_in_the_chooser_is_silent(self):
        """Esc: slurp says "selection cancelled" and stops. That's a choice, not a failure."""
        self.tool("slurp", "echo 'selection canceled' >&2\nexit 1")
        code, out = self.shot("region")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.said(), [])
        self.assertEqual(self.s.calls("grim"), [])
        self.assertEqual(self.saved(), [])

    def test_chooser_fails(self):
        self.tool("slurp", "echo 'failed to connect to a wayland display' >&2\nexit 1")
        code, out = self.shot("region")
        self.assertEqual(code, 1, out)
        (title, body), = self.said()
        self.assertEqual(title, "Slate couldn't take the screenshot")
        self.assertIn("slurp", body)
        self.assertIn("failed to connect to a wayland display", body)
        self.assertEqual(self.s.calls("grim"), [])

    def test_grim_fails(self):
        self.tool("grim", "echo 'compositor doesn’t support the screen capture protocol' >&2\nexit 1")
        for mode in ("region", "screen"):
            with self.subTest(mode):
                self.assertEqual(self.shot(mode)[0], 1)
        said = self.said()
        self.assertEqual([t for t, b in said], ["Slate couldn't take the screenshot"] * 2)
        self.assertTrue(all("screen capture protocol" in b for t, b in said), said)
        self.assertEqual(self.saved(), [])
        self.assertEqual(self.s.calls("wl-copy"), [], "a picture that wasn't taken was copied")

    def test_cannot_save(self):
        """The folder can't be made (something else has its name): said, and still copied."""
        with open(self.h("Pictures"), "w") as f:
            f.write("not a folder")
        code, out = self.shot("screen")
        self.assertEqual(code, 1, out)
        (title, body), = self.said()
        self.assertEqual(title, "Slate couldn't save the screenshot")
        self.assertIn(self.folder, body)
        self.assertEqual(len(self.s.calls("wl-copy")), 1)

    def test_mktemp_without_gnu_options(self):
        """Not every mktemp takes --suffix (BSD's and busybox's don't)."""
        self.tool("mktemp", 'case "$*" in *--*) echo "mktemp: unknown option" >&2; exit 1 ;; esac\n'
                            'exec "%s" "$@"' % self.mktemp)
        code, out = self.shot("screen")
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.saved()), 1)
        self.assertEqual([t for t, b in self.said()], ["Screenshot saved"])
