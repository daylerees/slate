"""scripts/webcam.py: Settings → Webcam's cameras, their picture settings (remembered and put
back at login) and who's using them. A fake v4l2-ctl replays a real camera (an ASUS FHD webcam:
its colour camera, its infrared one and their metadata nodes), over a fake /sys/class/video4linux."""
import json
import os
import subprocess
import sys
import time

import slate
from slate import Case, run
from stubs import Stubs, fixture_text

SCRIPT = slate.path("shell", "scripts", "webcam.py")
NAME = "ASUS FHD webcam: ASUS FHD webca"


class Webcam(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.sys = os.path.join(self.h.dir, "sys")
        self.dev = os.path.join(self.h.dir, "dev")
        os.makedirs(self.dev)
        # Four nodes, as the camera has: video0 (colour), video1 (its metadata), video2 (infrared),
        # video3 (its metadata), all on one USB port
        usb = os.path.join(self.h.dir, "devices", "pci0000:00", "usb3", "3-5", "3-5:1.0")
        os.makedirs(usb)
        for i, name in enumerate([NAME, NAME, "ASUS FHD webcam: ASUS IR camera", "ASUS FHD webcam: ASUS IR camera"]):
            node = os.path.join(self.sys, "video%d" % i)
            os.makedirs(node)
            with open(os.path.join(node, "name"), "w") as f:
                f.write(name + "\n")
            os.symlink(usb, os.path.join(node, "device"))
            open(os.path.join(self.dev, "video%d" % i), "w").close()
        self.s = Stubs(self.h)
        d = self.dev
        self.s.add("v4l2-ctl", by_args={
            f"{d}/video0 --all": fixture_text("webcam", "caps-camera.txt"),
            f"{d}/video2 --all": fixture_text("webcam", "caps-camera.txt"),
            f"{d}/video1 --all": fixture_text("webcam", "caps-meta.txt"),
            f"{d}/video3 --all": fixture_text("webcam", "caps-meta.txt"),
            f"{d}/video0 --list-formats": fixture_text("webcam", "formats-camera.txt"),
            f"{d}/video2 --list-formats": fixture_text("webcam", "formats-ir.txt"),
            f"{d}/video0 --list-ctrls-menus": fixture_text("webcam", "ctrls.txt"),
            "--set-ctrl": "",
        })
        self.s.env.update(SLATE_V4L_SYS=self.sys, SLATE_V4L_DEV=self.dev)
        self.state = os.path.join(self.h.state, "slate", "webcam.json")

    def webcam(self, *args, code=0):
        c, out = run(["python3", SCRIPT, *args], env=self.s.env, timeout=20)
        self.assertEqual(c, code, out)
        return out

    def sets(self):
        return [c[c.index("--set-ctrl") + 1] for c in self.s.calls("v4l2-ctl") if "--set-ctrl" in c]

    # ---- list -------------------------------------------------------------------------------
    def test_lists_the_colour_camera_only(self):
        """Not the infrared camera (face login) or the metadata nodes."""
        cams = json.loads(self.webcam("list"))
        self.assertEqual([(c["device"], c["name"]) for c in cams], [(self.dev + "/video0", "ASUS FHD webcam")])
        self.assertEqual(cams[0]["key"], NAME + "@3-5/3-5:1.0")

    def test_controls(self):
        """The settings Settings shows, in its order, with their ranges and current values."""
        c = {x["name"]: x for x in json.loads(self.webcam("list"))[0]["controls"]}
        self.assertEqual(list(c), ["brightness", "contrast", "saturation", "sharpness", "gain", "gamma",
                                   "white_balance_automatic", "white_balance_temperature", "auto_exposure",
                                   "exposure_time_absolute", "power_line_frequency", "backlight_compensation"])
        self.assertEqual(c["brightness"], {"name": "brightness", "type": "int", "inactive": False,
                                           "min": -64, "max": 64, "step": 1, "default": 0, "value": 0})
        self.assertEqual(c["white_balance_automatic"]["type"], "bool")
        self.assertTrue(c["white_balance_temperature"]["inactive"], "only usable with automatic white balance off")
        self.assertEqual(c["auto_exposure"]["options"], [[1, "Manual Mode"], [3, "Aperture Priority Mode"]])
        self.assertEqual(c["power_line_frequency"]["options"], [[0, "Disabled"], [1, "50 Hz"], [2, "60 Hz"]])
        self.assertNotIn("hue", c, "settings it doesn't show are left alone")

    def test_no_cameras(self):
        self.s.env["SLATE_V4L_SYS"] = os.path.join(self.h.dir, "nothing-here")
        self.assertEqual(json.loads(self.webcam("list")), [])

    def test_no_v4l2_ctl(self):
        self.s.add("v4l2-ctl", missing=True)
        out = self.webcam("list", code=3)
        self.assertIn("v4l2-ctl isn't installed", json.loads(out)["error"])

    # ---- set, reset, apply --------------------------------------------------------------------
    def test_set_is_remembered(self):
        self.webcam("set", self.dev + "/video0", "brightness", "10")
        self.webcam("set", self.dev + "/video0", "power_line_frequency", "1")
        self.assertEqual(self.sets(), ["brightness=10", "power_line_frequency=1"])
        with open(self.state) as f:
            self.assertEqual(json.load(f), {NAME + "@3-5/3-5:1.0": {"brightness": 10, "power_line_frequency": 1}})

    def test_set_unknown_control(self):
        out = self.webcam("set", self.dev + "/video0", "zoom_absolute", "3", code=1)
        self.assertIn("unknown control", out)
        self.assertEqual(self.sets(), [])

    def test_apply_puts_them_back(self):
        """At login: every remembered setting, the automatic switches first (switching one off is
        what lets its manual value be set)."""
        os.makedirs(os.path.dirname(self.state))
        with open(self.state, "w") as f:
            json.dump({NAME + "@3-5/3-5:1.0": {"white_balance_temperature": 3400, "brightness": 5,
                                                 "white_balance_automatic": 0, "auto_exposure": 1,
                                                 "exposure_time_absolute": 300},
                       "Another camera@1-1/1-1:1.0": {"brightness": 40}}, f)
        self.webcam("apply")
        self.assertEqual(self.sets(), ["white_balance_automatic=0", "auto_exposure=1", "brightness=5",
                                       "white_balance_temperature=3400", "exposure_time_absolute=300"])

    def test_apply_with_nothing_remembered(self):
        self.webcam("apply")
        self.assertEqual(self.sets(), [])

    def test_reset(self):
        """Back to the camera's defaults, and forgotten."""
        self.webcam("set", self.dev + "/video0", "brightness", "10")
        self.webcam("reset", self.dev + "/video0")
        done = self.sets()[1:]
        self.assertIn("brightness=0", done)
        self.assertIn("white_balance_automatic=1", done)
        self.assertIn("power_line_frequency=2", done)
        with open(self.state) as f:
            self.assertEqual(json.load(f), {})

    def test_damaged_state(self):
        os.makedirs(os.path.dirname(self.state))
        for bad in ("{half", "[]"):
            with self.subTest(bad):
                with open(self.state, "w") as f:
                    f.write(bad)
                self.webcam("apply")
                self.webcam("set", self.dev + "/video0", "contrast", "60")

    # ---- users -------------------------------------------------------------------------------
    def test_users(self):
        """An app with the camera open is listed; nothing else is."""
        self.assertEqual(json.loads(self.webcam("users")), [])
        app = subprocess.Popen([sys.executable, "-c", "import time; f = open(%r); print('open', flush=True); time.sleep(30)"
                                % (self.dev + "/video0")], stdout=subprocess.PIPE, text=True)
        self.addCleanup(app.kill)
        app.stdout.readline()
        users = json.loads(self.webcam("users"))
        self.assertEqual([(u["pid"], u["device"]) for u in users], [(app.pid, self.dev + "/video0")])

    def test_usage(self):
        out = self.webcam(code=1)
        self.assertIn("webcam.py list", out)
