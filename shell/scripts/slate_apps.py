"""The apps Slate themes (Settings → App Theming). Each entry:
  id, label, detail     shown in Settings
  installed()           whether the app is on this computer
  apply(ctx)            writes its theme from ctx.c (Slate's colours) through ctx, which
                        records every change so switching the app off undoes it
  reload(ctx)           optional: make running copies pick up the new colours
Only installed apps that aren't switched off are themed; switching one off reverses what
Slate did to it (slate_theme.Ctx.undo)."""
import colorsys
import glob
import json
import os
import re
import shutil
import time

from slate_theme import (CFG, DATA, GEN, HOME, SHELL_DIR, STATE, bare, first_existing, have, mix,
                         read, run, run_out, signal_all, touched)

APPS = []

def app(id, label, detail, installed):
    def deco(fn):
        APPS.append({"id": id, "label": label, "detail": detail, "installed": installed, "apply": fn, "reload": None,
                     "stale": None})
        return fn
    return deco

# Two apps are themed through a patch in the app's own files (Spotify by Spicetify, Discord by
# Vencord), and an update of the app replaces those files: the patch, and Slate's theme with it,
# is gone. Each has a quick check for that (`stale`: apply-theme.py --stale, which Slate runs
# every few minutes while the app's themed), and its next apply puts the patch back, noting
# here what happened, for Slate to tell you: ("restored" | "lost", app id, app name).
NOTES = []

def stale(id):
    def deco(fn):
        next(a for a in APPS if a["id"] == id)["stale"] = fn
        return fn
    return deco

def reloads(id):
    def deco(fn):
        next(a for a in APPS if a["id"] == id)["reload"] = fn
        return fn
    return deco

def cfg(*p):
    return os.path.join(CFG, *p)

def isdir(*p):
    return os.path.isdir(os.path.join(*p))

# Flatpak builds keep their config and data in ~/.var/app/<id>/{config,data}, not ~/.config
def flatpak(app_id, *p):
    """That path inside the app's Flatpak folder, or None when it has none (not installed, or
    never started)"""
    root = os.path.join(HOME, ".var", "app", app_id)
    return os.path.join(root, *p) if os.path.isdir(root) else None


def config_dirs(native, folder, app_id):
    """Where an app's config folder is: ~/.config/<folder> when it's installed natively
    (native: true), and inside its Flatpak when that's there"""
    out = [cfg(folder)] if native else []
    fp = flatpak(app_id, "config", folder)
    return out + ([fp] if fp else [])


# Flatpak apps read GTK's and KDE's settings from inside their sandbox, so they're given your
# own, read-only: an entry in the overrides every Flatpak app gets, as
# `flatpak override --user --filesystem=<path>:ro` writes it, taken out again on undo (it's
# written here rather than with that command, which can only add a "not" for an entry, never
# take one away). One you've already given, or refused ("!<path>"), is left as it is.
def flatpak_overrides():
    """Flatpak's overrides for all your apps, or None without Flatpak"""
    if not have("flatpak"):
        return None
    return os.path.join(os.environ.get("FLATPAK_USER_DIR") or os.path.join(DATA, "flatpak"), "overrides", "global")

def flatpak_share(ctx, *paths):
    f = flatpak_overrides()
    if not f:
        return
    for p in paths:
        ctx.listitem(f, "Context", "filesystems", p + ":ro",
                     same=lambda x, p=p: re.sub(r":(ro|rw|create)$", "", x.lstrip("!")) == p)


# Snap apps keep their settings in ~/snap/<name>/current/.config (that's their ~/.config) and
# can't read yours, so GTK's theme files go in each one's own
def snap_configs():
    return sorted(glob.glob(os.path.join(HOME, "snap", "*", "current", ".config")))


def starting(name):
    """Slate's starting config for an app (shell/data/<name>)"""
    return read(os.path.join(SHELL_DIR, "data", name)) or ""


# ==== Desktop toolkits ======================================================================
def gtk_css(c, version):
    head = c["surface"] if version == 3 else c["bg"]
    defs = [
        ("accent_color", c["accent"]), ("accent_bg_color", c["accent"]), ("accent_fg_color", c["accentText"]),
        None,
        ("destructive_bg_color", c["error"]), ("destructive_fg_color", c["accentText"]),
        None,
        ("error_bg_color", c["error"]), ("error_fg_color", c["accentText"]),
        None,
        ("window_bg_color", c["bg"]), ("window_fg_color", c["text"]),
        None,
        ("view_bg_color", c["bg"]), ("view_fg_color", c["text"]),
        None,
        ("headerbar_bg_color", head), ("headerbar_fg_color", c["text"]), ("headerbar_backdrop_color", "@window_bg_color"),
        None,
        ("popover_bg_color", c["surface"]), ("popover_fg_color", c["text"]),
        None,
        ("card_bg_color", c["surface"]), ("card_fg_color", c["text"]),
        None,
        ("dialog_bg_color", c["bg"]), ("dialog_fg_color", c["text"]),
        None,
        ("overview_bg_color", c["surface"]), ("overview_fg_color", c["text"]),
        None,
        ("sidebar_bg_color", c["surface"]), ("sidebar_fg_color", c["text"]),
        ("sidebar_backdrop_color", "@window_bg_color"), ("sidebar_border_color", "@window_bg_color"),
        None,
        ("secondary_sidebar_bg_color", c["bg"]), ("secondary_sidebar_fg_color", c["text"]),
    ]
    out = ["/*", "* GTK Colors (GTK%d)" % version, "* " + GEN, "*/", ""]
    out += ["@define-color %s %s;" % d if d else "" for d in defs]
    out += ["", "/* Focused selection states */",
            "@define-color theme_selected_bg_color @accent_bg_color;",
            "@define-color theme_selected_fg_color @accent_fg_color;", "",
            "/* Backdrop/unfocused states */",
            "@define-color theme_unfocused_fg_color @window_fg_color;",
            "@define-color theme_unfocused_text_color @view_fg_color;",
            "@define-color theme_unfocused_bg_color @window_bg_color;",
            "@define-color theme_unfocused_base_color @window_bg_color;",
            "@define-color theme_unfocused_selected_bg_color @accent_bg_color;",
            "@define-color theme_unfocused_selected_fg_color @accent_fg_color;"]
    if version == 4:
        out += ["", ":root {"]
        for d in defs:
            out.append("    --%s: %s;" % (d[0].replace("_", "-"), d[1]) if d else "")
        out += ["    --error-color: %s;" % c["error"],
                "    --warning-bg-color: %s;" % mix(c["surface"], c["tertiary"], 0.25),
                "    --warning-fg-color: %s;" % c["tertiary"],
                "    --warning-color: %s;" % c["tertiary"],
                "    --success-color: %s;" % c["secondary"],
                "    --success-bg-color: %s;" % mix(c["surface"], c["secondary"], 0.15),
                "    --success-fg-color: %s;" % c["secondary"],
                "    --shade-color: rgba(0, 0, 0, %s);" % ("0.07" if c["light"] else "0.36"),
                "}"]
    if version == 3:
        # Hyprland rounds and frames every window itself. GTK 3's message dialogs (an app asking
        # whether to save, say) round their own corners too, more than Hyprland does, and the
        # gap between the two curves showed what's behind the window at its bottom corners
        out += ["", "/* Hyprland rounds the window: no rounding of GTK's own inside it */",
                "messagedialog.csd.background, messagedialog.csd decoration { border-radius: 0; }"]
    return "\n".join(out) + "\n"

@app("gtk", "GTK apps", "Files, Text Editor, Calculator and other GNOME and GTK apps, Flatpak and Snap ones too", lambda: True)
def gtk(ctx):
    c = ctx.c
    for base in [CFG] + snap_configs():
        for v in (3, 4):
            ctx.file(os.path.join(base, "gtk-%d.0" % v, "slate.css"), gtk_css(c, v))
            ctx.line(os.path.join(base, "gtk-%d.0" % v, "gtk.css"), '@import url("slate.css");')   # last, so its colours win
    flatpak_share(ctx, "xdg-config/gtk-3.0", "xdg-config/gtk-4.0")
    dark = not c["light"]
    ctx.ini(cfg("gtk-3.0", "settings.ini"), "Settings", "gtk-application-prefer-dark-theme", "1" if dark else "0")
    ctx.gsetting("org.gnome.desktop.interface", "color-scheme", "prefer-dark" if dark else "prefer-light")
    # adw-gtk3 (libadwaita's look for GTK 3 apps) when it's installed: not every distro packages
    # it, and naming a theme that isn't there leaves GTK 3 apps unstyled. Without it they keep
    # Adwaita, still dark through prefer-dark and Slate's colours through gtk.css
    theme = "adw-gtk3-dark" if dark else "adw-gtk3"
    if theme_installed(theme):
        ctx.gsetting("org.gnome.desktop.interface", "gtk-theme", theme)

def theme_installed(name):
    """A GTK theme by name in ~/.themes or any data folder's themes/ (XDG_DATA_HOME, XDG_DATA_DIRS)."""
    dirs = [os.path.join(HOME, ".themes"), os.path.join(DATA, "themes")] + [
        os.path.join(d, "themes") for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if d]
    return any(os.path.isdir(os.path.join(d, name)) for d in dirs)

