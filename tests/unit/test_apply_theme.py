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
    def test_cursor_theme_from_settings(self):
        """Pointer style (Settings → Input): the theme chosen reaches GTK, X11 and KDE apps,
        whatever the session's environment says; with none chosen, the session's own."""
        self.put({".config/kcminputrc": "[Mouse]\ncursorTheme=Old\n"})
        self.env["XCURSOR_THEME"] = "Slate-Cursors"
        self.apply([], cursorTheme="Bibata-Modern-Ice", cursorSize=24)
        for v in ("gtk-3.0", "gtk-4.0"):
            self.assertIn("gtk-cursor-theme-name=Bibata-Modern-Ice", self.text(".config/%s/settings.ini" % v))
            self.assertIn("gtk-cursor-theme-size=24", self.text(".config/%s/settings.ini" % v))
        self.assertIn("Inherits=Bibata-Modern-Ice", self.text(".icons/default/index.theme"))
        self.assertIn("cursorTheme=Bibata-Modern-Ice", self.text(".config/kcminputrc"))
        self.apply([], cursorTheme="")
        self.assertIn("gtk-cursor-theme-name=Slate-Cursors", self.text(".config/gtk-3.0/settings.ini"))
        self.assertIn("Inherits=Slate-Cursors", self.text(".icons/default/index.theme"))

    def test_gtk3_dialogs_leave_rounding_to_hyprland(self):
        """GTK 3's message dialogs round their own corners more than Hyprland does, and the gap
        showed what's behind the window: GTK 3's slate.css squares them (GTK 4's needn't)."""
        self.apply(["gtk"])
        self.assertIn("messagedialog.csd.background, messagedialog.csd decoration { border-radius: 0; }",
                      self.text(".config/gtk-3.0/slate.css"))
        self.assertNotIn("messagedialog.csd", self.text(".config/gtk-4.0/slate.css"))

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

    def test_no_trailing_newline_kept(self):
        """A config whose last line has no newline comes back without one (the undo used to
        always end the file with a newline)."""
        mine = "font_size 12\nmap ctrl+t new_tab"
        self.put({".config/kitty/kitty.conf": mine})
        self.apply(["kitty"])
        self.apply([])
        self.assertEqual(self.text(".config/kitty/kitty.conf"), mine)

    def test_kdeglobals_restored_exactly(self):
        """Switching KDE off puts kdeglobals back exactly (removing the groups Slate added used
        to leave the blank line before them)."""
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
                # (about, url, packages and desktop: Settings → App Theming's description,
                # website, Install and Open buttons)
                self.assertEqual(set(a), {"id", "label", "detail", "installed", "about", "url", "packages", "desktop"})
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


class DiscordFlatpak(ApplyTheme):
    """Discord from Flatpak keeps Vencord in ~/.var/app/com.discordapp.Discord/config/Vencord. Slate
    only looked in ~/.config, so the theme went where Discord never reads it and wasn't switched on."""

    def test_flatpak_vencord_themed_and_switched_on(self):
        base = ".var/app/com.discordapp.Discord/config/Vencord"
        self.put({base + "/settings/settings.json": json.dumps({"enabledThemes": [], "useQuickCss": True})})
        self.apply(["discord"])
        self.assertIn("--background-primary", self.text(base + "/themes/slate.theme.css"))
        with open(self.h(base + "/settings/settings.json")) as f:
            self.assertIn("slate.theme.css", json.load(f)["enabledThemes"])
        # and switched off again, put back as it was
        self.apply([])
        with open(self.h(base + "/settings/settings.json")) as f:
            self.assertEqual(json.load(f)["enabledThemes"], [])
        self.assertFalse(os.path.exists(self.h(base + "/themes/slate.theme.css")))

    def test_flatpak_vesktop_counts_as_installed(self):
        self.put({".var/app/dev.vencord.Vesktop/config/vesktop/settings/settings.json": "{}"})
        code, out = run([sys.executable, SCRIPT, "--apps"], env=self.env)
        self.assertEqual(code, 0, out)
        self.assertTrue(next(a for a in json.loads(out) if a["id"] == "discord")["installed"])


