"""scripts/theme-packs.py: putting in a pointer or icon theme with one click (Settings → Input →
More pointer styles, Appearance → More icon styles). Each test makes a small archive here
and points the script at it (SLATE_THEME_PACKS, file:// links): nothing is downloaded, and
only the scratch home's icons folder is touched."""
import hashlib
import io
import json
import os
import sys
import tarfile

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "theme-packs.py")


class ThemePacks(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.h.env["XDG_DATA_DIRS"] = os.path.join(self.h.dir, "no-system")
        self.icons = os.path.join(self.h.data, "icons")

    def archive(self, name, members):
        """A .tar.gz of members: (path, text) files, (path, "->", target) links."""
        path = os.path.join(self.h.dir, name)
        with tarfile.open(path, "w:gz") as t:
            for m in members:
                info = tarfile.TarInfo(m[0])
                if len(m) == 3:
                    info.type, info.linkname = tarfile.SYMTYPE, m[2]
                    t.addfile(info)
                else:
                    data = m[1].encode()
                    info.size = len(data)
                    t.addfile(info, io.BytesIO(data))
        with open(path, "rb") as fh:
            return "file://" + path, hashlib.sha256(fh.read()).hexdigest()

    def packs(self, packs):
        p = os.path.join(self.h.dir, "packs.json")
        with open(p, "w") as fh:
            json.dump(packs, fh)
        self.h.env["SLATE_THEME_PACKS"] = p

    def go(self, *args):
        return run([sys.executable, SCRIPT] + list(args), env=self.h.env)

    def icon_pack(self, members, sha=None, take=None):
        url, digest = self.archive("pack.tar.gz", members)
        self.packs([{"id": "nice", "kind": "icons", "name": "Nice", "about": "Nice icons",
                     "files": [{"url": url, "sha256": sha or digest,
                                "take": take or {"nice-1.0/Nice": "Nice", "nice-1.0/Nice-Grey": "Nice-Grey"}}]}])

    def test_installs_and_lists(self):
        self.icon_pack([("nice-1.0/Nice/index.theme", "[Icon Theme]\nName=Nice\n"),
                        ("nice-1.0/Nice/apps/a.svg", "<svg/>"),
                        ("nice-1.0/Nice-Grey/index.theme", "[Icon Theme]\nName=Nice Grey\n"),
                        # (a link into the pack's other theme, as Kora Grey's are)
                        ("nice-1.0/Nice-Grey/apps", "->", "../Nice/apps"),
                        ("nice-1.0/README.md", "not a theme: left behind")])
        code, out = self.go("--list")
        self.assertEqual(json.loads(out)[0]["installed"], False)
        code, out = self.go("--install", "nice")
        self.assertEqual(code, 0, out)
        self.assertIn("installed nice", out)
        self.assertEqual(sorted(os.listdir(self.icons)), ["Nice", "Nice-Grey"])
        self.assertTrue(os.path.isfile(os.path.join(self.icons, "Nice-Grey", "apps", "a.svg")))
        self.assertEqual(os.readlink(os.path.join(self.icons, "Nice-Grey", "apps")), "../Nice/apps")
        code, out = self.go("--list")
        self.assertEqual(json.loads(out)[0]["installed"], True)
        # Again: the old copy is replaced, and nothing is left over from the work
        code, out = self.go("--install", "nice")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(os.listdir(self.icons)), ["Nice", "Nice-Grey"])

    def test_wrong_fingerprint(self):
        """A download that isn't the one Slate checked isn't used at all."""
        self.icon_pack([("nice-1.0/Nice/index.theme", "[Icon Theme]\n")], sha="0" * 64,
                       take={"nice-1.0/Nice": "Nice"})
        code, out = self.go("--install", "nice")
        self.assertEqual(code, 1)
        self.assertIn("fingerprint", out)
        self.assertEqual(os.listdir(self.icons), [])

    def test_nothing_lands_outside(self):
        """No file outside its theme, and no link out of the pack's themes."""
        for name, members in (
                ("dotdot", [("nice-1.0/Nice/index.theme", "x"), ("nice-1.0/Nice/../../escape", "x")]),
                ("link-out", [("nice-1.0/Nice/index.theme", "x"), ("nice-1.0/Nice/evil", "->", "../../../../.bashrc")]),
                ("abs-link", [("nice-1.0/Nice/index.theme", "x"), ("nice-1.0/Nice/evil", "->", "/etc/passwd")])):
            with self.subTest(name):
                self.icon_pack(members, take={"nice-1.0/Nice": "Nice"})
                code, out = self.go("--install", "nice")
                self.assertEqual(code, 1, out)
                self.assertEqual(os.listdir(self.icons), [], "something was left in the icons folder")
                self.assertFalse(os.path.exists(os.path.join(self.h.data, "escape")))

    def test_missing_theme(self):
        self.icon_pack([("nice-1.0/Other/index.theme", "x")], take={"nice-1.0/Nice": "Nice"})
        code, out = self.go("--install", "nice")
        self.assertEqual(code, 1)
        self.assertIn("didn't have Nice", out)

    def test_unknown_and_bad_arguments(self):
        self.icon_pack([("nice-1.0/Nice/index.theme", "x")])
        self.assertEqual(self.go("--install", "nope")[0], 2)
        self.assertEqual(self.go()[0], 2)

    def test_zip_with_links(self):
        """A .zip (Catppuccin's are), its links kept as links."""
        import stat
        import zipfile
        path = os.path.join(self.h.dir, "pack.zip")
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("cat-cursors/index.theme", "[Icon Theme]\nName=Cat\n")
            z.writestr("cat-cursors/cursors/default", "pointer")
            link = zipfile.ZipInfo("cat-cursors/cursors/arrow")
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(link, "default")
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        self.packs([{"id": "cat", "kind": "cursors", "name": "Cat", "about": "",
                     "files": [{"url": "file://" + path, "sha256": digest, "take": {"cat-cursors": "cat-cursors"}}]}])
        code, out = self.go("--install", "cat")
        self.assertEqual(code, 0, out)
        self.assertEqual(os.readlink(os.path.join(self.icons, "cat-cursors", "cursors", "arrow")), "default")

    def test_real_packs_are_pinned(self):
        """Slate's own list: every download an https link to one fixed version, with a fingerprint."""
        import importlib.util
        import re
        self.h.env.pop("SLATE_THEME_PACKS", None)
        spec = importlib.util.spec_from_file_location("theme_packs", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        old = os.environ.pop("SLATE_THEME_PACKS", None)
        try:
            spec.loader.exec_module(mod)
        finally:
            if old is not None:
                os.environ["SLATE_THEME_PACKS"] = old
        self.assertEqual({p["kind"] for p in mod.PACKS}, {"cursors", "icons"})
        self.assertEqual(len({p["id"] for p in mod.PACKS}), len(mod.PACKS), "two packs share an id")
        for p in mod.PACKS:
            for f in p["files"]:
                with self.subTest(f["url"]):
                    self.assertRegex(f["url"], r"^https://github\.com/[^/]+/[^/]+/(releases/download/[^/]+/[^/]+|archive/refs/tags/[^/]+\.tar\.gz)$")
                    self.assertRegex(f["sha256"], r"^[0-9a-f]{64}$")
                    self.assertTrue(f["take"])
