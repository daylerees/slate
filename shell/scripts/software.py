#!/usr/bin/env python3
"""Slate Software's engine: apps from Flathub (Flatpak), and the system's own updates.

Usage:
  software.py status              whether Flatpak and Flathub are set up, as JSON
  software.py catalogue           every app in the Flathub catalogue on this computer, as JSON
                                  ({id, name, summary, icon, categories, keywords, developer})
  software.py app <id>            one app's details, as JSON (description, screenshots, links,
                                  whether it's installed, its version)
  software.py discover            Flathub's popular, new and trending apps (their ids), as JSON;
                                  fetched at most every 6 hours, and the last answer kept for when
                                  there's no connection
  software.py installed           the apps installed with Flatpak, as JSON
  software.py updates             app updates (Flatpak) and the system's own updates, as JSON
  software.py install <id>        install an app from Flathub, for everyone on the computer
  software.py remove <id>         remove an installed app
  software.py update-apps [<id>…] update these apps (all with updates, with none named)
  software.py update-system       update the system's own packages (the distro's full upgrade,
                                  as root, through slate-system: an administrator's password)

Actions print "progress <0-100>" lines as they go, then one line: "ok", or "error <message>" in
words for people ("error canceled" when the password prompt was closed).

The catalogue is Flatpak's own copy of Flathub's (appstream.xml.gz, with the apps' icons), read
from this computer; nothing is fetched for it. Only `discover` goes to the network: Flathub's
public lists, at an address built here, over https, with nothing about you in it. Installing
and removing go through Flatpak itself, which asks for a password (polkit, Slate's own card)
when the system says it should. System updates: PackageKit's pkcon where it's installed,
otherwise the distro's own way of listing them (checkupdates, apt, dnf, zypper), as you; the
upgrade itself only ever through slate-system's root helper, the same fixed command per distro.
"""
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SLATE = os.path.dirname(HERE)
sys.path.insert(0, HERE)

REMOTE = "flathub"
API = "https://flathub.org/api/v2/collection/%s?page=1&per_page=%d"
LISTS = ("popular", "recently-added", "trending")
# Flathub's main categories (Slate Software's Discover has a row of each's most installed apps)
CATEGORIES = ("Game", "Graphics", "AudioVideo", "Office", "Network", "Development", "Education", "Science", "Utility", "System")
DISCOVER_EVERY = 6 * 3600
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "slate", "software")
# Where Flatpak keeps Flathub's catalogue, for everyone and for you
SYSTEM_FLATPAK = "/var/lib/flatpak"
USER_FLATPAK = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "flatpak")
LANG = "{http://www.w3.org/XML/1998/namespace}lang"
def env():
    """The environment for the tools: as it is now (never kept from when this was loaded), with
    their messages in English, which are read here."""
    return dict(os.environ, LANG="C", LC_ALL="C")


def run(cmd, timeout=60):
    """A command's output, or None when it isn't there or failed."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env())
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


def arch():
    out = run(["flatpak", "--default-arch"], timeout=10)
    return (out or "").strip() or os.uname().machine


def appstream_files():
    """Flathub's catalogue, for everyone and for you (the newer first, when both)."""
    found = []
    for base in (SYSTEM_FLATPAK, USER_FLATPAK):
        p = os.path.join(base, "appstream", REMOTE, arch(), "active", "appstream.xml.gz")
        if os.path.isfile(p):
            found.append(p)
    return sorted(found, key=os.path.getmtime, reverse=True)


def text_of(el, tag):
    """The untranslated text of a child (the catalogue holds every language's)."""
    for c in el.findall(tag):
        if c.get(LANG) is None:
            return (c.text or "").strip()
    return ""


def icon_of(comp, base):
    """The biggest cached icon of an app, as a file on this computer ("" if none)."""
    best, best_size = "", 0
    for ic in comp.findall("icon"):
        if ic.get("type") != "cached" or ic.get("scale"):
            continue
        size = int(ic.get("width") or 0)
        p = os.path.join(base, "icons", "%dx%d" % (size, size), (ic.text or "").strip())
        if size > best_size and os.path.isfile(p):
            best, best_size = p, size
    return best


