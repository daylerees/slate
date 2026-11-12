"""scripts/folder-colour.py: Papirus folder colours for file managers (Settings → Appearance →
Folder colour). Runs against a small Papirus-like icon tree made at test time, outside the
scratch home as the system's copy would be, with gsettings stubbed.

Checks --list, setting a named colour (the Slate-Icons theme it builds: which links point
where, its index.theme), the GTK/Qt/KDE files and gsettings calls, --auto, default, the
errors, and that nothing is written outside the scratch home.
"""
import json
import os
import sys

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "folder-colour.py")
IFACE = "org.gnome.desktop.interface"

# The colours of the fixture's folders: back, front edge, front (face() reads the third fill)
FACES = {"blue": "#5294e2", "teal": "#16a085", "red": "#e25252", "grey": "#8e8e8e",
         "black": "#4f4f4f", "yaru": "#e95420"}


def svg(*fills):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
            + "".join(f'<path d="M0 0h64v64H0z" style="fill:{c}"/>' for c in fills) + "</svg>")


class FolderColour(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        h = self.h
        # The "system" icon themes, beside the scratch home rather than in it
        self.sys = os.path.join(h.dir, "usr-share")
        self.papirus = os.path.join(self.sys, "icons", "Papirus")
        self.make_papirus()
        self.s = Stubs(h)
        self.s.env["XDG_DATA_DIRS"] = self.sys
        self.theme("Papirus-Dark")
        self.ours = os.path.join(h.data, "icons", "Slate-Icons")

    # --- fixtures ---
    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def make_papirus(self):
        """Papirus: two sizes of places/ with every colour's folders, and the default names
        (folder.svg, user-home.svg…) as links to the blue ones; Papirus-Dark inherits it."""
        sizes = ("48x48", "64x64")
        sections = "".join(f"\n[{s}/places]\nContext=Places\nSize={s.split('x')[0]}\nType=Fixed\n"
                           f"\n[{s}/apps]\nContext=Applications\nSize={s.split('x')[0]}\n" for s in sizes)
        self.write(os.path.join(self.papirus, "index.theme"),
                   "[Icon Theme]\nName=Papirus\nInherits=breeze,hicolor\n"
                   f"Directories={','.join(s + '/places,' + s + '/apps' for s in sizes)}\n" + sections)
        for s in sizes:
            places = os.path.join(self.papirus, s, "places")
            for c, hexc in FACES.items():
                fills = ("#e95420", hexc) if c == "yaru" else ("#000000", "#ffffff", hexc)
                for kind in ("", "-documents", "-download"):
                    self.write(os.path.join(places, f"folder-{c}{kind}.svg"), svg(*fills))
                self.write(os.path.join(places, f"user-{c}-home.svg"), svg(*fills))
            for name, target in (("folder.svg", "folder-blue.svg"),
                                 ("folder-documents.svg", "folder-blue-documents.svg"),
                                 ("folder-download.svg", "folder-blue-download.svg"),
                                 ("user-home.svg", "user-blue-home.svg"),
                                 # A colour this Papirus doesn't have in other kinds: kept as it is
                                 ("folder-videos.svg", "folder-blue-videos.svg"),
                                 # Links that aren't folder colours: left to the base theme
                                 ("network-workgroup.svg", "folder-remote.svg")):
                os.symlink(target, os.path.join(places, name))
            self.write(os.path.join(places, "folder-remote.svg"), svg("#123456"))
            self.write(os.path.join(places, "folder-blue-videos.svg"), svg("#000000", "#ffffff", "#5294e2"))
            self.write(os.path.join(self.papirus, s, "apps", "firefox.svg"), svg("#ff0000"))
        self.write(os.path.join(self.sys, "icons", "Papirus-Dark", "index.theme"),
                   "[Icon Theme]\nName=Papirus-Dark\nInherits=Papirus,breeze-dark,hicolor\n")
        self.write(os.path.join(self.sys, "icons", "Adwaita", "index.theme"),
                   "[Icon Theme]\nName=Adwaita\nInherits=hicolor\n")

    def theme(self, name):
        """The icon theme gsettings says is in use."""
        self.s.add("gsettings", by_args={"get " + IFACE + " icon-theme": f"'{name}'\n", "set ": ""})
        self.s.add("dbus-send")

    def folder(self, *args):
        return run([sys.executable, SCRIPT, *args], env=self.s.env)

    def listing(self):
        code, out = self.folder("--list")
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def snapshot(self, top):
        found = {}
        for d, dirs, names in os.walk(top):
            for n in dirs + names:
                p = os.path.join(d, n)
                st = os.lstat(p)
                found[os.path.relpath(p, top)] = (st.st_mode, st.st_size, st.st_mtime_ns,
                                                  os.readlink(p) if os.path.islink(p) else None)
        return found

    # --- --list ---
    def test_list(self):
        got = self.listing()
        self.assertEqual(got["supported"], True)
        self.assertEqual(got["base"], "Papirus-Dark")
        self.assertEqual(got["current"], "")
        # In COLOURS' order, each with its folder's front colour (yaru: the second fill)
        self.assertEqual(got["colours"], [{"name": n, "hex": FACES[n]}
                                          for n in ("black", "blue", "grey", "red", "teal", "yaru")])
        self.assertEqual(self.s.calls("gsettings"), [["get", IFACE, "icon-theme"]], "read once, nothing set")
        self.assertFalse(os.path.exists(self.ours))

    def test_list_not_papirus(self):
        self.theme("Adwaita")
        self.assertEqual(self.listing(), {"supported": False, "base": "Adwaita", "current": "", "kind": "", "colours": []})

    def test_list_no_gsettings(self):
        """No gsettings at all (not a GNOME system): unsupported, not a crash."""
        self.s.add("gsettings", missing=True)
        got = self.listing()
        self.assertEqual((got["supported"], got["base"], got["colours"]), (False, "", []))

    def test_list_theme_in_home(self):
        """A Papirus in ~/.local/share/icons is found too, before the system's."""
        self.theme("MyPapirus")
        self.write(os.path.join(self.h.data, "icons", "MyPapirus", "index.theme"),
                   "[Icon Theme]\nName=MyPapirus\nInherits=Papirus-Dark\n")
        got = self.listing()
        self.assertTrue(got["supported"])
        self.assertEqual(got["base"], "MyPapirus")

    # --- setting a colour ---
    def test_set_colour(self):
        before = self.snapshot(self.sys)
        code, out = self.folder("teal")
        self.assertEqual(code, 0, out)
        self.assertEqual(out, "teal\n")
        self.assertEqual(self.snapshot(self.sys), before, "the system's icon theme was changed")
        # Our theme: each size's places/, links only
        self.assertEqual(sorted(os.listdir(self.ours)), ["48x48", "64x64", "index.theme"])
        for size in ("48x48", "64x64"):
            places = os.path.join(self.ours, size, "places")
            real = os.path.realpath(os.path.join(self.papirus, size, "places"))
            links = {n: os.readlink(os.path.join(places, n)) for n in os.listdir(places)}
            self.assertEqual(links, {
                "folder.svg": os.path.join(real, "folder-teal.svg"),
                "folder-documents.svg": os.path.join(real, "folder-teal-documents.svg"),
                "folder-download.svg": os.path.join(real, "folder-teal-download.svg"),
                "user-home.svg": os.path.join(real, "user-teal-home.svg"),
                # No teal videos folder: the link keeps pointing at the blue one
                "folder-videos.svg": os.path.join(real, "folder-blue-videos.svg"),
            }, size)
            for n in links:
                self.assertTrue(os.path.isfile(os.path.join(places, n)), f"{size}/{n} is a broken link")
        with open(os.path.join(self.ours, "index.theme")) as f:
            index = f.read()
        self.assertIn("[Icon Theme]\nName=Slate-Icons\n", index)
        for line in ("Inherits=Papirus-Dark", "Directories=48x48/places,64x64/places",
                     "X-Slate-Base=Papirus-Dark", "X-Slate-Colour=teal",
                     "[64x64/places]\nContext=Places\nSize=64\nType=Fixed"):
            self.assertIn(line, index)
        self.assertNotIn("/apps]", index, "only the folders' directories are listed")

    def test_set_points_apps_at_it(self):
        self.write(os.path.join(self.h.config, "kdeglobals"),
                   "[General]\nColorScheme=Breeze\n\n[Icons]\nTheme=breeze\n")
        self.write(os.path.join(self.h.config, "gtk-3.0", "settings.ini"),
                   "[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=Papirus-Dark\n")
        code, out = self.folder("red")
        self.assertEqual(code, 0, out)

        def read(*p):
            with open(os.path.join(self.h.config, *p)) as f:
                return f.read()
        self.assertEqual(read("gtk-3.0", "settings.ini"),
                         "[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=Slate-Icons\n")
        self.assertEqual(read("gtk-4.0", "settings.ini"), "[Settings]\ngtk-icon-theme-name=Slate-Icons\n")
        self.assertEqual(read("qt6ct", "qt6ct.conf"), "[Appearance]\nicon_theme=Slate-Icons\n")
        self.assertEqual(read("kdeglobals"), "[General]\nColorScheme=Breeze\n\n[Icons]\nTheme=Slate-Icons\n")
        self.assertFalse(os.path.exists(os.path.join(self.h.config, "qt5ct")), "qt5ct is only changed if it's there")
        self.assertEqual(self.s.calls("gsettings"), [["get", IFACE, "icon-theme"],
                                                     ["set", IFACE, "icon-theme", "Slate-Icons"]])
        self.assertEqual(self.s.calls("dbus-send"), [["--session", "--type=signal", "/KIconLoader",
                                                      "org.kde.KIconLoader.iconChanged", "int32:0"]])

    def test_change_colour_refreshes(self):
        """Already on Slate-Icons, a new colour: rebuilt on the same base, and gsettings switches
        away and back so running apps reload the icons."""
        self.assertEqual(self.folder("teal")[0], 0)
        self.theme("Slate-Icons")
        seen = len(self.s.calls("gsettings"))
        code, out = self.folder("red")
        self.assertEqual((code, out), (0, "red\n"))
        self.assertIn("X-Slate-Colour=red", open(os.path.join(self.ours, "index.theme")).read())
        self.assertIn("Inherits=Papirus-Dark", open(os.path.join(self.ours, "index.theme")).read())
        self.assertEqual(os.path.basename(os.readlink(os.path.join(self.ours, "64x64", "places", "folder.svg"))),
                         "folder-red.svg")
        self.assertEqual([c for c in self.s.calls("gsettings")[seen:] if c[0] == "set"],
                         [["set", IFACE, "icon-theme", "hicolor"], ["set", IFACE, "icon-theme", "Slate-Icons"]])
        self.assertEqual(self.listing()["current"], "red")

    def test_same_colour_does_nothing(self):
        """Asking for the colour already in use changes nothing (so apps don't flicker)."""
        self.folder("teal")
        self.theme("Slate-Icons")
        before = self.snapshot(self.h.home)
        seen = len(self.s.calls("gsettings"))
        code, out = self.folder("teal")
        self.assertEqual((code, out), (0, "teal\n"))
        self.assertEqual(self.snapshot(self.h.home), before)
        self.assertEqual([c for c in self.s.calls("gsettings")[seen:] if c[0] == "set"], [])

    def test_auto(self):
        """--auto picks by hue for colourful colours, and a grey for greys."""
        for hexc, want in (("#4a90d9", "blue"), ("#20b090", "teal"), ("#d03030", "red"),
                           ("#e06020", "red"), ("#808080", "grey"), ("#202020", "black")):
            with self.subTest(hexc):
                code, out = self.folder("--auto", hexc)
                self.assertEqual((code, out), (0, want + "\n"))

    def test_auto_bad_colour(self):
        for bad in ([], ["blue"], ["#12345"], ["#gggggg"]):
            with self.subTest(str(bad)):
                code, out = self.folder("--auto", *bad)
                self.assertEqual(code, 1)
                self.assertIn("--auto needs a colour like #4a90d9", out)
        self.assertFalse(os.path.exists(self.ours))

    def test_unknown_colour(self):
        for name in ("mauve", "../blue", "BLUE"):
            with self.subTest(name):
                code, out = self.folder(name)
                self.assertEqual(code, 1)
                self.assertIn(f"no '{name}' folders in", out)
        self.assertFalse(os.path.exists(self.ours))
        self.assertFalse(os.path.exists(os.path.join(self.h.config, "gtk-3.0")))
        self.assertEqual([c for c in self.s.calls("gsettings") if c[0] == "set"], [])

    def test_not_papirus(self):
        self.theme("Adwaita")
        code, out = self.folder("teal")
        self.assertEqual(code, 1)
        self.assertIn("the icon theme (Adwaita) has no folders in colours", out)
        self.assertFalse(os.path.exists(self.ours))

    def test_default(self):
        """default: back to the theme ours was built on, and ours removed."""
        self.folder("teal")
        self.theme("Slate-Icons")
        code, out = self.folder("default")
        self.assertEqual((code, out), (0, ""))
        self.assertFalse(os.path.exists(self.ours))
        self.assertEqual([c for c in self.s.calls("gsettings") if c[0] == "set"][-1],
                         ["set", IFACE, "icon-theme", "Papirus-Dark"])
        with open(os.path.join(self.h.config, "gtk-4.0", "settings.ini")) as f:
            self.assertIn("gtk-icon-theme-name=Papirus-Dark", f.read())

    def test_default_when_not_in_use(self):
        """default with another theme in use: nothing is switched."""
        code, out = self.folder("default")
        self.assertEqual((code, out), (0, ""))
        self.assertEqual([c for c in self.s.calls("gsettings") if c[0] == "set"], [])
        self.assertFalse(os.path.exists(os.path.join(self.h.config, "gtk-3.0")))

    def test_icon_theme(self):
        code, out = self.folder("--icon-theme", "Papirus-Dark")
        self.assertEqual(code, 0, out)
        self.assertEqual([c for c in self.s.calls("gsettings") if c[0] == "set"],
                         [["set", IFACE, "icon-theme", "Papirus-Dark"]])
        code, out = self.folder("--icon-theme", "Nonexistent")
        self.assertEqual(code, 1)
        self.assertIn("no icon theme called Nonexistent", out)

    def test_stays_in_home(self):
        """Everything it writes is in the scratch home: the fixture "system" tree and the rest of
        the scratch dir are untouched."""
        top = self.h.dir
        skip = ("home", "stub-calls")
        before = {k: v for k, v in self.snapshot(top).items() if k.split("/")[0] not in skip}
        for args in (["teal"], ["--auto", "#d03030"], ["default"], ["--icon-theme", "Adwaita"]):
            self.folder(*args)
        after = {k: v for k, v in self.snapshot(top).items() if k.split("/")[0] not in skip}
        self.assertEqual(after, before)

    def test_usage(self):
        code, out = self.folder()
        self.assertEqual(code, 1)
        self.assertIn("folder-colour.py --list", out)

    # --- themes like Kora and Nordzy: the plain folder in colours, nothing else ---
    def make_kora(self):
        """A Kora-like theme: places/scalable with folder.svg and folder-<colour>.svg (drawn in
        rgb(), an outline plus the colour), and a Documents folder with no colours."""
        kora = os.path.join(self.sys, "icons", "kora")
        self.write(os.path.join(kora, "index.theme"),
                   "[Icon Theme]\nName=Kora\nInherits=breeze,hicolor\nDirectories=places/scalable\n"
                   "\n[places/scalable]\nContext=Places\nSize=48\nType=Scalable\n")
        places = os.path.join(kora, "places", "scalable")
        for c, rgb in (("blue", "1,41,180"), ("red", "200,30,30"), ("green", "40,160,60"), ("grey", "128,128,128")):
            self.write(os.path.join(places, "folder-%s.svg" % c),
                       '<svg><path style="fill:rgb(20,20,20)"/><path style="fill:rgb(%s)"/></svg>' % rgb)
        # The plain folder in the theme's own blue; Desktop drawn in the same colours plus its
        # emblem's; a folder drawn some other way (no shared colour) is left alone
        self.write(os.path.join(places, "folder.svg"),
                   '<svg><path style="fill:rgb(20,20,20)"/><path style="fill:rgb(0,131,213)"/></svg>')
        self.write(os.path.join(places, "user-desktop.svg"),
                   '<svg><path style="fill:rgb(20,20,20)"/><path style="fill:rgb(0,131,213)"/><path fill="#0b4e94"/></svg>')
        os.symlink("user-desktop.svg", os.path.join(places, "desktop.svg"))
        self.write(os.path.join(places, "folder-documents.svg"), '<svg><path fill="#ffaa00"/></svg>')
        self.theme("kora")
        return places

    def test_list_plain_folders(self):
        self.make_kora()
        got = self.listing()
        self.assertEqual((got["supported"], got["base"], got["kind"]), (True, "kora", "plain"))
        self.assertEqual([(c["name"], c["hex"]) for c in got["colours"]],
                         [("blue", "#0129b4"), ("green", "#28a03c"), ("grey", "#808080"), ("red", "#c81e1e")])

    def test_set_plain_folder(self):
        """folder.svg is the chosen colour, in every places folder that has the colours; other
        folders drawn in the plain folder's colours (Desktop) are repainted, their emblems moved
        the same way; the rest comes from the theme itself."""
        places = self.make_kora()
        code, out = self.folder("red")
        self.assertEqual(code, 0, out)
        link = os.path.join(self.ours, "places", "scalable", "folder.svg")
        self.assertEqual(os.readlink(link), os.path.join(os.path.realpath(places), "folder-red.svg"))
        self.assertEqual(sorted(os.listdir(os.path.dirname(link))), ["desktop.svg", "folder.svg", "user-desktop.svg"])
        desk = open(os.path.join(self.ours, "places", "scalable", "user-desktop.svg")).read()
        self.assertIn("rgb(200,30,30)", desk, "Desktop isn't in the chosen colour")
        self.assertIn("rgb(20,20,20)", desk, "the outline changed")
        self.assertNotIn("0,131,213", desk)
        self.assertNotIn("#0b4e94", desk, "the emblem kept the old colour")
        self.assertEqual(os.readlink(os.path.join(self.ours, "places", "scalable", "desktop.svg")), "user-desktop.svg")
        index = open(os.path.join(self.ours, "index.theme")).read()
        self.assertIn("Inherits=kora\n", index)
        self.assertIn("X-Slate-Base=kora\nX-Slate-Colour=red", index)
        self.assertIn("[places/scalable]\nContext=Places", index)
        self.assertIn(["set", IFACE, "icon-theme", "Slate-Icons"], self.s.calls("gsettings"))

    def test_auto_plain_folders(self):
        """From the wallpaper: the colour nearest it, from the folders' own drawn colours."""
        self.make_kora()
        code, out = self.folder("--auto", "#2a40c0")
        self.assertEqual(code, 0, out)
        self.assertEqual(out.strip(), "blue")


    def test_auto_goes_by_hue(self):
        """The wallpaper's colour reaches here soft and light (set for the theme), so the match
        goes mostly by hue. A bug: a mint-green wallpaper (#9cddba) got Papirus's bluish
        darkcyan, nearer in lightness, instead of teal, nearer in colour."""
        import importlib.util
        spec = importlib.util.spec_from_file_location("folder_colour", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        old = sys.argv
        try:
            sys.argv = [SCRIPT]
            spec.loader.exec_module(mod)
        finally:
            sys.argv = old
        papirus = [{"name": n, "hex": h} for n, h in (
            ("blue", "#5294e2"), ("cyan", "#00bcd4"), ("darkcyan", "#45abb7"), ("green", "#87b158"),
            ("teal", "#16a085"), ("violet", "#7e57c2"), ("pink", "#f06292"), ("grey", "#8e8e8e"))]
        for wall, want in (("#9cddba", "teal"), ("#8fb3e8", "blue"), ("#e8a6b4", "pink"), ("#a6d3a0", "green")):
            with self.subTest(wall):
                self.assertEqual(mod.nearest(wall, papirus), want)
