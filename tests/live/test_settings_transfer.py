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
        # (both: one with the same name may be listed already, from an export earlier the same day)
        st = self.wait(lambda st: st["settings"]["section"] == "transfer" and name in st["settings"]["transferFiles"]
                       and "Broken (unreadable)" in st["settings"]["transferFiles"], "the exported file in the list", timeout=15)
        self.assertIn("Broken (unreadable)", st["settings"]["transferFiles"])


class ExportButtons(LiveCase):
    """Import & Export's and Debug's Export buttons (one ExportRow, shared): pressing one saves
    the file, and Import & Export lists what it just made."""

    def test_export_your_settings(self):
        docs = os.path.join(self.s.h.home, "Documents")
        before = set(os.listdir(docs)) if os.path.isdir(docs) else set()
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "transfer")
        self.wait(lambda st: st["settings"]["section"] == "transfer", "Import & Export")
        self.ipc("test", "settingsButton", "Export your settings", "Export")
        new = lambda: sorted(set(os.listdir(docs)) - before) if os.path.isdir(docs) else []
        self.wait(lambda st: any(n.endswith(".slate-settings") for n in new()), "the settings file", timeout=20)
        made = [n for n in new() if n.endswith(".slate-settings")][0]
        self.addCleanup(lambda: os.remove(os.path.join(docs, made)))
        self.wait(lambda st: made[:-len(".slate-settings")] in st["settings"]["transferFiles"], "the new file in the list", timeout=15)

    def test_export_recent_logs(self):
        downloads = os.path.join(self.s.h.home, "Downloads")
        os.makedirs(downloads, exist_ok=True)
        before = set(os.listdir(downloads))
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "debug")
        self.wait(lambda st: st["settings"]["section"] == "debug", "Debug")
        self.ipc("test", "settingsButton", "Export recent logs", "Export")
        self.wait(lambda st: any(n.startswith("slate-logs-") for n in set(os.listdir(downloads)) - before), "the log file", timeout=30)
        for n in set(os.listdir(downloads)) - before:
            self.addCleanup(lambda n=n: os.remove(os.path.join(downloads, n)))
