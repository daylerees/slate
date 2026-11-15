"""Settings → Displays → Brightness (DisplayBrightness.qml, scripts/display-brightness.py): a
slider for each display. The built-in screen is a pretend laptop (the stand-in brightnessctl's
$HOME/.brightness.json, with a pretend /sys saying its backlight is the test output's); a
monitor is the stand-in ddcutil's $HOME/.ddc.json (tests/fixtures/brightness). The slider is
moved through the `test` IPC's brightnessSlide, as a drag would move it."""
import json
import os
import shutil
import subprocess
import sys
import time

from live import LiveCase
from session import OUTPUT

FAKE = os.path.join(os.path.dirname(__file__), "..", "lib", "fake_sensor.py")


class DisplayBrightnessCase(LiveCase):
    def setUp(self):
        super().setUp()
        self.home = self.s.h.home
        self.panel = os.path.join(self.home, ".brightness.json")
        self.monitors = os.path.join(self.home, ".ddc.json")
        self.ddc_calls = os.path.join(self.home, ".ddc-calls")
        self.sys = os.path.join(self.home, ".sys")
        self.dev = os.path.join(self.home, ".dev")
        self.put_back()
        self.addCleanup(self.put_back)

    def put_back(self):
        self.ipc("settings", "close")
        for f in (self.panel, self.monitors, self.ddc_calls, os.path.join(self.home, ".brightness-calls")):
            if os.path.exists(f):
                os.remove(f)
        shutil.rmtree(self.sys, ignore_errors=True)
        shutil.rmtree(self.dev, ignore_errors=True)

    def laptop(self, screen=500):
        """The test output is a laptop's own screen, its backlight at screen/1000."""
        with open(self.panel, "w") as f:
            json.dump({"screen": [screen, 1000]}, f)
        d = os.path.join(self.sys, "class", "backlight", "intel_backlight")
        os.makedirs(d)
        os.symlink("../../card0-" + OUTPUT, os.path.join(d, "device"))

    def monitor(self, value=60, answers=True, slow=0.0, connector="card1-" + OUTPUT, i2c=True):
        """The test output is a monitor ddcutil can reach, on I2C bus 7 (i2c=False: there's no
        /dev/i2c-* this account may use)."""
        if i2c:
            os.makedirs(self.dev, exist_ok=True)
            open(os.path.join(self.dev, "i2c-7"), "w").close()
        with open(self.monitors, "w") as f:
            json.dump({"displays": [{"connector": connector, "bus": 7, "mfg": "TST", "model": "Test Monitor",
                                     "serial": "S1", "value": value, "max": 100, "answers": answers}],
                       "slow": slow}, f)

    def screen(self):
        with open(self.panel) as f:
            return json.load(f)["screen"][0]

    def ddc_sets(self):
        try:
            with open(self.ddc_calls) as f:
                return [c["value"] for c in map(json.loads, f)]
        except FileNotFoundError:
            return []

    def mine(self, st):
        return st["displayBrightness"]["displays"].get(OUTPUT)

    def open_displays(self, ready, since=None):
        """Settings → Displays, from another page (it looks again each time it opens), and what
        it found for the test output once it's done looking (a look finished after `since`)."""
        if since is None:
            since = self.s.state()["displayBrightness"]["checks"]
            self.ipc("settings", "page", "dock")
            self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock", "the Dock page")
            self.ipc("settings", "page", "displays")
        st = self.wait(lambda st: st["settings"]["section"] == "displays" and st["displayBrightness"]["checks"] > since
                       and self.mine(st) is not None and ready(self.mine(st)), "the Displays page to find its brightness")
        return self.mine(st)


class Shown(DisplayBrightnessCase):
    def test_without_ddcutil(self):
        """A monitor, and ddcutil not installed: the row says so (grayed out), and nothing's set."""
        d = self.open_displays(lambda d: d["kind"] == "none")
        self.assertEqual(d["why"], "missing")
        st = self.s.state()
        self.assertEqual(st["displayBrightness"]["ddcutil"], "missing")
        self.assertEqual(st["displayBrightness"]["builtIn"], "")
        self.assertEqual(self.ipc("brightness", "set", OUTPUT, "40"), "no")
        self.assertEqual(json.loads(self.ipc("brightness", "list"))["displays"], {})

    def test_a_monitor_that_doesnt_answer(self):
        self.monitor(answers=False)
        d = self.open_displays(lambda d: d["kind"] == "none")
        self.assertEqual(d["why"], "silent")
        self.assertEqual(self.ipc("brightness", "set", OUTPUT, "40"), "no")
        self.assertEqual(self.ddc_sets(), [])

    def test_ddcutil_cant_reach_the_monitors(self):
        """ddcutil installed, but no I2C device this account may use (i2c-dev not loaded, or not
        in the i2c group): the row says what's needed."""
        self.monitor(i2c=False)
        with open(self.monitors, "w") as f:
            json.dump({"displays": []}, f)          # (ddcutil finds nothing it can talk to)
        d = self.open_displays(lambda d: d["kind"] == "none")
        self.assertEqual(d["why"], "access")
        self.assertEqual(self.s.state()["displayBrightness"]["ddcutil"], "access")