@reloads("gtk")
def gtk_reload(ctx):
    if not (touched("gtk-3.0") or touched("gtk-4.0")):
        return
    # GTK apps re-read their theme and gtk.css when the theme name changes: switch away and back
    cur = (run_out(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"]) or "").strip().strip("'")
    if cur:
        run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", "Adwaita" if cur != "Adwaita" else "HighContrast"])
        time.sleep(0.3)
        run(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", cur])
    if touched("gtk-4.0"):
        # GTK4/libadwaita apps read colours at start; Nautilus keeps running with no windows,
        # so restart it once they're closed (scripts/refresh-gtk-apps.sh)
        flag = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "slate", "gtk4-refresh")
        os.makedirs(os.path.dirname(flag), exist_ok=True)
        open(flag, "w").close()
        run([os.path.join(SHELL_DIR, "scripts", "refresh-gtk-apps.sh")])


# Qt 6 apps take their look from qt6ct, Qt 5 apps from qt5ct (when QT_QPA_PLATFORMTHEME names
# it: "qt5ct" reaches both, as qt6ct answers to that name too). Each is themed when it's here.
# Apps styled with Kvantum keep their Kvantum theme: it draws with its own pictures and sets its
# own colours over the palette, so Slate leaves your choice of theme alone.
QT_CT = ("qt6ct", "qt5ct")

def qt_ct_here(name):
    return have(name) or isdir(CFG, name)

@app("qt", "Qt apps", "Apps that use qt6ct or qt5ct for their look (a Kvantum theme keeps its own)",
     lambda: any(qt_ct_here(n) for n in QT_CT))
def qt(ctx):
    c = ctx.c
    # windowText,button,light,midlight,dark,mid,text,brightText,buttonText,base,window,shadow,
    # highlight,highlightedText,link,linkVisited,alternateBase,noRole,toolTipBase,toolTipText,
    # placeholderText,accent
    roles = [c["text"], c["bg"], "#ffffff", "#cacaca", "#9f9f9f", "#b8b8b8", c["text"], "#ffffff",
             c["text"], c["bg"], c["bg"], c["shadow"], c["selection"], c["accent"], c["secondary"],
             c["accent"], c["surface"], c["bg"], c["surface"], c["text"], c["text"] if not c["light"] else c["dim"], c["accent"]]
    names = ("windowText,button,light,midlight,dark,mid,text,brightText,buttonText,base,window,shadow,highlight,"
             "highlightedText,link,linkVisited,alternateBase,noRole,toolTipBase,toolTipText,placeholderText,accent")
    for name in QT_CT:
        if not qt_ct_here(name):
            continue
        # Qt 5 has no accent role: qt5ct's own schemes have the first 21
        n = 22 if name == "qt6ct" else 21
        row = ", ".join(roles[:n])
        path = cfg(name, "colors", "slate.conf")
        ctx.file(path, "[ColorScheme]\n# %s\n# %s\nactive_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n"
                 % (GEN, ",".join(names.split(",")[:n]), row, row, row))
        conf = cfg(name, name + ".conf")
        if os.path.exists(conf):
            ctx.ini_many(conf, [("Appearance", "color_scheme_path", path), ("Appearance", "custom_palette", "true")])

@reloads("qt")
def qt_reload(ctx):
    for name in QT_CT:
        conf = cfg(name, name + ".conf")
        if touched(name) and os.path.exists(conf):
            # qt6ct and qt5ct apps watch the folder: replace the .conf (same contents) to nudge them
            t = read(conf)
            tmp = conf + ".slate-tmp"
            with open(tmp, "w") as f:
                f.write(t)
            os.replace(tmp, conf)


def kde_groups(c):
    a, txt, var = c["accent"], c["text"], c["onVariant"]
    def group(bg, alt, fg=None, deco_hover=None, active=None):
        return {
            "BackgroundAlternate": alt, "BackgroundNormal": bg,
            "DecorationFocus": a, "DecorationHover": deco_hover or a,
            "ForegroundActive": active or a, "ForegroundInactive": var,
            "ForegroundLink": c["secondary"], "ForegroundNegative": c["error"],
            "ForegroundNeutral": c["tertiary"], "ForegroundNormal": fg or txt,
            "ForegroundPositive": c["tertiary"], "ForegroundVisited": c["secondary"],
        }
    sel = group(a, c["between"], fg=c["accentText"], active=c["accentText"])
    sel["ForegroundNegative"], sel["ForegroundNeutral"], sel["ForegroundPositive"] = c["onNegative"], c["onPositive"], c["onPositive"]
    return [
        ("ColorEffects:Disabled", {"Color": c["disabled"], "ColorAmount": "0", "ColorEffect": "0", "ContrastAmount": "0.65",
                                   "ContrastEffect": "1", "IntensityAmount": "0.1", "IntensityEffect": "2"}),
        ("ColorEffects:Inactive", {"ChangeSelectionColor": "true", "Color": c["surface"], "ColorAmount": "0.025",
                                   "ColorEffect": "2", "ContrastAmount": "0.1", "ContrastEffect": "2", "Enable": "false",
                                   "IntensityAmount": "0", "IntensityEffect": "0"}),
        ("Colors:Button", group(c["surfaceHigh"], c["between"])),
        ("Colors:Complementary", group(c["bg"], c["between"], fg=a)),
        ("Colors:Header", group(c["surface"], c["bg"])),
        ("Colors:Header][Inactive", group(c["bg"], c["surface"])),
        ("Colors:Selection", sel),
        ("Colors:Tooltip", group(c["surface"], c["bg"])),
        ("Colors:View", group(c["bg"], c["surface"], deco_hover=c["accentText"])),
        ("Colors:Window", group(c["surface"], c["selection"])),
        ("WM", {"activeBackground": c["selection"], "activeBlend": a, "activeForeground": a,
                "inactiveBackground": c["bg"], "inactiveBlend": var, "inactiveForeground": var}),
    ]

def kde_value(v):
    if isinstance(v, str) and v.startswith("#"):
        r, g, b = (int(v[i:i + 2], 16) for i in (1, 3, 5))
        return "%d,%d,%d" % (r, g, b)
    return v

@app("kde", "KDE apps", "Dolphin, Kate and other KDE apps (kdeglobals), Flatpak ones too", lambda: True)
def kde(ctx):
    groups = kde_groups(ctx.c)
    out = ["[KDE]", "contrast=4", "", "[General]", "ColorScheme=slate", "Name=slate", ""]
    for name, keys in groups:
        out.append("[%s]" % name)
        out += ["%s=%s" % (k, kde_value(v)) for k, v in keys.items()]
        out.append("")
    ctx.file(os.path.join(DATA, "color-schemes", "slate.colors"), "\n".join(out))
    items = [("General", "ColorScheme", "slate"), ("General", "Name", "slate")]
    items += [(name, k, kde_value(v)) for name, keys in groups for k, v in keys.items()]
    ctx.ini_many(cfg("kdeglobals"), items)
    flatpak_share(ctx, "xdg-config/kdeglobals")

@reloads("kde")
def kde_reload(ctx):
    if touched("color-schemes") or touched("kdeglobals"):
        run(["dbus-send", "--session", "--type=signal", "/KGlobalSettings",
             "org.kde.KGlobalSettings.notifyChange", "int32:0", "int32:0"])


# ==== Terminals =============================================================================
@app("kitty", "kitty", "Colours, plus a see-through starting config if you have none", lambda: have("kitty"))
def kitty(ctx):
    c = ctx.c
    lines = ["# " + GEN]
    lines += ["color%d %s" % (i, h) for i, h in enumerate(c["ansi"] + c["ansiBright"])]
    lines += ["",
              "cursor                %s" % c["text"],
              "cursor_text_color     %s" % c["bg"],
              "background            %s" % c["bg"],
              "foreground            %s" % c["text"],
              "selection_foreground  %s" % c["text"],
              "selection_background  %s" % (c["surface"] if not c["light"] else c["selection"]),
              "active_border_color   %s" % c["accent"],
              "inactive_border_color %s" % c["surface"],
              "url_color             %s" % c["accent"],
              "",
              "active_tab_foreground   %s" % c["accentText"],
              "active_tab_background   %s" % c["accent"],
              "inactive_tab_foreground %s" % c["onVariant"],
              "inactive_tab_background %s" % c["surface"],
              "cursor_trail_color      %s" % c["onVariant"]]
    if c["light"]:
        # A see-through light background lets the wallpaper turn it mid-grey, and kitty's
        # default 40% "dim" text then all but vanishes: keep it nearly solid, dim text firmer
        lines += ["",
                  "background_opacity      0.92",
                  "dim_opacity             0.7"]
    ctx.file(cfg("kitty", "themes", "slate.conf"), "\n".join(lines) + "\n")
    conf = cfg("kitty", "kitty.conf")
    ctx.start(conf, starting("kitty.conf"))
    ctx.line(conf, "include themes/slate.conf")

@reloads("kitty")
def kitty_reload(ctx):
    if touched("kitty"):
        signal_all("kitty", "USR1")          # kitty re-reads its config on SIGUSR1


@app("alacritty", "Alacritty", "Colours, plus a see-through starting config if you have none", lambda: have("alacritty"))
def alacritty(ctx):
    c = ctx.c
    q = lambda h: "'%s'" % h
    names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    on = c["surface"] if not c["light"] else c["bg"]
    out = ["# " + GEN, "",
           "[colors.primary]", "background = %s" % q(c["bg"]), "foreground = %s" % q(c["text"]), "",
           "[colors.cursor]", "text = %s" % q(c["bg"]), "cursor = %s" % q(c["text"]), "",
           "[colors.vi_mode_cursor]", "text = %s" % q(c["bg"]), "cursor = %s" % q(c["accent"]), "",
           "[colors.search.matches]", "foreground = %s" % q(on), "background = %s" % q(c["tertiary"]), "",
           "[colors.search.focused_match]", "foreground = %s" % q(on), "background = %s" % q(c["accent"]), "",
           "[colors.footer_bar]", "foreground = %s" % q(on), "background = %s" % q(mix(c["text"], c["dim"], 0.12)), "",
           "[colors.hints.start]", "foreground = %s" % q(on), "background = %s" % q(c["secondary"]), "",
           "[colors.hints.end]", "foreground = %s" % q(on), "background = %s" % q(c["secondary"]), "",
           "[colors.selection]", "text = %s" % q(c["text"]), "background = %s" % q(c["surface"] if not c["light"] else c["selection"]), ""]
    for section, cols in (("normal", c["ansi"]), ("bright", c["ansiBright"]), ("dim", c["ansi"])):
        out.append("[colors.%s]" % section)
        out += ["%-7s = %s" % (n, q(h)) for n, h in zip(names, cols)]
        out.append("")
    ctx.file(cfg("alacritty", "themes", "slate.toml"), "\n".join(out))
    conf = cfg("alacritty", "alacritty.toml")
    ctx.start(conf, starting("alacritty.toml"))
    path = '"~/.config/alacritty/themes/slate.toml"'
    t = read(conf) or ""
    if "themes/slate.toml" in t:
        return
    m = re.search(r"^import[ \t]*=[ \t]*\[(.*)\][ \t]*$", t, flags=re.M)
    if m:       # add to your import list (one line)
        inner = m.group(1).strip()
        ctx.replace(conf, r"^import[ \t]*=[ \t]*\[.*\][ \t]*$", "import = [%s%s]" % (inner + ", " if inner else "", path))
    elif re.search(r"^\[general\][ \t]*$", t, flags=re.M):
        ctx.replace(conf, r"^\[general\][ \t]*$", "[general]\nimport = [%s]" % path)
    else:
        ctx.block(conf, "[general]\nimport = [%s]\n\n" % path, top=True)


@app("ghostty", "Ghostty", "Colours, plus a see-through starting config if you have none", lambda: have("ghostty"))
def ghostty(ctx):
    c = ctx.c
    out = ["# " + GEN]
    out += ["palette = %d=%s" % (i, h) for i, h in enumerate(c["ansi"] + c["ansiBright"])]
    out += ["background = %s" % c["bg"], "foreground = %s" % c["text"],
            "cursor-color = %s" % c["text"], "cursor-text = %s" % c["bg"],
            "selection-background = %s" % (c["surface"] if not c["light"] else c["selection"]),
            "selection-foreground = %s" % c["text"]]
    ctx.file(cfg("ghostty", "themes", "slate"), "\n".join(out) + "\n")
    conf = first_existing(cfg("ghostty", "config.ghostty"), cfg("ghostty", "config")) or cfg("ghostty", "config")
    ctx.start(conf, starting("ghostty.conf"))
    ctx.line(conf, "theme = slate")

@reloads("ghostty")
def ghostty_reload(ctx):
    if touched("ghostty"):
        signal_all("ghostty", "USR2")        # Ghostty reloads its config on SIGUSR2


@app("foot", "foot", "Colours, plus a see-through starting config if you have none", lambda: have("foot"))
def foot(ctx):
    c = ctx.c
    out = ["# " + GEN, "[colors]", "background=%s" % bare(c["bg"]), "foreground=%s" % bare(c["text"]),
           "selection-background=%s" % bare(c["surface"] if not c["light"] else c["selection"]),
           "selection-foreground=%s" % bare(c["text"])]
    out += ["regular%d=%s" % (i, bare(h)) for i, h in enumerate(c["ansi"])]
    out += ["bright%d=%s" % (i, bare(h)) for i, h in enumerate(c["ansiBright"])]
    ctx.file(cfg("foot", "slate.ini"), "\n".join(out) + "\n")
    conf = cfg("foot", "foot.ini")
    ctx.start(conf, starting("foot.ini"))
    ctx.line(conf, "include=~/.config/foot/slate.ini", top=True)    # before any [section]


def wezterm_into(ctx, d, native):
    c = ctx.c
    q = lambda h: '"%s"' % h
    out = ["# " + GEN, "[colors]", "foreground = %s" % q(c["text"]), "background = %s" % q(c["bg"]),
           "cursor_bg = %s" % q(c["text"]), "cursor_fg = %s" % q(c["bg"]), "cursor_border = %s" % q(c["text"]),
           "selection_bg = %s" % q(c["surface"] if not c["light"] else c["selection"]), "selection_fg = %s" % q(c["text"]),
           "ansi = [%s]" % ", ".join(q(h) for h in c["ansi"]),
           "brights = [%s]" % ", ".join(q(h) for h in c["ansiBright"]),
           "", "[metadata]", 'name = "Slate"']
    ctx.file(os.path.join(d, "colors", "slate.toml"), "\n".join(out) + "\n")
    if not first_existing(os.path.join(d, "wezterm.lua"), *([os.path.join(HOME, ".wezterm.lua")] if native else [])):
        ctx.start(os.path.join(d, "wezterm.lua"), starting("wezterm.lua"))




@app("wezterm", "WezTerm", "A Slate colour scheme (pick \"Slate\" in your config); a starting config if you have none",
     lambda: have("wezterm") or flatpak("org.wezfurlong.wezterm") is not None)
def wezterm(ctx):
    if have("wezterm"):
        wezterm_into(ctx, cfg("wezterm"), True)
    fp = flatpak("org.wezfurlong.wezterm", "config", "wezterm")
    if fp:
        wezterm_into(ctx, fp, False)
@app("btop", "btop", "The system monitor's colours", lambda: have("btop"))
def btop(ctx):
    c = ctx.c
    a, s, t = c["accent"], c["secondary"], c["tertiary"]
    keys = [("main_bg", c["bg"]), ("main_fg", c["text"]), ("title", a), ("hi_fg", t),
            ("selected_bg", c["selectedBg"]), ("selected_fg", c["text"]), ("inactive_fg", c["onVariant"]),
            ("proc_misc", s), ("cpu_box", c["box"]), ("mem_box", c["box"]), ("net_box", c["box"]),
            ("proc_box", c["box"]), ("div_line", c["divider"])]
    for g in ("temp", "cpu", "free", "cached", "available", "used", "download", "upload"):
        keys += [(g + "_start", a), (g + "_mid", s), (g + "_end", t)]
    ctx.file(cfg("btop", "themes", "slate.theme"), "# %s\n\n" % GEN + "\n".join('theme[%s]="%s"' % kv for kv in keys) + "\n")
    ctx.replace(cfg("btop", "btop.conf"), r"^color_theme[ \t]*=.*$", 'color_theme = "slate"')

@reloads("btop")
def btop_reload(ctx):
    if touched("btop"):
        signal_all("btop", "USR2")           # btop re-reads its config (and theme) on SIGUSR2


# ==== Code editors ==========================================================================
@app("texteditor", "GNOME Text Editor", "A Slate colour scheme, used unless you've picked another",
     lambda: have("gnome-text-editor") or flatpak("org.gnome.TextEditor") is not None)
def text_editor(ctx):
    c, s = ctx.c, ctx.c["syn"]
    bg, fg, acc, dim = c["bg"], c["text"], c["accent"], c["dim"]
    cur = c["currentLine"]
    styles = [
        ("text", fg, bg, ""), ("selection", fg, c["selection"], ""),
        ("selection-unfocused", None, c["surface"], ""), ("cursor", acc, None, ""),
        ("current-line", None, cur, ""), ("line-numbers", dim, bg, ""),
        ("current-line-number", fg, cur, ""), ("right-margin", c["divider"], None, ""),
        ("draw-spaces", c["box"], None, ""), ("background-pattern", None, c["between"], ""),
        ("bracket-match", fg, c["selection"], ' bold="true"'), ("bracket-mismatch", c["red"], None, ' underline="error"'),
        ("search-match", c["accentText"], acc, ""),
        ("def:comment", s["comment"], None, ' italic="true"'), ("def:shebang", dim, None, ' bold="true"'),
        ("def:doc-comment-element", dim, None, ' bold="true"'),
        ("def:keyword", s["keyword"], None, ' bold="true"'), ("def:statement", s["keyword"], None, ""),
        ("def:type", s["type"], None, ""), ("def:function", s["function"], None, ""),
        ("def:identifier", fg, None, ""), ("def:builtin", s["constant"], None, ""),
        ("def:constant", s["constant"], None, ""), ("def:boolean", s["constant"], None, ""),
        ("def:number", s["number"], None, ""), ("def:string", s["string"], None, ""),
        ("def:special-char", s["escape"], None, ""), ("def:preprocessor", s["constant"], None, ""),
        ("def:operator", s["operator"], None, ""), ("def:error", c["red"], None, ' underline="error"'),
        ("def:warning", c["yellow"], None, ' underline="error"'), ("def:note", c["accentText"], c["yellow"], ' bold="true"'),
        ("def:net-address", acc, None, ' underline="single"'),
        ("def:heading", s["heading"], None, ' bold="true"'), ("def:emphasis", None, None, ' italic="true"'),
        ("def:strong-emphasis", None, None, ' bold="true"'), ("def:inline-code", s["string"], None, ""),
        ("def:preformatted-section", s["string"], None, ""), ("def:list-marker", c["yellow"], None, ' bold="true"'),
        ("def:link-text", acc, None, ""), ("def:link-destination", dim, None, ' underline="single"'),
        ("def:link-symbol", dim, None, ""), ("def:insertion", c["green"], None, ""),
        ("def:deletion", c["red"], None, ""), ("diff:location", c["secondary"], None, ' bold="true"'),
    ]
    rows = []
    for name, f, b, extra in styles:
        attrs = ('' if f is None else ' foreground="%s"' % f) + ('' if b is None else ' background="%s"' % b) + extra
        rows.append('  <style name="%s"%s/>' % (name, attrs))
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!-- %s -->\n'
           '<style-scheme id="slate" name="Slate" version="1.0">\n  <author>Slate</author>\n'
           "  <description>Slate's colours, following its light or dark theme</description>\n"
           % GEN + "\n".join(rows) + "\n</style-scheme>\n")
    if have("gnome-text-editor"):
        ctx.file(os.path.join(DATA, "gtksourceview-5", "styles", "slate.xml"), xml)
    # The Flatpak reads its style schemes from its own data folder (its settings are your desktop's)
    fp = flatpak("org.gnome.TextEditor", "data")
    if fp:
        ctx.file(os.path.join(fp, "gtksourceview-5", "styles", "slate.xml"), xml)
    ctx.gsetting("org.gnome.TextEditor", "style-scheme", "slate",
                 only_if=("", "Adwaita", "Adwaita-dark", "classic", "classic-dark"))


# -- VS Code, Code - OSS and VSCodium: a theme extension, selected in your settings --
VSCODES = [("Code", ".vscode"), ("Code - OSS", ".vscode-oss"), ("VSCodium", ".vscode-oss"), ("Code - Insiders", ".vscode-insiders")]
# Their Flatpaks: (app id, config folder, extensions folders it may use: in your home, or its own data)
VSCODE_FLATPAKS = [("com.visualstudio.code", "Code", [".vscode/extensions", "data/vscode/extensions"]),
                   ("com.vscodium.codium", "VSCodium", [".vscode-oss/extensions", "data/codium/extensions"])]


def vscode_installs():
    """[(its User settings folder, [extensions folders])] for each VS Code that's set up"""
    out = [(cfg(name, "User"), [os.path.join(HOME, extdir, "extensions")])
           for name, extdir in VSCODES if isdir(CFG, name, "User")]
    for app_id, name, exts in VSCODE_FLATPAKS:
        user = flatpak(app_id, "config", name, "User")
        if user and os.path.isdir(user):
            home_ext, own_ext = os.path.join(HOME, exts[0]), flatpak(app_id, exts[1])
            # whichever it uses; its own when neither is there yet
            found = [d for d in (home_ext, own_ext) if d and os.path.isdir(d)]
            out.append((user, found or [own_ext]))
    return out

def vscode_theme(c):
    s, bg, fg, surf, acc = c["syn"], c["bg"], c["text"], c["surface"], c["accent"]
    colors = {
        "foreground": fg, "focusBorder": acc, "widget.shadow": c["shadow"] + "80", "selection.background": c["selection"],
        "descriptionForeground": c["onVariant"], "errorForeground": c["red"], "icon.foreground": c["onVariant"],
        "textLink.foreground": acc, "textLink.activeForeground": acc,
        "editor.background": bg, "editor.foreground": fg, "editorCursor.foreground": acc,
        "editor.lineHighlightBackground": c["currentLine"], "editor.lineHighlightBorder": "#00000000",
        "editor.selectionBackground": c["selection"], "editor.inactiveSelectionBackground": surf,
        "editor.findMatchBackground": acc + "55", "editor.findMatchHighlightBackground": acc + "30",
        "editor.wordHighlightBackground": surf, "editorLineNumber.foreground": c["divider"],
        "editorLineNumber.activeForeground": fg, "editorIndentGuide.background1": surf,
        "editorIndentGuide.activeBackground1": c["box"], "editorWhitespace.foreground": c["box"],
        "editorBracketMatch.background": c["selection"], "editorBracketMatch.border": "#00000000",
        "editorGutter.background": bg, "editorWidget.background": surf, "editorWidget.border": c["divider"],
        "editorSuggestWidget.background": surf, "editorSuggestWidget.selectedBackground": c["selection"],
        "editorHoverWidget.background": surf, "editorError.foreground": c["red"], "editorWarning.foreground": c["yellow"],
        "editorInfo.foreground": acc, "editorGroupHeader.tabsBackground": bg, "editorGroup.border": surf,
        "tab.activeBackground": surf, "tab.inactiveBackground": bg, "tab.activeForeground": fg,
        "tab.inactiveForeground": c["onVariant"], "tab.border": bg, "tab.activeBorderTop": acc,
        "sideBar.background": bg, "sideBar.foreground": fg, "sideBar.border": surf,
        "sideBarSectionHeader.background": bg, "sideBarTitle.foreground": c["onVariant"],
        "activityBar.background": bg, "activityBar.foreground": fg, "activityBar.inactiveForeground": c["dim"],
        "activityBar.border": surf, "activityBarBadge.background": acc, "activityBarBadge.foreground": c["accentText"],
        "titleBar.activeBackground": bg, "titleBar.activeForeground": fg, "titleBar.inactiveBackground": bg,
        "titleBar.inactiveForeground": c["dim"], "titleBar.border": surf,
        "statusBar.background": bg, "statusBar.foreground": c["onVariant"], "statusBar.border": surf,
        "statusBar.noFolderBackground": bg, "statusBar.debuggingBackground": c["orange"],
        "statusBarItem.remoteBackground": acc, "statusBarItem.remoteForeground": c["accentText"],
        "panel.background": bg, "panel.border": surf, "panelTitle.activeBorder": acc,
        "panelTitle.activeForeground": fg, "panelTitle.inactiveForeground": c["dim"],
        "input.background": surf, "input.foreground": fg, "input.border": c["divider"],
        "input.placeholderForeground": c["dim"], "inputOption.activeBorder": acc,
        "dropdown.background": surf, "dropdown.border": c["divider"], "dropdown.foreground": fg,
        "list.activeSelectionBackground": c["selection"], "list.activeSelectionForeground": fg,
        "list.inactiveSelectionBackground": surf, "list.hoverBackground": c["between"],
        "list.focusOutline": acc, "list.highlightForeground": acc,
        "button.background": acc, "button.foreground": c["accentText"], "button.hoverBackground": mix(acc, fg, 0.15),
        "button.secondaryBackground": surf, "button.secondaryForeground": fg,
        "badge.background": acc, "badge.foreground": c["accentText"],
        "progressBar.background": acc, "scrollbarSlider.background": c["box"] + "60",
        "scrollbarSlider.hoverBackground": c["box"] + "90", "scrollbarSlider.activeBackground": c["box"],
        "menu.background": surf, "menu.foreground": fg, "menu.selectionBackground": c["selection"],
        "menu.separatorBackground": c["divider"], "quickInput.background": surf,
        "quickInputList.focusBackground": c["selection"], "notifications.background": surf,
        "terminal.background": bg, "terminal.foreground": fg, "terminalCursor.foreground": fg,
        "terminal.selectionBackground": c["selection"],
        "gitDecoration.modifiedResourceForeground": c["yellow"], "gitDecoration.untrackedResourceForeground": c["green"],
        "gitDecoration.deletedResourceForeground": c["red"], "gitDecoration.ignoredResourceForeground": c["dim"],
        "breadcrumb.foreground": c["onVariant"], "breadcrumb.focusForeground": fg,
    }
    names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
    for n, h in zip(names, c["ansi"]):
        colors["terminal.ansi" + n] = h
    for n, h in zip(names, c["ansiBright"]):
        colors["terminal.ansiBright" + n] = h
    tok = lambda scope, col, style=None: {"scope": scope, "settings": dict({"foreground": col}, **({"fontStyle": style} if style else {}))}
    tokens = [
        tok(["comment", "punctuation.definition.comment"], s["comment"], "italic"),
        tok(["keyword", "storage", "keyword.control", "storage.type", "storage.modifier"], s["keyword"]),
        tok(["keyword.operator"], s["operator"]),
        tok(["string", "string.quoted"], s["string"]),
        tok(["constant.character.escape", "constant.other.placeholder"], s["escape"]),
        tok(["constant.numeric"], s["number"]),
        tok(["constant", "constant.language", "support.constant"], s["constant"]),
        tok(["entity.name.function", "support.function", "meta.function-call"], s["function"]),
        tok(["entity.name.type", "entity.name.class", "support.type", "support.class"], s["type"]),
        tok(["variable", "variable.parameter"], s["variable"]),
        tok(["variable.other.property", "variable.other.object.property", "support.variable.property"], s["property"]),
        tok(["punctuation"], s["punctuation"]),
        tok(["entity.name.tag"], s["tag"]),
        tok(["entity.other.attribute-name"], s["attribute"]),
        tok(["markup.heading", "entity.name.section"], s["heading"], "bold"),
        tok(["markup.bold"], fg, "bold"), tok(["markup.italic"], fg, "italic"),
        tok(["markup.underline.link", "string.other.link"], s["link"]),
        tok(["markup.inline.raw", "markup.fenced_code"], s["string"]),
        tok(["markup.list.unnumbered", "markup.list.numbered", "punctuation.definition.list"], c["yellow"]),
        tok(["markup.inserted"], c["green"]), tok(["markup.deleted"], c["red"]), tok(["markup.changed"], c["yellow"]),
        tok(["invalid"], c["red"]),
    ]
    return {"name": "Slate", "type": "light" if c["light"] else "dark", "colors": colors,
            "tokenColors": tokens, "semanticHighlighting": True}

@app("vscode", "VS Code", "VS Code, Code - OSS and VSCodium (Flatpaks too): a Slate theme, selected for you",
     lambda: bool(vscode_installs()))
def vscode(ctx):
    c = ctx.c
    ext_id, ver = "slate.slate-theme", "1.0.0"
    folder = "%s-%s" % (ext_id, ver)
    pkg = {"name": "slate-theme", "displayName": "Slate", "description": "Slate's colours. " + GEN,
           "publisher": "slate", "version": ver, "engines": {"vscode": "^1.60.0"}, "categories": ["Themes"],
           "contributes": {"themes": [{"label": "Slate", "uiTheme": "vs" if c["light"] else "vs-dark",
                                       "path": "./themes/slate.json"}]}}
    done = set()
    for user, ext_dirs in vscode_installs():
        for exts in ext_dirs:
            if exts in done:              # (Code - OSS and VSCodium share one)
                continue
            done.add(exts)
            root = os.path.join(exts, folder)
            ctx.file(os.path.join(root, "package.json"), json.dumps(pkg, indent=2) + "\n")
            ctx.file(os.path.join(root, "themes", "slate.json"), json.dumps(vscode_theme(c), indent=2) + "\n")
            # VS Code lists its extensions in extensions.json; add ours so it's picked up
            reg = os.path.join(exts, "extensions.json")
            if os.path.exists(reg):
                ctx.jsonlist(reg, [], {"identifier": {"id": ext_id}, "version": ver,
                                       "location": {"$mid": 1, "path": root, "scheme": "file"},
                                       "relativeLocation": folder, "metadata": {"source": "vsix"}},
                             match=lambda x: isinstance(x, dict) and x.get("identifier", {}).get("id") == ext_id)
        ctx.jsonc(os.path.join(user, "settings.json"), "workbench.colorTheme", "Slate")


def zed_theme(c):
    s, bg, fg, surf, acc = c["syn"], c["bg"], c["text"], c["surface"], c["accent"]
    st = {
        "background": bg, "surface.background": bg, "elevated_surface.background": surf,
        "border": surf, "border.variant": surf, "border.focused": acc, "border.selected": acc,
        "text": fg, "text.muted": c["onVariant"], "text.placeholder": c["dim"], "text.accent": acc,
        "icon": c["onVariant"], "icon.accent": acc,
        "element.background": surf, "element.hover": c["between"], "element.selected": c["selection"],
        "ghost_element.hover": c["between"], "ghost_element.selected": c["selection"],
        "title_bar.background": bg, "title_bar.inactive_background": bg, "toolbar.background": bg,
        "tab_bar.background": bg, "tab.active_background": surf, "tab.inactive_background": bg,
        "status_bar.background": bg, "panel.background": bg, "panel.focused_border": acc,
        "scrollbar.thumb.background": c["box"] + "80", "scrollbar.track.background": "#00000000",
        "editor.background": bg, "editor.foreground": fg, "editor.gutter.background": bg,
        "editor.active_line.background": c["currentLine"], "editor.line_number": c["divider"],
        "editor.active_line_number": fg, "editor.indent_guide": surf, "editor.indent_guide_active": c["box"],
        "editor.document_highlight.read_background": surf,
        "search.match_background": acc + "40", "terminal.background": bg, "terminal.foreground": fg,
        "error": c["red"], "warning": c["yellow"], "info": acc, "hint": c["dim"], "success": c["green"],
        "created": c["green"], "deleted": c["red"], "modified": c["yellow"],
        "players": [{"cursor": acc, "selection": acc + "40", "background": acc}],
    }
    names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    for n, h in zip(names, c["ansi"]):
        st["terminal.ansi." + n] = h
    for n, h in zip(names, c["ansiBright"]):
        st["terminal.ansi.bright_" + n] = h
    sy = lambda col, style=None, weight=None: dict({"color": col}, **({"font_style": style} if style else {}),
                                                    **({"font_weight": weight} if weight else {}))
    st["syntax"] = {
        "comment": sy(s["comment"], "italic"), "comment.doc": sy(s["comment"], "italic"),
        "keyword": sy(s["keyword"]), "string": sy(s["string"]), "string.escape": sy(s["escape"]),
        "number": sy(s["number"]), "boolean": sy(s["constant"]), "constant": sy(s["constant"]),
        "function": sy(s["function"]), "type": sy(s["type"]), "constructor": sy(s["type"]),
        "variable": sy(s["variable"]), "property": sy(s["property"]), "operator": sy(s["operator"]),
        "punctuation": sy(s["punctuation"]), "punctuation.bracket": sy(s["punctuation"]),
        "tag": sy(s["tag"]), "attribute": sy(s["attribute"]), "title": sy(s["heading"], weight=700),
        "emphasis": sy(fg, "italic"), "emphasis.strong": sy(fg, weight=700),
        "link_text": sy(s["link"]), "link_uri": sy(s["link"]), "text.literal": sy(s["string"]),
        "embedded": sy(fg), "label": sy(c["yellow"]),
    }
    return {"$schema": "https://zed.dev/schema/themes/v0.2.0.json", "name": "Slate", "author": "Slate",
            "themes": [{"name": "Slate", "appearance": "light" if c["light"] else "dark", "style": st}]}

def zed_dirs():
    return config_dirs(have("zed") or have("zeditor") or isdir(CFG, "zed"), "zed", "dev.zed.Zed")


@app("zed", "Zed", "A Slate theme, selected for you (Flatpak too)", lambda: bool(zed_dirs()))
def zed(ctx):
    for d in zed_dirs():
        ctx.file(os.path.join(d, "themes", "slate.json"), json.dumps(zed_theme(ctx.c), indent=2) + "\n")
        ctx.jsonc(os.path.join(d, "settings.json"), "theme", "Slate")


def helix_into(ctx, d):
    c, s = ctx.c, ctx.c["syn"]
    fg = lambda col, *mods: '{ fg = "%s"%s }' % (col, ", modifiers = [%s]" % ", ".join('"%s"' % m for m in mods) if mods else "")
    rows = [
        ('"ui.background"', '{ bg = "%s" }' % c["bg"]), ('"ui.text"', fg(c["text"])),
        ('"ui.text.focus"', '{ fg = "%s", bg = "%s" }' % (c["text"], c["selection"])),
        ('"ui.cursor"', '{ fg = "%s", bg = "%s" }' % (c["bg"], c["dim"])),
        ('"ui.cursor.primary"', '{ fg = "%s", bg = "%s" }' % (c["accentText"], c["accent"])),
        ('"ui.cursor.match"', '{ bg = "%s" }' % c["selection"]),
        ('"ui.selection"', '{ bg = "%s" }' % c["selection"]),
        ('"ui.cursorline.primary"', '{ bg = "%s" }' % c["currentLine"]),
        ('"ui.linenr"', fg(c["divider"])), ('"ui.linenr.selected"', fg(c["text"])),
        ('"ui.statusline"', '{ fg = "%s", bg = "%s" }' % (c["text"], c["surface"])),
        ('"ui.statusline.inactive"', '{ fg = "%s", bg = "%s" }' % (c["dim"], c["bg"])),
        ('"ui.statusline.normal"', '{ fg = "%s", bg = "%s" }' % (c["accentText"], c["accent"])),
        ('"ui.statusline.insert"', '{ fg = "%s", bg = "%s" }' % (c["accentText"], c["green"])),
        ('"ui.statusline.select"', '{ fg = "%s", bg = "%s" }' % (c["accentText"], c["magenta"])),
        ('"ui.popup"', '{ bg = "%s" }' % c["surface"]), ('"ui.window"', fg(c["surface"])),
        ('"ui.help"', '{ fg = "%s", bg = "%s" }' % (c["text"], c["surface"])),
        ('"ui.menu"', '{ fg = "%s", bg = "%s" }' % (c["text"], c["surface"])),
        ('"ui.menu.selected"', '{ bg = "%s" }' % c["selection"]),
        ('"ui.virtual.whitespace"', fg(c["box"])), ('"ui.virtual.ruler"', '{ bg = "%s" }' % c["surface"]),
        ('"ui.virtual.indent-guide"', fg(c["surface"])), ('"ui.virtual.inlay-hint"', fg(c["dim"])),
        ('"ui.bufferline"', '{ fg = "%s", bg = "%s" }' % (c["dim"], c["bg"])),
        ('"ui.bufferline.active"', '{ fg = "%s", bg = "%s" }' % (c["text"], c["surface"])),
        ('"comment"', fg(s["comment"], "italic")), ('"keyword"', fg(s["keyword"])),
        ('"string"', fg(s["string"])), ('"constant.character.escape"', fg(s["escape"])),
        ('"constant.numeric"', fg(s["number"])), ('"constant"', fg(s["constant"])),
        ('"function"', fg(s["function"])), ('"type"', fg(s["type"])), ('"constructor"', fg(s["type"])),
        ('"variable"', fg(s["variable"])), ('"variable.other.member"', fg(s["property"])),
        ('"operator"', fg(s["operator"])), ('"punctuation"', fg(s["punctuation"])),
        ('"tag"', fg(s["tag"])), ('"attribute"', fg(s["attribute"])), ('"label"', fg(c["yellow"])),
        ('"markup.heading"', fg(s["heading"], "bold")), ('"markup.bold"', fg(c["text"], "bold")),
        ('"markup.italic"', fg(c["text"], "italic")), ('"markup.link.url"', fg(s["link"], "underlined")),
        ('"markup.link.text"', fg(s["link"])), ('"markup.list"', fg(c["yellow"])),
        ('"markup.raw"', fg(s["string"])), ('"markup.quote"', fg(c["dim"], "italic")),
        ('"diff.plus"', fg(c["green"])), ('"diff.minus"', fg(c["red"])), ('"diff.delta"', fg(c["yellow"])),
        ('"error"', fg(c["red"])), ('"warning"', fg(c["yellow"])), ('"info"', fg(c["accent"])), ('"hint"', fg(c["dim"])),
        ('"diagnostic.error"', '{ underline = { color = "%s", style = "curl" } }' % c["red"]),
        ('"diagnostic.warning"', '{ underline = { color = "%s", style = "curl" } }' % c["yellow"]),
    ]
    ctx.file(os.path.join(d, "themes", "slate.toml"), "# " + GEN + "\n" + "\n".join("%s = %s" % r for r in rows) + "\n")
    conf = os.path.join(d, "config.toml")
    if re.search(r'^theme\s*=', read(conf) or "", flags=re.M):
        ctx.replace(conf, r'^theme\s*=.*$', 'theme = "slate"')
    else:
        ctx.line(conf, 'theme = "slate"', top=True)                 # top-level keys go first



def helix_dirs():
    return config_dirs(have("hx") or have("helix"), "helix", "com.helix_editor.Helix")


@app("helix", "Helix", "A Slate theme, selected for you (Flatpak too)", lambda: bool(helix_dirs()))
def helix(ctx):
    for d in helix_dirs():
        helix_into(ctx, d)
@reloads("helix")
def helix_reload(ctx):
    if touched("helix"):
        signal_all("hx", "USR1")             # Helix reloads its config on SIGUSR1
        signal_all("helix", "USR1")


VIM_NAME = "slate-desktop"      # Vim and Neovim already ship a colour scheme called "slate"

def vim_colors(c):
    s = c["syn"]
    groups = {
        "Normal": (c["text"], c["bg"], None), "NormalFloat": (c["text"], c["surface"], None),
        "FloatBorder": (c["divider"], c["surface"], None), "Comment": (s["comment"], None, "italic"),
        "Constant": (s["constant"], None, None), "String": (s["string"], None, None),
        "Character": (s["string"], None, None), "Number": (s["number"], None, None),
        "Boolean": (s["constant"], None, None), "Float": (s["number"], None, None),
        "Identifier": (s["variable"], None, None), "Function": (s["function"], None, None),
        "Statement": (s["keyword"], None, None), "Keyword": (s["keyword"], None, None),
        "Conditional": (s["keyword"], None, None), "Repeat": (s["keyword"], None, None),
        "Operator": (s["operator"], None, None), "Exception": (s["keyword"], None, None),
        "PreProc": (s["constant"], None, None), "Type": (s["type"], None, None),
        "Special": (s["escape"], None, None), "SpecialChar": (s["escape"], None, None),
        "Tag": (s["tag"], None, None), "Delimiter": (s["punctuation"], None, None),
        "Underlined": (s["link"], None, "underline"), "Error": (c["red"], None, None),
        "Todo": (c["accentText"], c["yellow"], "bold"), "Title": (s["heading"], None, "bold"),
        "LineNr": (c["divider"], None, None), "CursorLineNr": (c["text"], c["currentLine"], None),
        "CursorLine": (None, c["currentLine"], "NONE"), "ColorColumn": (None, c["surface"], None),
        "Visual": (None, c["selection"], None), "Search": (c["accentText"], c["accent"], None),
        "IncSearch": (c["accentText"], c["yellow"], None), "CurSearch": (c["accentText"], c["yellow"], None),
        "MatchParen": (None, c["selection"], "bold"), "Pmenu": (c["text"], c["surface"], None),
        "PmenuSel": (c["text"], c["selection"], None), "PmenuSbar": (None, c["surface"], None),
        "PmenuThumb": (None, c["box"], None), "StatusLine": (c["text"], c["surface"], "NONE"),
        "StatusLineNC": (c["dim"], c["bg"], "NONE"), "VertSplit": (c["surface"], None, "NONE"),
        "WinSeparator": (c["surface"], None, "NONE"), "TabLine": (c["dim"], c["bg"], "NONE"),
        "TabLineSel": (c["text"], c["surface"], "NONE"), "TabLineFill": (None, c["bg"], "NONE"),
        "NonText": (c["box"], None, None), "SpecialKey": (c["box"], None, None),
        "Whitespace": (c["box"], None, None), "Folded": (c["dim"], c["surface"], None),
        "FoldColumn": (c["dim"], None, None), "SignColumn": (None, c["bg"], None),
        "EndOfBuffer": (c["bg"], None, None), "DiffAdd": (None, mix(c["bg"], c["green"], 0.2), None),
        "DiffChange": (None, mix(c["bg"], c["yellow"], 0.15), None), "DiffDelete": (c["red"], mix(c["bg"], c["red"], 0.15), None),
        "DiffText": (None, mix(c["bg"], c["yellow"], 0.3), None), "ErrorMsg": (c["red"], None, None),
        "WarningMsg": (c["yellow"], None, None), "MoreMsg": (c["green"], None, None),
        "Question": (c["accent"], None, None), "Directory": (c["accent"], None, None),
        "WildMenu": (c["accentText"], c["accent"], None), "SpellBad": (None, None, "undercurl"),
        "markdownH1": (s["heading"], None, "bold"), "markdownH2": (s["heading"], None, "bold"),
        "markdownListMarker": (c["yellow"], None, None), "markdownCode": (s["string"], None, None),
    }
    out = ['" ' + GEN, "hi clear", 'if exists("syntax_on") | syntax reset | endif',
           "let g:colors_name = '%s'" % VIM_NAME, "set background=%s" % ("light" if c["light"] else "dark"),
           "if has('termguicolors') | set termguicolors | endif"]
    for g, (f, b, a) in groups.items():
        parts = ["hi", g, "guifg=%s" % (f or "NONE"), "guibg=%s" % (b or "NONE"), "gui=%s" % (a or "NONE"), "cterm=%s" % (a or "NONE")]
        out.append(" ".join(parts))
    out.append("let g:terminal_ansi_colors = [%s]" % ", ".join("'%s'" % h for h in c["ansi"] + c["ansiBright"]))
    return "\n".join(out) + "\n"

def nvim_dirs():
    return config_dirs(have("nvim"), "nvim", "io.neovim.nvim")


@app("vim", "Vim and Neovim", "A Slate colour scheme (%s), used unless you set your own" % VIM_NAME,
     lambda: have("vim") or bool(nvim_dirs()))
def vim(ctx):
    text = vim_colors(ctx.c)
    use = "colorscheme " + VIM_NAME
    if have("vim"):
        ctx.file(os.path.join(HOME, ".vim", "colors", VIM_NAME + ".vim"), text)
        rc = first_existing(os.path.join(HOME, ".vimrc"), os.path.join(HOME, ".vim", "vimrc"))
        if rc is None:
            rc = os.path.join(HOME, ".vimrc")
            ctx.start(rc, starting("vimrc"))
        ctx.line(rc, use, present=r"^\s*colorscheme\s")
    for d in nvim_dirs():
        ctx.file(os.path.join(d, "colors", VIM_NAME + ".vim"), text)
        lua, vimrc = os.path.join(d, "init.lua"), os.path.join(d, "init.vim")
        if os.path.exists(lua):
            # Leave configs that pick their own scheme (or use a plugin manager) alone
            if not re.search(r"colorscheme|lazy|packer|plug", read(lua) or ""):
                ctx.line(lua, 'vim.cmd.colorscheme("%s")' % VIM_NAME)
        elif os.path.exists(vimrc):
            ctx.line(vimrc, use, present=r"^\s*colorscheme\s")
        else:
            ctx.start(lua, starting("nvim-init.lua"))
            ctx.line(lua, 'vim.cmd.colorscheme("%s")' % VIM_NAME)


# ==== Command-line tools ====================================================================
def tm_theme(c):
    """A TextMate theme (bat, and yazi's previews)"""
    s = c["syn"]
    def d(**kv):
        return "<dict>" + "".join("<key>%s</key><string>%s</string>" % kv_ for kv_ in kv.items()) + "</dict>"
    rule = lambda name, scope, fg, style="": ("<dict><key>name</key><string>%s</string><key>scope</key><string>%s</string>"
                                             "<key>settings</key>%s</dict>" % (name, scope, d(foreground=fg, **({"fontStyle": style} if style else {}))))
    rules = [rule("Comment", "comment", s["comment"], "italic"), rule("Keyword", "keyword, storage", s["keyword"]),
             rule("Operator", "keyword.operator", s["operator"]), rule("String", "string", s["string"]),
             rule("Escape", "constant.character.escape", s["escape"]), rule("Number", "constant.numeric", s["number"]),
             rule("Constant", "constant, support.constant", s["constant"]),
             rule("Function", "entity.name.function, support.function", s["function"]),
             rule("Type", "entity.name.type, entity.name.class, support.type, support.class", s["type"]),
             rule("Variable", "variable", s["variable"]), rule("Property", "variable.other.property", s["property"]),
             rule("Punctuation", "punctuation", s["punctuation"]), rule("Tag", "entity.name.tag", s["tag"]),
             rule("Attribute", "entity.other.attribute-name", s["attribute"]),
             rule("Heading", "markup.heading, entity.name.section", s["heading"], "bold"),
             rule("Link", "markup.underline.link", s["link"]), rule("Inserted", "markup.inserted", c["green"]),
             rule("Deleted", "markup.deleted", c["red"]), rule("Changed", "markup.changed", c["yellow"]),
             rule("Invalid", "invalid", c["red"])]
    general = d(background=c["bg"], foreground=c["text"], caret=c["accent"], selection=c["selection"],
                lineHighlight=c["currentLine"], gutterForeground=c["divider"], invisibles=c["box"])
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<!-- %s -->\n<plist version="1.0"><dict>'
            "<key>name</key><string>Slate</string><key>settings</key><array><dict><key>settings</key>%s</dict>%s"
            "</array></dict></plist>\n" % (GEN, general, "".join(rules)))

