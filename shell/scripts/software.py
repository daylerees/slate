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
            # (the untranslated one: Flathub's catalog lists some apps' translations first)
            desc = next((d for d in comp.findall("description") if d.get(LANG) is None), None)
            a.update(description=paragraphs(desc), screenshots=shots[:8],
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


def metered():
    """Whether NetworkManager says this connection is metered (charged by the amount): a phone's
    hotspot, say. Then the daily look for updates waits for another one."""
    out = run(["gdbus", "call", "--system", "--dest", "org.freedesktop.NetworkManager",
               "--object-path", "/org/freedesktop/NetworkManager", "--method", "org.freedesktop.DBus.Properties.Get",
               "org.freedesktop.NetworkManager", "Metered"], timeout=10)
    m = re.search(r"uint32 (\d+)", out or "")
    return bool(m) and int(m.group(1)) in (1, 3)       # (yes, or guessed yes)


def daily():
    """The once-a-day look (SoftwareUpdates.qml): how many app and system updates are waiting,
    or {"metered": true} without looking."""
    if metered():
        return {"metered": True}
    u = updates()
    return {"apps": len(u["apps"]), "system": len(u["system"])}


def status():
    have = shutil.which("flatpak") is not None
    remotes = run(["flatpak", "remotes", "--columns=name"]) if have else None
    return {"flatpak": have, "flathub": REMOTE in (remotes or "").split(), "catalogue": bool(appstream_files()) if have else False}


# ---- Actions ----------------------------------------------------------------------------------
APP_ID = re.compile(r"[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)+")


# Progress, from what an action prints. Away from a terminal Flatpak and pacman draw no bars,
# only steps, so the steps are the progress:
#   Flatpak:  "Updating 2/7…" (sometimes with "40%" for that step)
#   pacman:   "Packages (75) …", then " downloading x…" for each (the first 40%), then
#             "(12/75) upgrading x" (the rest; its hooks' own "(1/2) …" don't count)
#   others:   "(n/m)" steps, or a plain "40%"
STEP_VERB = re.compile(r"\b(?:Installing|Updating|Uninstalling|Downloading|Upgrading)\s+(\d+)/(\d+)")
PACMAN_STEP = re.compile(r"^\((\d+)/(\d+)\)\s+(?:upgrading|installing|removing|reinstalling|downgrading)\b")
PERCENT = re.compile(r"(\d{1,3})%")


def progress_lines(parts):
    """ "progress N" for each line that moves it on (never backwards)."""
    last, total, downloaded = -1, 0, 0
    for part in parts:
        m = re.search(r"^Packages \((\d+)\)", part.strip())
        if m:
            total = int(m.group(1))
            continue
        pct = PERCENT.search(part)
        within = min(100, int(pct.group(1))) / 100 if pct else 0
        step = STEP_VERB.search(part) or PACMAN_STEP.search(part.strip())
        if total and part.strip().startswith("downloading "):
            downloaded += 1
            n = 40 * min(downloaded, total) / total
        elif step:
            k, of = int(step.group(1)), max(1, int(step.group(2)))
            done = (k - 1 + within) / of
            n = (40 + 60 * done) if downloaded else 100 * done
        elif pct:
            n = 100 * within
        else:
            continue
        n = int(n)
        if n > last:
            last = n
            yield "progress %d" % n


ESCAPES = re.compile(r"\x1b(?:\[[0-9;?]*[A-Za-z]|[()][A-Z0-9]|[=>78])")


def chunks_of(cmd, tty):
    """(the process, its output as text as it comes). With tty, in a terminal of its own:
    Flatpak only shows how far a download has got when it's writing to one."""
    if not tty:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, env=env(), bufsize=1)
        return p, iter(lambda: p.stdout.readline(), "")
    import fcntl
    import pty
    import struct
    import termios
    leader, follower = pty.openpty()
    # (wide, so its progress line isn't wrapped or cut short)
    fcntl.ioctl(follower, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 200, 0, 0))
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=follower, stderr=follower, env=env(), close_fds=True)
    finally:
        os.close(follower)

    def read():
        try:
            while True:
                try:
                    data = os.read(leader, 4096)
                except OSError:          # (EIO: it has finished, and its terminal is closed)
                    return
                if not data:
                    return
                yield ESCAPES.sub("", data.decode(errors="replace"))
        finally:
            os.close(leader)
    return p, read()


