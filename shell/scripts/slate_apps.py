"""The apps Slate themes (Settings → Appearance → App theming). Each entry:
  id, label, detail     shown in Settings
  installed()           whether the app is on this computer
  apply(ctx)            writes its theme from ctx.c (Slate's colours) through ctx, which
                        records every change so switching the app off undoes it
  reload(ctx)           optional: make running copies pick up the new colours
Only installed apps that aren't switched off are themed; switching one off reverses what
Slate did to it (slate_theme.Ctx.undo)."""
import glob
import json
import os
import re

from slate_theme import (CFG, DATA, GEN, HOME, SHELL_DIR, bare, first_existing, have, mix,
                         read, run, run_out, signal_all, touched, write)

APPS = []

def app(id, label, detail, installed):
    def deco(fn):
        APPS.append({"id": id, "label": label, "detail": detail, "installed": installed, "apply": fn, "reload": None})
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
    return "\n".join(out) + "\n"

@app("gtk", "GTK apps", "Files, Text Editor, Calculator and other GNOME and GTK apps", lambda: True)
def gtk(ctx):
    c = ctx.c
    for v in (3, 4):
        ctx.file(cfg("gtk-%d.0" % v, "slate.css"), gtk_css(c, v))
        ctx.line(cfg("gtk-%d.0" % v, "gtk.css"), '@import url("slate.css");')   # last, so its colours win
    dark = not c["light"]
    ctx.ini(cfg("gtk-3.0", "settings.ini"), "Settings", "gtk-application-prefer-dark-theme", "1" if dark else "0")
    ctx.gsetting("org.gnome.desktop.interface", "color-scheme", "prefer-dark" if dark else "prefer-light")
    ctx.gsetting("org.gnome.desktop.interface", "gtk-theme", "adw-gtk3-dark" if dark else "adw-gtk3")

@reloads("gtk")
def gtk_reload(ctx):
    if not (touched("gtk-3.0") or touched("gtk-4.0")):
        return
    # GTK apps re-read their theme and gtk.css when the theme name changes: switch away and back
    cur = (run_out(["gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"]) or "").strip().strip("'")
    if cur:
        import time
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


@app("qt", "Qt apps", "Apps that use qt6ct for their look", lambda: have("qt6ct") or isdir(CFG, "qt6ct"))
def qt(ctx):
    c = ctx.c
    # windowText,button,light,midlight,dark,mid,text,brightText,buttonText,base,window,shadow,
    # highlight,highlightedText,link,linkVisited,alternateBase,noRole,toolTipBase,toolTipText,
    # placeholderText,accent
    roles = [c["text"], c["bg"], "#ffffff", "#cacaca", "#9f9f9f", "#b8b8b8", c["text"], "#ffffff",
             c["text"], c["bg"], c["bg"], c["shadow"], c["selection"], c["accent"], c["secondary"],
             c["accent"], c["surface"], c["bg"], c["surface"], c["text"], c["text"] if not c["light"] else c["dim"], c["accent"]]
    row = ", ".join(roles)
    path = cfg("qt6ct", "colors", "slate.conf")
    ctx.file(path, "[ColorScheme]\n# %s\n"
             "# windowText,button,light,midlight,dark,mid,text,brightText,buttonText,base,window,shadow,highlight,"
             "highlightedText,link,linkVisited,alternateBase,noRole,toolTipBase,toolTipText,placeholderText,accent\n"
             "active_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n" % (GEN, row, row, row))
    conf = cfg("qt6ct", "qt6ct.conf")
    if os.path.exists(conf):
        ctx.ini_many(conf, [("Appearance", "color_scheme_path", path), ("Appearance", "custom_palette", "true")])

@reloads("qt")
def qt_reload(ctx):
    conf = cfg("qt6ct", "qt6ct.conf")
    if touched("qt6ct") and os.path.exists(conf):
        # qt6ct apps watch the folder: replace qt6ct.conf (same contents) to nudge them
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

@app("kde", "KDE apps", "Dolphin, Kate and other KDE apps (kdeglobals)", lambda: True)
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


@app("wezterm", "WezTerm", "A Slate colour scheme (pick \"Slate\" in your config); a starting config if you have none",
     lambda: have("wezterm"))
