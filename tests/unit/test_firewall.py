"""scripts/firewall.py: which firewall there is, whether it's on and which of Slate's allowances
are open, read without a password (Settings → Security → Firewall). A pretend / for each test
(SLATE_FIREWALL_ROOT) with ufw's files or none, and stand-in ufw, firewall-cmd and systemctl."""
import json
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "firewall.py")

# ufw's own lines, as `ufw allow …` writes them (a tuple line above each rule)
UFW_SSH_LOCAL = """
### tuple ### allow tcp 22 0.0.0.0/0 any 192.168.0.0/16 in comment=736c6174652d737368
-A ufw-user-input -p tcp --dport 22 -s 192.168.0.0/16 -j ACCEPT
"""
UFW_KDE_BOTH = """
### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow udp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 in
"""
UFW_SAMBA_HALF = """
### tuple ### allow tcp 139,445 0.0.0.0/0 any 0.0.0.0/0 in
"""
UFW_ANY_PROTOCOL_RANGE = """
### tuple ### allow any 27000:27100 0.0.0.0/0 any 0.0.0.0/0 in
"""
UFW_DENY_AND_OUT = """
### tuple ### deny tcp 22 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow tcp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 out
### tuple ### allow udp 1714:1764 0.0.0.0/0 any 0.0.0.0/0 out
"""


