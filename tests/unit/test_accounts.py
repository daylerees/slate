"""scripts/accounts.py: the people on this computer for Settings → Users, through
AccountsService (its D-Bus calls replaced by a pretend AccountsService here), and
scripts/set-avatar.sh setting someone else's picture."""
import ctypes
import ctypes.util
import importlib.util
import io
import os
from contextlib import redirect_stdout
from unittest import mock

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "accounts.py")
AVATAR = slate.path("shell", "scripts", "set-avatar.sh")
ME = os.getuid()


def load_module():
    spec = importlib.util.spec_from_file_location("slate_accounts", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def person(uid, name, real, kind=0, system=False):
    return {"Uid": uid, "UserName": name, "RealName": real, "AccountType": kind,
            "IconFile": f"/nowhere/{name}", "HomeDirectory": f"/home/{name}",
            "Locked": False, "SystemAccount": system}


class PretendAccounts:
    """AccountsService and logind, as accounts.py's call() and logged_in() see them."""
    def __init__(self, mod, people, sessions=(), fail=None):
        self.mod = mod
        self.people = {p["Uid"]: dict(p) for p in people}
        self.sessions = set(sessions)
        self.fail = fail or {}            # method → message, raised as a Problem
        self.calls = []
        self.next_uid = 2000

    def path(self, uid):
        return f"/org/freedesktop/Accounts/User{uid}"

    def uid_of(self, path):
        return int(path.rsplit("User", 1)[1])

    def call(self, conn, path, iface, method, args=None, sig=None, ask=False):
        self.calls.append((method, args, ask))
        if method in self.fail:
            raise self.mod.Problem(self.fail[method])
        if method == "ListCachedUsers":
            return ([self.path(u) for u in self.people if u != ME],)
        if method == "FindUserById":
            if args[0] not in self.people:
                raise self.mod.Problem("That account isn't on this computer anymore")
            return (self.path(args[0]),)
        if method == "GetAll":
            return (self.people[self.uid_of(path)],)
        if method == "CreateUser":
            uid, self.next_uid = self.next_uid, self.next_uid + 1
            self.people[uid] = person(uid, args[0], args[1], args[2])
            return (self.path(uid),)
        if method == "DeleteUser":
            del self.people[args[0]]
            return ()
        user = self.people[self.uid_of(path)]
        if method == "SetRealName":
            user["RealName"] = args[0]
        elif method == "SetAccountType":
            user["AccountType"] = args[0]
        elif method == "SetPassword":
            user["password"] = args[0]
        return ()

    def __enter__(self):
        self.patches = [mock.patch.object(self.mod, "call", self.call),
                        mock.patch.object(self.mod, "bus", lambda: None),
                        mock.patch.object(self.mod, "logged_in", lambda: set(self.sessions))]
        for p in self.patches:
            p.start()
        return self

    def __exit__(self, *exc):
        for p in self.patches:
            p.stop()


class AccountsCase(Case):
    def setUp(self):
        super().setUp()
        self.mod = load_module()

    def everyone(self, me_admin=True):
        return [person(ME, "me", "Me Myself", 1 if me_admin else 0),
                person(1001, "sam", "Sam Lee"),
                person(1002, "robin", "Robin Park", 1),
                person(977, "polkitd", "", system=True)]

    def act(self, *argv, stdin=""):
        """Runs main() as the command line would; returns (exit code, the line it printed)."""
        out = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(stdin)), redirect_stdout(out):
            code = self.mod.main(list(argv))
        return code, out.getvalue().strip()


