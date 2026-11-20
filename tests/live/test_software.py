"""Slate Software (SoftwareWindow.qml): it opens on Discover with Flathub's lists, finds apps
by name and words, shows an app's own page, counts updates, asks before removing, and runs
installs one at a time. Its engine (scripts/software.py, unit-tested on its own) is stood in
for with pretend answers (test softwarePretend), so nothing here runs Flatpak or reaches
Flathub."""
import json
import os

from live import LiveCase

APPS = [
    {"id": "org.gimp.GIMP", "name": "GNU Image Manipulation Program", "summary": "Create images and edit photographs",
     "icon": "", "categories": ["Graphics"], "keywords": "photo paint", "developer": "The GIMP team"},
    {"id": "org.mozilla.firefox", "name": "Firefox", "summary": "Fast, private and safe web browser",
     "icon": "/tmp/slate-test-app-icon.png", "categories": ["Network"], "keywords": "web browser internet", "developer": "Mozilla"},
    {"id": "org.videolan.VLC", "name": "VLC", "summary": "Play every kind of video",
     "icon": "", "categories": ["AudioVideo"], "keywords": "player movie", "developer": "VideoLAN"},
    {"id": "com.valvesoftware.Steam", "name": "Steam", "summary": "Play your games",
     "icon": "", "categories": ["Game"], "keywords": "games", "developer": "Valve"},
]
PRETEND = {
    "status": {"flatpak": True, "flathub": True, "catalogue": True},
    "catalogue": APPS,
    "lists": {"popular": ["org.mozilla.firefox", "org.videolan.VLC", "not.in.the.Catalogue"],
              "trending": ["com.valvesoftware.Steam"], "recently-added": [],
              "categories": {"Network": ["org.mozilla.firefox"], "Game": ["com.valvesoftware.Steam"],
                             "AudioVideo": ["org.videolan.VLC", "not.in.the.Catalogue"]}},
    "installed": [{"id": "org.videolan.VLC", "name": "VLC", "version": "3.0", "installation": "system"}],
    "updates": {"apps": [{"id": "org.videolan.VLC", "name": "VLC", "version": "3.1", "installation": "system"}],
                "system": [{"name": "linux", "from": "6.1", "to": "6.2"}, {"name": "mesa", "from": "1", "to": "2"}],
                "systemTool": "checkupdates", "systemProblem": ""},
    "app": dict(APPS[1], description=["A browser."], screenshots=[], homepage="", license="MPL-2.0", latest="140",
                installed=False, version="", installation=""),
    "act": "ok",
}


# The catalog's picture of Firefox (a plain orange disc): drawn as the dock draws apps
ICON_MAKER = ("python3 -c \"from PIL import Image, ImageDraw; im = Image.new('RGBA', (128, 128), (0, 0, 0, 0)); "
              "ImageDraw.Draw(im).ellipse((8, 8, 120, 120), fill=(240, 120, 40, 255)); im.save('/tmp/slate-test-app-icon.png')\"")


