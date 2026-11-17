"""scripts/backup.py (Settings → Backups), with a stand-in restic: setting up (the key kept for
you alone), backing up (what and what not), when one's due, the backups there are, and restoring
beside your files, never over them."""
import json
import os
import stat
import sys
import time

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "backup.py")

# A pretend restic: the repository is a folder holding config and snapshots.json; every call is
# logged with the key it was given
RESTIC = r'''#!%s
import json, os, sys
repo, key = os.environ["RESTIC_REPOSITORY"], os.environ.get("RESTIC_PASSWORD", "")
open(%r, "a").write(json.dumps({"args": sys.argv[1:], "key": key}) + "\n")
a = sys.argv[1:]
cfg, snaps = os.path.join(repo, "config"), os.path.join(repo, "snapshots.json")
def load(): return json.load(open(snaps)) if os.path.exists(snaps) else []
if a[0] == "init":
    open(cfg, "w").write(key); sys.exit(0)
if not os.path.exists(cfg) or open(cfg).read() != key:
    sys.stderr.write("Fatal: wrong password or no repository found\n"); sys.exit(1)
if a[0] == "cat": sys.exit(0)
if a[0] == "backup":
    paths = [x for x in a[1:] if x.startswith("/") and a[a.index(x) - 1] != "--exclude"]
    s = load(); s.append({"id": "%%064d" %% len(s), "short_id": "snap%%d" %% len(s), "time": "2026-11-17T10:00:00Z", "paths": paths})
    json.dump(s, open(snaps, "w"))
    print(json.dumps({"message_type": "summary", "total_bytes_processed": 1234, "total_files_processed": 3})); sys.exit(0)
if a[0] == "snapshots": print(json.dumps(load())); sys.exit(0)
if a[0] == "ls":
    folder = a[-1]
    print(json.dumps({"struct_type": "snapshot"}))
    for n, t in (("notes.txt", "file"), ("Photos", "dir")):
        print(json.dumps({"struct_type": "node", "path": folder.rstrip("/") + "/" + n, "type": t, "size": 10}))
    sys.exit(0)
if a[0] == "restore":
    target, inc = a[a.index("--target") + 1], a[a.index("--include") + 1]
    p = os.path.join(target, inc.lstrip("/")); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write("restored")
    sys.exit(0)
'''


class Backup(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.log = os.path.join(self.h.dir, "restic-calls")
        p = os.path.join(self.s.dir, "restic")
        with open(p, "w") as f:
            f.write(RESTIC % (sys.executable, self.log))
        os.chmod(p, 0o755)
        self.s.add("secret-tool", missing=True)            # (the key in a file: no keyring here)
        self.repo = os.path.join(self.h.dir, "drive", "Slate Backups")
        os.makedirs(os.path.join(self.h.dir, "drive"))
        self.settings({})

    def settings(self, extra):
        os.makedirs(os.path.join(self.h.config, "slate"), exist_ok=True)
        with open(os.path.join(self.h.config, "slate", "settings.json"), "w") as f:
            json.dump(dict({"backupTo": self.repo}, **extra), f)

    def call(self, *args):
        code, out = run(["python3", SCRIPT, *args], env=self.s.env, timeout=60)
        self.assertEqual(code, 0, out)
        try:
            return json.loads(out)
        except ValueError:
            return out.strip()

    def calls(self):
        with open(self.log) as f:
            return [json.loads(l) for l in f]

    def test_set_up_back_up_and_restore(self):
        self.assertTrue(self.call("setup", self.repo)["ok"])
        key = os.path.join(self.h.state, "slate", "backup-key")
        self.assertEqual(stat.S_IMODE(os.stat(key).st_mode), 0o600, "the key isn't yours alone")
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(key)).st_mode), 0o700)
        self.assertGreater(len(open(key).read()), 30)
        self.assertEqual(self.call("status")["keyIn"], "file")
        self.assertEqual(self.call("due"), "yes", "a backup isn't due straight after setting up")
        self.assertTrue(self.call("run")["ok"])
        backup = [c for c in self.calls() if c["args"][0] == "backup"][0]["args"]
        self.assertIn(self.h.home, backup, "the home folder wasn't backed up")
        for skipped in (os.path.join(self.h.cache), os.path.join(self.h.data, "Trash")):
            self.assertIn(skipped, backup, "%s wasn't left out" % skipped)
        st = self.call("status")
        self.assertTrue(st["lastOk"])
        self.assertEqual(st["lastSize"], 1234)
        self.assertTrue(self.call("due").startswith("no"), "due again straight after a backup")
        snaps = self.call("snapshots")
        self.assertEqual(len(snaps), 1)
        entries = self.call("ls", snaps[0]["id"], self.h.home)
        self.assertEqual([e["name"] for e in entries], ["Photos", "notes.txt"], "folders first, then files")
        mine = os.path.join(self.h.home, "notes.txt")
        with open(mine, "w") as f:
            f.write("mine")
        r = self.call("restore", snaps[0]["id"], mine)
        self.assertTrue(r["ok"])
        self.assertTrue(r["to"].startswith(os.path.join(self.h.home, "Restored from backup")))
        self.assertEqual(open(mine).read(), "mine", "restoring wrote over your file")

    def test_personal_folders_only(self):
        for d in ("Documents", "Pictures"):
            os.makedirs(os.path.join(self.h.home, d))
        self.settings({"backupWhat": "personal"})
        self.call("setup", self.repo)
        self.call("run")
        backup = [c for c in self.calls() if c["args"][0] == "backup"][0]["args"]
        self.assertIn(os.path.join(self.h.home, "Documents"), backup)
        self.assertNotIn(self.h.home, backup, "the whole home folder was backed up")

    def test_not_due_when_away_or_by_hand(self):
        self.call("setup", self.repo)
        self.settings({"backupSchedule": "manual"})
        self.assertEqual(self.call("due"), "no: only by hand")
        self.settings({"backupTo": os.path.join(self.h.dir, "unplugged")})
        self.assertTrue(self.call("due").startswith("no"))

    def test_another_keys_backup_isnt_taken(self):
        os.makedirs(self.repo)
        with open(os.path.join(self.repo, "config"), "w") as f:
            f.write("somebody else's key")
        self.assertEqual(self.call("setup", self.repo)["error"], "locked")

    def test_without_restic(self):
        self.s.add("restic", missing=True)
        self.assertEqual(self.call("setup", self.repo)["error"], "restic")
        self.assertFalse(self.call("status")["restic"])
