"""Things that must agree across files: settings keys, Settings pages, lists kept in two
places, the site's links, shaders built from their sources."""
import hashlib
import html.parser
import json
import os
import re
import subprocess

import slate
from slate import Case


def settings_keys():
    """Every setting in SettingsData.qml: {name: type}."""
    src = slate.read("shell", "SettingsData.qml")
    return dict((n, t) for t, n in re.findall(r"^\s*property\s+([\w<>]+)\s+(\w+)\s*:", src, re.M))


def settings_pages():
    src = slate.read("shell", "SettingsIndex.qml")
    block = re.search(r"readonly property var pages:\s*\[(.*?)\n\s*\]", src, re.S).group(1)
    return re.findall(r"\{\s*id:\s*\"(\w+)\"", block)


def settings_window():
    return slate.read("shell", "SettingsWindow.qml")


def settings_page_sources():
    """Each Settings page's own QML: {page id: the text of its file in shell/settings/pages/},
    found through the window's `Component { id: <name>Page; <Type> {} }` for it."""
    src = settings_window()
    block = js_object_block(src, src.index("sourceComponent: ({"))
    pages = {comp: page for page, comp in re.findall(r"(\w+):\s*(\w+Page)\b", block)}
    types = dict(re.findall(r"^    Component \{ id: (\w+Page); (\w+) \{\} \}$", src, re.M))
    return {pages[comp]: slate.read("shell", "settings", "pages", typ + ".qml") for comp, typ in types.items() if comp in pages}


def curated_search_entries():
    """SettingsIndex.qml's hand-kept search entries: [(name, page, extra words)]."""
    src = slate.read("shell", "SettingsIndex.qml")
    block = src.split("readonly property var curated: [")[1].split("\n    ]")[0]
    found = re.findall(r'^\s*\[\s*"((?:[^"\\]|\\.)*)",\s*"(\w+)",\s*"((?:[^"\\]|\\.)*)"\s*\],?\s*$', block, re.M)
    lines = [l for l in block.splitlines() if l.strip().startswith("[")]
    assert len(found) == len(lines), "a curated entry isn't written as [\"name\", \"page\", \"words\"]"
    return found


def js_object_block(src, start):
    """The text of a `({ … })` starting at `start`, matched by brackets."""
    i = src.index("(", start)
    depth = 0
    for j in range(i, len(src)):
        if src[j] in "({[":
            depth += 1
        elif src[j] in ")}]":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    raise ValueError("unbalanced")


def tracked_files():
    """Files in the repo (git's list when there is one: tracked plus new, not ignored)."""
    try:
        out = subprocess.run(["git", "-C", slate.ROOT, "ls-files", "-co", "--exclude-standard"],
                             capture_output=True, text=True, check=True).stdout
        return [f for f in out.splitlines() if os.path.isfile(slate.path(f))]
    except (OSError, subprocess.CalledProcessError):
        return [f for f in slate.files(".", "") if not f.startswith(("tests/out", ".git/"))]


