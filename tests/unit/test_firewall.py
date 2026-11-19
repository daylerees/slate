"""scripts/firewall.py: which firewall there is, whether it's on and which of Slate's allowances
are open, read without a password (Settings → Security → Firewall). A pretend / for each test
(SLATE_FIREWALL_ROOT) with ufw's files or none, and stand-in ufw, firewall-cmd and slate-init."""
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


class FirewallCase(Case):
    """A pretend / and stand-ins; no tests of its own."""
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
        # (slate-init, which knows how services are run here: a stand-in recording what it's asked)
        self.s.add("slate-init-stub", stdout="", code=1)
        self.init = os.path.join(self.s.dir, "slate-init-stub")

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
        code, out = run([SCRIPT, "status"], env=dict(self.s.env, SLATE_FIREWALL_ROOT=self.root, SLATE_TEST="1",
                                                      SLATE_FIREWALL_INIT=self.init))
        self.assertEqual(code, 0, out)
        return json.loads(out)


class Reading(FirewallCase):
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
        for code, on in ((0, True), (1, False), (2, None)):
            with self.subTest(code=code):
                self.s.add("slate-init-stub", stdout="", code=code)
                st = self.status()
                self.assertEqual((st["kind"], st["on"], st["canChange"]), ("nixos", on, False))
                self.assertEqual(self.s.calls("slate-init-stub")[-1], ["service-active", "firewall"])

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
        code, out = run([SCRIPT, "status"], env=dict(self.s.env, SLATE_FIREWALL_ROOT=self.root, SLATE_TEST="1",
                                                      SLATE_FIREWALL_INIT=self.init), timeout=20)
        self.assertEqual(code, 0, out)
        st = json.loads(out)
        self.assertEqual((st["kind"], st["on"]), ("firewalld", None))

    def test_the_allowances_open_only_what_they_need(self):
        """The table bin/slate-firewall goes by: a few fixed ports each, from the local network."""
        fw = load_firewall()
        self.assertEqual(set(fw.ALLOWANCES), {"kdeconnect", "samba", "ssh", "steam"})
        for name, a in fw.ALLOWANCES.items():
            for spec_, proto in a["ports"]:
                self.assertIn(proto, ("tcp", "udp"), name)
                n = len(fw.ports(spec_))
                self.assertTrue(0 < n <= 51, f"{name} opens {n} ports")
        self.assertEqual(fw.LOCAL, ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fe80::/10", "fc00::/7"])


def load_firewall():
    import importlib.util
    spec = importlib.util.spec_from_file_location("firewall", SCRIPT)
    fw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fw)
    return fw


class Changing(FirewallCase):
    """firewall.py set and allow: ufw through Slate's root helper (slate-system --root
    slate-firewall, a stand-in here that records what it's asked), firewalld through
    firewall-cmd and its service (slate-init) themselves."""

    def setUp(self):
        super().setUp()
        self.asked = os.path.join(self.h.dir, "asked")
        self.system = os.path.join(self.h.dir, "slate-system")
        with open(self.system, "w") as f:
            f.write(f'#!/bin/sh\necho "$*" >> {self.asked}\nexit ${{STUB_SYSTEM_EXIT:-0}}\n')
        os.chmod(self.system, 0o755)

    def act(self, *args, extra=None):
        env = dict(self.s.env, SLATE_FIREWALL_ROOT=self.root, SLATE_TEST="1", SLATE_FIREWALL_SYSTEM=self.system,
                   SLATE_FIREWALL_INIT=self.init, **(extra or {}))
        return run([SCRIPT, *args], env=env)

    def asked_for(self):
        try:
            with open(self.asked) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def test_ufw_through_the_root_helper(self):
        self.ufw(False)
        for args, want in ((["set", "on"], "--root slate-firewall on"), (["set", "off"], "--root slate-firewall off"),
                           (["allow", "ssh", "on"], "--root slate-firewall allow ssh"),
                           (["allow", "kdeconnect", "off"], "--root slate-firewall deny kdeconnect")):
            with self.subTest(args):
                code, out = self.act(*args)
                self.assertEqual(code, 0, out)
                self.assertEqual(self.asked_for()[-1], want)

    def test_says_kindly_when_it_doesnt_happen(self):
        self.ufw(False)
        code, out = self.act("set", "on", extra={"STUB_SYSTEM_EXIT": "126"})
        self.assertEqual(code, 1)
        self.assertIn("Slate couldn't turn the firewall on. Was the password prompt closed?", out)
        code, out = self.act("allow", "samba", "on", extra={"STUB_SYSTEM_EXIT": "1"})
        self.assertIn("Slate couldn't change what the firewall lets in", out)

    def test_only_its_own_words(self):
        """Nothing it's told reaches the helper unless it's one of its own words."""
        self.ufw(True)
        for args in (["set", "maybe"], ["set"], ["set", "on", "now"], ["allow", "telnet", "on"], ["allow", "ssh"],
                     ["allow", "ssh", "yes"], ["allow", "ssh; reboot", "on"], ["allow", "../ssh", "on"]):
            with self.subTest(args):
                code, out = self.act(*args)
                self.assertEqual(code, 1, out)
        self.assertEqual(self.asked_for(), [])

    def test_nothing_to_change(self):
        for distro in ("nixos", "cachyos"):
            with self.subTest(distro):
                self.distro(distro, "arch" if distro == "cachyos" else "")
                code, out = self.act("set", "on")
                self.assertEqual(code, 1)
                self.assertIn("There's no firewall here that Slate can change", out)
        self.assertEqual(self.asked_for(), [])

    def test_firewalld_by_its_own_commands(self):
        self.s.add("firewall-cmd", by_args={"--state": "running\n", "": ""})
        self.s.add("slate-init-stub", stdout="")
        code, out = self.act("set", "off")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("slate-init-stub")[-1], ["service-disable", "firewalld"])
        code, out = self.act("set", "on")
        self.assertEqual(self.s.calls("slate-init-stub")[-1], ["service-enable", "firewalld"])
        code, out = self.act("allow", "ssh", "on")
        self.assertEqual(code, 0, out)
        added = [c for c in self.s.calls("firewall-cmd") if any(a.startswith("--add-rich-rule=") for a in c)]
        self.assertEqual(len(added), 5, added)
        for c in added:
            self.assertEqual(c[0], "--permanent")
            self.assertIn('service name="ssh" accept', c[1])
        self.assertEqual(sorted(c[1].split('source address="')[1].split('"')[0] for c in added),
                         sorted(load_firewall().LOCAL))
        self.assertEqual(self.s.calls("firewall-cmd")[-1], ["--reload"])
        self.assertEqual(self.asked_for(), [], "firewalld went through Slate's root helper")

    def test_firewalld_reads_slates_rich_rules(self):
        rule = 'rule family="ipv4" source address="192.168.0.0/16" service name="samba" accept'
        self.s.add("firewall-cmd", by_args={"--state": "running\n", "--list-services": "dhcpv6-client\n", "--list-rich-rules": rule + "\n"})
        st = self.act("status")
        self.assertEqual({k for k, v in json.loads(st[1])["allow"].items() if v}, {"samba"})


