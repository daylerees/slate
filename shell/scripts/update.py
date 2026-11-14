#!/usr/bin/env python3
"""Slate's updater: finds new releases on GitHub and installs them, keeping your files.

    update.py check [--force]   look for a newer release (at most every 20 hours unless --force)
    update.py modified          Slate's own files changed by hand since it was installed
    update.py install           download the latest release, check it against the checksum
                                published with it, and install it (install.sh --update)
    update.py revert            go back to the version before (~/.config/slate.previous), keeping
                                your settings and overrides; the one you leave becomes the backup

What it finds and does is kept in ~/.local/state/slate/update.json, which Settings → Updates
shows. Installing keeps settings.json, hypr/ and user/ (your settings and overrides), and
install.sh keeps the whole previous copy, one version back (~/.config/slate.previous).

What `install` trusts: the release's tag has to look like a version (v1.2.3) and be newer than
the Slate that's installed, the download addresses are built here from REPO and that tag (never
taken from GitHub's reply), and the download has to match the SHA-256 published beside it
before anything is unpacked or run. Both files are made by tools/release-assets.sh.
"""
import hashlib, json, os, re, shutil, subprocess, sys, tarfile, tempfile, time, urllib.error, urllib.parse, urllib.request

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
# A release's tag, exactly: it goes into the download addresses, so nothing else is accepted
TAG = re.compile(r"v\d+\.\d+\.\d+\Z")
# Where a release's own files are (tools/release-assets.sh makes them, and they're uploaded
# with the release): slate-<tag>.tar.gz, and its SHA-256 in slate-<tag>.tar.gz.sha256
DOWNLOADS = f"https://github.com/{REPO}/releases/download"
# The only places the updater talks to: GitHub, and where GitHub sends a release's files on
# from. A redirect anywhere else is refused
HOSTS = ("api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
# Far more than a release weighs (about 90 MB), and the checksum file is one short line
MAX_BYTES = 400 * 1024 * 1024
MAX_CHECKSUM_BYTES = 4096


class Refused(Exception):
    """The update was turned down before anything was unpacked or run. Its text is what
    Settings → Updates shows, so it's a whole sentence in Slate's words."""


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


def proper_tag(tag):
    """Whether it's a release's tag and nothing more (v1.2.3)."""
    return isinstance(tag, str) and bool(TAG.match(tag))


def check_address(url):
    """Only https, and only GitHub's own hosts."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.hostname not in HOSTS:
        raise Refused("Slate only downloads updates from GitHub, and this one led somewhere else (%s), "
                      "so nothing was installed." % (parts.hostname or url))


class GitHubOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to another of GitHub's hosts (a release's files are handed on
    to release-assets.githubusercontent.com)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_address(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def open_url(url, timeout, accept=None):
    check_address(url)
    headers = {"User-Agent": "slate-updater"}
    if accept:
        headers["Accept"] = accept
    return urllib.request.build_opener(GitHubOnly).open(urllib.request.Request(url, headers=headers), timeout=timeout)


def fetch_latest():
    with open_url(API, 20, accept="application/vnd.github+json") as r:
        return json.load(r)


def download(url, dest, limit, timeout=120):
    """Download url to dest (at most limit bytes), returning its SHA-256."""
    h, got = hashlib.sha256(), 0
    with open_url(url, timeout) as r, open(dest, "wb") as out:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            got += len(chunk)
            if got > limit:
                raise RuntimeError("the download was much bigger than expected")
            h.update(chunk)
            out.write(chunk)
    return h.hexdigest()


def checksum_in(text):
    """The SHA-256 in a checksum file ("<64 hex digits>  <name>", as sha256sum writes it), or ""."""
    first = (text.split() or [""])[0].lower()
    return first if re.fullmatch(r"[0-9a-f]{64}", first) else ""


def newer_than_installed(tag):
    """Turn down anything that isn't a release newer than the Slate that's installed, so a
    reply naming an old version (or something that isn't a version) can't put it in place.
    Going back a version is `revert`, which uses the copy already on this computer."""
    if not proper_tag(tag):
        raise Refused("Slate couldn't make sense of the version GitHub gave (%s), so nothing was installed."
                      % str(tag)[:40])
    have = installed_version()
    if not parse(have):
        raise Refused("Slate couldn't tell which version you have, so it can't be sure %s is newer and didn't "
                      "install it. Running ./install.sh from the release sorts that out." % tag)
    if parse(tag) <= parse(have):
        raise Refused("%s isn't newer than the Slate you have (%s), so there's nothing to install." % (tag, have))


def fetch_release(tag, folder):
    """Download a release's archive into folder and check it against the SHA-256 published
    with it. Returns (the archive's path, its SHA-256); raises Refused, with nothing unpacked,
    when there's no checksum to check against or the download doesn't match it."""
    name = "slate-%s.tar.gz" % tag
    sums = os.path.join(folder, name + ".sha256")
    try:
        download("%s/%s/%s.sha256" % (DOWNLOADS, tag, name), sums, MAX_CHECKSUM_BYTES, timeout=20)
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        # (every release made since the updater started checking has one: without it there's
        # nothing to tell a good download from a bad one, so it isn't installed)
        raise Refused("Slate couldn't check this download, so it wasn't installed: %s doesn't have a checksum "
                      "yet. Your Slate is just as it was, and you can try again later." % tag)
    with open(sums, encoding="utf-8", errors="replace") as f:
        want = checksum_in(f.read())
    if not want:
        raise Refused("Slate couldn't check this download, so it wasn't installed: the checksum published with %s "
                      "couldn't be read. Your Slate is just as it was, and you can try again later." % tag)
    archive = os.path.join(folder, name)
    got = download("%s/%s/%s" % (DOWNLOADS, tag, name), archive, MAX_BYTES)
    if got != want:
        os.remove(archive)
        raise Refused("The download didn't match the checksum published with %s, so Slate didn't install it. "
                      "Your Slate is just as it was, and you can try again." % tag)
    return archive, got


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
        st["error"] = "Slate couldn't reach GitHub (%s)" % (getattr(e, "reason", None) or e)
    st["checked"] = time.time()
    cur, new = parse(st["current"]), parse(st.get("latest", ""))
    # (only a proper tag is offered: `install` would turn anything else down)
    st["newer"] = bool(cur and new and new > cur and proper_tag(st.get("latest")))
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
        # Only the tag is taken from the reply for downloading, and only once it's a proper
        # one, newer than what's here: the addresses are built from it (the reply's own
        # tarball_url is never used)
        tag = rel.get("tag_name")
        newer_than_installed(tag)
        st.update(latest=tag, notes=rel.get("body") or "", url=rel.get("html_url", ""))
        save(st)
        archive, digest = fetch_release(tag, tmp)
        src = os.path.join(tmp, "src")
        with tarfile.open(archive) as t:
            t.extractall(src, filter="data")
        root = os.path.join(src, os.listdir(src)[0])
        with open(os.path.join(root, "shell", "VERSION"), "w") as f:
            f.write(tag + "\n")
        st["status"] = "installing"
        save(st)
        with open(LOG, "w") as log:
            log.write("%s matched the checksum published with %s (sha256 %s)\n\n" % (os.path.basename(archive), tag, digest))
            log.flush()
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
                                  "~/.config/slate/bin/slate-system --fix")
        elif rc == 3:
            # (install.sh --update installs new packages itself, with a password prompt)
            st.update(status="failed", error="This update needs packages that weren't installed (the password prompt "
                      "was cancelled, or they couldn't be). Try again, or download the release and run ./install.sh from it.")
        else:
            st.update(status="failed", error="The update didn't finish (see the log). Your previous Slate is still in place.")
    except Refused as e:
        st = load()
        st.update(status="failed", error=str(e))
    except Exception as e:
        st = load()
        st.update(status="failed", error="Slate couldn't download the update (%s). Your Slate is just as it was."
                  % (getattr(e, "reason", None) or e))
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