class Settings(Case):
    def test_pages_have_a_page(self):
        """Every page in SettingsIndex.pages is in SettingsWindow's loader map, and each
        component the map names exists."""
        src = settings_window()
        block = js_object_block(src, src.index("sourceComponent: ({"))
        mapping = dict(re.findall(r"(\w+):\s*(\w+Page)\b", block))
        for page in settings_pages():
            with self.subTest(page):
                self.assertIn(page, mapping, f"Settings page '{page}' isn't in SettingsWindow's loader map")
                self.assertRegex(src, rf"\bid:\s*{mapping[page]}\b", f"component {mapping[page]} doesn't exist")

    def test_page_ids_unique(self):
        pages = settings_pages()
        dupes = sorted({p for p in pages if pages.count(p) > 1})
        self.assertFalse(dupes, f"repeated page ids: {dupes}")

    def test_page_keys_exist(self):
        """Every key a page restores to its default (pageKeys) is a setting, on a real page."""
        keys = settings_keys()
        src = settings_window()
        block = js_object_block(src, src.index("pageKeys: ({"))
        pages = set(settings_pages()) | {"overview"}
        for page, body in re.findall(r"(\w+):\s*\[(.*?)\]", block, re.S):
            with self.subTest(page):
                self.assertIn(page, pages, f"pageKeys has a page that doesn't exist: {page}")
                missing = [k for k in re.findall(r"\"(\w+)\"", body) if k not in keys]
                self.assertFalse(missing, f"not in SettingsData.qml: {', '.join(missing)}")

    # Settings a page shows as changed (settingKey) but its Restore defaults leaves alone, on
    # purpose: each says why
    NOT_RESTORED = {
        # Night light on or off is how you have it right now, like a switch on the control
        # centre, not a preference of the page (the comment above pageKeys says so too)
        ("general", "nightLight"),
    }

    def test_page_keys_cover_the_page(self):
        """Every setting a page's rows name (`settingKey:`, or a switch's `key:`) is in that
        page's pageKeys. One that isn't shows the changed-from-default dot, yet the page title's
        Restore defaults neither counts it nor puts it back, and the assistant's settings
        changed / restore miss it too (Screensaver's Scenery quality was left out)."""
        src = settings_window()
        block = js_object_block(src, src.index("pageKeys: ({"))
        restored = {page: set(re.findall(r"\"(\w+)\"", body)) for page, body in re.findall(r"(\w+):\s*\[(.*?)\]", block, re.S)}
        sources = settings_page_sources()
        self.assertGreater(len(sources), 30, "the pages weren't found in SettingsWindow.qml")
        seen = set()
        for page, body in sorted(sources.items()):
            used = set(re.findall(r"\b(?:settingKey|key):\s*\"(\w+)\"", body))
            seen |= {(page, k) for k in used}
            missing = sorted(k for k in used - restored.get(page, set()) if (page, k) not in self.NOT_RESTORED)
            with self.subTest(page):
                self.assertFalse(missing, f"shown on the {page} page but not in pageKeys.{page}, so Restore defaults misses: {', '.join(missing)}")
        self.assertGreater(len(seen), 100, "far fewer settingKey/key rows found than Settings has")
        stale = sorted(f"{p}: {k}" for p, k in self.NOT_RESTORED - seen)
        self.assertFalse(stale, f"NOT_RESTORED lists a setting its page no longer shows: {stale}")

    # Curated search entries (SettingsIndex.curated) that aren't a row, a heading or the page's
    # name, on purpose
    # Another way of saying the whole page: the result opens it at the top
    SEARCH_PAGE_NAMES = {("General settings", "general"), ("Launcher settings", "launcher"), ("About Slate", "about")}
    # Rows the page makes from a list once it's open (the webcam's controls come from what the
    # camera offers), so scripts/settings-index.py can't see them: each must still be written
    # on its page as a label
    SEARCH_ROWS_MADE_IN_CODE = {(name, "webcam") for name in (
        "Brightness", "Contrast", "Color", "Sharpness", "Gain", "Gamma", "Color temperature", "Exposure",
        "Backlight compensation")}

    def test_search_entries_name_something_on_the_page(self):
        """Every curated search entry [name, page, words] names something search can take you
        to (SettingsWindow's showFound): a setting on that page as settings-index.py reports
        it (the entry then lends that row its words: SettingsIndex.entries), one of the page's
        headings, or the page itself. A name that's none of them is a second, dead result:
        it opens the page but can't scroll to anything ("Sound effects volume" outlived its
        slider; "Clicks sound" sat beside the real "Clicks" row instead of adding to it)."""
        out = subprocess.run(["python3", slate.path("shell", "scripts", "settings-index.py"),
                              slate.path("shell", "SettingsWindow.qml")], capture_output=True, text=True, check=True).stdout
        rows = {(r["page"], r["label"].lower()) for r in json.loads(out)}        # (as entries matches them)
        sources = settings_page_sources()
        index = slate.read("shell", "SettingsIndex.qml")
        page_names = dict(re.findall(r'\{ id: "(\w+)", label: "([^"]+)"', index))
        entries = curated_search_entries()
        self.assertGreater(len(entries), 100, "the curated entries weren't found in SettingsIndex.qml")
        used = set()
        for name, page, _words in entries:
            with self.subTest(f"{page}: {name}"):
                self.assertIn(page, sources, f"no such Settings page: {page}")
                if (page, name.lower()) in rows or page_names.get(page) == name:
                    continue
                # A heading is found by its exact text (GroupLabel { … text: "…" })
                if re.search(r'GroupLabel\s*\{[^}\n]*\btext:\s*"' + re.escape(name) + '"', sources[page]):
                    continue
                if (name, page) in self.SEARCH_PAGE_NAMES:
                    used.add((name, page))
                    continue
                if (name, page) in self.SEARCH_ROWS_MADE_IN_CODE:
                    used.add((name, page))
                    self.assertIn('"' + name + '"', sources[page], f"the {page} page no longer has a row called {name}")
                    continue
                self.fail(f'"{name}" isn\'t a setting or a heading on the {page} page: name the entry after the row '
                          "(its other names go in the words), or drop it if the setting has gone")
        unused = sorted(f"{p}: {n}" for n, p in (self.SEARCH_PAGE_NAMES | self.SEARCH_ROWS_MADE_IN_CODE) - used)
        self.assertFalse(unused, f"an exception for a search entry that's gone, or is a real row now: {unused}")

    def test_search_entries_are_not_repeated(self):
        """One curated entry per name and page: a second would be a second result (or lend its
        words twice)."""
        entries = [(page, name.lower()) for name, page, _words in curated_search_entries()]
        dupes = sorted({f"{p}: {n}" for p, n in entries if entries.count((p, n)) > 1})
        self.assertFalse(dupes, f"repeated curated search entries: {dupes}")

    def test_config_keys_exist(self):
        """Every Config.s.<key> the QML reads or writes is a setting in SettingsData.qml."""
        keys = settings_keys()
        used = {}
        for f in slate.files("shell", ".qml"):
            for m in re.finditer(r"\bConfig\.s\.(\w+)", slate.read(f)):
                used.setdefault(m.group(1), f)
        # inside Config.qml itself it's `s.<key>` / `root.s.<key>`
        # (lines where `s` is a function's own parameter, `s => …`, are someone else's s)
        for line in slate.read("shell", "Config.qml").splitlines():
            if re.search(r"\bs\s*=>|function\s*\w*\s*\([^)]*\bs\b", line):
                continue
            for m in re.finditer(r"(?<![\w.])(?:root\.)?s\.(\w+)", line):
                used.setdefault(m.group(1), "shell/Config.qml")
        known_methods = {"writeAdapter", "toString", "hasOwnProperty"}
        for key, where in sorted(used.items()):
            if key in known_methods:
                continue
            with self.subTest(key):
                self.assertTrue(key in keys, f"{where} uses Config.s.{key}, which isn't in SettingsData.qml")

    def test_config_functions_exist(self):
        """Every Config.something(…) called from a QML file is a function Config.qml has. (A
        call to one that's gone only warns as Slate runs, and what it was colouring turns black:
        the dock's glass did, when its dockSurface was dropped by mistake.)"""
        src = slate.read("shell", "Config.qml")
        have = set(re.findall(r"^\s*function (\w+)\(", src, re.M)) | set(re.findall(r"^\s*signal (\w+)", src, re.M))
        # (a property holding a function, or one of QtObject's own)
        have |= set(re.findall(r"^\s*(?:readonly )?property var (\w+):", src, re.M)) | {"toString", "destroy"}
        shell = slate.path("shell")
        for root, _, files in os.walk(shell):
            for name in files:
                if not name.endswith(".qml"):
                    continue
                text = open(os.path.join(root, name), encoding="utf-8").read()
                for fn in sorted(set(re.findall(r"\bConfig\.(\w+)\(", text))):
                    with self.subTest(os.path.relpath(os.path.join(root, name), shell) + ": Config." + fn):
                        self.assertIn(fn, have, f"Config.{fn}() is called here, but Config.qml has no such function")

    def test_glass_blurs_every_popup(self):
        """Slate's pop-ups are blurred behind with glass: each one's layer is named in the rule
        (the dock's window previews were left out, and showed the desktop sharp through them)."""
        m = re.search(r'glassRule\("SLATE_GLASS", "\^slate-\(([^)]*)\)\$"', slate.read("shell", "Config.qml"))
        self.assertTrue(m, "the glass rule for pop-ups has gone")
        named = set(m.group(1).split("|"))
        # (notifications have a rule of their own, with their own opacity: SLATE_GLASS_TOAST)
        self.assertIn('glassRule("SLATE_GLASS_TOAST", "^slate-notifications$"', slate.read("shell", "Config.qml"))
        for own in ('"SLATE_GLASS_LAUNCHER", "^slate-launcher$"', '"SLATE_GLASS_CHALK", "^slate-assistant$"'):
            self.assertIn("glassRule(" + own, slate.read("shell", "Config.qml"))
        for layer in ("dock-previews", "picker", "switcher",
                      "tray-menu", "desktop-menu", "confirm", "polkit", "osd", "bar-label"):
            with self.subTest(layer):
                self.assertIn(layer, named, f"slate-{layer} isn't blurred behind with glass")

    def test_interface_size_reaches_everything(self):
        """Interface size scales Slate through QT_SCALE_FACTOR on its process. Two things escape
        that: a window drawn by another process, and a position or size taken from Hyprland (in
        its pixels) used as Slate's. So every file that reads Hyprland's pointer or a window's
        place must use Config.uiScale, and every `qs` that bin/slate starts to draw something
        must be handed the scale. (The reload cover and the bar's arranging panel once weren't.)"""
        shell = os.path.join(slate.ROOT, "shell")
        # Files that only compare Hyprland's numbers with each other need no scale: say why here
        same_units = {"Switcher.qml": "the window's place and its monitor's size are both Hyprland's"}
        for name in sorted(os.listdir(shell)):
            if not name.endswith(".qml") or name in same_units:
                continue
            src = slate.read("shell", name)
            if re.search(r'"cursorpos"|lastIpcObject\??\.at\b|\bo\.at\[|\bc\.at\[|\bg\.at\[', src):
                with self.subTest(name):
                    self.assertIn("Config.uiScale", src,
                                  f"{name} takes a position from Hyprland but never uses Config.uiScale")
        launcher = slate.read("shell", "bin", "slate")
        started = 0
        for n, line in enumerate(launcher.splitlines(), 1):
            # (every qs that runs a config: started detached, or by the keeper that restarts
            # Slate after a crash; not `qs list`, `qs kill` or an ipc call to one that's running)
            if re.search(r"\bqs (-n )?-p ", line) and not re.search(r"\bipc\b", line):
                started += 1
                with self.subTest(f"bin/slate:{n}"):
                    self.assertIn("QT_SCALE_FACTOR", line, "a Slate window is started without the Interface size")
        # (Slate itself, with and without a scale, and the reload cover, the same: so the
        # pattern above still finds them when a line is written another way)
        self.assertGreaterEqual(started, 4, "bin/slate's qs launches weren't found")

    def test_accent_fills_on_pressable_controls_light_under_the_pointer(self):
        """The lit accent (CONVENTIONS, "The lit accent"): a switch that's on, a primary button,
        anything filled with the active colour that a click acts on, goes lighter under the
        pointer through Config.accentFor(hovered). A fill like `color: checked ? win.accent : ...`
        (the condition is checked, primary, on or lit) that skips it is flagged. What's chosen
        and stays chosen when clicked, and the knobs and glyphs drawn on a switch, are listed."""
        chosen_or_decoration = {
            ("AvatarPicker.qml", "color: on ? pk.accent"),                 # the chosen picture
            ("HotCornerPicker.qml", "color: corner.on ? Qt.rgba"),         # the chosen corner
            ("HotCornerPicker.qml", "color: corner.on ? hp.accent"),       # its glyph
            ("Launcher.qml", "color: toggleSwitch.on ? (row.onAccent"),    # the switch's knob
            ("NovaMic.qml", "color: mic.lit ? mic.accentText"),            # its glyph
            ("panels/SpacesPanel.qml", "color: wsCard.on ? pop.accent"),              # a number badge
            ("SettingsWindow.qml", "color: on ? win.accent"),              # chosen options, segments
            ("Welcome.qml", "color: on ? w.accent"),                       # the chosen theme option
        }
        line_re = re.compile(r"^\s*color:\s*([\w.!]+)\s*\?(.*)$")
        for name in slate.qml_names():
            for n, line in enumerate(slate.read("shell", name).splitlines(), 1):
                m = line_re.match(line)
                if not m or m.group(1).split(".")[-1] not in ("checked", "primary", "on", "lit"):
                    continue
                if not re.search(r"\b\w+\.accent\b(?!Text|Lit|Shade)", m.group(2)):
                    continue
                if "accentFor" in line or "accentLit" in line:
                    continue
                if any(name == f and line.strip().startswith(start) for f, start in chosen_or_decoration):
                    continue
                with self.subTest(f"{name}:{n}"):
                    self.fail(f"{name}:{n} fills with the plain accent on something a click acts on: "
                              f"use Config.accentFor(<hover>.hovered) ({line.strip()})")

    def test_title_bar_converts_once_at_the_edge(self):
        """TitleBar.qml draws on a window Hyprland places, and places it from the pointer: it
        mentioned Config.uiScale (so the test above passed) while using Hyprland's pixels as
        Slate's units throughout, which only works at 100%. Its rule now: what's read from
        Hyprland is divided by the scale as it's read, what's sent goes through toHypr(), and
        nothing drawn is multiplied by the scale (Qt already does that)."""
        src = slate.read("shell", "TitleBar.qml")
        code = [l.split("//")[0] for l in src.splitlines()]
        for name, read in (("winX", r"\(o\.at\[0\] - mon\.x\) / s"), ("winY", r"\(o\.at\[1\] - mon\.y\) / s"),
                           ("winW", r"o\.size\[0\] / s"), ("winH", r"o\.size\[1\] / s")):
            with self.subTest(name):
                line = next((l for l in code if re.search(rf"readonly property real {name}:", l)), "")
                self.assertRegex(line, read, f"{name} is the window's place from Hyprland: divide it by the scale")
        for n, line in enumerate(code, 1):
            # A place or size handed to Hyprland from the bar's own (Slate's) numbers
            if re.search(r"slateDragMove|slateDragResize|cursor\.move", line):
                with self.subTest(f"TitleBar.qml:{n}"):
                    numbers = re.findall(r"\$\{([^}]*)\}", line.split('("${address}"', 1)[-1])
                    self.assertTrue(numbers, "no place sent?")
                    for expr in numbers:
                        # (toHypr on the line itself, or a value the lines just above made with it)
                        made = any(re.search(rf"\b{re.escape(v)} = toHypr\(", "\n".join(code[max(0, n - 6):n]))
                                   for v in re.findall(r"[A-Za-z_]\w*", expr))
                        self.assertTrue("toHypr(" in expr or made,
                                        f"{expr} goes to Hyprland in Slate's units: toHypr() it")
            # A size multiplied by the scale is drawn twice as scaled (the scale is `s` here);
            # only toHypr itself and the bar's height in Hyprland's pixels may
            if re.search(r"\*\s*(tb\.)?s\b(?!\.)", line) and "function toHypr" not in line and "property int barPx" not in line:
                with self.subTest(f"TitleBar.qml:{n}"):
                    self.fail(f"multiplied by the Interface size, which Qt already applies: {line.strip()}")

    def test_small_pictures_are_not_decoded_at_full_size(self):
        """A thumbnail, avatar or cover is drawn a few dozen to a few hundred pixels wide, but a
        photo can be thousands across: an Image with no sourceSize decodes all of it. So the
        shared ones (RoundImage, the screensaver's Drifting, Settings' WallTile) say a size."""
        def block(src, start):
            i = src.index(start)
            depth = 0
            for end in range(src.index("{", i), len(src)):
                depth += (src[end] == "{") - (src[end] == "}")
                if depth == 0:
                    return src[i:end]
            self.fail(f"{start}: block not closed")
        tile = slate.read("shell", "settings", "WallTile.qml")
        cases = [
            ("RoundImage's Image", block(slate.read("shell", "RoundImage.qml"), "Image {")),
            ("Drifting", block(slate.read("shell", "Screensaver.qml"), "component Drifting: Image {")),
            ("WallTile's Image", block(tile[tile.index("Image {"):], "Image {")),
        ]
        for label, body in cases:
            with self.subTest(label):
                self.assertRegex(body, r"sourceSize(\.width|\.height)?\s*:", f"{label} has no sourceSize")
        self.assertIn("tile.small ?", tile, "a hidden too-small tile still decodes its picture")

    def test_rounded_corners_go_through_config(self):
        """Settings → Appearance → Rounded UI elements squares everything, which works because
        every corner is written Config.corner(radius). A corner given as a plain number would
        stay round with the setting off. (App icons and workspace dots keep shapes of their own,
        from Config.iconCornerFor and Config.dotRadius.)"""
        shell = os.path.join(slate.ROOT, "shell")
        skip = {"SlateMark.qml", "SlateLogo.qml", "FolderSwatch.qml", "Config.qml", "SettingsData.qml", "SettingsIndex.qml"}
        bare = re.compile(r"(?<![A-Za-z0-9_.])(radius|topLeftRadius|topRightRadius|bottomLeftRadius|bottomRightRadius)\s*:\s*(\d+(?:\.\d+)?)\b(?!\s*[*/+-])")
        for name in sorted(os.listdir(shell)):
            if not name.endswith(".qml") or name in skip:
                continue
            for n, line in enumerate(slate.read("shell", name).splitlines(), 1):
                code = line.split("//")[0]
                for m in bare.finditer(code):
                    if float(m.group(2)) > 0:
                        with self.subTest(f"{name}:{n}"):
                            self.fail(f"{name}:{n}: a corner of {m.group(2)} that isn't Config.corner(…): {line.strip()[:90]}")

    def test_slider_default_hints(self):
        """A row's changed-from-default dot says what the default is, as its slider shows it. A
        slider that shows a setting in other units (a 0–1 setting as a percentage) says so with
        `per`; and a default the slider can't show (one that means "not set here") has its
        row say it in words (`defaultText`). Menu Bar's opacity sliders once said the default
        was 1% for a setting that starts at 80%."""
        src = slate.read("shell", "SettingsWindow.qml")
        data = slate.read("shell", "SettingsData.qml")
        defaults = {m.group(1): float(m.group(2)) for m in re.finditer(r"property (?:real|int) (\w+): (-?[\d.]+)", data)}
        rows = re.split(r"\n\s*SettingRow \{", src)[1:]
        seen = 0
        for row in rows:
            key = re.search(r'settingKey: "(\w+)"', row[:600])
            slider = re.search(r"ValueSlider \{(.*?onMoved[^\n]*)", row[:2500], re.S)
            if not key or not slider or (key.end() > slider.start()) or key.group(1) not in defaults:
                continue
            k, body = key.group(1), slider.group(1)
            if "Config.s." + k not in body:
                continue
            seen += 1
            with self.subTest(k):
                scaled = re.search(r"Config\.s\.%s = (?:Math\.round\()?v / (\d+)" % k, body)
                per = re.search(r"\bper: (\d+)", body)
                if scaled:
                    self.assertTrue(per and per.group(1) == scaled.group(1),
                                    f"{k}'s slider stores v / {scaled.group(1)}: it needs per: {scaled.group(1)} for its default hint")
                else:
                    self.assertIsNone(per, f"{k}'s slider has per: but stores its value as it is")
                lo, hi = re.search(r"\bfrom: (-?[\d.]+)", body), re.search(r"\bto: (-?[\d.]+)", body)
                if lo and hi:
                    shown = defaults[k] * (int(per.group(1)) if per else 1)
                    if not float(lo.group(1)) <= shown <= float(hi.group(1)):
                        self.assertIn("defaultText:", row[:key.end() + 400],
                                      f"{k} starts at {defaults[k]}, which its slider can't show: its row needs defaultText")
        self.assertGreater(seen, 25, "far fewer slider rows found than Settings has")

    def test_switched_off_settings_say_what_they_need(self):
        """A setting greyed out because another one is off (Accent boldness without Accent
        colour from wallpaper, say) says which one, with a way there: its row's needsMet,
        needs, needsPage and needsLabel (SettingRow), rather than an `enabled:` or a dimming
        of its own tied to Config.s, which once left people wondering why a slider wouldn't
        move. Each one leads to a page that exists and a setting with that name."""
        src = settings_window()
        lines = src.splitlines()
        # Properties worked out from settings (`readonly property bool applies: Config.s.…`)
        derived = set(re.findall(r"^\s*(?:readonly\s+)?property\s+\w+\s+(\w+)\s*:[^\n]*Config\.s\.", src, re.M))
        tied = re.compile(r"Config\.s\.|\b(?:%s)\b" % "|".join(map(re.escape, derived)) if derived else r"Config\.s\.")
        for n, line in enumerate(lines, 1):
            code = line.split("//")[0]
            # (on a line of its own, or inline: `Toggle { checked: …; enabled: … }`)
            for m in re.finditer(r"(?:^|[{;])\s*(enabled|opacity)\s*:([^;}]*)", code):
                # (an opacity that dims, not a hover fill fading in: 0.4 against 1)
                dims = m.group(1) == "enabled" or re.search(r"\?\s*(0?\.\d+|1)\s*:\s*(0?\.\d+|1)\b", m.group(2))
                if dims and tied.search(m.group(2)):
                    with self.subTest(f"SettingsWindow.qml:{n}"):
                        self.fail(f"SettingsWindow.qml:{n}: grayed out by a setting without saying which: "
                                  f"give its row needsMet and needs instead ({line.strip()[:90]})")
        labels = set(re.findall(r'\b(?:label|text):\s*"([^"]+)"', src))
        pages = set(settings_pages())
        found = 0
        for n, line in enumerate(lines, 1):
            if not re.match(r"\s*needsMet\s*:", line):
                continue
            found += 1
            near = "\n".join(lines[max(0, n - 6):n + 6])
            with self.subTest(f"SettingsWindow.qml:{n}"):
                needs = re.search(r"\bneeds\s*:(.*)", near)
                self.assertTrue(needs and re.search(r'"[^"]+"', needs.group(1)), f"line {n}: needsMet without needs saying what")
                # What the system lacks (no systemd, no time service) has nowhere to go: the line
                # just says why. Only what another setting does leads to that setting
                if not tied.search(line):
                    # (a plain sentence of its own, in Slate's words, saying what's missing)
                    self.assertRegex(needs.group(1), r'"[^"]{12,}"', f"line {n}: a system-lacking row needs its own plain `needs` text")
                    continue
                page = re.search(r'\bneedsPage\s*:\s*"(\w+)"', near)
                self.assertTrue(page, f"line {n}: no needsPage to go to")
                self.assertIn(page.group(1), pages, f"line {n}: needsPage {page.group(1)!r} isn't a Settings page")
                to = re.search(r"\bneedsLabel\s*:([^;\n]*)", near)
                self.assertTrue(to, f"line {n}: no needsLabel to go to")
                for name in re.findall(r'(?<![=!]=)\s"([^"]+)"', " " + to.group(1)):
                    self.assertIn(name, labels, f"line {n}: needsLabel {name!r} isn't a setting's name")
        self.assertGreaterEqual(found, 6, "fewer dependent settings found than Settings has")

    def test_needs_lines_fit(self):
        """A grayed-out row's line saying what it needs is one short line, cut off with "…" past
        that: "Slate can't manage the power button here. It needs systemd or elogind, and
        neither is running" showed as "…It needs systemd or elogind,…". Kept to what fits."""
        import glob
        for path in sorted(glob.glob(os.path.join(slate.ROOT, "shell", "settings", "**", "*.qml"), recursive=True)):
            src = open(path, encoding="utf-8").read()
            for m in re.finditer(r'\bneeds:\s*"([^"]+)"', src):
                with self.subTest(f"{os.path.basename(path)}: {m.group(1)[:40]}"):
                    self.assertLessEqual(len(m.group(1)), 52, "too long for its line: it's cut off")

    def test_setting_names_unique(self):
        src = slate.read("shell", "SettingsData.qml")
        names = re.findall(r"^\s*property\s+[\w<>]+\s+(\w+)\s*:", src, re.M)
        dupes = sorted({n for n in names if names.count(n) > 1})
        self.assertFalse(dupes, f"settings defined twice: {dupes}")


