#!/usr/bin/env python3
"""The people on this computer, for Settings → Users.

Usage:
  accounts.py list                      the accounts, as JSON (below)
  accounts.py add <username> <name> <standard|admin>
                                        add an account; its password is read from stdin
  accounts.py remove <uid> [keep|delete]
                                        remove an account; its home folder is kept unless
                                        "delete" (then it and everything in it goes)
  accounts.py name <uid> <name>         change an account's full name
  accounts.py type <uid> <standard|admin>
  accounts.py password <uid>            set an account's password, read from stdin
  accounts.py picture <uid> <image>     set an account's picture (yours: scripts/set-avatar.sh)

Everything goes through AccountsService (org.freedesktop.Accounts) over D-Bus, the same on
every distro; polkit asks for an administrator's password where it's needed (Slate's own
password card). Nothing here runs as root or writes /etc/passwd. Passwords never go on the
command line (anyone can read that): they come in on stdin and are hashed here, with the
system's own libcrypt, before AccountsService sees them.

list prints {"service": "on"|"missing", "me": <your uid>, "admin": <you're an administrator>,
"users": [{uid, username, home, name, admin, picture, me, loggedIn, locked}]}, people only (no
system accounts), you first, then by name.
Actions print one line: "ok", or "error <message>" in words for people ("error canceled" when
the password prompt was closed).
"""
import ctypes
import ctypes.util
import json
import os
import re
import secrets
import subprocess
import sys

NAME = "org.freedesktop.Accounts"
PATH = "/org/freedesktop/Accounts"
USER = "org.freedesktop.Accounts.User"
# Long enough for someone to type their password into the prompt
PROMPT_MS = 300_000
# The usernames Linux accepts everywhere (useradd's default rule, lower case only)
USERNAME = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
ACCOUNT_TYPES = {"standard": 0, "admin": 1}
HERE = os.path.dirname(os.path.abspath(__file__))


class Problem(Exception):
    """Something to tell the person, in their words."""


def bus():
    from gi.repository import Gio
    return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def call(conn, path, iface, method, args=None, sig=None, ask=False):
    """One D-Bus call to AccountsService; ask: may show the password prompt."""
    from gi.repository import Gio, GLib
    flags = Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION if ask else Gio.DBusCallFlags.NONE
    variant = GLib.Variant(sig, args) if sig else None
    try:
        r = conn.call_sync(NAME, path, iface, method, variant, None, flags,
                           PROMPT_MS if ask else 10_000, None)
    except GLib.Error as e:
        raise Problem(explain(e)) from None
    return r.unpack() if r is not None else ()


def explain(e):
    """A D-Bus error from AccountsService or polkit, in words."""
    name = Gio_error_name(e)
    msg = str(getattr(e, "message", e))
    if name.endswith("UserExists"):
        return "Someone already has that username. Try another"
    if name.endswith("UserDoesNotExist"):
        return "That account isn't on this computer anymore"
    if name.endswith("PermissionDenied") or "not authorized" in msg.lower():
        # polkit says the same thing for a closed prompt and a refusal; Slate's card was
        # closed in nearly every case
        return "canceled"
    if name.endswith("ServiceUnknown") or name.endswith("NameHasNoOwner"):
        return "AccountsService isn't running (install the accountsservice package)"
    return "AccountsService said: " + msg.split(":", 2)[-1].strip()


def Gio_error_name(e):
    try:
        from gi.repository import Gio
        return Gio.DBusError.get_remote_error(e) or ""
    except Exception:
        return ""


def user_path(conn, uid):
    return call(conn, PATH, "org.freedesktop.Accounts", "FindUserById", (int(uid),), "(x)")[0]


def props(conn, path):
    from gi.repository import GLib  # noqa: F401  (unpack needs it loaded)
    return call(conn, path, "org.freedesktop.DBus.Properties", "GetAll", (USER,), "(s)")[0]


def logged_in():
    """The uids with a session open (logind), so they can't be removed from under it."""
    try:
        from gi.repository import Gio, GLib
        conn = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        r = conn.call_sync("org.freedesktop.login1", "/org/freedesktop/login1",
                           "org.freedesktop.login1.Manager", "ListUsers", None, None,
                           Gio.DBusCallFlags.NONE, 5000, None)
        return {int(u[0]) for u in r.unpack()[0]}
    except Exception:
        return set()


def picture(p):
    """The account's picture, if it has one (AccountsService names a file even when it
    isn't there)."""
    f = p.get("IconFile") or ""
    return f if f and os.path.isfile(f) else ""


def listing():
    me = os.getuid()
    try:
        conn = bus()
        paths = call(conn, PATH, "org.freedesktop.Accounts", "ListCachedUsers")[0]
        # (yours too, even if AccountsService hasn't cached it yet)
        mine = user_path(conn, me)
        if mine not in paths:
            paths = [mine] + list(paths)
        people = [props(conn, p) for p in paths]
    except Problem as e:
        return {"service": "missing", "why": str(e), "me": me, "admin": False, "users": []}
    except Exception:
        return {"service": "missing", "me": me, "admin": False, "users": []}
    sessions = logged_in()
    users = []
    for p in people:
        if p.get("SystemAccount"):
            continue
        uid = int(p.get("Uid", -1))
        users.append({
            "uid": uid,
            "username": p.get("UserName", ""),
            "home": p.get("HomeDirectory", ""),
            "name": p.get("RealName", "") or p.get("UserName", ""),
            "admin": p.get("AccountType", 0) == 1,
            "picture": picture(p),
            "me": uid == me,
            "loggedIn": uid in sessions,
            "locked": bool(p.get("Locked")),
        })
    users.sort(key=lambda u: (not u["me"], u["name"].lower()))
    admin = any(u["me"] and u["admin"] for u in users)
    return {"service": "on", "me": me, "admin": admin, "users": users}


