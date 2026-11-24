#!/usr/bin/env python3
"""Your Slate settings in one file, to keep or to take to another computer (Settings → Import &
Export):

  settings-transfer.py export [folder]   write "Slate settings <date>.slate-settings" there (your
                                         Documents folder by default); prints its path
  settings-transfer.py check <file>      whether a file can be imported, and what it holds, as JSON
  settings-transfer.py list              the .slate-settings files in Downloads, Documents, the
                                         Desktop and your home folder, newest first, as JSON
  settings-transfer.py import <file>     put a file's settings in place of yours, keeping yours in
                                         ~/.local/share/slate/backups/import-<date> first; Slate
                                         and Hyprland's config are restarted (your apps stay open)
  settings-transfer.py undo              put back what the last import replaced

A file holds: settings.json, your saved Spaces (spaces.json), your own files (hypr/: your
Hyprland tweaks, and user/: your own QML) and the wallpaper picture, so another computer looks
the same. Workspace names last only a session, so they aren't in it.

Reading a file is careful: only the names above, nothing outside its own folders, no links, and
size limits. Your own files hold code (Hyprland runs hypr/'s Lua, Slate loads user/'s QML), so
Settings asks before importing and says to import only files you made or trust."""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slate_common import replace_private_json  # noqa: E402

SLATE_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
HOME = os.path.expanduser("~")
USER = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "slate")   # Config.userDir
SHARE = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "slate")
SETTINGS = os.path.join(USER, "settings.json")
SPACES = os.path.join(SHARE, "spaces.json")
BACKUPS = os.path.join(SHARE, "backups")
WALLPAPERS = os.path.join(SHARE, "wallpapers")       # where an imported wallpaper picture goes
OWN = ("hypr", "user")                                # your own folders, whole

FORMAT = 1
SUFFIX = ".slate-settings"
MAX_FILE = 300 * 1024 * 1024         # the whole file
MAX_MEMBER = 150 * 1024 * 1024       # any one thing in it (a wallpaper can be big)
MAX_MEMBERS = 5000
PICTURES = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".jxl")


class Refused(Exception):
    """Said in Settings as it is: a whole sentence in Slate's words."""


# ---- export ---------------------------------------------------------------------------------
def user_dir(name):
    try:
        out = subprocess.run(["xdg-user-dir", name], capture_output=True, text=True, timeout=5).stdout.strip()
        if out and out != HOME and os.path.isdir(out):
            return out
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def export(folder=None):
    folder = folder or user_dir("DOCUMENTS") or os.path.join(HOME, "Documents")
    os.makedirs(folder, exist_ok=True)
    settings = read_json(SETTINGS, {})
    if not isinstance(settings, dict):
        settings = {}
    has = ["settings"]
    name = "Slate settings %s" % datetime.date.today().isoformat()
    path = os.path.join(folder, name + SUFFIX)
    n = 2
    while os.path.exists(path):
        path = os.path.join(folder, "%s (%d)%s" % (name, n, SUFFIX))
        n += 1
    tmp = path + ".part"
    try:
        # (yours alone: it holds your settings and your own files)
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as raw, zipfile.ZipFile(raw, "w", zipfile.ZIP_DEFLATED) as z:
            wall = settings.get("wallpaper") or ""
            inside = os.path.realpath(wall).startswith(os.path.realpath(SLATE_DIR) + os.sep) if wall else False
            if wall and inside:
                # One of Slate's own: named, not copied (every Slate has it)
                settings["wallpaper"] = "slate:" + os.path.relpath(os.path.realpath(wall), os.path.realpath(SLATE_DIR))
            elif wall and os.path.isfile(wall) and os.path.getsize(wall) <= MAX_MEMBER:
                z.write(wall, "wallpaper/" + os.path.basename(wall))
                has.append("wallpaper")
            z.writestr("settings.json", json.dumps(settings, indent=1))
            if os.path.isfile(SPACES):
                z.write(SPACES, "spaces.json")
                has.append("spaces")
            for d in OWN:
                top = os.path.join(USER, d)
                if not os.path.isdir(top):
                    continue
                for root, dirs, files in os.walk(top):
                    dirs[:] = sorted(x for x in dirs if not os.path.islink(os.path.join(root, x)))
                    for fn in sorted(files):
                        p = os.path.join(root, fn)
                        if os.path.islink(p) or not os.path.isfile(p):
                            continue
                        z.write(p, os.path.relpath(p, USER))
                has.append(d)
            z.writestr("manifest.json", json.dumps({"format": FORMAT, "made": int(time.time()), "has": has,
                                                     "version": slate_version()}, indent=1))
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    print(path)


