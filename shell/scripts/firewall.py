#!/usr/bin/env python3
"""The firewall (Settings → Security → Firewall): which one this computer has, whether it's on,
and which of Slate's allowances are open, all read without a password.

    firewall.py set on|off              turn it on or off (asks for the password)
    firewall.py allow <name> on|off     open or close one of Slate's allowances: kdeconnect,
                                        samba, ssh or steam (asks for the password)
    firewall.py status      one line of JSON:
        {"kind": "ufw" | "firewalld" | "nixos" | "none",
         "on": true | false | null (can't tell),
         "allow": {"kdeconnect": bool, "samba": bool, "ssh": bool, "steam": bool},
         "install": the package to offer when there's none ("ufw", "firewalld" or ""),
         "canChange": whether Settings can switch it (NixOS's is set in its configuration)}

ufw keeps its state in files everyone can read (/etc/ufw/ufw.conf, user.rules, user6.rules);
firewalld answers anyone over D-Bus (firewall-cmd). Changing either needs an administrator:
for ufw, Slate's root helper bin/slate-firewall (by slate-system --root, your password); for
firewalld, firewall-cmd and systemctl themselves, which ask for the password (polkit). Nothing
here runs as root. Allowances are let in from the local network only (LOCAL): ufw's rules say
so, and firewalld's are rich rules for the allowance's service from each of those ranges.

SLATE_FIREWALL_ROOT puts / somewhere else, for the tests (with stand-in commands on PATH)."""
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.environ.get("SLATE_FIREWALL_ROOT") or "/"

# Slate's allowances: each opens only these ports (ufw: from the local network's own addresses,
# LOCAL) or firewalld's service of the same use. The one table both readers here and
# bin/slate-firewall go by (tests/unit/test_firewall.py holds the two to it)
ALLOWANCES = {
    "kdeconnect": {"ports": [("1714:1764", "tcp"), ("1714:1764", "udp")], "service": "kdeconnect"},
    "samba": {"ports": [("137,138", "udp"), ("139,445", "tcp")], "service": "samba"},
    "ssh": {"ports": [("22", "tcp")], "service": "ssh"},
    "steam": {"ports": [("27031:27036", "udp"), ("27036:27037", "tcp")], "service": "steam-streaming"},
}
# The local network: private IPv4 ranges, and IPv6's link-local and unique local ones
LOCAL = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fe80::/10", "fc00::/7"]


def path(*p):
    return os.path.join(ROOT, *p)


