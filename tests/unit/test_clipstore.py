"""scripts/clipstore.py: the clipboard history (store, copy, delete, clear), in a scratch
home, with fake wl-paste/wl-copy that pass bytes through untouched."""
import hashlib
import io
import json
import os
import sys
import time
import unittest
import urllib.parse

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "clipstore.py")
UTF8 = "text/plain;charset=utf-8"

# wl-paste answers --list-types from types.txt and --type <mime> from offers/<mime>; wl-copy
# keeps what it's given in copied/<n>. Both log their arguments. (The shared stubs pass text,
# and images aren't text.)
FAKE = r'''#!{python}
import json, os, sys, urllib.parse
d, name, args = {dir!r}, {name!r}, sys.argv[1:]
with open(os.path.join(d, name + ".calls"), "a") as f:
    f.write(json.dumps(args) + "\n")
if name == "wl-copy":
    out = os.path.join(d, "copied")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, str(len(os.listdir(out)))), "wb") as f:
        f.write(sys.stdin.buffer.read())
elif "--list-types" in args:
    sys.stdout.write(open(os.path.join(d, "types.txt")).read())
else:
    p = os.path.join(d, "offers", urllib.parse.quote(args[args.index("--type") + 1], safe=""))
    if not os.path.exists(p):
        sys.exit(1)
    sys.stdout.buffer.write(open(p, "rb").read())
'''


def sha(data):
    return hashlib.sha1(data).hexdigest()[:16]


def image(fmt, size=(3, 2)):
    """A tiny image's bytes, made now rather than kept in the repo."""
    try:
        from PIL import Image
    except ImportError:
        raise unittest.SkipTest("Pillow isn't installed")
    buf = io.BytesIO()
    Image.new("RGB", size, (200, 40, 90)).save(buf, fmt)
    return buf.getvalue()


