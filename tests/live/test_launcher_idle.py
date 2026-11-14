"""The launcher while it's closed: it does nothing. A session of its own, with a list of recent
files there from the start (as on a desktop that's been used), so what the first opening shows
is known, and nothing else is opening the launcher meanwhile.

It used to keep working: closed with a few letters still in its box, it went on searching the
open windows' titles, so every title that changed anywhere (a browser's tab, a terminal) made
its rows again; and it read the whole list of recent files again each time any app added to it."""
import atexit
import os
import unittest

from live import LiveCase
from session import Session, in_container


def recent_files(h, names):
    """The desktop's list of recent files (recently-used.xbel) holding these, put in place the
    way apps do it: written beside it, then moved over it."""
    marks = "".join(
        f'  <bookmark href="file://{h("Documents", n)}" added="2024-05-0{i + 1}T10:00:00Z" '
        f'modified="2024-05-0{i + 1}T10:00:00Z" visited="2024-05-0{i + 1}T10:00:00Z"/>\n'
        for i, n in enumerate(names))
    path = os.path.join(h.data, "recently-used.xbel")
    with open(path + ".new", "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<xbel version="1.0">\n' + marks + "</xbel>\n")
    os.replace(path + ".new", path)


class LauncherIdle(LiveCase):
    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session()
        recent_files(cls.s.h, ["quarterly-report.pdf"])
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()

    def search(self, text):
        self.ipc("launcher", "search", text)
        return self.wait(lambda st: st["launcher"]["open"] and st["launcher"]["query"] == text, f"the search for {text}")

    def close(self):
        self.ipc("launcher", "close")
        self.wait(lambda st: not st["launcher"]["visible"], "the launcher to close")
        self.s.settle(0.4)
        return self.s.state()["launcher"]

    def titles(self):
        return [c.get("title") for c in self.s.hyprctl("clients", json_out=True) if c.get("mapped")]

    def test_1_recent_files_are_there_the_first_time(self):
        """(first: the first opening after Slate starts)"""
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.search("quarterly")
        self.wait(lambda st: "quarterly-report.pdf" in st["launcher"]["results"], "the recent file")

    def test_closed_it_takes_no_notice_of_window_titles(self):
        # A window whose title is whatever its file says
        title = self.s.h("window-title")
        script = self.s.h("window-title.sh")
        with open(title, "w") as f:
            f.write("zebra crossing")
        with open(script, "w") as f:
            f.write('#!/bin/sh\nwhile :; do printf \'\\033]2;%s\\007\' "$(cat "$1")"; sleep 0.2; done\n')
        os.chmod(script, 0o755)
        self.addCleanup(self.close_windows)
        self.s.hyprctl("eval", f'hl.exec_cmd("foot {script} {title}")')
        self.s._until(lambda: "zebra crossing" in self.titles(), 20, "the window didn't open")

        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.search("zeb")
        self.wait(lambda st: "zebra crossing" in st["launcher"]["results"], "the window among the results")
        before = self.close()["syncs"]

        with open(title, "w") as f:
            f.write("zebra finch")
        self.s._until(lambda: "zebra finch" in self.titles(), 20, "the window's title didn't change")
        self.s.settle(0.6)
        st = self.s.state()["launcher"]
        self.assertEqual(st["syncs"], before, "the closed launcher made its rows again when a window's title changed")
        self.assertEqual(st["query"], "", "the closed launcher kept what was typed")

        # Open, it still follows the titles
        self.search("zeb")
        self.wait(lambda st: "zebra finch" in st["launcher"]["results"], "the window by its new title")

    def test_closed_it_leaves_the_recent_files_unread(self):
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.search("quarterly")
        self.wait(lambda st: "quarterly-report.pdf" in st["launcher"]["results"], "the recent file")
        before = self.close()["recentReads"]

        recent_files(self.s.h, ["quarterly-report.pdf", "holiday-plans.odt"])
        self.s.settle(1.0)
        self.assertEqual(self.s.state()["launcher"]["recentReads"], before,
                         "the closed launcher read the recent files again when they changed")

        # The next opening has the new one
        self.search("holiday")
        self.wait(lambda st: "holiday-plans.odt" in st["launcher"]["results"], "the file added while it was closed")
        # And open, it follows the list as it changes
        recent_files(self.s.h, ["quarterly-report.pdf", "holiday-plans.odt", "holiday-budget.ods"])
        self.wait(lambda st: "holiday-budget.ods" in st["launcher"]["results"], "the file added while it was open")
