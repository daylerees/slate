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
                    self.assertRegex(src, r"\n\s+%s\) " % fam, f"{fam} isn't recognized")
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
    LINE = [l for l in SRC.splitlines() if '"$SLATE/bin/slate" restart' in l]

    def restarted(self, listing):
        # Slate's own command, standing in: says where it lives, and notes what it's asked
        script(os.path.join(self.dest, "bin", "slate"),
               f'echo "$1" >> {shlex.quote(self.log)}\nif [ "$1" = dir ]; then echo {shlex.quote(self.dest)}; fi\n')
        self.s.add("pgrep", code=0)                      # "a qs is running"
        self.s.add("qs", by_args={"list": listing})
        env = dict(self.s.env, WAYLAND_DISPLAY="wayland-9")
        code, out = bash(self.LINE[0] + "\necho CARRIED-ON\n", env, DEST=self.dest, CODE=self.dest, SLATE=self.dest)
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
        self.state = os.path.join(self.h.dir, "state", "slate")
        code, out = bash(piece + "\necho CARRIED-ON\n", self.s.env, answers=answers, DEST=self.dest, SLATE=self.dest,
                         STATE_DIR=self.state, **vars)
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        return out

    def test_asks_first(self):
        out = self.step(answers=["n"])
        self.assertIn("Use Papirus-Dark icons?", out)
        self.assertIn("Folder color", out)
        self.assertIn("your other desktops", out)
        self.assertEqual(self.ran(), [], "the icon theme was changed after a no")
        self.assertIn("keeping yours (Adwaita)", out)

    def test_yes_sets_it(self):
        self.step(answers=[""])
        self.assertEqual(self.ran(), ["--icon-theme Papirus-Dark"])

    def previous(self):
        try:
            with open(os.path.join(self.state, "previous-icon-theme")) as f:
                return f.read()
        except FileNotFoundError:
            return None

    def test_yes_keeps_what_it_replaced_so_uninstall_can_put_it_back(self):
        self.step(current="Adwaita", answers=[""])
        self.assertEqual(self.previous(), "Adwaita\n")
        self.assertEqual(os.stat(self.state).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(os.path.join(self.state, "previous-icon-theme")).st_mode & 0o777, 0o600)

    def test_no_keeps_nothing(self):
        self.step(answers=["n"])
        self.assertIsNone(self.previous())

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


class TooOldRelease(Pieces):
    """A release the installer calls too old: "Try anyway?" is asked when installing, and the
    answer is kept so --update (which can't ask) doesn't fail every time."""

    def step(self, answers=None, **vars):
        self.state = os.path.join(self.h.dir, "state", "slate")
        piece = between("# Releases too old for Slate's", "\n# --update: this version may need")
        vars = dict(dict(VERSION_ID="40"), **vars)
        return bash(piece + "\necho CARRIED-ON\n", self.s.env, answers=answers, ID="fedora",
                    STATE_DIR=self.state, **vars)

    def kept(self):
        return os.path.exists(os.path.join(self.state, "try-anyway"))

    def test_yes_when_installing_is_kept(self):
        code, out = self.step(answers=[""])
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)
        self.assertTrue(self.kept())
        self.assertEqual(os.stat(self.state).st_mode & 0o777, 0o700)

    def test_update_honours_it(self):
        self.step(answers=[""])
        code, out = self.step(UPDATE=1)
        self.assertEqual(code, 0, out)
        self.assertIn("CARRIED-ON", out)

    def test_update_without_it_still_stops(self):
        code, out = self.step(UPDATE=1)
        self.assertEqual(code, 1, out)
        self.assertNotIn("CARRIED-ON", out)
        self.assertFalse(self.kept())

    def test_no_when_installing_stops_and_keeps_nothing(self):
        code, out = self.step(answers=["n"])
        self.assertEqual(code, 1, out)
        self.assertFalse(self.kept())

    def test_a_release_that_isnt_too_old_keeps_nothing(self):
        code, out = self.step(answers=[], VERSION_ID="44")
        self.assertEqual(code, 0, out)
        self.assertFalse(self.kept())


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
        # which then runs the session's installer from its root-owned place, taking the two
        # session files from that release too: the copy for everyone is root's, not yours)
        self.assertIn("/usr/local/libexec/slate", out)
        self.assertEqual(self.s.calls("sudo"), [[os.path.join(self.release, "shell", "bin", "slate-helpers-install"),
                                                 os.path.join(self.release, "shell"), "slate-session-install",
                                                 os.path.join(self.release, "shell")]])

    def test_no_login_screen_on_nixos(self):
        self.s.add("sudo", code=0)
        code, out = bash(between("# ---- 6. ", "\necho\n"), self.s.env, DEST=self.dest, YES=1, LOGIN=1, family="nixos")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("sudo"), [])
        self.assertIn("services.greetd", out)