def bat_cmd():
    return "bat" if have("bat") else "batcat" if have("batcat") else None

@app("bat", "bat", "A Slate syntax theme, selected for you", lambda: bat_cmd() is not None)
def bat(ctx):
    ctx.file(cfg("bat", "themes", "Slate.tmTheme"), tm_theme(ctx.c))
    conf = cfg("bat", "config")
    if re.search(r"^\s*--theme[= ]", read(conf) or "", flags=re.M):
        ctx.replace(conf, r"^\s*--theme[= ].*$", '--theme="Slate"')
    else:
        ctx.line(conf, '--theme="Slate"')

@reloads("bat")
def bat_reload(ctx):
    if touched("bat") and bat_cmd():
        run([bat_cmd(), "cache", "--build"], timeout=60)


@app("fzf", "fzf", "Slate's colours for the fuzzy finder (FZF_DEFAULT_OPTS_FILE, set by the Slate session)",
     lambda: have("fzf"))
def fzf(ctx):
    c = ctx.c
    cols = {"fg": c["text"], "bg": "-1", "hl": c["accent"], "fg+": c["text"], "bg+": c["selection"],
            "hl+": c["accent"], "info": c["dim"], "prompt": c["accent"], "pointer": c["accent"],
            "marker": c["green"], "spinner": c["accent"], "header": c["dim"], "border": c["divider"],
            "gutter": "-1", "query": c["text"]}
    # Slate's session points FZF_DEFAULT_OPTS_FILE here; your own FZF_DEFAULT_OPTS still win
    ctx.file(os.path.join(fzf_opts_dir(), "slate.opts"),
             "# %s\n--color=%s\n" % (GEN, ",".join("%s:%s" % kv for kv in cols.items())), empty_on_undo=True)

