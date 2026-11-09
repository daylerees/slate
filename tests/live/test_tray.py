"""The tray: an app that signs its icon up only once (as Electron apps do) keeps it in Slate's
tray when Slate restarts, since the register runs apart from Slate (scripts/tray-watcher.py)."""
import os
import subprocess
import time

import slate
from live import LiveCase


class Tray(LiveCase):
    def test_icon_survives_a_full_restart(self):
        app = subprocess.Popen(["python3", os.path.join(slate.FIXTURES, "live", "fake_tray_app.py")],
                               env=self.s.env, stdout=subprocess.PIPE, text=True)
        self.addCleanup(app.kill)
        self.assertEqual(app.stdout.readline().strip(), "registered")
        self.wait(lambda st: "fake" in st["tray"], "the icon in the tray")
        # A full restart: a new Slate process (as updates and Settings → Debug → Reload do)
        ready = os.path.join(self.s.h.runtime, "slate-ready")
        os.remove(ready)
        self.s.run([os.path.join(self.s.slate_dir, "bin", "slate"), "restart", "--full"], timeout=30)
        for _ in range(120):
            if os.path.exists(ready):
                break
            time.sleep(0.25)
        else:
            self.fail("Slate didn't come back")
        self.s.settle(1)
        self.wait(lambda st: "fake" in st["tray"], "the icon still in the tray after the restart", timeout=10)
        self.s.new_log_errors()        # (the restart's own start-up is checked by test_session)
