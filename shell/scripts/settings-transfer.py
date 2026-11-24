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
import hashlib
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
# The dock's pinned apps (Dock.qml keeps them in ~/.local/state on purpose, whatever XDG_STATE_HOME says)
DOCK = os.path.join(HOME, ".local", "state", "slate", "dock.json")
BACKUPS = os.path.join(SHARE, "backups")
WALLPAPERS = os.path.join(SHARE, "wallpapers")       # where an imported wallpaper picture goes
OWN = ("hypr", "user")                                # your own folders, whole

FORMAT = 1
SUFFIX = ".slate-settings"
MAX_FILE = 300 * 1024 * 1024         # the whole file
MAX_MEMBER = 150 * 1024 * 1024       # any one thing in it (a wallpaper can be big)
MAX_MEMBERS = 5000
MAX_TOTAL = 300 * 1024 * 1024        # everything in it, unpacked
MAX_SMALL = 4 * 1024 * 1024          # manifest, settings, Spaces, the dock's pins
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
    # What goes in, checked first against the same rules import keeps to: a file this computer
    # can't read back is never written. Hidden files (a .git folder, an editor's swap file) and
    # backups (name~) are left out
    files = []
    for d in OWN:
        top = os.path.join(USER, d)
        if not os.path.isdir(top):
            continue
        for root, dirs, names in os.walk(top):
            dirs[:] = sorted(x for x in dirs if not x.startswith(".") and not os.path.islink(os.path.join(root, x)))
            for fn in sorted(names):
                p = os.path.join(root, fn)
                if fn.startswith(".") or fn.endswith("~") or os.path.islink(p) or not os.path.isfile(p):
                    continue
                files.append((p, os.path.relpath(p, USER)))
    wall = settings.get("wallpaper") or ""
    inside = os.path.realpath(wall).startswith(os.path.realpath(SLATE_DIR) + os.sep) if wall else False
    picture = wall if wall and not inside and os.path.isfile(wall) and os.path.getsize(wall) <= MAX_MEMBER \
        and wall.lower().endswith(PICTURES) else ""
    entries = [(rel, os.path.getsize(p)) for p, rel in files] + [("settings.json", 0)]
    if picture:
        entries.append(("wallpaper/" + os.path.basename(picture), os.path.getsize(picture)))
    for src, name in ((SPACES, "spaces.json"), (DOCK, "dock.json")):
        if os.path.isfile(src):
            entries.append((name, os.path.getsize(src)))
    try:
        check_members(entries)
    except Refused as e:
        raise Refused("Slate couldn't fit your settings in one file. " + str(e) + " Your own folders (hypr/ and user/) "
                      "may hold something big or a great many files.")
    tmp = path + ".part"
    try:
        # (yours alone: it holds your settings and your own files)
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as raw, zipfile.ZipFile(raw, "w", zipfile.ZIP_DEFLATED) as z:
            if wall and inside:
                # One of Slate's own: named, not copied (every Slate has it)
                settings["wallpaper"] = "slate:" + os.path.relpath(os.path.realpath(wall), os.path.realpath(SLATE_DIR))
            elif picture:
                z.write(picture, "wallpaper/" + os.path.basename(picture))
                has.append("wallpaper")
            z.writestr("settings.json", json.dumps(settings, indent=1))
            for src, name, what in ((SPACES, "spaces.json", "spaces"), (DOCK, "dock.json", "dock")):
                if os.path.isfile(src):
                    z.write(src, name)
                    has.append(what)
            for p, rel in files:
                z.write(p, rel)
            for d in OWN:
                if os.path.isdir(os.path.join(USER, d)):
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
SMALL = ("manifest.json", "settings.json", "spaces.json", "dock.json")


def allowed(name):
    """Whether a member's name is one a file may hold: the small files, one wallpaper picture,
    and files inside your own folders (never the folder name alone)."""
    if name.startswith("/") or "\\" in name or any(part in ("", ".", "..") for part in name.split("/")):
        return False
    if name in SMALL:
        return True
    if name.startswith("wallpaper/"):
        rest = name[len("wallpaper/"):]
        return "/" not in rest and rest.lower().endswith(PICTURES)
    top, _, rest = name.partition("/")
    return top in OWN and rest != ""


