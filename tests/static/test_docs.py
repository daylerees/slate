"""The site's docs (site/docs/): every page in docs.js's list has its file and every file is in
the list; every Settings page is documented somewhere (a page's `covers`); every page follows
the docs' skeleton; links between docs pages, and to their headings, lead somewhere; every
picture is there, described and sized (and every file in site/docs/img is used); and the words stay Slate's (no old names, never "premium" on its own).
And docs/ARCHITECTURE.md: its list names every QML file, helper and script Slate ships, and none
that has gone."""
import html.parser
import os
import re

import slate
from slate import Case

DOCS = slate.path("site", "docs")


def nav():
    """docs.js's pages: [(id, covers)]"""
    src = slate.read("site", "docs", "docs.js")
    block = src.split("const SECTIONS = [")[1].split("\n];")[0]
    out = []
    for line in block.splitlines():
        m = re.search(r'\{\s*id:\s*"([\w-]+)"', line)
        if m:
            cov = re.search(r"covers:\s*\[([^\]]*)\]", line)
            out.append((m.group(1), re.findall(r'"(\w+)"', cov.group(1)) if cov else []))
    return out


def settings_pages():
    src = slate.read("shell", "SettingsIndex.qml")
    block = src.split("readonly property var pages:")[1].split("\n    ]")[0]
    return re.findall(r'\{\s*id:\s*"(\w+)"', block)


def slug(text):
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", text.lower()))


class Page(html.parser.HTMLParser):
    """A docs page's headings (as docs.js names them), links, ids and body text."""
    def __init__(self):
        super().__init__()
        self.heads, self.links, self.ids, self.text, self.imgs = [], [], set(), [], []
        self._head = None
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a:
            self.ids.add(a["id"])
        if tag in ("h2", "h3"):
            self._head = []
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        if tag == "img":
            self.imgs.append(a)
        if tag in ("script", "style"):
            self._skip += 1

    def handle_endtag(self, tag):
        if tag in ("h2", "h3") and self._head is not None:
            self.heads.append(slug("".join(self._head)))
            self._head = None
        if tag in ("script", "style"):
            self._skip -= 1

    def handle_data(self, data):
        if self._head is not None:
            self._head.append(data)
        if not self._skip:
            self.text.append(data)


def parse(name):
    p = Page()
    with open(os.path.join(DOCS, name), encoding="utf-8") as f:
        p.raw = f.read()
    p.feed(p.raw)
    p.body = " ".join(p.text)
    return p


