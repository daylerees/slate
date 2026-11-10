"""Settings → App Theming's details for each app (scripts/slate_apps.py): what it is, its
website, and the packages its Install button installs; and slate-system --install, which
installs them."""
import os
import re
import sys

import slate
from slate import Case, run

sys.path.insert(0, slate.path("shell", "scripts"))
import slate_apps  # noqa: E402

FAMILIES = ("arch", "debian", "fedora", "opensuse")
PACKAGE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9@._+-]*$")      # as slate-system accepts


class AppInfo(Case):
    scratch = True

    def test_every_app_has_details(self):
        for a in slate_apps.APPS:
            with self.subTest(a["id"]):
                self.assertIn(a["id"], slate_apps.INFO, "no description, website or packages")
                about, url, pkgs = slate_apps.INFO[a["id"]]
                self.assertTrue(about and not about.endswith("."), "a short description, no full stop (Settings adds one)")
                self.assertRegex(url, r"^https://")
                self.assertTrue(set(pkgs) <= set(FAMILIES), f"unknown distro in {sorted(pkgs)}")
                for fam, names in pkgs.items():
                    for p in names.split():
                        self.assertRegex(p, PACKAGE, f"{fam}: {p!r} isn't a package name slate-system takes")

    def test_no_stale_details(self):
        ids = {a["id"] for a in slate_apps.APPS}
        self.assertFalse(set(slate_apps.INFO) - ids, "details for apps that aren't there any more")
        self.assertFalse(set(slate_apps.DESKTOP) - ids, "desktop entries for apps that aren't there any more")

    def test_desktop_entries(self):
        """What the Open button starts: desktop entry ids (no .desktop), at least one each."""
        for app, ids in slate_apps.DESKTOP.items():
            with self.subTest(app):
                self.assertTrue(ids)
                for d in ids:
                    self.assertRegex(d, r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
                    self.assertFalse(d.endswith(".desktop"))

    def test_family(self):
        cases = {'ID=cachyos\nID_LIKE=arch\n': "arch", 'ID=ubuntu\nID_LIKE="debian"\n': "debian",
                 'ID=fedora\n': "fedora", 'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n': "opensuse",
                 'ID=nixos\n': "nixos", 'ID=gentoo\n': "",
                 # Artix is Arch without systemd: apps install under the same names (pacman).
                 # Void and Gentoo: Slate doesn't know their names for the apps, so no Install button
                 'ID=artix\nID_LIKE=arch\n': "arch", 'ID=void\n': ""}
        for text, want in cases.items():
            with self.subTest(want or "unknown"):
                path = os.path.join(self.h.home, "os-release")
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
                self.assertEqual(slate_apps.family(path), want)
        self.assertEqual(slate_apps.family(os.path.join(self.h.home, "missing")), "")

    def test_detect_gives_this_distros_packages(self):
        fam = slate_apps.family()
        for a in slate_apps.detect():
            with self.subTest(a["id"]):
                self.assertEqual(set(a), {"id", "label", "detail", "installed", "about", "url", "packages", "desktop"})
                self.assertEqual(a["packages"], slate_apps.INFO[a["id"]][2].get(fam, ""))

    def test_install_refuses_bad_names(self):
        """Nothing that isn't a plain package name reaches the package manager (or the password prompt)."""
        for bad in ("bad;name", "-rf", "$(id)", "a b"):
            with self.subTest(bad):
                code, out = run([slate.path("shell", "bin", "slate-system"), "--install", bad], env=self.h.env, timeout=10)
                self.assertNotEqual(code, 0)
                self.assertIn("bad package name", out)

    def test_install_needs_names(self):
        code, out = run([slate.path("shell", "bin", "slate-system"), "--install"], env=self.h.env, timeout=10)
        self.assertNotEqual(code, 0)
        self.assertIn("needs package names", out)