def fzf_opts_dir():
    return os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "slate", "fzf")


@app("yazi", "Yazi", "A Slate flavour, selected for you", lambda: have("yazi"))
def yazi(ctx):
    c = ctx.c
    q = lambda h: '"%s"' % h
    st = lambda fg=None, bg=None, bold=False: "{ %s }" % ", ".join(
        x for x in (fg and "fg = %s" % q(fg), bg and "bg = %s" % q(bg), bold and "bold = true") if x)
    out = ["# " + GEN, "[mgr]", "cwd = %s" % st(c["accent"]), "hovered = %s" % st(c["text"], c["selection"]),
           "preview_hovered = %s" % st(bg=c["selection"]), "find_keyword = %s" % st(c["yellow"], bold=True),
           "find_position = %s" % st(c["magenta"]), "marker_copied = %s" % st(c["green"], c["green"]),
           "marker_cut = %s" % st(c["red"], c["red"]), "marker_marked = %s" % st(c["tertiary"], c["tertiary"]),
           "marker_selected = %s" % st(c["accent"], c["accent"]), "count_copied = %s" % st(c["bg"], c["green"]),
           "count_cut = %s" % st(c["bg"], c["red"]), "count_selected = %s" % st(c["bg"], c["accent"]),
           "border_style = %s" % st(c["divider"]), 'syntect_theme = "~/.config/yazi/flavors/slate.yazi/tmtheme.xml"',
           "", "[tabs]", "active = %s" % st(c["accentText"], c["accent"], True), "inactive = %s" % st(c["dim"], c["surface"]),
           "", "[mode]", "normal_main = %s" % st(c["accentText"], c["accent"], True), "normal_alt = %s" % st(c["accent"], c["surface"]),
           "select_main = %s" % st(c["accentText"], c["magenta"], True), "select_alt = %s" % st(c["magenta"], c["surface"]),
           "unset_main = %s" % st(c["accentText"], c["tertiary"], True), "unset_alt = %s" % st(c["tertiary"], c["surface"]),
           "", "[status]", "perm_type = %s" % st(c["accent"]), "perm_read = %s" % st(c["yellow"]),
           "perm_write = %s" % st(c["red"]), "perm_exec = %s" % st(c["green"]), "perm_sep = %s" % st(c["dim"]),
           "progress_label = %s" % st(c["text"], bold=True), "progress_normal = %s" % st(c["accent"], c["surface"]),
           "progress_error = %s" % st(c["red"], c["surface"]),
           "", "[input]", "border = %s" % st(c["accent"]), "value = %s" % st(c["text"]), "selected = %s" % st(bg=c["selection"]),
           "", "[cmp]", "border = %s" % st(c["accent"]), "active = %s" % st(bg=c["selection"]),
           "", "[tasks]", "border = %s" % st(c["accent"]), "hovered = %s" % st(c["text"], c["selection"]),
           "", "[which]", "mask = %s" % st(bg=c["bg"]), "cand = %s" % st(c["accent"]), "desc = %s" % st(c["onVariant"]),
           "separator_style = %s" % st(c["dim"]),
           "", "[help]", "on = %s" % st(c["accent"]), "run = %s" % st(c["magenta"]), "hovered = %s" % st(bg=c["selection"]),
           "", "[filetype]", "rules = [",
           '  { mime = "image/*", fg = %s },' % q(c["yellow"]), '  { mime = "{audio,video}/*", fg = %s },' % q(c["magenta"]),
           '  { mime = "application/*zip", fg = %s },' % q(c["red"]), '  { name = "*/", fg = %s },' % q(c["accent"]),
           "]"]
    d = cfg("yazi", "flavors", "slate.yazi")
    ctx.file(os.path.join(d, "flavor.toml"), "\n".join(out) + "\n")
    ctx.file(os.path.join(d, "tmtheme.xml"), tm_theme(c))
    theme = cfg("yazi", "theme.toml")
    ctx.ini_many(theme, [("flavor", "dark", '"slate"'), ("flavor", "light", '"slate"')], sep=" = ")


