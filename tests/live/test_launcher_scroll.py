"""The launcher with many apps (150 more than the test image has), scrolled from the top to the
bottom straight after Slate starts, then again: both times every app row comes into view in its
place, none skipped, each with its tile already loaded. A session of its own, so the apps are
there from the start, as they are when you log in, with tiles in each icon's colour (each row's
tile drawn behind its icon).

The first scroll used to go wrong: the apps arrive in several goes as Slate starts, and the
list, handed all those changes while it was closed, laid its rows out wrongly the first time it
opened (after the first screenful it skipped 15 to 50 rows, and the rest sat out of place),
where the second scroll was right. It also held up one frame for 40 to 90 ms as Slate
Settings' icon, drawn mipmapped, came into view at the bottom.

Each scroll's frame times, the time spent moving the list, and how long each opening took are
saved to tests/out/logs/launcher-scroll.json, for comparing the first scroll with the second
and before with after a change. They aren't checked here: a software-drawn session side by side
with others is too uneven for that."""
import atexit
import colorsys
import json
import os
import unittest

from live import LiveCase
from session import Session, in_container

APPS = 150
SCROLL_MS = 3000


def add_apps(h, n=APPS):
    """n apps, each with an icon of its own (a coloured square with a darker middle)."""
    from PIL import Image, ImageDraw
    apps = os.path.join(h.data, "applications")
    icons = os.path.join(h.data, "icons", "scroll-test")
    os.makedirs(apps, exist_ok=True)
    os.makedirs(icons, exist_ok=True)
    for i in range(n):
        r, g, b = (int(c * 255) for c in colorsys.hsv_to_rgb(i / n, 0.6, 0.9))
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((8, 8, 120, 120), 24, fill=(r, g, b, 255))
        d.ellipse((40, 40, 88, 88), fill=(r // 2, g // 2, b // 2, 255))
        icon = os.path.join(icons, f"scrolltest-{i:03d}.png")
        img.save(icon)
        with open(os.path.join(apps, f"scrolltest-{i:03d}.desktop"), "w") as f:
            f.write(f"[Desktop Entry]\nType=Application\nName=Scroll Test {i:03d}\n"
                    f"Comment=A test app, number {i}\nExec=true\nIcon={icon}\n")


def stats(frames):
    """Frame times (ms) summed up: how many, the median, the slowest, and how many took more
    than twice the median (a judder)."""
    if not frames:
        return {"frames": 0}
    s = sorted(frames)
    median = s[len(s) // 2]
    return {"frames": len(s), "median": median, "p95": s[int(len(s) * 0.95)], "max": s[-1],
            "slow": sum(1 for f in s if f > 2 * median)}


class LauncherScroll(LiveCase):
    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"iconTileColour": True})
        add_apps(cls.s.h)
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def open(self):
        """Open the launcher; how long until its first frame was drawn (ms)."""
        self.ipc("launcher", "open")
        st = self.wait(lambda st: st["launcher"]["open"] and st["launcher"]["openMs"] >= 0, "the launcher's first frame")
        return st["launcher"]["openMs"]

    def close(self):
        self.ipc("launcher", "close")
        self.wait(lambda st: not st["launcher"]["visible"], "the launcher to close")

    def scroll(self):
        """Scroll steadily to the bottom; the launcher's state once there."""
        self.ipc("test", "launcherScroll", str(SCROLL_MS))
        # (not asking for the state meanwhile: working it out takes Slate's time too, and
        # showed up in the frame times)
        self.s.settle(SCROLL_MS / 1000 + 0.5)
        return self.wait(lambda st: not st["launcher"]["scrolling"], "the scroll to the bottom", timeout=30)["launcher"]

    def test_first_scroll_shows_every_row(self):
        # Every app's tile drawn (Config's tile-all at login), as on a desktop that's been used
        self.wait(lambda st: st["launcher"]["tileVersion"] >= 1 and st["launcher"]["apps"] >= APPS,
                  "the apps and their tiles", timeout=60)
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        results, scrolls = {}, {}
        for run in ("first", "second"):
            opened = self.open()
            la = self.scroll()
            scrolls[run] = la
            results[run] = dict(stats(la["frames"]), openMs=opened, scrolled=la["scrolled"],
                                work=sum(la["work"]), workMax=max(la["work"] or [0]), frameTimes=la["frames"])
            self.close()
        # Opening again after a search: every row comes back as the search is cleared
        self.open()
        self.ipc("launcher", "search", "zzzz-no-such-app")
        self.wait(lambda st: st["launcher"]["query"] == "zzzz-no-such-app" and st["launcher"]["apps"] == 0, "the search")
        self.close()
        results["afterSearch"] = {"openMs": self.open()}
        self.close()
        self.log("launcher-scroll.json", json.dumps(results, indent=2))

        for run, la in scrolls.items():
            with self.subTest(run):
                done = la["scrolled"]
                self.assertGreaterEqual(la["apps"], APPS)
                # Every app's row was drawn on the way down, in its place, its tile loaded by then
                self.assertEqual(done["misplaced"], 0, f"{done['misplaced']} rows were drawn out of their place")
                self.assertEqual(done["seen"], la["apps"], f"only {done['seen']} of {la['apps']} app rows came into view")
                self.assertEqual(done["ready"], la["apps"], f"{done['seen'] - done['ready']} rows came into view without their tile")