class BuiltIn(DisplayBrightnessCase):
    def test_the_slider_and_the_keys_keep_in_step(self):
        self.laptop(screen=500)
        self.wait(lambda st: not st["osd"]["shown"], "the on-screen indicator to go", timeout=10)
        d = self.open_displays(lambda d: d["kind"] == "backlight")
        self.assertEqual(d["percent"], 50)
        self.assertEqual(self.s.state()["displayBrightness"]["builtIn"], OUTPUT)

        # The slider, as it's dragged: the screen follows it (brightnessctl is quick), quietly
        for v in (45, 40, 30):
            self.ipc("test", "brightnessSlide", OUTPUT, v, "false")
        self.ipc("test", "brightnessSlide", OUTPUT, 30, "true")
        for _ in range(25):
            if self.screen() == 300:
                break
            self.s.settle(0.2)
        self.assertEqual(self.screen(), 300)
        self.assertFalse(self.s.state()["osd"]["shown"], "the slider showed the on-screen indicator")

        # The keys: the slider moves with them
        self.ipc("osd", "brightness", "up")
        st = self.wait(lambda st: self.mine(st)["percent"] == 35, "the slider to follow the brightness keys")
        self.assertEqual(self.screen(), 350)
        self.assertTrue(st["osd"]["shown"], "the keys didn't show the on-screen indicator")
        # ...and the osd IPC (Nova)
        self.ipc("osd", "brightnessSet", "70")
        self.wait(lambda st: self.mine(st)["percent"] == 70, "the slider to follow the osd IPC")

    def test_automatic_brightness_learns_from_the_slider(self):
        """With Automatic brightness on, a change from the slider is yours, as the keys' are:
        learned, and not undone."""
        self.laptop(screen=500)
        p = subprocess.Popen([sys.executable, FAKE, "--lux", "2000"], env=self.s.env,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

        def stop():
            self.ipc("config", "set", "autoBrightness", "false")
            p.stdin.close()
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
        self.addCleanup(stop)
        self.assertEqual(p.stdout.readline().strip(), "ready")
        learned = os.path.join(self.home, ".local", "state", "slate", "auto-brightness.json")
        if os.path.exists(learned):
            os.remove(learned)
        self.config("autoBrightness", "true")
        self.wait(lambda st: st["autoBrightness"]["now"] and st["autoBrightness"]["now"].get("screen") is not None,
                  "Automatic brightness to start following")
        # (it eases to 2000 lux: 86%. The page opens part way there, and the slider shows where
        # it's going)
        self.open_displays(lambda d: d["kind"] == "backlight")
        self.wait(lambda st: self.mine(st)["percent"] >= 80, "the slider to follow Automatic brightness", timeout=10)
        for _ in range(50):
            if self.screen() >= 850:
                break
            self.s.settle(0.2)

        self.ipc("test", "brightnessSlide", OUTPUT, 40, "true")
        st = self.wait(lambda st: st["autoBrightness"]["now"] and st["autoBrightness"]["now"]["paused"],
                       "Automatic brightness to hear the slider")
        self.assertEqual(st["autoBrightness"]["now"]["screen"], 40)
        self.s.settle(2.0)
        self.assertEqual(self.screen(), 400, "the slider's change was undone")


class Monitor(DisplayBrightnessCase):
    def test_a_monitor_over_ddc(self):
        self.monitor(value=60)
        d = self.open_displays(lambda d: d["kind"] == "ddc")
        self.assertEqual((d["percent"], d["bus"], d["max"]), (60, 7, 100))
        self.assertEqual(self.s.state()["displayBrightness"]["ddcutil"], "ok")

        # Dragged: shown at once, and set only where it comes to rest (each step here is a
        # separate IPC call, slower than a drag, so a step or two may rest under a loaded run;
        # a drag's own steps come every few milliseconds)
        for v in (55, 50, 45, 40):
            self.ipc("test", "brightnessSlide", OUTPUT, v, "false")
        self.assertEqual(self.mine(self.s.state())["percent"], 40, "the slider didn't show where it was dragged")
        self.wait_sets(lambda s: s[-1:] == [40], "where the slider rested")
        rested = self.ddc_sets()
        self.assertLess(len(rested), 4, f"set at every step of the drag: {rested}")
        # Let go: straight away
        self.ipc("test", "brightnessSlide", OUTPUT, 75, "true")
        self.wait_sets(lambda s: s[-1:] == [75], "where the slider was let go", timeout=1.5)

        # Nova's way (the brightness IPC)
        self.assertEqual(json.loads(self.ipc("brightness", "list"))["displays"], {OUTPUT: 75})
        self.assertEqual(self.ipc("brightness", "set", OUTPUT, "20"), "ok")
        self.wait_sets(lambda s: s[-1:] == [20], "the brightness IPC's", timeout=1.5)
        self.assertEqual(self.ddc_sets(), rested + [75, 20])

    def wait_sets(self, check, what, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if check(self.ddc_sets()):
                return
            self.s.settle(0.1)
        self.fail(f"the monitor wasn't set to {what}: {self.ddc_sets()}")

    def test_a_slow_monitor_doesnt_hold_slate_up(self):
        """ddcutil takes its time (more with many monitors): Slate answers meanwhile, and the row
        says it's looking."""
        self.monitor(value=60, slow=2.0)
        since = self.s.state()["displayBrightness"]["checks"]
        self.ipc("settings", "page", "dock")
        self.wait(lambda st: st["settings"]["section"] == "dock", "the Dock page")
        self.ipc("settings", "page", "displays")
        st = self.wait(lambda st: st["settings"]["section"] == "displays", "the Displays page")
        t = time.monotonic()
        st = self.s.state()
        self.assertLess(time.monotonic() - t, 1.5, "Slate waited for ddcutil")
        self.assertTrue(st["displayBrightness"]["checking"], "it wasn't still looking")
        d = self.open_displays(lambda d: d["kind"] == "ddc", since=since)
        self.assertEqual(d["percent"], 60)