@app("cava", "cava", "The audio visualiser's colours: a gradient in Slate's accent", lambda: have("cava"))
def cava(ctx):
    c = ctx.c
    conf = cfg("cava", "config")
    ctx.start(conf, starting("cava.conf"))
    ctx.ini_many(conf, [("color", k, v) for k, v in (
        ("gradient", "1"), ("gradient_count", "3"), ("gradient_color_1", "'%s'" % c["tertiary"]),
        ("gradient_color_2", "'%s'" % c["accent"]), ("gradient_color_3", "'%s'" % c["magenta"]))], sep=" = ")

@reloads("cava")
def cava_reload(ctx):
    if touched("cava"):
        signal_all("cava", "USR2")           # cava reloads its colours on SIGUSR2


def zathura_into(ctx, d):
    c = ctx.c
    sets = [("default-bg", c["bg"]), ("default-fg", c["text"]), ("statusbar-bg", c["surface"]),
            ("statusbar-fg", c["text"]), ("inputbar-bg", c["bg"]), ("inputbar-fg", c["text"]),
            ("notification-bg", c["surface"]), ("notification-fg", c["text"]),
            ("notification-error-bg", c["surface"]), ("notification-error-fg", c["red"]),
            ("notification-warning-bg", c["surface"]), ("notification-warning-fg", c["yellow"]),
            ("highlight-color", c["accent"] + "60"), ("highlight-active-color", c["accent"]),
            ("completion-bg", c["surface"]), ("completion-fg", c["text"]),
            ("completion-highlight-bg", c["selection"]), ("completion-highlight-fg", c["text"]),
            ("index-bg", c["bg"]), ("index-fg", c["text"]), ("index-active-bg", c["selection"]),
            ("index-active-fg", c["text"]), ("recolor-lightcolor", c["bg"]), ("recolor-darkcolor", c["text"])]
    ctx.file(os.path.join(d, "slate"), "# %s\n" % GEN + "\n".join('set %s "%s"' % kv for kv in sets) + "\n")
    ctx.line(os.path.join(d, "zathurarc"), "include slate")




