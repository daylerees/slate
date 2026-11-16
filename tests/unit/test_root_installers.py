"""Slate's root helpers. Further down: they run only from a root-owned folder, which
bin/slate-helpers-install fills (HelpersInstall onwards). First, what two of them do there:

bin/slate-greeter-install and bin/slate-session-install run as root (sudo, pkexec) and take
what they install from your own Slate folder, which anything running as you could have changed.
So neither may trust it: a name in greeter/files can't lead outside the login screen's folder,
and a link in session/ can't pull a file only root may read into /usr/local/bin.

Neither is run as root here. `id` says it's root, `runuser` runs the command as whoever runs
the test, `getent` gives the scratch home, and the commands that would write to the system
(`install`, and `mktemp` for the login screen's staging folder) are stand-ins that only record
what they were asked to do."""
import os
import shlex
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

    def as_if_roots(self, writable_by_others=""):
        """stat says every folder is root's, and find says none can be written by anyone else
        (or the folder named can), as for Slate's copy for everyone in /usr/local/share."""
        self.stub("stat", 'case "$*" in *%U*) echo root ;; *) exec /usr/bin/stat "$@" ;; esac')
        self.stub("find", f'[ "$1" = {shlex.quote(writable_by_others) if writable_by_others else "/nothing"} ] && echo "$1"; exit 0')

    def test_the_copy_for_everyone(self):
        """Slate's copy for everyone is root's, not yours: it's taken, as long as only root can
        change it (it, and every folder above it)."""
        self.as_if_roots()
        self.assert_installed(*run([SESSION, self.slate], env=self.s.env, timeout=20))

    def test_a_copy_for_everyone_others_can_change(self):
        for where in (self.slate, os.path.dirname(self.slate)):
            with self.subTest(where):
                self.as_if_roots(writable_by_others=where)
                code, out = run([SESSION, self.slate], env=self.s.env, timeout=20)
                self.assertNotEqual(code, 0, out)
                self.assertIn("copy for everyone", out)
                self.assertEqual(self.root_calls(), [])

    def test_the_callers_say_where_slate_is(self):
        """(Both run the root-owned copy of it now: see the helpers' tests below.)"""
        with open(slate.path("install.sh")) as f:
            # (the release being installed: yours, where the copy for everyone is root's)
            self.assertIn('slate-session-install "$ROOT/shell" |', f.read())
        with open(slate.path("shell", "bin", "slate-system")) as f:
            self.assertIn('session) args+=("--session=$SRC")', f.read())


# ---- Slate's root helpers live in a root-owned folder --------------------------------------
# Everything Slate runs with your password used to be a script in your Slate folder, which
# anything running as you could change and then wait for the next prompt. Now root runs only
# the copies in /usr/local/libexec/slate, which bin/slate-helpers-install puts there.
#
# Nothing here touches the real system: the scripts are run from copies that say a scratch
# folder where they said /usr/local/libexec, /etc/polkit-1 and /etc/NIXOS (as
# test_distro_family.py does with /etc/os-release), and `install` writes only inside it.

HELPERS = ["slate-system-root", "slate-session-install", "slate-greeter-install", "slate-private-camera", "slate-update-install"]
LISTS = ["arch", "artix", "debian", "fedora", "gentoo", "opensuse", "void"]
REAL = "/usr/local/libexec/slate"


