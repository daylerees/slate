#!/usr/bin/env python3
"""Printers and scanners for Settings → Printers & Scanners.

Usage:
  printers.py list             the printing service and its printers, as JSON
  printers.py find             printers that could be added (network, USB), as JSON
  printers.py scanners         scanners (SANE) and an app to scan with, as JSON
  printers.py default <name>   make a printer your default (yours only: lpoptions)
  printers.py test <name>      print CUPS's test page
  printers.py cancel <name>    cancel your waiting jobs on a printer
  printers.py add <uri> <name> add a printer that needs no driver (IPP Everywhere); asks
                               for your password
  printers.py remove <name>    remove a printer; asks for your password
  printers.py service-on       start the printing service (CUPS) and keep it on; asks for
                               your password

Uses CUPS's own commands (lpstat, lpinfo, lpadmin, lp, cancel, lpoptions) and SANE's
scanimage, which every distro packages the same way; anything missing is reported rather
than assumed (the page then says what to install). Actions print one line: "ok" or
"error <message>".
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse

# CUPS's messages are parsed: keep them in English
ENV = dict(os.environ, LANG="C", LC_ALL="C")
# Apps that scan, best first (whichever is installed opens from the page)
SCAN_APPS = [("simple-scan", "Document Scanner"), ("skanpage", "Skanpage"), ("skanlite", "Skanlite"),
             ("naps2", "NAPS2"), ("xsane", "XSane")]
# The printer tool for printers that need a driver of their own, if installed; else CUPS's
# web page
CONFIG_TOOLS = ["system-config-printer"]
# CUPS's test page (the same path on every distro that ships it)
TEST_PAGES = ["/usr/share/cups/data/testprint", "/usr/share/cups/data/testprint.ps"]


def run(cmd, timeout=15):
    """A command's output ("" if it isn't there or failed)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def act(cmd, timeout=60):
    """Run an action and print "ok" or "error <message>"."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV)
    except FileNotFoundError:
        print("error %s isn't installed" % cmd[0])
        return
    except subprocess.SubprocessError:
        print("error it took too long")
        return
    if r.returncode == 0:
        print("ok")
    elif cmd[0] == "pkexec" and r.returncode in (126, 127):
        print("error cancelled")              # the password prompt was dismissed
    else:
        msg = (r.stderr or r.stdout).strip().splitlines()
        print("error " + (msg[-1] if msg else "it didn't work"))


def service_state():
    """"missing" (CUPS isn't installed), "off" (installed, not running) or "on"."""
    if not shutil.which("lpstat"):
        return "missing"
    if shutil.which("systemctl"):
        out = run(["systemctl", "is-active", "cups.service", "cups.socket"]).split()
        if "active" in out:
            return "on"
    # No systemd answer: ask CUPS itself
    r = subprocess.run(["lpstat", "-r"], capture_output=True, text=True, env=ENV)
    return "on" if "is running" in r.stdout else "off"


def list_printers():
    state = service_state()
    printers = []
    if state == "on":
        default = ""
        m = re.search(r"system default destination: (\S+)", run(["lpstat", "-d"]))
        if m:
            default = m.group(1)
        uris = dict(re.findall(r"^device for (\S+): (\S+)", run(["lpstat", "-v"]), re.M))
        accepting = set(re.findall(r"^(\S+) accepting requests", run(["lpstat", "-a"]), re.M))
        jobs = {}
        for line in run(["lpstat", "-o"]).splitlines():
            m = re.match(r"(\S+)-\d+\s", line)
            if m:
                jobs[m.group(1)] = jobs.get(m.group(1), 0) + 1
        current = None
        for line in run(["lpstat", "-l", "-p"]).splitlines():
            m = re.match(r"printer (\S+) (?:is (idle)|now (printing)|(disabled))", line)
            if m:
                name = m.group(1)
                status = m.group(2) or m.group(3) or "stopped"
                current = {"name": name, "status": status, "info": "", "uri": uris.get(name, ""),
                           "jobs": jobs.get(name, 0), "accepting": name in accepting,
                           "default": name == default}
                printers.append(current)
            elif current is not None:
                d = re.match(r"\s+Description: (.*)", line)
                if d:
                    current["info"] = d.group(1).strip()
    tool = next((t for t in CONFIG_TOOLS if shutil.which(t)), "")
    print(json.dumps({"service": state, "printers": printers, "configTool": tool}))


def nice_name(uri, info):
    """A printer's name from what lpinfo says about it (its make and model, or its address)."""
    if info and info.lower() not in ("unknown", ""):
        return info
    if uri.startswith("dnssd://"):
        return urllib.parse.unquote(uri[8:].split("._", 1)[0])
    return uri


def find_printers():
    """Printers that can be added with no driver: network ones that speak IPP Everywhere
    (found by CUPS over DNS-SD) and USB ones that do (IPP over USB). Ones already added
    are left out."""
    if service_state() != "on":
        print(json.dumps([]))
        return
    added = set(re.findall(r"^device for \S+: (\S+)", run(["lpstat", "-v"]), re.M))
    found, seen = [], set()
    out = run(["lpinfo", "-l", "--include-schemes", "dnssd,ipp,ipps,usb", "--timeout", "8", "-v"], timeout=30)
    block = {}
    for line in out.splitlines() + ["Device:"]:
        m = re.match(r"Device: uri = (\S+)", line)
        if m or line == "Device:":
            if block.get("uri") and "://" in block["uri"] and block["uri"] not in added:
                uri = block["uri"]
                name = nice_name(uri, block.get("make-and-model") or block.get("info", ""))
                if name not in seen:
                    seen.add(name)
                    found.append({"uri": uri, "name": name,
                                  "via": "USB" if uri.startswith("usb:") else "network"})
            block = {"uri": m.group(1)} if m else {}
            continue
        kv = re.match(r"\s+(\S+) = (.*)", line)
        if kv:
            block[kv.group(1)] = kv.group(2).strip()
    print(json.dumps(found))


def scanners():
    app = next(({"command": c, "name": n} for c, n in SCAN_APPS if shutil.which(c)), None)
    if not shutil.which("scanimage"):
        print(json.dumps({"sane": False, "scanners": [], "app": app}))
        return
    found = []
    for line in run(["scanimage", "-L"], timeout=30).splitlines():
        m = re.match(r"device `([^']+)' is a (.*)", line)
        if m:
            found.append({"device": m.group(1), "name": m.group(2).strip()})
    print(json.dumps({"sane": True, "scanners": found, "app": app}))


def safe_name(name):
    """A queue name CUPS accepts: letters, digits, "-" and "_", at most 127 of them."""
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_")[:127] or "Printer"


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == "list":
        list_printers()
    elif cmd == "find":
        find_printers()
    elif cmd == "scanners":
        scanners()
    elif cmd == "default" and len(a) == 2:
        act(["lpoptions", "-d", a[1]])
    elif cmd == "test" and len(a) == 2:
        page = next((p for p in TEST_PAGES if os.path.exists(p)), None)
        if not page:
            print("error CUPS's test page isn't installed")
        else:
            act(["lp", "-d", a[1], "-t", "Test page", page])
    elif cmd == "cancel" and len(a) == 2:
        act(["cancel", "-a", a[1]])
    elif cmd == "add" and len(a) == 3:
        act(["pkexec", "lpadmin", "-p", safe_name(a[2]), "-D", a[2], "-E", "-v", a[1], "-m", "everywhere"], timeout=120)
    elif cmd == "remove" and len(a) == 2:
        act(["pkexec", "lpadmin", "-x", a[1]], timeout=120)
    elif cmd == "service-on":
        act(["pkexec", "systemctl", "enable", "--now", "cups.socket", "cups.service"], timeout=120)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
