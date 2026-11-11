"""bin/slate-greeter-sync: --check says whether the login screen's installed code matches
yours, and a plain run copies its appearance (settings, wallpaper, avatar, fonts) into
SLATE_GREETER_DIR. Nothing here may ask for a password: sudo and pkexec are stubbed, and
checked to be unused.

The installed code's folder (/usr/local/share/slate-greeter) is fixed in the script, so the
--check tests run a copy with it pointed at a scratch folder instead."""
import json
import os
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
        # The installed code's folder, in the scratch dir
        self.code = os.path.join(self.h.dir, "usr-local-share-slate-greeter")
        self.s.env["SLATE_GREETER_CODE"] = self.code
        self.script = SCRIPT

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
        env = {k: v for k, v in self.s.env.items() if k != "SLATE_GREETER_CODE"}
        code, out = run(["bash", SCRIPT, "--check"], env=env)
        self.assertEqual(code, 0, out)
        self.assertIn(out, ("not-installed\n", "outdated\n", "current\n"))
        if not os.path.isdir(REAL_CODE):
            self.assertEqual(out, "not-installed\n")
        self.no_password_asked()


class Status(Check):
    """--status: what Settings → Security needs to offer installing, updating or switching
    back, one key=value a line. Only reads; never asks for a password."""

    def setUp(self):
        super().setUp()
        self.etc = os.path.join(self.h.dir, "etc-greetd")
        os.makedirs(self.etc)
        self.s.env["SLATE_GREETD_ETC"] = self.etc
        # A computer run by systemd (bin/slate-init goes by /run/systemd/system; the tests'
        # container has no init system at all)
        self.s.env["SLATE_INIT_ROOT"] = os.path.join(self.h.dir, "root")
        os.makedirs(os.path.join(self.h.dir, "root", "run", "systemd", "system"))
        self.s.add("systemctl", by_args={"show -P Id display-manager.service": "sddm.service\n", "cat greetd.service": ""})

    def status(self):
        code, out = run(["bash", self.script, "--status"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.no_password_asked()
        return dict(l.split("=", 1) for l in out.splitlines())

    def use_slate(self, backup=True):
        """What slate-greeter-install leaves in /etc/greetd."""
        with open(os.path.join(self.etc, "config.toml"), "w") as f:
            f.write('[default_session]\ncommand = "start-hyprland -- -c /usr/local/share/slate-greeter/hyprland.lua"\n')
        if backup:
            with open(os.path.join(self.etc, "config.toml.before-slate"), "w") as f:
                f.write('[default_session]\ncommand = "agreety"\n')

    def test_keys(self):
        self.assertEqual(sorted(self.status()), ["backup", "dm", "enable", "greetd", "state", "switch", "used"])

    def test_not_installed(self):
        st = self.status()
        self.assertEqual(st["state"], "not-installed")
        self.assertEqual((st["used"], st["backup"], st["dm"]), ("no", "no", "sddm"))

    def test_in_use(self):
        self.install_code()
        self.use_slate()
        self.s.add("systemctl", by_args={"show -P Id display-manager.service": "greetd.service\n"})
        st = self.status()
        self.assertEqual((st["state"], st["used"], st["backup"], st["dm"]), ("current", "yes", "yes", "greetd"))

    def test_switched_back(self):
        """--revert puts greetd's old config back but leaves the code: installed, not used."""
        self.install_code()
        self.use_slate()
        os.replace(os.path.join(self.etc, "config.toml.before-slate"), os.path.join(self.etc, "config.toml"))
        st = self.status()
        self.assertEqual((st["state"], st["used"], st["backup"]), ("current", "no", "no"))

    def test_no_display_manager(self):
        self.s.add("systemctl", by_args={"show -P Id display-manager.service": "display-manager.service\n"})
        self.assertEqual(self.status()["dm"], "none")
        self.s.add("systemctl", code=1)
        self.assertEqual(self.status()["dm"], "none")

    def test_command_to_switch_greetd_on(self):
        st = self.status()
        self.assertEqual(st["enable"], "sudo systemctl enable --now greetd.service")
        self.assertEqual(st["switch"], "sudo systemctl disable sddm && sudo systemctl enable greetd", "sddm is the one running")

    def test_without_systemd(self):
        """OpenRC and elogind (Artix, Gentoo): the login manager and the command are its own."""
        import shutil
        shutil.rmtree(os.path.join(self.h.dir, "root", "run", "systemd"))
        os.makedirs(os.path.join(self.h.dir, "root", "run", "openrc"))
        self.s.add("rc-service", by_args={"greetd status": ""}, code=3)
        self.s.add("pgrep", code=1)
        st = self.status()
        self.assertEqual((st["dm"], st["enable"], st["switch"]), ("greetd", "sudo rc-update add greetd default && sudo rc-service greetd start", ""))

    def test_greetd(self):
        self.s.add("greetd")
        self.assertEqual(self.status()["greetd"], "yes")
        if not any(os.path.exists(p) for p in ("/usr/bin/greetd", "/usr/sbin/greetd")):
            self.s.add("greetd", missing=True)
            self.assertEqual(self.status()["greetd"], "no")


class Prompt(Status):
    """--prompt offers an update only while greetd uses Slate's login screen: once you've
    switched back (or never installed it), its changes are none of your business."""

    def setUp(self):
        super().setUp()
        self.s.add("notify-send", stdout="later\n")
        self.s.env["XDG_STATE_HOME"] = os.path.join(self.h.dir, "state")

    def prompt(self):
        code, out = run(["bash", self.script, "--prompt"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("pkexec"), [])
        self.assertEqual(self.s.calls("sudo"), [])
        return self.s.calls("notify-send")

    def test_asks_when_in_use(self):
        self.install_code()
        self.use_slate()
        self.edit("LoginScreen.qml")
        calls = self.prompt()
        self.assertEqual(len(calls), 1)
        self.assertIn("Login screen out of date", calls[0])

    def test_quiet_when_switched_back(self):
        self.install_code()
        self.use_slate()
        os.replace(os.path.join(self.etc, "config.toml.before-slate"), os.path.join(self.etc, "config.toml"))
        self.edit("LoginScreen.qml")
        self.assertEqual(self.prompt(), [])

    def test_quiet_when_not_installed(self):
        self.assertEqual(self.prompt(), [])

    def test_later_holds_for_a_week_and_ends_once_up_to_date(self):
        """"Later" waits a week. Updating in that week (from Settings, say) ends the wait, so the
        next change is asked about: it used to run on, and that change went unasked."""
        import time
        later = os.path.join(self.s.env["XDG_STATE_HOME"], "slate", "greeter-later")
        self.install_code()
        self.use_slate()
        self.edit("LoginScreen.qml")
        self.assertEqual(len(self.prompt()), 1)                    # asked; the stub answers "later"
        self.assertGreater(int(open(later).read()), time.time() + 6 * 24 * 3600)
        self.edit("LoginScreen.qml")
        self.assertEqual(len(self.prompt()), 1, "asked again within the week")
        self.install_code()                                        # brought up to date another way
        self.prompt()
        self.assertFalse(os.path.exists(later), "the wait outlived the update")
        # (a new change to the login screen itself: its own copy of the file, in this test's Slate)
        with open(os.path.join(self.slate, "LoginScreen.qml"), "a") as f:
            f.write("\n// a later change\n")
        self.assertEqual(len(self.prompt()), 2, "the change after an update wasn't asked about")


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
