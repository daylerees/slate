"""Recent files with an apostrophe, & or # in their names: the desktop's list of them
(recently-used.xbel) is XML, so GLib writes "Tom's & Jerry #1.txt" as
Tom&#39;s%20%26%20Jerry%20%231.txt and the launcher showed the escapes, or (a broken % in another entry)
none of them at all."""
import os

from live import LiveCase

NAME = "Tom's & Jerry #1.txt"


class RecentFileNames(LiveCase):
    def write(self, hrefs):
        path = os.path.join(self.s.h.data, "recently-used.xbel")
        marks = "".join(f'  <bookmark href="{h}" added="2024-05-0{i + 1}T10:00:00Z" modified="2024-05-0{i + 1}T10:00:00Z" '
                        f'visited="2024-05-0{i + 1}T10:00:00Z"/>\n' for i, h in enumerate(hrefs))
        with open(path + ".new", "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<xbel version="1.0">\n' + marks + "</xbel>\n")
        os.replace(path + ".new", path)
        self.addCleanup(lambda: os.path.exists(path) and os.remove(path))

    def test_names_come_out_as_they_are(self):
        self.keep_setting("launcherFiles")
        self.config("launcherFiles", "true")
        docs = self.s.h("Documents")
        os.makedirs(docs, exist_ok=True)
        open(os.path.join(docs, NAME), "w").close()
        # (as GLib writes it: the path URL-encoded, & and # included, then the ' as XML)
        href = "file://" + docs + "/Tom&#39;s%20%26%20Jerry%20%231.txt"
        self.write([href, "file://" + docs + "/broken%E0%A4%A.txt"])
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.ipc("launcher", "search", "Jerry")
        st = self.wait(lambda st: st["launcher"]["open"] and NAME in st["launcher"]["results"],
                       "the file under its own name", timeout=10)["launcher"]
        self.assertFalse([r for r in st["results"] if "&#39;" in r or "%" in r], st["results"])


class OpenWindowResult(LiveCase):
    """Choosing an open window in the launcher goes to it, wherever it is: it asked the window to
    activate itself, which Hyprland ignores (and it won't move focus while the launcher holds
    the keyboard), so nothing happened."""

    def test_enter_on_a_window_goes_to_it(self):
        self.keep_setting("launcherWindows")
        self.config("launcherWindows", "true")
        title = "slate-find-me"
        self.s.hyprctl("dispatch", 'function() hl.exec_cmd("foot --title %s sleep 60", { workspace = "2 silent" }) end' % title)
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() for _, w in ipairs(hl.get_windows()) do if w.title == '%s' then hl.dispatch(hl.dsp.window.close({ window = 'address:' .. w.address })) end end end" % title))
        self.wait(lambda st: any(w["title"] == title and w["workspace"] == 2 for w in st["windows"]), "the window on workspace 2", timeout=15)
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = 1 })) end")
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.ipc("launcher", "search", title)
        self.wait(lambda st: st["launcher"]["open"] and st["launcher"]["results"][:1] == [title], "the window first in the results")
        self.s.settle(0.4)
        self.press("-k", "Return")
        self.wait(lambda st: self.s.hyprctl("activewindow", json_out=True).get("title") == title, "the window focused", timeout=8)