def apps_in(path):
    """(component, icons folder) for each desktop app in a catalogue file."""
    base = os.path.dirname(path)
    with gzip.open(path) as f:
        root = ET.parse(f).getroot()
    for comp in root.findall("component"):
        if comp.get("type") not in ("desktop-application", "desktop"):
            continue
        if comp.find("bundle") is None:
            continue
        yield comp, base


def short(comp, base):
    dev = comp.find("developer")
    developer = text_of(dev, "name") if dev is not None else text_of(comp, "developer_name")
    return {
        "id": (comp.findtext("id") or "").strip(),
        "name": text_of(comp, "name"),
        "summary": text_of(comp, "summary"),
        "icon": icon_of(comp, base),
        "categories": [c.text for c in comp.findall("categories/category") if c.text],
        "keywords": " ".join(k.text.lower() for k in comp.findall("keywords/keyword") if k.text and k.get(LANG) is None),
        "developer": developer,
    }


def catalogue():
    """Every app, from the newest catalogue; read once and kept (until it changes)."""
    files = appstream_files()
    if not files:
        return []
    src = files[0]
    cache = os.path.join(CACHE, "catalogue.json")
    try:
        with open(cache) as f:
            kept = json.load(f)
        if kept.get("from") == src and kept.get("mtime") == os.path.getmtime(src):
            return kept["apps"]
    except (OSError, ValueError, KeyError):
        pass
    seen, apps = set(), []
    for comp, base in apps_in(src):
        a = short(comp, base)
        if a["id"] and a["name"] and a["id"] not in seen:
            seen.add(a["id"])
            apps.append(a)
    apps.sort(key=lambda a: a["name"].lower())
    os.makedirs(CACHE, exist_ok=True)
    tmp = cache + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"from": src, "mtime": os.path.getmtime(src), "apps": apps}, f)
    os.replace(tmp, cache)
    return apps


def paragraphs(desc):
    """A catalogue description as plain paragraphs (lists as lines starting with "• ")."""
    out = []
    if desc is None:
        return out
    for el in desc:
        if el.get(LANG) is not None:
            continue
        if el.tag == "p":
            t = " ".join("".join(el.itertext()).split())
            if t:
                out.append(t)
        elif el.tag in ("ul", "ol"):
            items = ["• " + " ".join("".join(li.itertext()).split()) for li in el.findall("li") if li.get(LANG) is None]
            if items:
                out.append("\n".join(items))
    return out


def installed():
    """The apps installed with Flatpak: [{id, name, version, installation}]."""
    out = run(["flatpak", "list", "--app", "--columns=application,name,version,installation"])
    apps = []
    for line in (out or "").splitlines():
        p = line.split("\t")
        if len(p) >= 4 and p[0]:
            apps.append({"id": p[0], "name": p[1], "version": p[2], "installation": p[3]})
    return apps


def app(app_id):
    for path in appstream_files()[:1]:
        for comp, base in apps_in(path):
            if (comp.findtext("id") or "").strip() != app_id:
                continue
            a = short(comp, base)
            shots = []
            for s in comp.findall("screenshots/screenshot"):
                imgs = [i for i in s.findall("image") if i.get(LANG) is None]
                full = next((i.text for i in imgs if i.get("type") == "source"), None)
                thumbs = sorted((i for i in imgs if i.get("type") == "thumbnail" and i.get("width")),
                                key=lambda i: abs(int(i.get("width")) - 752))
                thumb = thumbs[0].text if thumbs else full
                if full or thumb:
                    shots.append({"thumb": (thumb or full).strip(), "full": (full or thumb).strip(),
                                  "caption": text_of(s, "caption")})
            links = {u.get("type"): (u.text or "").strip() for u in comp.findall("url") if u.get("type")}
            rel = comp.find("releases/release")
            mine = next((i for i in installed() if i["id"] == app_id), None)
            a.update(description=paragraphs(comp.find("description")), screenshots=shots[:8],
                     homepage=links.get("homepage", ""), license=(comp.findtext("project_license") or "").strip(),
                     latest=rel.get("version", "") if rel is not None else "",
                     installed=mine is not None, version=mine["version"] if mine else "",
                     installation=mine["installation"] if mine else "")
            return a
    return None


