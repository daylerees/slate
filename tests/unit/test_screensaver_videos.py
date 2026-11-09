"""scripts/screensaver-videos.py: Settings → Screensaver → Get scenery videos. Its pure parts
(best_size, the sizes file, CREDITS.txt, the clip list) tested directly, and a whole run with
downloading replaced by a fake, so nothing goes online."""
import contextlib
import importlib.util
import io
import json
import os
import sys
import urllib.request

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "screensaver-videos.py")


def load():
    spec = importlib.util.spec_from_file_location("screensaver_videos", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Pure(Case):
    scratch = True

    @classmethod
    def setUpClass(cls):
        cls.m = load()

    def test_best_size(self):
        all3 = {"sizes": ["2160p", "1440p", "1080p"]}
        upto1440 = {"sizes": ["1440p", "1080p"]}
        only1080 = {"sizes": ["1080p"]}
        cases = [
            (all3, "2160p", "2160p"), (all3, "1440p", "1440p"), (all3, "1080p", "1080p"),
            (upto1440, "2160p", "1440p"), (upto1440, "1440p", "1440p"), (upto1440, "1080p", "1080p"),
            (only1080, "2160p", "1080p"), (only1080, "1440p", "1080p"),
            (all3, "720p", "1080p"), (all3, "", "1080p"),          # an unknown quality: the default
            ({"sizes": ["1440p"]}, "1080p", "1080p"),              # nothing small enough: 1080p
            ({"sizes": ["1080p", "2160p"]}, "2160p", "2160p"),     # order doesn't matter
        ]
        for clip, quality, want in cases:
            with self.subTest(f"{clip['sizes']} up to {quality or 'nothing'}"):
                self.assertEqual(self.m.best_size(clip, quality), want)

    def test_clips(self):
        """Each clip is complete, its sizes are ones Commons makes, and its licence is one
        Slate allows (public domain, CC0 or CC BY with the credit)."""
        files = [c["file"] for c in self.m.CLIPS]
        self.assertEqual(len(files), len(set(files)), "two clips saved under one name")
        for c in self.m.CLIPS:
            with self.subTest(c["file"]):
                self.assertEqual(set(c), {"file", "title", "base", "sizes", "source", "licence"})
                self.assertRegex(c["file"], r"^[a-z0-9-]+\.webm$")
                self.assertTrue(c["base"].startswith("https://upload.wikimedia.org/wikipedia/commons/transcoded/"))
                self.assertTrue(c["base"].endswith(".webm"))
                self.assertTrue(c["source"].startswith("https://commons.wikimedia.org/wiki/File:"))
                self.assertTrue(c["sizes"] and set(c["sizes"]) <= set(self.m.QUALITIES))
                self.assertIn("1080p", c["sizes"], "every clip needs the default size")
                self.assertRegex(c["licence"], r"^(Public domain|CC0)|, CC BY \d\.\d \(https://creativecommons\.org/licenses/by/")

    def test_credits(self):
        d = self.h("videos")
        os.makedirs(d)
        self.m.credits(d)
        with open(os.path.join(d, "CREDITS.txt")) as f:
            text = f.read()
        lines = text.split("\n")
        self.assertEqual(lines[0], "Scenery videos for Slate's screensaver, downloaded from Wikimedia Commons.")
        self.assertEqual(lines[1], "")
        # Then four lines per clip: title (file), licence, source, a blank
        for i, c in enumerate(self.m.CLIPS):
            with self.subTest(c["file"]):
                at = 2 + 4 * i
                self.assertEqual(lines[at:at + 4], [f"{c['title']} ({c['file']})", "  " + c["licence"],
                                                    "  " + c["source"], ""])
        self.assertEqual(len(lines), 2 + 4 * len(self.m.CLIPS))

    def test_sizes_file(self):
        d = self.h("videos")
        os.makedirs(d)
        self.assertEqual(self.m.load_sizes(d), {}, "no file yet")
        self.m.save_sizes(d, {"a.webm": "1440p"})
        self.assertEqual(self.m.load_sizes(d), {"a.webm": "1440p"})
        with open(os.path.join(d, ".slate-scenery.json"), "w") as f:
            f.write("{not json")
        self.assertEqual(self.m.load_sizes(d), {}, "a broken file counts as none")
        self.assertEqual(self.m.load_sizes(self.h("missing")), {})


class Download(Case):
    """main() with fetch() replaced: which clips it fetches, at what size, and what it prints."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.m = load()
        self.dir = self.h("videos")
        self.fetched = []
        self.fail = set()

        def fetch(url, dest, report):
            self.fetched.append((os.path.basename(dest), url))
            with open(dest + ".part", "w") as f:
                f.write("partial")
            if os.path.basename(dest) in self.fail:
                raise OSError("connection reset")
            report(0.5)
            report(1.0)
            os.replace(dest + ".part", dest)
        self.m.fetch = fetch
        self.m.silence = lambda path: None
        # Belt and braces: nothing may go online
        def offline(*a, **k):
            raise AssertionError("tried to go online")
        self.addCleanup(setattr, urllib.request, "urlopen", urllib.request.urlopen)
        urllib.request.urlopen = offline

    def main(self, *args):
        out = io.StringIO()
        argv = sys.argv
        sys.argv = [SCRIPT, self.dir, *args]
        try:
            with contextlib.redirect_stdout(out):
                self.m.main()
        finally:
            sys.argv = argv
        return out.getvalue().splitlines()

    def sizes(self):
        with open(os.path.join(self.dir, ".slate-scenery.json")) as f:
            return json.load(f)

    def test_fetches_everything(self):
        lines = self.main("1440p")
        n = len(self.m.CLIPS)
        self.assertEqual([f for f, _ in self.fetched], [c["file"] for c in self.m.CLIPS])
        for c, (_, url) in zip(self.m.CLIPS, self.fetched):
            with self.subTest(c["file"]):
                self.assertEqual(url, f"{c['base']}.{self.m.best_size(c, '1440p')}.vp9.webm")
        self.assertEqual(self.sizes(), {c["file"]: self.m.best_size(c, "1440p") for c in self.m.CLIPS})
        self.assertEqual(lines[0], f"1/{n} {self.m.CLIPS[0]['title']}")
        self.assertEqual(lines[1], "progress 0.000")
        self.assertEqual(lines[-1], f"done {n}")
        self.assertEqual(lines[-2], "progress 1.000")
        self.assertTrue(os.path.exists(os.path.join(self.dir, "CREDITS.txt")))
        # Progress only ever goes up, between 0 and 1
        p = [float(l.split()[1]) for l in lines if l.startswith("progress ")]
        self.assertEqual(p, sorted(p))
        self.assertTrue(0 <= p[0] and p[-1] <= 1)

    def test_default_quality(self):
        self.main()
        self.assertTrue(all(url.endswith(".1080p.vp9.webm") for _, url in self.fetched))

    def test_skips_what_is_there(self):
        """Clips already there at the size wanted (or better) aren't fetched again; ones there
        smaller are (one from before sizes were noted counts as 1080p)."""
        os.makedirs(self.dir)
        big = [c["file"] for c in self.m.CLIPS if "2160p" in c["sizes"]]
        first, second, third = big[:3]
        for name in (first, second, third):
            open(os.path.join(self.dir, name), "w").close()
        # first: noted at 2160p; second: noted at 1080p; third: not noted
        with open(os.path.join(self.dir, ".slate-scenery.json"), "w") as f:
            json.dump({first: "2160p", second: "1080p"}, f)
        lines = self.main("2160p")
        got = [f for f, _ in self.fetched]
        self.assertEqual(got, [c["file"] for c in self.m.CLIPS if c["file"] != first])
        self.assertEqual(self.sizes()[second], "2160p")
        self.assertEqual(lines[-1], f"done {len(self.m.CLIPS)}")

    def test_nothing_to_do(self):
        """Everything there already: no downloads at all, and still CREDITS.txt."""
        os.makedirs(self.dir)
        for c in self.m.CLIPS:
            open(os.path.join(self.dir, c["file"]), "w").close()
        lines = self.main("1080p")
        self.assertEqual(self.fetched, [])
        self.assertEqual(lines[-1], f"done {len(self.m.CLIPS)}")
        self.assertTrue(os.path.exists(os.path.join(self.dir, "CREDITS.txt")))

    def test_a_failed_clip(self):
        """One clip failing says so, leaves no .part behind, and the rest still come."""
        bad = self.m.CLIPS[1]
        self.fail = {bad["file"]}
        lines = self.main()
        self.assertIn(f"error {bad['title']}: connection reset", lines)
        self.assertFalse(os.path.exists(os.path.join(self.dir, bad["file"] + ".part")))
        self.assertFalse(os.path.exists(os.path.join(self.dir, bad["file"])))
        self.assertNotIn(bad["file"], self.sizes())
        self.assertEqual(len(self.fetched), len(self.m.CLIPS))
        self.assertEqual(lines[-1], f"done {len(self.m.CLIPS) - 1}")


class Command(Case):
    """The script itself, run as Settings runs it."""
    scratch = True

    def test_usage(self):
        code, out = run([sys.executable, SCRIPT], env=self.h.env)
        self.assertEqual(code, 1)
        self.assertIn("Usage: screensaver-videos.py <folder> [quality]", out)

    def test_offline_run_with_everything_there(self):
        """With every clip already downloaded it never goes online: it just writes the credits.
        No ffmpeg on PATH, so nothing is re-encoded either."""
        d = self.h("Videos", "Scenery")
        os.makedirs(d)
        m = load()
        for c in m.CLIPS:
            with open(os.path.join(d, c["file"]), "w") as f:
                f.write("video")
        with open(os.path.join(d, ".slate-scenery.json"), "w") as f:
            json.dump({c["file"]: "2160p" for c in m.CLIPS}, f)
        s = Stubs(self.h)
        env = dict(s.env, PATH=s.dir, https_proxy="http://127.0.0.1:9", http_proxy="http://127.0.0.1:9")
        code, out = run([sys.executable, SCRIPT, d, "2160p"], env=env, timeout=30)
        self.assertEqual(code, 0, out)
        lines = out.splitlines()
        self.assertEqual(lines[-1], f"done {len(m.CLIPS)}")
        self.assertFalse([l for l in lines if l.startswith("error")])
        self.assertEqual(sorted(os.listdir(d)), sorted([".slate-scenery.json", "CREDITS.txt"] + [c["file"] for c in m.CLIPS]))
        with open(os.path.join(d, m.CLIPS[0]["file"])) as f:
            self.assertEqual(f.read(), "video")
