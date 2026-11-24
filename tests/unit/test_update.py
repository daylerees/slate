"""scripts/update.py: `modified` (Slate's own files you've changed since installing, shown in
Settings → Updates before an update replaces them) against a scratch install, and `check`
when its answer is still fresh (no network). Your own files (settings.json, hypr/, user/)
are never reported. `install` and `check --force` against a stand-in for the network: only a
proper, newer release from Slate's own repository that matches its published checksum is
unpacked and run."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import sys
import tarfile
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from unittest import mock

import slate
from slate import Case, run
from stubs import Stubs
from signing import Key


def manifest(dest):
    """.manifest as install.sh writes it: "<sha256>  <path>" for each of Slate's files, leaving
    out hidden files, caches, VERSION and your own files."""
    lines = []
    for d, dirs, names in os.walk(dest):
        dirs[:] = [x for x in dirs if not x.startswith(".") and x != "__pycache__"]
        for n in names:
            full = os.path.join(d, n)
            rel = os.path.relpath(full, dest)
            if (n.startswith(".") or os.path.islink(full) or rel in ("VERSION", "settings.json")
                    or rel.startswith(("hypr/", "user/"))):
                continue
            with open(full, "rb") as f:
                lines.append((rel, hashlib.sha256(f.read()).hexdigest()))
    with open(os.path.join(dest, ".manifest"), "w") as f:
        f.write("".join("%s  %s\n" % (h, rel) for rel, h in sorted(lines)))


class Modified(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.dest = self.h.install_slate()
        manifest(self.dest)
        # No network: curl and git as stubs, and nothing in `modified` should reach for them
        self.s = Stubs(self.h)
        self.s.add("curl", code=1)
        self.s.add("git", code=1)

    def modified(self):
        code, out = run([sys.executable, os.path.join(self.dest, "scripts", "update.py"), "modified"], env=self.s.env)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def write(self, rel, text, mode="w"):
        p = os.path.join(self.dest, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, mode) as f:
            f.write(text)

    def test_untouched(self):
        self.assertEqual(self.modified(), {"known": True, "changed": [], "added": []})

    def test_changed_and_added(self):
        self.write("Bar.qml", "// mine\n", mode="a")
        self.write("scripts/update.py", "# a note\n", mode="a")
        self.write("my-notes.txt", "hello\n")
        self.write("scripts/extra.sh", "echo hi\n")
        os.remove(os.path.join(self.dest, "OSD.qml"))     # removed: an update just puts it back
        self.assertEqual(self.modified(), {"known": True, "changed": ["Bar.qml", "scripts/update.py"],
                                           "added": ["my-notes.txt", "scripts/extra.sh"]})

    def test_same_content_not_changed(self):
        """Saved again with the same contents (a new mtime) isn't a change."""
        p = os.path.join(self.dest, "Bar.qml")
        with open(p, "rb") as f:
            data = f.read()
        with open(p, "wb") as f:
            f.write(data)
        os.utime(p, (time.time() + 100, time.time() + 100))
        self.assertEqual(self.modified()["changed"], [])

    def test_yours_never_reported(self):
        """settings.json, hypr/ and user/ are yours; VERSION, hidden files, caches and links
        aren't Slate's files either."""
        self.write("settings.json", '{"barHeight": 40}\n')
        self.write("hypr/keybinds.lua", "-- mine\n")
        self.write("user/Custom.qml", "// mine\n")
        self.write("VERSION", "v9.9.9\n")
        self.write(".hidden", "x\n")
        self.write("scripts/__pycache__/x.cpython-313.pyc", "x")
        self.write("data/.cache/thing", "x")
        os.symlink("Bar.qml", os.path.join(self.dest, "alias.qml"))
        self.assertEqual(self.modified(), {"known": True, "changed": [], "added": []})

    def test_kept_names_only_at_the_top(self):
        """A file called settings.json or a folder called user/ deeper down is still Slate's."""
        self.write("data/user/thing.txt", "x\n")
        self.write("scripts/settings.json", "{}\n")
        self.assertEqual(self.modified()["added"], ["data/user/thing.txt", "scripts/settings.json"])

    def test_file_named_like_settings_reported(self):
        """A file of yours whose name starts with settings.json (settings.json.bak) is listed:
        an update doesn't keep it (it used to be matched as a prefix and left out)."""
        self.write("settings.json.bak", "{}\n")
        self.assertEqual(self.modified()["added"], ["settings.json.bak"])

    def test_no_manifest(self):
        """An install from before manifests (or a linked checkout): nothing known."""
        os.remove(os.path.join(self.dest, ".manifest"))
        self.write("Bar.qml", "// mine\n", mode="a")
        self.assertEqual(self.modified(), {"known": False, "changed": [], "added": []})

    def test_yours_survive(self):
        """Running it changes nothing: your files are exactly as they were."""
        self.write("settings.json", '{"barHeight": 40}\n')
        self.write("hypr/keybinds.lua", "-- mine\n")
        self.modified()
        with open(os.path.join(self.dest, "settings.json")) as f:
            self.assertEqual(f.read(), '{"barHeight": 40}\n')
        with open(os.path.join(self.dest, "hypr", "keybinds.lua")) as f:
            self.assertEqual(f.read(), "-- mine\n")
        self.assertEqual(self.s.calls("curl") + self.s.calls("git"), [])

    def test_keep_matches_installer(self):
        """update.py's KEEP is install.sh's KEEP (the folders an update copies across)."""
        src = slate.read("shell", "scripts", "update.py")
        keep = re.search(r'^KEEP = \(([^)]*)\)', src, re.M).group(1)
        inst = re.search(r'^KEEP=\(([^)]*)\)', slate.read("install.sh"), re.M).group(1)
        self.assertEqual(re.findall(r'"([^"]+)"', keep), inst.split())