def run(cmd, timeout=5):
    """(exit status, what it printed), or (None, "") when it can't run."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return None, ""


def family():
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from slate_apps import family as fam
        return fam(path("etc", "os-release"))
    except Exception:
        return ""


def ports(spec):
    """The ports a ufw port field stands for: "22", "137,138", "1714:1764" (a set of numbers),
    or None for "any"."""
    if spec in ("any", ""):
        return None
    out = set()
    for part in spec.split(","):
        lo, _, hi = part.partition(":")
        try:
            a, b = int(lo), int(hi or lo)
        except ValueError:
            return set()
        if 0 < a <= b <= 65535:
            out.update(range(a, b + 1))
    return out


def ufw_rules():
    """ufw's own allow rules, coming in: [(protocol, ports or None for any)], from the
    "### tuple ###" lines it writes above each rule in user.rules and user6.rules."""
    out = []
    for name in ("user.rules", "user6.rules"):
        try:
            with open(path("etc", "ufw", name), encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            if not line.startswith("### tuple ###"):
                continue
            # action protocol dport dst sport src [app names…] direction [comment=…]
            f = line.split()[3:]
            if len(f) < 6 or f[0] != "allow":
                continue
            if "out" in f[6:] and "in" not in f[6:]:
                continue
            out.append((f[1], ports(f[2])))
    return out


def ufw_allows(rules, wanted):
    """Every (ports, protocol) wanted is let in by some rule (any protocol and any port count)."""
    for spec, proto in wanted:
        need = ports(spec)
        if not any((p in (proto, "any")) and (got is None or need <= got) for p, got in rules):
            return False
    return True


def ufw_status():
    enabled = None
    try:
        with open(path("etc", "ufw", "ufw.conf"), encoding="utf-8", errors="replace") as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k == "ENABLED":
                    enabled = v.strip().strip("\"'").lower() == "yes"
    except OSError:
        pass
    rules = ufw_rules()
    return {"kind": "ufw", "on": enabled,
            "allow": {k: ufw_allows(rules, a["ports"]) for k, a in ALLOWANCES.items()},
            "install": "", "canChange": True}


def firewalld_status():
    code, out = run(["firewall-cmd", "--state"])
    on = None if code is None else out.strip() == "running"
    services = set()
    if on:
        code, out = run(["firewall-cmd", "--list-services"])
        if code == 0:
            services = set(out.split())
        # (Slate's own, from the local network: rich rules accepting the service)
        code, out = run(["firewall-cmd", "--list-rich-rules"])
        if code == 0:
            for line in out.splitlines():
                m = re.search(r'service name="([^"]+)"\s+accept', line)
                if m:
                    services.add(m.group(1))
    return {"kind": "firewalld", "on": on,
            "allow": {k: a["service"] in services for k, a in ALLOWANCES.items()},
            "install": "", "canChange": True}


def nixos_status():
    # (networking.firewall: its systemd unit is "firewall")
    code, out = run(["systemctl", "is-active", "firewall"])
    on = None if code is None else out.strip() == "active"
    return {"kind": "nixos", "on": on, "allow": {k: False for k in ALLOWANCES},
            "install": "", "canChange": False}


def status():
    fam = family()
    if fam == "nixos" or os.path.exists(path("etc", "NIXOS")):
        return nixos_status()
    has_ufw = bool(shutil.which("ufw")) or os.path.exists(path("etc", "ufw", "ufw.conf"))
    has_firewalld = bool(shutil.which("firewall-cmd"))
    if has_ufw and has_firewalld:
        # Both installed: the one that's on; otherwise the distro's usual one
        fd = firewalld_status()
        if fd["on"]:
            return fd
        uf = ufw_status()
        if uf["on"]:
            return uf
        return fd if fam in ("fedora", "opensuse") else uf
    if has_firewalld:
        return firewalld_status()
    if has_ufw:
        return ufw_status()
    # None: the distro's usual one to offer, where Slate can install packages for you
    offer = "firewalld" if fam in ("fedora", "opensuse") else "ufw" if fam in ("arch", "artix", "debian") else ""
    return {"kind": "none", "on": False, "allow": {k: False for k in ALLOWANCES},
            "install": offer, "canChange": False}


# ---- Changing it ----------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
SLATE_SYSTEM = os.path.join(HERE, "..", "bin", "slate-system")
if os.environ.get("SLATE_TEST") and os.environ.get("SLATE_FIREWALL_SYSTEM"):
    SLATE_SYSTEM = os.environ["SLATE_FIREWALL_SYSTEM"]       # (the tests' stand-in, and only theirs)


def say(problem):
    """Why it didn't happen, in Slate's words, for Settings to show; exit status 1."""
    print(problem, file=sys.stderr, flush=True)
    return 1


def rich_rules(name):
    """firewalld's rich rules for an allowance: its service, from each local range."""
    service = ALLOWANCES[name]["service"]
    return [f'rule family="{"ipv6" if ":" in net else "ipv4"}" source address="{net}" service name="{service}" accept'
            for net in LOCAL]


def change(kind, args):
    """Do it: (exit status, what was run)."""
    if kind == "ufw":
        code, _ = run([SLATE_SYSTEM, "--root", "slate-firewall"] + args, timeout=300)
        return code
    # firewalld: the password is asked for by firewall-cmd and systemctl themselves
    if args[0] in ("on", "off"):
        verb = "enable" if args[0] == "on" else "disable"
        code, _ = run(["systemctl", verb, "--now", "firewalld"], timeout=300)
        return code
    flag = "--add-rich-rule" if args[0] == "allow" else "--remove-rich-rule"
    for rule in rich_rules(args[1]):
        code, _ = run(["firewall-cmd", "--permanent", f"{flag}={rule}"], timeout=300)
        # (removing one that isn't there is fine)
        if code != 0 and args[0] == "allow":
            return code
    code, _ = run(["firewall-cmd", "--reload"], timeout=120)
    return code


def main(argv):
    if argv[1:2] == ["status"]:
        print(json.dumps(status()), flush=True)
        return 0
    if argv[1:2] in (["set"], ["allow"]):
        if argv[1] == "set" and (len(argv) != 3 or argv[2] not in ("on", "off")):
            return say("firewall.py set takes on or off")
        if argv[1] == "allow" and (len(argv) != 4 or argv[2] not in ALLOWANCES or argv[3] not in ("on", "off")):
            return say("firewall.py allow takes " + ", ".join(ALLOWANCES) + ", then on or off")
        st = status()
        if not st["canChange"]:
            return say("There's no firewall here that Slate can change")
        args = [argv[2]] if argv[1] == "set" else ["allow" if argv[3] == "on" else "deny", argv[2]]
        code = change(st["kind"], args)
        if code != 0:
            what = ("turn the firewall " + argv[2]) if argv[1] == "set" else "change what the firewall lets in"
            return say(f"Slate couldn't {what}" + (". Was the password prompt closed?" if code in (126, 127) else ""))
        return 0
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