class Lists(Case):
    def test_keep_lists_match(self):
        """install.sh and update.py keep the same files when replacing Slate."""
        sh = re.search(r"^KEEP=\(([^)]*)\)", slate.read("install.sh"), re.M)
        py = re.search(r"^KEEP\s*=\s*\(([^)]*)\)", slate.read("shell", "scripts", "update.py"), re.M)
        self.assertTrue(sh and py, "KEEP not found in install.sh or update.py")
        self.assertEqual(sorted(sh.group(1).split()), sorted(re.findall(r"\"([^\"]+)\"", py.group(1))))

    def test_package_lists(self):
        """packaging/*.txt: one package name per line, "?" for optional, # comments."""
        for f in slate.files("packaging", ".txt"):
            with self.subTest(f):
                seen = set()
                for n, line in enumerate(slate.read(f).splitlines(), 1):
                    line = re.sub(r"\s*#.*", "", line).strip()
                    if not line:
                        continue
                    self.assertRegex(line, r"^\??[A-Za-z0-9][A-Za-z0-9+._:@/-]*$", f"line {n}: {line!r}")
                    name = line.lstrip("?")
                    self.assertNotIn(name, seen, f"line {n}: {name} listed twice")
                    seen.add(name)

    def test_hyprlands_portal_is_in_every_list(self):
        """Screen sharing, Private Mode and the share picker's window rule need
        xdg-desktop-portal-hyprland: every distro's list has it (Debian's is optional, like
        its Hyprland, which the PPA brings with it) and so does the NixOS example."""
        for f in slate.files("packaging", ".txt"):
            with self.subTest(f):
                names = [re.sub(r"\s*#.*", "", l).strip().lstrip("?") for l in slate.read(f).splitlines()]
                self.assertIn(("gui-libs/" if "gentoo" in f else "") + "xdg-desktop-portal-hyprland", names)
        self.assertIn("pkgs.xdg-desktop-portal-hyprland", slate.read("packaging", "nixos.nix"))
        self.assertIn("`xdg-desktop-portal-hyprland`", slate.read("docs", "ARCHITECTURE.md"))

    def test_lists_stay_tidy(self):
        """Packages Slate never calls stay out of the lists, build tools stay optional (only
        Hyprbars uses them, and it says what's missing), and nothing sits under a heading
        it doesn't belong to."""
        unused = {"unzip", "app-arch/unzip", "bluez-utils", "qt6-shadertools", "dev-qt/qtshadertools:6"}
        build = {"git", "make", "gcc", "g++", "gcc-c++", "pkgconf", "pkg-config", "dev-vcs/git", "dev-util/pkgconf"}
        for f in slate.files("packaging", ".txt"):
            with self.subTest(f):
                heading = ""
                for line in slate.read(f).splitlines():
                    if line.startswith("#"):
                        heading = line
                    code = re.sub(r"\s*#.*", "", line).strip()
                    if not code:
                        continue
                    name = code.lstrip("?")
                    self.assertNotIn(name, unused, f"{name} isn't used by Slate")
                    if name in build:
                        self.assertTrue(code.startswith("?"), f"{name} is only for Hyprbars: optional")
                    if name in ("v4l-utils", "media-tv/v4l-utils"):
                        self.assertTrue(code.startswith("?"), "the Webcam page says what's missing: optional")
                    if name in build | {"qml6-module-qtquick-shapes"}:
                        self.assertNotIn("Emoji", heading, f"{name} is under the wrong heading")


