"""Slate saves its files through Quickshell's FileView, which makes the folder a file goes in when
it's missing. Slate counts on it: a few saves started a `mkdir` in the background just before
writing, without waiting for it, so a first save on a fresh install could have been lost had
FileView not made the folder itself. Those mkdirs are gone (tests/static/test_shared.py checks), and
this checks FileView still does it."""
import os
import shutil

from live import LiveCase


class FileViewMakesFolders(LiveCase):
    def test_a_save_into_a_missing_folder(self):
        top = os.path.join(self.s.h.dir, "fileview-missing")
        shutil.rmtree(top, ignore_errors=True)
        self.addCleanup(shutil.rmtree, top, True)
        path = os.path.join(top, "a", "b", "saved.json")
        self.ipc("test", "fileViewWrite", path, '{"ok": true}')
        for _ in range(40):
            if os.path.exists(path):
                break
            self.s.settle(0.1)
        self.assertTrue(os.path.exists(path), "FileView didn't make the missing folders, so Slate's saves need a mkdir first")
        with open(path) as f:
            self.assertEqual(f.read(), '{"ok": true}')