def zathura_dirs():
    return config_dirs(have("zathura"), "zathura", "org.pwmt.zathura")


@app("zathura", "zathura", "The document viewer's colours (and its recolour mode), Flatpak too", lambda: bool(zathura_dirs()))
def zathura(ctx):
    for d in zathura_dirs():
        zathura_into(ctx, d)
# ==== Chat, music and browser ===============================================================
def discord_css(c):
    v = {
        "--background-primary": c["bg"], "--background-secondary": c["surface"],
        "--background-secondary-alt": c["between"], "--background-tertiary": c["bg"],
        "--background-floating": c["surface"], "--background-nested-floating": c["surface"],
        "--background-accent": c["accent"], "--background-mobile-primary": c["bg"],
        "--background-mobile-secondary": c["surface"], "--background-base-lowest": c["bg"],
        "--background-base-lower": c["bg"], "--background-base-low": c["surface"],
        "--background-surface-high": c["surface"], "--background-surface-higher": c["surfaceHigh"],
        "--background-surface-highest": c["surfaceHigh"],
        "--background-modifier-hover": c["accent"] + "14", "--background-modifier-active": c["accent"] + "1f",
        "--background-modifier-selected": c["accent"] + "29", "--background-modifier-accent": c["divider"],
        "--channeltextarea-background": c["surface"], "--chat-background": c["bg"],
        "--modal-background": c["surface"], "--modal-footer-background": c["bg"],
        "--input-background": c["surface"], "--deprecated-card-bg": c["surface"],
        "--text-normal": c["text"], "--text-default": c["text"], "--text-muted": c["dim"],
        "--text-link": c["accent"], "--text-brand": c["accent"], "--header-primary": c["text"],
        "--header-secondary": c["onVariant"], "--interactive-normal": c["onVariant"],
        "--interactive-hover": c["text"], "--interactive-active": c["text"], "--interactive-muted": c["dim"],
        "--channels-default": c["onVariant"], "--brand-experiment": c["accent"], "--brand-500": c["accent"],
        "--brand-560": mix(c["accent"], c["bg"], 0.15), "--brand-600": mix(c["accent"], c["bg"], 0.25),
        "--button-filled-brand-background": c["accent"], "--button-filled-brand-text": c["accentText"],
        "--scrollbar-auto-thumb": c["box"], "--scrollbar-thin-thumb": c["box"],
        "--scrollbar-auto-track": "transparent", "--border-subtle": c["divider"], "--border-faint": c["surface"],
        "--status-positive": c["green"], "--status-warning": c["yellow"], "--status-danger": c["red"],
        "--mention-background": c["accent"] + "1f", "--mention-foreground": c["accent"],
    }
    body = "\n".join("    %s: %s !important;" % kv for kv in v.items())
    return ("/**\n * @name Slate\n * @description Slate's colours. %s\n * @author Slate\n * @version 1.0.0\n */\n"
            ":root, .theme-dark, .theme-light, .visual-refresh {\n%s\n}\n" % (GEN, body))

DISCORDS = ["vesktop", "Vencord", "equibop", "Equicord", "legcord"]


