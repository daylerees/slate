"""bin/slate-unlock: which of a face, a fingerprint and a key the lock screen takes, kept in
Slate's own PAM service, /etc/pam.d/slate-lock. Run as root (a stand-in `id` says so) from a
scratch copy of /usr/local/libexec/slate, with a scratch pam.d and a scratch folder of PAM
modules: nothing on the computer is touched."""
import os
import stat

import slate
from slate import Case, run
from stubs import Stubs

HELPER = slate.path("shell", "bin", "slate-unlock")
DIRS = ("/usr/lib/security /usr/lib64/security /lib/security /lib64/security \\\n"
        "             /usr/lib/x86_64-linux-gnu/security /lib/x86_64-linux-gnu/security /usr/lib/aarch64-linux-gnu/security")


class Unlock(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.target = os.path.join(self.h.dir, "libexec", "slate")
        self.pamd = os.path.join(self.h.dir, "pam.d")
        self.mods = os.path.join(self.h.dir, "security")
        for d in (self.target, self.pamd, self.mods):
            os.makedirs(d)
        src = slate.read("shell", "bin", "slate-unlock")
        # (and the security keys' list: never the real one, even for remove)
        self.keys = os.path.join(self.h.dir, "etc-slate", "u2f_keys")
        for real in ("TARGET_DIR=/usr/local/libexec/slate", "PAMD=/etc/pam.d", DIRS, "KEYS=/etc/slate/u2f_keys"):
            self.assertIn(real, src)
        src = (src.replace("/usr/local/libexec/slate", self.target).replace("PAMD=/etc/pam.d", f"PAMD={self.pamd}")
                  .replace(DIRS, self.mods).replace("KEYS=/etc/slate/u2f_keys", f"KEYS={self.keys}"))
        self.helper = os.path.join(self.target, "slate-unlock")
        with open(self.helper, "w") as f:
            f.write(src)
        os.chmod(self.helper, 0o755)
        self.s.add("id", by_args={"-u": "0\n", "": "root\n"})
        self.s.add("chown", stdout="")             # (root's already, for real)
        self.file = os.path.join(self.pamd, "slate-lock")
        # Something else's service beside it, which must never change
        self.login = os.path.join(self.pamd, "login")
        with open(self.login, "w") as f:
            f.write("auth include system-local-login\n")

    def installed(self, *names):
        for n in names:
            p = os.path.join(self.mods, n)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").close()

    def go(self, *args, path=None, env=None):
        return run([path or self.helper, *args], env=dict(self.s.env, **(env or {})))

    def text(self):
        with open(self.file) as f:
            return f.read()

    def auth_lines(self):
        return [l.split(None, 2)[2] for l in self.text().splitlines() if l.startswith("auth")]

    def test_a_method_on(self):
        self.installed("pam_howdy.so")
        code, out = self.go("enable", "face")
        self.assertEqual(code, 0, out)
        self.assertEqual(self.auth_lines(), ["pam_howdy.so", "pam_deny.so"])
        self.assertIn("auth       sufficient   pam_howdy.so", self.text())
        self.assertIn("account    include      login", self.text())
        self.assertEqual(self.go("status")[1], "face\n")
        self.assertEqual(stat.S_IMODE(os.stat(self.file).st_mode), 0o644)

    def test_howdy_2_through_pam_python(self):
        self.installed("howdy/pam.py")
        self.assertEqual(self.go("enable", "face")[0], 0)
        self.assertEqual(self.auth_lines()[0], f"pam_python.so {self.mods}/howdy/pam.py")

    def test_the_password_is_never_in_it(self):
        """Only the methods, then pam_deny: the password is the lock screen's other
        conversation, through `login`, so nothing here can stand in for it or lock you out."""
        self.installed("pam_howdy.so", "pam_fprintd.so", "pam_u2f.so")
        for m in ("key", "face", "fingerprint"):
            self.go("enable", m)
        text = self.text()
        self.assertNotIn("pam_unix", text)
        self.assertNotIn("include      login\nauth", text)
        self.assertEqual([l.split()[1] for l in text.splitlines() if l.startswith("auth")],
                         ["sufficient", "sufficient", "sufficient", "required"])

    def test_always_the_same_order_and_each_once(self):
        self.installed("pam_howdy.so", "pam_fprintd.so", "pam_u2f.so")
        for m in ("key", "face", "key", "fingerprint", "face"):
            self.assertEqual(self.go("enable", m)[0], 0)
        self.assertEqual(self.go("status")[1], "face\nfingerprint\nkey\n")
        self.assertEqual(self.auth_lines(), ["pam_howdy.so", "pam_fprintd.so", f"pam_u2f.so authfile={self.keys} cue", "pam_deny.so"])

    def test_off_again_and_none_left_takes_the_file_away(self):
        self.installed("pam_howdy.so", "pam_fprintd.so")
        self.go("enable", "face")
        self.go("enable", "fingerprint")
        self.assertEqual(self.go("disable", "face")[0], 0)
        self.assertEqual(self.go("status")[1], "fingerprint\n")
        self.assertEqual(self.go("disable", "fingerprint")[0], 0)
        self.assertFalse(os.path.exists(self.file), "an empty service was left behind")
        self.assertEqual(self.go("disable", "fingerprint")[0], 0, "turning off what's off isn't an error")

    def test_remove(self):
        self.installed("pam_u2f.so")
        self.go("enable", "key")
        self.assertEqual(self.go("remove")[0], 0)
        self.assertFalse(os.path.exists(self.file))
        self.assertEqual(self.go("remove")[0], 0)

    def test_not_installed_changes_nothing(self):
        self.assertEqual(self.go("enable", "fingerprint")[0], 3)
        self.assertFalse(os.path.exists(self.file))
        self.installed("pam_howdy.so")
        self.go("enable", "face")
        before = self.text()
        self.assertEqual(self.go("enable", "key")[0], 3)
        self.assertEqual(self.text(), before)

    def test_only_its_own_words(self):
        self.installed("pam_howdy.so")
        for args in (["enable"], ["enable", "password"], ["enable", "face", "fingerprint"], ["enable", "pam_permit.so"],
                     ["enable", "face;reboot"], ["remove", "now"], ["reset"], []):
            with self.subTest(args):
                self.assertNotEqual(self.go(*args)[0], 0)
        self.assertFalse(os.path.exists(self.file))

    def test_nothing_else_in_pam_d_changes(self):
        self.installed("pam_howdy.so")
        self.go("enable", "face")
        self.go("remove")
        with open(self.login) as f:
            self.assertEqual(f.read(), "auth include system-local-login\n")
        self.assertEqual(sorted(os.listdir(self.pamd)), ["login"], "something else was left in pam.d")

    def test_never_through_a_link(self):
        self.installed("pam_howdy.so")
        os.symlink(self.login, self.file)
        self.assertEqual(self.go("enable", "face")[0], 1)
        self.assertEqual(self.go("remove")[0], 1)
        with open(self.login) as f:
            self.assertEqual(f.read(), "auth include system-local-login\n")

    def test_readable_by_everyone_whatever_the_umask(self):
        """The lock screen reads it as you: 0644 even from a caller with umask 077."""
        self.installed("pam_howdy.so")
        code, out = run(["sh", "-c", 'umask 077; exec "$0" enable face', self.helper], env=self.s.env)
        self.assertEqual(code, 0, out)
        self.assertEqual(stat.S_IMODE(os.stat(self.file).st_mode), 0o644)

    def test_runs_only_from_the_root_owned_folder_and_only_as_root(self):
        self.installed("pam_howdy.so")
        code, out = self.go("enable", "face", path=HELPER)
        self.assertEqual(code, 1)
        self.assertIn("only runs from /usr/local/libexec/slate", out)
        self.s.add("id", by_args={"-u": "1000\n", "": "me\n"})
        self.assertEqual(self.go("enable", "face")[0], 1)
        self.assertFalse(os.path.exists(self.file))


class Faces(Unlock):
    """Faces are Howdy's (Howdy Next 3), kept in /etc/howdy, root's: the helper adds, removes and
    lists them for whoever asked (pkexec's PKEXEC_UID), never a name it's given, through a
    root-owned howdy in a fixed place, and only with words and numbers it has checked."""

    def setUp(self):
        super().setUp()
        self.bin = os.path.join(self.h.dir, "usr-bin")
        os.makedirs(self.bin)
        self.howdy = os.path.join(self.bin, "howdy")
        self.log = os.path.join(self.h.dir, "howdy-asked")
        with open(self.howdy, "w") as f:
            f.write(f"""#!/bin/sh
echo "$*" >> {self.log}
case "$*" in *"list --plain"*) printf '1,2026-11-20 13:55:00,Me\\n2,2026-11-20 13:56:00,Glasses\\n' ;; esac
""")
        os.chmod(self.howdy, 0o755)
        self.models = os.path.join(self.h.dir, "howdy-models")
        os.makedirs(self.models)
        src = slate.read(self.helper)
        self.assertIn('HOWDY_PATHS="/usr/bin/howdy /usr/local/bin/howdy"', src)
        src = (src.replace('HOWDY_PATHS="/usr/bin/howdy /usr/local/bin/howdy"', f'HOWDY_PATHS="{self.howdy}"')
                  .replace("HOWDY_MODELS=/usr/share/howdy/models", f"HOWDY_MODELS={self.models}"))
        with open(self.helper, "w") as f:
            f.write(src)
        self.s.add("stat", stdout="0\n")                      # (howdy is root's, for real)
        self.s.add("getent", by_args={"1000": "tester:x:1000:1000:Test:/home/tester:/bin/bash\n"})
        self.asker = {"PKEXEC_UID": "1000"}

    def asked(self):
        return open(self.log).read().splitlines() if os.path.exists(self.log) else []

    def test_add_list_and_remove_your_own(self):
        """Each change ends with your faces, so Settings can show them without asking again."""
        open(os.path.join(self.models, "face.onnx"), "w").close()
        faces = ["1,2026-11-20 13:55:00,Me", "2,2026-11-20 13:56:00,Glasses"]
        for args in (("face-add", "Me"), ("face-add", "With glasses"), ("face-remove", "2")):
            code, out = self.go(*args, env=self.asker)
            self.assertEqual(code, 0, out)
            self.assertEqual(out.splitlines()[-2:], faces)
        code, out = self.go("face-list", env=self.asker)
        self.assertEqual(code, 0, out)
        self.assertEqual(out.splitlines(), faces)
        self.assertEqual(self.asked(), ["-U tester add --plain -y Me", "-U tester list --plain",
                                        "-U tester add --plain -y With glasses", "-U tester list --plain",
                                        "-U tester remove -y 2", "-U tester list --plain", "-U tester list --plain"])

    def test_the_first_face_gets_the_camera_and_models_too(self):
        """One password for all of it: the camera chosen, Howdy's models got (only when it has
        none), then the face."""
        cams = sorted(f for f in os.listdir("/dev") if f.startswith("video")) if os.path.isdir("/dev") else []
        if not cams:
            self.skipTest("no camera here to point at")
        code, out = self.go("face-add", "Me", "/dev/" + cams[0], env=self.asker)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.asked(), ["set device_path /dev/" + cams[0], "download-models",
                                        "-U tester add --plain -y Me", "-U tester list --plain"])

    def test_a_wrong_camera_adds_nothing(self):
        code, out = self.go("face-add", "Me", "/etc/shadow", env=self.asker)
        self.assertNotEqual(code, 0, out)
        self.assertEqual(self.asked(), [])

    def test_only_whoever_asked(self):
        """No PKEXEC_UID (not through pkexec), or root's own: nothing is done."""
        for env in ({}, {"PKEXEC_UID": "0"}, {"PKEXEC_UID": "1000; id"}, {"PKEXEC_UID": "999999"}):
            with self.subTest(env):
                code, out = self.go("face-add", "Me", env=env)
                self.assertNotEqual(code, 0, out)
        self.assertEqual(self.asked(), [])

    def test_only_a_plain_name_and_a_number(self):
        for bad in ("", "-U root", "Me; rm -rf /", "../x", "x" * 41, "$(id)", "Me\nYou"):
            with self.subTest(bad):
                self.assertNotEqual(self.go("face-add", bad, env=self.asker)[0], 0)
        for bad in ("", "1 2", "-y", "1;id", "x"):
            with self.subTest(bad):
                self.assertNotEqual(self.go("face-remove", bad, env=self.asker)[0], 0)
        self.assertEqual(self.asked(), [])

    def test_only_a_camera(self):
        for bad in ("/etc/shadow", "/dev/v4l/by-id/../../etc/shadow", "/dev/null", "-x", "/dev/video0; id",
                    "/dev/v4l/by-id/a b"):
            with self.subTest(bad):
                self.assertNotEqual(self.go("face-camera", bad)[0], 0)
        self.assertEqual(self.asked(), [])

    def test_a_camera(self):
        cams = sorted(f for f in os.listdir("/dev") if f.startswith("video")) if os.path.isdir("/dev") else []
        if not cams:
            self.skipTest("no camera here to point at")
        code, out = self.go("face-camera", "/dev/" + cams[0])
        self.assertEqual(code, 0, out)
        self.assertEqual(self.asked(), ["set device_path /dev/" + cams[0]])

    def test_models_only_when_there_are_none(self):
        self.assertEqual(self.go("face-models")[0], 0)
        open(os.path.join(self.models, "face.onnx"), "w").close()
        self.assertEqual(self.go("face-models")[0], 0)
        self.assertEqual(self.asked(), ["download-models"])

    def test_howdy_only_when_it_is_roots(self):
        """A howdy that isn't root's (or anyone can change) is never run as root."""
        self.s.add("stat", stdout="1000\n")
        code, out = self.go("face-list", env=self.asker)
        self.assertEqual(code, 3, out)
        self.assertIn("Howdy isn't installed", out)
        self.assertEqual(self.asked(), [])

    def test_not_installed(self):
        os.remove(self.howdy)
        self.assertEqual(self.go("face-list", env=self.asker)[0], 3)


