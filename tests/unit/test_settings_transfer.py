"""scripts/settings-transfer.py: your settings, saved Spaces, own files and wallpaper in one file
(Settings → Import & Export), and back. Run in a scratch home, without stopping or starting Slate
(SLATE_TRANSFER_NO_RESTART)."""
import io
import json
import os
import stat
import zipfile

import slate
from slate import Case, run

SCRIPT = slate.path("shell", "scripts", "settings-transfer.py")


class Transfer(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.env = dict(self.h.env, SLATE_TRANSFER_NO_RESTART="1")
        self.env.pop("XDG_DOCUMENTS_DIR", None)
        self.user = os.path.join(self.h.config, "slate")
        self.share = os.path.join(self.h.data, "slate")
        self.docs = self.h("Documents")
        os.makedirs(self.docs, exist_ok=True)
        self.pic = self.h("Pictures", "mine.png")
        os.makedirs(os.path.dirname(self.pic), exist_ok=True)
        with open(self.pic, "wb") as f:
            f.write(b"\x89PNG picture")
        self.put(os.path.join(self.user, "settings.json"), json.dumps({"accent": "#ff8800", "wallpaper": self.pic}))
        self.put(os.path.join(self.share, "spaces.json"), json.dumps({"spaces": [{"id": "a", "name": "Work"}]}))
        self.put(os.path.join(self.user, "hypr", "binds.lua"), "-- my binds\n")
        self.put(os.path.join(self.user, "user", "Mine.qml"), "Item {}\n")

    def put(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def read(self, path):
        with open(path) as f:
            return f.read()

    def go(self, *args, code=0):
        c, out = run(["python3", SCRIPT, *args], env=self.env, timeout=60)
        self.assertEqual(c, code, out)
        return out.strip()

    def export(self):
        return self.go("export", self.docs)

    def test_export_holds_everything_and_is_yours_alone(self):
        path = self.export()
        self.assertTrue(path.endswith(".slate-settings"), path)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)
        with zipfile.ZipFile(path) as z:
            names = sorted(z.namelist())
            self.assertEqual(names, ["hypr/binds.lua", "manifest.json", "settings.json", "spaces.json", "user/Mine.qml", "wallpaper/mine.png"])
            manifest = json.loads(z.read("manifest.json"))
        self.assertEqual(manifest["format"], 1)
        self.assertEqual(sorted(manifest["has"]), ["hypr", "settings", "spaces", "user", "wallpaper"])
        # (a second export the same day doesn't overwrite the first)
        self.assertNotEqual(self.export(), path)

    def test_import_puts_everything_in_place_and_undo_puts_it_back(self):
        path = self.export()
        # Another computer: different settings, no wallpaper there, other own files
        os.remove(self.pic)
        self.put(os.path.join(self.user, "settings.json"), json.dumps({"accent": "#0088ff"}))
        self.put(os.path.join(self.share, "spaces.json"), json.dumps({"spaces": []}))
        self.put(os.path.join(self.user, "hypr", "binds.lua"), "-- theirs\n")
        self.put(os.path.join(self.user, "hypr", "extra.lua"), "-- only theirs\n")
        out = json.loads(self.go("import", path))
        self.assertTrue(os.path.isdir(out["backup"]))
        settings = json.loads(self.read(os.path.join(self.user, "settings.json")))
        self.assertEqual(settings["accent"], "#ff8800")
        # The wallpaper came with it, and the setting points at this computer's copy
        self.assertTrue(settings["wallpaper"].startswith(os.path.join(self.share, "wallpapers")), settings["wallpaper"])
        self.assertEqual(open(settings["wallpaper"], "rb").read(), b"\x89PNG picture")
        self.assertEqual(json.loads(self.read(os.path.join(self.share, "spaces.json")))["spaces"][0]["name"], "Work")
        self.assertEqual(self.read(os.path.join(self.user, "hypr", "binds.lua")), "-- my binds\n")
        self.assertFalse(os.path.exists(os.path.join(self.user, "hypr", "extra.lua")), "hypr/ is the file's, whole")
        self.assertEqual(stat.S_IMODE(os.stat(os.path.join(self.user, "settings.json")).st_mode), 0o600)
        self.assertEqual(json.loads(self.go("last"))["backup"], out["backup"])
        # Undo: what was there before the import
        self.go("undo")
        self.assertEqual(json.loads(self.read(os.path.join(self.user, "settings.json")))["accent"], "#0088ff")
        self.assertEqual(self.read(os.path.join(self.user, "hypr", "extra.lua")), "-- only theirs\n")
        self.assertEqual(json.loads(self.read(os.path.join(self.share, "spaces.json"))), {"spaces": []})
        self.assertEqual(self.go("last"), "{}")
        self.go("undo", code=1)

    def test_slates_own_wallpaper_goes_by_name(self):
        own = os.path.join(slate.SHELL, "wallpapers")
        pics = sorted(f for f in os.listdir(own) if f.endswith(".png"))
        self.assertTrue(pics)
        self.put(os.path.join(self.user, "settings.json"), json.dumps({"wallpaper": os.path.join(own, pics[0])}))
        path = self.export()
        with zipfile.ZipFile(path) as z:
            self.assertFalse([n for n in z.namelist() if n.startswith("wallpaper/")], "Slate's own picture was copied")
            self.assertEqual(json.loads(z.read("settings.json"))["wallpaper"], "slate:wallpapers/" + pics[0])
        self.go("import", path)
        settings = json.loads(self.read(os.path.join(self.user, "settings.json")))
        self.assertEqual(os.path.realpath(settings["wallpaper"]), os.path.realpath(os.path.join(own, pics[0])))

    def made(self, members, manifest=None):
        """A .slate-settings file of these (name, bytes, unix mode or None)."""
        path = os.path.join(self.docs, "Made.slate-settings")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.writestr("manifest.json", json.dumps(manifest or {"format": 1, "has": ["settings", "hypr"]}))
            z.writestr("settings.json", json.dumps({"accent": "#123456"}))
            for name, data, mode in members:
                info = zipfile.ZipInfo(name)
                if mode is not None:
                    info.external_attr = mode << 16
                z.writestr(info, data)
        with open(path, "wb") as f:
            f.write(buf.getvalue())
        return path

    def test_only_slates_own_things_are_read(self):
        """A file with anything else in it (a path out of its folders, a link, something not
        Slate's) changes nothing."""
        before = self.read(os.path.join(self.user, "settings.json"))
        for members in ([("../evil.sh", b"x", None)], [("hypr/../../evil", b"x", None)], [("/etc/passwd", b"x", None)],
                        [("hypr/link", b"/etc/passwd", 0o120777)], [("bin/slate", b"x", None)],
                        [("wallpaper/sub/x.png", b"x", None)], [("wallpaper/x.sh", b"x", None)]):
            with self.subTest(members[0][0]):
                path = self.made(members)
                self.go("check", path, code=1)
                self.go("import", path, code=1)
                self.assertEqual(self.read(os.path.join(self.user, "settings.json")), before)
        self.assertFalse(os.path.exists(os.path.join(self.share, "backups")), "a refused file made a backup")

    def test_another_format_or_not_a_settings_file(self):
        for path in (self.made([], {"format": 2}), self.made([], {"nothing": 1})):
            self.go("import", path, code=1)
        junk = os.path.join(self.docs, "Junk.slate-settings")
        self.put(junk, "not a zip")
        self.go("import", junk, code=1)
        self.go("import", os.path.join(self.docs, "notes.txt"), code=1)

    def test_listing_finds_files_in_the_usual_places(self):
        mine = self.export()
        os.makedirs(self.h("Downloads"), exist_ok=True)
        broken = os.path.join(self.h("Downloads"), "Broken.slate-settings")
        self.put(broken, "no")
        found = json.loads(self.go("list"))
        paths = {f["path"]: f for f in found}
        self.assertIn(mine, paths)
        self.assertTrue(paths[mine]["ok"])
        self.assertIn("wallpaper", paths[mine]["has"])
        self.assertIn(broken, paths)
        self.assertFalse(paths[broken]["ok"])
