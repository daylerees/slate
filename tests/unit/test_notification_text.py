"""shell/NotificationText.js: what a notification's message is allowed to do. The card shows
the message as styled text (bold, italic, underline and links, as the spec allows), and Qt's
styled text would also resize it, recolour it, load any picture it names and link to anything
at all, so safeBody() lets through only the safe kind. Run with node when it's there (the
live tests ask Slate's own engine the same, test_overlays.py)."""

import json
import os
import shutil
import subprocess
import unittest

import slate

REPO = slate.ROOT
SOURCE = os.path.join(REPO, "shell", "NotificationText.js")

# What goes in → what the card's text item is given
BODIES = {
    # The spec's own, kept as they are
    "plain words": "plain words",
    "<b>bold</b> <i>italic</i> <u>under</u>": "<b>bold</b> <i>italic</i> <u>under</u>",
    'see <a href="https://example.org/a?b=1&c=2">this</a>': 'see <a href="https://example.org/a?b=1&c=2">this</a>',
    '<a href="mailto:someone@example.org">write</a>': '<a href="mailto:someone@example.org">write</a>',
    "one<br>two<br/>three": "one<br>two<br>three",
    # Links to anything else lose the link and keep their words
    '<a href="file:///etc/passwd">open</a>': "open",
    '<a href="javascript:alert(1)">open</a>': "open",
    '<a href="slate://settings">open</a>': "open",
    '<a href=" https://example.org/a b">open</a>': "open",
    "<a>open</a>": "open",
    '<a name="https://example.org">open</a>': "open",
    # …however the tag is written; and nothing else in it survives
    "<a href='https://example.org'>x</a>": '<a href="https://example.org">x</a>',
    "<A HREF=https://example.org>x</A>": '<a href="https://example.org">x</a>',
    '<a href="https://example.org" onclick="evil()" style="font-size:90px">x</a>': '<a href="https://example.org">x</a>',
    '<a onclick="href=1" href="HTTPS://example.org">x</a>': '<a href="HTTPS://example.org">x</a>',
    '<a href="https://example.org"><a href="file:///x">y</a></a>': '<a href="https://example.org"></a>y',
    '<b style="font-size:90px" onclick=x>bold</b>': "<b>bold</b>",
    "<B>bold</B> <I>it</I>": "<b>bold</b> <i>it</i>",
    # Pictures named in the words are never loaded
    '<img src="http://example.org/y.png">': "",
    'before <IMG SRC="file:///etc/passwd" alt="x"/> after': "before  after",
    "<img/src=http://example.org/y.png>": "",
    # Every other tag is shown as it was typed
    "<font size=40>big</font>": "&lt;font size=40&gt;big&lt;/font&gt;",
    '<font color="red">x</font>': '&lt;font color="red"&gt;x&lt;/font&gt;',
    "<h1>loud</h1><script>x</script>": "&lt;h1&gt;loud&lt;/h1&gt;&lt;script&gt;x&lt;/script&gt;",
    "<image src=x> <bold> <ins> <ul><li>": "&lt;image src=x&gt; &lt;bold&gt; &lt;ins&gt; &lt;ul&gt;&lt;li&gt;",
    # Ordinary characters and entities
    "a < b and c > d": "a &lt; b and c &gt; d",
    "Tom & Jerry": "Tom &amp; Jerry",
    "&lt;b&gt; &amp; &#8230; &#x2026; &nbsp;": "&lt;b&gt; &amp; &#8230; &#x2026; &nbsp;",
    "&lt;img src=x&gt;": "&lt;img src=x&gt;",
    "& &; &# &#x; AT&T": "&amp; &amp;; &amp;# &amp;#x; AT&amp;T",
    "I <3 this": "I &lt;3 this",
    "std::vector<int> v": "std::vector&lt;int&gt; v",
    # Left open, closed out of order, or never opened
    "unclosed <b": "unclosed &lt;b",
    "<b>open": "<b>open</b>",
    "<b><i>both": "<b><i>both</i></b>",
    "<b><i>crossed</b></i>": "<b><i>crossed</i></b>",
    "closed</b> twice</i>": "closed twice",
    '<a href="https://example.org">open': '<a href="https://example.org">open</a>',
    "<<b>>": "&lt;<b>&gt;</b>",
    "<b <i>x": "&lt;b <i>x</i>",
    "< b>not a tag</ b>": "&lt; b&gt;not a tag&lt;/ b&gt;",
    "": "",
}
# Links the card will open when clicked, and ones it won't
OPENS = ["https://example.org", "http://example.org/a?b=c", "HTTPS://EXAMPLE.ORG", "mailto:someone@example.org"]
STAYS_SHUT = ["file:///etc/passwd", "javascript:alert(1)", "slate://x", "/etc/passwd", "", "https://", "ftp://example.org",
              "https://example.org/a b", " https://example.org", "data:text/html,x", "smb://host/share", "x-scheme-handler:foo"]


