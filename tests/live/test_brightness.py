"""Automatic brightness (Settings → Displays; AutoBrightness.qml, scripts/auto-brightness.py),
on a pretend laptop: a light sensor standing in for iio-sensor-proxy on the session bus
(tests/lib/fake_sensor.py) and a stand-in brightnessctl whose backlights are numbers in
$HOME/.brightness.json (tests/fixtures/brightness). The switch only shows where there's a
sensor; the screen eases to the room; a change of yours is kept for that light rather than
undone; and switching it off gives the sensor back."""
import json
import os
import subprocess
import sys
import time

from live import LiveCase

FAKE = os.path.join(os.path.dirname(__file__), "..", "lib", "fake_sensor.py")


class AutoBrightnessCase(LiveCase):
    def setUp(self):
        super().setUp()
        self.home = self.s.h.home
        self.panel = os.path.join(self.home, ".brightness.json")
        self.calls = os.path.join(self.home, ".brightness-calls")
        self.record = os.path.join(self.home, ".sensor.json")
        learned = os.path.join(self.home, ".local", "state", "slate", "auto-brightness.json")
        for f in (self.calls, self.record, learned):
            if os.path.exists(f):
                os.remove(f)
        self.addCleanup(self.put_back)

    def put_back(self):
        self.ipc("config", "set", "autoBrightness", "false")
        self.ipc("settings", "close")
        self.wait(lambda st: not st["autoBrightness"]["running"], "Automatic brightness to stop")
        if os.path.exists(self.panel):
            os.remove(self.panel)

    def laptop(self, screen=500, keyboard=None):
        """The pretend laptop's backlights: the screen at screen/1000, the keyboard's at
        keyboard/3 (None: it has none)."""
        state = {"screen": [screen, 1000]}
        if keyboard is not None:
            state["keyboard"] = [keyboard, 3]
        with open(self.panel, "w") as f:
            json.dump(state, f)

    def sensor(self, lux=100):
        """The pretend light sensor, until the test ends."""
        p = subprocess.Popen([sys.executable, FAKE, "--lux", str(lux), "--record", self.record], env=self.s.env,
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

        def stop():
            p.stdin.close()
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
        self.addCleanup(stop)
        line = p.stdout.readline().strip()
        if line != "ready":
            self.fail("the pretend light sensor didn't start: " + line)
        self.light = p
        return p

    def lux(self, value):
        self.light.stdin.write("lux %s\n" % value)
        self.light.stdin.flush()

    def screen(self):
        with open(self.panel) as f:
            return json.load(f)["screen"][0]

    def keyboard(self):
        with open(self.panel) as f:
            return json.load(f)["keyboard"][0]

    def set_calls(self, device="screen"):
        try:
            with open(self.calls) as f:
                return [c["value"] for c in map(json.loads, f) if c["device"] == device]
        except FileNotFoundError:
            return []

    def claims(self):
        try:
            with open(self.record) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def wait_screen(self, want, what, timeout=10, near=10):
        """Until the screen is about `want`: as long as it's still moving (`timeout` seconds
        without a step is too long), since a loaded run makes each step slower, not wrong."""
        last, since = self.screen(), time.monotonic()
        while time.monotonic() - since < timeout:
            now = self.screen()
            if abs(now - want) <= near:
                return
            if now != last:
                last, since = now, time.monotonic()
            self.s.settle(0.2)
        self.fail(f"{what}: the screen stopped at {self.screen()}/1000, not about {want}")

    def wait_eased(self, what, timeout=10):
        """Until the easing has reached where Slate says it's taking the screen: the last step
        set is the target (Light.raw of the percentage in its status line, which every ease ends
        on). Waiting for half a second without a step ended early in a loaded full run, and the
        rest of the easing was then taken for following a flicker."""
        target = None
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            now = self.s.state()["autoBrightness"]["now"] or {}
            if now.get("screen") is not None:
                target = max(1, min(1000, int(round(now["screen"] / 100.0 * 1000))))
                calls = self.set_calls()
                if calls and calls[-1] == target and self.screen() == target:
                    return
            self.s.settle(0.1)
        self.fail(f"{what}: the screen is at {self.screen()}/1000, still easing to {target}")

    def switch_on(self):
        self.config("autoBrightness", "true")
        return self.wait(lambda st: st["autoBrightness"]["running"] and st["autoBrightness"]["now"]
                         and st["autoBrightness"]["now"].get("screen") is not None, "Automatic brightness to start following")


class Shown(AutoBrightnessCase):
    def open_displays(self):
        # (from another page: the Displays page looks again each time it opens)
        self.ipc("settings", "page", "dock")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock", "the Dock page")
        self.ipc("settings", "page", "displays")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "displays", "the Displays page")

    def test_hidden_without_a_sensor(self):
        """A laptop without a light sensor (or a desktop): no switch, and nothing left running."""
        self.laptop()
        self.open_displays()
        st = self.wait(lambda st: st["autoBrightness"]["checked"], "the check for a sensor")
        self.assertFalse(st["autoBrightness"]["sensor"])
        self.assertFalse(st["autoBrightness"]["shown"], "the switch shows without a sensor")
        # Switched on anyway (from the command line, or settings brought from another computer):
        # the script finds no sensor and stops, rather than waiting about
        self.config("autoBrightness", "true")
        self.s.settle(1.5)
        self.assertFalse(self.s.state()["autoBrightness"]["running"], "it kept running without a sensor")
        self.assertEqual(self.set_calls(), [], "it changed the brightness without a sensor")

    def test_shown_with_a_sensor(self):
        self.laptop()
        self.sensor()
        self.open_displays()
        st = self.wait(lambda st: st["autoBrightness"]["checked"] and st["autoBrightness"]["sensor"], "the sensor to be found")
        self.assertTrue(st["autoBrightness"]["shown"])
        self.assertFalse(st["autoBrightness"]["running"], "it's running with the switch off")
        self.assertEqual(self.claims().get("claimed"), 0, "the sensor was claimed with the switch off")