def hash_password(password):
    """password, hashed the way this system's own passwd would (libcrypt's preferred method,
    yescrypt or SHA-512), for AccountsService's SetPassword."""
    name = ctypes.util.find_library("crypt")
    if not name:
        raise Problem("Slate couldn't find the system's password library (libcrypt)")
    lib = ctypes.CDLL(name)
    lib.crypt.restype = ctypes.c_char_p
    lib.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    salt = None
    if hasattr(lib, "crypt_gensalt"):          # libxcrypt: its own best method, its own salt
        lib.crypt_gensalt.restype = ctypes.c_char_p
        lib.crypt_gensalt.argtypes = [ctypes.c_char_p, ctypes.c_ulong, ctypes.c_char_p, ctypes.c_int]
        salt = lib.crypt_gensalt(None, 0, None, 0)
    if not salt:                               # an older libcrypt: SHA-512
        chars = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        salt = ("$6$" + "".join(secrets.choice(chars) for _ in range(16))).encode()
    hashed = lib.crypt(password.encode(), salt)
    if not hashed or hashed.startswith(b"*"):
        raise Problem("Slate couldn't secure that password")
    return hashed.decode()


def read_password():
    """The password, from stdin (one line; a trailing newline isn't part of it)."""
    pw = sys.stdin.readline()
    if pw.endswith("\n"):
        pw = pw[:-1]
    if not pw:
        raise Problem("Choose a password")
    return pw


def account_type(word):
    if word not in ACCOUNT_TYPES:
        raise Problem("The account type is standard or admin")
    return ACCOUNT_TYPES[word]


def check_username(username):
    if not USERNAME.match(username):
        raise Problem("A username is lower case letters, numbers, - and _, starting with a letter")
    return username


def add(username, name, kind):
    check_username(username)
    kind = account_type(kind)
    password = hash_password(read_password())
    conn = bus()
    path = call(conn, PATH, "org.freedesktop.Accounts", "CreateUser",
                (username, name, kind), "(ssi)", ask=True)[0]
    # A new account can't log in until it has a password. If setting it fails, take the
    # account away again rather than leave one nobody can use
    try:
        call(conn, path, USER, "SetPassword", (password, ""), "(ss)", ask=True)
    except Problem:
        try:
            uid = props(conn, path).get("Uid")
            call(conn, PATH, "org.freedesktop.Accounts", "DeleteUser", (int(uid), True), "(xb)", ask=True)
        except Exception:
            pass
        raise


def remove(uid, files="keep"):
    if files not in ("keep", "delete"):
        raise Problem("Say whether to keep their files or delete them")
    uid = int(uid)
    if uid == os.getuid():
        raise Problem("You can't remove your own account while you're using it")
    if uid in logged_in():
        raise Problem("They're logged in right now. Once they log out, you can remove them")
    conn = bus()
    user_path(conn, uid)                        # (still there?)
    # Their home folder is kept unless asked: nothing they made is lost by accident
    call(conn, PATH, "org.freedesktop.Accounts", "DeleteUser", (uid, files == "delete"), "(xb)", ask=True)


def admins(conn):
    return [u for u in listing()["users"] if u["admin"]]


def set_type(uid, kind):
    kind = account_type(kind)
    conn = bus()
    if kind == 0:
        others = [u for u in admins(conn) if u["uid"] != int(uid)]
        if not others:
            raise Problem("Someone has to be an administrator, and they're the only one")
    call(conn, user_path(conn, uid), USER, "SetAccountType", (kind,), "(i)", ask=True)


def set_name(uid, name):
    name = name.strip()
    if not name:
        raise Problem("Type a name")
    if any(c in name for c in ":\n"):
        raise Problem("A name can't have a colon in it")
    conn = bus()
    call(conn, user_path(conn, uid), USER, "SetRealName", (name,), "(s)", ask=True)


def set_password(uid):
    password = hash_password(read_password())
    conn = bus()
    call(conn, user_path(conn, uid), USER, "SetPassword", (password, ""), "(ss)", ask=True)


def set_picture(uid, image):
    """Cropped and saved by set-avatar.sh, the same as your own picture."""
    r = subprocess.run([os.path.join(HERE, "set-avatar.sh"), "--", image, str(int(uid))],
                       capture_output=True, text=True)
    if r.returncode != 0:
        msg = (r.stderr.strip().splitlines() or ["Slate couldn't change the picture"])[-1]
        raise Problem("canceled" if "canceled" in msg else msg)


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    what, args = argv[0], argv[1:]
    if what == "list":
        print(json.dumps(listing()))
        return 0
    # (each action and how many arguments it takes)
    actions = {"add": (add, (3,)), "remove": (remove, (1, 2)), "name": (set_name, (2,)),
               "type": (set_type, (2,)), "password": (set_password, (1,)), "picture": (set_picture, (2,))}
    if what not in actions or len(args) not in actions[what][1]:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        actions[what][0](*args)
    except Problem as e:
        print("error " + str(e))
        return 1
    except ValueError:
        print("error That account isn't on this computer anymore")
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
