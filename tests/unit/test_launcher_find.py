"""The launcher's folder search (the `find` in shell/Launcher.qml): folders in your home by
name, up to three deep, not hidden ones. It used to leave hidden folders out of what it printed
but still walk through them (~/.cache, ~/.local/share) on every search; now it doesn't go in.
What it finds is the same, in the same order, checked here against the command it replaced."""
import os
import re
import subprocess
import tempfile
import unittest

import slate
from slate import Case

# The command as it was, walking everything and leaving hidden paths out afterwards
OLD = 'find "$HOME" -mindepth 1 -maxdepth 3 -type d -not -path "*/.*" -iname "*$1*" 2>/dev/null | head -n 4'

FOLDERS = [
    "Projects", "Projects/project-notes", "Projects/Old/PROJECT-archive",
    "Projects/Old/deep/project-too-deep",            # four deep: past where it looks
    "Documents/.project-hidden",                     # hidden, inside a visible one
    "Documents/.git/project-in-git",                 # visible, inside a hidden one inside a visible one
    ".cache/project-cache", ".local/share/project-data",      # visible, inside hidden ones
    ".project-dot",                                  # hidden, at the top
    "Music/my projects", "Pictures", "a/b/project-three-deep",
]
FILES = ["project-file.txt", "Projects/project.md", ".cache/project-file"]


def command():
    """The command the launcher runs, from its QML."""
    found = re.findall(r"""\["sh", "-c", '(find "\$HOME"[^']*)', "sh", q\]""", slate.read("shell", "Launcher.qml"))
    assert len(found) == 1, f"expected one folder search in Launcher.qml, found {len(found)}"
    return found[0]


def tree(home):
    for d in FOLDERS:
        os.makedirs(os.path.join(home, d))
    for f in FILES:
        open(os.path.join(home, f), "w").close()


def run(cmd, home, query):
    r = subprocess.run(["sh", "-c", cmd, "sh", query], env={"HOME": home, "PATH": os.environ["PATH"]},
                       capture_output=True, text=True, timeout=30)
    return [os.path.relpath(l, home) for l in r.stdout.split("\n") if l], r.stderr


def whole(cmd):
    """The command without its limit of four, to compare everything it would find."""
    assert cmd.endswith(" | head -n 4"), cmd
    return cmd[:-len(" | head -n 4")]


class LauncherFind(Case):
    def setUp(self):
        super().setUp()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def home(self, *parts):
        home = os.path.join(self.tmp.name, *parts)
        tree(home)
        return home

    def test_finds_what_it_did_in_the_same_order(self):
        home = self.home("home", "someone")
        new = command()
        for query in ("project", "PROJ", "pictures", "my proj", "o", "nothing-like-this"):
            with self.subTest(query):
                self.assertEqual(run(new, home, query), run(OLD, home, query))
                self.assertEqual(run(whole(new), home, query), run(whole(OLD), home, query))
        # (and that is: the visible ones, three deep at most, whatever their case, folders only)
        self.assertEqual(sorted(run(whole(new), home, "project")[0]),
                         ["Music/my projects", "Projects", "Projects/Old/PROJECT-archive", "Projects/project-notes",
                          "a/b/project-three-deep"])
        self.assertEqual(len(run(new, home, "project")[0]), 4)

    def test_a_home_under_a_hidden_folder(self):
        """Hidden means hidden within your home. With the home folder itself somewhere under a
        dot-folder (/srv/.homes/someone), the old command found nothing at all, as every path
        had a hidden part; now the same folders are found there as anywhere else."""
        plain, dotted = self.home("home", "someone"), self.home(".homes", "someone")
        self.assertEqual(run(whole(OLD), dotted, "project")[0], [])
        new = whole(command())
        self.assertEqual(sorted(run(new, dotted, "project")[0]), sorted(run(new, plain, "project")[0]))
        # (a home that's a dot-folder itself, too)
        self.assertEqual(sorted(run(new, self.home("home", ".someone"), "project")[0]), sorted(run(new, plain, "project")[0]))

    @unittest.skipIf(os.geteuid() == 0, "root can read a folder nobody is allowed to")
    def test_hidden_folders_are_not_walked(self):
        """A hidden folder nobody may read: going into it is refused, which find says. Not
        going in, there's nothing to say."""
        home = self.home("home", "someone")
        locked = os.path.join(home, ".locked")
        os.makedirs(os.path.join(locked, "inside"))
        os.chmod(locked, 0)
        self.addCleanup(os.chmod, locked, 0o700)
        cmd = command()
        self.assertIn(" 2>/dev/null", cmd)
        found, said = run(whole(cmd).replace(" 2>/dev/null", ""), home, "project")
        self.assertEqual(said, "", "the folder search went into a hidden folder")
        self.assertEqual(len(found), 5)