# Two registrations as pamu2fcfg -n gives them (handles and public keys made up, the shape real)
REG1 = ":" + "A" * 43 + "x," + "B" * 87 + "y,es256,+presence"
REG2 = ":" + "C" * 43 + "z," + "D" * 87 + "w,es256,+presence"


class Keys(Unlock):
    """Security keys are pam_u2f's, in /etc/slate/u2f_keys: root's, never in your home, and
    readable by everyone (public keys only; the lock screen reads it as you). The helper adds and
    removes the keys of whoever asked, and nobody else's, and takes only a registration's shape."""

    def setUp(self):
        super().setUp()
        self.s.add("getent", by_args={"1000": "tester:x:1000:1000:Test:/home/tester:/bin/bash\n",
                                      "1001": "sam:x:1001:1001:Sam:/home/sam:/bin/bash\n"})
        self.me = {"PKEXEC_UID": "1000"}

    def lines(self):
        with open(self.keys) as f:
            return f.read().splitlines()

    def test_add_list_and_remove(self):
        code, out = self.go("key-add", REG1, env=self.me)
        self.assertEqual(code, 0, out)
        self.assertEqual(out, "1," + "A" * 43 + "x\n")
        code, out = self.go("key-add", REG2, env=self.me)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.lines(), ["tester:" + REG1[1:] + ":" + REG2[1:]])
        self.assertEqual(stat.S_IMODE(os.stat(self.keys).st_mode), 0o644, "the lock screen reads it as you")
        self.assertEqual(self.go("key-list", env=self.me)[1].splitlines(), ["1," + "A" * 43 + "x", "2," + "C" * 43 + "z"])
        code, out = self.go("key-remove", "1", env=self.me)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.lines(), ["tester:" + REG2[1:]])
        self.go("key-remove", "1", env=self.me)
        self.assertEqual(self.lines(), [], "no keys left: your line goes")

    def test_only_yours_change(self):
        self.go("key-add", REG1, env={"PKEXEC_UID": "1001"})
        self.go("key-add", REG2, env=self.me)
        self.go("key-remove", "1", env=self.me)
        self.assertEqual(self.lines(), ["sam:" + REG1[1:]])
        self.assertEqual(self.go("key-list", env=self.me)[1], "")

    def test_the_same_key_once(self):
        self.go("key-add", REG1, env=self.me)
        code, out = self.go("key-add", REG1, env=self.me)
        self.assertNotEqual(code, 0)
        self.assertIn("already added", out)

    def test_only_a_registrations_shape(self):
        for bad in ("hello", REG1 + ":more", REG1.replace("es256", "md5"), "x" * 20 + "," + "y" * 20 + ",es256,+presence\nroot:" + REG2,
                    "../../etc/shadow", REG1.replace(",", ";")):
            with self.subTest(bad[:30]):
                code, out = self.go("key-add", bad, env=self.me)
                self.assertNotEqual(code, 0, out)
        self.assertFalse(os.path.exists(self.keys))

    def test_only_whoever_asked(self):
        code, out = self.go("key-add", REG1)
        self.assertNotEqual(code, 0)
        code, out = self.go("key-add", REG1, env={"PKEXEC_UID": "0"})
        self.assertNotEqual(code, 0)
        self.assertFalse(os.path.exists(self.keys))

    def test_a_number_thats_there(self):
        self.go("key-add", REG1, env=self.me)
        for bad in ("0", "2", "-1", "1x", ""):
            with self.subTest(bad):
                self.assertNotEqual(self.go("key-remove", bad, env=self.me)[0], 0)
        self.assertEqual(len(self.lines()), 1)

    def test_the_lock_screen_line_reads_this_file(self):
        self.installed("pam_u2f.so")
        self.assertEqual(self.go("enable", "key")[0], 0)
        self.assertIn(f"pam_u2f.so authfile={self.keys} cue", self.text())

    def test_remove_takes_the_keys_too(self):
        """Uninstalling or a factory reset (remove): Slate's list of keys goes with slate-lock."""
        self.installed("pam_u2f.so")
        self.go("key-add", REG1, env=self.me)
        self.go("enable", "key")
        code, out = self.go("remove")
        self.assertEqual(code, 0, out)
        self.assertFalse(os.path.exists(self.file))
        self.assertFalse(os.path.exists(self.keys))
        self.assertFalse(os.path.exists(os.path.dirname(self.keys)))