class Listing(AccountsCase):
    def test_people_only_you_first_then_by_name(self):
        with PretendAccounts(self.mod, self.everyone(), sessions=[ME, 1002]):
            got = self.mod.listing()
        self.assertEqual(got["service"], "on")
        self.assertTrue(got["admin"])
        self.assertEqual([u["username"] for u in got["users"]], ["me", "robin", "sam"])
        robin = got["users"][1]
        self.assertEqual(robin, {"uid": 1002, "username": "robin", "home": "/home/robin", "name": "Robin Park",
                                 "admin": True, "picture": "", "me": False, "loggedIn": True, "locked": False})
        self.assertTrue(got["users"][0]["me"])

    def test_a_standard_account_isnt_an_administrator(self):
        with PretendAccounts(self.mod, self.everyone(me_admin=False)):
            self.assertFalse(self.mod.listing()["admin"])

    def test_no_name_shows_the_username(self):
        people = [person(ME, "me", "")]
        with PretendAccounts(self.mod, people):
            self.assertEqual(self.mod.listing()["users"][0]["name"], "me")

    def test_no_accountsservice(self):
        with PretendAccounts(self.mod, [], fail={"ListCachedUsers": "AccountsService isn't running (install the accountsservice package)"}):
            got = self.mod.listing()
        self.assertEqual(got["service"], "missing")
        self.assertEqual(got["users"], [])


