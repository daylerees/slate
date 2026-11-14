"""bin/slate-greeter-install and bin/slate-session-install run as root (sudo, pkexec) and take
what they install from your own Slate folder, which anything running as you could have changed.
So neither may trust it: a name in greeter/files can't lead outside the login screen's folder,
and a link in session/ can't pull a file only root may read into /usr/local/bin.

Neither is run as root here. `id` says it's root, `runuser` runs the command as whoever runs
the test, `getent` gives the scratch home, and the commands that would write to the system
(`install`, and `mktemp` for the login screen's staging folder) are stand-ins that only record
what they were asked to do."""
import os
import pwd
import shutil
import stat

import slate
from slate import Case, run
from stubs import Stubs

GREETER = slate.path("shell", "bin", "slate-greeter-install")
SESSION = slate.path("shell", "bin", "slate-session-install")


def me():
    """The name `stat -c %U` gives for files the test makes."""
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        return "UNKNOWN"


class RootCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.slate = self.h.install_slate()
        self.s = Stubs(self.h)
        self.s.env["SUDO_USER"] = me()
        self.s.env.pop("PKEXEC_UID", None)
        self.log = os.path.join(self.h.dir, "root-calls")
        self.out = os.path.join(self.h.dir, "installed")
        os.makedirs(self.out)
        # "You are root", and the person who ran sudo lives in the scratch home
        self.stub("id", 'case "$*" in -u) echo 0 ;; *) echo tester ;; esac')
        self.stub("getent", f'echo "$2:x:1000:1000::{self.h.home}:/bin/sh"')
        # runuser -u <name> -- <command…>: the command, as whoever runs the test
        self.stub("runuser", '[ "$1" = -u ] && shift 2; [ "$1" = -- ] && shift; exec "$@"')
        # install … <source> <dest>: recorded, and the source's content kept under its
        # installed name (following a link, as the real one does)
        self.stub("install", f'echo "install $*" >> {self.log}\n'
                             'for a; do from=${to:-}; to=$a; done\n'
                             f'[ -d "$from" ] || [ -d "$to" ] || cat "$from" > {self.out}/$(basename "$to")')

    def stub(self, name, body):
        p = os.path.join(self.s.dir, name)
        with open(p, "w") as f:
            f.write("#!/bin/sh\n" + body + "\n")
        os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)

    def root_calls(self):
        try:
            with open(self.log) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []


class GreeterNames(RootCase):
    """Every line of greeter/files is checked before root makes anything from it."""

    def setUp(self):
        super().setUp()
        # The staging folder is made under /usr/local/share: recorded instead, and the script
        # stops there, so reaching it means the list was accepted
        self.stub("mktemp", f'echo "mktemp $*" >> {self.log}; exit 1')

    def install_with(self, *lines):
        """Run it with these lines added to Slate's own list."""
        with open(slate.path("shell", "greeter", "files")) as f:
            own = f.read()
        with open(os.path.join(self.slate, "greeter", "files"), "w") as f:
            f.write(own + "\n" + "\n".join(lines) + "\n")
        return run([GREETER], env=self.s.env, timeout=20)

    def test_names_that_leave_the_folder_stop_it(self):
        for name in ("../x", "/etc/x", "a/../../b", "..", "a//b", "a/", "a$b", "a;b", "a\\b", "`id`", "é.qml"):
            with self.subTest(name=name):
                if os.path.exists(self.log):
                    os.remove(self.log)
                code, out = self.install_with(f"{name}  greeter/shell.qml")
                self.assertNotEqual(code, 0, f"{name!r} was accepted:\n{out}")
                self.assertEqual(self.root_calls(), [], f"{name!r}: root went on to write:\n{out}")
                self.assertIn("Not installed", out)
                self.assertIn(name, out, "the message doesn't say which name")

    def test_sources_that_leave_your_folder_stop_it(self):
        for src in ("/etc/shadow", "../../etc/shadow", "greeter/../../x", ".."):
            with self.subTest(src=src):
                if os.path.exists(self.log):
                    os.remove(self.log)
                code, out = self.install_with(f"extra.qml  {src}")
                self.assertNotEqual(code, 0, f"{src!r} was accepted:\n{out}")
                self.assertEqual(self.root_calls(), [], f"{src!r}: root went on to write:\n{out}")
                self.assertIn("Not installed", out)

    def test_good_names_go_ahead(self):
        """Slate's own list, and names like its own, reach the staging step as before."""
        code, out = self.install_with("extra/Deep-er_1.qml  greeter/shell.qml", "a.b/c  Config.qml")
        self.assertNotIn("Not installed", out)
        self.assertEqual([c.split()[0] for c in self.root_calls()], ["mktemp"], out)


