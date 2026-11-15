"""scripts/auto-brightness.py: Automatic brightness's curve and what it learns (Curve), when it
follows the light (Follower: hysteresis, settling, the pause after a change of yours), how a
change eases, the private file it keeps, and --check's answer on a pretend laptop (the
stand-in brightnessctl in tests/fixtures/brightness, a pretend /sys). The sensor itself, over
D-Bus, is in tests/live/test_brightness.py."""
import importlib.util
import json
import os
import sys

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "auto-brightness.py")
TOOLS = slate.path("tests", "fixtures", "brightness")


def load():
    sys.path.insert(0, os.path.dirname(SCRIPT))       # (it imports slate_common to save)
    spec = importlib.util.spec_from_file_location("auto_brightness", SCRIPT)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


ab = load()


def lux(n):
    return ab.position(n)


class Curve(Case):
    def test_slates_own_curve(self):
        c = ab.Curve(ab.SCREEN_BASE)
        self.assertEqual(round(c.value(lux(0))), 15)
        self.assertEqual(round(c.value(lux(99))), 50)        # indoors
        self.assertEqual(round(c.value(lux(9999))), 100)     # daylight
        self.assertEqual(round(c.value(lux(1e6))), 100)      # (past the top: the top)
        values = [c.value(x / 10) for x in range(0, 41)]
        self.assertEqual(values, sorted(values), "brighter rooms got a darker screen")

    def test_the_keyboard_goes_the_other_way(self):
        k = ab.Curve(ab.KEYBOARD_BASE, rising=False)
        self.assertGreater(k.value(lux(0)), 50)
        self.assertEqual(k.value(lux(500)), 0)

    def test_a_change_is_learned_at_that_light(self):
        c = ab.Curve(ab.SCREEN_BASE)
        c.learn(lux(2000), 40)
        self.assertAlmostEqual(c.value(lux(2000)), 40, places=6)
        # Nearby light changes with it; it still rises; far darker rooms are left alone
        self.assertLess(c.value(lux(5000)), 75)
        values = [c.value(x / 10) for x in range(0, 41)]
        self.assertEqual([round(v, 6) for v in values], sorted(round(v, 6) for v in values))
        self.assertEqual(round(c.value(lux(0))), 15)

    def test_on_a_point_only_that_point_moves(self):
        c = ab.Curve(ab.SCREEN_BASE)
        c.learn(2.0, 60)
        self.assertEqual(c.points(), [15, 30, 60, 80, 100])

    def test_brighter_for_a_dark_room_lifts_the_brighter_ones(self):
        c = ab.Curve(ab.SCREEN_BASE)
        c.learn(1.0, 70)
        p = c.points()
        self.assertEqual(p[1], 70)
        self.assertGreaterEqual(p[2], 70)
        self.assertGreaterEqual(p[3], p[2])

    def test_keyboard_learning_keeps_it_falling(self):
        k = ab.Curve(ab.KEYBOARD_BASE, rising=False)
        k.learn(2.5, 50)
        self.assertAlmostEqual(k.value(2.5), 50)
        p = k.points()
        self.assertEqual(p, sorted(p, reverse=True))

    def test_never_past_the_ends(self):
        c = ab.Curve(ab.SCREEN_BASE)
        c.learn(3.5, 250)
        c.learn(0.5, -40)
        self.assertTrue(all(0 <= v <= 100 for v in c.points()), c.points())
        # (and offsets saved by hand that would go past them are trimmed)
        self.assertEqual(ab.Curve(ab.SCREEN_BASE, offsets=[200, 0, 0, 0, 0]).points()[0], 100)
        self.assertEqual(ab.Curve(ab.SCREEN_BASE, offsets=[1, 2]).offsets, [0.0] * 5)

    def test_vendor_units(self):
        """Sensors that report a share of their range rather than lux use the whole curve."""
        self.assertEqual(ab.position(0, "vendor"), 0)
        self.assertEqual(ab.position(100, "vendor"), ab.TOP)
        self.assertEqual(ab.position(-5), 0)