class InstallPlaces(Pieces):
    """Step 4: Slate's code goes in $CODE, once for everyone (root's, with sudo; or in place
    without sudo when that folder is yours on purpose), and ~/.config/slate keeps only your files,
    an older copy of your own moved aside whole."""
    PIECES = function("stage_code") + function("place_code") + function("your_folder") + "KEEP=(settings.json hypr user)\n"

    def setUp(self):
        super().setUp()
        # sudo as a stand-in: it notes the command and runs it as you (chown to root can't be
        # done in a test, so that's only noted)
        self.sudo_log = os.path.join(self.h.dir, "sudo")
        script(os.path.join(self.s.dir, "sudo"),
               f'echo "$*" >> "{self.sudo_log}"\ncase "$1" in chown) exit 0 ;; esac\nexec "$@"\n')
        # A checkout of Slate with what a --link'ed one gathers: your files, caches, backups
        self.root = os.path.join(self.h.dir, "checkout")
        shell = os.path.join(self.root, "shell")
        for rel, text in {"shell.qml": "Scope {}\n", "bin/slate": "#!/bin/sh\n", "scripts/a.py": "#\n",
                          "session/slate-session": "#!/bin/sh\n", "session/hypr/hyprland.lua": "--\n",
                          "settings.json": "{}", "hypr/binds.lua": "-- mine\n", "user/shell.qml": "mine\n",
                          "Bar.qml.bak-old": "old\n", "scripts/__pycache__/a.pyc": "x"}.items():
            os.makedirs(os.path.dirname(os.path.join(shell, rel)), exist_ok=True)
            with open(os.path.join(shell, rel), "w") as f:
                f.write(text)
        os.makedirs(os.path.join(self.root, "packaging"))
        with open(os.path.join(self.root, "packaging", "arch.txt"), "w") as f:
            f.write("hyprland\n")
        self.code = os.path.join(self.h.dir, "usr-local-share", "slate")
        os.makedirs(os.path.dirname(self.code))
        self.dest = self.h.slate_home

    def piece(self, body, **more):
        code, out = bash(self.PIECES + body, self.s.env, ROOT=self.root, CODE=self.code, DEST=self.dest, **more)
        self.assertEqual(code, 0, out)
        return out

    def sudo(self):
        try:
            with open(self.sudo_log) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def install(self):
        return self.piece('t=$(mktemp -d); stage_code "$t/slate"; place_code "$t/slate"; rm -rf "$t"; your_folder\n')

    def test_for_everyone_with_sudo(self):
        self.install()
        self.assertTrue(os.path.isfile(os.path.join(self.code, "shell.qml")))
        self.assertTrue(os.path.isfile(os.path.join(self.code, ".manifest")))
        self.assertTrue(os.path.isfile(os.path.join(self.code, "packaging", "arch.txt")))
        self.assertTrue(os.access(os.path.join(self.code, "bin", "slate"), os.X_OK))
        for mine in ("settings.json", "hypr", "user", "Bar.qml.bak-old", "scripts/__pycache__"):
            self.assertFalse(os.path.exists(os.path.join(self.code, mine)), f"{mine} went into the copy for everyone")
        said = self.sudo()
        self.assertTrue(any(l.startswith("chown -R root:root") for l in said), said)
        self.assertTrue(any(l.startswith("chmod -R u+rwX,go+rX,go-w") for l in said), said)
        with self.subTest("again: the one before is kept"):
            # (root's, as it really is: not one you can write to, so sudo again)
            os.chmod(self.code, 0o555)
            self.addCleanup(lambda: os.path.isdir(self.code + ".previous") and os.chmod(self.code + ".previous", 0o755))
            self.install()
            self.assertTrue(os.path.isfile(os.path.join(self.code + ".previous", "shell.qml")))

    def test_a_folder_of_yours_is_changed_without_sudo(self):
        os.makedirs(self.code)
        with open(os.path.join(self.code, "gone.qml"), "w") as f:
            f.write("from before\n")
        out = self.install()
        self.assertIn("no password", out)
        self.assertEqual(self.sudo(), [])
        self.assertTrue(os.path.isfile(os.path.join(self.code, "shell.qml")))
        self.assertFalse(os.path.exists(os.path.join(self.code, "gone.qml")), "a file of the old version was left")
        self.assertFalse(os.path.exists(self.code + ".previous"))

    def test_your_own_copy_from_before_is_moved_aside(self):
        os.makedirs(os.path.join(self.dest, "hypr"))
        os.makedirs(os.path.join(self.dest, "user"))
        for rel, text in {"shell.qml": "old code", "settings.json": '{"accent": "#123456"}',
                          "hypr/binds.lua": "-- my keys", "user/shell.qml": "my qml", "Bar.qml.bak-x": "old"}.items():
            with open(os.path.join(self.dest, rel), "w") as f:
                f.write(text)
        os.makedirs(self.code)
        self.install()
        self.assertEqual(sorted(os.listdir(self.dest)), ["hypr", "settings.json", "user"])
        with open(os.path.join(self.dest, "settings.json")) as f:
            self.assertEqual(f.read(), '{"accent": "#123456"}')
        with open(os.path.join(self.dest, "hypr", "binds.lua")) as f:
            self.assertEqual(f.read(), "-- my keys")
        kept = self.dest + ".before-shared"
        self.assertEqual(sorted(os.listdir(kept)), ["Bar.qml.bak-x", "hypr", "settings.json", "shell.qml", "user"])
        with self.subTest("a second time: nothing more is moved"):
            self.install()
            self.assertEqual(sorted(os.listdir(self.dest)), ["hypr", "settings.json", "user"])
            self.assertFalse([d for d in os.listdir(self.h.config) if d.startswith("slate.before-shared-")])

    def test_a_link_to_a_checkout_becomes_your_folder(self):
        os.makedirs(self.code)
        os.makedirs(self.h.config, exist_ok=True)
        os.rmdir(self.dest) if os.path.isdir(self.dest) and not os.listdir(self.dest) else None
        os.symlink(os.path.join(self.root, "shell"), self.dest)
        self.install()
        self.assertFalse(os.path.islink(self.dest))
        self.assertEqual(sorted(os.listdir(self.dest)), ["hypr", "settings.json", "user"])
        self.assertTrue(os.path.isfile(os.path.join(self.root, "shell", "settings.json")), "the checkout's own was taken")

    def test_where_slate_runs_from(self):
        os.makedirs(self.code)
        out = self.piece('echo "IN_USE=$(code_in_use)"\n')
        self.assertIn("IN_USE=" + self.code, out)
        os.makedirs(os.path.join(self.dest, "session", "hypr"))
        with open(os.path.join(self.dest, "session", "hypr", "hyprland.lua"), "w") as f:
            f.write("--")
        self.assertIn("IN_USE=" + self.dest, self.piece('echo "IN_USE=$(code_in_use)"\n'))

    def test_an_update_from_settings_never_asks_for_a_password(self):
        """Settings → Updates can't give one: a copy for everyone that's root's stops with
        code 3 (install in full), and nothing is changed."""
        body = between("    # (an update from Settings has no password to give", "    code_is_yours || [") + "    echo carried-on\n"
        code, out = bash("if true; then\n" + body + "fi\n", self.s.env, CODE="/usr", DEST=self.dest, UPDATE=1)
        self.assertEqual(code, 3, out)
        self.assertNotIn("carried-on", out)
        self.assertEqual(self.sudo(), [])
        os.makedirs(self.code)
        code, out = bash("if true; then\n" + body + "fi\n", self.s.env, CODE=self.code, DEST=self.dest, UPDATE=1)
        self.assertEqual((code, "carried-on" in out), (0, True), out)