@unittest.skipUnless(shutil.which("node"), "needs node (the live tests ask Slate itself)")
class NotificationText(unittest.TestCase):
    def ask(self, expression, values):
        """The file as Slate loads it (less the line that's QML's alone), with each value put to it."""
        with open(SOURCE) as f:
            source = "".join(line for line in f if not line.startswith(".pragma"))
        script = source + "\nconsole.log(JSON.stringify(%s.map(v => %s)));" % (json.dumps(values), expression)
        out = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=30)
        self.assertEqual(out.returncode, 0, out.stderr)
        return json.loads(out.stdout)

    def test_only_the_safe_markup_gets_through(self):
        bodies = list(BODIES)
        for body, got in zip(bodies, self.ask("safeBody(v)", bodies)):
            with self.subTest(body=body):
                self.assertEqual(got, BODIES[body])

    def test_safe_twice_is_the_same(self):
        """What comes out is safe to put through again (a card is drawn more than once)."""
        once = list(BODIES.values())
        for was, got in zip(once, self.ask("safeBody(v)", once)):
            with self.subTest(body=was):
                self.assertEqual(got, was)

    def test_never_throws(self):
        """Whatever it's handed, it answers with text, and none of it an image or a font."""
        odd = [None, 12, {"a": 1}, ["<img src=x>"], "<" * 5000, "<a " * 3000, "<b>" * 3000, "&" * 5000,
               "<a href=\"" + "x" * 20000, "\x00<img\x00src=x>", "<img\nsrc=\nhttp://example.org/x.png\n>", "<\timg src=x>"]
        for got in self.ask("safeBody(v)", odd):
            self.assertIsInstance(got, str)
            self.assertNotRegex(got.lower(), r"<\s*(img|font|h1|script)")

    def test_only_web_and_mail_links_open(self):
        self.assertEqual(self.ask("openable(v)", OPENS), [True] * len(OPENS))
        self.assertEqual(self.ask("openable(v)", STAYS_SHUT + [None, 3]), [False] * (len(STAYS_SHUT) + 2))

    def test_release_notes_lose_pictures_and_odd_links(self):
        """Settings -> Updates shows release notes (from the network) as Markdown: no picture
        is left to load, only web links stay, and the rest of the Markdown is untouched."""
        notes = {
            "![logo](file:///etc/passwd) hi": "logo hi",
            "![x](http://example.org/t.png)": "x",
            "![a ![b](x)](y)": "a b",
            "[open](file:///etc/passwd)": "open",
            "[open](javascript:alert(1))": "open",
            "[open](<file:///x> \"t\")": "open",
            "[web](https://example.org/a)": "[web](https://example.org/a)",
            "[web](https://example.org/a \"title\")": "[web](https://example.org/a \"title\")",
            "[x][ref]\n\n[ref]: file:///etc/passwd": "[x][ref]\n\n",
            "# Title\n\n- one\n- **two**": "# Title\n\n- one\n- **two**",
        }
        keys = list(notes)
        for note, got in zip(keys, self.ask("safeMarkdown(v)", keys)):
            with self.subTest(note=note):
                self.assertEqual(got, notes[note])
        for got in self.ask("safeMarkdown(v)", [None, 5, "![" * 3000, "[" * 5000 + "](" * 3000]):
            self.assertIsInstance(got, str)


if __name__ == "__main__":
    unittest.main()