class Docs(Case):
    def test_every_page_has_its_file(self):
        ids = [i for i, _ in nav()]
        self.assertEqual(len(ids), len(set(ids)), "a page is in docs.js twice")
        for i in ids:
            with self.subTest(i):
                self.assertTrue(os.path.isfile(os.path.join(DOCS, i + ".html")), f"docs.js lists {i}, but site/docs/{i}.html isn't there")
        files = {f[:-5] for f in os.listdir(DOCS) if f.endswith(".html")} - {"index"}
        self.assertEqual(files - set(ids), set(), "pages in site/docs/ that aren't in docs.js's list (so not in the sidebar)")

    def test_every_settings_page_is_documented(self):
        covered = {c for _, cs in nav() for c in cs}
        for p in settings_pages():
            with self.subTest(p):
                self.assertIn(p, covered, f"Settings' {p} page isn't documented: add it to a docs page's covers in docs.js (and write about it there)")

    def test_pages_follow_the_skeleton(self):
        for i, _ in nav():
            with self.subTest(i):
                p = parse(i + ".html")
                self.assertIn(f'data-page="{i}"', p.raw)
                for part in ('id="docs-nav"', 'id="docs-pager"', 'id="docs-toc"', 'class="doc"', 'src="docs.js', 'href="docs.css', "<h1>", 'class="lead"'):
                    self.assertIn(part, p.raw, f"{i}.html is missing {part}")
                self.assertRegex(p.raw, r"<title>[^<]+ · Slate docs</title>")

    def test_links_lead_somewhere(self):
        pages = {i: parse(i + ".html") for i, _ in nav()}
        pages["index"] = parse("index.html")
        for name, p in pages.items():
            for href in p.links:
                if re.match(r"^(https?:|mailto:|#$)", href) or href.startswith("../"):
                    continue
                with self.subTest(f"{name}: {href}"):
                    target, _, anchor = href.partition("#")
                    page = target[:-5] if target.endswith(".html") else (name if target == "" else None)
                    self.assertIn(page, pages, f"{name}.html links to {href}, which isn't a docs page")
                    if anchor:
                        t = pages[page]
                        self.assertIn(anchor, set(t.heads) | t.ids, f"{name}.html links to {href}: {page}.html has no heading for #{anchor}")

    def test_pictures(self):
        """Every picture on a docs page (site/docs/img, taken by tools/docs-shots) is there, has
        alt text, a width and height (half its pixels: the files are twice the size, for sharp
        screens) and loads lazily; and nothing in site/docs/img is left unused."""
        try:
            from PIL import Image
        except ImportError:
            Image = None
        used = set()
        pages = [i + ".html" for i, _ in nav()] + ["index.html"]
        for name in pages:
            for img in parse(name).imgs:
                src = img.get("src", "")
                if src.startswith("../"):          # the site's own (the logo in the header)
                    continue
                with self.subTest(f"{name}: {src}"):
                    path = os.path.join(DOCS, src.split("?")[0])
                    self.assertTrue(src.startswith("img/") and os.path.isfile(path),
                                    f"{name} shows {src}, which isn't in site/docs/img")
                    used.add(os.path.basename(path))
                    self.assertTrue((img.get("alt") or "").strip(), f"{name}: {src} has no alt text (say what it shows)")
                    self.assertEqual(img.get("loading"), "lazy", f"{name}: {src} should have loading=\"lazy\"")
                    w, h = img.get("width", ""), img.get("height", "")
                    self.assertTrue(w.isdigit() and h.isdigit(), f"{name}: {src} needs a width and height (its size on the page)")
                    if Image is not None:
                        with Image.open(path) as im:
                            self.assertEqual((int(w) * 2, int(h) * 2), im.size,
                                             f"{name}: {src} is {im.size[0]}×{im.size[1]}; its width and height should be half that")
        folder = os.path.join(DOCS, "img")
        files = set(os.listdir(folder)) if os.path.isdir(folder) else set()
        self.assertEqual(files - used, set(), "pictures in site/docs/img that no docs page shows")

    def test_words(self):
        for i, _ in nav():
            with self.subTest(i):
                body = parse(i + ".html").body
                self.assertNotRegex(body, r"\bChalk\b", "the assistant is called Nova now")
                self.assertNotRegex(body, r"(?i)\bpremium\b(?!\s*(feel|-feeling))", "Slate has a premium feel; it isn't \"premium\" (that sounds like it costs money)")
                self.assertNotIn("!", re.sub(r"<!--.*?-->|<!doctype[^>]*>", "", body), "Slate is calm: no exclamation marks")


def shipped_files():
    """What docs/ARCHITECTURE.md's list has to name: [(the name to look for, the file)]. Slate's
    own QML (and the script beside it) by file name, helpers as bin/<name> and scripts as
    scripts/<name>, the way the list writes them."""
    out = []
    for f in sorted(os.listdir(slate.SHELL)):
        if f.endswith((".qml", ".js")):
            out.append((f, "shell/" + f))
    for folder in ("bin", "scripts"):
        for f in sorted(os.listdir(os.path.join(slate.SHELL, folder))):
            if os.path.isfile(os.path.join(slate.SHELL, folder, f)):
                out.append((folder + "/" + f, f"shell/{folder}/{f}"))
    return out


class Architecture(Case):
    """docs/ARCHITECTURE.md's list of what Slate is made of keeps up with the files: it once
    left out a third of them (the menus, the Welcome window, most helpers), since nothing said
    a new file needed a line there."""

    def test_every_shipped_file_is_named(self):
        doc = slate.read("docs", "ARCHITECTURE.md")
        for name, where in shipped_files():
            with self.subTest(where):
                # The whole name: "Gloss.qml" isn't named by "IconGloss.qml", nor bin/slate by bin/slate-init
                self.assertRegex(doc, r"(?<![\w-])" + re.escape(name) + r"(?![\w-])",
                                 f"{where} isn't in docs/ARCHITECTURE.md: give it a line there (as {name}) saying what it's for")

    def test_named_files_exist(self):
        """And the other way: nothing the list names as a QML file, helper or script has gone."""
        doc = slate.read("docs", "ARCHITECTURE.md")
        have = {name for name, _ in shipped_files()}
        named = set(re.findall(r"(?<![\w/.-])((?:bin|scripts)/[\w.-]*\w)", doc))
        named |= set(re.findall(r"(?<![\w/.-])([A-Z]\w+\.qml)\b", doc))
        for name in sorted(named - have - {"LoginWindow.qml"}):      # greeter/LoginWindow.qml: the login screen's own
            with self.subTest(name):
                self.fail(f"docs/ARCHITECTURE.md names {name}, which isn't in shell/ any more")
