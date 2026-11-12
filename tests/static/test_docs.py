"""The site's docs (site/docs/): every page in docs.js's list has its file and every file is in
the list; every Settings page is documented somewhere (a page's `covers`); every page follows
the docs' skeleton; links between docs pages, and to their headings, lead somewhere; and the
words stay Slate's (no old names, never "premium" on its own)."""
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
        self.heads, self.links, self.ids, self.text = [], [], set(), []
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

    def test_words(self):
        for i, _ in nav():
            with self.subTest(i):
                body = parse(i + ".html").body
                self.assertNotRegex(body, r"\bChalk\b", "the assistant is called Nova now")
                self.assertNotRegex(body, r"(?i)\bpremium\b(?!\s*(feel|-feeling))", "Slate has a premium feel; it isn't \"premium\" (that sounds like it costs money)")
                self.assertNotIn("!", re.sub(r"<!--.*?-->|<!doctype[^>]*>", "", body), "Slate is calm: no exclamation marks")
