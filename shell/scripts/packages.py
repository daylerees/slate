#!/usr/bin/env python3
"""The package that gives an optional library, by its name on this computer's distro, for
messages that say what to install ("Videos need Qt Multimedia (the qt6-multimedia package)").
Each distro calls them something else; Packages.qml runs this once, the first time a message
needs one, and leaves the package out where the distro isn't known.

    packages.py      {"qtmultimedia": "qt6-multimedia", "poppler": "poppler"}, for this distro

The names are the ones packaging/<family>.txt and packaging/nixos.nix install
(tests/unit/test_packages.py holds them to it)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slate_apps import family  # noqa: E402  (the same answer as install.sh and slate-system)

NAMES = {
    # Qt Multimedia: the click sound, videos in the screensaver and Quick Look, the webcam preview
    "qtmultimedia": {"arch": "qt6-multimedia", "artix": "qt6-multimedia", "void": "qt6-multimedia",
                     "gentoo": "dev-qt/qtmultimedia:6", "debian": "qml6-module-qtmultimedia",
                     "fedora": "qt6-qtmultimedia", "opensuse": "qt6-multimedia-imports",
                     "nixos": "qt6.qtmultimedia"},
    # poppler's pdftoppm: a PDF's pages in Quick Look
    "poppler": {"arch": "poppler", "artix": "poppler", "void": "poppler-utils", "gentoo": "app-text/poppler",
                "debian": "poppler-utils", "fedora": "poppler-utils", "opensuse": "poppler-tools",
                "nixos": "poppler-utils"},
}


def names(fam):
    return {k: v[fam] for k, v in NAMES.items() if fam in v}


if __name__ == "__main__":
    print(json.dumps(names(family())))
