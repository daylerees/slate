"""tests/out/visual/review.html (tests/visual/review.py): one page to look at every changed
screenshot (approved, new, difference) and pick which to approve. Built from made-up pictures
in a scratch checkout."""
import os
import re
import shutil
import sys
import time

from PIL import Image

import slate
from slate import Case, run

VISUAL = slate.path("tests", "visual")


class Review(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.root = os.path.join(self.h.dir, "slate")
        self.visual = os.path.join(self.root, "tests", "visual")
        self.out = os.path.join(self.root, "tests", "out", "visual")
        self.baselines = os.path.join(self.visual, "baselines")
        for d in (self.baselines, self.out, os.path.join(self.root, "shell")):
            os.makedirs(d)
        for f in ("review.py", "approve.py"):
            shutil.copy(os.path.join(VISUAL, f), self.visual)
        self.touch(os.path.join(self.visual, "scenes.py"), -100)
        self.touch(os.path.join(self.root, "shell", "Bar.qml"), -100)
        self.env = {k: v for k, v in self.h.env.items() if k != "SLATE_TEST_OUT"}

    def touch(self, path, ago):
        open(path, "a").close()
        t = time.time() + ago
        os.utime(path, (t, t))

    def shot(self, path, colour, ago=0):
        Image.new("RGB", (16, 10), colour).save(path)
        self.touch(path, ago)

    def changed(self, name, ago=0, approved=True):
        if approved:
            self.shot(os.path.join(self.baselines, name + ".png"), "black", -200)
            self.shot(os.path.join(self.out, name + ".diff.png"), "red", ago)
        self.shot(os.path.join(self.out, name + ".actual.png"), "white", ago)

    def review(self):
        code, out = run([sys.executable, os.path.join(self.visual, "review.py")], env=self.env, cwd=self.root)
        self.assertEqual(code, 0, out)
        return out.strip()

    def page(self):
        with open(os.path.join(self.out, "review.html"), encoding="utf-8") as f:
            return f.read()

    def test_every_changed_scene_and_the_approve_line(self):
        self.changed("panel-control")
        self.changed("settings-dock")
        self.changed("launcher-new", approved=False)
        self.assertEqual(self.review(), "tests/out/visual/review.html")
        page = self.page()
        for name in ("panel-control", "settings-dock", "launcher-new"):
            self.assertIn(f'<input type="checkbox" value="{name}" checked>', page)
            self.assertIn(f'src="{name}.actual.png"', page)
        for name in ("panel-control", "settings-dock"):
            self.assertIn(f'src="{name}.approved.png"', page)
            self.assertIn(f'src="{name}.diff.png"', page)
            self.assertTrue(os.path.exists(os.path.join(self.out, name + ".approved.png")),
                            "the approved picture is copied beside the others")
        self.assertIn("No approved picture yet", page)
        self.assertIn('<code id="cmd">tests/run --approve launcher-new panel-control settings-dock</code>', page)

    def test_self_contained(self):
        self.changed("desktop")
        self.review()
        page = self.page()
        srcs = re.findall(r'(?:src|href)="([^"]+)"', page)
        self.assertTrue(srcs)
        for s in srcs:
            self.assertNotRegex(s, r"^(/|[a-z]+:)", "only relative paths")
            self.assertTrue(os.path.exists(os.path.join(self.out, s)), f"{s} isn't there")
        self.assertNotRegex(page, r"https?://", "nothing from the network")
        self.assertNotIn("<link", page)
        self.assertIn("<style>", page)
        self.assertIn("<script>", page)
        self.assertIn("prefers-color-scheme", page)

    def test_a_stale_picture_starts_unticked(self):
        self.changed("desktop", ago=-300)          # (taken before the code last changed)
        self.changed("launcher")
        self.review()
        page = self.page()
        self.assertIn('<input type="checkbox" value="desktop">', page)
        self.assertIn("--approve leaves it alone", page)
        self.assertIn('<code id="cmd">tests/run --approve launcher</code>', page)

    def test_nothing_changed_no_page(self):
        self.changed("desktop")
        self.review()
        for n in os.listdir(self.out):
            if n.endswith((".actual.png", ".diff.png")):
                os.remove(os.path.join(self.out, n))
        self.assertEqual(self.review(), "", "no path printed")
        self.assertEqual(os.listdir(self.out), [], "the page and the copies go")

    def test_names_are_escaped(self):
        self.changed("a<b")
        self.review()
        self.assertIn('value="a&lt;b"', self.page())