class Software(LiveCase):
    def setUp(self):
        super().setUp()
        os.system(ICON_MAKER)
        self.addCleanup(lambda: self.ipc("software", "close"))
        self.ipc("test", "softwarePretend", json.dumps(PRETEND))
        self.ipc("software", "open")
        self.wait(lambda st: st["software"]["open"] and st["software"]["apps"] == len(APPS), "Slate Software open with the catalog")

    def sw(self):
        return self.s.state()["software"]

    def test_opens_on_discover_with_counts(self):
        st = self.wait(lambda st: st["software"]["updates"] == 3, "1 app and 2 system updates counted")["software"]
        self.assertEqual(st["page"], "discover")
        self.assertEqual(st["installed"], ["org.videolan.VLC"])

    def test_search_has_the_keyboard_on_opening(self):
        self.wait(lambda st: st["software"]["searchFocused"], "the search box with the keyboard")

    def test_search_by_name_and_words(self):
        self.ipc("software", "search", "fire")
        self.wait(lambda st: st["software"]["found"] == ["org.mozilla.firefox"], "Firefox found by its name")
        self.ipc("software", "search", "photo")
        self.wait(lambda st: st["software"]["found"] == ["org.gimp.GIMP"], "GIMP found by a keyword")
        self.ipc("software", "search", "play")
        # (names starting with the words first, then by name)
        self.wait(lambda st: set(st["software"]["found"]) == {"org.videolan.VLC", "com.valvesoftware.Steam"}, "both players")
        self.ipc("software", "search", "zzzz")
        self.wait(lambda st: st["software"]["found"] == [], "nothing for nonsense")

    def test_app_page_and_back_to_pages(self):
        self.ipc("software", "app", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["app"] == "org.mozilla.firefox" and st["software"]["detail"] == "Firefox", "Firefox's page")
        self.ipc("software", "page", "updates")
        self.wait(lambda st: st["software"]["page"] == "updates" and st["software"]["app"] == "", "Updates, off the app's page")

    def test_remove_asks_first(self):
        self.ipc("software", "app", "org.videolan.VLC")
        self.ipc("test", "softwareRemove", "org.videolan.VLC")
        self.s.wait(lambda st: st["asking"] == "Remove VLC?", what="the remove question")
        self.ipc("test", "answer", "false")
        self.s.wait(lambda st: st["asking"] == "", what="the question to close")
        self.s.settle(0.8)
        self.assertEqual(self.sw()["busy"], "", "nothing removed after Cancel")

    def test_installs_run_one_at_a_time(self):
        self.ipc("test", "softwareAct", "install", "org.mozilla.firefox")
        self.ipc("test", "softwareAct", "install", "org.gimp.GIMP")
        self.ipc("test", "softwareAct", "install", "org.gimp.GIMP")     # (twice: once is enough)
        st = self.wait(lambda st: st["software"]["busy"] == "install org.mozilla.firefox", "Firefox installing")["software"]
        self.assertEqual(st["queued"], 1, "GIMP waits its turn, once")
        self.wait(lambda st: st["software"]["busy"] == "install org.gimp.GIMP", "then GIMP")
        self.wait(lambda st: st["software"]["busy"] == "" and st["software"]["queued"] == 0, "both done")

    def test_what_went_wrong_is_said(self):
        self.ipc("test", "softwarePretend", json.dumps(dict(PRETEND, act="Slate couldn't install it: no connection")))
        self.ipc("test", "softwareAct", "install", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["note"] == "Slate couldn't install it: no connection", "what went wrong, said")

    def test_one_app_updates_on_its_own(self):
        self.ipc("software", "page", "updates")
        self.ipc("test", "softwareAct", "update-apps", "org.videolan.VLC")
        self.wait(lambda st: st["software"]["busy"] == "update-apps org.videolan.VLC", "VLC updating, on its own")
        self.wait(lambda st: st["software"]["busy"] == "", "done")

    def test_icons_drawn_as_the_docks(self):
        """An app that isn't installed has its catalog picture drawn as a tile in the icon
        style in use (Settings → Icons), into that style's own folder."""
        st = self.wait(lambda st: st["software"]["tilesDrawn"] > 0, "Firefox's picture drawn", timeout=20)["software"]
        tile = os.path.join(st["flathubTiles"], "org.mozilla.firefox.png")
        self.assertTrue(os.path.isfile(tile), tile)
        from PIL import Image
        self.assertEqual(Image.open(tile).size, (192, 192))
        # Its tile behind it in a shade of its own colour (Settings → Icons, on by default), as the
        # dock's are: the colours noted as it was drawn
        with open(os.path.join(st["flathubTiles"], "colours.json")) as f:
            self.assertIn("org.mozilla.firefox", json.load(f))
        self.wait(lambda st: "org.mozilla.firefox" in st["software"]["shaded"], "Firefox's tile in its own colour")

    def test_opens_again_after_closing_from_outside(self):
        """Closed from outside Slate (Super+Q, or a title bar's close button), it opens again
        the next time it's asked for, rather than staying gone until Slate restarts."""
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = slateWindowAddress("Software") })) end')
        self.wait(lambda st: not st["software"]["open"], "closed from outside")
        self.ipc("test", "softwarePretend", json.dumps(PRETEND))
        self.ipc("software", "open")
        self.wait(lambda st: st["software"]["open"], "open again")
        self.s.settle(1.0)
        clients = [c for c in self.s.hyprctl("clients", json_out=True) if c.get("title") == "Software"]
        self.assertTrue(clients and clients[0].get("mapped", True), "on screen again")

    def test_a_job_carries_on_when_the_window_goes(self):
        """Closed with Super+Q in the middle of an install (the window is built afresh after
        that), the install carries on, and the window opened again shows it."""
        self.ipc("test", "softwarePretend", json.dumps(dict(PRETEND, actMs=4000)))
        self.ipc("test", "softwareAct", "install", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["busy"] == "install org.mozilla.firefox", "Firefox installing")
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = slateWindowAddress("Software") })) end')
        self.wait(lambda st: not st["software"]["open"], "closed from outside")
        self.ipc("software", "open")
        st = self.wait(lambda st: st["software"]["open"], "open again")["software"]
        self.assertEqual(st["busy"], "install org.mozilla.firefox", "the install ended with the window")
        self.wait(lambda st: st["software"]["busy"] == "", "then finished", timeout=10)

    def test_colours_that_arrive_later_are_used(self):
        """A tile and its colour that arrive while Slate runs, without Slate Software drawing
        anything (as after an update, the first time): its tile is in its own colour once the
        window opens again."""
        # (once its own drawing is done, which reads the colours again as it finishes)
        st = self.wait(lambda st: st["software"]["tilesDrawn"] > 0, "Firefox's picture drawn", timeout=20)["software"]
        self.s.settle(0.5)
        self.ipc("software", "close")
        folder = st["flathubTiles"]
        os.makedirs(folder, exist_ok=True)
        from PIL import Image
        Image.new("RGBA", (192, 192), (40, 160, 90, 255)).save(os.path.join(folder, "org.gimp.GIMP.png"))
        path = os.path.join(folder, "colours.json")
        try:
            with open(path) as f:
                noted = json.load(f)
        except (OSError, ValueError):
            noted = {}
        noted["org.gimp.GIMP"] = {"c": "#28a05a", "t": 0}
        with open(path, "w") as f:
            json.dump(noted, f)
        self.ipc("software", "open")
        self.wait(lambda st: "org.gimp.GIMP" in st["software"]["shaded"], "GIMP's tile in its own colour")

    def test_grey_and_white_icons_get_a_tile_too(self):
        """A grey or white icon (LibreOffice, DBeaver) gets a neutral tile of its own rather than
        the theme's, which barely showed on a card."""
        st = self.wait(lambda st: st["software"]["tilesDrawn"] > 0, "Firefox's picture drawn", timeout=20)["software"]
        self.s.settle(0.5)
        self.ipc("software", "close")
        folder = st["flathubTiles"]
        from PIL import Image
        Image.new("RGBA", (192, 192), (231, 231, 231, 255)).save(os.path.join(folder, "org.videolan.VLC.png"))
        path = os.path.join(folder, "colours.json")
        with open(path) as f:
            noted = json.load(f)
        noted["org.videolan.VLC"] = {"c": "#e7e7e7", "t": 0}
        with open(path, "w") as f:
            json.dump(noted, f)
        self.ipc("software", "open")
        st = self.wait(lambda st: "org.videolan.VLC" in st["software"]["shaded"], "VLC's white icon on a tile of its own")
        # A plain grey: not leaning to the accent (as the theme's tile does)
        hex_ = st["software"]["shades"]["org.videolan.VLC"].lstrip("#")[-6:]
        r, g, b = (int(hex_[i:i + 2], 16) for i in (0, 2, 4))
        self.assertLessEqual(max(r, g, b) - min(r, g, b), 10, f"#{hex_} isn't a neutral grey")

    def test_a_job_running_is_picked_up(self):
        """A job runs as a process of its own and keeps how it's going in a file: one already
        running (when Slate starts or reloads) is picked up with its progress, and finishes
        when its file says so."""
        import subprocess
        self.ipc("test", "softwarePretend", json.dumps({k: v for k, v in PRETEND.items() if k != "act"}))
        st = self.s.state()["software"]
        stand_in = subprocess.Popen(["sleep", "60"])
        self.addCleanup(stand_in.kill)
        path = st["jobFile"]
        os.makedirs(os.path.dirname(path), exist_ok=True)

        def say(**more):
            state = dict({"token": "from-before", "what": "install", "id": "org.gimp.GIMP", "pid": stand_in.pid,
                          "progress": 30, "done": False, "result": ""}, **more)
            with open(path + ".tmp", "w") as f:
                json.dump(state, f)
            os.replace(path + ".tmp", path)
        say()
        self.wait(lambda st: st["software"]["busy"] == "install org.gimp.GIMP" and st["software"]["progress"] == 30,
                  "the running job picked up, at 30%", timeout=10)
        say(progress=80)
        self.wait(lambda st: st["software"]["progress"] == 80, "its progress followed", timeout=10)
        say(progress=100, done=True, result="ok")
        self.wait(lambda st: st["software"]["busy"] == "", "finished", timeout=10)

    def test_screenshots_large_in_quick_look(self):
        """A screenshot clicked on an app's page shows large in Quick Look (the dimmed screen,
        Left and Right through the rest), with its caption, and no Open: it isn't a file."""
        shots = [{"thumb": "https://example.invalid/a-small.png", "full": "https://example.invalid/a.png", "caption": "The main window"},
                 {"thumb": "https://example.invalid/b-small.png", "full": "https://example.invalid/b.png", "caption": ""}]
        self.ipc("test", "softwarePretend", json.dumps(dict(PRETEND, app=dict(PRETEND["app"], screenshots=shots))))
        self.ipc("software", "app", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["detail"] == "Firefox", "Firefox's page")
        self.addCleanup(lambda: self.ipc("quicklook", "close"))
        self.ipc("test", "softwareShot", "1")
        st = self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["index"] == 1, "the second screenshot, large")["quicklook"]
        self.assertEqual((st["path"], st["count"], st["web"], st["openShown"]), ("https://example.invalid/b.png", 2, True, False))
        self.assertEqual(st["name"], "Firefox, screenshot 2")
        self.assertTrue(st["closeShown"], "no close button")
        # (offline here: says so, rather than an empty card)
        self.wait(lambda st: "couldn't load this screenshot" in st["quicklook"]["note"], "why it can't show it", timeout=15)
        self.ipc("quicklook", "close")
        self.ipc("test", "softwareShot", "0")
        self.wait(lambda st: st["quicklook"]["open"] and st["quicklook"]["name"] == "The main window", "the first, with its caption")

    def test_the_assistants_way_in(self):
        """slate ipc call software act (what the assistant's software tool calls, after Slate
        has asked): the job starts in Software, as its buttons start it; anything else is ignored."""
        self.ipc("software", "act", "install", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["busy"] == "install org.mozilla.firefox", "the install started")
        self.wait(lambda st: st["software"]["busy"] == "", "and finished")
        for what, app in (("rm", "everything"), ("install", "bad id;x"), ("remove", "")):
            self.ipc("software", "act", what, app)
        self.s.settle(0.8)
        st = self.s.state()["software"]
        self.assertEqual((st["busy"], st["queued"]), ("", 0), "something not on the list was started")



