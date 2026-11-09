"""scripts/apply-theme.py: App Theming. Applying a theme writes each app's files in Slate's
colours, switching an app off puts your own config back exactly (the undo log), and
`--apps` lists what Slate can theme. Run with SLATE_THEME_TEST=1 in a scratch home, with a
PATH of stubs only, so which apps count as installed is up to the test."""
import json
import os
import sys
import unittest

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "apply-theme.py")
ACCENT = "#c0ffee"
ACCENT_RGB = "192,255,238"
COLOURS = {"accent": ACCENT, "accentText": "#12151a", "bg": "#0f1216", "surface": "#1d222a",
           "surfaceHigh": "#262c35", "text": "#eef1f5", "dim": "#8b94a3", "error": "#f28b8b",
           "light": False}
# Programs whose presence on PATH makes their app count as installed
PROGRAMS = ("kitty", "alacritty", "foot", "ghostty", "hx", "zathura", "btop", "wezterm")
ALL = ["gtk", "qt", "kde", "kitty", "alacritty", "foot", "ghostty", "helix", "zed", "vscode",
       "btop", "zathura", "wezterm", "firefox"]

# Your own configs, there before Slate themes anything
YOURS = {
    ".config/foot/foot.ini": "[main]\nfont=monospace:size=11\n",
    ".config/alacritty/alacritty.toml": "[general]\nimport = [\"~/extra.toml\"]\n\n[font]\nsize = 11\n",
    ".config/helix/config.toml": "theme = \"onedark\"\n[editor]\nline-number = \"relative\"\n",
    ".config/zed/settings.json": "// Zed settings\n{\n  \"vim_mode\": true,\n  \"ui_font_size\": 16\n}\n",
    ".config/Code/User/settings.json": "{\n    \"editor.fontSize\": 14,\n    \"workbench.colorTheme\": \"Default Dark+\"\n}\n",
    ".config/qt6ct/qt6ct.conf": "[Appearance]\ncolor_scheme_path=/usr/share/qt6ct/colors/darker.conf\n"
                                "custom_palette=false\nstyle=Fusion\n\n[Fonts]\nfixed=\"Mono,10\"\n",
    ".config/gtk-3.0/gtk.css": "window { padding: 0; }\n",
    ".config/gtk-3.0/settings.ini": "[Settings]\ngtk-theme-name=Adwaita\n",
    ".config/btop/btop.conf": "color_theme = \"Default\"\ntheme_background = False\n",
    ".config/kitty/kitty.conf": "font_size 12\nmap ctrl+t new_tab\n",
    ".config/zathura/zathurarc": "set recolor true\n",
    ".mozilla/firefox/profiles.ini": "[Profile0]\nName=default\nIsRelative=1\nPath=test.default\nDefault=1\n",
    ".mozilla/firefox/test.default/prefs.js": "// prefs\n",
}