class Clipstore(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.fake = os.path.join(self.h.dir, "clip")
        os.makedirs(os.path.join(self.fake, "offers"))
        for name in ("wl-paste", "wl-copy"):
            p = os.path.join(self.s.dir, name)
            with open(p, "w") as f:
                f.write(FAKE.format(python=sys.executable, dir=self.fake, name=name))
            os.chmod(p, 0o755)
        self.dir = self.h(".local", "state", "slate", "clipboard")
        self.index = os.path.join(self.dir, "index.json")

    def offer_path(self, mime):
        return os.path.join(self.fake, "offers", urllib.parse.quote(mime, safe=""))

    def offer_types(self, *types, data=b"x"):
        """What's on the clipboard: these types, each giving `data`."""
        with open(os.path.join(self.fake, "types.txt"), "w") as f:
            f.write("".join(t + "\n" for t in types))
        for t in types:
            with open(self.offer_path(t), "wb") as f:
                f.write(data)

    def clip(self, *args, code=0, state=None):
        env = dict(self.s.env)
        if state is not None:
            env["CLIPBOARD_STATE"] = state
        c, out = run(["python3", SCRIPT, *args], env=env, input="what wl-paste pipes in", timeout=20)
        self.assertEqual(c, code, out)
        return out

    def calls(self, name):
        try:
            with open(os.path.join(self.fake, name + ".calls")) as f:
                return [json.loads(l) for l in f]
        except FileNotFoundError:
            return []

    def entries(self):
        with open(self.index) as f:
            return json.load(f)["entries"]

    def entries_without_time(self):
        out = []
        for e in self.entries():
            self.assertAlmostEqual(e.pop("time"), time.time(), delta=60)
            out.append(e)
        return out

    def seed(self, entries, files=()):
        os.makedirs(self.dir, exist_ok=True)
        with open(self.index, "w") as f:
            json.dump({"entries": entries}, f)
        for name in files:
            with open(os.path.join(self.dir, name), "wb") as f:
                f.write(b"old image")

    # ---- store ----

    def test_store_text(self):
        self.offer_types(UTF8, "text/plain", "TEXT", data="héllo wörld".encode())
        self.clip("store")
        self.assertEqual(self.entries_without_time(),
                         [{"id": sha("héllo wörld".encode()), "kind": "text", "text": "héllo wörld"}])
        # The best text type, without a newline added
        self.assertEqual(self.calls("wl-paste"), [["--list-types"], ["--no-newline", "--type", UTF8]])

    def test_text_types(self):
        """Whichever text type is offered, best first."""
        for types, want in [(("TEXT", "UTF8_STRING"), "UTF8_STRING"), (("STRING",), "STRING"),
                            (("text/plain", "STRING"), "text/plain")]:
            with self.subTest(types=types):
                self.offer_types(*types, data=b"abc")
                self.clip("store")
                self.assertEqual(self.calls("wl-paste")[-1], ["--no-newline", "--type", want])

    def test_repeat_moves_to_top(self):
        for text in (b"one", b"two", b"one"):
            self.offer_types(UTF8, data=text)
            self.clip("store")
        self.assertEqual([e["text"] for e in self.entries()], ["one", "two"])

    def test_not_kept(self):
        cases = {
            "blank": ((UTF8,), b"  \n\t "),
            "too long": ((UTF8,), b"a" * (256 * 1024 + 1)),
            "password manager hint": ((UTF8, "x-kde-passwordmanagerhint"), b"secret"),
            "password type": ((UTF8, "application/x-password"), b"secret"),
            "nothing offered": ((), b""),
            "only types it doesn't keep": (("text/html", "application/x-foo"), b"<b>hi</b>"),
        }
        for name, (types, data) in cases.items():
            with self.subTest(name):
                self.offer_types(*types, data=data)
                self.clip("store")
                self.assertFalse(os.path.exists(self.index))

    def test_longest_text_kept(self):
        self.offer_types(UTF8, data=b"a" * (256 * 1024))
        self.clip("store")
        self.assertEqual(len(self.entries()[0]["text"]), 256 * 1024)

    def test_clipboard_state(self):
        """Cleared, or marked sensitive: wl-paste isn't even asked."""
        self.offer_types(UTF8, data=b"secret")
        for state in ("sensitive", "clear"):
            with self.subTest(state):
                self.clip("store", state=state)
                self.assertEqual(self.calls("wl-paste"), [])
                self.assertFalse(os.path.exists(self.index))
        self.clip("store", state="data")
        self.assertEqual([e["text"] for e in self.entries()], ["secret"])

    def test_store_images(self):
        for mime, fmt, size in [("image/png", "PNG", (3, 2)), ("image/jpeg", "JPEG", (5, 4)),
                                ("image/gif", "GIF", (7, 1)),
                                # No size read from WebP or BMP
                                ("image/webp", "WEBP", (0, 0)), ("image/bmp", "BMP", (0, 0))]:
            with self.subTest(mime):
                data = image(fmt, size if size != (0, 0) else (2, 2))
                self.offer_types(mime, "application/x-other", data=data)
                self.clip("store")
                name = sha(data) + "." + mime.split("/")[1]
                e = self.entries()[0]
                del e["time"]
                self.assertEqual(e, {"id": sha(data), "kind": "image", "file": name, "mime": mime,
                                     "w": size[0], "h": size[1], "bytes": len(data)})
                with open(os.path.join(self.dir, name), "rb") as f:
                    self.assertEqual(f.read(), data)

    def test_image_with_text_is_text(self):
        """An app offering text as well (a file manager's copied file) is kept as the text."""
        self.offer_types("image/png", UTF8, data=b"/srv/pictures/cat.png")
        self.clip("store")
        self.assertEqual([(e["kind"], e.get("text")) for e in self.entries()], [("text", "/srv/pictures/cat.png")])
        self.assertFalse([n for n in os.listdir(self.dir) if n.endswith(".png")])

    def test_paste_fails(self):
        self.offer_types(UTF8)
        os.remove(self.offer_path(UTF8))
        self.clip("store")
        self.assertFalse(os.path.exists(self.index))

    def test_trim_to_100(self):
        """The oldest entry goes once there are 100, and its image file with it."""
        old = [{"id": f"t{i:02}", "kind": "text", "text": str(i), "time": 1} for i in range(99)]
        old.append({"id": "img", "kind": "image", "file": "img.png", "mime": "image/png", "time": 1})
        self.seed(old, files=["img.png"])
        self.offer_types(UTF8, data=b"new")
        self.clip("store")
        got = self.entries()
        self.assertEqual(len(got), 100)
        self.assertEqual([e["id"] for e in got[:2]], [sha(b"new"), "t00"])
        self.assertEqual(got[-1]["id"], "t98")
        self.assertFalse(os.path.exists(os.path.join(self.dir, "img.png")))

    def test_bad_index_starts_afresh(self):
        os.makedirs(self.dir)
        with open(self.index, "w") as f:
            f.write("{half written")
        self.offer_types(UTF8, data=b"new")
        self.clip("store")
        self.assertEqual([e["text"] for e in self.entries()], ["new"])

    # ---- copy, delete, clear ----

    def test_copy_text(self):
        self.seed([{"id": "a", "kind": "text", "text": "héllo"}])
        self.clip("copy", "a")
        self.assertEqual(self.calls("wl-copy"), [["--type", UTF8]])
        with open(os.path.join(self.fake, "copied", "0"), "rb") as f:
            self.assertEqual(f.read(), "héllo".encode())

    def test_copy_image(self):
        data = image("PNG")
        self.seed([{"id": "i", "kind": "image", "file": "i.png", "mime": "image/png"}])
        with open(os.path.join(self.dir, "i.png"), "wb") as f:
            f.write(data)
        self.clip("copy", "i")
        self.assertEqual(self.calls("wl-copy"), [["--type", "image/png"]])
        with open(os.path.join(self.fake, "copied", "0"), "rb") as f:
            self.assertEqual(f.read(), data)

    def test_copy_unknown(self):
        self.seed([{"id": "a", "kind": "text", "text": "x"}])
        self.clip("copy", "nope", code=1)
        self.assertEqual(self.calls("wl-copy"), [])

    def test_delete(self):
        self.seed([{"id": "a", "kind": "text", "text": "x"},
                   {"id": "i", "kind": "image", "file": "i.png"},
                   {"id": "j", "kind": "image", "file": "j.png"}], files=["i.png", "j.png"])
        self.clip("delete", "i")
        self.assertEqual([e["id"] for e in self.entries()], ["a", "j"])
        self.assertFalse(os.path.exists(os.path.join(self.dir, "i.png")))
        self.assertTrue(os.path.exists(os.path.join(self.dir, "j.png")))
        self.clip("delete", "nope")
        self.assertEqual([e["id"] for e in self.entries()], ["a", "j"])

    def test_clear(self):
        self.seed([{"id": "a", "kind": "text", "text": "x"}, {"id": "i", "kind": "image", "file": "i.png"}],
                  files=["i.png"])
        self.clip("clear")
        with open(self.index) as f:
            self.assertEqual(json.load(f), {"entries": []})
        self.assertEqual(sorted(os.listdir(self.dir)), [".lock", "index.json"])

    def test_clear_with_nothing(self):
        self.clip("clear")
        with open(self.index) as f:
            self.assertEqual(json.load(f), {"entries": []})

    def test_usage(self):
        for args in ([], ["copy"], ["delete"], ["frobnicate"]):
            with self.subTest(args=args):
                out = self.clip(*args, code=2)
                self.assertIn("Slate clipboard history", out)
        self.assertEqual(self.calls("wl-paste") + self.calls("wl-copy"), [])
