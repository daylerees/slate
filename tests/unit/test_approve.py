"""tests/run --approve (tests/visual/approve.py): makes the screenshots a failing run took the
approved ones, without taking them again, and only while they're still current."""
import os
import shutil
import sys
import time

from PIL import Image

import slate
from slate import Case, run

SCRIPT = slate.path("tests", "visual", "approve.py")


class Approve(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        # A copy of the tool in a scratch checkout: tests/visual (with scenes.py and its
        # baselines), tests/out/visual, and a shell/ whose files say when the code changed
        self.root = os.path.join(self.h.dir, "slate")
        self.visual = os.path.join(self.root, "tests", "visual")
        self.out = os.path.join(self.root, "tests", "out", "visual")
        self.baselines = os.path.join(self.visual, "baselines")
        for d in (self.visual, self.out, os.path.join(self.root, "shell")):
            os.makedirs(d)
        shutil.copy(SCRIPT, self.visual)
        self.touch(os.path.join(self.visual, "scenes.py"), -100)
        self.touch(os.path.join(self.root, "shell", "Bar.qml"), -100)
        self.env = {k: v for k, v in self.h.env.items() if k != "SLATE_TEST_OUT"}

    def touch(self, path, ago):
        open(path, "a").close()
        t = time.time() + ago
        os.utime(path, (t, t))

    def shot(self, name, colour, ago=0, kind=".actual.png"):
        p = os.path.join(self.out, name + kind)
        Image.new("RGBA", (8, 8), colour).save(p)
        self.touch(p, ago)
        return p

    def approve(self, *args):
        return run([sys.executable, os.path.join(self.visual, "approve.py")] + list(args), env=self.env)

    def colour(self, name):
        with Image.open(os.path.join(self.baselines, name + ".png")) as im:
            return im.mode, im.getpixel((0, 0))

    def test_approves_what_the_run_took(self):
        self.shot("desktop", "red")
        self.shot("desktop", "white", kind=".diff.png")
        self.shot("launcher", "blue")
        os.makedirs(self.baselines)
        Image.new("RGB", (8, 8), "black").save(os.path.join(self.baselines, "desktop.png"))
        code, out = self.approve()
        self.assertEqual(code, 0, out)
        self.assertEqual(out, "Approved: desktop\nNew: launcher\n")
        self.assertEqual(self.colour("desktop"), ("RGB", (255, 0, 0)))
        self.assertEqual(self.colour("launcher"), ("RGB", (0, 0, 255)))
        self.assertEqual(os.listdir(self.out), [], "the run's pictures should be cleared once approved")

    def test_only_the_scenes_named(self):
        self.shot("desktop", "red")
        self.shot("launcher", "blue")
        code, out = self.approve("launcher")
        self.assertEqual((code, out), (0, "New: launcher\n"))
        self.assertEqual(os.listdir(self.baselines), ["launcher.png"])
        self.assertEqual(os.listdir(self.out), ["desktop.actual.png"])

    def test_pictures_from_before_the_code_changed_are_left(self):
        """Slate's code changed after the picture was taken: it may not be what Slate draws now."""
        self.shot("desktop", "red", ago=-50)
        self.shot("launcher", "blue", ago=-50)
        self.touch(os.path.join(self.root, "shell", "Bar.qml"), -10)
        self.shot("picker", "green")                      # (taken since)
        code, out = self.approve()
        self.assertEqual(code, 1)
        self.assertIn("New: picker", out)
        self.assertIn("Left alone", out)
        self.assertIn("desktop, launcher", out)
        self.assertEqual(os.listdir(self.baselines), ["picker.png"])

    def test_scenes_changed_counts_too(self):
        self.shot("desktop", "red", ago=-50)
        self.touch(os.path.join(self.visual, "scenes.py"), -10)
        self.assertEqual(self.approve()[0], 1)
        self.assertFalse(os.path.isdir(self.baselines))

    def test_nothing_to_approve(self):
        code, out = self.approve()
        self.assertEqual(code, 0)
        self.assertIn("Nothing to approve", out)

    def test_unknown_scene(self):
        self.shot("desktop", "red")
        code, out = self.approve("dekstop")
        self.assertEqual(code, 2)
        self.assertIn("No changed screenshot for: dekstop", out)
        self.assertFalse(os.path.isdir(self.baselines))
