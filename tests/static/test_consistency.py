"""Things that must agree across files: settings keys, Settings pages, lists kept in two
places, the site's links, shaders built from their sources."""
import hashlib
import html.parser
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
        for layer in ("dock-menu", "dock-previews", "picker", "switcher",
                      "tray-menu", "desktop-menu", "confirm", "polkit", "osd"):
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
        for n, line in enumerate(launcher.splitlines(), 1):
            if re.search(r"setsid qs\b.*-p ", line):
                with self.subTest(f"bin/slate:{n}"):
                    self.assertIn("QT_SCALE_FACTOR", line, "a Slate window is started without the Interface size")

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
                self.assertLess(os.path.getsize(p), 4_000_000, "too big to ship")


class Shaders(Case):
    def test_built_from_source(self):
        """Every shaders/*.frag has its .qsb, built after the source last changed."""
        def changed(rel):
            # A file edited but not committed counts as changed now
            try:
                st = subprocess.run(["git", "-C", slate.ROOT, "status", "--porcelain", "--", rel],
                                    capture_output=True, text=True, check=True).stdout
                if st.strip():
                    return os.path.getmtime(slate.path(rel))
                t = subprocess.run(["git", "-C", slate.ROOT, "log", "-1", "--format=%ct", "--", rel],
                                   capture_output=True, text=True, check=True).stdout.strip()
                return int(t) if t else os.path.getmtime(slate.path(rel))
            except (OSError, subprocess.CalledProcessError):
                return os.path.getmtime(slate.path(rel))

        for frag in slate.files("shell/shaders", ".frag", ".vert"):
            with self.subTest(frag):
                qsb = frag + ".qsb"
                self.assertTrue(os.path.exists(slate.path(qsb)), f"{qsb} is missing (build it with qsb)")
                self.assertGreaterEqual(changed(qsb), changed(frag), f"{frag} changed after {os.path.basename(qsb)} was built")
