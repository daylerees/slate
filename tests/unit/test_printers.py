"""scripts/printers.py: printers, printers to add and scanners for Settings → Printers &
Scanners, from CUPS's and SANE's own commands (stubbed with fixture output)."""
import importlib.util
import json

import slate
from slate import Case, run
from stubs import Stubs, fixture_text

SCRIPT = slate.path("shell", "scripts", "printers.py")
SCAN_APPS = ["simple-scan", "skanpage", "skanlite", "naps2", "xsane"]


def load_module():
    spec = importlib.util.spec_from_file_location("slate_printers", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def printer(name, status, info, uri, jobs=0, accepting=True, default=False):
    # In the order the script writes the keys, so the JSON can be compared as text too
    return {"name": name, "status": status, "info": info, "uri": uri, "jobs": jobs,
            "accepting": accepting, "default": default}


class PrintersCase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        # The host's own printer tool and scan apps mustn't change the answer
        self.s.add("system-config-printer", missing=True)
        for app in SCAN_APPS:
            self.s.add(app, missing=True)

    def cups(self, running=True, default="Office_Laser", printers=True):
        """A CUPS with the fixture printers (or none), answering through lpstat."""
        f = lambda n: fixture_text("printers", n) if printers else ""
        dest = (f"system default destination: {default}\n" if default
                else "no system default destination\n")
        self.s.add("lpstat", by_args={
            "-l -p": f("lpstat-p.txt"), "-r": "scheduler is running\n" if running else "scheduler is not running\n",
            "-d": dest, "-v": f("lpstat-v.txt"), "-a": f("lpstat-a.txt"), "-o": f("lpstat-o.txt")})

    def script(self, *args):
        code, out = run(["python3", SCRIPT, *args], env=self.s.env)
        self.assertEqual(code, 0, out)
        return out

    def json(self, *args, expected):
        """Runs the script and checks its JSON, as data and as the exact text it prints."""
        out = self.script(*args)
        self.assertEqual(json.loads(out), expected)
        self.assertEqual(out, json.dumps(expected) + "\n")


class List(PrintersCase):
    FOUR = [
        printer("Brother_HL-L2350DW_series", "idle", "Brother HL-L2350DW series",
                "usb://Brother/HL-L2350DW%20series?serial=E00000A0B1C2"),
        printer("EPSON.ET-2850", "printing", "Kitchen Inkjet", "ipp://192.0.2.31/ipp/print", jobs=2),
        printer("Office_Laser", "idle", "Office Laser (HP LaserJet Pro M404dn)",
                "ipps://192.0.2.20:631/ipp/print", default=True),
        printer("Old-Printer", "stopped", "", "socket://192.0.2.99:9100", jobs=1, accepting=False),
    ]

    def test_several_printers(self):
        """Status, description, address, waiting jobs, accepting and the default, per printer."""
        self.cups()
        self.json("list", expected={"service": "on", "printers": self.FOUR, "configTool": ""})

    def test_no_default(self):
        self.cups(default=None)
        expected = [dict(p, default=False) for p in self.FOUR]
        self.json("list", expected={"service": "on", "printers": expected, "configTool": ""})

    def test_default_not_a_printer_here(self):
        """A default that names no printer in the list marks none of them."""
        self.cups(default="Gone_Away")
        self.assertFalse(any(p["default"] for p in json.loads(self.script("list"))["printers"]))

    def test_none_at_all(self):
        self.cups(printers=False, default=None)
        self.json("list", expected={"service": "on", "printers": [], "configTool": ""})

    def test_service_off(self):
        """CUPS installed but not running: no printers asked for."""
        self.cups(running=False)
        self.json("list", expected={"service": "off", "printers": [], "configTool": ""})
        self.assertEqual(self.s.calls("lpstat"), [["-r"]])

    def test_service_on_from_systemd(self):
        """systemd says the socket is active: CUPS isn't asked whether it's running."""
        self.cups(running=False)
        self.s.add("systemctl", stdout="inactive\nactive\n")
        out = json.loads(self.script("list"))
        self.assertEqual(out["service"], "on")
        self.assertEqual(len(out["printers"]), 4)
        self.assertEqual(self.s.calls("systemctl"), [["is-active", "cups.service", "cups.socket"]])
        self.assertNotIn(["-r"], self.s.calls("lpstat"))

    def test_service_inactive_in_systemd(self):
        self.cups(running=False)
        self.s.add("systemctl", stdout="inactive\ninactive\n", code=3)
        self.assertEqual(json.loads(self.script("list"))["service"], "off")

    def test_cups_missing(self):
        self.s.add("lpstat", missing=True)
        self.json("list", expected={"service": "missing", "printers": [], "configTool": ""})

    def test_config_tool(self):
        self.cups(printers=False)
        self.s.add("system-config-printer")
        self.assertEqual(json.loads(self.script("list"))["configTool"], "system-config-printer")


class Find(PrintersCase):
    def test_printers_to_add(self):
        """Network and USB printers, named by make and model (or their DNS-SD name), without
        ones already added, the same printer twice, or bare backends."""
        self.cups()
        self.s.add("lpinfo", stdout=fixture_text("printers", "lpinfo.txt"))
        self.json("find", expected=[
            {"uri": "ipp://192.0.2.40/ipp/print", "name": "Canon TS5300 series", "via": "network"},
            {"uri": "dnssd://Brother%20MFC-L2710DW%20series._ipp._tcp.local/?uuid=e3248000-80ce-11db-8000-000000000001",
             "name": "Brother MFC-L2710DW series", "via": "network"},
            {"uri": "usb://Kyocera/ECOSYS%20P2040dw?serial=VCF0000001", "name": "Kyocera ECOSYS P2040dw", "via": "USB"},
        ])
        self.assertEqual(self.s.calls("lpinfo"),
                         [["-l", "--include-schemes", "dnssd,ipp,ipps,usb", "--timeout", "8", "-v"]])

    def test_nothing_added_yet(self):
        """With no printers added, the one already on the network is offered too."""
        self.cups(printers=False)
        self.s.add("lpinfo", stdout=fixture_text("printers", "lpinfo.txt"))
        names = [p["name"] for p in json.loads(self.script("find"))]
        self.assertEqual(names, ["HP LaserJet Pro M404dn", "Canon TS5300 series",
                                 "Brother MFC-L2710DW series", "Kyocera ECOSYS P2040dw"])

    def test_nothing_found(self):
        self.cups()
        self.s.add("lpinfo", stdout="")
        self.json("find", expected=[])

    def test_service_off(self):
        """Nothing to search with: an empty list, and lpinfo isn't run."""
        self.cups(running=False)
        self.s.add("lpinfo", stdout=fixture_text("printers", "lpinfo.txt"))
        self.json("find", expected=[])
        self.assertEqual(self.s.calls("lpinfo"), [])


class Scanners(PrintersCase):
    def test_scanners(self):
        self.s.add("scanimage", stdout=fixture_text("printers", "scanimage-L.txt"))
        self.s.add("simple-scan")
        self.json("scanners", expected={"sane": True, "scanners": [
            {"device": "airscan:e0:Canon TS5300 series", "name": "eSCL Canon TS5300 series ip=192.0.2.40"},
            {"device": "hpaio:/net/officejet_pro_8020?ip=192.0.2.31&queue=false",
             "name": "Hewlett-Packard OfficeJet_Pro_8020 all-in-one"},
            {"device": "v4l:/dev/video0", "name": "Noname USB2.0 HD UVC WebCam virtual device"},
        ], "app": {"command": "simple-scan", "name": "Document Scanner"}})
        self.assertEqual(self.s.calls("scanimage"), [["-L"]])

    def test_none_found(self):
        self.s.add("scanimage", stdout=fixture_text("printers", "scanimage-none.txt"))
        self.json("scanners", expected={"sane": True, "scanners": [], "app": None})

    def test_sane_missing(self):
        self.s.add("scanimage", missing=True)
        self.s.add("xsane")
        self.json("scanners", expected={"sane": False, "scanners": [],
                                        "app": {"command": "xsane", "name": "XSane"}})

    def test_best_app_first(self):
        """Of several scan apps, the one first in the list."""
        self.s.add("scanimage", stdout="")
        for app in ("naps2", "skanlite", "skanpage"):
            self.s.add(app)
        self.assertEqual(json.loads(self.script("scanners"))["app"], {"command": "skanpage", "name": "Skanpage"})


class Actions(PrintersCase):
    """The actions only run CUPS's commands (stubbed here): what they'd run, and what they say."""

    def test_default(self):
        self.s.add("lpoptions")
        self.assertEqual(self.script("default", "Office_Laser"), "ok\n")
        self.assertEqual(self.s.calls("lpoptions"), [["-d", "Office_Laser"]])

    def test_add_first_printer_becomes_default(self):
        self.cups(printers=False)
        self.s.add("pkexec")
        self.s.add("lpoptions")
        self.assertEqual(self.script("add", "ipp://192.0.2.40/ipp/print", "Canon TS5300 series"), "ok\n")
        self.assertEqual(self.s.calls("pkexec"), [["lpadmin", "-p", "Canon_TS5300_series", "-D", "Canon TS5300 series",
                                                   "-E", "-v", "ipp://192.0.2.40/ipp/print", "-m", "everywhere"]])
        self.assertEqual(self.s.calls("lpoptions"), [["-d", "Canon_TS5300_series"]])

    def test_add_another_keeps_default(self):
        self.cups()
        self.s.add("pkexec")
        self.s.add("lpoptions")
        self.assertEqual(self.script("add", "ipp://192.0.2.40/ipp/print", "Canon"), "ok\n")
        self.assertEqual(self.s.calls("lpoptions"), [])

    def test_add_cancelled(self):
        """The password prompt dismissed (pkexec exits 126)."""
        self.cups(printers=False)
        self.s.add("pkexec", code=126)
        self.s.add("lpoptions")
        self.assertEqual(self.script("add", "ipp://192.0.2.40/ipp/print", "Canon"), "error cancelled\n")
        self.assertEqual(self.s.calls("lpoptions"), [])

    def test_error_message(self):
        self.s.add("cancel", stdout="cancel: Unknown destination \"Gone\".\n", code=1)
        self.assertEqual(self.script("cancel", "Gone"), 'error cancel: Unknown destination "Gone".\n')

    def test_unknown_command(self):
        code, out = run(["python3", SCRIPT, "frobnicate"], env=self.s.env)
        self.assertEqual(code, 1)
        self.assertIn("Usage:", out)


class SafeName(Case):
    @classmethod
    def setUpClass(cls):
        cls.safe_name = staticmethod(load_module().safe_name)

    def test_names(self):
        for name, expected in [
            ("Office_Laser", "Office_Laser"),
            ("Canon TS5300 series", "Canon_TS5300_series"),
            ("HP LaserJet Pro (M404dn)", "HP_LaserJet_Pro_M404dn"),
            ("Brother HL-L2350DW series", "Brother_HL-L2350DW_series"),
            ("Büro Drucker", "B_ro_Drucker"),
            ("Upstairs/Office #2", "Upstairs_Office_2"),
            ("  printer @ 192.0.2.20  ", "printer_192_0_2_20"),
            ("__x__", "x"),
            ("--", "--"),
        ]:
            with self.subTest(name):
                self.assertEqual(self.safe_name(name), expected)

    def test_nothing_usable(self):
        """A name with nothing CUPS accepts still gets a name."""
        for name in ("", "   ", "!!!", "東京"):
            with self.subTest(repr(name)):
                self.assertEqual(self.safe_name(name), "Printer")

    def test_at_most_127(self):
        self.assertEqual(self.safe_name("a" * 300), "a" * 127)
        self.assertEqual(len(self.safe_name("x " * 200)), 127)