def discover():
    """Flathub's lists (their app ids): popular, new and trending, and each category's most
    installed apps ({"categories": {name: [ids]}}), fetched at most every 6 hours; the last
    answer when there's no connection."""
    cache = os.path.join(CACHE, "discover.json")
    kept = {}
    try:
        with open(cache) as f:
            kept = json.load(f)
    except (OSError, ValueError):
        pass
    # (kept from before the categories were fetched too: fetched again)
    if kept and "categories" in kept and time.time() - kept.get("at", 0) < DISCOVER_EVERY:
        return kept

    def ids_of(path, many):
        url = API % (path, many)
        assert url.startswith("https://flathub.org/")
        req = urllib.request.Request(url, headers={"User-Agent": "slate-software"})
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read(4 * 1024 * 1024))
        ids = [h.get("app_id") for h in data.get("hits", []) if isinstance(h, dict)]
        return [i for i in ids if isinstance(i, str) and re.fullmatch(r"[A-Za-z0-9._-]+", i)]

    got = {"at": time.time(), "categories": {}}
    try:
        for name in LISTS:
            got[name] = ids_of(name, 30)
        for cat in CATEGORIES:
            got["categories"][cat] = ids_of("category/" + cat, 16)
    except Exception:
        if kept:
            kept["offline"] = True
            return kept
        return {"offline": True}
    os.makedirs(CACHE, exist_ok=True)
    with open(cache + ".tmp", "w") as f:
        json.dump(got, f)
    os.replace(cache + ".tmp", cache)
    return got


def family():
    try:
        from slate_apps import family as fam
        return fam()
    except Exception:
        return ""


def system_updates():
    """(the tool used, [{name, from, to}], a problem in words or "")."""
    def pairs(lines, rx):
        out = []
        for line in lines:
            m = re.match(rx, line.strip())
            if m:
                out.append({"name": m.group("n"), "from": m.groupdict().get("f") or "", "to": m.group("t")})
        return out
    if shutil.which("pkcon"):
        out = run(["pkcon", "get-updates", "--plain"], timeout=120)
        if out is not None:
            return "pkcon", pairs(out.splitlines(), r"^\S+\s+(?P<n>[^-\s][^\s]*?)-(?P<t>\d[^\s]*)\s"), ""
    fam = family()
    if fam in ("arch", "artix"):
        if not shutil.which("checkupdates"):
            return "", [], "Install pacman-contrib to see system updates"
        try:
            r = subprocess.run(["checkupdates"], capture_output=True, text=True, timeout=180, env=env())
        except (OSError, subprocess.SubprocessError):
            return "checkupdates", [], "Slate couldn't check for system updates"
        # (exit 2: nothing to update)
        if r.returncode not in (0, 2):
            return "checkupdates", [], "Slate couldn't check for system updates"
        return "checkupdates", pairs(r.stdout.splitlines(), r"^(?P<n>\S+)\s+(?P<f>\S+)\s+->\s+(?P<t>\S+)$"), ""
    if fam == "debian":
        out = run(["apt", "list", "--upgradable"], timeout=120)
        return "apt", pairs((out or "").splitlines(), r"^(?P<n>[^/\s]+)/\S+\s+(?P<t>\S+)\s.*\[upgradable from: (?P<f>[^\]]+)\]"), ""
    if fam == "fedora":
        try:
            r = subprocess.run(["dnf", "-q", "check-update"], capture_output=True, text=True, timeout=300, env=env())
        except (OSError, subprocess.SubprocessError):
            return "dnf", [], "Slate couldn't check for system updates"
        return "dnf", pairs(r.stdout.splitlines(), r"^(?P<n>[^\s.]+)\.\S+\s+(?P<t>\S+)\s+\S+$"), ""
    if fam == "opensuse":
        out = run(["zypper", "-q", "list-updates"], timeout=300)
        return "zypper", pairs((out or "").splitlines(), r"^v\s*\|\s*\S+\s*\|\s*(?P<n>\S+)\s*\|\s*(?P<f>\S+)\s*\|\s*(?P<t>\S+)"), ""
    if fam == "nixos":
        return "", [], "On NixOS, your configuration updates the system"
    return "", [], ""


def app_updates():
    """Apps with an update waiting, from each installation (for everyone, and yours)."""
    apps = []
    for where in ("system", "user"):
        out = run(["flatpak", "remote-ls", "--" + where, "--updates", "--app", "--columns=application,name,version"], timeout=180)
        for line in (out or "").splitlines():
            p = line.split("\t")
            if p and p[0]:
                apps.append({"id": p[0], "name": p[1] if len(p) > 1 else p[0], "version": p[2] if len(p) > 2 else "",
                             "installation": where})
    return apps


