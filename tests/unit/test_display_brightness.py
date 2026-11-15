"""scripts/display-brightness.py: which displays Settings → Displays can set the brightness of,
and how bright they are. ddcutil's `detect --terse` read as ddcutil 3 prints it (and 1.x, which
names no connector), each ddcutil display matched to Hyprland's output, the built-in screen
found from /sys, and the whole run with stand-ins for hyprctl, brightnessctl and ddcutil: what
it says when ddcutil isn't installed, can't reach the monitors, or a monitor doesn't answer."""
import importlib.util
import json
import os
import sys

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "display-brightness.py")


def load():
    spec = importlib.util.spec_from_file_location("display_brightness", SCRIPT)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


db = load()

# What ddcutil 3.0 printed on a laptop with its lid open and nothing plugged in
LAPTOP_ONLY = """Invalid display
   I2C bus:          /dev/i2c-13
   DRM connector:    card0-eDP-1
   drm_connector_id: 397
   Monitor:          SDC::

"""

# Two monitors (one through a dock, which shows it twice), and the laptop's own
DESK = """Display 1
   I2C bus:          /dev/i2c-4
   DRM connector:    card1-DP-1
   drm_connector_id: 98
   Monitor:          DEL:DELL U2720Q:7XYZ123

Display 2
   I2C bus:          /dev/i2c-6
   DRM connector:    card1-HDMI-A-1
   drm_connector_id: 104
   Monitor:          GSM:LG ULTRAGEAR:

Phantom display
   I2C bus:          /dev/i2c-9
   DRM connector:    card1-DP-1
   Monitor:          DEL:DELL U2720Q:7XYZ123

Invalid display
   I2C bus:          /dev/i2c-13
   DRM connector:    card1-eDP-1
   drm_connector_id: 397
   Monitor:          SDC::
   DDC communication failed
   This is a eDP laptop display. Laptop displays do not support DDC/CI.
"""

# ddcutil 1.x: no connector, so matched by the EDID
OLD = """Display 1
   I2C bus:             /dev/i2c-5
   Monitor:             DEL:DELL P2419H:CFV9N99
Display 2
   I2C bus:             /dev/i2c-7
   Monitor:             DEL:DELL P2419H:CFV9N88
"""


def mon(name, model="", serial="", disabled=False):
    return {"name": name, "make": "Dell Inc.", "model": model, "serial": serial, "disabled": disabled,
            "description": "Dell Inc. %s %s" % (model, serial)}


class Detect(Case):
    def test_ddcutil_3(self):
        got = db.parse_detect(DESK)
        self.assertEqual([(d["valid"], d["bus"], d.get("connector")) for d in got],
                         [(True, 4, "DP-1"), (True, 6, "HDMI-A-1"), (False, 13, "eDP-1")])
        self.assertEqual((got[0]["mfg"], got[0]["model"], got[0]["serial"]), ("DEL", "DELL U2720Q", "7XYZ123"))
        self.assertEqual(got[1]["serial"], "")

    def test_a_laptop_on_its_own(self):
        got = db.parse_detect(LAPTOP_ONLY)
        self.assertEqual(len(got), 1)
        self.assertFalse(got[0]["valid"])

    def test_ddcutil_1(self):
        got = db.parse_detect(OLD)
        self.assertEqual([(d["bus"], d.get("connector"), d["serial"]) for d in got],
                         [(5, None, "CFV9N99"), (7, None, "CFV9N88")])

    def test_nothing_found(self):
        self.assertEqual(db.parse_detect("No displays found.\n"), [])
        self.assertEqual(db.parse_detect(""), [])

    def test_a_model_with_a_colon(self):
        got = db.parse_detect("Display 1\n   I2C bus: /dev/i2c-3\n   Monitor: ACME:Pro: 27:SN1\n")
        self.assertEqual((got[0]["model"], got[0]["serial"]), ("Pro: 27", "SN1"))

    def test_brightness(self):
        self.assertEqual(db.parse_vcp("VCP 10 C 70 100\n"), (70, 100))
        self.assertEqual(db.parse_vcp("VCP 10 C 30 255"), (30, 255))
        self.assertIsNone(db.parse_vcp("VCP 10 ERR\n"))
        self.assertIsNone(db.parse_vcp("VCP 10 C 0 0\n"))
        self.assertIsNone(db.parse_vcp(""))


