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
    def __init__(self):
        super().__init__()
        self.ids, self.refs = set(), []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
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
            p = Links()
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