class Check(Case):
    """`check` with a recent answer saved: it answers from that, without going online."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.dest = self.h.install_slate()
        self.state = os.path.join(self.h.state, "slate", "update.json")
        os.makedirs(os.path.dirname(self.state))
        self.s = Stubs(self.h)

    def check(self, saved, version):
        with open(self.state, "w") as f:
            json.dump(saved, f)
        with open(os.path.join(self.dest, "VERSION"), "w") as f:
            f.write(version + "\n")
        # A proxy that can't be reached, in case it tried to go online after all
        env = dict(self.s.env, https_proxy="http://127.0.0.1:9", http_proxy="http://127.0.0.1:9")
        code, out = run([sys.executable, os.path.join(self.dest, "scripts", "update.py"), "check"], env=env, timeout=30)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def test_fresh_answer(self):
        saved = {"checked": time.time() - 60, "latest": "v0.30.0", "newer": True, "notified": "v0.30.0"}
        st = self.check(saved, "v0.23.0")
        self.assertEqual(st["current"], "v0.23.0")
        self.assertEqual(st["latest"], "v0.30.0")
        self.assertIs(st["notify"], False)
        self.assertEqual(st["previous"], "")
        self.assertNotIn("error", st)

    def test_previous_version(self):
        """The backup's version, or "unknown" for a backup without one."""
        prev = self.dest + ".previous"
        os.makedirs(prev)
        with open(os.path.join(prev, "shell.qml"), "w") as f:
            f.write("")
        saved = {"checked": time.time(), "latest": "v0.23.0"}
        self.assertEqual(self.check(saved, "v0.23.0")["previous"], "unknown")
        with open(os.path.join(prev, "VERSION"), "w") as f:
            f.write("v0.22.0\n")
        self.assertEqual(self.check(saved, "v0.23.0")["previous"], "v0.22.0")