class SessionFiles(RootCase):
    """The session's two files are read as you, and a link is refused."""

    def session(self, top=None):
        return os.path.join(top or self.slate, "session")

    def installed(self, name):
        with open(os.path.join(self.out, name)) as f:
            return f.read()

    def original(self, name):
        with open(slate.path("shell", "session", name)) as f:
            return f.read()

    def assert_installed(self, code, out):
        self.assertEqual(code, 0, out)
        calls = self.root_calls()
        self.assertEqual(len(calls), 2, out)
        self.assertTrue(calls[0].endswith(" /usr/local/bin/slate-session"), calls[0])
        self.assertTrue(calls[1].endswith(" /usr/share/wayland-sessions/slate.desktop"), calls[1])
        self.assertIn("-m 755 -o root -g root", calls[0])
        self.assertIn("-m 644 -o root -g root", calls[1])
        self.assertEqual(self.installed("slate-session"), self.original("slate-session"))
        self.assertEqual(self.installed("slate.desktop"), self.original("slate.desktop"))
        return calls

    def test_a_normal_install(self):
        code, out = run([SESSION], env=self.s.env, timeout=20)
        calls = self.assert_installed(code, out)
        # (from root's own copy, never straight from your folder as root)
        for c in calls:
            self.assertNotIn(self.h.home, c, "root read the file from your folder itself")

    def test_a_link_is_refused(self):
        secret = os.path.join(self.h.dir, "only-root-may-read")
        with open(secret, "w") as f:
            f.write("SECRET\n")
        for name in ("slate-session", "slate.desktop"):
            with self.subTest(name=name):
                slate_dir = os.path.join(self.h.dir, "linked-" + name, "slate")
                shutil.copytree(self.slate, slate_dir)
                p = os.path.join(slate_dir, "session", name)
                os.remove(p)
                os.symlink(secret, p)
                code, out = run([SESSION, slate_dir], env=self.s.env, timeout=20)
                self.assertNotEqual(code, 0, f"a linked {name} was installed:\n{out}")
                self.assertEqual(self.root_calls(), [], "something was installed all the same")
                self.assertEqual(os.listdir(self.out), [])
                self.assertIn("is a link", out)

    def test_the_slate_folder_can_be_named(self):
        """With XDG_CONFIG_HOME set, Slate isn't in ~/.config/slate: install.sh passes it."""
        elsewhere = os.path.join(self.h.dir, "elsewhere", "slate")
        os.makedirs(os.path.dirname(elsewhere))
        os.rename(self.slate, elsewhere)
        code, out = run([SESSION, elsewhere], env=self.s.env, timeout=20)
        self.assert_installed(code, out)
        # (and through a link to it, which is resolved first)
        os.remove(self.log)
        link = os.path.join(self.h.dir, "a-link")
        os.symlink(elsewhere, link)
        self.assert_installed(*run([SESSION, link], env=self.s.env, timeout=20))

    def test_a_folder_that_is_not_there_or_not_yours(self):
        code, out = run([SESSION, os.path.join(self.h.dir, "nowhere")], env=self.s.env, timeout=20)
        self.assertNotEqual(code, 0, out)
        self.assertIn("Can't find your Slate folder", out)
        code, out = run([SESSION, os.path.join(self.slate, "session", "slate-session")], env=self.s.env, timeout=20)
        self.assertNotEqual(code, 0, "a file was taken as the Slate folder")
        # A complete Slate folder, but someone else ran sudo: it isn't theirs
        env = dict(self.s.env, SUDO_USER="slate-test-someone-else")
        code, out = run([SESSION, self.slate], env=env, timeout=20)
        self.assertNotEqual(code, 0, out)
        self.assertIn("own folder", out)
        self.assertEqual(self.root_calls(), [])

    def test_the_callers_say_where_slate_is(self):
        with open(slate.path("install.sh")) as f:
            self.assertIn('sudo "$DEST/bin/slate-session-install" "$DEST"', f.read())
        with open(slate.path("shell", "bin", "slate-system")) as f:
            self.assertIn('"$SRC/bin/slate-session-install" "$SRC"', f.read())