def wezterm(ctx):
    c = ctx.c
    q = lambda h: '"%s"' % h
    out = ["# " + GEN, "[colors]", "foreground = %s" % q(c["text"]), "background = %s" % q(c["bg"]),
           "cursor_bg = %s" % q(c["text"]), "cursor_fg = %s" % q(c["bg"]), "cursor_border = %s" % q(c["text"]),
           "selection_bg = %s" % q(c["surface"] if not c["light"] else c["selection"]), "selection_fg = %s" % q(c["text"]),
           "ansi = [%s]" % ", ".join(q(h) for h in c["ansi"]),
           "brights = [%s]" % ", ".join(q(h) for h in c["ansiBright"]),
           "", "[metadata]", 'name = "Slate"']
    ctx.file(cfg("wezterm", "colors", "slate.toml"), "\n".join(out) + "\n")
    if not first_existing(cfg("wezterm", "wezterm.lua"), os.path.join(HOME, ".wezterm.lua")):
        ctx.start(cfg("wezterm", "wezterm.lua"), starting("wezterm.lua"))


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
     lambda: have("gnome-text-editor"))
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
    ctx.file(os.path.join(DATA, "gtksourceview-5", "styles", "slate.xml"),
             '<?xml version="1.0" encoding="UTF-8"?>\n<!-- %s -->\n'
             '<style-scheme id="slate" name="Slate" version="1.0">\n  <author>Slate</author>\n'
             "  <description>Slate's colours, following its light or dark theme</description>\n"
             % GEN + "\n".join(rows) + "\n</style-scheme>\n")
    ctx.gsetting("org.gnome.TextEditor", "style-scheme", "slate",
                 only_if=("", "Adwaita", "Adwaita-dark", "classic", "classic-dark"))


# -- VS Code, Code - OSS and VSCodium: a theme extension, selected in your settings --
VSCODES = [("Code", ".vscode"), ("Code - OSS", ".vscode-oss"), ("VSCodium", ".vscode-oss"), ("Code - Insiders", ".vscode-insiders")]

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

@app("vscode", "VS Code", "VS Code, Code - OSS and VSCodium: a Slate theme, selected for you",
     lambda: any(isdir(CFG, name, "User") for name, _ in VSCODES))
def vscode(ctx):
    c = ctx.c
    ext_id, ver = "slate.slate-theme", "1.0.0"
    folder = "%s-%s" % (ext_id, ver)
    pkg = {"name": "slate-theme", "displayName": "Slate", "description": "Slate's colours. " + GEN,
           "publisher": "slate", "version": ver, "engines": {"vscode": "^1.60.0"}, "categories": ["Themes"],
           "contributes": {"themes": [{"label": "Slate", "uiTheme": "vs" if c["light"] else "vs-dark",
                                       "path": "./themes/slate.json"}]}}
    for name, extdir in VSCODES:
        user = cfg(name, "User")
        if not os.path.isdir(user):
            continue
        exts = os.path.join(HOME, extdir, "extensions")
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

@app("zed", "Zed", "A Slate theme, selected for you", lambda: have("zed") or have("zeditor") or isdir(CFG, "zed"))
def zed(ctx):
    ctx.file(cfg("zed", "themes", "slate.json"), json.dumps(zed_theme(ctx.c), indent=2) + "\n")
    ctx.jsonc(cfg("zed", "settings.json"), "theme", "Slate")


@app("helix", "Helix", "A Slate theme, selected for you", lambda: have("hx") or have("helix"))
def helix(ctx):
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
    ctx.file(cfg("helix", "themes", "slate.toml"), "# " + GEN + "\n" + "\n".join("%s = %s" % r for r in rows) + "\n")
    conf = cfg("helix", "config.toml")
    if re.search(r'^theme\s*=', read(conf) or "", flags=re.M):
        ctx.replace(conf, r'^theme\s*=.*$', 'theme = "slate"')
    else:
        ctx.line(conf, 'theme = "slate"', top=True)                 # top-level keys go first

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

@app("vim", "Vim and Neovim", "A Slate colour scheme (%s), used unless you set your own" % VIM_NAME,
     lambda: have("vim") or have("nvim"))
