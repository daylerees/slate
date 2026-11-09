#!/usr/bin/env python3
"""Slate's updater: finds new releases on GitHub and installs them, keeping your files.

    update.py check [--force]   look for a newer release (at most every 20 hours unless --force)
    update.py modified          Slate's own files changed by hand since it was installed
    update.py install           download the latest release and install it (install.sh --update)
    update.py revert            go back to the version before (~/.config/slate.previous), keeping
                                your settings and overrides; the one you leave becomes the backup

What it finds and does is kept in ~/.local/state/slate/update.json, which Settings → Updates
shows. Installing keeps settings.json, hypr/ and user/ (your settings and overrides), and
install.sh keeps the whole previous copy, one version back (~/.config/slate.previous).
"""
import hashlib, json, os, re, shutil, subprocess, sys, tarfile, tempfile, time, urllib.request

REPO = "daylerees/slate"
API = f"https://api.github.com/repos/{REPO}/releases/latest"
HERE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))      # ~/.config/slate
DEST = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "slate")
PREVIOUS = DEST + ".previous"
# Yours, never replaced by an update: copied across to the new version as they are (the
# same list as KEEP in install.sh, which must match)
KEEP = ("settings.json", "hypr", "user")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "slate")
STATE = os.path.join(STATE_DIR, "update.json")
LOG = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "slate-update.log")
# The same, as the start of a path inside the install (folders end in "/"), for leaving them
# out when comparing files
KEPT = tuple(k if k == "settings.json" else k + "/" for k in KEEP)
CHECK_EVERY = 20 * 3600


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {}


def save(st):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1)
    os.replace(tmp, STATE)


def version_in(folder):
    try:
        with open(os.path.join(folder, "VERSION")) as f:
            return f.read().strip()
    except Exception:
        return ""


def installed_version():
    return version_in(HERE)


def previous_version():
    """The backup's version ("unknown" if it has none), or "" when there's no backup."""
    if os.path.islink(DEST) or not os.path.isfile(os.path.join(PREVIOUS, "shell.qml")):
        return ""
    return version_in(PREVIOUS) or "unknown"


def parse(v):
    """'v0.4.2' or 'v0.4.2-15-gabc123' (a development copy past v0.4.2) → (0, 4, 2)."""
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", v or "")
    return tuple(int(x) for x in m.groups()) if m else None


