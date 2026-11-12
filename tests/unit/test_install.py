"""install.sh --help: prints the usage from the comments at the top and exits, before any
check or change (it must be safe to run anywhere, even without sudo)."""
import os

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
                self.assertEqual(lines[-1], "Your current desktop and ~/.config/hypr are not changed: pick \"Slate\" at login to use it.")
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
        self.assertIn('sudo "$DEST/bin/slate-greeter-install"', step)

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