class Follows(AutoBrightnessCase):
    def test_follows_the_light_smoothly(self):
        self.laptop(screen=500, keyboard=0)
        self.sensor(lux=100)
        self.switch_on()
        # 100 lux (indoors) is Slate's 50%: where the screen already is
        self.s.settle(0.5)
        self.assertEqual(self.screen(), 500)
        self.assertEqual(self.claims().get("held"), 1, "the sensor isn't claimed")

        # Brighter: it waits for the light to settle, then eases there in steps
        self.lux(2000)
        self.s.settle(1.0)
        self.assertEqual(self.screen(), 500, "it followed before the light had settled")
        self.wait_screen(860, "following 2000 lux", near=5)
        steps = self.set_calls()
        self.assertGreater(len(steps), 4, f"it jumped rather than eased: {steps}")
        self.assertEqual(steps, sorted(steps), f"it didn't go one way: {steps}")
        self.assertTrue(all(b - a <= 150 for a, b in zip([500] + steps, steps)), f"too big a step: {steps}")

        # A flicker (a little more light) isn't followed. (Once the easing has finished: near
        # 860 can be a step short of it, and that last step was once taken for following it)
        self.wait_eased("easing to 2000 lux")
        before = len(self.set_calls())
        self.lux(2300)
        self.s.settle(3.0)
        self.assertEqual(len(self.set_calls()), before, "it followed a small flicker")

        # Dark: the screen goes down, and the keyboard's light comes on
        self.lux(1)
        self.wait_screen(195, "following a dark room", near=10)
        self.assertGreaterEqual(self.keyboard(), 1, "the keyboard's light stayed off in the dark")

    def test_a_change_of_yours_is_kept(self):
        self.laptop(screen=500)
        self.sensor(lux=2000)
        self.switch_on()
        self.wait_screen(860, "following 2000 lux", near=5)

        # You turn it down (the keys and Nova both come through the osd IPC)
        self.ipc("osd", "brightnessSet", "40")
        st = self.wait(lambda st: st["autoBrightness"]["now"] and st["autoBrightness"]["now"]["paused"],
                       "your change to be heard")
        self.assertEqual(st["autoBrightness"]["now"]["screen"], 40)
        self.assertEqual(self.screen(), 400)

        # The light changes straight after: it isn't fought while your change is fresh
        self.lux(6000)
        self.s.settle(3.0)
        self.assertEqual(self.screen(), 400, "your change was undone straight away")

        # Once the pause is over it follows again, from what you chose: brighter, but well
        # under the 96% it would have been
        self.wait_screen(475, "following again, with your change learned", timeout=15, near=40)
        # ...and back in the light you chose it for, it's what you chose
        self.lux(2000)
        self.wait_screen(400, "back to your choice for that light", near=15)

        # Kept for next time, readable by you alone
        learned = os.path.join(self.home, ".local", "state", "slate", "auto-brightness.json")
        self.assertEqual(os.stat(learned).st_mode & 0o777, 0o600)
        self.assertLess(json.load(open(learned))["screen"][3], 0)

    def test_off_gives_the_sensor_back(self):
        self.laptop()
        self.sensor()
        self.switch_on()
        self.assertEqual(self.claims().get("held"), 1)
        self.config("autoBrightness", "false")
        self.wait(lambda st: not st["autoBrightness"]["running"], "it to stop")
        for _ in range(20):
            if self.claims().get("held") == 0:
                break
            self.s.settle(0.2)
        c = self.claims()
        self.assertEqual(c.get("held"), 0, "the sensor's still claimed")
        self.assertEqual(c.get("released"), 1, "the claim wasn't given back (ReleaseLight)")
        # ...and nothing moves the brightness any more
        before = len(self.set_calls())
        self.lux(5000)
        self.s.settle(3.0)
        self.assertEqual(len(self.set_calls()), before)
