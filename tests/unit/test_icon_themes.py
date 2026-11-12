"""Choosing a cursor or icon theme (Settings → Input → Pointer style, Appearance → Icons):
scripts/icon-themes.py lists what's installed, and scripts/appicon.py draws Slate's tiles from
the chosen icon theme (the themes it builds on, then the usual ones), wherever that theme
keeps its app icons. Made-up themes in a scratch home: no system themes are read."""
import json
import os
import sys

import slate
from slate import Case, run

THEMES = slate.path("shell", "scripts", "icon-themes.py")
APPICON_DIR = slate.path("shell", "scripts")

SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#%s"/></svg>'


class Themes(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        h = self.h
        self.sys = os.path.join(h.dir, "sys-share")
        os.makedirs(self.sys)
        h.env["XDG_DATA_DIRS"] = self.sys
        self.icons = os.path.join(h.data, "icons")

    def theme(self, name, index=None, files=(), where=None):
        d = os.path.join(where or self.icons, name)
        os.makedirs(d, exist_ok=True)
        if index is not None:
            with open(os.path.join(d, "index.theme"), "w") as f:
                f.write(index)
        for rel, colour in files:
            p = os.path.join(d, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as f:
                f.write(SVG % colour)
        return d

    def listed(self, kind):
        code, out = run([sys.executable, THEMES, "--" + kind], env=self.h.env)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    # ---- icon-themes.py --------------------------------------------------------------------
    def test_cursor_themes(self):
        """Any theme with a cursors folder, by its own name; the first of a name wins."""
        os.makedirs(os.path.join(self.theme("Bibata-Modern-Ice", "[Icon Theme]\nName=Bibata Modern Ice\n"), "cursors"))
        os.makedirs(os.path.join(self.theme("Plain"), "cursors"))                 # (no index: its folder name)
        self.theme("Papirus", "[Icon Theme]\nName=Papirus\nDirectories=64x64/apps\n[64x64/apps]\nContext=Applications\nSize=64\n",
                   [("64x64/apps/firefox.svg", "ff0000")])
        sys_icons = os.path.join(self.sys, "icons")
        os.makedirs(os.path.join(self.theme("Plain", where=sys_icons), "cursors"))
        self.assertEqual(self.listed("cursors"), [{"id": "Bibata-Modern-Ice", "name": "Bibata Modern Ice"},
                                                  {"id": "Plain", "name": "Plain"}])

    def test_icon_themes_need_app_icons(self):
        """Only themes with app icons of their own: not cursor-only themes, hicolor, Slate's
        folder-colour theme, or one whose app folder isn't there."""
        apps = "Directories=64x64/apps\n[64x64/apps]\nContext=Applications\nSize=64\n"
        self.theme("Papirus-Dark", "[Icon Theme]\nName=Papirus-Dark\n" + apps, [("64x64/apps/a.svg", "00ff00")])
        self.theme("breeze", "[Icon Theme]\nName=Breeze\nDirectories=apps/48\n[apps/48]\nContext=Applications\nSize=48\n",
                   [("apps/48/a.svg", "0000ff")])
        self.theme("hicolor", "[Icon Theme]\nName=Hicolor\n" + apps, [("64x64/apps/a.svg", "000000")])
        self.theme("Slate-Icons", "[Icon Theme]\nName=Slate-Icons\nInherits=Papirus-Dark\n" + apps, [("64x64/apps/a.svg", "000000")])
        os.makedirs(os.path.join(self.theme("Cursors-Only", "[Icon Theme]\nName=Cursors Only\n"), "cursors"))
        self.theme("Empty", "[Icon Theme]\nName=Empty\n" + apps)                    # (says it has apps; the folder isn't there)
        self.assertEqual([t["id"] for t in self.listed("icons")], ["breeze", "Papirus-Dark"])

    def test_bad_arguments(self):
        code, out = run([sys.executable, THEMES], env=self.h.env)
        self.assertNotEqual(code, 0)

    # ---- appicon.py: which icon a tile is drawn from ----------------------------------------
    def find(self, theme, name):
        """appicon.py's choice of file for an icon name, drawing from `theme` ("" = GTK's)."""
        code = ("import sys; sys.argv = ['appicon.py']; sys.path.insert(0, %r)\n"
                "import appicon\nappicon.CHAIN = appicon.theme_chain(%r or appicon.gtk_icon_theme())\n"
                "print(appicon.find_icon_file(%r) or '')\n") % (APPICON_DIR, theme, name)
        rc, out = run([sys.executable, "-c", code], env=self.h.env)
        self.assertEqual(rc, 0, out)
        return out.strip()

    def test_chosen_theme_first_in_its_own_layout(self):
        """The chosen theme wins over Papirus, found where its index says (apps/48 in Breeze)."""
        self.theme("Papirus-Dark", "[Icon Theme]\nName=Papirus-Dark\nDirectories=64x64/apps\n[64x64/apps]\nContext=Applications\nSize=64\n",
                   [("64x64/apps/firefox.svg", "ff0000")])
        self.theme("breeze", "[Icon Theme]\nName=Breeze\nDirectories=apps/48\n[apps/48]\nContext=Applications\nSize=48\n",
                   [("apps/48/firefox.svg", "0000ff")])
        self.assertTrue(self.find("breeze", "firefox").endswith("breeze/apps/48/firefox.svg"))
        self.assertTrue(self.find("Papirus-Dark", "firefox").endswith("Papirus-Dark/64x64/apps/firefox.svg"))

    def test_falls_back_through_what_it_builds_on(self):
        """An icon the chosen theme hasn't: from the themes it inherits, then the usual ones."""
        self.theme("Mine", "[Icon Theme]\nName=Mine\nInherits=Base\nDirectories=scalable/apps\n[scalable/apps]\nContext=Applications\nType=Scalable\nSize=64\n",
                   [("scalable/apps/one.svg", "111111")])
        self.theme("Base", "[Icon Theme]\nName=Base\nDirectories=48x48/apps\n[48x48/apps]\nContext=Applications\nSize=48\n",
                   [("48x48/apps/two.svg", "222222")])
        self.theme("Papirus-Dark", "[Icon Theme]\nName=Papirus-Dark\nDirectories=64x64/apps\n[64x64/apps]\nContext=Applications\nSize=64\n",
                   [("64x64/apps/three.svg", "333333")])
        self.assertTrue(self.find("Mine", "one").endswith("Mine/scalable/apps/one.svg"))
        self.assertTrue(self.find("Mine", "two").endswith("Base/48x48/apps/two.svg"))
        self.assertTrue(self.find("Mine", "three").endswith("Papirus-Dark/64x64/apps/three.svg"))

    def test_gtk_theme_when_none_chosen(self):
        """No theme asked for: the one GTK apps use (gtk-3.0/settings.ini)."""
        self.theme("breeze", "[Icon Theme]\nName=Breeze\nDirectories=apps/48\n[apps/48]\nContext=Applications\nSize=48\n",
                   [("apps/48/firefox.svg", "0000ff")])
        self.theme("Papirus-Dark", "[Icon Theme]\nName=Papirus-Dark\nDirectories=64x64/apps\n[64x64/apps]\nContext=Applications\nSize=64\n",
                   [("64x64/apps/firefox.svg", "ff0000")])
        os.makedirs(os.path.join(self.h.config, "gtk-3.0"))
        with open(os.path.join(self.h.config, "gtk-3.0", "settings.ini"), "w") as f:
            f.write("[Settings]\ngtk-icon-theme-name=breeze\n")
        self.assertTrue(self.find("", "firefox").endswith("breeze/apps/48/firefox.svg"))

    def test_theme_of_a_tiles_folder(self):
        """Each theme's tiles have folders of their own (tiles/themes/<theme>/<style>): the
        folder says which theme belongs in it, as it does the style."""
        code = ("import sys; sys.argv = ['appicon.py']; sys.path.insert(0, %r)\nimport appicon\n"
                "print(appicon.theme_of_folder('/c/tiles/themes/breeze-dark/tile'), appicon.theme_of_folder('/c/tiles/circle-whole'),"
                " appicon.style_of_folder('/c/tiles/themes/breeze-dark/tile'))") % APPICON_DIR
        rc, out = run([sys.executable, "-c", code], env=self.h.env)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.strip(), "breeze-dark None ('tile', True)")
