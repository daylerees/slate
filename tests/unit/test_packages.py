"""scripts/packages.py: an optional library's package by its name on this distro, for messages
saying what to install. They named Arch's packages everywhere ("the qt6-multimedia package",
"poppler-utils (poppler on Arch)"), which don't exist under those names on Debian, Fedora,
openSUSE or NixOS (a bug). Every name in the table is one packaging/ installs for that family."""
import json
import os
import re
import sys

import slate
from slate import Case, run

sys.path.insert(0, slate.path("shell", "scripts"))
import packages  # noqa: E402

FAMILIES = ("arch", "artix", "void", "gentoo", "debian", "fedora", "opensuse", "nixos")


def listed(fam):
    """The package names packaging/ installs for a family."""
    if fam == "nixos":
        text = slate.read("packaging", "nixos.nix")
        return set(re.findall(r"[A-Za-z0-9_.+:/-]+", text))
    out = set()
    for line in slate.read("packaging", fam + ".txt").split("\n"):
        line = line.split("#")[0].strip().lstrip("?")
        if line:
            out.update(line.split())
    return out


class Names(Case):
    def test_every_family_has_every_name(self):
        for key, by in packages.NAMES.items():
            self.assertEqual(set(by), set(FAMILIES), key)

    def test_each_name_is_one_packaging_installs(self):
        for key, by in packages.NAMES.items():
            for fam, name in by.items():
                with self.subTest(key=key, fam=fam):
                    self.assertIn(name, listed(fam), f"packaging for {fam} doesn't install {name}")

    def test_prints_this_distros(self):
        code, out = run([sys.executable, slate.path("shell", "scripts", "packages.py")], timeout=10)
        self.assertEqual(code, 0, out)
        self.assertIsInstance(json.loads(out), dict)

    def test_unknown_distro_names_none(self):
        self.assertEqual(packages.names(""), {})
        self.assertEqual(packages.names("debian")["qtmultimedia"], "qml6-module-qtmultimedia")

    def test_messages_name_no_distros_package(self):
        """No message spells out one distro's package: they go through Packages.named."""
        found = []
        for root, _, files in os.walk(slate.path("shell")):
            for f in files:
                if not f.endswith(".qml"):
                    continue
                for n, line in enumerate(open(os.path.join(root, f), encoding="utf-8"), 1):
                    if re.search(r'"[^"]*(qt6-multimedia|poppler-utils|poppler on Arch)[^"]*"', line.split("//")[0]):
                        found.append(f"{f}:{n}")
        self.assertEqual(found, [])