class OtherFlatpaks(ApplyTheme):
    """Apps installed only as Flatpaks get their theme in the Flatpak's own folders
    (~/.var/app/<id>/config or data), where they read it, not ~/.config."""

    def fp(self, app_id, rel=""):
        return os.path.join(".var/app", app_id, rel)

    def test_editors_and_viewers(self):
        cases = {
            "zed": ("dev.zed.Zed", "config/zed/.keep", "config/zed/themes/slate.json"),
            "helix": ("com.helix_editor.Helix", "config/helix/.keep", "config/helix/themes/slate.toml"),
            "vim": ("io.neovim.nvim", "config/nvim/.keep", "config/nvim/colors/slate-desktop.vim"),
            "zathura": ("org.pwmt.zathura", "config/zathura/.keep", "config/zathura/slate"),
            "wezterm": ("org.wezfurlong.wezterm", "config/wezterm/.keep", "config/wezterm/colors/slate.toml"),
            "texteditor": ("org.gnome.TextEditor", "data/.keep", "data/gtksourceview-5/styles/slate.xml"),
        }
        for app, (app_id, marker, theme) in cases.items():
            with self.subTest(app):
                self.put({self.fp(app_id, marker): ""})
                self.apply([app])
                self.assertTrue(os.path.exists(self.h(self.fp(app_id, theme))), f"no theme in {app_id}'s Flatpak")
                # and gone again when switched off
                self.apply([])
                self.assertFalse(os.path.exists(self.h(self.fp(app_id, theme))))

    def test_vscode_flatpak(self):
        self.put({self.fp("com.visualstudio.code", "config/Code/User/settings.json"): "{}\n",
                  self.fp("com.visualstudio.code", "data/vscode/extensions/.keep"): ""})
        self.apply(["vscode"])
        ext = self.fp("com.visualstudio.code", "data/vscode/extensions/slate.slate-theme-1.0.0/themes/slate.json")
        self.assertTrue(os.path.exists(self.h(ext)))
        self.assertIn('"workbench.colorTheme": "Slate"', self.text(self.fp("com.visualstudio.code", "config/Code/User/settings.json")))

    def test_firefox_flatpak(self):
        base = self.fp("org.mozilla.firefox", ".mozilla/firefox")
        self.put({base + "/profiles.ini": "[Profile0]\nPath=abc.default\n", base + "/abc.default/prefs.js": "// prefs\n"})
        self.apply(["firefox"])
        self.assertTrue(os.path.exists(self.h(base + "/abc.default/chrome/userChrome.css")))