class HelpersCase(RootCase):
    def setUp(self):
        super().setUp()
        self.sys = os.path.join(self.h.dir, "system")
        os.makedirs(os.path.join(self.sys, "polkit-1", "rules.d"))
        self.target = os.path.join(self.sys, "libexec", "slate")
        self.rule = os.path.join(self.sys, "polkit-1", "rules.d", "49-slate-private-camera.rules")
        self.os_release = os.path.join(self.h.dir, "os-release")
        self.on("ID=slackware\n")
        shutil.copytree(slate.path("packaging"), os.path.join(self.slate, "packaging"))
        for name in ("slate-helpers-install", "slate-private-camera", "slate-system-root", "slate-system"):
            self.rewrite(name, self.swapped(slate.read("shell", "bin", name), keep_real=name == "slate-system"))
        self.boot = os.path.join(self.slate, "bin", "slate-helpers-install")
        # install: as the real one for folders and files inside the scratch system (owner and
        # group left out), only recorded for anywhere else
        self.stub("install", f'echo "install $*" >> {self.log}\n'
                             'dir=0; mode=644; set -- "$@" --end\n'
                             'while [ "$1" != --end ]; do\n'
                             '  case "$1" in -d) dir=1 ;; -D) ;; -m) mode=$2; shift ;; -o|-g) shift ;; *) set -- "$@" "$1" ;; esac\n'
                             '  shift\ndone; shift\n'
                             f'for a; do last=$a; done\ncase "$last" in {self.sys}/*) ;; *) exit 0 ;; esac\n'
                             'if [ "$dir" = 1 ]; then for a; do mkdir -p "$a" && chmod "$mode" "$a" || exit 1; done; exit 0; fi\n'
                             'rm -f "$2"; cat "$1" > "$2" && chmod "$mode" "$2"')

    def on(self, text):
        with open(self.os_release, "w") as f:
            f.write(text)

    def swapped(self, src, keep_real=False):
        """A script's source, with the scratch system where it named the real one. slate-system
        keeps the real folder's name (what it hands to pkexec is what's being checked)."""
        src = src.replace("/etc/os-release", self.os_release).replace("/usr/local/bin/slate-session", self.sys + "/slate-session")
        if keep_real:
            return src
        self.assertTrue("/usr/local/libexec" in src)
        return src.replace("/usr/local/libexec", self.sys + "/libexec").replace("/etc/polkit-1", self.sys + "/polkit-1") \
                  .replace("/etc/NIXOS", self.sys + "/NIXOS")

    def rewrite(self, name, text):
        p = os.path.join(self.slate, "bin", name)
        with open(p, "w") as f:
            f.write(text)
        os.chmod(p, 0o755)

    def home(self, name):
        return os.path.join(self.slate, "bin", name)

    def boot_run(self, *args, folder=None, env=None):
        return run([self.boot, folder or self.slate, *args], env=env or self.s.env, timeout=30)

    def state(self):
        code, out = run([self.boot, "--check", self.slate], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        return out.strip()

    def installed(self):
        found = []
        for top, _, names in os.walk(self.target):
            found += [os.path.relpath(os.path.join(top, n), self.target) for n in names]
        return sorted(found)

    def text(self, path):
        with open(path) as f:
            return f.read()


class HelpersInstall(HelpersCase):
    """bin/slate-helpers-install: the one script root runs from your folder."""

    def test_copies_exactly_its_list(self):
        self.assertEqual(self.state(), "missing")
        code, out = self.boot_run()
        self.assertEqual(code, 0, out)
        self.assertEqual(self.installed(), sorted(HELPERS + [f"packaging/{l}.txt" for l in LISTS]))
        calls = [c for c in self.root_calls() if " -d " not in c]
        self.assertEqual(len(calls), len(HELPERS) + len(LISTS), calls)
        for c in calls:
            self.assertIn(" -o root -g root ", c)
            self.assertIn(" -m 0644 " if c.endswith(".txt") else " -m 0755 ", c)
            # (from root's own copy of what it read as you, never straight from your folder)
            self.assertNotIn(self.slate, c, "root installed the file from your folder itself")
        for d in (c for c in self.root_calls() if " -d " in c):
            self.assertIn("-d -m 0755 -o root -g root", d)
        for name in HELPERS:
            self.assertEqual(self.text(os.path.join(self.target, name)), self.text(self.home(name)))
            self.assertTrue(os.access(os.path.join(self.target, name), os.X_OK))
        self.assertEqual(self.state(), "current")

    def test_the_list_is_all_there_is(self):
        """The list in the script is the root helpers and every package list: a new one that
        isn't added would never reach the root-owned folder."""
        src = slate.read("shell", "bin", "slate-helpers-install")
        self.assertIn('HELPERS="' + " ".join(HELPERS) + '"', src)
        self.assertIn('LISTS="' + " ".join(LISTS) + '"', src)
        self.assertEqual(sorted(n[:-4] for n in os.listdir(slate.path("packaging")) if n.endswith(".txt")), LISTS)
        for name in HELPERS:
            self.assertTrue(os.access(slate.path("shell", "bin", name), os.X_OK), name)

    def test_a_changed_copy_in_your_folder_is_out_of_date_and_changes_nothing(self):
        """Tampering with your folder's copy leaves what root runs as it was; all it does is
        make Slate say the helpers are out of date."""
        self.assertEqual(self.boot_run()[0], 0)
        pairs = [(self.home(n), os.path.join(self.target, n)) for n in HELPERS]
        pairs.append((os.path.join(self.slate, "packaging", "fedora.txt"), os.path.join(self.target, "packaging", "fedora.txt")))
        for yours, roots in pairs:
            with self.subTest(os.path.basename(yours)):
                before, was = self.text(yours), self.text(roots)
                with open(yours, "a") as f:
                    f.write("\ntouch /tmp/slate-test-should-never-run\n")
                self.assertEqual(self.state(), "outdated")
                self.assertEqual(self.text(roots), was, "what root runs changed with your copy")
                with open(yours, "w") as f:
                    f.write(before)
                self.assertEqual(self.state(), "current")

    def test_a_link_is_refused(self):
        secret = os.path.join(self.h.dir, "only-root-may-read")
        with open(secret, "w") as f:
            f.write("#!/bin/sh\nSECRET\n")
        for rel in ("bin/slate-greeter-install", "packaging/fedora.txt"):
            with self.subTest(rel):
                p = os.path.join(self.slate, rel)
                keep = self.text(p)
                os.remove(p)
                os.symlink(secret, p)
                code, out = self.boot_run()
                self.assertNotEqual(code, 0, out)
                self.assertIn("is a link", out)
                self.assertEqual(self.root_calls(), [], "something was installed all the same")
                self.assertFalse(os.path.exists(self.target))
                os.remove(p)
                with open(p, "w") as f:
                    f.write(keep)

    def test_what_is_not_a_script_is_refused(self):
        for text in ("", "not a script\n"):
            with self.subTest(text):
                self.rewrite("slate-session-install", text)
                code, out = self.boot_run()
                self.assertNotEqual(code, 0, out)
                self.assertIn("Nothing was changed", out)
                self.assertEqual(self.root_calls(), [])

    def test_odd_folders_and_names_are_refused(self):
        other = dict(self.s.env, SUDO_USER="slate-test-someone-else")
        for what, args, env in (("an option for a folder", ["-x"], None),
                                ("a folder that isn't there", [os.path.join(self.h.dir, "nowhere")], None),
                                ("a file for a folder", [self.boot], None),
                                ("someone else's sudo", [self.slate], other),
                                ("no folder", [], None)):
            with self.subTest(what):
                code, out = run([self.boot, *args], env=env or self.s.env, timeout=20)
                self.assertNotEqual(code, 0, out)
                self.assertEqual(self.root_calls(), [], out)
        # A helper to run afterwards is one of the list, by name: never a path, never another
        for name in ("sh", "../../../bin/sh", "/bin/sh", "slate-system", "slate-helpers-install", "slate-greeter-sync", ""):
            with self.subTest(name=name):
                code, out = self.boot_run(name, "-c", "echo RAN")
                self.assertNotEqual(code, 0, out)
                self.assertNotIn("RAN", out)
                self.assertIn("isn't one of Slate's helpers", out)
                self.assertEqual(self.root_calls(), [], out)

    def test_not_as_yourself_and_not_as_root_alone(self):
        self.stub("id", 'case "$*" in -u) echo 1000 ;; *) echo tester ;; esac')
        code, out = self.boot_run()
        self.assertNotEqual(code, 0)
        self.assertIn("run as root", out)
        self.stub("id", 'case "$*" in -u) echo 0 ;; *) echo tester ;; esac')
        env = dict(self.s.env)
        env.pop("SUDO_USER")
        self.assertNotEqual(self.boot_run(env=env)[0], 0)
        self.assertNotEqual(self.boot_run(env=dict(env, SUDO_USER="root"))[0], 0)
        self.assertEqual(self.root_calls(), [])

    def test_nixos_is_left_to_its_configuration(self):
        with open(os.path.join(self.sys, "NIXOS"), "w"):
            pass
        code, out = self.boot_run()
        self.assertEqual(code, 3, out)
        self.assertIn("NixOS", out)
        self.assertEqual(self.root_calls(), [])

    def test_then_runs_the_installed_copy(self):
        """One password does both: the helper named is run from the root-owned folder."""
        code, out = self.boot_run("slate-private-camera", "status")
        self.assertEqual(code, 0, out)
        self.assertIn(out.strip().splitlines()[-1], ("on", "off"))
        # (the camera's `install` only works from there, so this shows which copy ran)
        code, out = self.boot_run("slate-private-camera", "install")
        self.assertEqual(code, 0, out)
        self.assertIn(f'action.lookup("program") == "{self.target}/slate-private-camera"', self.text(self.rule))
        self.assertTrue(os.path.exists(os.path.join(self.target, "camera-allowed")))


class CameraHelper(HelpersCase):
    """bin/slate-private-camera install used to copy itself, from your folder, to where a rule
    then let it run as root with no password. It copies nothing now, and writes the rule only
    when it is the root-owned copy."""

    def test_install_from_your_folder_is_refused(self):
        self.assertEqual(self.boot_run()[0], 0)
        os.remove(self.log)
        for script in (self.home("slate-private-camera"), slate.path("shell", "bin", "slate-private-camera")):
            with self.subTest(script):
                code, out = run(["/bin/sh", script, "install"], env=self.s.env, timeout=10)
                self.assertEqual(code, 1, out)
                self.assertIn("install only runs from", out)
        self.assertFalse(os.path.exists(self.rule))
        self.assertFalse(os.path.exists(os.path.join(self.target, "camera-allowed")))
        self.assertEqual(self.root_calls(), [], "it installed something")

    def test_it_never_copies_itself(self):
        src = slate.read("shell", "bin", "slate-private-camera")
        self.assertNotIn("install -m", src)
        self.assertNotIn('"$self"', src)
        self.assertIn("TARGET=/usr/local/libexec/slate/slate-private-camera", src)

    def old_layout(self, rule=True):
        old = os.path.join(self.sys, "libexec", "slate-private-camera")
        os.makedirs(os.path.dirname(old))
        with open(old, "w") as f:
            f.write("#!/bin/sh\n# whatever your folder held the day it was copied\n")
        if rule:
            with open(self.rule, "w") as f:
                f.write(f'action.lookup("program") == "{old}"\n')
        return old

    def test_the_old_copy_and_its_rule_are_moved_over(self):
        old = self.old_layout()
        code, out = self.boot_run()
        self.assertEqual(code, 0, out)
        self.assertFalse(os.path.exists(old), "the old copy is still there")
        rule = self.text(self.rule)
        self.assertNotIn(f'"{old}"', rule, "the rule still lets the old path run without a password")
        self.assertIn(f'action.lookup("program") == "{self.target}/slate-private-camera"', rule)
        self.assertIn("subject.local && subject.active", rule)
        self.assertTrue(os.path.exists(os.path.join(self.target, "camera-allowed")))

    def test_no_rule_unless_you_had_said_yes(self):
        old = self.old_layout(rule=False)
        code, out = self.boot_run()
        self.assertEqual(code, 0, out)
        self.assertFalse(os.path.exists(old))
        self.assertFalse(os.path.exists(self.rule))
        self.assertFalse(os.path.exists(os.path.join(self.target, "camera-allowed")))


class SystemRoot(HelpersCase):
    """bin/slate-system-root, the half of slate-system that runs as root."""

    def setUp(self):
        super().setUp()
        self.assertEqual(self.boot_run()[0], 0)
        os.remove(self.log)
        self.root = os.path.join(self.target, "slate-system-root")
        for m in ("pacman", "dnf"):
            self.s.add(m)

    def test_only_from_the_root_owned_folder(self):
        self.on("ID=arch\n")
        for script in (self.home("slate-system-root"), slate.path("shell", "bin", "slate-system-root")):
            with self.subTest(script):
                code, out = run([script, "kitty"], env=self.s.env, timeout=10)
                self.assertEqual(code, 1, out)
                self.assertIn("only runs from", out)
        self.assertEqual(self.s.calls("pacman"), [])

    def test_installs_what_it_is_told_and_checks_it(self):
        self.on("ID=arch\n")
        code, out = run([self.root, "kitty", "foot"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("pacman"), [["-S", "--needed", "--noconfirm", "kitty", "foot"]])
        for bad in ("-Syu", "a b", "a;b", "$(id)", "--config=/tmp/x", "/tmp/x.pkg"):
            with self.subTest(bad):
                code, out = run([self.root, "kitty", bad], env=self.s.env, timeout=10)
                self.assertNotEqual(code, 0, out)
                self.assertIn("bad package name", out)
        self.assertEqual(len(self.s.calls("pacman")), 1)

    def test_the_full_upgrade_and_nothing_else(self):
        """--upgrade: the distro's whole system upgrade, one fixed command, never only some
        packages (a partial upgrade can break Arch), and nothing else may come with it."""
        for release, tool, expected in (("ID=arch\n", "pacman", ["-Syu", "--noconfirm"]),
                                        ("ID=fedora\n", "dnf", ["upgrade", "-y", "--refresh"])):
            with self.subTest(tool):
                self.on(release)
                os.remove(self.s._log(tool)) if os.path.exists(self.s._log(tool)) else None
                code, out = run([self.root, "--upgrade"], env=self.s.env, timeout=10)
                self.assertEqual(code, 0, out)
                self.assertEqual(self.s.calls(tool), [expected])
        self.on("ID=arch\n")
        os.remove(self.s._log("pacman"))
        for extra in ("kitty", "--overwrite=*", "--session"):
            with self.subTest(extra):
                code, out = run([self.root, "--upgrade", extra], env=self.s.env, timeout=10)
                self.assertNotEqual(code, 0, out)
        self.assertEqual(self.s.calls("pacman"), [])

    def test_repositories_come_from_the_root_owned_list(self):
        """Fedora's COPRs are read from root's own copy of the list: one added to your folder's
        list afterwards isn't switched on (it would be someone else's packages, as root)."""
        self.on("ID=fedora\n")
        with open(os.path.join(self.slate, "packaging", "fedora.txt"), "a") as f:
            f.write("copr:someone/else\n")
        code, out = run([self.root, "kitty"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        coprs = [c[-1] for c in self.s.calls("dnf") if "copr" in c]
        own = [l.split("#")[0].strip()[5:] for l in slate.read("packaging", "fedora.txt").splitlines() if l.startswith("copr:")]
        self.assertTrue(own)
        self.assertEqual(coprs, own)

    def test_the_session_is_installed_by_the_copy_beside_it(self):
        with open(self.home("slate-session-install"), "a") as f:
            f.write("\necho TAMPERED\n")
        code, out = run([self.root, "--session=" + self.slate], env=self.s.env, timeout=20)
        self.assertEqual(code, 0, out)
        self.assertNotIn("TAMPERED", out, "root ran the installer in your folder")
        calls = self.root_calls()
        self.assertEqual(len(calls), 2, out)
        self.assertTrue(calls[0].endswith(" /usr/local/bin/slate-session"), calls[0])


class SlateSystem(HelpersCase):
    """bin/slate-system, as you: what it hands to pkexec is the root-owned copy, or (only when
    those are missing or out of date) the one installer."""

    def setUp(self):
        super().setUp()
        self.system = os.path.realpath(self.home("slate-system"))
        self.top = os.path.dirname(os.path.dirname(self.system))
        self.s.add("pkexec")
        self.s.add("pacman")          # (asked whether each package is installed: yes)

    def pkexec(self, *args):
        before = len(self.s.calls("pkexec"))
        code, out = run([self.system, *args], env=self.s.env, timeout=20)
        return code, out, self.s.calls("pkexec")[before:]

    def check(self):
        code, out = run([self.system, "--check"], env=self.s.env, timeout=20)
        self.assertEqual(code, 0, out)
        return out.split()

    def test_up_to_date_runs_the_root_owned_copy(self):
        self.assertEqual(self.boot_run()[0], 0)
        self.assertEqual(self.check(), [])
        code, out, calls = self.pkexec("--root", "slate-greeter-install", "--code-only")
        self.assertEqual(code, 0, out)
        self.assertEqual(calls, [[REAL + "/slate-greeter-install", "--code-only"]])
        self.assertEqual(self.pkexec("--root", "slate-private-camera", "install")[2], [[REAL + "/slate-private-camera", "install"]])
        self.assertEqual(self.pkexec("--install", "kitty")[2], [])       # (no package manager known here)
        self.on("ID=arch\n")
        self.assertEqual(self.pkexec("--install", "kitty", "foot")[2], [[REAL + "/slate-system-root", "kitty", "foot"]])
        self.assertEqual(self.pkexec("--fix")[2], [])

    def test_missing_or_out_of_date_goes_through_the_one_installer(self):
        boot = os.path.join(self.top, "bin", "slate-helpers-install")
        for how in ("missing", "outdated"):
            with self.subTest(how):
                if how == "outdated":
                    self.assertEqual(self.boot_run()[0], 0)
                    with open(self.home("slate-session-install"), "a") as f:
                        f.write("# changed by this version\n")
                self.assertEqual(self.check(), ["helpers"])
                code, out, calls = self.pkexec("--root", "slate-greeter-install", "--code-only")
                self.assertEqual(calls, [[boot, self.top, "slate-greeter-install", "--code-only"]])
                # --fix with nothing else to do: the helpers alone
                self.assertEqual(self.pkexec("--fix")[2], [[boot, self.top]])

    def test_only_its_own_helpers(self):
        for name in ("sh", "slate-system-root", "../slate-private-camera", "/bin/sh", ""):
            with self.subTest(name=name):
                code, out, calls = self.pkexec("--root", name, "x")
                self.assertNotEqual(code, 0, out)
                self.assertEqual(calls, [])

    def test_nixos_is_told_before_any_password(self):
        self.on("ID=nixos\n")
        self.assertEqual(self.check(), [])
        code, out, calls = self.pkexec("--root", "slate-private-camera", "install")
        self.assertEqual(code, 3, out)        # (PrivateMode.qml says why, for this code)
        self.assertIn("on NixOS", out)
        self.assertEqual(calls, [])

    def test_the_prompt_says_where_the_helpers_come_from(self):
        """With only the helpers to do, the notification says they're copied from your Slate
        folder, and pressing Install runs the one installer."""
        self.s.add("notify-send", by_args={"install=Install": "install\n", "": ""})
        code, out, calls = self.pkexec("--prompt")
        self.assertEqual(code, 0, out)
        asked = self.s.calls("notify-send")[0]
        self.assertEqual(asked[-2], "Slate's helpers need updating")
        self.assertIn("from your Slate folder", asked[-1])
        self.assertIn("You'll be asked for your password", asked[-1])
        self.assertEqual(calls, [[os.path.join(self.top, "bin", "slate-helpers-install"), self.top]])


class PeopleLooks(Case):
    """slate-greeter-install makes the login screen's people/ folder, where each person's own
    Slate keeps their look: root's, sticky and open to all (as /tmp), so anyone can add their own
    folder and nobody can touch anyone else's. On a full install and on a code-only update (how
    an existing login screen gets it)."""
    def test_made_on_both_routes(self):
        src = slate.read("shell", "bin", "slate-greeter-install")
        line = 'install -d -m 1777 -o root -g root "$DATA/people"'
        self.assertEqual(src.count(line), 2, "people/ isn't made, or not as root's sticky folder")
        code_only = src.index('if [ "$MODE" = code ]; then')
        self.assertLess(src.index(line), code_only, "a code-only update stops before making people/")
