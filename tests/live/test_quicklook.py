"""Quick Look (QuickLook.qml): a large preview of a file, from the launcher's results, the dock's
Downloads and the Waste Basket. Each kind of file gets its own view (a picture, text, a PDF's
pages), anything else its details with Open; Space or Escape closes it; a file's name is shown
as it is, never read as markup."""
import os
import shutil

from live import LiveCase

ODD = '<b>notes<i> & "quotes" #1?.txt'       # (markup, an ampersand, a quote, # and ?: no slash, it can't be in a name)


class QuickLook(LiveCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: self.ipc("quicklook", "close"))

    def file(self, *parts, data=b""):
        p = self.s.h(*parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)
        return p

    def picture(self, *parts, size=(640, 480)):
        from PIL import Image
        p = self.s.h(*parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        Image.new("RGB", size, "#3a7bd5").save(p)
        return p

    def pdf(self, *parts, pages=2):
        from PIL import Image
        p = self.s.h(*parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        imgs = [Image.new("RGB", (600, 800), c) for c in ("white", "#ccddee", "#eeddcc")[:pages]]
        imgs[0].save(p, save_all=True, append_images=imgs[1:])
        return p

    def look(self, path):
        self.ipc("quicklook", "open", path)
        return self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["path"] == path
                         and st["quicklook"]["view"] != "loading", f"Quick Look on {os.path.basename(path)}")["quicklook"]

    def key(self, *args):
        """A real key press (wtype: -s waits a moment for its keymap). Each wtype is a new
        virtual keyboard, and its first key can arrive before Slate has its keymap and be lost
        (it was, now and then, for a key to a window that had only just taken the keyboard):
        a Shift first, which nothing here minds, takes that place."""
        self.s.run(["wtype", "-s", "300", "-k", "Shift_L", *args], check=True)

    def closed(self, what="Quick Look to close"):
        self.wait(lambda st: not st["quicklook"]["open"], what)

    # ---- Each kind --------------------------------------------------------------------------

    def test_a_picture(self):
        p = self.picture("Pictures", "beach.png")
        st = self.look(p)
        self.assertEqual(st["view"], "image")
        st = self.wait(lambda st: st["quicklook"]["image"] is not None, "the picture drawn")["quicklook"]
        self.assertEqual(st["image"], [640, 480], f"a picture that fits is shown at its own size: {st}")
        self.assertIn("640 × 480", st["details"])
        self.assertEqual(st["name"], "beach.png")
        self.screenshot("quicklook-picture")

    def test_a_big_picture_fits_the_screen(self):
        p = self.picture("Pictures", "huge.png", size=(5000, 3000))
        self.look(p)
        st = self.wait(lambda st: st["quicklook"]["image"] is not None, "the picture drawn")["quicklook"]
        scr = self.s.state()["screens"][0]
        self.assertLessEqual(st["card"][0], scr["width"])
        self.assertLessEqual(st["card"][1], scr["height"])
        self.assertLess(st["image"][0], 5000, "decoded at full size, not near the size it's shown at")
        self.assertIn("5000 × 3000", st["details"])

    def test_text_and_an_odd_name(self):
        p = self.file("Documents", ODD, data=b"<i>not italic</i>\nline two\n")
        st = self.look(p)
        self.assertEqual(st["view"], "text")
        self.assertEqual(st["name"], ODD, "the name wasn't shown as it is")
        self.assertTrue(st["plain"], "a file's name must be plain text, never markup")
        self.assertEqual(st["textLength"], len("<i>not italic</i>\nline two\n"))
        self.assertFalse(st["code"], "a .txt is read in the interface's font")
        self.assertFalse(st["cut"])

    def test_code_and_a_long_file(self):
        p = self.file("Documents", "big.py", data=(b"print('hello world')  # " + b"x" * 40 + b"\n") * 5000)
        st = self.look(p)
        self.assertEqual(st["view"], "text")
        self.assertTrue(st["code"], "code is in the code font")
        self.assertTrue(st["cut"], "only the first 200 KB is read")
        self.assertEqual(st["textLength"], 200 * 1024)

    def test_a_pdf(self):
        p = self.pdf("Documents", "two pages.pdf")
        st = self.look(p)
        if shutil.which("pdftoppm"):
            self.assertEqual(st["view"], "pdf")
            st = self.wait(lambda st: st["quicklook"]["pagesDone"], "the pages drawn", timeout=20)["quicklook"]
            self.assertEqual(st["pages"], 2)
            self.assertIn("2 pages", st["details"])
        else:
            # Without poppler's pdftoppm: its details, and what to install
            self.assertEqual(st["view"], "details")
            self.assertIn("poppler", st["note"])

    def test_anything_else_shows_its_details(self):
        p = self.file("Downloads", "data.bin", data=bytes(range(256)) * 8)
        st = self.look(p)
        self.assertEqual(st["view"], "details")
        self.assertEqual(st["name"], "data.bin")
        self.assertTrue(st["plain"])
        self.assertIn("2.0 KB", st["details"])
        self.assertEqual(st["note"], "")
        self.screenshot("quicklook-details")

    def test_a_folder(self):
        os.makedirs(self.s.h("Projects", "slate-notes"), exist_ok=True)
        for n in ("a", "b", "c"):
            self.file("Projects", "slate-notes", n)
        st = self.look(self.s.h("Projects", "slate-notes"))
        self.assertEqual(st["view"], "details")
        self.assertIn("3 items", st["details"])

    def test_the_file_managers_command(self):
        """What Dolphin's and Thunar's Quick Look items run (scripts/apply-theme.py): the path
        after "--", which the command line takes as the end of its options, not an argument."""
        p = self.file("Documents", "--from a menu.txt", data=b"hi\n")
        self.s.run(["qs", "-p", self.s.slate_dir, "ipc", "call", "quicklook", "open", "--", p], check=True)
        self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["path"] == p, "Quick Look from the menu's command")

    # ---- Closing ----------------------------------------------------------------------------

    def test_space_and_escape_close_it(self):
        p = self.file("Documents", "close me.txt", data=b"hello\n")
        self.look(p)
        self.key("-k", "space")
        self.closed("Space to close it")
        self.look(p)
        self.key("-k", "Escape")
        self.closed("Escape to close it")

    # ---- From the launcher ------------------------------------------------------------------

    def recent(self, paths):
        marks = "".join(
            f'  <bookmark href="file://{p}" added="2024-05-0{i + 1}T10:00:00Z" '
            f'modified="2024-05-0{i + 1}T10:00:00Z" visited="2024-05-0{i + 1}T10:00:00Z"/>\n'
            for i, p in enumerate(paths))
        path = os.path.join(self.s.h.data, "recently-used.xbel")
        with open(path + ".new", "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<xbel version="1.0">\n' + marks + "</xbel>\n")
        os.replace(path + ".new", path)

    def test_space_on_a_file_in_the_launcher(self):
        first = self.file("Documents", "zephyr-one.txt", data=b"one\n")
        second = self.picture("Documents", "zephyr-two.png")
        self.recent([first, second])
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.ipc("launcher", "open")
        self.wait(lambda st: st["launcher"]["open"], "the launcher")
        self.ipc("launcher", "search", "zephyr")
        st = self.wait(lambda st: "zephyr-two.png" in st["launcher"]["results"] and "zephyr-one.txt" in st["launcher"]["results"],
                       "the two files", timeout=10)["launcher"]
        # Moved to with the keys (the text file, after the newer picture), Space shows it
        down = st["results"].index("zephyr-one.txt")
        self.assertGreater(down, 0)
        # (one wtype for both: a second, straight after, lost its keys to the launcher)
        self.key(*["-k", "Down"] * down, "-k", "space")
        st = self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["view"] == "text", "Quick Look on the text file")["quicklook"]
        self.assertEqual(st["path"], first)
        self.assertEqual(st["count"], 2, "the other file in the results, to step to")
        self.assertEqual(self.s.state()["launcher"]["query"], "zephyr", "Space went into the search too")
        # Left: the file before it in the results
        self.key("-k", "Left")
        self.wait(lambda st: st["quicklook"]["path"] == second and st["quicklook"]["view"] == "image", "the file before it")
        # Escape: Quick Look closes, the launcher stays, with the keyboard back
        self.key("-k", "Escape")
        self.closed()
        self.assertTrue(self.s.state()["launcher"]["open"], "the launcher closed with Quick Look")
        self.key("x")
        self.wait(lambda st: st["launcher"]["query"] == "zephyrx", "typing to reach the launcher again")

    def test_space_while_typing_is_a_space(self):
        p = self.file("Documents", "quokka.txt", data=b"q\n")
        self.recent([p])
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.ipc("launcher", "open")
        self.ipc("launcher", "search", "quokka")
        self.wait(lambda st: st["launcher"]["results"][:1] == ["quokka.txt"], "the file first", timeout=10)
        self.key("-k", "space", "x")          # (the query is trimmed: a letter after, so the space shows)
        self.wait(lambda st: st["launcher"]["query"] == "quokka x", "a space in the search")
        self.assertFalse(self.s.state()["quicklook"]["open"])

    # ---- From the dock ----------------------------------------------------------------------

    def test_space_in_the_dock_downloads(self):
        self.keep_setting("dockShowDownloads")
        self.config("dockShowDownloads", "true")
        p = self.file("Downloads", "invoice.txt", data=b"total: 12\n")
        self.ipc("dock", "downloads")
        st = self.wait(lambda st: (st["dock"]["files"] or [])[:1] == ["invoice.txt"], "the download in the grid", timeout=10)
        self.ipc("test", "dockHoverFile", "0")
        self.key("-k", "space")
        st = self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["view"] == "text", "Quick Look on the download")["quicklook"]
        self.assertEqual(st["path"], p)
        self.assertEqual(self.s.state()["dock"]["menu"], "", "the menu stayed open under it")
        self.key("-k", "space")
        self.closed()

    def test_quick_look_on_a_file_in_the_waste_basket(self):
        self.keep_setting("dockShowTrash")
        self.config("dockShowTrash", "true")
        p = self.picture(".local", "share", "Trash", "files", "old photo.png")
        self.file(".local", "share", "Trash", "info", "old photo.png.trashinfo",
                  data=b"[Trash Info]\nPath=/tmp/old photo.png\nDeletionDate=2026-01-05T09:00:00\n")
        self.addCleanup(lambda: [os.remove(x) for x in (p, p.replace("/files/", "/info/") + ".trashinfo") if os.path.exists(x)])
        self.ipc("dock", "trash")
        self.wait(lambda st: "old photo.png" in (st["dock"]["files"] or []), "the Waste Basket's grid", timeout=10)
        st = self.s.state()["dock"]
        self.assertIn("Open Waste Basket", st["menuItems"])
        # Its right-click menu: Quick Look, chosen with the keys
        self.ipc("dock", "fileMenu", str(st["files"].index("old photo.png")))
        self.wait(lambda st: st["dock"]["menuItems"] == ["Quick Look", "Open"], "the file's own menu")
        self.key("-k", "Down", "-k", "Return")
        st = self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["view"] == "image", "Quick Look from the menu")["quicklook"]
        self.assertEqual(st["path"], p)