class LostToAnUpdate(ApplyTheme):
    """Spotify and Discord are themed through a patch in the app's own files (Spicetify,
    Vencord), which an update of the app replaces: the theme went with it and nothing put it
    back (seen with Spotify, 2026-11-10). `--stale` notices; applying again restores it and
    says so, for Slate to pass on."""
    SPOTIFY = ".local/share/spotify/Apps"
    DISCORD = ".local/share/flatpak/app/com.discordapp.Discord/current/active/files/discord/resources"

    def stale(self, on):
        code, out = run([sys.executable, SCRIPT, "--stale", json.dumps(dict(COLOURS, on=on))], env=self.env)
        self.assertEqual(code, 0, out)
        return out.split()

    # ---- Spotify (Spicetify) ----
    def spicetify(self, works=True):
        """A stand-in spicetify: `backup apply` unpacks Apps/xpui.spa into Apps/xpui, as the
        real one does (or, with works=False, fails to)."""
        apps = self.h(self.SPOTIFY)
        self.put({".config/spicetify/config-xpui.ini": "[Setting]\nspotify_path = $HOME/.local/share/spotify/\ncurrent_theme = Slate\n"})
        p = os.path.join(self.s.dir, "spicetify")
        with open(p, "w") as f:
            f.write("#!%s\nimport os, sys\nopen(%r, 'a').write(' '.join(sys.argv[1:]) + '\\n')\n"
                    "if 'config' in sys.argv: print('Slate')\n"
                    "if 'backup' in sys.argv and %r:\n    os.remove(%r); os.makedirs(%r)\n"
                    % (sys.executable, os.path.join(self.h.dir, "spicetify-calls"), works,
                       os.path.join(apps, "xpui.spa"), os.path.join(apps, "xpui")))
        os.chmod(p, 0o755)

    def spotify_updated(self):
        import shutil
        shutil.rmtree(self.h(self.SPOTIFY), ignore_errors=True)
        self.put({self.SPOTIFY + "/xpui.spa": "the new version"})

    def live(self, on):
        """Applied as Slate does it (not SLATE_THEME_TEST): Spicetify is only run then. The
        session's own commands are all stand-ins that do nothing."""
        env = {k: v for k, v in self.env.items() if k != "SLATE_THEME_TEST"}
        code, out = run([sys.executable, SCRIPT, json.dumps(dict(COLOURS, on=on))], env=env)
        self.assertEqual(code, 0, out)
        return out.splitlines()

    def calls(self):
        p = os.path.join(self.h.dir, "spicetify-calls")
        if not os.path.exists(p):
            return []
        with open(p) as f:
            return f.read().splitlines()

    def test_spotify_stale_after_an_update(self):
        self.spicetify()
        self.put({self.SPOTIFY + "/xpui/index.html": "patched"})
        self.assertEqual(self.stale(["spotify"]), [])
        self.spotify_updated()
        self.assertEqual(self.stale(["spotify"]), ["spotify"])
        self.assertEqual(self.stale(["kitty"]), [], "only for apps that are themed")
        self.assertEqual(self.calls(), [], "--stale must be quick: it ran spicetify")

    def test_spotify_patched_again(self):
        self.spicetify()
        self.spotify_updated()
        out = self.live(["spotify"])
        self.assertIn("restored spotify Spotify", out)
        self.assertIn("-q -n backup apply", self.calls())
        self.assertTrue(os.path.isdir(self.h(self.SPOTIFY, "xpui")))
        self.assertEqual(self.stale(["spotify"]), [])
        # nothing more to say the next time
        self.assertFalse([l for l in self.live(["spotify"]) if l.startswith(("restored", "lost"))])

    def test_spotify_that_cannot_be_patched_is_said_once(self):
        self.spicetify(works=False)
        self.spotify_updated()
        self.assertIn("lost spotify Spotify", self.live(["spotify"]))
        self.assertFalse([l for l in self.live(["spotify"]) if l.startswith("lost")], "said again")
        self.assertEqual(self.stale(["spotify"]), [], "it would be tried again every few minutes")
        # once it works, it's put back, and a later loss is said again
        self.spicetify()
        self.assertIn("restored spotify Spotify", self.live(["spotify"]))
        self.spicetify(works=False)
        self.spotify_updated()
        self.assertIn("lost spotify Spotify", self.live(["spotify"]))

    # ---- Discord (Vencord) ----
    def vencord(self):
        """Discord from your own Flatpak with Vencord in it: a tiny app.asar that loads
        Vencord, and Discord's own beside it as _app.asar."""
        patcher = self.h(".config/Vencord/dist/patcher.js")
        self.stub = '{"files":{"index.js":{"size":54}}}require("%s"){"name":"discord","main":"index.js"}' % patcher
        self.put({".config/Vencord/dist/patcher.js": "// vencord", ".config/Vencord/settings/settings.json": "{}",
                  self.DISCORD + "/app.asar": self.stub, self.DISCORD + "/_app.asar": "discord itself " * 8000})

    def discord_updated(self):
        os.remove(self.h(self.DISCORD, "_app.asar"))
        self.put({self.DISCORD + "/app.asar": "the new discord " * 8000})

    def test_vencord_put_back(self):
        self.vencord()
        self.assertFalse([l for l in self.apply(["discord"]).splitlines() if l.startswith(("restored", "lost"))])
        self.assertEqual(self.stale(["discord"]), [])
        self.discord_updated()
        self.assertEqual(self.stale(["discord"]), ["discord"])
        self.assertIn("restored discord Discord", self.apply(["discord"]).splitlines())
        self.assertEqual(self.text(self.DISCORD + "/app.asar"), self.stub)
        self.assertTrue(self.text(self.DISCORD + "/_app.asar").startswith("the new discord"))
        self.assertEqual(self.stale(["discord"]), [])

    def test_vencord_itself_gone(self):
        """What the saved app.asar loads isn't there any more: putting it back would stop
        Discord starting, so it's left alone and said once."""
        self.vencord()
        self.apply(["discord"])
        self.discord_updated()
        os.remove(self.h(".config/Vencord/dist/patcher.js"))
        self.assertIn("lost discord Discord", self.apply(["discord"]).splitlines())
        self.assertTrue(self.text(self.DISCORD + "/app.asar").startswith("the new discord"), "Discord was changed")
        self.assertFalse(os.path.exists(self.h(self.DISCORD, "_app.asar")))
        self.assertFalse([l for l in self.apply(["discord"]).splitlines() if l.startswith("lost")], "said again")

    def test_discord_without_vencord_left_alone(self):
        """Vesktop users (Vencord built in) with plain Discord installed too: never patched."""
        self.put({".config/vesktop/settings/settings.json": "{}", self.DISCORD + "/app.asar": "plain discord " * 8000})
        self.assertEqual(self.stale(["discord"]), [])
        self.assertFalse([l for l in self.apply(["discord"]).splitlines() if l.startswith(("restored", "lost"))])
        self.assertTrue(self.text(self.DISCORD + "/app.asar").startswith("plain discord"))