def follow(cmd, tty=False):
    """Run an action, printing "progress N" as it goes (and 100 once it's done); its exit code
    and its last words."""
    try:
        p, chunks = chunks_of(cmd, tty)
    except OSError:
        return 127, "%s isn't installed" % cmd[0]
    said = []

    def parts():
        rest = ""
        for chunk in chunks:
            pieces = re.split(r"[\r\n]", rest + chunk)
            rest = pieces.pop()
            for part in pieces:
                if part.strip() and not PERCENT.search(part):
                    said.append(part.strip())
                yield part
        if rest:
            if rest.strip() and not PERCENT.search(rest):
                said.append(rest.strip())
            yield rest
    last = None
    for line in progress_lines(parts()):
        print(line, flush=True)
        last = line
    code = p.wait()
    if code == 0 and last != "progress 100":
        print("progress 100", flush=True)
    return code, (said[-1] if said else "")


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
    code, said = follow(["flatpak", "install", "--system", "-y", REMOTE, app_id], tty=True)
    return words(code, said, "install it")


def remove(app_id):
    if not APP_ID.fullmatch(app_id):
        return "error That isn't an app's name"
    where = next((i["installation"] for i in installed() if i["id"] == app_id), "system")
    flag = "--user" if where == "user" else "--system"
    code, said = follow(["flatpak", "uninstall", flag, "-y", app_id], tty=True)
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
            code, said = follow(["flatpak", "update", flag, "-y", *todo], tty=True)
            results.append(words(code, said, "update them"))
    return next((r for r in results if r != "ok"), "ok")


def update_system():
    code, said = follow([os.path.join(SLATE, "bin", "slate-system"), "--upgrade"])
    return words(code, said, "update the system")


# ---- Jobs that outlive Slate ------------------------------------------------------------------
# Slate starts each install, removal or update as `software.py job <token> <action> [id]`, a
# process of its own (so a reload or restart of Slate can't cut it off), which keeps how it's going
# in a file Slate follows: {token, what, id, pid, progress, done, result}. Slate picks up a job
# still running when it starts, from the same file.
def runtime_dir():
    """Slate's runtime folder: $XDG_RUNTIME_DIR, or without one a folder of your own that only
    you can open, never /tmp (the rule is Config.qml's runtimeDir)."""
    d = os.environ.get("XDG_RUNTIME_DIR")
    if d:
        return d
    d = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "slate", "run")
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    return d


def job_file():
    return os.path.join(runtime_dir(), "slate", "software-job.json")


def write_job(state):
    path = job_file()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(state, f)
    os.replace(tmp, path)


def job(token, what, args):
    state = {"token": token, "what": what, "id": args[0] if args else "", "pid": os.getpid(),
             "progress": 0, "done": False, "result": ""}
    write_job(state)
    try:
        p = subprocess.Popen([sys.executable, os.path.abspath(__file__), what, *args],
                             stdout=subprocess.PIPE, text=True, bufsize=1)
        for line in p.stdout:
            line = line.strip()
            if line.startswith("progress "):
                state["progress"] = int(line.split()[1])
                write_job(state)
            elif line:
                state["result"] = line
        p.wait()
    except Exception as e:  # anything at all: say so, rather than leave it "running"
        state["result"] = "error Slate couldn't finish that (%s)" % e
    state["done"] = True
    write_job(state)
    return 0 if state["result"] == "ok" else 1


def main(argv):
    if not argv:
        sys.exit(__doc__)
    what, args = argv[0], argv[1:]
    looks = {"status": status, "catalogue": catalogue, "discover": discover, "installed": installed, "updates": updates,
             "daily": daily}
    if what in looks and not args:
        print(json.dumps(looks[what]()))
        return 0
    if what == "job" and len(args) >= 2 and args[1] in ("install", "remove", "update-apps", "update-system"):
        return job(args[0], args[1], args[2:])
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
