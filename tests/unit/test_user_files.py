"""scripts/user-files.sh: the files for your own tweaks (hypr/*.lua, user/shell.qml) are made
in Slate's folder from data/user-files, and one that's already there is never touched."""
import os

import slate
from slate import Case, run

SRC = slate.path("shell", "data", "user-files")


def templates():
    """Each template, as a path relative to data/user-files, sorted."""
    out = []
    for d, _, names in os.walk(SRC):
        out += [os.path.relpath(os.path.join(d, n), SRC) for n in names]
    return sorted(out)


def read(p):
    with open(p, "rb") as f:
        return f.read()


class UserFiles(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.slate = self.h.install_slate()
        self.script = os.path.join(self.slate, "scripts", "user-files.sh")

    def make(self, *args):
        code, out = run(["sh", self.script, *args], env=self.h.env)
        self.assertEqual(code, 0, out)
        return out

    def created(self, out):
        return sorted(os.path.relpath(l.removeprefix("created "), self.slate) for l in out.splitlines())

    def test_templates(self):
        """The ones the docs and Hyprland config expect are all there."""
        self.assertEqual(templates(), ["hypr/autostart.lua", "hypr/binds.lua", "hypr/env.lua", "hypr/hyprland.lua",
                                       "hypr/monitors.lua", "hypr/rules.lua", "hypr/variables.lua", "user/shell.qml"])

    def test_creates_them(self):
        """A fresh install gets a copy of each, and says so, a line per file."""
        out = self.make()
        self.assertEqual(self.created(out), templates())
        for rel in templates():
            with self.subTest(rel):
                self.assertEqual(read(os.path.join(self.slate, rel)), read(os.path.join(SRC, rel)))

    def test_folder_argument(self):
        """The folder can be given (install.sh does); the default is the one the script is in."""
        other = os.path.join(self.h.dir, "elsewhere")
        os.makedirs(os.path.join(other, "data"))
        os.symlink(os.path.join(self.slate, "data", "user-files"), os.path.join(other, "data", "user-files"))
        out = self.make(other)
        self.assertEqual(sorted(os.path.relpath(l.removeprefix("created "), other) for l in out.splitlines()), templates())
        self.assertFalse(os.path.exists(os.path.join(self.slate, "hypr")), "made in the script's folder, not the one given")

    def test_second_run_does_nothing(self):
        self.make()
        stamps = {r: os.stat(os.path.join(self.slate, r)).st_mtime_ns for r in templates()}
        self.assertEqual(self.make(), "")
        self.assertEqual({r: os.stat(os.path.join(self.slate, r)).st_mtime_ns for r in templates()}, stamps)

    def test_never_overwrites(self):
        """Your own edits stay, byte for byte, and only the missing files are made."""
        mine = {"hypr/binds.lua": b"-- my binds\nbind('SUPER, T', 'exec', 'foot')\n",
                "user/shell.qml": b"import QtQuick\nItem { /* mine */ }\n",
                "hypr/env.lua": b""}            # even an empty one is yours
        for rel, text in mine.items():
            p = os.path.join(self.slate, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(text)
            os.chmod(p, 0o600)
        out = self.make()
        self.assertEqual(self.created(out), sorted(set(templates()) - set(mine)))
        for rel, text in mine.items():
            with self.subTest(rel):
                p = os.path.join(self.slate, rel)
                self.assertEqual(read(p), text)
                self.assertEqual(os.stat(p).st_mode & 0o777, 0o600)

    def test_never_follows_your_links(self):
        """A file that's a link (e.g. into your dotfiles) is left alone, even one that points
        nowhere yet: nothing is written through it."""
        dots = os.path.join(self.h.dir, "dotfiles")
        os.makedirs(dots)
        with open(os.path.join(dots, "rules.lua"), "w") as f:
            f.write("-- from my dotfiles\n")
        os.makedirs(os.path.join(self.slate, "hypr"))
        os.symlink(os.path.join(dots, "rules.lua"), os.path.join(self.slate, "hypr", "rules.lua"))
        os.symlink(os.path.join(dots, "binds.lua"), os.path.join(self.slate, "hypr", "binds.lua"))
        out = self.make()
        self.assertNotIn("hypr/rules.lua", out)
        self.assertNotIn("created " + os.path.join(self.slate, "hypr", "binds.lua"), out)
        self.assertEqual(read(os.path.join(dots, "rules.lua")), b"-- from my dotfiles\n")
        self.assertFalse(os.path.exists(os.path.join(dots, "binds.lua")), "wrote through a link to a missing file")
        self.assertTrue(os.path.islink(os.path.join(self.slate, "hypr", "binds.lua")))

    def test_only_its_own_files(self):
        """Nothing outside hypr/ and user/ is added to Slate's folder."""
        before = set(os.listdir(self.slate))
        self.make()
        self.assertEqual(set(os.listdir(self.slate)) - before, {"hypr", "user"})
        self.assertEqual(sorted(os.listdir(self.h.home)), [".cache", ".config", ".local"])

    def test_no_templates(self):
        """A Slate folder without data/user-files (an old copy): nothing to do, no error."""
        bare = os.path.join(self.h.dir, "bare")
        os.makedirs(bare)
        self.assertEqual(self.make(bare), "")
        self.assertEqual(os.listdir(bare), [])
