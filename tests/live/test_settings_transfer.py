"""Settings → Import & Export lists the settings files in the usual folders: one exported shows
up there, and one that isn't a Slate settings file is listed as unreadable rather than offered
(scripts/settings-transfer.py has the unit tests for exporting and importing)."""
import os

from live import LiveCase


class ImportList(LiveCase):
    def test_exported_files_are_listed(self):
        docs = os.path.join(self.s.h.home, "Documents")
        downloads = os.path.join(self.s.h.home, "Downloads")
        os.makedirs(downloads, exist_ok=True)
        broken = os.path.join(downloads, "Broken.slate-settings")
        with open(broken, "w") as f:
            f.write("not a zip")
        self.addCleanup(lambda: os.path.exists(broken) and os.remove(broken))
        made = self.s.run(["python3", os.path.join(self.s.slate_dir, "scripts", "settings-transfer.py"), "export", docs], check=True)[1].strip()
        self.addCleanup(lambda: os.path.exists(made) and os.remove(made))
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "transfer")
        name = os.path.basename(made)[:-len(".slate-settings")]
        st = self.wait(lambda st: st["settings"]["section"] == "transfer" and name in st["settings"]["transferFiles"],
                       "the exported file in the list", timeout=15)
        self.assertIn("Broken (unreadable)", st["settings"]["transferFiles"])