class Links(html.parser.HTMLParser):
    """A page's anchors and links. A docs page's h2/h3 are anchors too: docs.js gives each an id
    from its text, as slug() does here."""
    def __init__(self, docs=False):
        super().__init__()
        self.ids, self.refs = set(), []
        self._head = None
        self.docs = docs

    def handle_endtag(self, tag):
        if tag in ("h2", "h3") and self._head is not None:
            self.ids.add(re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", "".join(self._head).lower())))
            self._head = None

    def handle_data(self, data):
        if self._head is not None:
            self._head.append(data)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("h2", "h3") and self.docs:
            self._head = []
        for k in ("id", "name"):
            if a.get(k):
                self.ids.add(a[k])
        for k in ("href", "src", "poster"):
            if a.get(k):
                self.refs.append((self.getpos()[0], a[k]))


class Site(Case):
    def test_links(self):
        """Every link and image on the site points at a file (and an anchor) that exists."""
        pages = {}
        for f in slate.files("site", ".html"):
            p = Links(docs=os.sep + "docs" + os.sep in f)
            p.feed(slate.read(f))
            pages[f] = p
        for f, p in pages.items():
            with self.subTest(f):
                broken = []
                for line, ref in p.refs:
                    if re.match(r"^(https?:|mailto:|data:|javascript:|//)", ref):
                        continue
                    target, _, anchor = ref.partition("#")
                    target = target.split("?")[0]
                    tf = os.path.normpath(os.path.join(os.path.dirname(f), target)) if target else f
                    if target and not os.path.exists(slate.path(tf)):
                        broken.append(f"line {line}: {ref}")
                    elif anchor and tf in pages and anchor not in pages[tf].ids:
                        broken.append(f"line {line}: #{anchor} isn't on {os.path.basename(tf)}")
                self.assertFalse(broken, "; ".join(broken[:4]) + (f" (+{len(broken) - 4} more)" if len(broken) > 4 else ""))


# Other desktop shells, which Slate doesn't name anywhere. Kept as hashes (sha256, first 16
# hex digits, of the lower-case word) so this file doesn't name them either.
OTHER_SHELLS = {"721ee3c57b31edac", "9dc59291377e30c7", "35d8035b3c7c3520", "e22f8d3377e9bf56", "eee78869879d21d7"}


class Names(Case):
    def test_no_other_shells_named(self):
        hits = []
        for f in tracked_files():
            if f.startswith("tests/out/"):
                continue
            try:
                text = slate.read(f).lower()
            except (UnicodeDecodeError, OSError):
                continue
            for n, line in enumerate(text.splitlines(), 1):
                for word in set(re.findall(r"[a-z0-9]+", line)):
                    if hashlib.sha256(word.encode()).hexdigest()[:16] in OTHER_SHELLS:
                        hits.append(f"{f}:{n}")
        self.assertFalse(hits, "another shell is named at " + ", ".join(hits[:5]))


class WorkspaceLabels(Case):
    """A workspace can have a name of its own, so nothing builds "Workspace 3" by hand: every
    place that shows one asks Config.workspaceLabel (or the name would be missing there)."""

    def test_none_built_by_hand(self):
        found = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).splitlines(), 1):
                if re.search(r'"Workspace "\s*\+', line.split("//")[0]) and "function workspaceNumber" not in line:
                    found.append(f"{f}:{n}")
        self.assertEqual(found, [])


class Wallpapers(Case):
    """Slate's own wallpapers (shell/wallpapers) are made by tools/make-wallpapers.py, never
    drawn by hand: two files per look in the tool (with Slate's mark, and plain), each a 4K PNG
    small enough to ship. PNG, not
    JPEG: JPEG rounds colour in blocks, which shows as bands across colour this smooth."""

    def test_made_by_the_tool(self):
        import re
        from PIL import Image
        looks = re.findall(r'^    "(\w+)":\s+\("#', slate.read("tools", "make-wallpapers.py"), re.M)
        self.assertGreaterEqual(len(looks), 4, "couldn't read the looks from the tool")
        folder = slate.path("shell", "wallpapers")
        files = [f"slate-{n}{plain}.png" for n in looks for plain in ("", "-plain")]
        self.assertEqual(sorted(os.listdir(folder)), sorted(files))
        for n in (f[len("slate-"):-len(".png")] for f in files):
            with self.subTest(n):
                p = os.path.join(folder, f"slate-{n}.png")
                with Image.open(p) as im:
                    self.assertEqual((im.format, im.size, im.mode), ("PNG", (3840, 2160), "RGB"))
                # The tool writes them itself (save_png, every row "Sub"-filtered); saved by
                # Pillow they come out around 2.5 MB each, so this catches that coming back
                self.assertLess(os.path.getsize(p), 2_000_000, "bigger than the tool makes it")