class Match(Case):
    def test_by_connector(self):
        found = [d for d in db.parse_detect(DESK) if d["valid"]]
        # (the names Hyprland gives, whatever the EDID says)
        got = db.match(found, [mon("HDMI-A-1", "something else"), mon("DP-1", "", "")])
        self.assertEqual({n: d["bus"] for n, d in got.items()}, {"DP-1": 4, "HDMI-A-1": 6})

    def test_by_model_and_serial(self):
        """Two of the same monitor (ddcutil 1.x: no connector): each by its serial, wherever it's plugged."""
        found = db.parse_detect(OLD)
        got = db.match(found, [mon("DP-2", "DELL P2419H", "CFV9N88"), mon("DP-3", "DELL P2419H", "CFV9N99")])
        self.assertEqual({n: d["bus"] for n, d in got.items()}, {"DP-2": 7, "DP-3": 5})

    def test_a_model_alone_only_when_theres_one(self):
        one = [{"valid": True, "bus": 3, "model": "LG ULTRAGEAR", "serial": ""}]
        self.assertEqual(list(db.match(one, [mon("DP-1", "lg ultragear")])), ["DP-1"])
        # Two outputs with that model, or two such monitors: no telling which is which
        self.assertEqual(db.match(one, [mon("DP-1", "LG ULTRAGEAR"), mon("DP-2", "LG ULTRAGEAR")]), {})
        two = one + [{"valid": True, "bus": 4, "model": "LG ULTRAGEAR", "serial": ""}]
        self.assertEqual(db.match(two, [mon("DP-1", "LG ULTRAGEAR")]), {})

    def test_a_wrong_serial_isnt_matched(self):
        found = db.parse_detect(OLD)[:1]
        self.assertEqual(db.match(found, [mon("DP-1", "DELL P2419H", "OTHER")]), {})

    def test_nothing_without_a_model(self):
        self.assertEqual(db.match([{"valid": True, "bus": 3, "model": "", "serial": ""}], [mon("DP-1")]), {})


class BuiltIn(Case):
    scratch = True

    def sys_link(self, device, target):
        d = self.h("sys", "class", "backlight", device)
        os.makedirs(d)
        os.symlink(target, os.path.join(d, "device"))
        os.environ["SLATE_SYS"] = self.h("sys")
        self.addCleanup(os.environ.pop, "SLATE_SYS", None)

    def test_from_sys(self):
        """intel_backlight's device is the connector: that output, whatever it's called."""
        self.sys_link("intel_backlight", "../../card0-eDP-1")
        self.assertEqual(db.built_in_output("intel_backlight", [mon("DP-1"), mon("eDP-1")]), "eDP-1")
        self.assertEqual(db.built_in_output("intel_backlight", [mon("DP-1")]), None)

    def test_by_name(self):
        """AMD's (and ACPI's) device is the graphics card: then the one laptop panel there is."""
        self.sys_link("amdgpu_bl1", "../../../0000:03:00.0")
        self.assertEqual(db.built_in_output("amdgpu_bl1", [mon("DP-1"), mon("eDP-2")]), "eDP-2")
        self.assertEqual(db.built_in_output("amdgpu_bl1", [mon("LVDS-1")]), "LVDS-1")
        self.assertEqual(db.built_in_output("amdgpu_bl1", [mon("DP-1"), mon("HDMI-A-1")]), None)
        self.assertEqual(db.built_in_output("amdgpu_bl1", [mon("eDP-1"), mon("eDP-2")]), None)