def fetch_latest():
    req = urllib.request.Request(API, headers={"Accept": "application/vnd.github+json", "User-Agent": "slate-updater"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def check(force):
    st = load()
    st["previous"] = previous_version()
    if not force and time.time() - st.get("checked", 0) < CHECK_EVERY and st.get("latest"):
        st["current"] = installed_version()
        st["notify"] = False
        print(json.dumps(st))
        return
    st["current"] = installed_version()
    try:
        rel = fetch_latest()
        st.update(latest=rel.get("tag_name", ""), notes=rel.get("body") or "", url=rel.get("html_url", ""),
                  published=rel.get("published_at", ""), error="")
    except Exception as e:
        st["error"] = "Couldn't reach GitHub (%s)" % (getattr(e, "reason", None) or e)
    st["checked"] = time.time()
    cur, new = parse(st["current"]), parse(st.get("latest", ""))
    st["newer"] = bool(cur and new and new > cur)
    # A notification once per new version
    st["notify"] = st["newer"] and st.get("notified") != st["latest"]
    if st["notify"]:
        st["notified"] = st["latest"]
    if st.get("status") == "done" and not st["newer"]:
        st["status"] = "idle"
    save(st)
    print(json.dumps(st))


def ignored(rel):
    """Not Slate's own files: yours (kept), hidden files and Python's caches."""
    # (settings.json itself, not settings.json.bak: only the exact name is kept)
    return rel in KEEP or rel.startswith(tuple(k for k in KEPT if k.endswith("/"))) or rel in ("VERSION",) or any(p.startswith(".") or p == "__pycache__" for p in rel.split("/"))


def modified():
    """Files changed by hand (differ from what was installed) and files added outside the kept folders."""
    manifest = os.path.join(HERE, ".manifest")
    if not os.path.exists(manifest):
        print(json.dumps({"known": False, "changed": [], "added": []}))
        return
    want = {}
    with open(manifest) as f:
        for line in f:
            h, _, rel = line.rstrip("\n").partition("  ")
            if rel:
                want[rel] = h
    changed, added = [], []
    for rel, h in want.items():
        p = os.path.join(HERE, rel)
        if not os.path.exists(p):
            continue           # removed by hand: an update simply puts it back
        with open(p, "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() != h:
                changed.append(rel)
    for dirpath, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "__pycache__"]
        for name in files:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, HERE)
            if os.path.islink(full):
                continue           # links (the cursor theme's aliases) come with Slate as they are
            if not ignored(rel) and rel not in want:
                added.append(rel)
    print(json.dumps({"known": True, "changed": sorted(changed), "added": sorted(added)}))


def install():
    st = load()
    st.update(status="downloading", error="", log=LOG)
    save(st)
    tmp = tempfile.mkdtemp(prefix="slate-update-")
    try:
        rel = fetch_latest()
        tag = rel["tag_name"]
        st.update(latest=tag, notes=rel.get("body") or "", url=rel.get("html_url", ""))
        save(st)
        archive = os.path.join(tmp, "slate.tar.gz")
        req = urllib.request.Request(rel["tarball_url"], headers={"User-Agent": "slate-updater"})
        with urllib.request.urlopen(req, timeout=120) as r, open(archive, "wb") as f:
            shutil.copyfileobj(r, f)
        src = os.path.join(tmp, "src")
        with tarfile.open(archive) as t:
            t.extractall(src, filter="data")
        root = os.path.join(src, os.listdir(src)[0])
        with open(os.path.join(root, "shell", "VERSION"), "w") as f:
            f.write(tag + "\n")
        st["status"] = "installing"
        save(st)
        with open(LOG, "w") as log:
            rc = subprocess.run(["bash", os.path.join(root, "install.sh"), "--update"], cwd=root,
                                stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                env=dict(os.environ, TERM="dumb")).returncode
        st = load()
        st["note"] = ""
        if rc == 0:
            st.update(status="done", current=tag, newer=False, error="", previous=previous_version())
            with open(LOG) as log:
                if "changes the login session" in log.read():
                    st["note"] = ("One more step: this version changes the login session. In a terminal, run: "
                                  "sudo ~/.config/slate/bin/slate-session-install")
        elif rc == 3:
            # (install.sh --update installs new packages itself, with a password prompt)
            st.update(status="failed", error="This update needs packages that weren't installed (the password prompt "
                      "was cancelled, or they couldn't be). Try again, or download the release and run ./install.sh from it.")
        else:
            st.update(status="failed", error="The update didn't finish (see the log). Your previous Slate is still in place.")
    except Exception as e:
        st = load()
        st.update(status="failed", error="Couldn't download the update (%s)" % (getattr(e, "reason", None) or e))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    save(st)


def revert():
    st = load()
    if not previous_version():
        st.update(status="failed", error="There's no previous version to go back to.")
        save(st)
        return
    leaving = installed_version()
    swap = DEST + ".swap"
    shutil.rmtree(swap, ignore_errors=True)
    os.rename(DEST, swap)
    os.rename(PREVIOUS, DEST)
    # Your settings and overrides come along, as they are now
    for k in KEEP:
        src, dst = os.path.join(swap, k), os.path.join(DEST, k)
        if not os.path.exists(src):
            continue
        if os.path.isdir(dst) and not os.path.islink(dst):
            shutil.rmtree(dst)
        elif os.path.lexists(dst):
            os.remove(dst)
        (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst, **({"symlinks": True} if os.path.isdir(src) else {}))
    os.rename(swap, PREVIOUS)
    st.update(status="reverted", error="", current=version_in(DEST), reverted_from=leaving, previous=previous_version())
    cur, new = parse(st["current"]), parse(st.get("latest", ""))
    st["newer"] = bool(cur and new and new > cur)
    save(st)
    subprocess.run([os.path.join(DEST, "bin", "slate"), "restart"], stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "check":
        check("--force" in sys.argv)
    elif cmd == "modified":
        modified()
    elif cmd == "install":
        install()
    elif cmd == "revert":
        revert()
    else:
        sys.exit(__doc__)
