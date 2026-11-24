"""Slate uses American spelling in everything people read (CLAUDE.md, Voice): color, center,
favorite, gray, canceled, organize, behavior, license, program, traveling, catalog, analyze,
airplane. This looks for British spellings in the words people see: QML strings, strings in
the Python and shell helpers, the site, README, docs/ and the assistant's prompt.

Identifiers and keys keep their spelling so saved settings keep working (`pageColour`,
`Config.colourful`, the `"colourful"` setting value, `folder-colour.py`): only whole words are
looked at, and a lower-case run with no spaces in a string is a key, not a word. Comments aren't
read by people, so they may stay as they are."""
import os
import re

import slate
from slate import Case

import spelling

# Words people read that are British on purpose, by file: names of places.
ALLOWED = {
    "shell/scripts/screensaver-videos.py": {"Harbour"},        # Gold Harbour, South Georgia
    "shell/scripts/folder-colour.py": {"colour"},              # its messages start with its own name
}

# Files that aren't Slate's words: licences and third-party text, and the tests and tools.
SKIP = ("shell/cursors/", "shell/fonts/", "site/docs/img/", "tests/", "tools/")


# A run of lower-case words with nothing else is a list of search words (Settings' search and
# the launcher's), which keep the British spelling next to the American one on purpose.
SEARCH_WORDS = re.compile(r"^[a-z0-9 \-]+$")


def left_in(spans, search_words_ok=False):
    """The British words in the string literals and text spans that people read."""
    found = []
    for s, e, body in spans:
        if search_words_ok and SEARCH_WORDS.match(body):
            continue
        if spelling.literal_ok(body):
            found += spelling.british_words(body)
    return found


def text_spans(src, spans):
    return [(s, e, src[s:e]) for s, e in spans]


class Spelling(Case):
    def check(self, files, spans_of, search_words_ok=False):
        bad = {}
        for f in files:
            if f.startswith(SKIP) or os.path.basename(f) in ("LICENSE", "LICENSE.md"):
                continue
            src = slate.read(f)
            words = [w for w in left_in(spans_of(src), search_words_ok) if w not in ALLOWED.get(f, ())]
            if words:
                bad[f] = sorted(set(words))
        self.assertEqual(bad, {}, "British spellings in what people read: use the American one")

    def test_qml_strings(self):
        self.check(slate.files("shell", ".qml"), lambda s: list(spelling.c_literals(s)), search_words_ok=True)

    def test_python_strings(self):
        self.check(slate.files("shell/scripts", ".py"), lambda s: list(spelling.py_literals(s)))

    def test_site_text(self):
        self.check(slate.files("site", ".html"), lambda s: text_spans(s, spelling.html_texts(s)))
        self.check(["site/docs/docs.js", "site/site.js"], lambda s: list(spelling.c_literals(s)))

    def test_markdown(self):
        names = ["README.md", "CLAUDE.md", "shell/data/assistant-prompt.md"] + slate.files("docs", ".md")
        self.check(names, lambda s: text_spans(s, spelling.md_texts(s)))

    def test_shell_messages(self):
        """What the installer and the helper scripts say (comment lines aren't read)."""
        names = ["install.sh"] + [n for n in slate.files("shell/bin", "") + slate.files("shell/scripts", ".sh")]
        bad = {}
        for f in names:
            try:
                lines = slate.read(f).split("\n")
            except (UnicodeDecodeError, IsADirectoryError):
                continue
            hits = [w for l in lines if not l.lstrip().startswith("#")
                    for w in spelling.british_words(re.sub(r"\s#\s.*$", "", l))]
            if hits:
                bad[f] = sorted(set(hits))
        # nocolour is a function name in the log helpers
        bad = {f: [w for w in ws if w != "nocolour"] for f, ws in bad.items()}
        self.assertEqual({f: ws for f, ws in bad.items() if ws}, {},
                         "British spellings in what people read: use the American one")

    def test_your_own_files(self):
        """The files Slate makes for your own tweaks (hypr/*.lua, user/shell.qml) are read by
        people, comments and all: their instructions are the comments."""
        names = [f for f in slate.files("shell/data/user-files", "")]
        self.assertTrue(names)
        self.check(names, lambda s: [(0, len(s), re.sub(r"(?<![\w])[\w]+\.[\w.]+", "", s))])

    def test_the_word_list_knows_the_usual_ones(self):
        """The checker itself: it must catch the usual British words and leave identifiers alone."""
        for british, american in {
            "colour": "color", "Colourful": "Colorful", "centre": "center", "centred": "centered",
            "favourite": "favorite", "grey": "gray", "greyed": "grayed", "cancelled": "canceled",
            "cancelling": "canceling", "organise": "organize", "recognised": "recognized",
            "customise": "customize", "customising": "customizing", "prioritise": "prioritize",
            "minimise": "minimize", "maximise": "maximize", "Maximised": "Maximized",
            "behaviour": "behavior", "licence": "license", "programme": "program",
            "travelling": "traveling", "catalogue": "catalog", "analyse": "analyze",
            "aeroplane": "airplane", "whilst": "while", "organisation": "organization",
        }.items():
            with self.subTest(british):
                self.assertEqual(spelling.american(british), american)
                self.assertEqual(spelling.british_words(f"a {british} here"), [british])
        for kept in ("pageColour", "Config.colourful is on", "folder-colour.py", "--colour",
                     "wallpaper-colours.py", "raise", "otherwise", "noise", "exercise", "GREY",
                     "ecosystem", "colour_cache", "X-Slate-Colour"):
            with self.subTest(kept):
                self.assertEqual(spelling.british_words(kept), [])
