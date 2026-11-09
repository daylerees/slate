"""Screenshots of each scene (tests/visual/scenes.py) compared with the approved ones in
tests/visual/baselines/. On a difference: tests/out/visual/<scene>.actual.png and .diff.png
(changes in red). Approve new looks with: tests/run --update-baselines [scene…]"""
import atexit
import os
import unittest

import imgdiff
from PIL import Image
import slate
from live import LiveCase
from scenes import SCENES
from session import Session, SessionError, in_container

BASELINES = os.path.join(slate.TESTS, "visual", "baselines")
OUT = os.path.join(slate.OUT, "visual")


def updating():
    """Scenes to re-shoot (SLATE_UPDATE_BASELINES: "all" or names), or an empty set."""
    v = os.environ.get("SLATE_UPDATE_BASELINES", "").split()
    return set(SCENES) if "all" in v else set(v)


class Visual(LiveCase):
    filters_itself = True       # --filter picks scenes (SLATE_TEST_FILTER), not this test

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("screenshots are taken in the test container only (software rendering)")
        # A fresh session of its own: nothing left open or changed by the live tests
        cls.s = Session()
        atexit.register(cls.s.stop)
        cls.s.start()
        cls.s.settle(4)         # the bar's segments and fonts settle before the first shot
        os.makedirs(OUT, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def shoot(self, name, scene):
        old = {}
        try:
            for k, v in scene.get("settings", {}).items():
                old[k] = self.setting(k)
                self.ipc("config", "set", k, v)
            for step in scene.get("do", []):
                self.ipc(*step)
            self.wait(scene["wait"], f"the {name} scene")
            self.s.settle(scene.get("settle", 0.8))
            return self.s.screenshot(os.path.join(OUT, name + ".actual.png"))
        finally:
            for step in scene.get("undo", []):
                try:
                    self.ipc(*step)
                except SessionError:
                    pass
            for k, v in old.items():
                self.ipc("config", "set", k, v)
            if old:
                self.s.settle(0.8)

    def test_scenes(self):
        update = updating()
        filt = os.environ.get("SLATE_TEST_FILTER", "")
        changed, added = [], []
        for name, scene in SCENES.items():
            if filt and filt not in name:
                continue
            with self.subTest(name):
                actual = self.shoot(name, scene)
                approved = os.path.join(BASELINES, name + ".png")
                if name in update:
                    if not os.path.exists(approved):
                        added.append(name)
                    elif not imgdiff.compare(approved, actual, scene.get("mask", ())).ok:
                        changed.append(name)
                    else:
                        continue          # the same: keep the approved file as it is
                    os.makedirs(BASELINES, exist_ok=True)
                    # (as RGB, compressed harder: the same pixels in a smaller file for git)
                    Image.open(actual).convert("RGB").save(approved, optimize=True)
                    continue
                if not os.path.exists(approved):
                    self.fail(f"no approved screenshot yet; make one with: tests/run --update-baselines {name}")
                result = imgdiff.compare(approved, actual, scene.get("mask", ()))
                if not result.ok:
                    diff = imgdiff.save_diff(approved, actual, os.path.join(OUT, name + ".diff.png"), scene.get("mask", ()))
                    self.fail(f"{result.reason}  [{os.path.relpath(diff, os.getcwd())}]")
                os.remove(actual)
        if update:
            with open(os.path.join(OUT, "updated.txt"), "w") as f:
                f.write("".join(f"new      {n}\n" for n in added) + "".join(f"changed  {n}\n" for n in changed))
