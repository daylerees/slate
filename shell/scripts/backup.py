#!/usr/bin/env python3
"""Settings → Backups: backups of your files with restic (encrypted, deduplicated snapshots).

    backup.py status               where, the last backup and whether one's due: JSON
    backup.py setup <folder>       a new backup there (restic init), its key made and kept
    backup.py run                  back up now (at low priority); the outcome kept for status
    backup.py due                  "yes" if a scheduled backup should run now (and can: the drive's
                                   there), else why not
    backup.py snapshots            the backups there are, newest first: JSON
    backup.py ls <id> <folder>     what's in a folder of a backup: JSON
    backup.py restore <id> <path>  a file or folder from a backup, into ~/Restored from backup/<date>/,
                                   beside your files, never over them
    backup.py key                  the backup's key (for restoring on another computer)

What's backed up, how often and where come from settings.json (backupWhat: "home" or "personal",
backupSchedule: "daily", "weekly" or "manual", backupTo). The key lives in your keyring
(secret-tool) when there is one, else in a file only you can read. restic is needed; without it
everything answers {"error": "restic"} and the page says what to install.
"""
import datetime
import json
import os
import secrets
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "slate")
STATE = os.path.join(STATE_DIR, "backup.json")
KEYFILE = os.path.join(STATE_DIR, "backup-key")
CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
DATA = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
PERSONAL = ["Desktop", "Documents", "Pictures", "Music", "Videos"]
KEYRING = ["service", "slate-backup", "account", "restic"]


def settings():
    try:
        with open(os.path.join(CONFIG, "slate", "settings.json")) as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    return {"to": d.get("backupTo") or "", "what": d.get("backupWhat") or "home", "schedule": d.get("backupSchedule") or "daily"}


def private_dir():
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)


def read_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def write_state(st):
    private_dir()
    tmp = STATE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE)


# ---- The key ----------------------------------------------------------------------------------
def have(cmd):
    return shutil.which(cmd) is not None