class FlatpakAndSnapGtk(ApplyTheme):
    """Flatpak and Snap apps can't see ~/.config, so GTK's and KDE's theme never reached them.
    Flatpak apps are given read-only access to it through the overrides every one of them
    gets (`flatpak override --user`'s file, ~/.local/share/flatpak/overrides/global); each
    snap gets GTK's theme files in its own ~/snap/<name>/current/.config. All undone when
    switched off."""
    OVERRIDES = ".local/share/flatpak/overrides/global"
    OURS = ["xdg-config/gtk-3.0:ro", "xdg-config/gtk-4.0:ro"]

    def filesystems(self, rel=OVERRIDES):
        for line in self.text(rel).splitlines():
            if line.startswith("filesystems="):
                return [i for i in line.split("=", 1)[1].split(";") if i]
        return []

    def test_flatpak_apps_read_your_gtk_and_kde_settings(self):
        self.s.add("flatpak")
        yours = "[Context]\nfilesystems=xdg-download;\n\n[Environment]\nFOO=1\n"
        self.put({self.OVERRIDES: yours})
        self.apply(["gtk", "kde"])
        self.assertEqual(self.filesystems(), ["xdg-download"] + self.OURS + ["xdg-config/kdeglobals:ro"])
        self.assertIn("[Environment]\nFOO=1", self.text(self.OVERRIDES))
        self.assertFalse(os.path.exists(self.h(self.OVERRIDES + ".bak-slate-theme")),
                         "a stray file in Flatpak's overrides")
        self.apply(["gtk", "kde"])
        self.assertEqual(len(self.filesystems()), 4, "added twice")
        self.apply(["kde"])
        self.assertEqual(self.filesystems(), ["xdg-download", "xdg-config/kdeglobals:ro"])
        self.apply([])
        self.assertEqual(self.text(self.OVERRIDES), yours)

    def test_overrides_made_and_removed(self):
        self.s.add("flatpak")
        self.apply(["gtk"])
        self.assertEqual(self.filesystems(), self.OURS)
        self.apply([])
        self.assertFalse(os.path.exists(self.h(".local/share/flatpak")), "Slate's overrides left behind")

    def test_your_own_choice_kept(self):
        """Access you've given already (even read-write), or refused, is left as it is."""
        self.s.add("flatpak")
        yours = "[Context]\nfilesystems=xdg-config/gtk-3.0;!xdg-config/gtk-4.0;\n"
        self.put({self.OVERRIDES: yours})
        self.apply(["gtk"])
        self.assertEqual(self.text(self.OVERRIDES), yours)
        self.apply([])
        self.assertEqual(self.text(self.OVERRIDES), yours)

    def test_flatpak_user_dir(self):
        self.s.add("flatpak")
        self.env["FLATPAK_USER_DIR"] = self.h("elsewhere", "flatpak")
        self.apply(["gtk"])
        self.assertEqual(self.filesystems("elsewhere/flatpak/overrides/global"), self.OURS)

    def test_without_flatpak(self):
        self.apply(["gtk", "kde"])
        self.assertFalse(os.path.exists(self.h(".local/share/flatpak")))

    def test_snaps(self):
        os.makedirs(self.h("snap", "firefox", "4793", ".config"))
        os.symlink("4793", self.h("snap", "firefox", "current"))
        os.makedirs(self.h("snap", "cli-tool", "12"))          # nothing of GTK's: no .config
        os.symlink("12", self.h("snap", "cli-tool", "current"))
        before = self.tree()
        self.apply(["gtk"])
        for v in ("3", "4"):
            d = "snap/firefox/4793/.config/gtk-%s.0/" % v
            self.assertIn("@define-color accent_color %s;" % ACCENT, self.text(d + "slate.css"))
            self.assertEqual(self.text(d + "gtk.css"), '@import url("slate.css");\n')
        self.assertFalse(os.path.exists(self.h("snap", "cli-tool", "12", ".config")))
        self.apply([])
        self.assertEqual({p for p in self.tree() if p.startswith("snap/")}, {p for p in before if p.startswith("snap/")})
        self.assertFalse(os.path.exists(self.h("snap", "firefox", "4793", ".config", "gtk-3.0")))


