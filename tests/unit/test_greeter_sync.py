"""bin/slate-greeter-sync: --check says whether the login screen's installed code matches
yours, and a plain run copies its appearance (settings, wallpaper, avatar, fonts) into
SLATE_GREETER_DIR. Nothing here may ask for a password: sudo and pkexec are stubbed, and
checked to be unused.

The installed code's folder (/usr/local/share/slate-greeter) is fixed in the script, so the
--check tests run a copy with it pointed at a scratch folder instead."""
import json
import os
import re
import shutil

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "bin", "slate-greeter-sync")
REAL_CODE = "/usr/local/share/slate-greeter"


def code_files(src):
    """(installed name, source path) for the login screen's code, as greeter/files lists it."""
    out = []
    with open(os.path.join(src, "greeter", "files")) as f:
        for line in f:
            parts = line.split("#")[0].split()
            if len(parts) >= 2 and parts[0] not in ("-", "+"):
                out.append((parts[0], os.path.join(src, parts[1])))
    return out


def tree(top):
    """Every path under `top`, with its size and modification time."""
    out = {}
    for d, dirs, names in os.walk(top):
        for n in dirs + names:
            st = os.lstat(os.path.join(d, n))
            out[os.path.relpath(os.path.join(d, n), top)] = (st.st_size, st.st_mtime_ns)
    return out


class GreeterCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.slate = self.h.install_slate()
        self.s = Stubs(self.h)
        self.dest = os.path.join(self.h.dir, "var-lib-slate-greeter")
        self.s.env["SLATE_GREETER_DIR"] = self.dest
        self.s.env["USER"] = "tester"

    def no_password_asked(self):
        for cmd in ("sudo", "pkexec", "notify-send"):
            self.assertEqual(self.s.calls(cmd), [], f"{cmd} was run")