class DailyLook(LiveCase):
    """The once-a-day look for app and system updates (SoftwareUpdates.qml): a calm notification
    when anything's waiting, at most once a day, and none with the setting off. (Under the
    tests it never looks by itself: it's handed what the engine would say.)"""
    def setUp(self):
        super().setUp()
        self.keep_setting("softwareUpdateCheck")
        self.ipc("test", "softwareDailyReset")

    def daily(self):
        return self.s.state()["softwareDaily"]

    def test_tells_once_a_day(self):
        before = self.daily()
        self.ipc("test", "softwareDaily", json.dumps({"apps": 2, "system": 3}))
        st = self.wait(lambda st: st["softwareDaily"]["notices"] == before["notices"] + 1, "a notification")["softwareDaily"]
        self.assertEqual(st["waiting"], 5)
        # Again the same day: counted, not told again
        self.ipc("test", "softwareDaily", json.dumps({"apps": 2, "system": 4}))
        st = self.wait(lambda st: st["softwareDaily"]["waiting"] == 6, "the new count")["softwareDaily"]
        self.assertEqual(st["notices"], before["notices"] + 1, "told twice in a day")

    def test_nothing_with_it_off_or_metered(self):
        before = self.daily()
        self.config("softwareUpdateCheck", "false")
        self.ipc("test", "softwareDaily", json.dumps({"apps": 1, "system": 0}))
        self.wait(lambda st: st["softwareDaily"]["looks"] == before["looks"] + 1, "the look")
        self.ipc("test", "softwareDailyReset")
        self.config("softwareUpdateCheck", "true")
        self.ipc("test", "softwareDaily", json.dumps({"metered": True}))
        self.s.settle(0.8)
        st = self.daily()
        self.assertEqual(st["notices"], before["notices"], "told with it off, or on a metered connection")
        self.assertEqual(st["looks"], before["looks"] + 1, "a metered connection counted as a look")