class Firewall(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.root = os.path.join(self.h.dir, "root")
        os.makedirs(os.path.join(self.root, "etc"))
        self.distro("cachyos", "arch")
        # (none of the computer's own: each test adds what it has)
        for name in ("ufw", "firewall-cmd"):
            self.s.add(name, missing=True)
        self.s.add("systemctl", stdout="inactive\n", code=3)

    def distro(self, id_, like=""):
        with open(os.path.join(self.root, "etc", "os-release"), "w") as f:
            f.write(f"ID={id_}\n" + (f"ID_LIKE={like}\n" if like else ""))

    def ufw(self, enabled, rules="", rules6=""):
        d = os.path.join(self.root, "etc", "ufw")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "ufw.conf"), "w") as f:
            f.write(f"# ufw.conf\n\nENABLED={'yes' if enabled else 'no'}\nLOGLEVEL=low\n")
        with open(os.path.join(d, "user.rules"), "w") as f:
            f.write("*filter\n### RULES ###\n" + rules + "\n### END RULES ###\nCOMMIT\n")
        with open(os.path.join(d, "user6.rules"), "w") as f:
            f.write("*filter\n### RULES ###\n" + rules6 + "\n### END RULES ###\nCOMMIT\n")
        self.s.add("ufw", stdout="")

    def status(self):
        code, out = run([SCRIPT, "status"], env=dict(self.s.env, SLATE_FIREWALL_ROOT=self.root))
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def test_ufw_on_and_off(self):
        self.ufw(True)
        st = self.status()
        self.assertEqual((st["kind"], st["on"], st["canChange"]), ("ufw", True, True))
        self.assertEqual(st["allow"], {"kdeconnect": False, "samba": False, "ssh": False, "steam": False})
        self.ufw(False)
        self.assertFalse(self.status()["on"])

    def test_ufw_reads_without_running_anything_as_root(self):
        """Read from ufw's files: `ufw status` needs root, so it's never run."""
        self.ufw(True, UFW_SSH_LOCAL)
        self.status()
        self.assertEqual(self.s.calls("ufw"), [])

    def test_ufw_allowances(self):
        cases = [
            (UFW_SSH_LOCAL, "", {"ssh"}),
            (UFW_KDE_BOTH, "", {"kdeconnect"}),
            ("", UFW_KDE_BOTH, {"kdeconnect"}),                 # (IPv6's rules count too)
            (UFW_SAMBA_HALF, "", set()),                        # (the TCP half isn't enough)
            (UFW_ANY_PROTOCOL_RANGE, "", {"steam"}),            # (any protocol, a wider range)
            (UFW_DENY_AND_OUT, "", set()),                      # (denied, or going out only)
        ]
        for rules, rules6, want in cases:
            with self.subTest(rules=rules.strip()[:60], rules6=rules6.strip()[:20]):
                self.ufw(True, rules, rules6)
                st = self.status()
                self.assertEqual({k for k, v in st["allow"].items() if v}, want)

    def test_firewalld(self):
        self.s.add("firewall-cmd", by_args={"--state": "running\n", "--list-services": "ssh dhcpv6-client kdeconnect\n"})
        st = self.status()
        self.assertEqual((st["kind"], st["on"], st["canChange"]), ("firewalld", True, True))
        self.assertEqual({k for k, v in st["allow"].items() if v}, {"ssh", "kdeconnect"})
        self.s.add("firewall-cmd", stdout="not running\n", code=252)
        st = self.status()
        self.assertEqual((st["kind"], st["on"]), ("firewalld", False))
        self.assertFalse(any(st["allow"].values()))

    def test_both_installed_the_one_thats_on(self):
        self.ufw(True)
        self.s.add("firewall-cmd", stdout="not running\n", code=252)
        self.assertEqual(self.status()["kind"], "ufw")
        self.ufw(False)
        self.s.add("firewall-cmd", by_args={"--state": "running\n", "": ""})
        self.assertEqual(self.status()["kind"], "firewalld")

    def test_both_installed_both_off_the_distros_usual_one(self):
        for distro, like, want in (("fedora", "", "firewalld"), ("ubuntu", "debian", "ufw"), ("cachyos", "arch", "ufw")):
            with self.subTest(distro):
                self.distro(distro, like)
                self.ufw(False)
                self.s.add("firewall-cmd", stdout="not running\n", code=252)
                self.assertEqual(self.status()["kind"], want)

    def test_nixos_is_read_only(self):
        self.distro("nixos")
        self.s.add("systemctl", stdout="active\n")
        st = self.status()
        self.assertEqual((st["kind"], st["on"], st["canChange"]), ("nixos", True, False))
        self.assertEqual(self.s.calls("systemctl")[-1], ["is-active", "firewall"])

    def test_none_offers_the_distros_usual_one(self):
        for distro, like, offer in (("cachyos", "arch", "ufw"), ("debian", "", "ufw"), ("ubuntu", "debian", "ufw"),
                                    ("fedora", "", "firewalld"), ("opensuse-tumbleweed", "suse opensuse", "firewalld"),
                                    ("gentoo", "", ""), ("void", "", "")):
            with self.subTest(distro):
                self.distro(distro, like)
                st = self.status()
                self.assertEqual((st["kind"], st["on"], st["install"], st["canChange"]), ("none", False, offer, False))

    def test_a_firewall_that_cant_be_asked(self):
        """firewall-cmd there but not answering (D-Bus down): "can't tell", not "off"."""
        stub = os.path.join(self.s.dir, "firewall-cmd")
        with open(stub, "w") as f:
            f.write("#!/bin/sh\nsleep 30\n")
        os.chmod(stub, 0o755)
        code, out = run([SCRIPT, "status"], env=dict(self.s.env, SLATE_FIREWALL_ROOT=self.root), timeout=20)
        self.assertEqual(code, 0, out)
        st = json.loads(out)
        self.assertEqual((st["kind"], st["on"]), ("firewalld", None))

    def test_the_allowances_open_only_what_they_need(self):
        """The table bin/slate-firewall goes by: a few fixed ports each, from the local network."""
        import importlib.util
        spec = importlib.util.spec_from_file_location("firewall", SCRIPT)
        fw = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(fw)
        self.assertEqual(set(fw.ALLOWANCES), {"kdeconnect", "samba", "ssh", "steam"})
        for name, a in fw.ALLOWANCES.items():
            for spec_, proto in a["ports"]:
                self.assertIn(proto, ("tcp", "udp"), name)
                n = len(fw.ports(spec_))
                self.assertTrue(0 < n <= 51, f"{name} opens {n} ports")
        self.assertEqual(fw.LOCAL, ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fe80::/10", "fc00::/7"])