class Check(GreeterCase):
    def setUp(self):
        super().setUp()
        self.code = os.path.join(self.h.dir, "usr-local-share-slate-greeter")
        # The script, with its code folder in the scratch dir
        with open(SCRIPT) as f:
            src, n = re.subn(r"^CODE=/usr/local/share/slate-greeter$", f"CODE={self.code}", f.read(), flags=re.M)
        self.assertEqual(n, 1, "the script's CODE= line has changed; update this test")
        self.script = os.path.join(self.h.dir, "slate-greeter-sync")
        with open(self.script, "w") as f:
            f.write(src)

    def install_code(self, layout="us"):
        """What slate-greeter-install puts in place: the listed files and hyprland.lua."""
        for name, src in code_files(self.slate):
            p = os.path.join(self.code, name)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            shutil.copyfile(src, p)
        with open(os.path.join(self.slate, "greeter", "hyprland.lua")) as f:
            hypr = f.read().replace("__KB_LAYOUT__", layout)
        with open(os.path.join(self.code, "hyprland.lua"), "w") as f:
            f.write(hypr)

    def layout(self, kb):
        os.makedirs(self.dest, exist_ok=True)
        with open(os.path.join(self.dest, "user.json"), "w") as f:
            json.dump({"user": "tester", "kb_layout": kb}, f)

    def check(self):
        code, out = run(["bash", self.script, "--check"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.no_password_asked()
        return out

    def edit(self, name, text="\n// changed\n"):
        with open(os.path.join(self.code, name), "a") as f:
            f.write(text)

    def test_lists_files(self):
        """The code list isn't empty and every file in it exists (or the checks below prove nothing)."""
        files = code_files(self.slate)
        self.assertGreater(len(files), 5)
        for name, src in files:
            with self.subTest(name):
                self.assertTrue(os.path.isfile(src), src)

    def test_not_installed(self):
        self.assertEqual(self.check(), "not-installed\n")

    def test_current(self):
        self.install_code()
        self.assertEqual(self.check(), "current\n")

    def test_outdated(self):
        """Any difference in its code counts, the files shared with the desktop included."""
        for name in ("LoginScreen.qml", "shell.qml", "Config.qml", "emergency/Window.qml",
                     "scripts/wallpaper-accent.py", "hyprland.lua"):
            with self.subTest(name):
                self.install_code()
                self.assertEqual(self.check(), "current\n")
                self.edit(name)
                self.assertEqual(self.check(), "outdated\n")

    def test_file_missing(self):
        self.install_code()
        os.remove(os.path.join(self.code, "emergency", "Box.qml"))
        self.assertEqual(self.check(), "outdated\n")

    def test_keyboard_layout_from_greeter_data(self):
        """With no Hyprland to ask, the layout the login screen last had (in SLATE_GREETER_DIR)."""
        self.install_code(layout="de")
        self.assertEqual(self.check(), "outdated\n")       # expects "us" without it
        self.layout("de")
        self.assertEqual(self.check(), "current\n")
        self.layout("fr")
        self.assertEqual(self.check(), "outdated\n")

    def test_keyboard_layout_from_hyprland(self):
        """The running Hyprland's layout comes first."""
        self.install_code(layout="gb")
        self.layout("de")
        self.s.add("hyprctl", stdout='{"option": "input:kb_layout", "str": "gb", "set": true}\n')
        self.assertEqual(self.check(), "current\n")
        self.assertEqual(self.s.calls("hyprctl"), [["getoption", "input:kb_layout", "-j"]])

    def test_hyprland_layout_empty(self):
        self.install_code(layout="de")
        self.layout("de")
        self.s.add("hyprctl", stdout='{"option": "input:kb_layout", "str": "[[EMPTY]]", "set": false}\n')
        self.assertEqual(self.check(), "current\n")

    def test_writes_nothing(self):
        self.install_code()
        self.layout("us")
        # (the stubs' call logs aside)
        tops = (self.h.home, self.code, self.dest)
        before = [tree(t) for t in tops]
        self.check()
        self.assertEqual([tree(t) for t in tops], before)

    def test_real_script(self):
        """The script itself, unchanged: --check only reads, answers one word, and exits 0.
        (Its answer depends on this machine's login screen, so any of the three is fine.)"""
        code, out = run(["bash", SCRIPT, "--check"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.assertIn(out, ("not-installed\n", "outdated\n", "current\n"))
        if not os.path.isdir(REAL_CODE):
            self.assertEqual(out, "not-installed\n")
        self.no_password_asked()


class Sync(GreeterCase):
    """A plain run, copying the appearance into SLATE_GREETER_DIR."""

    def setUp(self):
        super().setUp()
        self.wall = os.path.join(self.h.dir, "wallpaper.jpg")
        with open(self.wall, "wb") as f:
            f.write(b"\xff\xd8\xff\xe0 not really a jpeg")
        self.settings({"wallpaper": self.wall, "fontFamily": "Geist", "accent": "#3584e4"})
        with open(self.h(".face"), "wb") as f:
            f.write(b"\x89PNG face")
        self.s.add("getent", stdout="tester:x:1000:1000:Test User,,,:/home/tester:/bin/bash\n")
        self.s.add("pgrep", code=1)
        self.s.add("fc-list", stdout="")
        self.s.add("hyprctl", stdout='{"option": "input:kb_layout", "str": "gb", "set": true}\n')
        self.s.env["SLATE_SESSION"] = "1"

    def settings(self, s):
        with open(os.path.join(self.slate, "settings.json"), "w") as f:
            json.dump(s, f)

    def sync(self):
        code, out = run(["bash", SCRIPT], env=self.s.env)
        self.no_password_asked()
        return code, out

    def same(self, a, b):
        with open(a, "rb") as f, open(b, "rb") as g:
            return f.read() == g.read()

    def test_not_set_up(self):
        code, out = self.sync()
        self.assertEqual(code, 1)
        self.assertEqual(out, f"slate-greeter-sync: {self.dest} isn't set up yet; run: "
                              "sudo ~/.config/slate/bin/slate-greeter-install\n")
        self.assertFalse(os.path.exists(self.dest))

    def test_copies_appearance(self):
        os.makedirs(os.path.join(self.dest, "fonts"))
        open(os.path.join(self.dest, "fonts", "OldFont.ttf"), "w").close()
        code, out = self.sync()
        self.assertEqual(code, 0, out)
        self.assertEqual(out, "slate-greeter-sync: login screen appearance updated\n")
        d = lambda *p: os.path.join(self.dest, *p)
        self.assertTrue(self.same(d("settings.json"), os.path.join(self.slate, "settings.json")))
        self.assertTrue(self.same(d("wallpaper"), self.wall))
        self.assertTrue(self.same(d("avatar"), self.h(".face")))
        with open(d("user.json")) as f:
            self.assertEqual(f.read(), '{ "user": "tester", "name": "Test User", "session": "slate", "kb_layout": "gb" }\n')
        # Slate's icon font and Geist; a font no longer wanted is removed
        self.assertEqual(sorted(os.listdir(d("fonts"))), ["Geist-Italic-Variable.ttf", "Geist-Variable.ttf",
                                                          "GeistMono-Italic-Variable.ttf", "GeistMono-Variable.ttf",
                                                          "tabler.ttf"])
        self.assertFalse([n for n in os.listdir(self.dest) if n.endswith(".tmp")], "temporary files left")

    def test_unchanged_files_left_alone(self):
        """A second run doesn't copy the wallpaper and fonts again."""
        os.makedirs(self.dest)
        self.assertEqual(self.sync()[0], 0)
        paths = [os.path.join(self.dest, n) for n in ("wallpaper", "settings.json", "fonts/tabler.ttf")]
        stamps = [os.stat(p).st_ino for p in paths]
        self.assertEqual(self.sync()[0], 0)
        self.assertEqual([os.stat(p).st_ino for p in paths], stamps)

    def test_no_wallpaper(self):
        """No wallpaper set (or it's gone): the old copy is removed, for plain slate."""
        os.makedirs(self.dest)
        self.assertEqual(self.sync()[0], 0)
        os.remove(self.wall)
        self.assertEqual(self.sync()[0], 0)
        self.assertFalse(os.path.exists(os.path.join(self.dest, "wallpaper")))

    def test_session(self):
        """The session you're in now: Slate, Hyprland under uwsm, or plain Hyprland."""
        os.makedirs(self.dest)
        for slate_session, uwsm, expected in (("1", 1, "slate"), (None, 0, "hyprland-uwsm"), (None, 1, "hyprland")):
            with self.subTest(expected):
                if slate_session:
                    self.s.env["SLATE_SESSION"] = slate_session
                else:
                    self.s.env.pop("SLATE_SESSION", None)
                self.s.add("pgrep", code=uwsm)
                self.assertEqual(self.sync()[0], 0)
                with open(os.path.join(self.dest, "user.json")) as f:
                    self.assertEqual(json.load(f)["session"], expected)

    def test_no_full_name(self):
        os.makedirs(self.dest)
        self.s.add("getent", stdout="tester:x:1000:1000::/home/tester:/bin/bash\n")
        self.assertEqual(self.sync()[0], 0)
        with open(os.path.join(self.dest, "user.json")) as f:
            self.assertEqual(json.load(f)["name"], "tester")
