"""scripts/update.py: `modified` (Slate's own files you've changed since installing, shown in
Settings → Updates before an update replaces them) against a scratch install, and `check`
when its answer is still fresh (no network). Your own files (settings.json, hypr/, user/)
are never reported."""
import hashlib
import importlib.util
import json
import os
import re
import sys
import time
import unittest

import slate
from slate import Case, run
from stubs import Stubs


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

    @unittest.expectedFailure
    def test_file_named_like_settings_reported(self):
        """Slate bug: a file of yours next to settings.json whose name starts with it
        (settings.json.bak) is ignored, as `ignored()` matches "settings.json" as a prefix,
        yet an update doesn't keep it (KEEP copies only settings.json itself)."""
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