class Pointer(Case):
    """Where the pointer turns into a hand: over buttons, switches and links in panels and
    windows, not over the desktop, the dock or right-click menus (those keep the arrow)."""
    def test_desktop_keeps_the_arrow(self):
        src = slate.read("shell", "Wallpaper.qml")
        self.assertNotIn("ClickArea {", src, "the desktop's right-click area turns the pointer into a hand: a MouseArea")

    def test_menus_keep_the_arrow(self):
        for f in ("DesktopMenu.qml", "TrayMenu.qml"):
            with self.subTest(f):
                src = slate.read("shell", f)
                taps = len(re.findall(r"ClickTap \{", src))
                arrows = len(re.findall(r"ClickTap \{[^}]*?hand: false", src, re.S))
                self.assertEqual(taps, arrows, f"every ClickTap in {f} needs hand: false (menus keep the arrow)")

    def test_dock_keeps_the_arrow(self):
        src = slate.read("shell", "Dock.qml")
        m = re.search(r"ClickArea \{\s*id: mouse\b(.*?)\n    \}", src, re.S)
        self.assertTrue(m, "the dock's pointer area (ClickArea id: mouse) has moved")
        self.assertIn("cursorShape: Qt.ArrowCursor", m.group(1))
        previews = slate.read("shell", "DockPreviews.qml")
        for card in ("liveCard", "titleCard"):
            self.assertRegex(previews, r"ClickTap \{ hand: false; onTapped: \{ %s\." % card)

    def test_hand_is_the_default(self):
        self.assertRegex(slate.read("shell", "ClickTap.qml"), r"property bool hand: true")


class Hover(Case):
    """Under the pointer, a fill gives way to the muted hover. Animated from a solid fill to the
    see-through hover, a colour passes through a brighter, fuller accent and settles back: a flash
    on every hover (seen by Dayle on the notifications panel's cards, 2026-11-12). So a fill goes to
    Config.hoverOn(fill), solid for a solid fill, or cross-fades as layers (HoverFill)."""
    def test_solid_fills_hover_through_hover_on(self):
        bad = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).splitlines(), 1):
                m = re.search(r"\? Config\.hover : ([A-Za-z_][\w.]*)", line)
                # (from see-through to see-through doesn't flash: "transparent" and Qt.rgba fills)
                if m and m.group(1) not in ("transparent", "Qt.rgba"):
                    bad.append(f"{f}:{n}")
        self.assertFalse(bad, "a fill going straight to Config.hover (use Config.hoverOn(fill)): " + ", ".join(bad))

    def test_hover_on_a_solid_fill_is_solid(self):
        config = slate.read("shell", "Config.qml")
        m = re.search(r"function hoverOn\(base\) \{(.*?)\}\n", config)
        self.assertTrue(m, "Config.hoverOn has moved")
        self.assertIn("base.a", m.group(1), "hoverOn doesn't tell a solid fill from a see-through one")
        self.assertIn("Qt.tint(", m.group(1), "hoverOn doesn't give a solid fill a solid hover")


class WindowPreviews(Case):
    """Every live window preview (the overview, the window switcher, the dock's previews, New
    Space) is a WindowPreview. In Quickshell's live mode, a capture that failed as its window
    closed was asked for again from the window's closed handle, and Slate died ("The Wayland
    connection experienced a fatal error: Invalid argument"; closing several windows at once
    while New Space or the overview showed them, 2026-11-12). WindowPreview asks for frames
    itself and never uses live mode."""
    def test_only_window_preview_captures_windows(self):
        bad = [f for f in slate.files("shell", ".qml")
               if not f.endswith("WindowPreview.qml") and re.search(r"\bScreencopyView\s*\{", slate.read(f))]
        self.assertFalse(bad, "a ScreencopyView of its own (use WindowPreview): " + ", ".join(bad))

    def test_never_live(self):
        src = slate.read("shell", "WindowPreview.qml")
        self.assertRegex(src, r"\n    live: false\n")
        self.assertIn("captureFrame()", src)
        # (the first frame comes by itself: asked for again before it's here, it started over)
        self.assertRegex(src, r"running: .*wp\.hasContent")

    def test_blur_decoded_once(self):
        """The wallpaper behind see-through previews (WallBlur) is decoded at one size, so it's
        shared through the image cache, and the switcher has it ready before it opens (each
        preview decoding it again, the blur came in after the window)."""
        blur = slate.read("shell", "WallBlur.qml")
        m = re.search(r"decodeSize: Qt\.size\((\d+), (\d+)\)", blur)
        self.assertTrue(m, "WallBlur's decodeSize has moved")
        self.assertIn("sourceSize: wb.decodeSize", blur)
        self.assertIn(f"sourceSize: Qt.size({m.group(1)}, {m.group(2)})", slate.read("shell", "Switcher.qml"),
                      "the switcher's wallpaper, loaded ahead, isn't at WallBlur's decodeSize")


class Shadows(Case):
    """One shadow look everywhere (Settings → Appearance → Shadows)."""
    def test_no_shadow_sets_its_own_look(self):
        """A Shadow takes its softness and distance from Config, never a blur of its own."""
        bad = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).splitlines(), 1):
                if re.search(r"\bShadow \{[^}]*\bblur:", line):
                    bad.append(f"{f}:{n}")
        self.assertFalse(bad, "a Shadow with a look of its own: " + ", ".join(bad))

    def test_every_setting_reaches_the_look(self):
        """The five Shadows settings each reach Config's one look (and from there Shadow.qml,
        Qt's effects and Hyprland), and the spread reaches the shader."""
        config = slate.read("shell", "Config.qml")
        for key in ("shadowDarkness", "shadowSoftness", "shadowSpread", "shadowDistance", "shadowDirection"):
            with self.subTest(key):
                self.assertIn(f"s.{key}", config, f"{key} isn't read anywhere in Config.qml")
        shadow = slate.read("shell", "Shadow.qml")
        for prop in ("Config.shadowReach", "Config.shadowSpread", "Config.shadowDX", "Config.shadowDY"):
            self.assertIn(prop, shadow)
        self.assertIn("spread", slate.read("shell", "shaders", "shadow.frag"))
        self.assertRegex(config, r"shadow = \{ enabled = \$\{hyprShadow\.on", "Hyprland's shadows don't follow the switch")

    def test_distance_moves_never_spreads(self):
        """Every Shadow is moved by the distance the way the direction says, and grown by the
        spread alone: Shadow.qml's spread and drop are Config's and can't be set (a panel's and
        the bar's added the distance to the spread, so a distance straight down grew a panel's
        shadow at its sides too). A surface hanging off an edge says so (attachEdge) instead."""
        shadow = slate.read("shell", "Shadow.qml")
        for prop, value in (("spread", "Config.shadowSpread"), ("dropX", "Config.shadowDX"), ("dropY", "Config.shadowDY")):
            self.assertRegex(shadow, rf"readonly property real {prop}: {re.escape(value)}\b", f"Shadow's {prop} isn't fixed to {value}")
        for f in slate.files("shell", ".qml"):
            self.assertNotRegex(slate.read(f), r"shadowSpread \+ Config\.shadowDrop|shadowDrop \+ Config\.shadowSpread",
                                f"{f}: the distance added to the spread")
        self.assertIn('attachEdge: pop.sideways ? pop.side : pop.fromBottom ? "bottom" : "top"', slate.read("shell", "Popouts.qml"))
        frag = slate.read("shell", "shaders", "shadow.frag")
        self.assertIn("vec2 p = q - drop;", frag, "the shadow isn't the shape moved by the distance")
        self.assertIn("dot(q - drop, under.xy)", frag, "the bar's shadow under a panel's isn't moved as the bar's is")

    def test_hyprland_shadow_from_the_same_settings(self):
        """Hyprland's shadow under floating windows is worked out from the same values as
        Shadow.qml's (Config.hyprShadow), in Hyprland's pixels, and handed over whole: range,
        power, sharpness, offset and colour (the live test Shadows checks it looks the same)."""
        config = slate.read("shell", "Config.qml")
        m = re.search(r"readonly property var hyprShadow: \{(.*?)\n    \}\n", config, re.S)
        self.assertTrue(m, "Config.hyprShadow has moved")
        body = m.group(1)
        for value in ("shadowSpread", "shadowReach", "shadowStrength", "shadowDX", "shadowDY", "shadowHex", "shadowsOn", "uiScale"):
            self.assertRegex(body, rf"\b{value}\b", f"Hyprland's shadow doesn't follow {value}")
        line = next((l for l in config.splitlines() if "shadow = { enabled" in l), "")
        for part in ("range = ${hyprShadow.range}", "render_power = ${hyprShadow.power}", "sharp = ${hyprShadow.sharp",
                     "offset = { ${hyprShadow.offsetX}, ${hyprShadow.offsetY} }", 'color = "${hyprShadow.colour}"'):
            self.assertIn(part, line)
        self.assertNotRegex(config, r"shadow = \{ color = ", "a second shadow colour handed to Hyprland")

    def test_no_dark_line_under_a_see_through_edge(self):
        """In the pixel a surface's edge crosses, the shadow is what makes it the surface where it
        covers and the shadow where it doesn't, for how solid the surface is: at full strength
        under a solid edge it showed through a see-through one (glass) as a dark line round
        menus and panels (2026-11-15). Shadow.qml passes the surface's opacity."""
        frag = slate.read("shell", "shaders", "shadow.frag")
        self.assertIn("float surfaceAlpha;", frag)
        self.assertRegex(frag, r"\(1\.0 - c\) / max\(0\.001, 1\.0 - c \* surfaceAlpha\)")
        qml = slate.read("shell", "Shadow.qml")
        self.assertIn("readonly property real surfaceAlpha: root.surfaceAlpha", qml)

    def test_falloff_is_as_modelled(self):
        """The live test of Hyprland's shadow models Shadow.qml's falloff: these lines are it."""
        frag = slate.read("shell", "shaders", "shadow.frag")
        self.assertIn("float soft = max(blur, 0.5);", frag)
        self.assertIn("float t = clamp((shade + soft * 0.4) / (soft * 1.4), 0.0, 1.0);", frag)
        self.assertIn("float a = (1.0 - t) * (1.0 - t);", frag)

    def test_qt_shadows_follow_the_switch(self):
        """Qt's own shadows (MultiEffect, RectangularShadow) are off when Slate's are."""
        bad = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).splitlines(), 1):
                if re.search(r"shadowEnabled:\s*true\b", line):
                    bad.append(f"{f}:{n}")
        self.assertFalse(bad, "shadowEnabled: true (use Config.shadowsOn): " + ", ".join(bad))


