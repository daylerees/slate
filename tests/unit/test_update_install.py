"""bin/slate-update-install: as root, puts a newer release of Slate in /usr/local/share/slate
for everyone, or goes back. Run here from a copy whose real places (its own folder, the copy
for everyone, GitHub, root's uid) are swapped for scratch ones, with curl and chown stood in
for: nothing on this computer is touched, and nothing is downloaded."""
import hashlib
import io
import os
import tarfile

import slate
from slate import Case, run
from stubs import Stubs
from signing import Key

TAG = "v2.0.0"
BASE = "https://test.invalid/releases/download"


def release(tag=TAG, outside_link=False, extra=None):
    """A release as tools/release-assets.sh packs it, with a link inside it (the cursor theme
    has those), and a settings.json that must never reach the copy for everyone."""
    buf = io.BytesIO()
    root = "slate-%s" % tag
    files = {"shell/shell.qml": "Scope {}\n", "shell/bin/slate": "#!/bin/sh\n", "shell/settings.json": "{}",
             "shell/cursors/a": "cursor", "packaging/arch.txt": "hyprland\n"}
    files.update(extra or {})
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for d in ("", "/shell", "/shell/bin", "/shell/cursors", "/packaging"):
            info = tarfile.TarInfo(root + d)
            info.type, info.mode = tarfile.DIRTYPE, 0o755
            t.addfile(info)
        for name, text in files.items():
            data = text.encode()
            info = tarfile.TarInfo("%s/%s" % (root, name))
            info.size, info.mode = len(data), 0o755 if "/bin/" in name else 0o644
            t.addfile(info, io.BytesIO(data))
        link = tarfile.TarInfo(root + "/shell/cursors/b")
        link.type, link.linkname = tarfile.SYMTYPE, "/etc/passwd" if outside_link else "a"
        t.addfile(link)
    return buf.getvalue()