class Parse(Case):
    """Version strings, as the updater compares them."""

    def test_parse(self):
        spec = importlib.util.spec_from_file_location("slate_update", slate.path("shell", "scripts", "update.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        for text, want in (("v0.4.2", (0, 4, 2)), ("0.4.2", (0, 4, 2)), ("v0.4.2-15-gabc123", (0, 4, 2)),
                           ("v1.10.0", (1, 10, 0)), ("", None), (None, None), ("unknown", None)):
            with self.subTest(text):
                self.assertEqual(mod.parse(text), want)
        self.assertGreater(mod.parse("v0.10.0"), mod.parse("v0.9.9"))


def load_updater():
    spec = importlib.util.spec_from_file_location("slate_update", slate.path("shell", "scripts", "update.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def release_archive(tag, marker, who):
    """A release as tools/release-assets.sh packs it (slate-<tag>/ with install.sh and shell/),
    whose install.sh only notes that it ran, how, and which archive it came from."""
    script = ('#!/bin/bash\necho "$1 %s" >> "%s"\ndirname "$(readlink -f "$0")" > "%s.where"\n' % (who, marker, marker)).encode()
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as t:
        for name in ("slate-%s" % tag, "slate-%s/shell" % tag):
            info = tarfile.TarInfo(name)
            info.type, info.mode = tarfile.DIRTYPE, 0o755
            t.addfile(info)
        info = tarfile.TarInfo("slate-%s/install.sh" % tag)
        info.size, info.mode = len(script), 0o755
        t.addfile(info, io.BytesIO(script))
    return buf.getvalue()


class Internet:
    """Stands in for the network, underneath urllib (so the updater's own checks of addresses
    and redirects still run): `pages` maps an address to its bytes, or to ("to", address) for
    a redirect; anything else is a 404. `asked` is every address fetched, in order."""

    def __init__(self):
        self.pages, self.asked = {}, []

    def open(self):
        net = self

        def fake(opener, req, data=None, timeout=None):
            url = req if isinstance(req, str) else req.full_url
            for _ in range(5):
                net.asked.append(url)
                page = net.pages.get(url)
                if page is None:
                    raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
                if isinstance(page, bytes):
                    reply = io.BytesIO(page)
                    reply.headers = {"Content-Length": str(len(page))}   # (as GitHub's downloads say)
                    return reply
                # A redirect: asked of urllib's redirect handler, as a real one would be
                handler = next(h for h in opener.handlers if isinstance(h, urllib.request.HTTPRedirectHandler))
                url = handler.redirect_request(urllib.request.Request(url), None, 302, "Found", {}, page[1]).full_url
            raise AssertionError("too many redirects")
        return mock.patch.object(urllib.request.OpenerDirector, "open", fake)


class Releases(Case):
    """A scratch Slate and a stand-in GitHub with a release on it (no real network)."""
    scratch = True
    TAG = "v9.9.9"
    API = "https://api.github.com/repos/daylerees/slate/releases/latest"
    BASE = "https://github.com/daylerees/slate/releases/download"
    ELSEWHERE = "https://downloads.example/slate.tar.gz"

    def setUp(self):
        super().setUp()
        self.mod = load_updater()
        self.dest = os.path.join(self.h.dir, "installed")
        os.makedirs(self.dest)
        self.marker = os.path.join(self.h.dir, "installer-ran")
        for name, value in (("HERE", self.dest), ("DEST", self.dest), ("PREVIOUS", self.dest + ".previous"),
                            ("STATE_DIR", os.path.join(self.h.dir, "state")),
                            ("STATE", os.path.join(self.h.dir, "state", "update.json")),
                            ("LOG", os.path.join(self.h.dir, "update.log"))):
            setattr(self.mod, name, value)
        self.have("v0.31.0")
        # (this copy's release key: the tests' own, in its data/release-signers)
        self.key = Key(os.path.join(self.h.dir, "keys"))
        os.makedirs(os.path.join(self.dest, "data"), exist_ok=True)
        with open(os.path.join(self.dest, "data", "release-signers"), "w") as f:
            f.write(self.key.signers())
        self.net = Internet()
        self.good = release_archive(self.TAG, self.marker, "good")
        # What GitHub's reply calls the download: somewhere else entirely, which must never be
        # fetched (the updater used to download and run whatever this named)
        self.net.pages[self.ELSEWHERE] = release_archive(self.TAG, self.marker, "elsewhere")
        self.release(self.TAG, self.good)

    def have(self, version):
        with open(os.path.join(self.dest, "VERSION"), "w") as f:
            f.write(version + "\n" if version else "")

    def release(self, tag, archive, checksum=None, reply_tag=None, signature=None):
        """Publish a release: GitHub's reply, and its three files (each behind the redirect
        GitHub answers with). checksum: the checksum file's text, or False for none.
        signature: the .sig's bytes, None to sign with this copy's key, or False for none."""
        name = "slate-%s.tar.gz" % tag
        self.net.pages[self.API] = json.dumps({"tag_name": reply_tag if reply_tag is not None else tag, "body": "notes",
                                               "html_url": "", "tarball_url": self.ELSEWHERE}).encode()
        stored = "https://release-assets.githubusercontent.com/github-production-release-asset/1/"
        self.net.pages["%s/%s/%s" % (self.BASE, tag, name)] = ("to", stored + name)
        self.net.pages[stored + name] = archive
        sums = "%s/%s/%s.sha256" % (self.BASE, tag, name)
        if checksum is None:
            checksum = "%s  %s\n" % (hashlib.sha256(archive).hexdigest(), name)
        if checksum is False:
            self.net.pages.pop(sums, None)
        else:
            self.net.pages[sums] = ("to", stored + name + ".sha256")
            self.net.pages[stored + name + ".sha256"] = checksum.encode()
        sig = "%s/%s/%s.sig" % (self.BASE, tag, name)
        if signature is None:
            signature = self.key.sign(archive)
        if signature is False:
            self.net.pages.pop(sig, None)
        else:
            self.net.pages[sig] = ("to", stored + name + ".sig")
            self.net.pages[stored + name + ".sig"] = signature

    def install(self):
        with self.net.open():
            self.mod.install()
        with open(self.mod.STATE) as f:
            return json.load(f)

    def ran(self):
        if not os.path.exists(self.marker):
            return ""
        with open(self.marker) as f:
            return f.read().strip()

    def refused(self, saying):
        st = self.install()
        self.assertEqual(self.ran(), "", "the installer ran")
        self.assertEqual(st["status"], "failed")
        self.assertIn(saying, st["error"])
        return st



class Install(Releases):
    """`install`: only a proper, newer release, from Slate's own repository on GitHub, that
    matches the checksum published with it, is unpacked and run. No real network."""

    def test_good_checksum_installs(self):
        st = self.install()
        self.assertEqual(self.ran(), "--update good")
        self.assertEqual((st["status"], st["current"], st["error"]), ("done", self.TAG, ""))
        with open(self.mod.LOG) as f:
            self.assertIn("matched the checksum", f.read())

    def test_says_how_much_has_downloaded(self):
        """While the release downloads, Settings → Updates is told how much has come and how big
        it is (written now and then, not for every piece), and once it's installing the
        numbers are cleared, so the page shows that step instead."""
        big = self.good + b"\0" * (1 << 20)        # (a few pieces' worth: trailing zeros gzip ignores)
        self.release(self.TAG, big)
        written, save = [], self.mod.save
        self.mod.save = lambda st: (written.append(dict(st)), save(st))
        self.install()
        during = [(w["got"], w["size"]) for w in written if w.get("status") == "downloading" and w.get("got")]
        self.assertTrue(during, "nothing said how much had downloaded")
        self.assertEqual(during[-1], (len(big), len(big)), "the last word wasn't the whole download")
        self.assertLess(len(during), 10, "written for every piece that arrived")
        first_installing = next(w for w in written if w.get("status") == "installing")
        self.assertEqual((first_installing["got"], first_installing["size"]), (0, 0))

    def test_address_in_the_reply_is_ignored(self):
        """Only GitHub's own hosts are asked, at addresses built from the repository and the
        tag: the reply's tarball_url isn't one of them."""
        self.install()
        self.assertNotIn(self.ELSEWHERE, self.net.asked)
        for url in self.net.asked:
            self.assertIn(urllib.parse.urlsplit(url).hostname, self.mod.HOSTS, url)
        self.assertIn("%s/%s/slate-%s.tar.gz" % (self.BASE, self.TAG, self.TAG), self.net.asked)

    def test_wrong_checksum_refused(self):
        self.release(self.TAG, self.good, checksum="%s  slate-%s.tar.gz\n" % ("0" * 64, self.TAG))
        self.refused("didn't match the checksum")

    def test_changed_download_refused(self):
        """The checksum is the published one; the archive that arrives is another."""
        self.release(self.TAG, release_archive(self.TAG, self.marker, "swapped"),
                     checksum="%s  slate-%s.tar.gz\n" % (hashlib.sha256(self.good).hexdigest(), self.TAG))
        self.refused("didn't match the checksum")

    def test_missing_checksum_refused(self):
        """A release without a checksum isn't installed, and its archive isn't even fetched."""
        self.release(self.TAG, self.good, checksum=False)
        st = self.refused("Slate couldn't check this download")
        self.assertIn("doesn't have a checksum", st["error"])
        self.assertFalse([u for u in self.net.asked if u.endswith(".tar.gz")], self.net.asked)

    def test_unreadable_checksum_refused(self):
        self.release(self.TAG, self.good, checksum="<html>Not here</html>\n")
        self.refused("Slate couldn't check this download")

    def test_unpacked_and_run_in_the_runtime_folder(self):
        """The new version is unpacked, and its installer run, in the runtime folder (yours
        alone, gone at log out), never /tmp."""
        runtime = os.path.join(self.h.dir, "run")
        os.makedirs(runtime, mode=0o700)
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime}):
            self.assertEqual(self.install()["status"], "done")
        with open(self.marker + ".where") as f:
            where = f.read().strip()
        self.assertTrue(where.startswith(os.path.realpath(runtime) + os.sep), where)
        self.assertEqual(os.listdir(runtime), [], "left behind in the runtime folder")

    def test_unsigned_refused(self):
        """The checksum shows the download arrived whole, not who made it: anyone who could
        publish a release (a stolen token, say) could have had their code installed. A release
        without Slate's signature isn't installed, and its archive isn't even fetched."""
        self.release(self.TAG, self.good, signature=False)
        st = self.refused("Slate couldn't check who made this update")
        self.assertIn("isn't signed", st["error"])
        self.assertFalse([u for u in self.net.asked if u.endswith(".tar.gz")], self.net.asked)

    def test_signed_by_another_key_refused(self):
        other = Key(os.path.join(self.h.dir, "keys"), "someone-else")
        self.release(self.TAG, self.good, signature=other.sign(self.good))
        self.refused("isn't signed by Slate's own key")

    def test_signed_for_something_else_refused(self):
        self.release(self.TAG, self.good, signature=self.key.sign(self.good, namespace="file"))
        self.refused("isn't signed by Slate's own key")

    def test_a_signature_for_another_archive_refused(self):
        """A genuine signature, moved onto an archive it wasn't made for (with that archive's own
        checksum published beside it)."""
        swapped = release_archive(self.TAG, self.marker, "swapped")
        self.release(self.TAG, swapped, signature=self.key.sign(self.good))
        self.refused("isn't signed by Slate's own key")

    def test_an_older_release_relabelled_refused(self):
        """The signature covers the archive, not the tag it's published under: an older genuine
        release (slate-v0.30.0/ inside, really signed) published again as a newer one isn't
        installed. It would have brought back the updater from before signing."""
        old = release_archive("v0.30.0", self.marker, "old")
        self.release(self.TAG, old)
        self.refused("isn't the release it says it is")

    def test_no_key_in_this_copy_refused(self):
        os.remove(os.path.join(self.dest, "data", "release-signers"))
        self.refused("no key to check it with")

    def test_older_releases_have_no_other_way_in(self):
        """There's no unchecked path for releases from before checksums: one that's newer than
        what's installed but has no checksum file is refused like any other."""
        self.have("v0.1.0")
        self.release("v0.2.0", release_archive("v0.2.0", self.marker, "old"), checksum=False)
        self.refused("Slate couldn't check this download")

    def test_bad_tags_refused(self):
        for tag in ("v9.9.9-rc1", "9.9.9", "v9.9", "v9.9.9.1", "v9.9.9\n", " v9.9.9", "v9.9.9/../../../x", "latest", "", 999):
            with self.subTest(tag=tag):
                self.net.asked.clear()
                self.release(self.TAG, self.good, reply_tag=tag)
                self.refused("couldn't make sense of the version")
                self.assertEqual(self.net.asked, [self.API])

    def test_not_newer_refused(self):
        """The same version, an older one (compared as numbers: 9.10 is past 9.9) and a
        development copy already past it."""
        for have in ("v9.9.9", "v9.10.0", "v10.0.0", "v9.9.9-4-gabc1234"):
            with self.subTest(have=have):
                self.net.asked.clear()
                self.have(have)
                self.refused("isn't newer than the Slate you have")
                self.assertEqual(self.net.asked, [self.API])

    def test_unknown_installed_version_refused(self):
        self.have("")
        self.refused("couldn't tell which version you have")

    def test_newer_as_numbers_installs(self):
        self.have("v9.9.8-2-gabc1234")
        self.assertEqual(self.install()["status"], "done")
        self.assertEqual(self.ran(), "--update good")

    def test_redirect_elsewhere_refused(self):
        """GitHub's address for the archive sending us to another host: not followed, even
        with a checksum that would match what's there."""
        self.release(self.TAG, self.net.pages[self.ELSEWHERE])
        self.net.pages["%s/%s/slate-%s.tar.gz" % (self.BASE, self.TAG, self.TAG)] = ("to", self.ELSEWHERE)
        self.refused("led somewhere else")
        self.assertNotIn(self.ELSEWHERE, self.net.asked)

    def test_redirect_for_the_checksum_elsewhere_refused(self):
        self.net.pages["https://downloads.example/sum"] = b"%s  x\n" % hashlib.sha256(self.good).hexdigest().encode()
        self.net.pages["%s/%s/slate-%s.tar.gz.sha256" % (self.BASE, self.TAG, self.TAG)] = ("to", "https://downloads.example/sum")
        self.refused("led somewhere else")

    def test_redirects(self):
        """What the redirect check lets through: https to GitHub's hosts and nothing else."""
        follow = self.mod.GitHubOnly().redirect_request
        req = urllib.request.Request("https://github.com/daylerees/slate/releases/download/v9.9.9/x")
        for url in ("https://release-assets.githubusercontent.com/a/b?sig=1", "https://objects.githubusercontent.com/a"):
            self.assertEqual(follow(req, None, 302, "Found", {}, url).full_url, url)
        for url in ("http://release-assets.githubusercontent.com/a", "https://githubusercontent.com.example/a",
                    "https://example.com/github.com/a", "https://raw.githubusercontent.com/a", "file:///etc/passwd",
                    "https://github.com@example.com/a"):
            with self.subTest(url=url):
                with self.assertRaises(self.mod.Refused):
                    follow(req, None, 302, "Found", {}, url)

    def test_much_too_big_refused(self):
        self.mod.MAX_BYTES = 64
        st = self.install()
        self.assertEqual(self.ran(), "")
        self.assertEqual(st["status"], "failed")
        self.assertIn("Slate couldn't download the update", st["error"])

    def test_checksum_file(self):
        h = "ab" * 32
        for text, want in ((h + "  slate-v1.2.3.tar.gz\n", h), (h.upper() + "\n", h), (h, h), ("", ""), ("\n", ""),
                           (h[:-1] + "  x\n", ""), (h + "0  x\n", ""), ("sha256:" + h, ""), ("x " + h, "")):
            with self.subTest(text):
                self.assertEqual(self.mod.checksum_in(text), want)

    @unittest.skipUnless(shutil.which("git") and shutil.which("sha256sum"), "needs git and sha256sum")
    def test_release_assets_script(self):
        """tools/release-assets.sh packs a tag into the three files the updater asks for: its
        checksum file reads back, matches, its signature is this key's, and the archive installs."""
        repo = os.path.join(self.h.dir, "repo")
        os.makedirs(os.path.join(repo, "shell", "data"))
        with open(os.path.join(repo, "shell", "data", "release-signers"), "w") as f:
            f.write(self.key.signers())
        with open(os.path.join(repo, "install.sh"), "w") as f:
            f.write('#!/bin/bash\necho "$1 packed" >> "%s"\n' % self.marker)
        with open(os.path.join(repo, "shell", "shell.qml"), "w") as f:
            f.write("// Slate\n")
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull, GIT_AUTHOR_NAME="t",
                   GIT_AUTHOR_EMAIL="t@example.com", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com",
                   SLATE_RELEASE_KEY=self.key.path)
        # (a repository of its own, whatever git folder the tests themselves run from)
        for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            env.pop(name, None)
        for cmd in (["init", "-q"], ["add", "-A"], ["commit", "-q", "-m", "release"], ["tag", self.TAG]):
            self.ok(["git"] + cmd, cwd=repo, env=env)
        # Something uncommitted, which mustn't get in
        with open(os.path.join(repo, "notes.txt"), "w") as f:
            f.write("mine\n")
        script = slate.path("tools", "release-assets.sh")
        out = os.path.join(self.h.dir, "assets")
        made = self.ok(["bash", script, self.TAG, out], cwd=repo, env=env).split()
        name = "slate-%s.tar.gz" % self.TAG
        self.assertEqual(made, [os.path.join(out, name), os.path.join(out, name + ".sha256"), os.path.join(out, name + ".sig")])
        with open(made[0], "rb") as f:
            archive = f.read()
        with open(made[1]) as f:
            checksum = f.read()
        self.assertEqual(self.mod.checksum_in(checksum), hashlib.sha256(archive).hexdigest())
        with tarfile.open(made[0]) as t:
            self.assertEqual(sorted(t.getnames()), ["slate-v9.9.9", "slate-v9.9.9/install.sh", "slate-v9.9.9/shell",
                                                    "slate-v9.9.9/shell/data", "slate-v9.9.9/shell/data/release-signers",
                                                    "slate-v9.9.9/shell/shell.qml"])
        # The same tag packs to the same bytes
        again = self.ok(["bash", script, self.TAG, os.path.join(self.h.dir, "again")], cwd=repo, env=env).split()
        with open(again[0], "rb") as f:
            self.assertEqual(f.read(), archive)
        with open(made[2], "rb") as f:
            signature = f.read()
        self.release(self.TAG, archive, checksum=checksum, signature=signature)
        self.assertEqual(self.install()["status"], "done")
        # A key that isn't the one the updaters trust signs nothing (every update would be refused)
        other = Key(os.path.join(self.h.dir, "keys"), "someone-else")
        r = run(["bash", script, self.TAG, os.path.join(self.h.dir, "other")], cwd=repo, env=dict(env, SLATE_RELEASE_KEY=other.path))
        self.assertEqual(r[0], 1, r[1])
        self.assertIn("isn't the one in shell/data/release-signers", r[1])
        self.assertEqual(self.ran(), "--update packed")
        # Not a release's tag, or one that isn't there: nothing made
        for tag, code in (("9.9.9", 2), ("v9.9.9-rc1", 2), ("", 2), ("v1.0.0", 1)):
            with self.subTest(tag=tag):
                self.assertEqual(run(["bash", script, tag, os.path.join(self.h.dir, "none")], cwd=repo, env=env)[0], code)
        self.assertFalse(os.path.exists(os.path.join(self.h.dir, "none")))