def discord_roots():
    """Each Vencord-style config folder: in ~/.config, and inside Flatpaks' own config folders
    (~/.var/app/<app>/config: Discord's Flatpak keeps Vencord there, Vesktop's its own)"""
    bases = [CFG] + sorted(glob.glob(os.path.join(HOME, ".var", "app", "*", "config")))
    return [os.path.join(b, d) for b in bases for d in DISCORDS if os.path.isdir(os.path.join(b, d))]


# Vencord in Discord itself (not Vesktop and the like, which have it built in): its installer
# renames Discord's resources/app.asar to _app.asar and puts a tiny app.asar in its place that
# loads Vencord. A Discord update brings a new app.asar and the patch is gone.
DISCORD_INSTALLS = ["/opt/discord", "/opt/discord-ptb", "/opt/discord-canary", "/usr/share/discord", "/usr/lib/discord",
                    "/usr/lib64/discord"]
VENCORD_STUB = os.path.join(STATE, "slate", "vencord-app.asar")     # a copy of that tiny app.asar

def discord_resources():
    """Every Discord's resources folder: packages, and Flatpaks (yours and the system's).
    Only your own Flatpaks when trying things against a scratch home (SLATE_THEME_TEST)"""
    system = not os.environ.get("SLATE_THEME_TEST")
    out = [os.path.join(d, "resources") for d in DISCORD_INSTALLS] if system else []
    for base in [os.path.join(DATA, "flatpak")] + (["/var/lib/flatpak"] if system else []):
        out += glob.glob(os.path.join(base, "app", "com.discordapp.Discord*", "current", "active", "files", "discord*", "resources"))
    return [d for d in out if os.path.isfile(os.path.join(d, "app.asar"))]

def vencord_gone():
    """The Discords Vencord isn't in: a full-size app.asar, and no _app.asar beside it"""
    def size(path):
        try:
            return os.path.getsize(path)
        except OSError:
            return 0
    return [d for d in discord_resources()
            if not os.path.exists(os.path.join(d, "_app.asar")) and size(os.path.join(d, "app.asar")) > 65536]

def vencord_used():
    """Vencord has been set up for Discord itself (it keeps its files in ~/.config/Vencord)"""
    return os.path.isfile(cfg("Vencord", "dist", "patcher.js")) or os.path.isfile(VENCORD_STUB)

def vencord_restore():
    """Keep a copy of Vencord's app.asar while it's in place; put it back into a Discord that an
    update has taken it out of. Only where Slate may write (your own Flatpak, say) and what
    the copy loads is still there; otherwise it's noted as lost, for Slate to tell you."""
    for d in discord_resources():
        stub = os.path.join(d, "app.asar")
        if os.path.exists(os.path.join(d, "_app.asar")) and os.path.getsize(stub) < 4096:
            with open(stub, "rb") as f:
                data = f.read()
            if b"patcher.js" in data:
                os.makedirs(os.path.dirname(VENCORD_STUB), exist_ok=True)
                with open(VENCORD_STUB + ".tmp", "wb") as f:
                    f.write(data)
                os.replace(VENCORD_STUB + ".tmp", VENCORD_STUB)
    if not vencord_used():
        return
    for d in vencord_gone():
        ok = False
        try:
            with open(VENCORD_STUB, "rb") as f:
                data = f.read()
            loads = re.search(rb'require\("([^"]+)"\)', data)
            if loads and os.path.isfile(loads.group(1).decode()) and os.access(d, os.W_OK):
                with open(os.path.join(d, "app.asar.slate-tmp"), "wb") as f:
                    f.write(data)
                os.rename(os.path.join(d, "app.asar"), os.path.join(d, "_app.asar"))
                os.replace(os.path.join(d, "app.asar.slate-tmp"), os.path.join(d, "app.asar"))
                ok = True
        except OSError:
            pass
        NOTES.append(("restored" if ok else "lost", "discord", "Discord"))

@app("discord", "Discord (Vencord)", "Vesktop, Vencord and Equicord, Flatpak builds too: a Slate theme, switched on for you, with Vencord put back after Discord updates",
     lambda: bool(discord_roots()))
def discord(ctx):
    css = discord_css(ctx.c)
    for root in discord_roots():
        ctx.file(os.path.join(root, "themes", "slate.theme.css"), css)
        settings = first_existing(os.path.join(root, "settings", "settings.json"), os.path.join(root, "settings.json"))
        if settings:
            ctx.jsonlist(settings, ["enabledThemes"], "slate.theme.css")
    vencord_restore()

@stale("discord")
def discord_stale():
    return vencord_used() and bool(vencord_gone())


def spicetify():
    """The spicetify command: on the PATH, or where its own installer puts it (~/.spicetify),
    which it only adds to your shell's PATH, not the desktop's. None if neither."""
    found = shutil.which("spicetify")
    if found:
        return found
    own = os.path.join(HOME, ".spicetify", "spicetify")
    return own if os.access(own, os.X_OK) else None


@app("spotify", "Spotify (Spicetify)", "A Slate theme for Spicetify, applied without restarting Spotify, and put back after Spotify updates",
     lambda: spicetify() is not None)
def spotify(ctx):
    c = ctx.c
    keys = [("text", c["text"]), ("subtext", c["onVariant"]), ("main", c["bg"]), ("main-elevated", c["surface"]),
            ("highlight", c["surface"]), ("highlight-elevated", c["surfaceHigh"]), ("sidebar", c["bg"]),
            ("player", c["bg"]), ("card", c["surface"]), ("shadow", c["shadow"]), ("selected-row", c["text"]),
            ("button", c["accent"]), ("button-active", c["accent"]), ("button-disabled", c["dim"]),
            ("tab-active", c["surface"]), ("notification", c["accent"]), ("notification-error", c["red"]),
            ("misc", c["dim"])]
    root = cfg("spicetify", "Themes", "Slate")
    ctx.file(os.path.join(root, "color.ini"), "; %s\n[slate]\n" % GEN + "\n".join("%-19s= %s" % (k, bare(v)) for k, v in keys) + "\n")
    ctx.file(os.path.join(root, "user.css"), "/* %s */\n" % GEN)
    sp = spicetify()
    cur = (run_out([sp, "config", "current_theme"]) or "").strip()
    if cur != "Slate":
        # (the scheme in use, to put back if Spotify's theming is switched off)
        scheme = (run_out([sp, "config", "color_scheme"]) or "").strip()
        ctx.command([sp, "config", "current_theme", "Slate", "color_scheme", "slate"],
                    [sp, "config", "current_theme", cur or "marketplace", "color_scheme", scheme or ""])

def spotify_unpatched():
    """Spotify's files are as Spotify ships them: Spicetify's patch isn't in (never applied, or
    a Spotify update has replaced it). Spicetify unpacks Apps/xpui.spa into Apps/xpui."""
    try:
        with open(cfg("spicetify", "config-xpui.ini"), encoding="utf-8") as f:
            m = re.search(r"^spotify_path\s*=\s*(\S.*)$", f.read(), re.M)
    except OSError:
        return False
    if not m:
        return False
    apps = os.path.join(os.path.expanduser(os.path.expandvars(m.group(1).strip())), "Apps")
    return os.path.isfile(os.path.join(apps, "xpui.spa")) and not os.path.isdir(os.path.join(apps, "xpui"))

@stale("spotify")
def spotify_stale():
    return spicetify() is not None and spotify_unpatched()

@reloads("spotify")
def spotify_reload(ctx):
    if not ctx.live:
        return
    if spotify_unpatched():
        # Spotify was updated: take Spicetify's copy of the new version and patch it again
        # (-n: don't restart Spotify; it shows when Spotify next starts)
        run([spicetify(), "-q", "-n", "backup", "apply"], timeout=300)
        NOTES.append(("lost" if spotify_unpatched() else "restored", "spotify", "Spotify"))
    elif touched("spicetify"):
        run([spicetify(), "apply", "-n", "-q"], timeout=120)     # -n: don't restart Spotify


def obsidian_vaults():
    """Every vault Obsidian knows about (its own list; the Flatpak's too)"""
    out = []
    for f in (cfg("obsidian", "obsidian.json"), os.path.join(HOME, ".var", "app", "md.obsidian.Obsidian", "config", "obsidian", "obsidian.json")):
        try:
            vaults = json.loads(read(f) or "{}").get("vaults", {})
        except ValueError:
            continue
        for v in vaults.values():
            p = v.get("path") if isinstance(v, dict) else None
            if p and os.path.isdir(os.path.join(p, ".obsidian")) and p not in out:
                out.append(p)
    return out