class Whole(Case):
    """The whole run, as Settings sees it."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.dev = self.h("dev")
        os.makedirs(self.dev)
        sysd = self.h("sys", "class", "backlight", "intel_backlight")
        os.makedirs(sysd)
        os.symlink("../../card0-eDP-1", os.path.join(sysd, "device"))
        self.s.env.update(SLATE_SYS=self.h("sys"), SLATE_DEV=self.dev)
        self.s.add("hyprctl", stdout=json.dumps([mon("eDP-1", "", ""), mon("DP-1", "DELL U2720Q", "7XYZ123"),
                                                 mon("HDMI-A-1", "LG ULTRAGEAR")]))

    def lines(self):
        code, out = run([sys.executable, SCRIPT], env=self.s.env, timeout=30)
        self.assertEqual(code, 0, out)
        return [json.loads(line) for line in out.splitlines()]

    def laptop(self, percent=52):
        self.s.add("brightnessctl", stdout="intel_backlight,backlight,%d,%d%%,1000\n" % (percent * 10, percent))

    def test_a_laptop_and_two_monitors(self):
        self.laptop()
        self.s.add("ddcutil", by_args={"detect": DESK, "--bus 4 getvcp": "VCP 10 C 70 100\n",
                                       "--bus 6 getvcp": ["", 1]})
        got = self.lines()
        self.assertEqual(got[0], {"display": "eDP-1", "kind": "backlight", "percent": 52})
        self.assertEqual(got[1:], [{"display": "DP-1", "kind": "ddc", "bus": 4, "max": 100, "percent": 70},
                                   {"display": "HDMI-A-1", "kind": "none", "why": "silent"},
                                   {"done": True, "ddcutil": "ok"}])
        # (only read: nothing set)
        self.assertFalse([c for c in self.s.calls("ddcutil") if "setvcp" in c])
        self.assertFalse([c for c in self.s.calls("brightnessctl") if "set" in c])

    def test_a_monitor_counting_to_255(self):
        self.s.add("brightnessctl", stdout="", code=1)
        self.s.add("ddcutil", by_args={"detect": DESK, "--bus 4 getvcp": "VCP 10 C 51 255\n", "getvcp": ["", 1]})
        got = self.lines()
        self.assertEqual(got[0], {"display": "eDP-1", "kind": "none", "why": "silent"})
        self.assertEqual(got[1]["percent"], 20)
        self.assertEqual(got[1]["max"], 255)

    def test_without_ddcutil(self):
        self.laptop()
        self.s.add("ddcutil", missing=True)
        got = self.lines()
        self.assertEqual(got[0]["kind"], "backlight")
        self.assertEqual([g.get("why") for g in got[1:3]], ["missing", "missing"])
        self.assertEqual(got[-1], {"done": True, "ddcutil": "missing"})

    def test_ddcutil_cant_reach_the_monitors(self):
        """No /dev/i2c-* this account may use (i2c-dev not loaded, or not in the i2c group):
        ddcutil finds nothing, and Settings says what's needed."""
        self.laptop()
        self.s.add("ddcutil", by_args={"detect": "No displays found.\n"})
        got = self.lines()
        self.assertEqual([g.get("why") for g in got[1:3]], ["access", "access"])
        self.assertEqual(got[-1]["ddcutil"], "access")
        # ...with one it may use, they just don't answer
        open(os.path.join(self.dev, "i2c-4"), "w").close()
        got = self.lines()
        self.assertEqual([g.get("why") for g in got[1:3]], ["silent", "silent"])
        os.chmod(os.path.join(self.dev, "i2c-4"), 0o400)
        if not os.access(os.path.join(self.dev, "i2c-4"), os.W_OK):      # (root may write anyway)
            self.assertEqual(self.lines()[-1]["ddcutil"], "access")

    def test_a_desktop(self):
        """No backlight: no built-in screen; every output is a monitor to ask."""
        self.s.add("brightnessctl", stdout="", code=1)
        self.s.add("hyprctl", stdout=json.dumps([mon("DP-1", "DELL U2720Q", "7XYZ123")]))
        self.s.add("ddcutil", by_args={"detect": DESK, "getvcp": "VCP 10 C 40 100\n"})
        self.assertEqual(self.lines(), [{"display": "DP-1", "kind": "ddc", "bus": 4, "max": 100, "percent": 40},
                                        {"done": True, "ddcutil": "ok"}])

    def test_without_hyprland(self):
        self.s.add("hyprctl", stdout="", code=1)
        self.s.add("brightnessctl", stdout="", code=1)
        self.s.add("ddcutil", missing=True)
        self.assertEqual(self.lines(), [{"done": True, "ddcutil": "missing"}])
