"""scripts/screenshot.sh in a real session: the screen frozen while you choose an area, and the
picture of what you saw then."""
import glob
import os
import shutil
import signal
import subprocess
import time

import numpy as np
from PIL import Image

import slate
from live import LiveCase

# A chooser that gives an area once the test says so (as if you'd dragged it out then), leaving
# word that it opened
SLURP = """#!/bin/sh
touch "$STUB_DIR/opened"
while [ ! -e "$STUB_DIR/go" ]; do sleep 0.05; done
echo "$STUB_AREA"
"""
# Round the dock, at the bottom of the screen
AREA = (420, 700, 600, 200)


class Frozen(LiveCase):
    def setUp(self):
        super().setUp()
        self.stubs = self.s.h("screenshot-stubs")
        shutil.rmtree(self.stubs, ignore_errors=True)
        os.makedirs(self.stubs)
        for name, text in (("slurp", SLURP), ("notify-send", "#!/bin/sh\n"), ("wl-copy", "#!/bin/sh\ncat >/dev/null\n"),
                           ("swash", "#!/bin/sh\n")):
            p = os.path.join(self.stubs, name)
            with open(p, "w") as f:
                f.write(text)
            os.chmod(p, 0o755)
        self.folder = self.s.h("Pictures", "Screenshots")
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_area_is_what_was_frozen(self):
        """Print Screen with the dock magnified: the screen freezes as it is, the dock springs
        back under the freeze (the pointer's on the chooser now), and the area you choose is
        saved. The picture is the frozen one. It was taken once the freeze was put away, while
        Hyprland faded it out over the dock as it is now, so the dock came out twice, one over
        the other (a bug)."""
        self.keep_setting("dockHoverEffect")
        self.config("dockHoverEffect", "magnify")
        self.close_windows()
        # Hyprland's own animations, as on a desktop (the tests have them off)
        self.s.hyprctl("eval", "hl.config({ animations = { enabled = true } })")
        self.addCleanup(lambda: self.s.hyprctl("eval", "hl.config({ animations = { enabled = false } })"))
        self.addCleanup(lambda: self.ipc("test", "dockHover", "-1"))
        first = next(i for i, x in enumerate(self.s.state()["dock"]["slots"]) if x["kind"] == "app")
        self.ipc("test", "dockHover", str(first))
        self.wait(lambda st: st["dock"]["scale"][first] > 1.2, "the dock magnified")
        self.s.settle(0.5)

        x, y, w, h = AREA
        # (hyprpicker's freeze: a stand-in, as the session has no pointer and hyprpicker needs one)
        path = os.pathsep.join([self.stubs, os.path.join(slate.FIXTURES, "live", "freeze"), self.s.env.get("PATH", os.environ["PATH"])])
        env = dict(self.s.env, PATH=path,
                   STUB_DIR=self.stubs, STUB_AREA=f"{x},{y} {w}x{h}")
        shot = subprocess.Popen(["/bin/sh", os.path.join(self.s.slate_dir, "scripts", "screenshot.sh"), "region"],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

        def stop():
            if shot.poll() is None:
                os.killpg(shot.pid, signal.SIGTERM)
        self.addCleanup(stop)
        end = time.monotonic() + 10
        while not (os.path.exists(os.path.join(self.stubs, "opened")) and '"hyprpicker"' in self.s.hyprctl("-j", "layers")):
            self.assertLess(time.monotonic(), end, "the screen didn't freeze")
            time.sleep(0.1)
        self.s.settle(1)                     # (Hyprland's fade in)
        frozen = self.s.h("frozen.png")
        self.s.run(["grim", "-g", f"{x},{y} {w}x{h}", frozen], check=True)

        # The pointer's on the chooser now: the dock springs back, under the freeze
        self.ipc("test", "dockHover", "-1")
        self.wait(lambda st: all(sc == 1 for sc in st["dock"]["scale"]), "the dock back to rest")
        self.s.settle(0.5)
        open(os.path.join(self.stubs, "go"), "w").close()
        self.assertEqual(shot.wait(timeout=15), 0)
        saved = glob.glob(os.path.join(self.folder, "*.png"))
        self.assertEqual(len(saved), 1, "no screenshot saved")
        self.assertFalse('"hyprpicker"' in self.s.hyprctl("-j", "layers"), "the freeze stayed up")

        want = np.asarray(Image.open(frozen).convert("RGB")).astype(int)
        got = np.asarray(Image.open(saved[0]).convert("RGB")).astype(int)
        shutil.copy(saved[0], os.path.join(self.s.out, "screenshot-of-frozen-dock.png"))
        self.assertEqual(got.shape, want.shape)
        off = np.abs(got - want).max(axis=2)
        self.assertLess(int((off > 8).sum()), 20,
                        f"{int((off > 8).sum())} pixels differ from the frozen screen (up to {int(off.max())}): "
                        "the dock as it is now showed through")