class CheckOnline(Case):
    """`check --force`, with the network stood in for."""
    scratch = True

    def setUp(self):
        super().setUp()
        self.mod = load_updater()
        self.dest = os.path.join(self.h.dir, "installed")
        os.makedirs(self.dest)
        with open(os.path.join(self.dest, "VERSION"), "w") as f:
            f.write("v0.31.0\n")
        for name, value in (("HERE", self.dest), ("DEST", self.dest), ("PREVIOUS", self.dest + ".previous"),
                            ("STATE_DIR", os.path.join(self.h.dir, "state")),
                            ("STATE", os.path.join(self.h.dir, "state", "update.json"))):
            setattr(self.mod, name, value)
        self.net = Internet()

    def check(self):
        out = io.StringIO()
        with self.net.open(), contextlib.redirect_stdout(out):
            self.mod.check(True)
        return json.loads(out.getvalue())

    def test_offline_in_slates_words(self):
        st = self.check()
        self.assertTrue(st["error"].startswith("Slate couldn't reach GitHub ("), st["error"])
        self.assertIs(st["newer"], False)

    def test_newer_release_offered(self):
        self.net.pages[Install.API] = json.dumps({"tag_name": "v0.32.0"}).encode()
        st = self.check()
        self.assertEqual((st["latest"], st["newer"], st["error"]), ("v0.32.0", True, ""))

    def test_odd_tag_not_offered(self):
        """Something that isn't a release's tag is never offered as an update."""
        for tag in ("v0.32.0-rc1", "v0.32.0/../x", "0.32.0"):
            with self.subTest(tag=tag):
                self.net.pages[Install.API] = json.dumps({"tag_name": tag}).encode()
                self.assertIs(self.check()["newer"], False)