def shader_is_stale(root, frag, qsb):
    """Whether `frag` changed after `qsb` was built from it, by where each one stands in git:
    committed (when it was committed), staged for the commit being made, or edited in the
    working tree (its file time). File times only count for files edited by hand: a commit
    being made (a cherry-pick, a checkout) writes the working files in whatever order it
    likes, so their times say nothing about which was built first, and comparing them used
    to refuse a commit now and then."""
    def where(rel):
        # (rank, time): 0 = committed, 1 = staged, 2 = edited since; the time orders within a rank
        try:
            st = subprocess.run(["git", "-C", root, "status", "--porcelain", "--", rel],
                                capture_output=True, text=True, check=True).stdout
            if st[1:2].strip() or st.startswith("?"):
                return 2, os.path.getmtime(os.path.join(root, rel))
            if st.strip():
                return 1, 0
            t = subprocess.run(["git", "-C", root, "log", "-1", "--format=%ct", "--", rel],
                               capture_output=True, text=True, check=True).stdout.strip()
            return 0, int(t) if t else os.path.getmtime(os.path.join(root, rel))
        except (OSError, subprocess.CalledProcessError):
            return 2, os.path.getmtime(os.path.join(root, rel))
    return where(frag) > where(qsb)


class Shaders(Case):
    def test_built_from_source(self):
        """Every shaders/*.frag has its .qsb, built after the source last changed."""
        for frag in slate.files("shell/shaders", ".frag", ".vert"):
            with self.subTest(frag):
                qsb = frag + ".qsb"
                self.assertTrue(os.path.exists(slate.path(qsb)), f"{qsb} is missing (build it with qsb)")
                self.assertFalse(shader_is_stale(slate.ROOT, frag, qsb), f"{frag} changed after {os.path.basename(qsb)} was built")

    def test_staleness_check_ignores_checkout_order(self):
        """A commit being made (a cherry-pick) writes the source after its built file now and
        then: that's no reason to refuse it; a source really edited after the build still is."""
        import tempfile
        from unittest import mock
        # (inside git's pre-commit hook GIT_INDEX_FILE names the real index: a scratch
        # repository must not see it)
        clean = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        with tempfile.TemporaryDirectory() as root, mock.patch.dict(os.environ, clean, clear=True):
            def git(*a):
                subprocess.run(["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t", *a],
                               check=True, capture_output=True)
            git("init", "-q")
            f, q = os.path.join(root, "a.frag"), os.path.join(root, "a.frag.qsb")
            for path, text in ((q, "built 1"), (f, "source 1")):      # the source written last
                open(path, "w").write(text)
            git("add", ".")
            self.assertFalse(shader_is_stale(root, "a.frag", "a.frag.qsb"), "both staged, the source written later")
            git("commit", "-q", "-m", "one")
            self.assertFalse(shader_is_stale(root, "a.frag", "a.frag.qsb"), "both committed together")
            for path, text in ((q, "built 2"), (f, "source 2")):
                open(path, "w").write(text)
            git("add", ".")
            os.utime(q, (1, 1))                                  # the built file looks older
            self.assertFalse(shader_is_stale(root, "a.frag", "a.frag.qsb"), "both staged for one commit")
            git("commit", "-q", "-m", "two")
            open(f, "w").write("source 3")
            self.assertTrue(shader_is_stale(root, "a.frag", "a.frag.qsb"), "the source edited, the built file not")
            open(q, "w").write("built 3")
            self.assertFalse(shader_is_stale(root, "a.frag", "a.frag.qsb"), "rebuilt after the edit")
            os.utime(q, (1, 1))
            self.assertTrue(shader_is_stale(root, "a.frag", "a.frag.qsb"), "edited after it was built")


class LuaText(Case):
    """Text that Slate writes into Lua for Hyprland (hyprctl eval / dispatch, displays.lua)
    goes through Config.luaString: a monitor's description, a folder or a command written
    between long brackets or quotes by hand could end the string and run as Lua."""
    def test_no_long_brackets_by_hand(self):
        shell = os.path.join(slate.ROOT, "shell")
        for name in sorted(os.listdir(shell)):
            if name.endswith(".qml"):
                for n, line in enumerate(slate.read("shell", name).splitlines(), 1):
                    with self.subTest(name, line=n):
                        self.assertNotRegex(line, r"\[=+\[|\]=+\]", "a Lua long string written by hand: use Config.luaString")

    def test_what_comes_from_outside_is_written_by_luastring(self):
        displays = slate.read("shell", "Displays.qml")
        self.assertEqual(len(re.findall(r"output = \$\{Config\.luaString\(out\)\}", displays)), 2)
        self.assertNotRegex(displays, r"output = [^$]")
        downloads = re.search(r"function openDownloads\(\) \{(.*?)\n    \}", slate.read("shell", "Dock.qml"), re.S).group(1)
        self.assertIn("FILE_MANAGER .. ${Config.luaString(", downloads)
        self.assertNotRegex(downloads, r"""\.replace\(/'/g, ""\)""", "the folder's quotes dropped rather than escaped")
        launcher = slate.read("shell", "Launcher.qml")
        self.assertIn("Config.luaString(q(inTerminal))", launcher)
        self.assertIn("Config.luaString(cmd)", launcher)
        mode = re.search(r"function setWorkspaceMode\(id, mode\) \{(.*?)\n    \}", slate.read("shell", "Config.qml"), re.S).group(1)
        self.assertIn("if (mode && !windowModes.some(x => x.value === mode)) return;", mode)
        self.assertIn("if (!Number.isInteger(id) || id <= 0) return;", mode)


class PrivateFiles(Case):
    """What Slate keeps that's private (the conversation with Nova, the notification history)
    is written from QML, where a file can't be made with a mode: so its folder is closed
    first, by a command run here as Slate runs it, and the file after."""
    FILES = {"Assistant.qml": "root.chatFile", "Notifications.qml": "notifs.stateFile"}

    def test_folder_is_closed_before_the_file_is_written(self):
        import stat
        import tempfile
        for name, prop in self.FILES.items():
            with self.subTest(name):
                src = slate.read("shell", name)
                m = re.search(r"""command: \["sh", "-c", '([^']+)', %s\]\s*onExited: \{(.*?)\n    \}""" % re.escape(prop), src, re.S)
                self.assertTrue(m, "no command closing the folder of " + prop)
                script, after = m.groups()
                # Every write is after that command has finished, and is followed by the file's chmod
                self.assertEqual(src.count(".setText("), 1, "a write that doesn't wait for the folder")
                self.assertRegex(after, r"""(?s)\.setText\(.*?\);\s*Quickshell\.execDetached\(\["chmod", "600", %s\]\)""" % re.escape(prop))
                # The command: the folder made, or one that was open to others closed
                old = os.umask(0o022)
                self.addCleanup(os.umask, old)
                with tempfile.TemporaryDirectory() as top:
                    for folder in ("new", "old"):
                        d = os.path.join(top, folder, "slate")
                        if folder == "old":
                            os.makedirs(d)
                            self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o755)
                        subprocess.run(["sh", "-c", script, os.path.join(d, "file.json")], check=True)
                        self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700, folder)


class NovaAnswers(Case):
    """Nova's answers never reach a text item that reads markup of its own accord
    (docs/ASSISTANT.md, "How answers look"): Qt's Markdown, styled and rich text all load the
    pictures they name, from the network or disk (checked on Qt 6.12), and an answer is
    written by a model that may have been misled. The runner reads the answer
    (scripts/safe_markdown.py); the window's one rich text item is given only what rich()
    writes, around words it has escaped."""
    def src(self):
        return slate.read("shell", "Assistant.qml")

    def test_no_markup_of_the_models(self):
        src = self.src()
        self.assertNotRegex(src, r"\b(Text|TextEdit)\.(MarkdownText|StyledText|AutoText)\b")
        self.assertNotRegex(src, r"\bText\.RichText\b", "a Text item with rich text (only AnswerWords may have it)")
        self.assertEqual(len(re.findall(r"textFormat:\s*TextEdit\.RichText", src)), 1, "rich text other than AnswerWords")
        words = re.search(r"component AnswerWords: TextEdit \{(.*?)\n    \}", src, re.S)
        self.assertTrue(words, "AnswerWords has moved")
        self.assertIn("text: root.rich(runs, heading)", words.group(1))
        self.assertIn("textFormat: TextEdit.RichText", words.group(1))

    def test_rich_escapes_the_words(self):
        src = self.src()
        esc = re.search(r"function esc\(s\) \{ return String\(s\)(.*?) \}\n", src)
        self.assertTrue(esc, "esc() has moved")
        # (& first, or the others' & would be escaped again)
        self.assertEqual(esc.group(1), '.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");')
        rich = re.search(r"function rich\(runs, strong\) \{(.*?)\n    \}", src, re.S)
        self.assertTrue(rich, "rich() has moved")
        self.assertIn("let t = esc(r.text);", rich.group(1))
        # Nothing but Slate's own tags, and no address of any kind
        self.assertEqual(set(re.findall(r"<(/?\w+)", rich.group(1))), {"b", "/b", "i", "/i", "span", "/span"})
        self.assertNotRegex(rich.group(1), r"url\(|src=|href=")

    def test_nothing_loads_or_opens(self):
        src = self.src()
        self.assertNotRegex(src, r"\b(Image|AnimatedImage|BorderImage|AnimatedSprite)\s*\{", "a picture in Nova's window")
        for opens in ("openUrlExternally", "linkActivated"):
            self.assertNotIn(opens, src)


