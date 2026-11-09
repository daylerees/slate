"""scripts/open-with.sh: files dropped on an app in the dock are opened with that app, by
its desktop entry (found where the desktop keeps them) and launched through `gio launch`
(stubbed: nothing is ever opened)."""
import os

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "open-with.sh")

ENTRY = "[Desktop Entry]\nType=Application\nName={name}\nExec={exec} %F\nMimeType={mime}\n"


class OpenWith(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.s.add("gio")
        # Two system folders (like /usr/share and Flatpak's), both inside the scratch dir
        self.sys1 = os.path.join(self.h.dir, "usr-share")
        self.sys2 = os.path.join(self.h.dir, "flatpak-exports")
        self.s.env["XDG_DATA_DIRS"] = f"{self.sys1}:{self.sys2}"
        self.docs = self.h("Documents")
        os.makedirs(self.docs)

    def entry(self, top, app_id, name="App", exec_="app", mime=""):
        d = os.path.join(top, "applications")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, app_id + ".desktop")
        with open(p, "w") as f:
            f.write(ENTRY.format(name=name, exec=exec_, mime=mime))
        return p

    def file(self, name):
        p = os.path.join(self.docs, name)
        open(p, "w").close()
        return p

    def open_with(self, *args, env=None):
        return run(["sh", SCRIPT, *args], env=env or self.s.env)

    def test_file_types(self):
        """Whatever the file, it's handed to gio with the app's desktop entry, as given."""
        viewer = self.entry(self.sys1, "org.gnome.Papers", "Papers", "papers", "application/pdf;")
        images = self.entry(self.sys1, "org.gnome.Loupe", "Image Viewer", "loupe", "image/png;image/jpeg;")
        editor = self.entry(self.sys1, "org.gnome.TextEditor", "Text Editor", "gnome-text-editor", "text/plain;")
        for entry, app_id, name in [(viewer, "org.gnome.Papers", "report.pdf"),
                                    (images, "org.gnome.Loupe", "photo.jpg"),
                                    (editor, "org.gnome.TextEditor", "notes.txt")]:
            with self.subTest(name):
                f = self.file(name)
                before = len(self.s.calls("gio"))
                code, out = self.open_with(app_id, f)
                self.assertEqual(code, 0, out)
                self.assertEqual(self.s.calls("gio")[before:], [["launch", entry, f]])

    def test_several_files_odd_names(self):
        """Several files at once, with spaces, colons, quotes and non-ASCII names kept whole."""
        app = self.entry(self.sys1, "org.gnome.Loupe")
        files = [self.file(n) for n in ("holiday photo.png", "a:b.png", "it's.png", "café 2026.jpg", "-dash.png")]
        code, out = self.open_with("org.gnome.Loupe", *files)
        self.assertEqual(code, 0, out)
        self.assertEqual(self.s.calls("gio"), [["launch", app] + files])

    def test_your_own_first(self):
        """Your own entry (~/.local/share/applications) wins over the system's."""
        self.entry(self.sys1, "org.example.Editor")
        mine = self.entry(self.h.data, "org.example.Editor", exec_="editor --mine")
        f = self.file("notes.txt")
        self.assertEqual(self.open_with("org.example.Editor", f)[0], 0)
        self.assertEqual(self.s.calls("gio"), [["launch", mine, f]])

    def test_later_data_dir(self):
        """An entry only in a later XDG_DATA_DIRS folder (e.g. Flatpak's) is found."""
        app = self.entry(self.sys2, "org.example.Flat")
        f = self.file("notes.txt")
        self.assertEqual(self.open_with("org.example.Flat", f)[0], 0)
        self.assertEqual(self.s.calls("gio"), [["launch", app, f]])

    def test_order_of_data_dirs(self):
        first = self.entry(self.sys1, "org.example.Both")
        self.entry(self.sys2, "org.example.Both")
        f = self.file("notes.txt")
        self.open_with("org.example.Both", f)
        self.assertEqual(self.s.calls("gio"), [["launch", first, f]])

    def test_no_xdg_data_home(self):
        """Without XDG_DATA_HOME, your own entries are looked for in ~/.local/share."""
        env = dict(self.s.env)
        del env["XDG_DATA_HOME"]
        mine = self.entry(self.h(".local", "share"), "org.example.Mine")
        f = self.file("notes.txt")
        self.assertEqual(self.open_with("org.example.Mine", f, env=env)[0], 0)
        self.assertEqual(self.s.calls("gio"), [["launch", mine, f]])

    def test_not_found(self):
        f = self.file("notes.txt")
        code, out = self.open_with("org.example.Missing", f)
        self.assertEqual(code, 1)
        self.assertEqual(out, "open-with: no org.example.Missing.desktop found\n")
        self.assertEqual(self.s.calls("gio"), [])

    def test_folder_named_like_an_entry(self):
        """Only a file counts as the entry, not a folder with its name."""
        os.makedirs(os.path.join(self.sys1, "applications", "org.example.Odd.desktop"))
        code, _ = self.open_with("org.example.Odd", self.file("notes.txt"))
        self.assertEqual(code, 1)
        self.assertEqual(self.s.calls("gio"), [])

    def test_no_app(self):
        for args in ([], [""]):
            with self.subTest(args=args):
                self.assertEqual(self.open_with(*args)[0], 1)
        self.assertEqual(self.s.calls("gio"), [])

    def test_launch_fails(self):
        """gio's own failure is passed on."""
        self.s.add("gio", stdout="gio: Failed to launch\n", code=2)
        self.entry(self.sys1, "org.example.Broken")
        code, out = self.open_with("org.example.Broken", self.file("notes.txt"))
        self.assertEqual(code, 2)
        self.assertIn("Failed to launch", out)