def vim(ctx):
    text = vim_colors(ctx.c)
    use = "colorscheme " + VIM_NAME
    if have("vim"):
        ctx.file(os.path.join(HOME, ".vim", "colors", VIM_NAME + ".vim"), text)
        rc = first_existing(os.path.join(HOME, ".vimrc"), os.path.join(HOME, ".vim", "vimrc"))
        if rc is None:
            rc = os.path.join(HOME, ".vimrc")
            ctx.start(rc, "\" Vim's usual defaults (a vimrc of your own turns them off)\nsource $VIMRUNTIME/defaults.vim\n")
        ctx.line(rc, use, present=r"^\s*colorscheme\s")
    if have("nvim"):
        ctx.file(cfg("nvim", "colors", VIM_NAME + ".vim"), text)
        lua, vimrc = cfg("nvim", "init.lua"), cfg("nvim", "init.vim")
        if os.path.exists(lua):
            # Leave configs that pick their own scheme (or use a plugin manager) alone
            if not re.search(r"colorscheme|lazy|packer|plug", read(lua) or ""):
                ctx.line(lua, 'vim.cmd.colorscheme("%s")' % VIM_NAME)
        elif os.path.exists(vimrc):
            ctx.line(vimrc, use, present=r"^\s*colorscheme\s")
        else:
            ctx.start(lua, "-- Neovim config\n")
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
    ctx.start(conf, "# cava config (see https://github.com/karlstav/cava)\n")
    ctx.ini_many(conf, [("color", k, v) for k, v in (
        ("gradient", "1"), ("gradient_count", "3"), ("gradient_color_1", "'%s'" % c["tertiary"]),
        ("gradient_color_2", "'%s'" % c["accent"]), ("gradient_color_3", "'%s'" % c["magenta"]))], sep=" = ")

@reloads("cava")
def cava_reload(ctx):
    if touched("cava"):
        signal_all("cava", "USR2")           # cava reloads its colours on SIGUSR2


@app("zathura", "zathura", "The document viewer's colours (and its recolour mode)", lambda: have("zathura"))
def zathura(ctx):
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
    ctx.file(cfg("zathura", "slate"), "# %s\n" % GEN + "\n".join('set %s "%s"' % kv for kv in sets) + "\n")
    ctx.line(cfg("zathura", "zathurarc"), "include slate")


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

@app("discord", "Discord (Vencord)", "Vesktop, Vencord and Equicord: a Slate theme, switched on for you",
     lambda: any(isdir(CFG, d) for d in DISCORDS))
def discord(ctx):
    css = discord_css(ctx.c)
    for d in DISCORDS:
        root = cfg(d)
        if not os.path.isdir(root):
            continue
        ctx.file(os.path.join(root, "themes", "slate.theme.css"), css)
        settings = first_existing(os.path.join(root, "settings", "settings.json"), os.path.join(root, "settings.json"))
        if settings:
            ctx.jsonlist(settings, ["enabledThemes"], "slate.theme.css")


@app("spotify", "Spotify (Spicetify)", "A Slate theme for Spicetify, applied without restarting Spotify",
     lambda: have("spicetify"))
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
    cur = (run_out(["spicetify", "config", "current_theme"]) or "").strip()
    scheme = (run_out(["spicetify", "config", "color_scheme"]) or "").strip()
    if cur != "Slate":
        ctx.command(["spicetify", "config", "current_theme", "Slate", "color_scheme", "slate"],
                    ["spicetify", "config", "current_theme", cur or "marketplace", "color_scheme", scheme or ""])

@reloads("spotify")
def spotify_reload(ctx):
    if touched("spicetify") and ctx.live:
        run(["spicetify", "apply", "-n", "-q"], timeout=120)     # -n: don't restart Spotify


def firefox_profiles():
    out = []
    for base in (os.path.join(HOME, ".mozilla", "firefox"), cfg("mozilla", "firefox")):
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


def detect():
    """[{id, label, detail, installed}] for Settings"""
    out = []
    for a in APPS:
        try:
            inst = bool(a["installed"]())
        except Exception:
            inst = False
        out.append({"id": a["id"], "label": a["label"], "detail": a["detail"], "installed": inst})
    return out