def get_key():
    if have("secret-tool"):
        r = subprocess.run(["secret-tool", "lookup", *KEYRING], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    try:
        with open(KEYFILE) as f:
            return f.read().strip()
    except OSError:
        return ""


def keep_key(key):
    if have("secret-tool"):
        r = subprocess.run(["secret-tool", "store", "--label=Slate backups", *KEYRING], input=key, text=True,
                           capture_output=True)
        if r.returncode == 0:
            return "keyring"
    private_dir()
    fd = os.open(KEYFILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(key)
    return "file"


# ---- restic -----------------------------------------------------------------------------------
def restic(repo, args, key=None, low=False, timeout=None):
    env = dict(os.environ, RESTIC_REPOSITORY=repo, RESTIC_PASSWORD=key if key is not None else get_key())
    cmd = ["restic", *args]
    if low:
        cmd = ["nice", "-n", "19"] + (["ionice", "-c", "3"] if have("ionice") else []) + cmd
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout)


def last_line(text):
    lines = [l for l in (text or "").splitlines() if l.strip()]
    return lines[-1][:200] if lines else ""


def what_to_back_up(what):
    if what == "personal":
        return [p for p in (os.path.join(HOME, d) for d in PERSONAL) if os.path.isdir(p)]
    return [HOME]


def excludes():
    # (things that are made again, or aren't yours to keep: caches, the Waste Basket, apps' own
    # installs, and the backup itself if it's inside your home)
    out = ["--exclude-caches", "--exclude", CACHE, "--exclude", os.path.join(DATA, "Trash"),
           "--exclude", os.path.join(DATA, "flatpak"), "--exclude", os.path.join(HOME, ".var", "app", "*", "cache"),
           "--exclude", os.path.join(DATA, "Steam", "steamapps")]
    to = settings()["to"]
    if to:
        out += ["--exclude", to]
    return out


def status():
    s = settings()
    st = read_state()
    out = {"restic": have("restic"), "to": s["to"], "what": s["what"], "schedule": s["schedule"],
           "set": bool(s["to"]) and st.get("repo") == s["to"],
           "last": st.get("last"), "lastOk": st.get("lastOk"), "lastError": st.get("lastError", ""),
           "lastSize": st.get("lastSize"), "lastFiles": st.get("lastFiles"),
           "running": os.path.exists(os.path.join(STATE_DIR, "backup-running")),
           "keyIn": st.get("keyIn", ""), "reachable": bool(s["to"]) and os.path.isdir(s["to"])}
    return out


def setup(folder):
    if not have("restic"):
        return {"error": "restic"}
    folder = os.path.abspath(os.path.expanduser(folder))
    try:
        os.makedirs(folder, exist_ok=True)
    except OSError as e:
        return {"error": "folder", "detail": str(e)}
    st = read_state()
    # A backup already there (set up before, or on another computer's drive with our key)
    if os.path.exists(os.path.join(folder, "config")):
        key = get_key()
        r = restic(folder, ["cat", "config"], key=key, timeout=60)
        if r.returncode != 0:
            return {"error": "locked", "detail": "There's already a backup there, made with another key."}
        st.update({"repo": folder})
        write_state(st)
        return {"ok": True, "existing": True}
    key = get_key() or secrets.token_urlsafe(32)
    r = restic(folder, ["init"], key=key, timeout=120)
    if r.returncode != 0:
        return {"error": "init", "detail": last_line(r.stderr)}
    st.update({"repo": folder, "keyIn": keep_key(key)})
    write_state(st)
    return {"ok": True}


def run():
    s = status()
    if not s["restic"]:
        return {"error": "restic"}
    if not s["set"]:
        return {"error": "notset"}
    if not s["reachable"]:
        return {"error": "away"}
    flag = os.path.join(STATE_DIR, "backup-running")
    private_dir()
    open(flag, "w").close()
    try:
        r = restic(s["to"], ["backup", "--json", "--one-file-system", *excludes(), *what_to_back_up(s["what"])], low=True)
    finally:
        try:
            os.remove(flag)
        except OSError:
            pass
    st = read_state()
    st["last"] = int(time.time())
    summary = {}
    for line in (r.stdout or "").splitlines():
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("message_type") == "summary":
            summary = m
    # (exit 3: some files couldn't be read, the rest backed up: still a backup)
    ok = r.returncode in (0, 3) and bool(summary)
    st["lastOk"] = ok
    st["lastError"] = "" if ok else last_line(r.stderr) or "restic stopped (exit %d)" % r.returncode
    if ok:
        st["lastGood"] = st["last"]
        st["lastSize"] = summary.get("total_bytes_processed")
        st["lastFiles"] = summary.get("total_files_processed")
    write_state(st)
    return {"ok": ok, "error": st["lastError"]} if not ok else {"ok": True}


def due():
    s = status()
    if not s["restic"] or not s["set"]:
        return "no: not set up"
    if s["schedule"] == "manual":
        return "no: only by hand"
    if s["running"]:
        return "no: running"
    if not s["reachable"]:
        return "no: away"
    good = read_state().get("lastGood") or 0
    every = 86400 if s["schedule"] == "daily" else 7 * 86400
    return "yes" if time.time() - good >= every else "no: not yet"


def snapshots():
    s = status()
    if not s["set"]:
        return []
    r = restic(s["to"], ["snapshots", "--json"], timeout=120)
    try:
        snaps = json.loads(r.stdout or "[]")
    except ValueError:
        return []
    return [{"id": x.get("short_id") or x["id"][:8], "time": x.get("time", ""), "paths": x.get("paths", [])}
            for x in reversed(snaps)]


def ls(snap, folder):
    s = status()
    r = restic(s["to"], ["ls", "--json", snap, folder], timeout=180)
    out = []
    for line in (r.stdout or "").splitlines():
        try:
            m = json.loads(line)
        except ValueError:
            continue
        p = m.get("path")
        if not p or m.get("struct_type") != "node" or p == folder or os.path.dirname(p) != folder.rstrip("/"):
            continue
        out.append({"path": p, "name": os.path.basename(p), "dir": m.get("type") == "dir", "size": m.get("size", 0)})
    out.sort(key=lambda e: (not e["dir"], e["name"].lower()))
    return out


def restore(snap, path):
    s = status()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H.%M")
    target = os.path.join(HOME, "Restored from backup", stamp)
    os.makedirs(target, exist_ok=True)
    r = restic(s["to"], ["restore", snap, "--target", target, "--include", path], low=True)
    if r.returncode != 0:
        return {"error": last_line(r.stderr) or "restic stopped (exit %d)" % r.returncode}
    return {"ok": True, "to": target}


if __name__ == "__main__":
    a = sys.argv[1:]
    what = a[0] if a else ""
    if what == "status":
        print(json.dumps(status()))
    elif what == "setup" and len(a) == 2:
        print(json.dumps(setup(a[1])))
    elif what == "run":
        print(json.dumps(run()))
    elif what == "due":
        print(due())
    elif what == "snapshots":
        print(json.dumps(snapshots()))
    elif what == "ls" and len(a) == 3:
        print(json.dumps(ls(a[1], a[2])))
    elif what == "restore" and len(a) == 3:
        print(json.dumps(restore(a[1], a[2])))
    elif what == "key":
        print(get_key())
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