def check_members(entries):
    """entries: (name, size) for everything to go in or come out of a file. Raises Refused for
    anything a settings file can't hold, so export and import keep to the same rules."""
    if len(entries) > MAX_MEMBERS:
        raise Refused("That's far more files than Slate's settings ever hold.")
    total = 0
    names = set()
    for name, size in entries:
        if not allowed(name):
            raise Refused("That holds something other than Slate's settings.")
        if size > (MAX_SMALL if name in SMALL else MAX_MEMBER):
            raise Refused("Something in it is far bigger than Slate's settings ever are.")
        total += size
        names.add(name)
    if total > MAX_TOTAL:
        raise Refused("It's far bigger than Slate's settings ever are.")
    # (a name that's both a file and a folder of others can't be put in place)
    for name in names:
        parts = name.split("/")
        if any("/".join(parts[:i]) in names for i in range(1, len(parts))):
            raise Refused("That holds something other than Slate's settings.")


def open_file(path):
    """The file's zip, manifest, settings and Spaces, checked; raises Refused."""
    if not path.endswith(SUFFIX) or not os.path.isfile(path):
        raise Refused("Slate couldn't find that settings file. It may have been moved or deleted.")
    if os.path.getsize(path) > MAX_FILE:
        raise Refused("That file is far bigger than Slate's settings ever are, so Slate didn't open it.")
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        raise Refused("That isn't a Slate settings file Slate can read.")
    infos = [i for i in z.infolist() if not i.is_dir()]
    for i in infos:
        mode = (i.external_attr >> 16) & 0o170000
        if mode and mode != 0o100000:
            z.close()
            raise Refused("That file holds something other than Slate's settings, so Slate didn't open it.")
    try:
        check_members([(i.filename, i.file_size) for i in infos])
    except Refused as e:
        z.close()
        raise Refused(str(e) + " So Slate didn't open that file.")
    try:
        manifest = json.loads(z.read("manifest.json"))
        settings = json.loads(z.read("settings.json"))
        names = {i.filename for i in infos}
        spaces = json.loads(z.read("spaces.json")) if "spaces.json" in names else None
        dock = json.loads(z.read("dock.json")) if "dock.json" in names else None
    except (KeyError, ValueError, zipfile.BadZipFile):
        z.close()
        raise Refused("That isn't a Slate settings file Slate can read.")
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT or not isinstance(settings, dict) \
            or (spaces is not None and not isinstance(spaces, dict)) or (dock is not None and not isinstance(dock, dict)):
        z.close()
        raise Refused("That settings file is from a version of Slate this one can't read.")
    return z, manifest, settings, spaces, dock


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
                z, manifest, _, _, _ = open_file(p)
                z.close()
                entry.update(made=int(manifest.get("made") or 0), has=[str(h) for h in manifest.get("has", [])][:10],
                             version=str(manifest.get("version", ""))[:40], ok=True)
            except Refused as e:
                entry.update(ok=False, why=str(e))
            found.append(entry)
    found.sort(key=lambda f: f.get("made") or f["modified"], reverse=True)
    print(json.dumps(found))


# ---- import and undo ------------------------------------------------------------------------
def notify(title, body):
    """Said in a notification: Settings, which asked, may have restarted (or is waiting), so
    nothing else would show it. Not under the tests."""
    if os.environ.get("SLATE_TRANSFER_NO_RESTART"):
        return
    subprocess.run(["notify-send", "-a", "Slate", "-i", os.path.join(SLATE_DIR, "assets", "icon", "icon-64.png"),
                    "-h", "string:x-slate-page:transfer", "--", title, body], capture_output=True)


def own_state(d):
    """How your own folder d stands: "dir", "link:<target>" or "none"."""
    top = os.path.join(USER, d)
    if os.path.islink(top):
        return "link:" + os.readlink(top)
    return "dir" if os.path.isdir(top) else "none"


def keep_current(kind):
    """What's there now, copied into a new backup folder (returned), with before.json saying
    how your own folders stood, so putting it back restores exactly that."""
    stamp = time.strftime("%Y-%m-%d-%H%M%S")
    backup = os.path.join(BACKUPS, "%s-%s" % (kind, stamp))
    n = 2
    while os.path.lexists(backup):
        backup = os.path.join(BACKUPS, "%s-%s-%d" % (kind, stamp, n))
        n += 1
    os.makedirs(BACKUPS, mode=0o700, exist_ok=True)
    os.mkdir(backup, 0o700)
    for src, name in ((SETTINGS, "settings.json"), (SPACES, "spaces.json"), (DOCK, "dock.json")):
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(backup, name))
    before = {}
    for d in OWN:
        before[d] = own_state(d)
        if before[d] == "dir":
            shutil.copytree(os.path.join(USER, d), os.path.join(backup, d), symlinks=True)
    with open(os.path.join(backup, "before.json"), "w") as f:
        json.dump({"own": before}, f)
    return backup