HELPER = slate.path("shell", "bin", "slate-firewall")


class RootHelper(Case):
    """bin/slate-firewall, run as root (a stand-in `id` says so) from a scratch copy of
    /usr/local/libexec/slate, with a stand-in ufw recording what it's asked."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.target = os.path.join(self.h.dir, "libexec", "slate")
        os.makedirs(self.target)
        self.defaults = os.path.join(self.h.dir, "default-ufw")
        with open(self.defaults, "w") as f:
            f.write("IPV6=yes\n")
        src = slate.read("shell", "bin", "slate-firewall")
        self.assertIn("TARGET_DIR=/usr/local/libexec/slate", src)
        src = src.replace("/usr/local/libexec/slate", self.target).replace("/etc/default/ufw", self.defaults)
        self.helper = os.path.join(self.target, "slate-firewall")
        with open(self.helper, "w") as f:
            f.write(src)
        os.chmod(self.helper, 0o755)
        self.s.add("id", by_args={"-u": "0\n", "": "root\n"})
        self.s.add("ufw", stdout="")
        self.s.add("systemctl", stdout="")

    def go(self, *args, path=None):
        return run([path or self.helper, *args], env=self.s.env)

    def ufw_calls(self):
        return [" ".join(c) for c in self.s.calls("ufw")]

    def test_on_and_off(self):
        self.assertEqual(self.go("on")[0], 0)
        self.assertEqual(self.ufw_calls(), ["--force enable"])
        self.assertEqual(self.go("off")[0], 0)
        self.assertEqual(self.ufw_calls()[-1], "disable")

    def test_allow_opens_only_its_ports_from_the_local_network(self):
        self.assertEqual(self.go("allow", "ssh")[0], 0)
        self.assertEqual(self.ufw_calls(), [f"allow proto tcp from {net} to any port 22 comment slate-ssh"
                                            for net in load_firewall().LOCAL])

    def test_without_ipv6_only_ipv4_ranges(self):
        with open(self.defaults, "w") as f:
            f.write('IPV6="no"\n')
        self.go("allow", "ssh")
        self.assertEqual([c.split()[4] for c in self.ufw_calls()], ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])

    def test_deny_takes_its_rules_away(self):
        self.assertEqual(self.go("deny", "samba")[0], 0)
        calls = self.ufw_calls()
        self.assertEqual(len(calls), 2 * 5)
        self.assertTrue(all(c.startswith("--force delete allow proto ") for c in calls), calls)

    def test_refuses_anything_else(self):
        for args in (["allow", "telnet"], ["allow"], ["allow", "ssh", "extra"], ["allow", "22"],
                     ["allow", "ssh;reboot"], ["on", "now"], ["reset"], []):
            with self.subTest(args):
                code, out = self.go(*args)
                self.assertNotEqual(code, 0, out)
        self.assertEqual(self.ufw_calls(), [])

    def test_runs_only_from_the_root_owned_folder(self):
        code, out = self.go("on", path=HELPER)
        self.assertEqual(code, 1)
        self.assertIn("only runs from /usr/local/libexec/slate", out)
        self.assertEqual(self.ufw_calls(), [])

    def test_only_as_root(self):
        self.s.add("id", by_args={"-u": "1000\n", "": "me\n"})
        code, out = self.go("on")
        self.assertEqual(code, 1)
        self.assertEqual(self.ufw_calls(), [])

    def test_no_ufw(self):
        self.s.add("ufw", missing=True)
        self.assertEqual(self.go("on")[0], 2)

    def test_same_table_as_firewall_py(self):
        """The helper's allowances and ranges are firewall.py's, rule for rule."""
        code, out = run([HELPER, "--table"])
        self.assertEqual(code, 0, out)
        fw = load_firewall()
        lines = out.splitlines()
        self.assertEqual(lines[-1].split()[1:], fw.LOCAL)
        got = sorted(tuple(l.split()) for l in lines[:-1])
        want = sorted((name, proto, spec) for name, a in fw.ALLOWANCES.items() for spec, proto in a["ports"])
        self.assertEqual(got, want)