class LinkedConfigs(ApplyTheme):
    """Configs that are links: a dotfile manager's (GNU Stow) stays a link, changed where it
    leads, where Slate used to replace the link with a file; Home Manager's (read-only, in the
    Nix store) is left alone, where Slate's file in its way stopped `home-manager switch`."""

    def test_link_kept(self):
        self.put({"dotfiles/gtk.css": "window { padding: 0; }\n"})
        os.makedirs(self.h(".config", "gtk-3.0"))
        os.symlink(self.h("dotfiles", "gtk.css"), self.h(".config", "gtk-3.0", "gtk.css"))
        self.apply(["gtk"])
        self.assertTrue(os.path.islink(self.h(".config", "gtk-3.0", "gtk.css")))
        self.assertIn('@import url("slate.css");', self.text("dotfiles/gtk.css"))
        self.apply([])
        self.assertTrue(os.path.islink(self.h(".config", "gtk-3.0", "gtk.css")))
        self.assertEqual(self.text("dotfiles/gtk.css"), "window { padding: 0; }\n")

    @unittest.skipIf(os.geteuid() == 0, "root can write anything")
    def test_read_only_left_alone(self):
        self.put({"store/gtk.css": "window { padding: 0; }\n"})
        os.chmod(self.h("store", "gtk.css"), 0o444)
        os.chmod(self.h("store"), 0o555)
        self.addCleanup(os.chmod, self.h("store"), 0o755)
        os.makedirs(self.h(".config", "gtk-3.0"))
        os.symlink(self.h("store", "gtk.css"), self.h(".config", "gtk-3.0", "gtk.css"))
        out = self.apply(["gtk"])
        self.assertIn("gtk-3.0/gtk.css is read-only", out)
        self.assertEqual(self.text(".config/gtk-3.0/gtk.css"), "window { padding: 0; }\n")
        self.assertTrue(os.path.islink(self.h(".config", "gtk-3.0", "gtk.css")))
        self.assertFalse(os.path.exists(self.h(".config", "gtk-3.0", "gtk.css.bak-slate-theme")))
        # the rest of GTK's theme still goes on
        self.assertIn('@import url("slate.css");', self.text(".config/gtk-4.0/gtk.css"))
        self.apply([])
        self.assertEqual(self.text(".config/gtk-3.0/gtk.css"), "window { padding: 0; }\n")