class ApplyTheme(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        for p in PROGRAMS:
            self.s.add(p)
        # Only the stubs: real apps on this computer mustn't change what's "installed"
        self.env = dict(self.s.env, PATH=self.s.dir, SLATE_THEME_TEST="1")

    def apply(self, on, **over):
        code, out = run([sys.executable, SCRIPT, json.dumps(dict(COLOURS, on=on, **over))], env=self.env)
        self.assertEqual(code, 0, out)
        return out

    def put(self, files):
        for rel, text in files.items():
            p = self.h(rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w") as f:
                f.write(text)

    def text(self, rel):
        with open(self.h(rel)) as f:
            return f.read()

    def tree(self):
        """Every file under the scratch home (but Slate's undo log), home-relative."""
        out = set()
        for d, _, names in os.walk(self.h.home):
            for n in names:
                rel = os.path.relpath(os.path.join(d, n), self.h.home)
                if rel != ".local/state/slate/app-theming.json":
                    out.add(rel)
        return out

    def manifest(self):
        with open(os.path.join(self.h.state, "slate", "app-theming.json")) as f:
            return json.load(f)

    # ---- applying ----
    def test_writes_each_apps_theme(self):
        self.put(YOURS)
        out = self.apply(ALL)
        expect = {
            ".config/gtk-3.0/slate.css": "@define-color accent_color %s;" % ACCENT,
            ".config/gtk-3.0/gtk.css": '@import url("slate.css");',
            ".config/gtk-4.0/slate.css": "--accent-color: %s;" % ACCENT,
            ".config/gtk-4.0/gtk.css": '@import url("slate.css");',
            ".config/gtk-3.0/settings.ini": "gtk-application-prefer-dark-theme=1",
            ".config/qt6ct/colors/slate.conf": ACCENT,
            ".config/qt6ct/qt6ct.conf": "color_scheme_path=%s" % self.h(".config/qt6ct/colors/slate.conf"),
            ".local/share/color-schemes/slate.colors": "DecorationFocus=%s" % ACCENT_RGB,
            ".config/kdeglobals": "ColorScheme=slate",
            ".config/kitty/themes/slate.conf": "active_border_color   %s" % ACCENT,
            ".config/kitty/kitty.conf": "include themes/slate.conf",
            ".config/alacritty/themes/slate.toml": "cursor = '%s'" % ACCENT,
            ".config/alacritty/alacritty.toml":
                'import = ["~/extra.toml", "~/.config/alacritty/themes/slate.toml"]',
            ".config/foot/slate.ini": "regular4=%s" % ACCENT[1:],
            ".config/ghostty/themes/slate": "palette = 4=%s" % ACCENT,
            ".config/ghostty/config": "theme = slate",
            ".config/helix/themes/slate.toml": ACCENT,
            ".config/helix/config.toml": 'theme = "slate"',
            ".config/zed/themes/slate.json": ACCENT,
            ".config/zed/settings.json": '"theme": "Slate"',
            ".vscode/extensions/slate.slate-theme-1.0.0/themes/slate.json": '"focusBorder": "%s"' % ACCENT,
            ".config/Code/User/settings.json": '"workbench.colorTheme": "Slate"',
            ".config/btop/themes/slate.theme": 'theme[title]="%s"' % ACCENT,
            ".config/btop/btop.conf": 'color_theme = "slate"',
            ".config/zathura/slate": 'set highlight-active-color "%s"' % ACCENT,
            ".config/zathura/zathurarc": "include slate",
            ".config/wezterm/colors/slate.toml": '"%s"' % ACCENT,
            ".mozilla/firefox/test.default/chrome/slate.css": "--focus-outline-color: %s !important;" % ACCENT,
            ".mozilla/firefox/test.default/chrome/userChrome.css": '@import "slate.css";',
            ".mozilla/firefox/test.default/user.js": "toolkit.legacyUserProfileCustomizations.stylesheets",
        }
        for rel, want in expect.items():
            with self.subTest(rel):
                self.assertIn(want, self.text(rel))
        # It says what it changed, with ~ for the home
        self.assertIn("updated ~/.config/kitty/themes/slate.conf", out)
        self.assertNotIn(self.h.home, out)

    def test_themes_are_valid_json(self):
        self.put(YOURS)
        self.apply(["zed", "vscode"])
        for rel in (".config/zed/themes/slate.json", ".vscode/extensions/slate.slate-theme-1.0.0/package.json",
                    ".vscode/extensions/slate.slate-theme-1.0.0/themes/slate.json",
                    ".config/Code/User/settings.json"):
            with self.subTest(rel):
                json.loads(self.text(rel))
        theme = json.loads(self.text(".vscode/extensions/slate.slate-theme-1.0.0/themes/slate.json"))
        self.assertEqual((theme["name"], theme["type"]), ("Slate", "dark"))
        # Your other settings stay
        self.assertEqual(json.loads(self.text(".config/Code/User/settings.json")),
                         {"editor.fontSize": 14, "workbench.colorTheme": "Slate"})

    def test_light_mode(self):
        self.apply(["gtk", "kitty"], light=True, bg="#f6f7f9", text="#1b1f24")
        self.assertIn("gtk-application-prefer-dark-theme=0", self.text(".config/gtk-3.0/settings.ini"))
        theme = self.text(".config/kitty/themes/slate.conf")
        self.assertIn("background            #f6f7f9", theme)
        self.assertIn("background_opacity      0.92", theme)

    def test_backs_up_your_config_once(self):
        self.put(YOURS)
        self.apply(["kitty"])
        self.apply(["kitty"], accent="#ff8800")
        self.assertEqual(self.text(".config/kitty/kitty.conf.bak-slate-theme"), YOURS[".config/kitty/kitty.conf"])
        self.assertIn("#ff8800", self.text(".config/kitty/themes/slate.conf"))

    def test_only_installed_apps(self):
        """An app switched on but not installed is left alone."""
        os.remove(os.path.join(self.s.dir, "kitty"))
        self.apply(["kitty", "gtk"])
        self.assertFalse(os.path.exists(self.h(".config/kitty")))
        self.assertTrue(os.path.exists(self.h(".config/gtk-3.0/slate.css")))

    def test_nothing_until_switched_on(self):
        self.put(YOURS)
        before = self.tree()
        out = self.apply([])
        self.assertEqual(self.tree(), before)
        self.assertEqual(out.strip(), "")

    def test_reapplying_changes_nothing(self):
        self.put(YOURS)
        self.apply(ALL)
        log = self.manifest()
        out = self.apply(ALL)
        self.assertNotIn("updated", out)
        self.assertEqual(self.manifest(), log, "the undo log grew on a second run")

    def test_bad_colours(self):
        for key, value in (("accent", "c0ffee"), ("bg", "#12345"), ("text", "#gggggg"), ("dim", None)):
            with self.subTest(key):
                p = dict(COLOURS, on=["gtk"])
                if value is None:
                    del p[key]
                else:
                    p[key] = value
                code, out = run([sys.executable, SCRIPT, json.dumps(p)], env=self.env)
                self.assertEqual(code, 1)
                self.assertIn("missing or bad colour '%s'" % key, out)
        self.assertFalse(os.path.exists(self.h(".config/gtk-3.0")), "wrote files despite a bad colour")

    def test_usage(self):
        code, out = run([sys.executable, SCRIPT], env=self.env)
        self.assertEqual(code, 1)
        self.assertIn("Usage:", out)

    # ---- switching off ----
    def test_switching_off_restores_your_files(self):
        self.put(YOURS)
        before = self.tree()
        self.apply(ALL)
        out = self.apply([])
        for app in ALL:
            with self.subTest("said " + app):
                self.assertIn("switched off " + app, out)
        for rel, text in YOURS.items():
            with self.subTest(rel):
                self.assertEqual(self.text(rel), text)
        # Everything Slate made is gone again, folders too; only the one-off backups stay
        left = {f for f in self.tree() - before if not f.endswith(".bak-slate-theme")}
        self.assertEqual(left, set())
        self.assertEqual(self.manifest(), {})

    def test_switching_one_off(self):
        self.put(YOURS)
        self.apply(["gtk", "kitty", "foot"])
        out = self.apply(["gtk", "foot"])
        self.assertEqual(out.splitlines()[0], "switched off kitty")
        self.assertEqual(self.text(".config/kitty/kitty.conf"), YOURS[".config/kitty/kitty.conf"])
        self.assertFalse(os.path.exists(self.h(".config/kitty/themes")))
        self.assertTrue(os.path.exists(self.h(".config/foot/slate.ini")))
        self.assertEqual(sorted(self.manifest()), ["foot", "gtk"])

    def test_starting_config_removed(self):
        """With no config of yours, Slate makes a starting one, and takes it away again."""
        self.apply(["kitty", "foot", "ghostty"])
        start = self.text(".config/kitty/kitty.conf")
        with open(slate.path("shell", "data", "kitty.conf")) as f:
            self.assertEqual(start, f.read())
        self.apply([])
        for d in (".config/kitty", ".config/foot", ".config/ghostty"):
            with self.subTest(d):
                self.assertFalse(os.path.exists(self.h(d)))

    def test_edited_starting_config_kept(self):
        """A starting config you've since changed stays, minus the line pointing at Slate's theme."""
        self.apply(["kitty"])
        with open(self.h(".config/kitty/kitty.conf"), "a") as f:
            f.write("font_size 14\n")
        self.apply([])
        conf = self.text(".config/kitty/kitty.conf")
        self.assertIn("font_size 14", conf)
        self.assertIn("background_opacity          0.6", conf)
        self.assertNotIn("include themes/slate.conf", conf)
        self.assertFalse(os.path.exists(self.h(".config/kitty/themes/slate.conf")))

    def test_jsonc_key_added_then_removed(self):
        """A key Slate added to your settings (none there before) is taken out again exactly."""
        mine = "{\n    // my editor\n    \"editor.fontSize\": 14\n}\n"
        self.put({".config/Code/User/settings.json": mine})
        self.apply(["vscode"])
        self.assertIn('"workbench.colorTheme": "Slate"', self.text(".config/Code/User/settings.json"))
        self.apply([])
        self.assertEqual(self.text(".config/Code/User/settings.json"), mine)

    def test_vscode_extensions_list(self):
        """VS Code's extensions.json gets Slate's theme added, and loses it again."""
        reg = [{"identifier": {"id": "someone.other"}, "version": "2.0.0"}]
        text = json.dumps(reg, indent=4) + "\n"
        self.put({".config/Code/User/settings.json": "{}\n", ".vscode/extensions/extensions.json": text})
        self.apply(["vscode"])
        ids = [e["identifier"]["id"] for e in json.loads(self.text(".vscode/extensions/extensions.json"))]
        self.assertEqual(ids, ["someone.other", "slate.slate-theme"])
        self.apply([])
        self.assertEqual(self.text(".vscode/extensions/extensions.json"), text)

    # Known gaps in the undo (Slate bugs): see each test
    @unittest.expectedFailure
    def test_no_trailing_newline_kept(self):
        """A config whose last line has no newline gets one added by apply and switch-off
        (slate_theme's line undo always ends the file with "\n"), so it isn't put back exactly."""
        mine = "font_size 12\nmap ctrl+t new_tab"
        self.put({".config/kitty/kitty.conf": mine})
        self.apply(["kitty"])
        self.apply([])
        self.assertEqual(self.text(".config/kitty/kitty.conf"), mine)

    @unittest.expectedFailure
    def test_kdeglobals_restored_exactly(self):
        """Switching KDE off leaves a blank line at the end of kdeglobals: removing the groups
        Slate added (del_ini_key) keeps the blank line that separated them from yours."""
        mine = "[General]\nColorScheme=BreezeDark\n\n[KDE]\nSingleClick=false\n"
        self.put({".config/kdeglobals": mine})
        self.apply(["kde"])
        self.apply([])
        self.assertEqual(self.text(".config/kdeglobals"), mine)


class Apps(Case):
    """`--apps`: what Settings → App Theming lists."""
    scratch = True

    def apps(self, env):
        code, out = run([sys.executable, SCRIPT, "--apps"], env=env)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def test_shape(self):
        s = Stubs(self.h)
        apps = self.apps(dict(s.env, PATH=s.dir))
        ids = [a["id"] for a in apps]
        self.assertEqual(len(ids), len(set(ids)), "an app listed twice")
        self.assertEqual(ids[:4], ["gtk", "qt", "kde", "kitty"])
        for a in apps:
            with self.subTest(a.get("id")):
                self.assertEqual(set(a), {"id", "label", "detail", "installed"})
                self.assertRegex(a["id"], r"^[a-z]+$")
                self.assertTrue(a["label"] and a["detail"])
                self.assertIsInstance(a["installed"], bool)
        self.assertTrue(set(ALL) <= set(ids))

    def test_installed(self):
        """Nothing installed but what every desktop has; then a program, a config folder and a
        Firefox profile each count."""
        s = Stubs(self.h)
        env = dict(s.env, PATH=s.dir)
        found = lambda: sorted(a["id"] for a in self.apps(env) if a["installed"])
        self.assertEqual(found(), ["gtk", "kde"])
        s.add("kitty")
        s.add("batcat")                  # bat's name on Debian
        os.makedirs(self.h(".config", "qt6ct"))
        os.makedirs(self.h(".config", "VSCodium", "User"))
        os.makedirs(self.h(".mozilla", "firefox", "abc.default"))
        with open(self.h(".mozilla", "firefox", "profiles.ini"), "w") as f:
            f.write("[Profile0]\nPath=abc.default\n")
        self.assertEqual(found(), ["bat", "firefox", "gtk", "kde", "kitty", "qt", "vscode"])
