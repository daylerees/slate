#!/usr/bin/env python3
"""Slate's updater: finds new releases on GitHub and installs them, keeping your files.

    update.py check [--force]   look for a newer release (at most every 20 hours unless --force)
    update.py modified          Slate's own files changed by hand since it was installed
    update.py install           download the latest release, check it against the checksum
                                published with it, and install it (install.sh --update), or
                                for Slate installed for everyone, have slate-update-install do
                                that as root, with an administrator's password
    update.py revert            go back to the version before (<Slate's folder>.previous),
                                keeping your settings and overrides; the one you leave becomes the
                                backup

How Slate's installed decides which (layout(), shown as `how` in the state):
  own       yours to change: a copy or link of your own in ~/.config/slate, or the copy for
            everyone in a folder that's yours (made so to work on Slate): updated as you
  shared    the copy for everyone in /usr/local/share/slate, root's: updated by the root-owned
            slate-update-install (given only the tag; it downloads and checks the release
            itself), with an administrator's password
  packaged  from a distro package (/usr/share/slate, the Nix store): updated with the rest of
            the system, never by Slate itself

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
HERE = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))      # Slate's code, this one
DEST = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "slate")  # your files
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


# Slate from a distro package: these places are only ever written by a package manager
PACKAGED = ("/usr/share/", "/nix/store/")


def layout():
    """"own", "shared" or "packaged": see the top of this file."""
    here = os.path.realpath(HERE)
    if here.startswith(PACKAGED):
        return "packaged"
    st = os.stat(here)
    return "own" if st.st_uid == os.getuid() and os.access(here, os.W_OK) else "shared"


def previous_dir():
    """Where the version before this one is kept: beside it (none for a link to a checkout)."""
    if os.path.islink(DEST) and os.path.realpath(DEST) == os.path.realpath(HERE):
        return ""
    return os.path.realpath(HERE) + ".previous"


def previous_version():
    """The backup's version ("unknown" if it has none), or "" when there's no backup."""
    prev = previous_dir()
    if not prev or not os.path.isfile(os.path.join(prev, "shell.qml")):
        return ""
    return version_in(prev) or "unknown"


def as_root(*args):
    """Runs a root-owned helper through slate-system (an administrator's password): its exit
    code and what it said."""
    r = subprocess.run([os.path.join(HERE, "bin", "slate-system"), "--root", *args], stdin=subprocess.DEVNULL,
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


# pkexec's own exit codes: the password prompt closed, or not allowed
CANCELED = (126, 127)


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


def download(url, dest, limit, timeout=120, progress=None):
    """Download url to dest (at most limit bytes), returning its SHA-256. progress, if given,
    is called with (bytes so far, the whole size or 0 when the server doesn't say) as it goes."""
    h, got = hashlib.sha256(), 0
    with open_url(url, timeout) as r, open(dest, "wb") as out:
        try:
            size = int((getattr(r, "headers", None) or {}).get("Content-Length") or 0)
        except (TypeError, ValueError):
            size = 0
        size = size if 0 < size <= limit else 0
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            got += len(chunk)
            if got > limit:
                raise RuntimeError("the download was much bigger than expected")
            h.update(chunk)
            out.write(chunk)
            if progress:
                progress(got, size)
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


def fetch_release(tag, folder, progress=None):
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
    got = download("%s/%s/%s" % (DOWNLOADS, tag, name), archive, MAX_BYTES, progress=progress)
    if got != want:
        os.remove(archive)
        raise Refused("The download didn't match the checksum published with %s, so Slate didn't install it. "
                      "Your Slate is just as it was, and you can try again." % tag)
    return archive, got


def check(force):
    st = load()
    st["previous"] = previous_version()
    st["how"] = layout()
    st["kept"] = previous_dir().replace(os.path.expanduser("~"), "~", 1)
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
    how = st["how"] = layout()
    if how == "packaged":
        st.update(status="failed", error="Slate came with your system's packages, so it updates with them: "
                  "use your system's own updates.")
        save(st)
        return
    if how == "shared":
        install_for_everyone(st)
        return
    st.update(status="downloading", error="", log=LOG, got=0, size=0)
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
        archive, digest = fetch_release(tag, tmp, progress=lambda got, size: show_progress(st, got, size))
        src = os.path.join(tmp, "src")
        with tarfile.open(archive) as t:
            t.extractall(src, filter="data")
        root = os.path.join(src, os.listdir(src)[0])
        with open(os.path.join(root, "shell", "VERSION"), "w") as f:
            f.write(tag + "\n")
        st.update(status="installing", got=0, size=0)
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
                                  + os.path.join(HERE, "bin", "slate-system") + " --fix")
        elif rc == 3:
            with open(LOG) as log:
                said = log.read()
            if "installed for everyone on the computer" in said:
                # (a copy of your own from before Slate was installed for everyone)
                st.update(status="failed", error="Slate is now installed once for everyone on the computer. To move "
                          "to that, download the release and run ./install.sh from it (it asks for your password and "
                          "keeps your settings).")
            else:
                # (install.sh --update installs new packages itself, with a password prompt)
                st.update(status="failed", error="This update needs packages that weren't installed (the password prompt "
                          "was canceled, or they couldn't be). Try again, or download the release and run ./install.sh from it.")
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


_last_shown = [0.0]


def show_progress(st, got, size, every=0.25):
    """How much of the download has come, for Settings → Updates: written a few times a second
    at most (and when it's all there), not for every piece that arrives."""
    now = time.monotonic()
    if not (size and got >= size) and now - _last_shown[0] < every:
        return
    _last_shown[0] = now
    st.update(got=got, size=size)
    save(st)


def install_for_everyone(st):
    """The copy for everyone, root's: checked here that the newest release is a proper one,
    newer than this, then handed to slate-update-install by its tag alone, which downloads
    and checks it again itself, as root (an administrator's password)."""
    st.update(status="downloading", error="", log=LOG)
    save(st)
    try:
        rel = fetch_latest()
        tag = rel.get("tag_name")
        newer_than_installed(tag)
        st.update(latest=tag, notes=rel.get("body") or "", url=rel.get("html_url", ""), status="installing")
        save(st)
    except Refused as e:
        st.update(status="failed", error=str(e))
        save(st)
        return
    except Exception as e:
        st.update(status="failed", error="Slate couldn't reach GitHub (%s). Your Slate is just as it was."
                  % (getattr(e, "reason", None) or e))
        save(st)
        return
    rc, said = as_root("slate-update-install", tag)
    with open(LOG, "w") as log:
        log.write(said + "\n")
    st = load()
    st["note"] = ""
    if rc == 0:
        st.update(status="done", current=installed_version(), newer=False, error="", previous=previous_version())
        restart()
    elif rc in CANCELED:
        st.update(status="failed", error="The password prompt was closed, so nothing changed.")
    else:
        st.update(status="failed", error="The update didn't finish (see the log). Your previous Slate is still in place.")
    save(st)


def restart():
    subprocess.run([os.path.join(HERE, "bin", "slate"), "restart"], stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def revert():
    st = load()
    st["how"] = how = layout()
    if how == "packaged":
        st.update(status="failed", error="Slate came with your system's packages, so going back is up to them.")
        save(st)
        return
    if how == "shared":
        if not previous_version():
            st.update(status="failed", error="There's no previous version to go back to.")
            save(st)
            return
        leaving = installed_version()
        rc, said = as_root("slate-update-install", "--revert")
        st = load()
        if rc == 0:
            st.update(status="reverted", error="", current=installed_version(), reverted_from=leaving, previous=previous_version())
            cur, new = parse(st["current"]), parse(st.get("latest", ""))
            st["newer"] = bool(cur and new and new > cur)
            save(st)
            restart()
        else:
            st.update(status="failed", error="The password prompt was closed, so nothing changed." if rc in CANCELED
                      else "Slate couldn't go back (%s)." % said.splitlines()[-1] if said else "Slate couldn't go back.")
            save(st)
        return
    if not previous_version():
        st.update(status="failed", error="There's no previous version to go back to.")
        save(st)
        return
    leaving = installed_version()
    code, prev = os.path.realpath(HERE), previous_dir()
    swap = code + ".swap"
    shutil.rmtree(swap, ignore_errors=True)
    os.rename(code, swap)
    os.rename(prev, code)
    # Your settings and overrides come along, as they are now (when they're kept in with the
    # code: an install of your own in ~/.config/slate)
    for k in KEEP if code == os.path.realpath(DEST) else ():
        src, dst = os.path.join(swap, k), os.path.join(code, k)
        if not os.path.exists(src):
            continue
        if os.path.isdir(dst) and not os.path.islink(dst):
            shutil.rmtree(dst)
        elif os.path.lexists(dst):
            os.remove(dst)
        (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst, **({"symlinks": True} if os.path.isdir(src) else {}))
    os.rename(swap, prev)
    st.update(status="reverted", error="", current=version_in(code), reverted_from=leaving, previous=previous_version())
    cur, new = parse(st["current"]), parse(st.get("latest", ""))
    st["newer"] = bool(cur and new and new > cur)
    save(st)
    restart()


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