class Adding(AccountsCase):
    def test_adds_with_a_hashed_password_from_stdin(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            code, line = self.act("add", "alex", "Alex Morgan", "admin", stdin="s3cret pass\n")
        self.assertEqual((code, line), (0, "ok"))
        new = pa.people[2000]
        self.assertEqual((new["UserName"], new["RealName"], new["AccountType"]), ("alex", "Alex Morgan", 1))
        hashed = new["password"]
        self.assertNotIn("s3cret", hashed)
        self.assertTrue(hashed.startswith("$"), hashed)
        # The system's own crypt() takes it back to the same hash: the password is right
        lib = ctypes.CDLL(ctypes.util.find_library("crypt"))
        lib.crypt.restype = ctypes.c_char_p
        lib.crypt.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        self.assertEqual(lib.crypt(b"s3cret pass", hashed.encode()).decode(), hashed)
        # Both changes may ask for the password
        self.assertTrue(all(ask for m, _, ask in pa.calls if m in ("CreateUser", "SetPassword")))

    def test_the_password_never_goes_on_the_command_line(self):
        src = slate.read("shell", "settings", "pages", "UsersPage.qml")
        for action in ('"add"', '"password"'):
            line = next(l for l in src.splitlines() if "usersPane.act([" + action in l)
            self.assertNotIn("pw]", line, "the password is in the command's arguments")
            self.assertRegex(line, r"\], .+, pw,", "the password isn't handed in on stdin")

    def test_a_bad_username_is_refused_before_anything_changes(self):
        for bad in ["Sam", "1sam", "sam lee", "sam:x", "", "a" * 33, "-sam"]:
            with self.subTest(bad), PretendAccounts(self.mod, self.everyone()) as pa:
                code, line = self.act("add", bad, "Sam", "standard", stdin="pw\n")
                self.assertEqual(code, 1)
                self.assertTrue(line.startswith("error A username is"), line)
                self.assertEqual([m for m, _, _ in pa.calls], [])

    def test_no_password_is_refused(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            self.assertEqual(self.act("add", "alex", "Alex", "standard", stdin="\n"), (1, "error Choose a password"))
            self.assertNotIn(2000, pa.people)

    def test_a_password_that_wont_set_takes_the_account_away_again(self):
        """An account nobody can log in to isn't left behind."""
        with PretendAccounts(self.mod, self.everyone(), fail={"SetPassword": "canceled"}) as pa:
            self.assertEqual(self.act("add", "alex", "Alex", "standard", stdin="pw\n"), (1, "error canceled"))
        self.assertNotIn(2000, pa.people)
        self.assertIn(("DeleteUser", (2000, True), True), pa.calls)

    def test_a_taken_username(self):
        with PretendAccounts(self.mod, self.everyone(), fail={"CreateUser": "Someone already has that username. Try another"}):
            self.assertEqual(self.act("add", "sam", "Sam", "standard", stdin="pw\n"),
                             (1, "error Someone already has that username. Try another"))


class Changing(AccountsCase):
    def test_remove_keeps_their_files(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            self.assertEqual(self.act("remove", "1001"), (0, "ok"))
        self.assertNotIn(1001, pa.people)
        self.assertIn(("DeleteUser", (1001, False), True), pa.calls)

    def test_you_cant_remove_yourself(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            code, line = self.act("remove", str(ME))
        self.assertEqual(code, 1)
        self.assertIn(ME, pa.people)

    def test_someone_logged_in_isnt_removed(self):
        with PretendAccounts(self.mod, self.everyone(), sessions=[1001]) as pa:
            code, line = self.act("remove", "1001")
        self.assertEqual(code, 1)
        self.assertIn("logged in", line)
        self.assertIn(1001, pa.people)

    def test_the_last_administrator_stays_one(self):
        people = [person(ME, "me", "Me", 1), person(1001, "sam", "Sam")]
        with PretendAccounts(self.mod, people) as pa:
            code, line = self.act("type", str(ME), "standard")
            self.assertEqual(code, 1, line)
            self.assertEqual(pa.people[ME]["AccountType"], 1)
            # With another, it can
            self.assertEqual(self.act("type", "1001", "admin"), (0, "ok"))
            self.assertEqual(self.act("type", str(ME), "standard"), (0, "ok"))
            self.assertEqual(pa.people[ME]["AccountType"], 0)

    def test_name(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            self.assertEqual(self.act("name", "1001", "  Samantha Lee "), (0, "ok"))
            self.assertEqual(pa.people[1001]["RealName"], "Samantha Lee")
            for bad in ["", "   ", "Sam:Lee"]:
                with self.subTest(bad):
                    self.assertEqual(self.act("name", "1001", bad)[0], 1)
            self.assertEqual(pa.people[1001]["RealName"], "Samantha Lee")

    def test_password(self):
        with PretendAccounts(self.mod, self.everyone()) as pa:
            self.assertEqual(self.act("password", "1001", stdin="new one\n"), (0, "ok"))
        self.assertTrue(pa.people[1001]["password"].startswith("$"))

    def test_someone_gone(self):
        with PretendAccounts(self.mod, self.everyone()):
            self.assertEqual(self.act("name", "4242", "X"), (1, "error That account isn't on this computer anymore"))

    def test_errors_in_words(self):
        class E(Exception):
            message = "GDBus.Error:org.freedesktop.Accounts.Error.PermissionDenied: Not authorized"
        with mock.patch.object(self.mod, "Gio_error_name", lambda e: "org.freedesktop.Accounts.Error.PermissionDenied"):
            self.assertEqual(self.mod.explain(E()), "canceled")
        with mock.patch.object(self.mod, "Gio_error_name", lambda e: "org.freedesktop.Accounts.Error.UserExists"):
            self.assertIn("already has that username", self.mod.explain(E()))


class SomeoneElsesPicture(Case):
    """set-avatar.sh <image> <uid>: their picture through AccountsService, not your ~/.face."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("gdbus")
        self.img = os.path.join(self.h.dir, "pic.png")
        from PIL import Image
        Image.new("RGB", (40, 30), "red").save(self.img)
        self.env = self.s.env
        self.face = os.path.join(self.h.home, ".face")

    def said(self):
        return " ".join(" ".join(c) if isinstance(c, list) else str(c) for c in self.s.calls("gdbus"))

    def test_theirs(self):
        code, out = run([AVATAR, "--", self.img, "1001"], env=self.env)
        self.assertEqual(code, 0, out)
        said = self.said()
        self.assertIn("/org/freedesktop/Accounts/User1001", said)
        self.assertIn("--interactive", said)
        self.assertFalse(os.path.exists(self.face), "their picture became your ~/.face")

    def test_yours_still_sets_face(self):
        code, out = run([AVATAR, self.img], env=self.env)
        self.assertEqual(code, 0, out)
        self.assertTrue(os.path.exists(self.face))
        self.assertIn(f"/org/freedesktop/Accounts/User{ME}", self.said())

    def test_a_uid_is_a_number(self):
        code, out = run([AVATAR, "--", self.img, "1001; rm -rf ~"], env=self.env)
        self.assertNotEqual(code, 0)
        self.assertEqual(self.s.calls("gdbus"), [])