def slate_version():
    try:
        with open(os.path.join(SLATE_DIR, "VERSION")) as f:
            return f.read().strip()
    except OSError:
        return ""


# ---- reading a file -------------------------------------------------------------------------
def allowed(name):
    """Whether a member's name is one a file may hold."""
    if name.startswith("/") or "\\" in name or any(part in ("", ".", "..") for part in name.rstrip("/").split("/")):
        return False
    if name in ("manifest.json", "settings.json", "spaces.json"):
        return True
    if name.startswith("wallpaper/"):
        rest = name[len("wallpaper/"):]
        return "/" not in rest and rest.lower().endswith(PICTURES)
    return name.split("/")[0] in OWN and not name.endswith("/")


def open_file(path):
    """The file's zip and manifest, checked; raises Refused."""
    if not path.endswith(SUFFIX) or not os.path.isfile(path):
        raise Refused("Slate couldn't find that settings file.")
    if os.path.getsize(path) > MAX_FILE:
        raise Refused("That file is far bigger than Slate's settings ever are, so Slate didn't open it.")
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        raise Refused("That isn't a Slate settings file Slate can read.")
    infos = [i for i in z.infolist() if not i.is_dir()]
    if len(infos) > MAX_MEMBERS:
        raise Refused("That file holds far more than Slate's settings ever do, so Slate didn't open it.")
    for i in infos:
        mode = (i.external_attr >> 16) & 0o170000
        if not allowed(i.filename) or (mode and mode != 0o100000) or i.file_size > MAX_MEMBER:
            raise Refused("That file holds something other than Slate's settings, so Slate didn't open it.")
    try:
        manifest = json.loads(z.read("manifest.json"))
        settings = json.loads(z.read("settings.json"))
    except (KeyError, ValueError):
        raise Refused("That isn't a Slate settings file Slate can read.")
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT or not isinstance(settings, dict):
        raise Refused("That settings file is from a version of Slate this one can't read.")
    return z, manifest, settings


def listing():
    places = []
    for name, fallback in (("DOWNLOAD", "Downloads"), ("DOCUMENTS", "Documents"), ("DESKTOP", "Desktop")):
        d = user_dir(name) or os.path.join(HOME, fallback)
        if d not in places:
            places.append(d)
    places.append(HOME)
    found = []
    for d in places:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            p = os.path.join(d, n)
            if not n.endswith(SUFFIX) or not os.path.isfile(p) or any(f["path"] == p for f in found):
                continue
            entry = {"path": p, "name": n[:-len(SUFFIX)], "folder": d.replace(HOME, "~", 1), "size": os.path.getsize(p),
                     "modified": int(os.path.getmtime(p))}
            try:
                z, manifest, _ = open_file(p)
                z.close()
                entry.update(made=int(manifest.get("made") or 0), has=[str(h) for h in manifest.get("has", [])][:10],
                             version=str(manifest.get("version", ""))[:40], ok=True)
            except Refused as e:
                entry.update(ok=False, why=str(e))
            found.append(entry)
    found.sort(key=lambda f: f.get("made") or f["modified"], reverse=True)
    print(json.dumps(found))


# ---- import and undo ------------------------------------------------------------------------
def keep_current(kind):
    """What's there now, moved into a dated backup folder (returned)."""
    backup = os.path.join(BACKUPS, "%s-%s" % (kind, time.strftime("%Y-%m-%d-%H%M%S")))
    os.makedirs(backup, mode=0o700)
    for src, name in ((SETTINGS, "settings.json"), (SPACES, "spaces.json")):
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(backup, name))
    for d in OWN:
        if os.path.isdir(os.path.join(USER, d)):
            shutil.copytree(os.path.join(USER, d), os.path.join(backup, d), symlinks=True)
    return backup


def restart_around(apply, title, body):
    """Slate stopped, apply() run, Hyprland's config reloaded (it loads hypr/), Slate started,
    then a notification (Settings, which asked, was restarted too). Under the tests, Slate isn't
    stopped or started (SLATE_TRANSFER_NO_RESTART)."""
    slate = os.path.join(SLATE_DIR, "bin", "slate")
    restart = not os.environ.get("SLATE_TRANSFER_NO_RESTART")
    if restart:
        subprocess.run([slate, "stop"], capture_output=True)
        time.sleep(0.3)
    try:
        apply()
    finally:
        if restart:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            subprocess.run([slate, "start"], capture_output=True)
            time.sleep(3)
            subprocess.run(["notify-send", "-a", "Slate", "-i", os.path.join(SLATE_DIR, "assets", "icon", "icon-64.png"),
                            "-h", "string:x-slate-page:transfer", "--", title, body], capture_output=True)


