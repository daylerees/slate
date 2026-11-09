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