class ForEveryone(Releases):
    """Slate installed once for everyone: root's copy is updated by slate-update-install,
    given only the tag (it downloads and checks the release again itself, as root), through
    slate-system's password prompt. Nothing is downloaded or run here. A packaged Slate
    updates with the system, never by itself."""

    def setUp(self):
        super().setUp()
        # (this copy's slate-system and slate stand in for the real ones: they note what
        # they're asked; slate-system answers with $ROOT_ANSWER)
        self.asked = os.path.join(self.h.dir, "asked")
        bin_dir = os.path.join(self.dest, "bin")
        os.makedirs(bin_dir)
        for name in ("slate-system", "slate"):
            p = os.path.join(bin_dir, name)
            with open(p, "w") as f:
                f.write('#!/bin/sh\necho "%s $*" >> "%s"\nexit ${ROOT_ANSWER:-0}\n' % (name, self.asked))
            os.chmod(p, 0o755)
        self.mod.layout = lambda: "shared"

    def calls(self):
        try:
            with open(self.asked) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def test_handed_over_by_its_tag_only(self):
        st = self.install()
        self.assertEqual(st["status"], "done", st)
        self.assertEqual(self.calls(), ["slate-system --root slate-update-install " + self.TAG, "slate restart"])
        self.assertEqual(self.ran(), "", "a release's installer was run here")
        downloads = [u for u in self.net.asked if u != self.API]
        self.assertEqual(downloads, [], "the release was downloaded here, not by the root helper")

    def test_password_prompt_closed(self):
        os.environ["ROOT_ANSWER"] = "126"
        self.addCleanup(os.environ.pop, "ROOT_ANSWER", None)
        st = self.install()
        self.assertEqual(st["status"], "failed")
        self.assertIn("password prompt was closed", st["error"])
        self.assertNotIn("slate restart", self.calls())

    def test_only_a_newer_proper_release_is_handed_over(self):
        for tag in ("v0.30.0", "v9.9.9; rm -rf /", "latest"):
            with self.subTest(tag):
                self.release(tag, self.good, reply_tag=tag)
                st = self.install()
                self.assertEqual(st["status"], "failed")
                self.assertEqual(self.calls(), [])

    def test_going_back(self):
        os.makedirs(self.dest + ".previous")
        with open(os.path.join(self.dest + ".previous", "shell.qml"), "w") as f:
            f.write("Scope {}\n")
        self.mod.revert()
        self.assertEqual(self.calls(), ["slate-system --root slate-update-install --revert", "slate restart"])

    def test_packaged_never_updates_itself(self):
        self.mod.layout = lambda: "packaged"
        st = self.install()
        self.assertEqual(st["status"], "failed")
        self.assertIn("system's packages", st["error"])
        self.assertEqual((self.calls(), self.ran(), self.net.asked), ([], "", []))
        self.mod.revert()
        self.assertEqual(self.calls(), [])