class Uninstall(Case):
    """--uninstall in a scratch home, with sudo and everything else stood in for: it says what
    it leaves and how to remove each, and only deletes the older copy when told to."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("sudo", code=0)
        self.s.add("qs", code=0)
        # A copy for everyone of its own, never the real one
        self.code = os.path.join(self.h.dir, "usr-local-share", "slate")
        os.makedirs(self.code)
        with open(os.path.join(self.code, "shell.qml"), "w") as f:
            f.write("Scope {}\n")
        self.s.env.update(SLATE_TEST="1", SLATE_TEST_CODE=self.code)
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

    def keep_previous(self, theme):
        state = os.path.join(self.s.env["XDG_STATE_HOME"], "slate")
        os.makedirs(state)
        with open(os.path.join(state, "previous-icon-theme"), "w") as f:
            f.write(theme + "\n")
        return state

    def test_puts_the_icon_theme_back(self):
        state = self.keep_previous("Adwaita")
        out, _ = self.uninstall()
        self.assertIn(["set", "org.gnome.desktop.interface", "icon-theme", "Adwaita"], self.s.calls("gsettings"))
        self.assertIn("Icon theme back to Adwaita", out)
        self.assertFalse(os.path.exists(os.path.join(state, "previous-icon-theme")))

    def test_a_theme_you_picked_since_is_left_alone(self):
        self.keep_previous("Adwaita")
        self.uninstall(icon_theme="Tela")
        self.assertFalse([c for c in self.s.calls("gsettings") if c[0] in ("set", "reset")])

    def test_no_theme_before_resets_it(self):
        self.keep_previous("")
        self.uninstall()
        self.assertIn(["reset", "org.gnome.desktop.interface", "icon-theme"], self.s.calls("gsettings"))

    def test_lists_the_copy_for_everyone_and_keeps_it_unasked(self):
        out, _ = self.uninstall()
        self.assertIn(f"sudo rm -r {self.code} {self.code}.previous", out.split("These were left as they are:", 1)[1])
        self.assertTrue(os.path.isfile(os.path.join(self.code, "shell.qml")))

    def test_a_folder_that_isnt_slate_is_never_offered(self):
        os.remove(os.path.join(self.code, "shell.qml"))
        out, _ = self.uninstall("--yes")
        self.assertTrue(os.path.isdir(self.code))
        self.assertNotIn(self.code, out)

    def test_yes_deletes_the_older_copies_only(self):
        out, moved = self.uninstall("--yes", icon_theme="Adwaita")
        self.assertFalse(os.path.exists(self.dest + ".previous"))
        self.assertFalse(os.path.exists(self.code), "the copy for everyone was asked about, and told yes")
        left = out.split("These were left as they are:", 1)[1]
        self.assertNotIn(".previous", left)
        self.assertNotIn("icon theme", left)
        self.assertTrue(os.path.isdir(self.fonts), "the fonts may be yours: they're listed, not deleted")
        self.assertIn(f"rm -r {self.fonts}", left)


class SessionStarter(Case):
    """session/slate-session (what the login screen's "Slate" entry runs) starts Hyprland with
    the config in your own install if you have one (~/.config/slate, or a link from it to a
    checkout), else the copy installed once for everyone, and tells it where that is
    (SLATE_DIR). There was never a release that lived in ~/.config/quickshell/slate, so that
    isn't tried."""
    scratch = True
    STARTER = slate.path("shell", "session", "slate-session")

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("start-hyprland", code=0)
        self.s.add("uwsm", missing=True)
        # (a session bus "already there", so it's started directly on any computer; and the
        # copies for everyone looked for in a scratch folder, never this computer's own)
        self.env = dict(self.s.env, DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent",
                        SLATE_TEST="1", SLATE_TEST_SHARED=os.path.join(self.h.dir, "no-copy-for-everyone"))

    def config_in(self, *folder):
        d = os.path.join(self.h.config, *folder, "session", "hypr")
        os.makedirs(d)
        with open(os.path.join(d, "hyprland.lua"), "w") as f:
            f.write("-- a stand-in\n")
        return os.path.join(d, "hyprland.lua")

    def test_starts_from_your_install(self):
        conf = self.config_in("slate")
        code, out = run(["sh", self.STARTER], env=self.env, timeout=20)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("start-hyprland"), [["--", "-c", conf]])

    def shared_copy(self, name):
        """A copy for everyone, at a scratch path the starter is told to look in (as it looks
        in /usr/local/share/slate and /usr/share/slate)."""
        d = os.path.join(self.h.dir, name, "slate", "session", "hypr")
        os.makedirs(d)
        with open(os.path.join(d, "hyprland.lua"), "w") as f:
            f.write("-- a stand-in\n")
        return os.path.join(self.h.dir, name, "slate")

    def started_with(self, env):
        """Runs the starter; the config it gave Hyprland and the SLATE_DIR it set."""
        self.s.add("start-hyprland", stdin_to=None)
        probe = os.path.join(self.h.dir, "said")
        with open(os.path.join(self.s.dir, "start-hyprland"), "w") as f:
            f.write('#!/bin/sh\nprintf "%%s\\n%%s\\n" "$3" "$SLATE_DIR" > "%s"\n' % probe)
        code, out = run(["sh", self.STARTER], env=env, timeout=20)
        self.assertEqual(code, 0, out)
        with open(probe) as f:
            return f.read().splitlines()

    def test_the_copy_for_everyone(self):
        local = self.shared_copy("usr-local")
        other = self.shared_copy("usr")
        env = dict(self.env, SLATE_TEST="1", SLATE_TEST_SHARED=f"{local} {other}")
        self.assertEqual(self.started_with(env), [os.path.join(local, "session", "hypr", "hyprland.lua"), local])

    def test_your_own_install_comes_first(self):
        """A copy of your own (your development link) wins over the one for everyone."""
        mine = self.config_in("slate")
        local = self.shared_copy("usr-local")
        env = dict(self.env, SLATE_TEST="1", SLATE_TEST_SHARED=local)
        self.assertEqual(self.started_with(env), [mine, os.path.dirname(os.path.dirname(os.path.dirname(mine)))])

    def test_the_tests_paths_only_under_the_tests(self):
        local = self.shared_copy("usr-local")
        env = dict(self.env, SLATE_TEST_SHARED=local)
        env.pop("SLATE_TEST")
        run(["sh", self.STARTER], env=env, timeout=20)
        # (this computer's own copy may be there and be started: never the one the variable named)
        self.assertFalse([c for c in self.s.calls("start-hyprland") if any(local in a for a in c)])

    def test_nowhere_else(self):
        self.config_in("quickshell", "slate")
        code, out = run(["sh", self.STARTER], env=self.env, timeout=20)
        self.assertEqual(code, 1, out)
        self.assertIn("Slate isn't installed", out)
        self.assertEqual(self.s.calls("start-hyprland"), [])
        for rel in (("install.sh",), ("shell", "session", "slate-session")):
            with self.subTest(rel[-1]):
                self.assertNotIn("quickshell/slate", slate.read(*rel))
