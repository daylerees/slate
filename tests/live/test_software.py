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
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = "title:^(Slate Software)$" })) end')
        self.wait(lambda st: not st["software"]["open"], "closed from outside")
        self.ipc("test", "softwarePretend", json.dumps(PRETEND))
        self.ipc("software", "open")
        self.wait(lambda st: st["software"]["open"], "open again")
        self.s.settle(1.0)
        clients = [c for c in self.s.hyprctl("clients", json_out=True) if c.get("title") == "Slate Software"]
        self.assertTrue(clients and clients[0].get("mapped", True), "on screen again")

    def test_a_job_carries_on_when_the_window_goes(self):
        """Closed with Super+Q in the middle of an install (the window is built afresh after
        that), the install carries on, and the window opened again shows it."""
        self.ipc("test", "softwarePretend", json.dumps(dict(PRETEND, actMs=4000)))
        self.ipc("test", "softwareAct", "install", "org.mozilla.firefox")
        self.wait(lambda st: st["software"]["busy"] == "install org.mozilla.firefox", "Firefox installing")
        self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.window.close({ window = "title:^(Slate Software)$" })) end')
        self.wait(lambda st: not st["software"]["open"], "closed from outside")
        self.ipc("software", "open")
        st = self.wait(lambda st: st["software"]["open"], "open again")["software"]
        self.assertEqual(st["busy"], "install org.mozilla.firefox", "the install ended with the window")
        self.wait(lambda st: st["software"]["busy"] == "", "then finished", timeout=10)