class CopiedTextIsNeverAnOption(Case):
    """Text handed to wl-copy as an argument comes after "--", so words that start with a dash
    are still the words: the launcher's answer to 2-7 is "-5", which wl-copy took for an option
    and copied nothing (2026-11-14). Options written out ("--type", "text/plain") are fine,
    and text piped in needs nothing."""
    def test_wl_copy_text_follows_a_double_dash(self):
        bad = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).split("\n"), 1):
                for argv in re.findall(r'\[\s*"wl-copy"([^\]]*(?:\[[^\]]*\][^\]]*)*)\]', line):
                    # What follows "wl-copy": words written out in quotes are Slate's own (its
                    # options and their values); anything else is text Slate worked out, and
                    # needs the "--" before it
                    words = [w.strip() for w in re.split(r',(?![^\[(]*[\])])', argv) if w.strip()]
                    for word in words:
                        if word == '"--"':
                            break
                        if not re.fullmatch(r'"[^"]*"', word):
                            bad.append("%s:%d" % (os.path.basename(f), n))
                            break
        self.assertFalse(bad, 'wl-copy is given text without "--" before it: ' + ", ".join(bad))

    def test_it_is_looked_for(self):
        """(the check above finds the copies it's meant to, so it can't pass by finding none)"""
        found = [f for f in slate.files("shell", ".qml") if re.search(r'\[\s*"wl-copy",\s*"--",', slate.read(f))]
        self.assertGreaterEqual(len(found), 5, found)


class DefaultWindowModeGoesThroughOneDoor(Case):
    """The default window mode is changed only by Config.setDefaultMode, which also settles the
    workspaces given a mode of their own. Welcome's cards once set `s.windowMode` directly, so a
    workspace already set to the new default kept a stale override of it."""
    def test_only_config_sets_it(self):
        bad = []
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).split("\n"), 1):
                if re.search(r"\bs\.windowMode\s*=[^=]", line) and not (f.endswith("/Config.qml") and "s.windowMode = v;" in line):
                    bad.append("%s:%d" % (os.path.basename(f), n))
        self.assertFalse(bad, "set the default window mode with Config.setDefaultMode: " + ", ".join(bad))


class NoSelfBindings(Case):
    """`popouts: popouts` inside `Dock { }` reads the Dock's own `popouts` property, not the
    outer object with that id (an object's own properties come before the document's ids), so it
    hands over null. That froze the dock with auto-hide on (2026-11-15), and left the launcher
    without notifications. Pass such things through a property of another name."""
    def test_no_name_bound_to_itself(self):
        bad = []
        pat = re.compile(r"^\s+([A-Za-z_]\w*):\s*\1\s*(//.*)?$")
        for f in slate.files("shell", ".qml"):
            for n, line in enumerate(slate.read(f).split("\n"), 1):
                if pat.match(line):
                    bad.append("%s:%d: %s" % (os.path.relpath(f, slate.path("shell")), n, line.strip()))
        self.assertFalse(bad, "a property bound to itself (it reads its own value, not the outer id): " + "; ".join(bad))


