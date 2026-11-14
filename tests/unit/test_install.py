"""install.sh --help: prints the usage from the comments at the top and exits, before any
check or change (it must be safe to run anywhere, even without sudo)."""
import fcntl
import os
import pty
import shlex
import subprocess
import termios

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("install.sh")
OPTIONS = ["--yes", "--login-screen", "--no-deps", "--link", "--update", "--uninstall"]


def tree(top):
    """Every path under `top`, with its size and modification time."""
    out = {}
    for d, dirs, names in os.walk(top):
        for n in dirs + names:
            p = os.path.join(d, n)
            st = os.lstat(p)
            out[os.path.relpath(p, top)] = (st.st_size, st.st_mtime_ns)
    return out


class Help(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.before = tree(self.h.home)

    def untouched(self):
        self.assertEqual(tree(self.h.home), self.before, "the scratch home changed")
        for cmd in ("sudo", "pkexec", "systemctl", "qs", "hyprctl"):
            self.assertEqual(self.s.calls(cmd), [], f"{cmd} was run")

    def test_help(self):
        for flag in ("--help", "-h"):
            with self.subTest(flag):
                code, out = run(["bash", SCRIPT, flag], env=self.s.env)
                self.assertEqual(code, 0, out)
                lines = out.splitlines()
                self.assertEqual(lines[0], "Slate installer. Run from the Slate folder as your normal user (it asks for sudo when")
                for opt in OPTIONS + ["./install.sh "]:
                    self.assertIn(opt, out)
                self.assertIn("What it does:", out)
                # Just the comments, without their "#", and nothing past them
                self.assertFalse([l for l in lines if l.startswith("#")], "comment marks left in")
                self.assertNotIn("set -euo", out)
                self.assertNotIn("ROOT=", out)
                self.assertEqual(lines[-1], "and ~/.config/hypr is not changed: pick \"Slate\" at login to use it.")
                self.untouched()

    def test_help_with_other_options(self):
        """--help after other options still only prints the usage."""
        code, out = run(["bash", SCRIPT, "--yes", "--no-deps", "--help"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("Slate installer."))
        self.untouched()

    def test_help_without_sudo(self):
        self.s.add("sudo", missing=True)
        code, out = run(["bash", SCRIPT, "--help"], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.assertTrue(out.startswith("Slate installer."))
        self.untouched()

    def test_unknown_option(self):
        code, out = run(["bash", SCRIPT, "--frobnicate"], env=self.s.env)
        self.assertEqual(code, 1)
        self.assertEqual(out, "Unknown option: --frobnicate (see ./install.sh --help)\n")
        self.untouched()

    def test_options_documented(self):
        """Every option the script accepts is in its usage."""
        src = slate.read("install.sh")
        handled = src.split('for a in "$@"; do')[1].split("done")[0]
        code, out = run(["bash", SCRIPT, "--help"], env=self.s.env)
        for opt in OPTIONS:
            with self.subTest(opt):
                self.assertIn(opt + ")", handled.replace("|", ")"))
                self.assertIn("./install.sh " + opt, out)


class LoginScreenOptIn(Case):
    """Slate's login screen replaces the system's, so installing Slate never sets it up unless
    asked: only --login-screen (not --yes, not --update) reaches slate-greeter-install."""

    def test_only_with_login_screen(self):
        src = slate.read("install.sh")
        self.assertIn("LOGIN=0", src.split('for a in "$@"; do')[0], "LOGIN must start off")
        handled = src.split('for a in "$@"; do')[1].split("done")[0]
        sets = [l.strip() for l in handled.splitlines() if "LOGIN=1" in l]
        self.assertEqual(sets, ["--login-screen) LOGIN=1 ;;"])
        # Every line that installs it sits inside the --login-screen step
        step = src.split('if [ "$LOGIN" -eq 1 ]; then', 1)[1].split("\nfi\n", 1)[0]
        outside = src.replace(step, "")
        runs = [l for l in outside.splitlines()
                if "slate-greeter-install" in l and not l.lstrip().startswith("#")
                and "echo" not in l and "warn" not in l]
        self.assertEqual(runs, [], "slate-greeter-install run outside the --login-screen step")
        # (through the helpers' installer, from this release: the root-owned copy is what runs)
        self.assertIn('sudo "$ROOT/shell/bin/slate-helpers-install" "$ROOT/shell" slate-greeter-install', step)

    def test_risks_explained_before_asking(self):
        """The step says what can go wrong and what keeping it working takes, before it asks."""
        step = slate.read("install.sh").split('if [ "$LOGIN" -eq 1 ]; then', 1)[1].split("\nfi\n", 1)[0]
        before = step.split('if ask "Switch the login screen', 1)[0]
        for words in ("stop you logging in", "Ctrl+Alt+F3", "--revert", "updated", "password"):
            with self.subTest(words):
                self.assertIn(words, before)


class WithoutSystemd(Case):
    """Artix, Void and Gentoo (docs/INSTALL.md, Without systemd): each has its own package
    list, the installer and bin/slate-system know them, and nothing switches services on
    with systemctl where systemd isn't running."""

    def test_families(self):
        for rel in ("install.sh", "shell/bin/slate-system"):
            src = slate.read(*rel.split("/"))
            with self.subTest(rel):
                for fam in ("artix", "void", "gentoo"):
                    self.assertRegex(src, r"\n\s+%s\) " % fam, f"{fam} isn't recognised")
                # Artix's ID_LIKE is arch: it has to be matched first
                self.assertLess(src.index("artix)"), src.index("arch|cachyos"), "artix would be taken for Arch")

    def test_lists(self):
        def names(fam):
            return {l.split("#")[0].strip().lstrip("?") for l in slate.read("packaging", fam + ".txt").splitlines()} - {""}
        arch, artix = names("arch"), names("artix")
        self.assertEqual(arch - artix, {"systemd", "uwsm"}, "Artix's list should be Arch's without systemd's own parts")
        self.assertEqual(artix - arch, {"elogind"})
        for fam, elogind in (("void", "elogind"), ("gentoo", "sys-auth/elogind")):
            with self.subTest(fam):
                self.assertIn(elogind, names(fam))
                self.assertFalse({n for n in names(fam) if "systemd" in n or "uwsm" in n})

    def test_gentoo_is_listed_not_installed(self):
        src = slate.read("install.sh")
        branch = src.split("        gentoo)\n", 1)[1].split(";;", 1)[0]
        self.assertIn("read_list gentoo", branch)
        self.assertNotIn("emerge ", branch.replace("leaves emerge to you", "").replace("Emerge them", ""))
        self.assertNotIn("install_gentoo", src)

    def test_services_not_switched_on_without_systemd(self):
        fn = slate.read("install.sh").split("enable_services() {", 1)[1].split("\n}\n", 1)[0]
        guard, rest = fn.split("have systemctl || return 0", 1)
        self.assertIn("[ ! -d /run/systemd/system ]", guard)
        self.assertIn("service-hint", guard)
        self.assertNotIn("systemctl", guard.replace("/run/systemd/system", ""))


class NoStraySystemdCalls(Case):
    """Everything that needs the init system or the login service goes through bin/slate-init
    (or says why it's an exception here), so a computer without systemd isn't left with a
    button that does nothing."""
    ALLOWED = {
        "shell/bin/slate-init": "the one place that knows",
        "shell/bin/slate-logs": "journalctl only where it exists",
        "shell/bin/slate-greeter-install": "systemd-cat only where systemd runs",
        "shell/scripts/printers.py": "systemctl only where it exists (CUPS itself is asked otherwise)",
        "shell/scripts/session-services.sh": "tells systemd the environment only where it runs",
        "shell/scripts/private-capture.sh": "masks the portal's service only where systemd runs (stops it by hand otherwise, `keep`)",
        "shell/greeter/shell.qml": "the login screen runs from a root-owned copy without slate-init: the same choice inline",
        "shell/greeter/emergency/shell.qml": "as the login screen",
        "shell/session/slate-session": "uwsm only where systemd runs",
    }

    def test_none(self):
        import re
        pat = re.compile(r"\b(systemctl|systemd-inhibit|systemd-cat|timedatectl|journalctl|busctl|hostnamectl|localectl)\b")
        found = {}
        for f in slate.files("shell", ".qml", ".py", ".sh", ".lua") + ["shell/bin/" + n for n in os.listdir(slate.path("shell", "bin"))] + ["shell/session/slate-session"]:
            if f in self.ALLOWED:
                continue
            for n, line in enumerate(slate.read(*f.split("/")).splitlines(), 1):
                code = line.split("//")[0] if f.endswith(".qml") else line.split("--")[0] if f.endswith(".lua") else line.split("#")[0]
                if pat.search(code):
                    found.setdefault(f, []).append(n)
        self.assertEqual(found, {}, f"direct systemd calls outside bin/slate-init: {found}")


# ---- Pieces of install.sh, run by themselves -------------------------------------------
# install.sh does its work as it's read, so it can't be sourced for its functions: the tests
# cut out the piece they're about (by the words around it) and run that under the same
# `set -euo pipefail`, with stand-ins for everything it would reach.
SRC = slate.read("install.sh")
HELPERS = "# ---- Output helpers" + SRC.split("# ---- Output helpers", 1)[1].split('\n[ "$(id -u)" -ne 0 ]', 1)[0]


def between(start, end):
    """install.sh from `start` up to (not including) `end`."""
    return start + SRC.split(start, 1)[1].split(end, 1)[0]


def function(name):
    return between(name + "() {", "\n}\n") + "\n}\n"


def bash(body, env, answers=None, **vars):
    """Run a piece of install.sh; returns (exit code, output). With no `answers` there's no
    terminal at all (as from a script or Settings → Updates); with them, they're typed at a
    terminal of its own, a line per question."""
    head = "set -euo pipefail\nYES=0; UPDATE=0; family=arch\n" + "".join(f"{k}={shlex.quote(str(v))}\n" for k, v in vars.items())
    cmd = ["bash", "-c", head + HELPERS + "\n" + body]
    if answers is None:
        # (a session of its own has no terminal: opening /dev/tty fails)
        p = subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=60, start_new_session=True)
        return p.returncode, p.stdout
    master, slave = pty.openpty()

    def own_terminal():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    try:
        os.write(master, "".join(a + "\n" for a in answers).encode())
        p = subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=60, preexec_fn=own_terminal, pass_fds=(slave,))
        return p.returncode, p.stdout
    finally:
        os.close(master)
        os.close(slave)


def script(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("#!/bin/sh\n" + text)
    os.chmod(path, 0o755)
    return path


class Pieces(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.dest = os.path.join(self.h.dir, "slate")
        self.log = os.path.join(self.h.dir, "ran")

    def ran(self):
        try:
            with open(self.log) as f:
                return f.read().split("\n")[:-1]
        except FileNotFoundError:
            return []


class Asking(Pieces):
    """A question nobody can answer is a no, said out loud: never a silent yes to sudo."""
    ASK = 'if ask "Do the thing?"; then echo ANSWER=yes; else echo ANSWER=no; fi\n'

    def test_no_terminal_is_no(self):
        code, out = bash(self.ASK + self.ASK, self.s.env)
        self.assertEqual(code, 0, out)
        self.assertEqual(out.count("ANSWER=no"), 2, out)
        self.assertIn('Skipped "Do the thing?"', out)
        self.assertIn("no terminal", out)
        # (how to get a yes to everything: said once, not with every question)
        self.assertEqual(out.count("--yes answers yes to everything"), 1, out)

    def test_yes_answers_yes_without_a_terminal(self):
        code, out = bash(self.ASK, self.s.env, YES=1)
        self.assertEqual((code, out), (0, "ANSWER=yes\n"))

    def test_update_never_asks(self):
        """--update (Settings → Updates, with no terminal) is a no to every question, --yes or
        not: it never leaned on the silent yes."""
        for yes in (0, 1):
            code, out = bash(self.ASK, self.s.env, UPDATE=1, YES=yes)
            self.assertEqual((code, out), (0, "ANSWER=no\n"))

    def test_at_a_terminal(self):
        for typed, want in (("", "yes"), ("y", "yes"), ("n", "no"), ("No", "no")):
            with self.subTest(typed=typed):
                code, out = bash(self.ASK, self.s.env, answers=[typed])
                self.assertEqual(code, 0, out)
                self.assertIn("ANSWER=" + want, out)
                self.assertNotIn("Skipped", out)

    def test_no_bare_errors(self):
        """Voice: what went wrong and what to do, never "Error:"."""
        self.assertNotIn("Error:", SRC)
        code, out = bash('die "sudo isn\'t installed."\n', self.s.env)
        self.assertEqual((code, out), (1, "Slate's installer couldn't carry on: sudo isn't installed.\n"))


class ServicesWithoutSystemd(Pieces):
    def services(self, slate_init):
        root = os.path.join(self.h.dir, "src")
        script(os.path.join(root, "shell", "bin", "slate-init"), slate_init)
        fn = function("enable_services").replace("/run/systemd/system", os.path.join(self.h.dir, "no-systemd-here"))
        return bash(fn + "enable_services\necho CARRIED-ON\n", self.s.env, ROOT=root)

    def test_carries_on_and_says_what_is_off(self):
        """slate-init answers "not running" with exit code 1: that's the answer, not a failure,
        and the installer has to get past it (it used to end right there, silently, before
        Slate was put in place)."""
        code, out = self.services("""case "$1" in
    service-active) exit 1 ;;
    service-hint) echo "sudo rc-update add $2 default" ;;
    # (the rest comes a moment later, as the real one's does: a reader that leaves early cuts it off)
    info) echo init=openrc; echo logind=none; sleep 0.3; echo suspend=no; echo power=no ;;
esac
""")
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        self.assertIn("The bluetooth service isn't running (Slate's Bluetooth panel needs it). To switch it on: sudo rc-update add bluetooth default", out)
        self.assertIn("The network service isn't running (Slate's Wi-Fi panel needs it)", out)
        self.assertIn("elogind isn't running", out)
        self.assertEqual(self.s.calls("systemctl") + self.s.calls("sudo"), [])

    def test_running_services_say_nothing(self):
        code, out = self.services("""case "$1" in
    service-active) exit 0 ;;
    info) echo init=runit; echo logind=elogind ;;
esac
""")
        self.assertEqual((code, out), (0, "CARRIED-ON\n"))


class RestartOnlySlate(Pieces):
    """After putting Slate in place the installer restarts it, if it's running. `qs` is
    Quickshell, which other shells run on too: one of those running on another desktop isn't
    Slate, and `slate restart` there would start Slate over that desktop."""
    LINE = [l for l in SRC.splitlines() if '"$DEST/bin/slate" restart' in l]

    def restarted(self, listing):
        # Slate's own command, standing in: says where it lives, and notes what it's asked
        script(os.path.join(self.dest, "bin", "slate"),
               f'echo "$1" >> {shlex.quote(self.log)}\nif [ "$1" = dir ]; then echo {shlex.quote(self.dest)}; fi\n')
        self.s.add("pgrep", code=0)                      # "a qs is running"
        self.s.add("qs", by_args={"list": listing})
        env = dict(self.s.env, WAYLAND_DISPLAY="wayland-9")
        code, out = bash(self.LINE[0] + "\necho CARRIED-ON\n", env, DEST=self.dest)
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        return "restart" in self.ran()

    def test_one_line_restarts(self):
        self.assertEqual(len(self.LINE), 1, self.LINE)

    def test_not_for_another_shell(self):
        self.assertFalse(self.restarted(("", 255)), "Slate was restarted (started) though only another Quickshell was running")
        # It asked about Slate's own folder, not for any qs at all
        self.assertIn(["list", "-p", self.dest], self.s.calls("qs"))

    def test_when_slate_runs(self):
        self.assertTrue(self.restarted("Instance abc123:\n  Process ID: 4242\n  Shell ID: 0\n  Config path: x\n"))


class IconTheme(Pieces):
    """The icon theme is shared with every other desktop, so it's a question, not a step."""

    def step(self, current="Adwaita", answers=None, **vars):
        papirus = os.path.join(self.h.dir, "icons", "Papirus-Dark")
        os.makedirs(papirus, exist_ok=True)
        script(os.path.join(self.dest, "scripts", "folder-colour.py"), f'echo "$*" >> {shlex.quote(self.log)}\n')
        self.s.add("gsettings", stdout=f"'{current}'\n")
        piece = between("# Icon theme: Papirus-Dark", '\ncase ":$PATH:"').replace("/usr/share/icons/Papirus-Dark", papirus)
        code, out = bash(piece + "\necho CARRIED-ON\n", self.s.env, answers=answers, DEST=self.dest, **vars)
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        return out

    def test_asks_first(self):
        out = self.step(answers=["n"])
        self.assertIn("Use Papirus-Dark icons?", out)
        self.assertIn("Folder colour", out)
        self.assertIn("your other desktops", out)
        self.assertEqual(self.ran(), [], "the icon theme was changed after a no")
        self.assertIn("keeping yours (Adwaita)", out)

    def test_yes_sets_it(self):
        self.step(answers=[""])
        self.assertEqual(self.ran(), ["--icon-theme Papirus-Dark"])

    def test_dash_dash_yes_sets_it(self):
        self.step(YES=1)
        self.assertEqual(self.ran(), ["--icon-theme Papirus-Dark"])

    def test_skipped_without_a_terminal(self):
        out = self.step()
        self.assertEqual(self.ran(), [], "the icon theme was changed with nobody to ask")
        self.assertIn("no terminal", out)

    def test_your_own_is_never_asked_about(self):
        out = self.step(current="Tela", YES=1)
        self.assertEqual(self.ran(), [])
        self.assertIn("keeping yours (Tela)", out)

    def test_not_on_update(self):
        self.step(UPDATE=1, YES=1)
        self.assertEqual(self.ran(), [])

    def test_usage_says_so(self):
        """The usage no longer promises nothing outside Slate changes: it says what's asked."""
        usage = SRC.split("\nset -euo pipefail", 1)[0]
        self.assertNotIn("Your current desktop and ~/.config/hypr are not changed", usage)
        self.assertIn("icon theme", usage)


class ThirdPartyRepositories(Pieces):
    """A PPA or COPR is somebody else's repository: named in plain words before "Install them
    now?", not added under it unannounced."""

    def said(self, **vars):
        read_list = next(l for l in SRC.splitlines() if l.startswith("read_list() {"))
        body = read_list + "\n" + between('HYPR_PPA="', "\ninstall_debian() {") + "\nthird_party_repos\n"
        code, out = bash(body, self.s.env, ROOT=slate.path(), **vars)
        self.assertEqual(code, 0, out)
        return out

    def test_fedora(self):
        out = self.said(family="fedora")
        self.assertIn("This adds third-party repositories:", out)
        coprs = [l.split("#")[0].strip()[5:] for l in slate.read("packaging", "fedora.txt").splitlines() if l.startswith("copr:")]
        self.assertTrue(coprs)
        for c in coprs:
            self.assertIn(c + " COPR", out)

    def test_ubuntu(self):
        if os.path.isdir("/etc/apt/sources.list.d"):
            self.skipTest("this computer has apt sources of its own")
        out = self.said(family="debian", ID="ubuntu", ID_LIKE="debian")
        self.assertIn("This adds a third-party repository: ppa:cppiber/hyprland", out)
        self.assertEqual(self.said(family="debian", ID="debian", ID_LIKE=""), "")

    def test_none_elsewhere(self):
        self.assertEqual(self.said(family="arch", ID="arch", ID_LIKE=""), "")

    def test_named_before_the_question_and_once(self):
        step = between('if [ "$DEPS" -eq 1 ]; then', "\nfi\n")
        self.assertLess(step.index("third_party_repos"), step.index('ask "Install them now'))
        # (the PPA's name is written once, so what's said and what's added can't drift apart)
        self.assertEqual(SRC.count("ppa:"), 1)
        self.assertIn('add-apt-repository -y "$HYPR_PPA"', SRC)


class NixOS(Pieces):
    """NixOS manages /usr/share and /etc itself (docs/INSTALL.md): the session and the login
    screen go in its configuration, and the installer doesn't offer to write them."""

    def step5(self, **vars):
        self.s.add("sudo", code=0)
        self.release = os.path.join(self.h.dir, "release")
        code, out = bash(between('step "5. ', "# ---- 6. ") + "echo CARRIED-ON\n", self.s.env, DEST=self.dest, YES=1,
                         ROOT=self.release, HELPERS="/usr/local/libexec/slate", **vars)
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        return out

    def test_no_session_files_on_nixos(self):
        out = self.step5(family="nixos")
        self.assertEqual(self.s.calls("sudo"), [])
        self.assertIn("services.displayManager.sessionPackages", out)
        self.assertNotIn("/usr/share/wayland-sessions", out)

    def test_elsewhere_as_before(self):
        out = self.step5(family="fedora")
        self.assertIn("/usr/share/wayland-sessions/slate.desktop", out)
        # (the helpers' installer from the release being installed, never a script in $DEST,
        # which then runs the session's installer from its root-owned place)
        self.assertIn("/usr/local/libexec/slate", out)
        self.assertEqual(self.s.calls("sudo"), [[os.path.join(self.release, "shell", "bin", "slate-helpers-install"),
                                                 os.path.join(self.release, "shell"), "slate-session-install", self.dest]])

    def test_no_login_screen_on_nixos(self):
        self.s.add("sudo", code=0)
        code, out = bash(between("# ---- 6. ", "\necho\n"), self.s.env, DEST=self.dest, YES=1, LOGIN=1, family="nixos")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("sudo"), [])
        self.assertIn("services.greetd", out)


class Uninstall(Case):
    """--uninstall in a scratch home, with sudo and everything else stood in for: it says what
    it leaves and how to remove each, and only deletes the older copy when told to."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("sudo", code=0)
        self.s.add("qs", code=0)
        self.dest = os.path.join(self.h.config, "slate")
        self.fonts = os.path.join(self.s.env["XDG_DATA_HOME"], "fonts", "Geist")
        for d in (self.dest, self.dest + ".previous", self.fonts):
            os.makedirs(d)
        with open(os.path.join(self.dest, "settings.json"), "w") as f:
            f.write("{}\n")

    def uninstall(self, *flags, icon_theme="Papirus-Dark"):
        self.s.add("gsettings", stdout=f"'{icon_theme}'\n")
        p = subprocess.run(["bash", SCRIPT, "--uninstall", *flags], env=self.s.env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60, start_new_session=True)
        self.assertEqual(p.returncode, 0, p.stdout)
        self.assertFalse(os.path.exists(self.dest), "~/.config/slate is still there")
        moved = [n for n in os.listdir(self.h.config) if n.startswith("slate.removed-")]
        self.assertEqual(len(moved), 1, moved)
        self.assertTrue(os.path.isfile(os.path.join(self.h.config, moved[0], "settings.json")), "the settings weren't kept")
        return p.stdout, os.path.join(self.h.config, moved[0])

    def test_lists_what_it_leaves(self):
        out, moved = self.uninstall()
        left = out.split("These were left as they are:", 1)[1]
        for what in (f"rm -r {moved}", f"rm -r {self.dest}.previous", f"rm -r {self.fonts}", "Your icon theme is Papirus-Dark", "packages"):
            with self.subTest(what):
                self.assertIn(what, left)
        # Nobody to ask: the older copy stays, and nothing else was deleted either
        self.assertIn("no terminal", out)
        self.assertTrue(os.path.isdir(self.dest + ".previous"))
        self.assertTrue(os.path.isdir(self.fonts))

    def test_yes_deletes_the_older_copy_only(self):
        out, moved = self.uninstall("--yes", icon_theme="Adwaita")
        self.assertFalse(os.path.exists(self.dest + ".previous"))
        left = out.split("These were left as they are:", 1)[1]
        self.assertNotIn(".previous", left)
        self.assertNotIn("icon theme", left)
        self.assertTrue(os.path.isdir(self.fonts), "the fonts may be yours: they're listed, not deleted")
        self.assertIn(f"rm -r {self.fonts}", left)