def put_back(backup):
    """Everything in backup put back as it was: the files, and your own folders as they stood
    (a folder, a link to one, or none at all)."""
    for name, dest in (("settings.json", SETTINGS), ("spaces.json", SPACES), ("dock.json", DOCK)):
        src = os.path.join(backup, name)
        remove_path(dest)
        if os.path.isfile(src):
            replace_private_json(dest, read_json(src, {}))
    before = read_json(os.path.join(backup, "before.json"), {}).get("own", {})
    for d in OWN:
        top = os.path.join(USER, d)
        state = before.get(d, "dir" if os.path.isdir(os.path.join(backup, d)) else "none")
        remove_path(top)
        if state.startswith("link:"):
            os.symlink(state[len("link:"):], top)
        elif state == "dir" and os.path.isdir(os.path.join(backup, d)):
            shutil.copytree(os.path.join(backup, d), top, symlinks=True)


def remove_path(p):
    if os.path.islink(p) or os.path.isfile(p):
        os.remove(p)
    elif os.path.isdir(p):
        shutil.rmtree(p)


def restarted(apply, rollback):
    """Slate stopped, apply() run (and on any failure, rollback() run), Hyprland's config
    reloaded (it loads hypr/), Slate started again. Returns whether apply() worked. Under the
    tests, Slate isn't stopped or started (SLATE_TRANSFER_NO_RESTART)."""
    slate = os.path.join(SLATE_DIR, "bin", "slate")
    restart = not os.environ.get("SLATE_TRANSFER_NO_RESTART")
    if restart:
        subprocess.run([slate, "stop"], capture_output=True)
        time.sleep(0.3)
    ok = True
    try:
        apply()
    except Exception as e:  # (anything at all: what was there goes back)
        ok = False
        print("settings-transfer: %s" % e, file=sys.stderr)
        rollback()
    finally:
        if restart:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            subprocess.run([slate, "start"], capture_output=True)
            time.sleep(3)
    return ok


def import_file(path):
    z, manifest, settings, spaces, dock = open_file(path)
    has = [h for h in manifest.get("has", []) if isinstance(h, str)]
    wall = settings.get("wallpaper") or ""
    if wall.startswith("slate:"):
        mine = os.path.realpath(os.path.join(SLATE_DIR, wall[len("slate:"):]))
        settings["wallpaper"] = mine if mine.startswith(os.path.realpath(SLATE_DIR) + os.sep) and os.path.isfile(mine) else ""
    elif wall and not os.path.isfile(wall):
        settings["wallpaper"] = ""              # (a picture that isn't on this computer: Slate's default)
    # Your own folders and the picture, unpacked beside where they go before anything changes:
    # a file that can't be unpacked changes nothing
    stage = os.path.join(USER, ".import-%d" % os.getpid())
    remove_path(stage)
    os.makedirs(stage, mode=0o700)
    try:
        wallpaper = None
        for i in z.infolist():
            if i.is_dir():
                continue
            top = i.filename.split("/")[0]
            if top in OWN and top in has:
                dest = os.path.join(stage, i.filename)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with z.open(i) as src, open(dest, "wb") as out:
                    shutil.copyfileobj(src, out)
                # (a script stays one: run by Hyprland's exec lines, say)
                os.chmod(dest, 0o755 if (i.external_attr >> 16) & 0o111 else 0o644)
            elif top == "wallpaper":
                with z.open(i) as src:
                    data = src.read()
                ext = os.path.splitext(i.filename)[1].lower()
                # (named by what's in it: an earlier import's picture is never overwritten)
                wallpaper = ("imported-%s%s" % (hashlib.sha256(data).hexdigest()[:16], ext), data)
        z.close()
        backup = keep_current("import")
        with open(os.path.join(backup, "imported-from.txt"), "w") as f:
            f.write(path + "\n")

        def apply():
            if wallpaper:
                os.makedirs(WALLPAPERS, exist_ok=True)
                dest = os.path.join(WALLPAPERS, wallpaper[0])
                if not os.path.exists(dest):
                    with open(dest, "wb") as f:
                        f.write(wallpaper[1])
                settings["wallpaper"] = dest
            replace_private_json(SETTINGS, settings)
            if spaces is not None:
                replace_private_json(SPACES, spaces)
            if dock is not None:
                replace_private_json(DOCK, dock)
            for d in OWN:
                if d in has:
                    remove_path(os.path.join(USER, d))
                    staged = os.path.join(stage, d)
                    if os.path.isdir(staged):
                        os.rename(staged, os.path.join(USER, d))
                    else:
                        os.makedirs(os.path.join(USER, d))
                    # (the tests: an import that fails halfway, to see everything put back)
                    if os.environ.get("SLATE_TRANSFER_TEST_FAIL") == d:
                        raise OSError("the tests' failure, after " + d)
        ok = restarted(apply, lambda: put_back(backup))
    finally:
        remove_path(stage)
    if ok:
        notify("Settings imported", "Your apps and windows stayed open. The settings you had before are kept, "
               "and Settings → Import & Export can put them back.")
        print(json.dumps({"backup": backup}))
    else:
        os.rename(backup, backup.replace("/import-", "/failed-import-", 1))
        notify("Slate couldn't import those settings", "Yours are back just as they were, and your apps and windows "
               "stayed open. The file may be damaged; try exporting it again.")
        raise Refused("Slate couldn't import those settings, so yours were put back as they were.")