class HowItsInstalled(Case):
    """layout(): own (a folder you can change), shared (the copy for everyone, not yours) or
    packaged (where only package managers put things)."""
    scratch = True

    def test_each(self):
        mod = load_updater()
        code = os.path.join(self.h.dir, "slate")
        os.makedirs(code)
        mod.HERE = code
        self.assertEqual(mod.layout(), "own")
        os.chmod(code, 0o555)
        self.addCleanup(os.chmod, code, 0o755)
        self.assertEqual(mod.layout(), "shared", "a copy you can't change is updated as root")
        mod.PACKAGED = (self.h.dir + "/",)
        self.assertEqual(mod.layout(), "packaged")

    def test_where_the_version_before_is_kept(self):
        mod = load_updater()
        mod.HERE = "/usr/local/share/slate"
        mod.DEST = os.path.join(self.h.dir, "config", "slate")
        self.assertEqual(mod.previous_dir(), "/usr/local/share/slate.previous")
        # A link to a checkout keeps none
        os.makedirs(os.path.join(self.h.dir, "checkout", "shell"))
        os.makedirs(os.path.dirname(mod.DEST))
        os.symlink(os.path.join(self.h.dir, "checkout", "shell"), mod.DEST)
        mod.HERE = os.path.join(self.h.dir, "checkout", "shell")
        self.assertEqual(mod.previous_dir(), "")