class UpdateInstall(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.libexec = os.path.join(self.h.dir, "libexec", "slate")
        self.code = os.path.join(self.h.dir, "share", "slate")
        self.web = os.path.join(self.h.dir, "web")
        self.key = Key(os.path.join(self.h.dir, "keys"))
        os.makedirs(self.libexec)
        os.makedirs(self.web)
        self.installed("v1.0.0")
        self.helper = self.copy(root_uid=os.getuid())
        # curl: the file named by the address, from the stand-in web (or a failure)
        p = os.path.join(self.s.dir, "curl")
        with open(p, "w") as f:
            f.write('#!/bin/sh\nout=""; for a; do [ "$prev" = -o ] && out=$a; prev=$a; url=$a; done\n'
                    f'name=$(basename "$url"); [ -f "{self.web}/$name" ] || exit 22\ncp "{self.web}/$name" "$out"\n')
        os.chmod(p, 0o755)
        self.s.add("chown")

    def copy(self, root_uid):
        src = slate.read("shell", "bin", "slate-update-install")
        for real, scratch in (("/usr/local/libexec/slate", self.libexec), ("/usr/local/share/slate", self.code),
                              ("https://github.com/daylerees/slate/releases/download", BASE),
                              ('[ "$(id -u)" -eq 0 ]', "[ 0 -eq 0 ]"),
                              ('"$(stat -c %u "$CODE")" = 0', '"$(stat -c %%u "$CODE")" = %d' % root_uid),
                              ('"$(stat -c %u "$CODE.previous")" = 0', '"$(stat -c %%u "$CODE.previous")" = %d' % root_uid)):
            self.assertIn(real, src)
            src = src.replace(real, scratch)
        p = os.path.join(self.libexec, "slate-update-install")
        with open(p, "w") as f:
            f.write(src)
        os.chmod(p, 0o755)
        return p

    def installed(self, version, where=None):
        d = where or self.code
        os.makedirs(d, exist_ok=True)
        os.makedirs(os.path.join(d, "data"), exist_ok=True)
        for name, text in (("shell.qml", "old\n"), ("VERSION", version + "\n"), ("data/release-signers", self.key.signers())):
            with open(os.path.join(d, name), "w") as f:
                f.write(text)

    def publish(self, archive, tag=TAG, checksum=None, signature=None):
        """signature: the .sig's bytes, None to sign with the installed copy's key, or False for none."""
        name = "slate-%s.tar.gz" % tag
        with open(os.path.join(self.web, name), "wb") as f:
            f.write(archive)
        if signature is None:
            signature = self.key.sign(archive)
        if signature is not False:
            with open(os.path.join(self.web, name + ".sig"), "wb") as f:
                f.write(signature)
        with open(os.path.join(self.web, name + ".sha256"), "w") as f:
            f.write((checksum or hashlib.sha256(archive).hexdigest()) + "  " + name + "\n")

    def go(self, *args):
        return run([self.helper, *args], env=self.s.env)

    def version(self, d=None):
        with open(os.path.join(d or self.code, "VERSION")) as f:
            return f.read().strip()

    def unchanged(self):
        self.assertEqual(self.version(), "v1.0.0")
        self.assertFalse(os.path.exists(self.code + ".previous"))

    def test_a_good_release(self):
        self.publish(release())
        code, out = self.go(TAG)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.version(), TAG)
        self.assertEqual(self.version(self.code + ".previous"), "v1.0.0")
        self.assertFalse(os.path.exists(os.path.join(self.code, "settings.json")), "someone's settings went in")
        self.assertTrue(os.path.isfile(os.path.join(self.code, ".manifest")))
        self.assertTrue(os.path.isfile(os.path.join(self.code, "packaging", "arch.txt")))
        self.assertEqual(os.readlink(os.path.join(self.code, "cursors", "b")), "a")
        self.assertIn(["-R", "root:root", self.code + ".new"], self.s.calls("chown"))

    def test_and_back(self):
        self.publish(release())
        self.go(TAG)
        code, out = self.go("--revert")
        self.assertEqual(code, 0, out)
        self.assertEqual((self.version(), self.version(self.code + ".previous")), ("v1.0.0", TAG))

    def test_the_wrong_checksum(self):
        self.publish(release(), checksum="0" * 64)
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("doesn't match the checksum", out)
        self.unchanged()

    def test_an_unsigned_release(self):
        """Anyone who could publish a release (a stolen token, say) could have had their code
        installed as root on every computer: only a release signed by Slate's key goes in."""
        self.publish(release(), signature=False)
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("couldn't download", out)
        self.unchanged()

    def test_a_release_signed_by_another_key(self):
        other = Key(os.path.join(self.h.dir, "keys"), "someone-else")
        archive = release()
        self.publish(archive, signature=other.sign(archive))
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("isn't signed by Slate's own key", out)
        self.unchanged()

    def test_a_signature_made_for_something_else(self):
        """Slate's key signing something for another purpose (another namespace) isn't a release."""
        archive = release()
        self.publish(archive, signature=self.key.sign(archive, namespace="file"))
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("isn't signed by Slate's own key", out)
        self.unchanged()

    def test_the_key_is_the_installed_copys(self):
        """Whose signature counts is read from the copy that's root's, never from the release."""
        os.remove(os.path.join(self.code, "data", "release-signers"))
        self.publish(release(extra={"shell/data/release-signers": self.key.signers()}))
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("no key to check", out)
        self.unchanged()

    def test_an_older_release_relabelled(self):
        """An older genuine release (slate-v1.5.0/ inside, really signed) published again as
        v2.0.0 isn't taken: the folder inside names the release."""
        self.publish(release("v1.5.0"), tag=TAG)
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("isn't the release it says it is", out)
        self.unchanged()

    def test_only_newer(self):
        """An older or the same release, however genuine, could bring back what a later one fixed."""
        for tag in ("v1.0.0", "v0.9.9"):
            with self.subTest(tag):
                self.publish(release(tag), tag=tag)
                code, out = self.go(tag)
                self.assertNotEqual(code, 0)
                self.assertIn("isn't newer", out)
                self.unchanged()

    def test_only_a_tag(self):
        for bad in ("2.0.0", "v2.0.0/../../x", "v2.0.0 extra", "--help", ""):
            with self.subTest(bad):
                code, out = self.go(bad) if bad else self.go()
                self.assertNotEqual(code, 0)
                self.unchanged()

    def test_a_link_out_of_the_release(self):
        self.publish(release(outside_link=True))
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("link out of its own folder", out)
        self.unchanged()

    def test_a_copy_thats_not_roots_is_left_alone(self):
        """Made someone's own on purpose: theirs to update, without a password."""
        self.helper = self.copy(root_uid=0)
        self.publish(release())
        code, out = self.go(TAG)
        self.assertNotEqual(code, 0)
        self.assertIn("isn't root's", out)
        self.unchanged()

    def test_only_from_its_root_owned_place(self):
        elsewhere = os.path.join(self.h.dir, "slate-update-install")
        with open(self.helper) as f, open(elsewhere, "w") as g:
            g.write(f.read())
        os.chmod(elsewhere, 0o755)
        code, out = run([elsewhere, TAG], env=self.s.env)
        self.assertNotEqual(code, 0)
        self.assertIn("only runs from", out)

    def test_nothing_to_go_back_to(self):
        code, out = self.go("--revert")
        self.assertNotEqual(code, 0)
        self.assertIn("no previous version", out)