def replace_own(d, files):
    """Your own folder d (hypr or user) replaced by files ({relative path: bytes})."""
    top = os.path.join(USER, d)
    if os.path.islink(top):
        os.remove(top)
    elif os.path.isdir(top):
        shutil.rmtree(top)
    for rel, data in files.items():
        p = os.path.join(top, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)


def import_file(path):
    z, manifest, settings = open_file(path)
    # Read whole before anything changes: a broken file changes nothing
    own = {d: {} for d in OWN}
    wallpaper = None
    spaces = None
    for i in z.infolist():
        if i.is_dir():
            continue
        top = i.filename.split("/")[0]
        if top in OWN:
            own[top][i.filename[len(top) + 1:]] = z.read(i)
        elif top == "wallpaper":
            wallpaper = (os.path.basename(i.filename), z.read(i))
        elif i.filename == "spaces.json":
            try:
                spaces = json.loads(z.read(i))
            except ValueError:
                raise Refused("That settings file's saved Spaces couldn't be read, so nothing was changed.")
    has = manifest.get("has", [])
    wall = settings.get("wallpaper") or ""
    if wall.startswith("slate:"):
        mine = os.path.realpath(os.path.join(SLATE_DIR, wall[len("slate:"):]))
        settings["wallpaper"] = mine if mine.startswith(os.path.realpath(SLATE_DIR) + os.sep) and os.path.isfile(mine) else ""
    backup = keep_current("import")
    with open(os.path.join(backup, "imported-from.txt"), "w") as f:
        f.write(path + "\n")

    def apply():
        if wallpaper:
            os.makedirs(WALLPAPERS, exist_ok=True)
            dest = os.path.join(WALLPAPERS, wallpaper[0])
            with open(dest, "wb") as f:
                f.write(wallpaper[1])
            settings["wallpaper"] = dest
        elif wall and not wall.startswith("slate:") and not os.path.isfile(wall):
            settings["wallpaper"] = ""          # (a picture that isn't on this computer: Slate's default)
        replace_private_json(SETTINGS, settings)
        if spaces is not None:
            replace_private_json(SPACES, spaces)
        for d in OWN:
            if d in has:
                replace_own(d, own[d])
    restart_around(apply, "Settings imported",
                   "Your apps and windows stayed open. Yours from before are kept, and Settings → Import & Export can put them back.")
    print(json.dumps({"backup": backup}))


def undo():
    """The last import's backup put back (itself kept, as the next import or a factory reset is)."""
    try:
        last = sorted(n for n in os.listdir(BACKUPS) if n.startswith("import-"))[-1]
    except (OSError, IndexError):
        raise Refused("There's no import to undo.")
    backup = os.path.join(BACKUPS, last)

    def apply():
        for src, dest in ((os.path.join(backup, "settings.json"), SETTINGS), (os.path.join(backup, "spaces.json"), SPACES)):
            if os.path.exists(src):
                replace_private_json(dest, read_json(src, {}))
            elif os.path.exists(dest):
                os.remove(dest)
        for d in OWN:
            top, saved = os.path.join(USER, d), os.path.join(backup, d)
            if os.path.isdir(saved):
                if os.path.isdir(top) and not os.path.islink(top):
                    shutil.rmtree(top)
                elif os.path.lexists(top):
                    os.remove(top)
                shutil.copytree(saved, top, symlinks=True)
    restart_around(apply, "Your settings are back", "Slate is as it was before the import. Your apps and windows stayed open.")
    os.rename(backup, backup.replace("/import-", "/undone-import-", 1))
    print(json.dumps({"undone": backup}))


def main():
    args = sys.argv[1:]
    try:
        if args[:1] == ["export"] and len(args) <= 2:
            export(args[1] if len(args) == 2 else None)
        elif args == ["list"]:
            listing()
        elif args[:1] == ["check"] and len(args) == 2:
            z, manifest, _ = open_file(os.path.abspath(args[1]))
            z.close()
            print(json.dumps({"has": [str(h) for h in manifest.get("has", [])][:10], "made": int(manifest.get("made") or 0),
                              "version": str(manifest.get("version", ""))[:40]}))
        elif args[:1] == ["import"] and len(args) == 2:
            import_file(os.path.abspath(args[1]))
        elif args == ["undo"]:
            undo()
        elif args == ["last"]:
            # (the import that could be undone, for Settings: its backup folder and when, or nothing)
            try:
                last = sorted(n for n in os.listdir(BACKUPS) if n.startswith("import-"))[-1]
                print(json.dumps({"backup": os.path.join(BACKUPS, last), "when": int(os.path.getmtime(os.path.join(BACKUPS, last)))}))
            except (OSError, IndexError):
                print("{}")
        else:
            sys.exit(__doc__)
    except Refused as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