class GoingBackYourOwn(Case):
    """revert for a copy that's yours apart from your files (the copy for everyone in a folder
    of yours): the two versions swap, and your files, which aren't in either, stay put."""
    scratch = True

    def test_swap(self):
        mod = load_updater()
        code = os.path.join(self.h.dir, "share", "slate")
        for d, v in ((code, "v2.0.0"), (code + ".previous", "v1.0.0")):
            os.makedirs(os.path.join(d, "bin"))
            with open(os.path.join(d, "VERSION"), "w") as f:
                f.write(v + "\n")
            with open(os.path.join(d, "shell.qml"), "w") as f:
                f.write("Scope {}\n")
            with open(os.path.join(d, "bin", "slate"), "w") as f:
                f.write("#!/bin/sh\n")
            os.chmod(os.path.join(d, "bin", "slate"), 0o755)
        mine = os.path.join(self.h.dir, "config", "slate")
        os.makedirs(mine)
        with open(os.path.join(mine, "settings.json"), "w") as f:
            f.write("{}")
        mod.HERE, mod.DEST = code, mine
        mod.STATE_DIR = os.path.join(self.h.dir, "state")
        mod.STATE = os.path.join(mod.STATE_DIR, "update.json")
        mod.revert()
        self.assertEqual(mod.version_in(code), "v1.0.0")
        self.assertEqual(mod.version_in(code + ".previous"), "v2.0.0")
        self.assertFalse(os.path.exists(os.path.join(code, "settings.json")), "your files went into Slate's code")
        self.assertTrue(os.path.isfile(os.path.join(mine, "settings.json")))