def obsidian_css(c):
    r, g, b = (int(c["accent"][i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    alpha = lambda a: "%02x" % round(a * 255)
    line = c["text"] + alpha(0.12 if c["light"] else 0.08)
    line_hover = c["text"] + alpha(0.2 if c["light"] else 0.14)
    v = {
        # Obsidian works out its accent shades from these
        "--accent-h": "%d" % round(h * 360), "--accent-s": "%d%%" % round(s * 100), "--accent-l": "%d%%" % round(l * 100),
        "--background-primary": c["bg"], "--background-primary-alt": c["between"],
        "--background-secondary": c["surface"], "--background-secondary-alt": c["between"],
        # Lines (borders, between panes, round tabs): a faint wash of the text colour, gentle on
        # any background, rather than a solid grey
        "--background-modifier-border": line, "--background-modifier-border-hover": line_hover,
        "--divider-color": line, "--divider-color-hover": c["accent"], "--tab-outline-color": line,
        "--tab-divider-color": line, "--titlebar-border-color": line, "--table-border-color": line,
        "--hr-color": line, "--metadata-divider-color": line, "--prompt-border-color": line,
        "--modal-border-color": line, "--embed-border-left": "2px solid " + line,
        "--background-modifier-border-focus": c["accent"], "--background-modifier-hover": c["accent"] + "14",
        "--background-modifier-active-hover": c["accent"] + "1f", "--background-modifier-form-field": c["surface"],
        "--background-modifier-message": c["surface"],
        "--titlebar-background": c["bg"], "--titlebar-background-focused": c["bg"],
        "--tab-container-background": c["bg"], "--ribbon-background": c["bg"], "--ribbon-background-collapsed": c["bg"],
        "--text-normal": c["text"], "--text-muted": c["onVariant"], "--text-faint": c["dim"],
        "--text-accent": c["accent"], "--text-accent-hover": c["accent"], "--text-on-accent": c["accentText"],
        "--text-selection": c["selection"], "--text-highlight-bg": c["accent"] + "33",
        "--interactive-normal": c["surface"], "--interactive-hover": c["surfaceHigh"],
        "--interactive-accent": c["accent"], "--interactive-accent-hover": c["accent"],
        "--link-color": c["accent"], "--link-color-hover": c["accent"], "--link-external-color": c["accent"],
        "--link-unresolved-color": c["secondary"], "--checkbox-color": c["accent"], "--checkbox-marker-color": c["accentText"],
        "--blockquote-border-color": c["accent"], "--code-background": c["surface"],
        # Code: blocks and their syntax colours
        "--code-normal": c["text"], "--code-comment": c["dim"], "--code-function": c["accent"],
        "--code-keyword": c["magenta"], "--code-string": c["green"], "--code-value": c["orange"],
        "--code-property": c["tertiary"], "--code-tag": c["red"], "--code-operator": c["onVariant"],
        "--code-important": c["yellow"], "--code-punctuation": c["dim"],
        "--nav-item-background-active": c["selection"], "--nav-item-background-hover": c["accent"] + "14",
        "--scrollbar-thumb-bg": c["box"], "--scrollbar-active-thumb-bg": c["dim"],
        "--color-red": c["red"], "--color-green": c["green"], "--color-yellow": c["yellow"], "--color-orange": c["orange"],
    }
    body = "\n".join("    %s: %s !important;" % kv for kv in v.items())
    # Inline code (`like this`), styled directly as well: themes (like Things) give it their own
    # colours that the variables above don't reach
    inline = (".markdown-rendered code:not(pre code), .markdown-preview-view code:not(pre code),\n"
              ".cm-s-obsidian span.cm-inline-code, .markdown-source-view.mod-cm6 .cm-inline-code {\n"
              "    background-color: %s !important;\n    color: %s !important;\n}\n"
              ".markdown-rendered pre, .markdown-source-view.mod-cm6 .HyperMD-codeblock {\n"
              "    background-color: %s !important;\n}\n") % (c["surface"], c["accent"], c["surface"])
    return "/* %s */\nbody.theme-dark, body.theme-light, .theme-dark, .theme-light {\n%s\n}\n%s" % (GEN, body, inline)

@app("obsidian", "Obsidian", "A Slate CSS snippet in each of your vaults, switched on for you (reopen Obsidian once if it was open)",
     lambda: bool(obsidian_vaults()))
def obsidian(ctx):
    css = obsidian_css(ctx.c)
    for v in obsidian_vaults():
        ctx.file(os.path.join(v, ".obsidian", "snippets", "slate.css"), css)
        ctx.jsonlist(os.path.join(v, ".obsidian", "appearance.json"), ["enabledCssSnippets"], "slate")


def firefox_profiles():
    out = []
    for base in (os.path.join(HOME, ".mozilla", "firefox"), cfg("mozilla", "firefox"),
                 os.path.join(HOME, ".var", "app", "org.mozilla.firefox", ".mozilla", "firefox"),
                 os.path.join(HOME, ".var", "app", "org.mozilla.firefox", "config", "mozilla", "firefox")):
        ini = read(os.path.join(base, "profiles.ini")) or ""
        for m in re.finditer(r"^Path=(.+)$", ini, flags=re.M):
            p = m.group(1).strip()
            p = p if os.path.isabs(p) else os.path.join(base, p)
            if os.path.isdir(p) and p not in out:
                out.append(p)
    return out

def firefox_css(c):
    v = {"--lwt-accent-color": c["bg"], "--lwt-accent-color-inactive": c["bg"], "--lwt-text-color": c["text"],
         "--toolbar-bgcolor": c["surface"], "--toolbar-color": c["text"],
         "--toolbar-field-background-color": c["bg"], "--toolbar-field-color": c["text"],
         "--toolbar-field-focus-background-color": c["bg"], "--toolbar-field-focus-color": c["text"],
         "--toolbar-field-focus-border-color": c["accent"], "--toolbar-field-border-color": "transparent",
         "--tab-selected-bgcolor": c["surface"], "--tab-selected-textcolor": c["text"],
         "--lwt-selected-tab-background-color": c["surface"], "--tab-loading-fill": c["accent"],
         "--toolbarbutton-icon-fill": c["text"], "--arrowpanel-background": c["surface"],
         "--arrowpanel-color": c["text"], "--arrowpanel-border-color": c["divider"],
         "--panel-separator-color": c["divider"], "--sidebar-background-color": c["bg"],
         "--sidebar-text-color": c["text"], "--focus-outline-color": c["accent"],
         "--button-primary-bgcolor": c["accent"], "--button-primary-color": c["accentText"],
         "--urlbarView-highlight-background": c["selection"], "--urlbarView-highlight-color": c["text"]}
    body = "\n".join("  %s: %s !important;" % kv for kv in v.items())
    return ("/* %s */\n:root, #navigator-toolbox, menupopup, panel {\n%s\n}\n"
            "#navigator-toolbox, #TabsToolbar, #titlebar { background-color: %s !important; }\n" % (GEN, body, c["bg"]))

@app("firefox", "Firefox", "Toolbars, tabs and menus in Slate's colours (userChrome.css), after a restart",
     lambda: bool(firefox_profiles()))
def firefox(ctx):
    css = firefox_css(ctx.c)
    for p in firefox_profiles():
        ctx.file(os.path.join(p, "chrome", "slate.css"), css)
        ctx.line(os.path.join(p, "chrome", "userChrome.css"), '@import "slate.css";', top=True)   # imports go first
        ctx.line(os.path.join(p, "user.js"), 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);')


# ---- For Settings → App Theming: what each app is, its website, and its packages ------------
# Packages by distro family (as install.sh and slate-system work it out), only where the
# distro's own repositories have it; elsewhere Settings just links to the website. NixOS is
# left to your configuration.
INFO = {
    "gtk": ("The toolkit behind GNOME's apps and many others", "https://www.gtk.org", {}),
    "qt": ("Sets the look of Qt apps outside KDE", "https://github.com/trialuser02/qt6ct",
           {"arch": "qt6ct", "debian": "qt6ct", "fedora": "qt6ct", "opensuse": "qt6ct"}),
    "kde": ("Apps from the KDE community", "https://apps.kde.org", {}),
    "kitty": ("A fast terminal that uses the graphics card", "https://sw.kovidgoyal.net/kitty/",
              {"arch": "kitty", "debian": "kitty", "fedora": "kitty", "opensuse": "kitty"}),
    "alacritty": ("A fast, minimal terminal", "https://alacritty.org",
                  {"arch": "alacritty", "debian": "alacritty", "fedora": "alacritty", "opensuse": "alacritty"}),
    "ghostty": ("A fast terminal with native tabs and splits", "https://ghostty.org", {"arch": "ghostty"}),
    "foot": ("A light, fast terminal for Wayland", "https://codeberg.org/dnkl/foot",
             {"arch": "foot", "debian": "foot", "fedora": "foot", "opensuse": "foot"}),
    "wezterm": ("A terminal with tabs, splits and a Lua config", "https://wezterm.org", {"arch": "wezterm"}),
    "btop": ("A system monitor for the terminal", "https://github.com/aristocratos/btop",
             {"arch": "btop", "debian": "btop", "fedora": "btop", "opensuse": "btop"}),
    "texteditor": ("GNOME's simple text editor", "https://apps.gnome.org/TextEditor/",
                   {"arch": "gnome-text-editor", "debian": "gnome-text-editor", "fedora": "gnome-text-editor",
                    "opensuse": "gnome-text-editor"}),
    "vscode": ("Microsoft's code editor, and its open builds", "https://code.visualstudio.com", {"arch": "code"}),
    "zed": ("A fast code editor built for collaboration", "https://zed.dev", {"arch": "zed"}),
    "helix": ("A modal text editor for the terminal", "https://helix-editor.com",
              {"arch": "helix", "fedora": "helix", "opensuse": "helix"}),
    "vim": ("The classic terminal text editor (installs Neovim)", "https://neovim.io",
            {"arch": "neovim", "debian": "neovim", "fedora": "neovim", "opensuse": "neovim"}),
    "bat": ("cat with syntax highlighting", "https://github.com/sharkdp/bat",
            {"arch": "bat", "debian": "bat", "fedora": "bat", "opensuse": "bat"}),
    "fzf": ("A fuzzy finder for the terminal", "https://junegunn.github.io/fzf/",
            {"arch": "fzf", "debian": "fzf", "fedora": "fzf", "opensuse": "fzf"}),
    "yazi": ("A fast file manager for the terminal", "https://yazi-rs.github.io", {"arch": "yazi"}),
    "cava": ("An audio visualiser for the terminal", "https://github.com/karlstav/cava",
             {"arch": "cava", "debian": "cava", "fedora": "cava", "opensuse": "cava"}),
    "zathura": ("A keyboard-driven document viewer", "https://pwmt.org/projects/zathura/",
                {"arch": "zathura zathura-pdf-mupdf", "debian": "zathura", "fedora": "zathura zathura-pdf-mupdf",
                 "opensuse": "zathura"}),
    "discord": ("Discord with Vencord's themes and plugins", "https://vesktop.dev", {}),
    "spotify": ("Themes and extensions for Spotify", "https://spicetify.app", {}),
    "obsidian": ("Notes in plain Markdown files", "https://obsidian.md", {"arch": "obsidian"}),
    "firefox": ("Mozilla's web browser", "https://www.mozilla.org/firefox/",
                {"arch": "firefox", "debian": "firefox-esr", "fedora": "firefox", "opensuse": "MozillaFirefox"}),
}


# Each app's desktop entries (the first one found is what Settings' Open button starts), for
# its native, Flatpak and other builds. Apps with none to open (GTK, KDE, bat, fzf) aren't here.
DESKTOP = {
    "qt": ["qt6ct", "qt5ct"],
    "kitty": ["kitty"],
    "alacritty": ["Alacritty", "alacritty"],
    "ghostty": ["com.mitchellh.ghostty"],
    "foot": ["foot"],
    "wezterm": ["org.wezfurlong.wezterm"],
    "btop": ["btop"],
    "texteditor": ["org.gnome.TextEditor"],
    "vscode": ["code", "code-oss", "codium", "visual-studio-code", "com.visualstudio.code", "com.vscodium.codium"],
    "zed": ["dev.zed.Zed", "zed"],
    "helix": ["Helix", "helix", "com.helix_editor.Helix"],
    "vim": ["nvim", "vim", "gvim", "io.neovim.nvim"],
    "yazi": ["yazi"],
    "zathura": ["org.pwmt.zathura"],
    "discord": ["vesktop", "dev.vencord.Vesktop", "equibop", "discord", "com.discordapp.Discord"],
    "spotify": ["spotify", "spotify-launcher", "com.spotify.Client"],
    "obsidian": ["obsidian", "md.obsidian.Obsidian"],
    "firefox": ["firefox", "org.mozilla.firefox", "firefox-esr"],
}


def family(os_release="/etc/os-release"):
    """arch, debian, fedora, opensuse, nixos or "" (as install.sh and slate-system decide)"""
    ids = []
    try:
        with open(os_release, encoding="utf-8") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k in ("ID", "ID_LIKE"):
                    ids += v.strip('"').split()
    except OSError:
        pass
    groups = {"arch": ("arch", "cachyos", "endeavouros", "manjaro", "garuda"),
              "debian": ("debian", "ubuntu", "linuxmint", "pop", "elementary", "zorin"),
              "fedora": ("fedora", "rhel", "centos", "nobara", "ultramarine"),
              "opensuse": ("suse", "sles"), "nixos": ("nixos",)}
    for i in ids:
        for fam, names in groups.items():
            if i in names or (fam == "opensuse" and i.startswith("opensuse")):
                return fam
    return ""


def detect():
    """[{id, label, detail, installed, about, url, packages, desktop}] for Settings; packages:
    what installs it here ("" when this distro doesn't have it); desktop: its desktop entries"""
    fam = family()
    out = []
    for a in APPS:
        try:
            inst = bool(a["installed"]())
        except Exception:
            inst = False
        about, url, pkgs = INFO.get(a["id"], ("", "", {}))
        out.append({"id": a["id"], "label": a["label"], "detail": a["detail"], "installed": inst,
                    "about": about, "url": url, "packages": pkgs.get(fam, ""), "desktop": DESKTOP.get(a["id"], [])})
    return out
