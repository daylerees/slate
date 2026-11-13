"""tests/run without the vkms module: the live and visual tiers say how to load it, now and at
every boot, and run nothing. A fake docker stands in and SLATE_TEST_DRM points the card search
at a scratch folder, so nothing is built, run or unloaded."""
import os

import slate
from slate import Case, run

RUNNER = slate.path("tests", "run")
DOCKER = """#!/bin/sh
echo "$*" >> "{log}"
case "$1" in image) exit 0 ;; esac
exit 0
"""


class NoVkms(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.bin = os.path.join(self.h.dir, "bin")
        self.drm = os.path.join(self.h.dir, "drm")
        self.log = os.path.join(self.h.dir, "docker.log")
        os.makedirs(self.bin)
        os.makedirs(os.path.join(self.drm, "card0", "device"))      # (a real GPU's card, no driver link)
        with open(os.path.join(self.bin, "docker"), "w") as f:
            f.write(DOCKER.format(log=self.log))
        os.chmod(os.path.join(self.bin, "docker"), 0o755)
        self.env = dict(self.h.env, PATH=self.bin + ":" + self.h.env["PATH"], SLATE_TEST_DRM=self.drm,
                        SLATE_TEST_OUT=os.path.join(self.h.dir, "out"))
        self.env.pop("CI", None)

    def test_says_how_to_load_it_now_and_at_every_boot(self):
        code, out = run([RUNNER, "--tier", "live", "-q"], env=self.env, timeout=60)
        self.assertEqual(code, 2, out)
        self.assertIn("    sudo modprobe vkms\n", out)
        self.assertIn("    echo vkms | sudo tee /etc/modules-load.d/slate-tests.conf\n", out)
        with open(self.log) as f:
            self.assertNotIn("run ", f.read(), "nothing runs without it")

    def test_the_docs_say_the_same(self):
        self.assertIn("echo vkms | sudo tee /etc/modules-load.d/slate-tests.conf", slate.read("docs", "TESTING.md"))