def imports():
    """The import backups, oldest first, done or undone: (name, undone)."""
    try:
        names = os.listdir(BACKUPS)
    except OSError:
        return []
    found = [(n, n.startswith("undone-")) for n in names if n.startswith("import-") or n.startswith("undone-import-")]
    return sorted(found, key=lambda x: x[0].split("import-", 1)[1])


def undoable():
    """The import that can be undone: the newest, if it hasn't been already (None otherwise)."""
    found = imports()
    return found[-1][0] if found and not found[-1][1] else None


def undo():
    last = undoable()
    if not last:
        raise Refused("There's no import to undo.")
    backup = os.path.join(BACKUPS, last)
    undone = keep_current("before-undo")        # (in case putting it back goes wrong)
    ok = restarted(lambda: put_back(backup), lambda: put_back(undone))
    if not ok:
        notify("Slate couldn't put your settings back", "Nothing changed, and your apps and windows stayed open. "
               "Your earlier settings are still kept in ~/.local/share/slate/backups.")
        raise Refused("Slate couldn't put your settings back, so nothing changed.")
    remove_path(undone)
    os.rename(backup, os.path.join(BACKUPS, "undone-" + last))
    notify("Your settings are back", "Slate is as it was before the import. Your apps and windows stayed open.")
    print(json.dumps({"undone": backup}))


def main():
    args = sys.argv[1:]
    try:
        if args[:1] == ["export"] and len(args) <= 2:
            export(args[1] if len(args) == 2 else None)
        elif args == ["list"]:
            listing()
        elif args[:1] == ["check"] and len(args) == 2:
            z, manifest, _, _, _ = open_file(os.path.abspath(args[1]))
            z.close()
            print(json.dumps({"has": [str(h) for h in manifest.get("has", [])][:10], "made": int(manifest.get("made") or 0),
                              "version": str(manifest.get("version", ""))[:40]}))
        elif args[:1] == ["import"] and len(args) == 2:
            import_file(os.path.abspath(args[1]))
        elif args == ["undo"]:
            undo()
        elif args == ["last"]:
            # (the import that can be undone, for Settings: its backup folder and when, or nothing)
            last = undoable()
            print(json.dumps({"backup": os.path.join(BACKUPS, last), "when": int(os.path.getmtime(os.path.join(BACKUPS, last)))}
                             if last else {}))
        else:
            sys.exit(__doc__)
    except Refused as e:
        say(args, str(e))
        sys.exit(1)
    except Exception as e:  # (an import or undo that failed before changing anything)
        say(args, "Something went wrong reading or saving the files (%s)." % type(e).__name__)
        raise


def say(args, why):
    """A refusal or failure, said: printed, and for an import or undo (which run on their own,
    after Settings asked, so nobody reads what's printed) as a notification too, unless the
    import or undo already sent its own."""
    print(why, file=sys.stderr)
    if args[:1] == ["import"] and "couldn't import those settings" not in why:
        notify("Slate didn't import that file", why + " Your settings are just as they were.")
    elif args == ["undo"] and "couldn't put your settings back" not in why:
        notify("Nothing was put back", why)


if __name__ == "__main__":
    main()
