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
        Session.stop_shared()
        cls.s = Session()
        atexit.register(cls.s.stop)
        cls.s.start()
        cls.s.settle(4)         # the bar's segments and fonts settle before the first shot
        # The clock can be laid out before Slate's own font has loaded, keeping glyph positions a
        # fraction of a pixel off from then on (only the first scene showed it; later ones had
        # re-laid the bar). Lay it out again, now the font's there
        cls.s.ipc("config", "set", "barClockDate", "false")
        cls.s.settle(0.5)
        cls.s.ipc("config", "set", "barClockDate", "true")
        cls.s.settle(1.5)
        os.makedirs(OUT, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def shoot(self, name, scene):
        old = {}
        # Every scene starts with no notifications: one left from an earlier scene (its pop-up,
        # the bell's count) made a scene's picture depend on what ran before it, so it differed
        # when run on its own. Scenes that show one send it themselves
        self.ipc("notifications", "clear")
        self.wait(lambda st: st["notifications"]["toasts"] == 0, "the pop-ups to go")
        try:
            for k, v in scene.get("settings", {}).items():
                old[k] = self.setting(k)
                self.ipc("config", "set", k, v)
            for step in scene.get("do", []):
                if step[0].startswith("!"):          # a command, in the session (notify-send…)
                    self.s.run([step[0][1:]] + list(step[1:]), check=True)
                else:
                    self.ipc(*step)
            self.wait(scene["wait"], f"the {name} scene")
            self.s.settle(scene.get("settle", 0.8))
            return self.s.screenshot(os.path.join(OUT, name + ".actual.png"))
        finally:
            for step in scene.get("undo", []):
                try:
                    if step[0].startswith("!"):
                        self.s.run([step[0][1:]] + list(step[1:]))
                    else:
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
                    # Approving keeps what's on screen now when it really changed, a change within
                    # the tolerance too (else small changes pile up unseen in the approved pictures)
                    if not os.path.exists(approved):
                        added.append(name)
                    else:
                        if not imgdiff.changed(approved, actual, scene.get("mask", ())):
                            continue          # the same (but for rendering noise): keep the approved file
                        r = imgdiff.compare(approved, actual, scene.get("mask", ()))
                        changed.append(name if not r.ok else name + "  (small: within the tolerance)")
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