class Following(Case):
    def follower(self):
        return ab.Follower(ab.Curve(ab.SCREEN_BASE), ab.Curve(ab.KEYBOARD_BASE, rising=False))

    def test_the_first_reading_is_followed_at_once(self):
        f = self.follower()
        self.assertTrue(f.reading(lux(100), 0))
        self.assertTrue(f.due(0))
        self.assertEqual(f.decide(0), {"screen": 50, "keyboard": 0})

    def test_a_change_of_light_waits_to_settle(self):
        f = self.follower()
        f.reading(lux(100), 0)
        f.decide(0)
        self.assertTrue(f.reading(lux(2000), 10))
        self.assertFalse(f.due(11))
        self.assertTrue(f.due(10 + ab.SETTLE))
        self.assertEqual(f.decide(12)["screen"], 86)

    def test_flickers_are_not_followed(self):
        f = self.follower()
        f.reading(lux(1000), 0)
        f.decide(0)
        self.assertFalse(f.reading(lux(1200), 5), "a small change started a move")
        # A shadow that's gone again by the time it settles: nothing
        self.assertTrue(f.reading(lux(100), 10))
        f.reading(lux(1000), 10.5)
        f.reading(lux(1000), 11)
        f.reading(lux(1000), 11.5)
        self.assertIsNone(f.decide(12))

    def test_a_change_of_yours_pauses_and_sticks(self):
        f = self.follower()
        f.reading(lux(2000), 0)
        f.decide(0)
        self.assertTrue(f.manual("screen", 40, 5))
        self.assertTrue(f.paused(5 + ab.PAUSE - 1))
        # The light changes straight after: not followed
        self.assertTrue(f.reading(lux(6000), 6))
        self.assertIsNone(f.decide(6 + ab.SETTLE))
        # Afterwards it is, from what you chose
        f.reading(lux(6000), 5 + ab.PAUSE + 1)
        got = f.decide(5 + ab.PAUSE + 1 + ab.SETTLE)
        self.assertIsNotNone(got)
        self.assertLess(got["screen"], 60)
        # ...and the light you chose it in gives your choice
        self.assertEqual(f.targets(lux(2000))["screen"], 40)

    def test_never_fully_dark(self):
        f = ab.Follower(ab.Curve(ab.SCREEN_BASE, offsets=[-40, 0, 0, 0, 0]))
        self.assertEqual(f.targets(0)["screen"], ab.SCREEN_MIN)

    def test_nothing_to_learn_before_any_light(self):
        self.assertFalse(self.follower().manual("screen", 40, 0))
        self.assertFalse(ab.Follower(ab.Curve(ab.SCREEN_BASE)).manual("keyboard", 40, 0))


class Easing(Case):
    def test_eases_both_ways_without_repeats(self):
        up = ab.ease(100, 900)
        self.assertEqual(up[-1], 900)
        self.assertEqual(up, sorted(set(up)))
        self.assertLessEqual(len(up), ab.STEPS)
        # Slow at the ends, quicker in the middle
        steps = [b - a for a, b in zip([100] + up, up)]
        self.assertLess(steps[0], max(steps))
        self.assertLess(steps[-1], max(steps))
        down = ab.ease(60, 57)
        self.assertEqual(down, [59, 58, 57])
        self.assertEqual(ab.ease(5, 5), [])


class Kept(Case):
    scratch = True

    def test_saved_privately_and_read_back(self):
        os.environ_backup = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(os.environ_backup)))
        os.environ["XDG_STATE_HOME"] = self.h.state
        old = os.umask(0o022)
        self.addCleanup(os.umask, old)
        f = ab.Follower(ab.Curve(ab.SCREEN_BASE), ab.Curve(ab.KEYBOARD_BASE, rising=False))
        f.reading(2.0, 0)
        f.manual("screen", 70, 0)
        ab.save(f)
        path = os.path.join(self.h.state, "slate", "auto-brightness.json")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        back = ab.load()
        self.assertEqual(ab.Curve(ab.SCREEN_BASE, offsets=back["screen"]).value(2.0), 70)
        self.assertEqual(len(back["keyboard"]), 5)

    def test_a_broken_file_is_a_fresh_start(self):
        os.environ_backup = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(os.environ_backup)))
        os.environ["XDG_STATE_HOME"] = self.h.state
        os.makedirs(os.path.join(self.h.state, "slate"))
        with open(os.path.join(self.h.state, "slate", "auto-brightness.json"), "w") as fh:
            fh.write("[not, json")
        self.assertEqual(ab.load(), {})


class Check(Case):
    """--check: what Settings → Displays asks before showing the switch. Without a session or
    system bus there's no iio-sensor-proxy to ask (sensor false)."""
    scratch = True

    def check(self, panel=None, sensor_in_kernel=False):
        env = dict(self.h.env, PATH=TOOLS + ":" + self.h.env["PATH"], SLATE_SYS=self.h("sys"))
        if panel is not None:
            with open(self.h(".brightness.json"), "w") as fh:
                json.dump(panel, fh)
        if sensor_in_kernel:
            d = self.h("sys", "bus", "iio", "devices", "iio:device0")
            os.makedirs(d)
            open(os.path.join(d, "in_illuminance_raw"), "w").close()
        code, out = run([sys.executable, SCRIPT, "--check"], env=env)
        self.assertEqual(code, 0, out)
        return json.loads(out.strip().splitlines()[-1])

    def test_a_desktop(self):
        self.assertEqual(self.check(), {"sensor": False, "hardware": False, "backlight": False, "keyboard": False})

    def test_a_laptop_with_a_keyboard_light(self):
        got = self.check({"screen": [300, 1000], "keyboard": [1, 3]})
        self.assertEqual(got, {"sensor": False, "hardware": False, "backlight": True, "keyboard": True})

    def test_a_sensor_nothing_reads_yet(self):
        """The kernel has a light sensor but iio-sensor-proxy isn't there: Settings shows the
        switch grayed, saying what to install."""
        got = self.check({"screen": [300, 1000]}, sensor_in_kernel=True)
        self.assertEqual(got, {"sensor": False, "hardware": True, "backlight": True, "keyboard": False})

    def test_check_changes_nothing(self):
        self.check({"screen": [300, 1000], "keyboard": [1, 3]})
        self.assertFalse(os.path.exists(self.h(".brightness-calls")), "--check set a brightness")
