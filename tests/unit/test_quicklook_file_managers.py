"""Quick Look in Dolphin and Thunar (Settings → Default Apps → Quick Look in Dolphin and
Thunar): scripts/apply-theme.py gives each one that's installed a "Quick Look" item on its
right-click menu (and Thunar Space), only with the switch on, and takes all of it out again
when it's switched off, leaving your own menus and shortcuts as they were. Run in a scratch
home with only stub commands on PATH, so which file managers are "installed" is up to the test."""
import json
import os
import shlex
import stat
import sys

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "apply-theme.py")
COLOURS = {"accent": "#c0ffee", "accentText": "#12151a", "bg": "#0f1216", "surface": "#1d222a",
           "surfaceHigh": "#262c35", "text": "#eef1f5", "dim": "#8b94a3", "error": "#f28b8b", "light": False}
MENU = ".local/share/kio/servicemenus/slate-quicklook.desktop"
UCA = ".config/Thunar/uca.xml"
ACCELS = ".config/Thunar/accels.scm"
YOUR_UCA = ('<?xml version="1.0" encoding="UTF-8"?>\n<actions>\n<action>\n\t<icon>utilities-terminal</icon>\n'
            '\t<name>Open Terminal Here</name>\n\t<unique-id>1700000000000000-1</unique-id>\n'
            '\t<command>exo-open --working-directory %f --launch TerminalEmulator</command>\n'
            '\t<description>Example for a custom action</description>\n\t<patterns>*</patterns>\n'
            '\t<startup-notify/>\n\t<directories/>\n</action>\n</actions>\n')
YOUR_ACCELS = ('; thunar GtkAccelMap rc-file         -*- scheme -*-\n'
               '(gtk_accel_path "<Actions>/ThunarActions/uca-action-1700000000000000-1" "<Primary><Alt>t")\n'
               '; (gtk_accel_path "<Actions>/ThunarActions/uca-action-slate-quicklook" "")\n')


class QuickLookInFileManagers(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.env = dict(self.s.env, PATH=self.s.dir, SLATE_THEME_TEST="1")

    def install(self, *names):
        for n in names:
            self.s.add(n)

    def apply(self, on):
        code, out = run([sys.executable, SCRIPT, json.dumps(dict(COLOURS, on=[], quickLookInFileManagers=on))], env=self.env)
        self.assertEqual(code, 0, out)
        return out

    def files(self):
        out = {}
        for d, _, names in os.walk(self.h.home):
            for n in names:
                rel = os.path.relpath(os.path.join(d, n), self.h.home)
                if rel != ".local/state/slate/app-theming.json" and not rel.endswith(".bak-slate-theme"):
                    with open(os.path.join(d, n), "rb") as f:
                        out[rel] = f.read()
        return out

    def dirs(self):
        return {os.path.relpath(d, self.h.home) for d, _, _ in os.walk(self.h.home)}

    def put(self, rel, text):
        p = self.h(rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)

    def text(self, rel):
        with open(self.h(rel)) as f:
            return f.read()

    def test_nothing_until_chosen(self):
        """Off (as it is to start with), with both installed: nothing is written."""
        self.install("dolphin", "thunar")
        before, folders = self.files(), self.dirs()
        self.apply(False)
        self.assertEqual(self.files(), before)
        self.assertEqual(self.dirs() - {".local/state/slate"}, folders - {".local/state/slate"})

    def test_only_what_is_installed(self):
        self.install("dolphin")
        self.apply(True)
        self.assertTrue(os.path.isfile(self.h(MENU)))
        self.assertFalse(os.path.exists(self.h(".config/Thunar")))

    def test_dolphin_menu(self):
        self.install("dolphin")
        self.apply(True)
        menu = self.text(MENU)
        self.assertIn("X-KDE-ServiceTypes=KonqPopupMenu/Plugin\n", menu)
        self.assertIn("Name=Quick Look\n", menu)
        slate_cmd = os.path.join(slate.SHELL, "bin", "slate")
        exec_line = next(l for l in menu.splitlines() if l.startswith("Exec="))
        self.assertTrue(exec_line.endswith(" ipc call quicklook open -- %f"), exec_line)
        self.assertIn(slate_cmd, exec_line)
        self.assertTrue(os.stat(self.h(MENU)).st_mode & stat.S_IXUSR, "Dolphin skips a service menu it can't run")
        # Off: gone, and the folders made for it with it
        out = self.apply(False)
        self.assertIn("switched off quick-look", out)
        self.assertFalse(os.path.exists(self.h(".local/share/kio")))

    def test_thunar_in_an_empty_home(self):
        self.install("thunar")
        self.apply(True)
        uca = self.text(UCA)
        self.assertIn("<unique-id>slate-quicklook</unique-id>", uca)
        self.assertIn("<name>Quick Look</name>", uca)
        self.assertEqual(uca.count("<action>"), 1)
        self.assertIn('(gtk_accel_path "<Actions>/ThunarActions/uca-action-slate-quicklook" "space")', self.text(ACCELS))
        self.apply(True)                       # (again: nothing added twice)
        self.assertEqual(self.text(UCA).count("<action>"), 1)
        self.assertEqual(self.text(ACCELS).count("slate-quicklook"), 1)
        self.apply(False)
        self.assertFalse(os.path.exists(self.h(".config/Thunar")), "Thunar's folder, made only for this, stays")

    def test_thunar_keeps_your_own(self):
        self.install("thunar")
        self.put(UCA, YOUR_UCA)
        self.put(ACCELS, YOUR_ACCELS)
        self.apply(True)
        uca = self.text(UCA)
        self.assertIn("Open Terminal Here", uca)
        self.assertEqual(uca.count("<action>"), 2)
        self.assertTrue(uca.rstrip().endswith("</actions>"))
        accels = self.text(ACCELS)
        self.assertIn('"<Primary><Alt>t"', accels)
        self.assertIn('(gtk_accel_path "<Actions>/ThunarActions/uca-action-slate-quicklook" "space")', accels)
        self.assertNotIn('; (gtk_accel_path "<Actions>/ThunarActions/uca-action-slate-quicklook" "")', accels)
        self.apply(False)
        self.assertEqual(self.text(UCA), YOUR_UCA)
        self.assertEqual(self.text(ACCELS), YOUR_ACCELS)

    def test_the_command_is_quoted_for_each_reader(self):
        """Slate's folder with a space, a quote and a dollar in it: each file manager reads its
        command its own way (Dolphin as a desktop entry's Exec, Thunar through a shell's rules),
        and each gets the path back exactly."""
        import importlib.util
        spec = importlib.util.spec_from_file_location("apply_theme", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        sys.path.insert(0, os.path.dirname(SCRIPT))
        try:
            spec.loader.exec_module(mod)
        finally:
            sys.path.pop(0)
        odd = "/home/me/My \"Slate\" $HOME `x` \\ folder/bin/slate"
        # Desktop entry: unescape the value (\\ → \), then split as the spec's quoting says
        value = mod.desktop_exec_arg(odd).replace("\\\\", "\\")
        self.assertTrue(value.startswith('"') and value.endswith('"'))
        inner, out, i = value[1:-1], "", 0
        while i < len(inner):
            if inner[i] == "\\" and i + 1 < len(inner) and inner[i + 1] in '"`$\\':
                out += inner[i + 1]
                i += 2
            else:
                out += inner[i]
                i += 1
        self.assertEqual(out, odd)
        self.assertEqual(shlex.split(shlex.quote(odd) + " ipc")[0], odd)