class OutsideTextIsPlain(Case):
    """Words another program chose (a window's title, a notification, a Wi-Fi network's or a
    Bluetooth device's name, a track, a tray menu, a file's name, what you copied) are shown as
    plain text. A Text item left to itself reads anything that looks like markup as markup
    (Text.AutoText), so a web page's title could resize or recolour Slate's own words, place a
    link in them, or have Slate fetch a picture from an address of its choosing. Each such Text
    says `textFormat: Text.PlainText`, as Nova's window always has. The one exception is a
    notification's message, which the spec lets use a little markup: it goes through
    NotificationText.js first (tests/unit/test_notification_text.py)."""

    # A text binding with any of these in it shows something Slate didn't write
    OUTSIDE = re.compile(r"\.title\b|\btitle \|\||appName|\.summary\b|\.body\b|trackTitle|trackArtist|trackAlbum|tooltipTitle"
                         r"|\.identity\b|[fF]ileName|deviceName|\.ssid\b|\.description\b|\.nickname\b|\.comment\b|genericName"
                         r"|entry\??\.name|modelData\.name|\.n\.name|printer\.(info|name)|fullName|locationName|workspaceLabel\("
                         r"|\bws\.name|nameOf\(|nicePath\(|browseDir|idName\(|clipDetail\(|\.preview\(")
    # …and these do too, though nothing in their wording says so: (file, the binding)
    ALSO = [
        ("Bar.qml", "text: wsName.says"),                    # a workspace's name
        ("Bar.qml", "text: seg.drawnLabel"),                 # a Wi-Fi network's name, a keyboard layout's
        ("Tooltip.qml", "text: tip.text"),                   # every tooltip: an app's name, a tray icon's, a Bluetooth device's
        ("DesktopMenu.qml", "text: row.modelData.label"),    # "Show <player>", a window's title, an app's name
        ("TrayMenu.qml", "text: entryRow.e && !entryRow.sep ? String(entryRow.e.text)"),   # apps' own menus
        ("NotificationCard.qml", "text: modelData.text"),    # an app's word for its button
        ("PolkitAgent.qml", "text: root.message"),           # the program asking for a password wrote these
        ("PolkitAgent.qml", "text: root.busy ? \"Checking…\" : root.prompt"),
        ("PolkitAgent.qml", "text: root.error !== \"\" ? root.error : root.supplementary"),
        ("OSD.qml", "text: osd.label"),
        ("LoginScreen.qml", "text: ls.message !== \"\" ? ls.message"),   # what the login said (PAM)
        ("LoginScreen.qml", "text: pill.label"),                        # a session's name
        ("LoginScreen.qml", "text: parent.parent.modelData.label"),     # …and its menu row
        ("Dock.qml", "text: dl.modelData.name"),            # a download's name
        ("Launcher.qml", "text: row.calc ? row.detail"),     # an app's own description, a file's folder
        ("BarEditor.qml", "text: barChip.label"),            # a tray icon's name
        ("SettingsWindow.qml", "text: label; color: win.text"),      # SettingRow: rows named after apps, devices, downloads
        ("SettingsWindow.qml", "text: detail; color: win.dim"),
        ("SettingsWindow.qml", "text: dropdown.current ? dropdown.current.label"),   # devices, apps, files as options
        ("SettingsWindow.qml", "text: parent.parent.modelData.label; color: win.text"),
        ("SettingsWindow.qml", "text: (wifiPane.facts.find(f => f.k === factRow.modelData) ?? { v: \"\" }).v"),         # a network's own details
        ("SettingsWindow.qml", "text: printersPane.note"),           # what the printing service said
    ]
    # Text you type into has no markup to read
    TYPED = {"TextInput", "TextEdit", "TextField"}
    # Slate's own components whose words are plain inside them (Tooltip.qml: named in ALSO, so checked)
    PLAIN = {"Tooltip"}
    # The login screen's files that draw nothing from outside (LoginScreen.qml, which shows the
    # login's message and this computer's account names, is checked like the rest)
    LOGIN_SCREEN = {"Config.qml", "SettingsData.qml", "RoundImage.qml", "WallBlur.qml", "Gloss.qml", "GlassFill.qml"}
    # Every word in these is Slate's own (their cards' titles, the corners' names)
    SLATES_OWN = {"Welcome.qml", "HotCornerPicker.qml"}

    @staticmethod
    def item_at(src, at):
        """The item a binding at `at` belongs to: (its type, its text), matched by brackets."""
        depth, start = 0, None
        for i in range(at - 1, -1, -1):
            if src[i] == "}":
                depth += 1
            elif src[i] == "{":
                if depth == 0:
                    start = i
                    break
                depth -= 1
        if start is None:
            return "", ""
        depth = 0
        for j in range(start, len(src)):
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    break
        kind = re.search(r"([A-Za-z_][\w.]*)\s*$", src[:start])
        return (kind.group(1) if kind else ""), src[start:j + 1]

    @staticmethod
    def plain_kinds(src):
        """The file's own text components that are plain already (the panels' Label, and what's built on it)."""
        plain = set()
        # The panels' shared pieces live in shell/panels/, one per file: a file is its root's kind
        # (Label is a Text with its own PlainText, Heading is built on Label…)
        panel_files = {}
        for f in sorted(os.listdir(os.path.join(slate.SHELL, "panels"))):
            m = re.search(r"^(\w+) \{([^\n]*\n[^\n]*\n[^\n]*\n)", slate.read("shell", "panels", f), re.M)
            if f.endswith(".qml") and m:
                panel_files[f[:-4]] = (m.group(1), m.group(2))
        for _ in range(3):
            for name, (base, body) in panel_files.items():
                if base in plain or (base == "Text" and re.search(r"^\s*textFormat: Text\.PlainText\b", body, re.M)):
                    plain.add(name)
                elif re.search(r"property alias text: (\w+)\.text\b", body + slate.read("shell", "panels", name + ".qml")):
                    inner = re.search(r"property alias text: (\w+)\.text\b", slate.read("shell", "panels", name + ".qml")).group(1)
                    holder = re.search(r"(\w+) \{\s*id: %s\b" % inner, slate.read("shell", "panels", name + ".qml"))
                    if holder and holder.group(1) in plain:
                        plain.add(name)
        for _ in range(3):
            for name, base, body in re.findall(r"^\s*component (\w+): (\w+) \{([^\n]*\n[^\n]*)", src, re.M):
                if base in plain or (base == "Text" and re.match(r"\s*textFormat: Text\.PlainText\b", body)):
                    plain.add(name)
            # (and one whose text is handed straight to a plain one inside it: PanelTitle's Label)
            for name, inner in re.findall(r"^\s*component (\w+): \w+ \{\s*property alias text: (\w+)\.text\b", src, re.M):
                holder = re.search(r"(\w+) \{\s*id: %s\b" % inner, src)
                if holder and holder.group(1) in plain:
                    plain.add(name)
        return plain

    def check(self, name, src, at, why):
        kind, item = self.item_at(src, at)
        line = src[src.rfind("\n", 0, at) + 1:src.find("\n", at)].strip()[:120]
        where = f"{name}:{src.count(chr(10), 0, at) + 1}"
        if kind in self.TYPED or kind in self.PLAIN or kind in self.plain_kinds(src):
            return
        if "NotificationText.safeBody(" in line:
            self.assertIn("textFormat: Text.StyledText", item, where)
            return
        self.assertRegex(item, r"textFormat:\s*(root\.info\.long \? Text\.StyledText : )?Text\.PlainText\b",
                         f"{where} shows {why} without `textFormat: Text.PlainText`, so anything in it that looks "
                         f"like markup would be read as markup: {line}")

    def test_text_from_outside_is_plain(self):
        seen = 0
        names = sorted(os.listdir(slate.SHELL)) + ["panels/" + n for n in sorted(os.listdir(os.path.join(slate.SHELL, "panels")))]
        for name in names:
            if not name.endswith(".qml") or name in self.LOGIN_SCREEN or name in self.SLATES_OWN:
                continue
            src = slate.read("shell", name)
            for m in re.finditer(r"(?<![\w.])text:[ \t]*([^\n]+)", src):
                # (the binding alone: not what follows it on a one-line item, nor a comment)
                words = re.split(r";\s+\w[\w.]*:|\s//", m.group(1))[0]
                if self.OUTSIDE.search(words):
                    with self.subTest(file=name, line=src.count("\n", 0, m.start()) + 1):
                        self.check(name, src, m.start(), "something another program chose")
                    seen += 1
        self.assertGreater(seen, 40, "the check has stopped finding the labels it's for")

    def test_the_named_ones_are_plain(self):
        for name, binding in self.ALSO:
            src = slate.read("shell", name)
            self.assertIn(binding, src, f"{name}: `{binding}` has moved; find where it went and name it here")
            at = -1
            while (at := src.find(binding, at + 1)) >= 0:
                with self.subTest(file=name, binding=binding):
                    self.check(name, src, at, "a name something else chose")

    def test_the_panels_label_is_plain(self):
        """panels/Label.qml (every panel's words) is plain, and the one use that wants markup
        (the forecast's low, in a fainter colour) builds it from numbers alone."""
        src = slate.read("shell", "Popouts.qml")
        self.assertIn("Label", self.plain_kinds(src))
        styled = []
        for f in ["Popouts.qml"] + ["panels/" + n for n in sorted(os.listdir(os.path.join(slate.SHELL, "panels")))]:
            styled += re.findall(r"[^\n]*\n[^\n]*\n[^\n]*textFormat: Text\.(?:StyledText|RichText|AutoText|MarkdownText)", slate.read("shell", f))
        self.assertEqual(len(styled), 1, "markup in a panel other than the forecast's temperatures")
        self.assertIn("Math.round(pop.forecast.temperature_2m_min[forecastDay.day])", styled[0])

    def test_a_notifications_message_is_made_safe(self):
        card = slate.read("shell", "NotificationCard.qml")
        self.assertEqual(len(re.findall(r"textFormat: Text\.(?:StyledText|RichText|AutoText|MarkdownText)", card)), 1)
        self.assertIn("text: card.entry ? NotificationText.safeBody(card.entry.body) : \"\"", card)
        self.assertNotRegex(card, r"onLinkActivated: link => Qt\.openUrlExternally", "a link opened without asking what kind it is")
        self.assertIn("if (NotificationText.openable(link)) Qt.openUrlExternally(link)", card)
        # Its picture: a file or one Quickshell holds, never an address to fetch
        self.assertIn("entry.image && /^(file:|image:|\\/)/.test(entry.image) ? entry.image : \"\"", card)

    def test_release_notes_are_made_safe(self):
        """Settings → Updates shows release notes from the network as Markdown: they go
        through NotificationText.safeMarkdown (no pictures, web links only), and a link only
        opens when it's a web one (tests/unit/test_notification_text.py)."""
        src = slate.read("shell", "SettingsWindow.qml")
        self.assertIn("text: NotificationText.safeMarkdown(Updates.notes)", src)
        self.assertNotRegex(src, r"onLinkActivated: link => Qt\.openUrlExternally", "a link opened without asking what kind it is")
        self.assertIn("if (NotificationText.openable(link)) Qt.openUrlExternally(link)", src)

    def test_novas_notification_is_escaped(self):
        """Nova's answer, sent as a notification when its window is away: the agent's words
        escaped, and after "--" so a line starting with a dash isn't read as an option."""
        src = slate.read("shell", "Assistant.qml")
        sent = re.search(r"doneNote\.command = \[(.*?)\];", src, re.S)
        self.assertTrue(sent, "the notification has moved")
        self.assertRegex(sent.group(1), r'"--", "Nova", esc\(line\)$')


class NothingOfYoursRunsAsRoot(Case):
    """No pkexec or sudo in Slate names a script in your home folder (or in the Slate folder,
    wherever that is), in what it runs or in what it tells you to run, except the one
    installer of the root helpers."""
    YOURS = r"""(?:pkexec|sudo)["',\s]+(?:\$\{?(?:SRC|DEST|HOME|SELF|ROOT|SLATE|SLATE_DIR|XDG_CONFIG_HOME)\b|~/|<Slate folder>|Quickshell\.shellPath)"""

    def files(self):
        found = ["install.sh"]
        for top, dirs, names in os.walk(slate.path("shell")):
            dirs[:] = [d for d in dirs if d != "__pycache__"]
            found += [os.path.relpath(os.path.join(top, n), slate.ROOT) for n in names]
        return sorted(found)

    def test_no_script_of_yours_is_run_as_root(self):
        found = []
        files = self.files()
        self.assertIn("shell/bin/slate-system", files)
        for rel in files:
            try:
                text = slate.read(*rel.split("/"))
            except (UnicodeDecodeError, OSError):        # (pictures, fonts, sounds)
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if re.search(self.YOURS, line) and "slate-helpers-install" not in line:
                    found.append(f"{rel}:{n}: {line.strip()}")
        self.assertEqual(found, [], "run as root from your folder:\n" + "\n".join(found))

    def test_the_callers(self):
        self.assertIn('sudo "$ROOT/shell/bin/slate-helpers-install" "$ROOT/shell" slate-session-install "$DEST"',
                      slate.read("install.sh"))
        self.assertIn('"$SRC/bin/slate-system" --root slate-greeter-install --code-only',
                      slate.read("shell", "bin", "slate-greeter-sync"))
        self.assertIn('[Quickshell.shellPath("bin/slate-system"), "--root", "slate-private-camera", "install"]',
                      slate.read("shell", "PrivateMode.qml"))
        self.assertIn('[Quickshell.shellPath("bin/slate-system"), "--root", "slate-greeter-install"]',
                      slate.read("shell", "SettingsWindow.qml"))
        # Private Mode switches the camera with the root-owned copy, and only once that's allowed
        private = slate.read("shell", "PrivateMode.qml")
        self.assertIn('readonly property string helper: "/usr/local/libexec/slate/slate-private-camera"', private)
        self.assertIn('readonly property string allowed: "/usr/local/libexec/slate/camera-allowed"', private)

    def test_uninstall_takes_them_away(self):
        """./install.sh --uninstall removes the folder, the old single helper and the camera's
        rule, and asks first."""
        block = slate.read("install.sh").split('if [ "$UNINSTALL" -eq 1 ]; then', 1)[1].split("\nfi\n", 1)[0]
        ask = block.index('if ask "Remove Slate\'s root helpers')
        rm = block.index('sudo rm -rf "$HELPERS" "$HELPERS-private-camera" /etc/polkit-1/rules.d/49-slate-private-camera.rules')
        self.assertLess(ask, rm)
        self.assertIn("HELPERS=/usr/local/libexec/slate ", slate.read("install.sh"))