def updates():
    tool, sysups, problem = system_updates()
    return {"apps": app_updates() if shutil.which("flatpak") else [], "system": sysups,
            "systemTool": tool, "systemProblem": problem}


def status():
    have = shutil.which("flatpak") is not None
    remotes = run(["flatpak", "remotes", "--columns=name"]) if have else None
    return {"flatpak": have, "flathub": REMOTE in (remotes or "").split(), "catalogue": bool(appstream_files()) if have else False}


# ---- Actions ----------------------------------------------------------------------------------
APP_ID = re.compile(r"[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+")


def follow(cmd):
    """Run an action, printing "progress N" as it goes; its exit code and its last words."""
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env(), bufsize=1)
    except OSError:
        return 127, "%s isn't installed" % cmd[0]
    last, said = -1, []
    for chunk in iter(lambda: p.stdout.readline(), ""):
        for part in re.split(r"[\r\n]", chunk):
            m = re.search(r"(\d{1,3})%", part)
            if m:
                n = min(100, int(m.group(1)))
                if n != last:
                    print("progress %d" % n, flush=True)
                    last = n
            elif part.strip():
                said.append(part.strip())
    return p.wait(), (said[-1] if said else "")


def words(code, said, what):
    """How an action went, in words."""
    low = said.lower()
    if code == 0:
        return "ok"
    if "not authorized" in low or "authentication" in low or code in (126, 127) and "pkexec" in low:
        return "error canceled"
    if "no space" in low:
        return "error There isn't enough free space to %s" % what
    if "could not resolve" in low or "network" in low or "couldn't connect" in low or "unable to connect" in low:
        return "error Slate couldn't reach Flathub. Check you're online, then try again"
    return "error Slate couldn't %s%s" % (what, (" (" + said + ")") if said else "")


def install(app_id):
    if not APP_ID.fullmatch(app_id):
        return "error That isn't an app's name"
    code, said = follow(["flatpak", "install", "--system", "-y", "--noninteractive", REMOTE, app_id])
    return words(code, said, "install it")


def remove(app_id):
    if not APP_ID.fullmatch(app_id):
        return "error That isn't an app's name"
    where = next((i["installation"] for i in installed() if i["id"] == app_id), "system")
    flag = "--user" if where == "user" else "--system"
    code, said = follow(["flatpak", "uninstall", flag, "-y", "--noninteractive", app_id])
    return words(code, said, "remove it")


def update_apps(ids):
    for i in ids:
        if not APP_ID.fullmatch(i):
            return "error That isn't an app's name"
    results = []
    for flag in ("--system", "--user"):
        mine = [a["id"] for a in app_updates() if (a["installation"] == "user") == (flag == "--user")]
        todo = [i for i in ids if i in mine] if ids else mine
        if todo:
            code, said = follow(["flatpak", "update", flag, "-y", "--noninteractive", *todo])
            results.append(words(code, said, "update them"))
    return next((r for r in results if r != "ok"), "ok")


def update_system():
    code, said = follow([os.path.join(SLATE, "bin", "slate-system"), "--upgrade"])
    return words(code, said, "update the system")


def main(argv):
    if not argv:
        sys.exit(__doc__)
    what, args = argv[0], argv[1:]
    looks = {"status": status, "catalogue": catalogue, "discover": discover, "installed": installed, "updates": updates}
    if what in looks and not args:
        print(json.dumps(looks[what]()))
        return 0
    if what == "app" and len(args) == 1:
        print(json.dumps(app(args[0])))
        return 0
    if not shutil.which("flatpak") and what in ("install", "remove", "update-apps"):
        print("error Flatpak isn't installed (install the flatpak package)")
        return 1
    if what == "install" and len(args) == 1:
        line = install(args[0])
    elif what == "remove" and len(args) == 1:
        line = remove(args[0])
    elif what == "update-apps":
        line = update_apps(args)
    elif what == "update-system" and not args:
        line = update_system()
    else:
        sys.exit(__doc__)
    print(line, flush=True)
    return 0 if line == "ok" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
