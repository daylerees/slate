"""scripts/storage.py (Settings → Storage): the drives, what's using the space, and clearing old
caches, in a scratch home."""
import json
import os
import time

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "storage.py")


class Storage(Case):
    scratch = True

    def call(self, *args, env=None):
        code, out = run(["python3", SCRIPT, *args], env=dict(self.h.env, SLATE_TEST="1", **(env or {})), timeout=60)
        self.assertEqual(code, 0, out)
        return json.loads(out)

    def put(self, rel, size, age_days=0):
        p = os.path.join(self.h.home, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(b"x" * size)
        if age_days:
            t = time.time() - age_days * 86400
            os.utime(p, (t, t))
        return p

    def test_drives_are_real_filesystems_once_each(self):
        mounts = os.path.join(self.h.dir, "mounts")
        with open(mounts, "w") as f:
            f.write("proc /proc proc rw 0 0\n"
                    "tmpfs /run tmpfs rw 0 0\n"
                    "/dev/nvme0n1p2 %s btrfs rw,subvol=/@ 0 0\n"
                    "/dev/nvme0n1p2 %s btrfs rw,subvol=/@home 0 0\n"
                    "/dev/nvme0n1p1 /boot vfat rw 0 0\n"
                    "/dev/sdb1 /run/media/me/Photo\\040Card exfat rw 0 0\n" % (self.h.dir, self.h.dir))
        drives = self.call("drives", env={"SLATE_TEST_MOUNTS": mounts})
        self.assertEqual(len(drives), 1, "the same filesystem twice, or proc/tmpfs/boot counted: %s" % drives)
        d = drives[0]
        self.assertEqual(d["mount"], self.h.dir)
        self.assertGreater(d["size"], 0)
        self.assertLessEqual(d["free"], d["size"])
        self.assertFalse(d["removable"])

    def test_what_uses_the_space_by_kind(self):
        self.put("Downloads/big.iso", 3_000_000)
        self.put("Pictures/a.jpg", 1_000_000)
        self.put(".cache/app/blob", 2_000_000)
        self.put(".local/share/Trash/files/old.txt", 500_000)
        self.put("Notes/n.txt", 700_000)
        d = self.call("kinds")
        k = d["kinds"]
        self.assertGreaterEqual(k["downloads"], 3_000_000)
        self.assertGreaterEqual(k["pictures"], 1_000_000)
        self.assertGreaterEqual(k["caches"], 2_000_000)
        self.assertGreaterEqual(k["trash"], 500_000)
        self.assertGreaterEqual(k["other"], 700_000, "a folder of its own isn't counted under everything else")
        self.assertEqual(d["biggest"][0]["name"], "Downloads", d["biggest"])
        # Kept, for the page to show at once next time
        self.assertEqual(self.call("cached")["kinds"], k)

    def test_clearing_takes_only_old_caches_and_thumbnails(self):
        old = self.put(".cache/app/old.bin", 100_000, age_days=40)
        new = self.put(".cache/app/new.bin", 100_000)
        thumb = self.put(".cache/thumbnails/large/t.png", 50_000)
        mine = self.put("Documents/keep.txt", 10_000, age_days=400)
        freed = self.call("clear-caches")["freed"]
        self.assertGreaterEqual(freed, 150_000)
        self.assertFalse(os.path.exists(old), "an old cache file stayed")
        self.assertFalse(os.path.exists(thumb), "thumbnails stayed")
        self.assertTrue(os.path.exists(new), "a cache file in use was deleted")
        self.assertTrue(os.path.exists(mine), "one of your own files was touched")