class FirstCatalogue(LiveCase):
    """A new computer: Flathub set up, but Flatpak hasn't got its catalogue yet (it only does on
    its first update or install), so Software was empty with nothing said. Bug, 2026-11-20.
    Software gets it as it opens, says so, and says what went wrong with a Try again if that
    fails."""
    def open_with(self, **changes):
        self.ipc("software", "close")
        self.ipc("test", "softwarePretend", json.dumps(dict(PRETEND, **changes)))
        self.ipc("software", "open")

    def test_got_as_software_opens(self):
        self.addCleanup(lambda: self.ipc("software", "close"))
        none = {"flatpak": True, "flathub": True, "catalogue": False}
        offline = "error Slate couldn't reach Flathub. Check you're online, then try again"
        self.open_with(status=none, catalogue=[], fetch=offline)
        st = self.wait(lambda st: st["software"]["open"] and st["software"]["fetching"] == offline[len("error "):],
                       "what went wrong, said")["software"]
        self.assertEqual(st["apps"], 0)
        # Opened again, online: it's got, and the apps are read
        self.open_with(status=none, catalogue=APPS, fetch="ok")
        self.wait(lambda st: st["software"]["open"] and st["software"]["fetching"] == "" and st["software"]["apps"] == len(APPS),
                  "the apps, once the catalogue's been got")


class NewAppFolders(LiveCase):
    """AppFolders.qml: an app folder missing when Slate started has appeared (the first Flatpak
    install, on a computer set up before the installer made it), and Slate can't see apps there
    until it restarts: it asks, in Slate's confirmation window, and Later leaves it be."""
    def test_asks_to_restart(self):
        self.addCleanup(lambda: self.ipc("test", "answer", "false"))
        self.ipc("test", "appFolderAppeared")
        st = self.wait(lambda st: st["asking"] == "Restart Slate to show your new apps?", "the question")
        self.assertIn("Your apps and windows stay open", st["askingBody"])
        self.ipc("test", "answer", "false")
        self.wait(lambda st: st["asking"] == "", "Later to close it")
