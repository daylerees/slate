"""The docs' pictures (site/docs/img/<name>.webp): what each one shows, and how Slate is put
there. The same shape as the visual tier's scenes (tests/visual/scenes.py), plus a crop:

    "name": {
        "settings": {key: value},        # set first (put back afterwards)
        "do": [(target, function, *args), …],    # IPC calls, ("!command", …) run in the session,
                                         # ("&command", …) left running until the picture's taken,
                                         # or lambda st: … to wait for something on the way
        "wait": lambda st: …,            # true once it's on screen (the "test" IPC's state)
        "settle": seconds,               # extra time for images and fades (default 1)
        "undo": [(target, function, *args), …],  # and lambda st: … waits, after the "&"s stop
        "crop": (x, y, w, h),            # the part to keep, in the screen's own 1440×900
    }

Everything shown is made up: the apps are terminals with an app id of their own (APPS), the
windows show fixed text, and the names, files and notifications are invented.
"""
import json as _json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_LIB = os.path.join(os.path.dirname(os.path.dirname(HERE)), "tests", "lib")
FIXTURES = os.path.join(os.path.dirname(TESTS_LIB), "fixtures")

# Pretend apps: (id, name, icon from the icon theme, comment, categories)
APPS = [
    ("docs-files", "Files", "system-file-manager", "Browse your folders", "System;FileManager;"),
    ("docs-browser", "Web Browser", "web-browser", "Browse the web", "Network;WebBrowser;"),
    ("docs-mail", "Mail", "internet-mail", "Read and write email", "Network;Email;"),
    ("docs-music", "Music", "multimedia-audio-player", "Play your music", "AudioVideo;Audio;"),
    ("docs-photos", "Photos", "image-viewer", "Look through your pictures", "Graphics;Viewer;"),
    ("docs-notes", "Notes", "accessories-notes", "Jot things down", "Utility;"),
    ("docs-editor", "Text Editor", "accessories-text-editor", "Edit text files", "Utility;TextEditor;"),
    ("docs-calendar", "Calendar", "office-calendar", "Your days and plans", "Office;Calendar;"),
    ("docs-calculator", "Calculator", "accessories-calculator", "Add things up", "Utility;Calculator;"),
    ("docs-weather", "Weather", "weather", "The forecast where you are", "Utility;"),
]
# The container's own apps that stay in the launcher (the others are hidden)
KEEP_APPS = {"foot.desktop"}
PINNED = ["docs-files", "docs-browser", "docs-mail", "docs-music", "docs-photos", "foot"]


def _picture(src):
    """A download that's a picture: one of Slate's own wallpapers, made smaller."""
    def make(path, slate_dir):
        from PIL import Image
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.open(os.path.join(slate_dir, "wallpapers", src)).convert("RGB").resize((640, 360)).save(path)
    return make


def _file(text):
    def make(path, slate_dir):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    return make


DOWNLOADS = [
    ("Train tickets.pdf", _file("%PDF-1.4\n%%EOF\n")),
    ("Lagoon.png", _picture("slate-lagoon.png")),
    ("Recipes.txt", _file("Lemon and basil pasta\n")),
    ("Ember.png", _picture("slate-ember.png")),
    ("Holiday photos.zip", _file("PK")),
    ("Fern.png", _picture("slate-fern.png")),
]

# Two saved spaces (Spaces panel): what spaces.py would have saved
SPACES = [
    {"id": "docswriting01", "name": "Writing", "colour": "#a3c8f0", "icon": "eb04", "saved": 1767605000,
     "workspaces": [{"monitor": "TEST", "aspect": 1.6, "windows": [
         {"class": "docs-notes", "desktopId": "docs-notes", "title": "Notes", "at": [0, 0], "size": [0.5, 1]},
         {"class": "docs-editor", "desktopId": "docs-editor", "title": "Chapter one", "at": [0.5, 0], "size": [0.5, 1]}]}]},
    {"id": "docsevening1", "name": "Evening", "colour": "#d3a8e8", "icon": "eafc", "saved": 1767605000,
     "workspaces": [{"monitor": "TEST", "aspect": 1.6, "windows": [
         {"class": "docs-music", "desktopId": "docs-music", "title": "Music", "at": [0, 0], "size": [0.4, 1]},
         {"class": "docs-photos", "desktopId": "docs-photos", "title": "Photos", "at": [0.4, 0], "size": [0.6, 1]}]},
         {"monitor": "TEST", "aspect": 1.6, "windows": [
         {"class": "docs-browser", "desktopId": "docs-browser", "title": "Web Browser", "at": [0, 0], "size": [1, 1]}]}]},
]

# ---- Windows, with contents that never change ------------------------------------------
NOTES = ("Notes\n\n  Call the garage about the MOT.\n  Book the train for Friday.\n"
         "  Ask Sam about the weekend.\n\n  Shopping\n  - oat milk\n  - two lemons\n  - basil\n")
CHAPTER = ("Chapter one\n\n  The rain had stopped by the time the\n  last train pulled in, and the platform\n"
           "  smelled of wet stone and coffee.\n")
TERMINAL = ("~ $ ls\n  Documents  Downloads  Music  Pictures  Videos\n~ $ cat todo.txt\n"
            "  water the plants\n  back up the photos\n")
PACKING = "Packing\n\n  [x] passport\n  [x] chargers\n  [ ] walking boots\n"


def _window(app_id, title, text):
    # (\033[?25l hides the cursor; nothing runs after the text, so it stays as it is)
    return ("&foot", "--app-id", app_id, "--title", title, "sh", "-c", "printf '\\033[?25l%s' \"$0\"; exec sleep infinity", text)


def _on(title, ws):
    return lambda st: any(w["title"] == title and w["workspace"] == ws for w in st["windows"])


def _to_workspace(ws):
    return [("!hyprctl", "dispatch", "function() instantTo(hl.dsp.focus({ workspace = %d })) end" % ws),
            lambda st: st["overview"]["focused"] == ws]


WINDOWS = [("docs-notes", "Notes", NOTES, 1), ("docs-editor", "Chapter one", CHAPTER, 1),
           ("foot", "Terminal", TERMINAL, 1), ("docs-notes", "Packing", PACKING, 2)]
_OPEN = []
for _ws in (1, 2):
    _OPEN += _to_workspace(_ws)
    for _id, _title, _text, _w in WINDOWS:
        if _w == _ws:
            _OPEN += [_window(_id, _title, _text), _on(_title, _ws)]
_OPEN += _to_workspace(1) + [lambda st: st["bars"][0]["dots"]["count"] == 3]
_GONE = lambda st: not any(w["title"] in [t for _, t, _, _ in WINDOWS] for w in st["windows"]) \
    and st["bars"][0]["dots"]["count"] == 1
# The same windows on workspaces 2 and 3, workspace 1 left empty: the dock stays in view (it
# steps aside for tiled windows) with them running on it
_AWAY = (_to_workspace(2) + [x for i, t, txt, w in WINDOWS if w == 1 for x in (_window(i, t, txt), _on(t, 2))]
         + _to_workspace(3) + [x for i, t, txt, w in WINDOWS if w == 2 for x in (_window(i, t, txt), _on(t, 3))]
         + _to_workspace(1) + [lambda st: st["bars"][0]["dots"]["count"] == 4])

_PLAYING = ("&" + sys.executable, os.path.join(TESTS_LIB, "fake_mpris.py"), "--still", "--title", "Morning Light",
            "--art", os.path.join(FIXTURES, "live", "album-art.png"))
_NOT_PLAYING = lambda st: not st["dock"]["media"]


# (each names its app, so it shows that app's icon)
_NOTIFY = [
    ("!notify-send", "-a", "Calendar", "-h", "string:desktop-entry:docs-calendar", "Team catch-up in 10 minutes", "Room 2, with Sam and Priya"),
    ("!notify-send", "-a", "Mail", "-h", "string:desktop-entry:docs-mail", "Jo Marsh", "Photos from the weekend are in the shared album"),
    ("!notify-send", "-a", "Files", "-h", "string:desktop-entry:docs-files", "Copy finished", "1,204 files copied to Backup"),
]

SETTINGS_CROP = (262, 144, 916, 656)       # the Settings window, with a little of the desktop round it


def _settings(page, **extra):
    """A Settings page, open and drawn (thumbnails loaded, its first look at the system done)."""
    return dict({"do": [("settings", "page", page)], "crop": SETTINGS_CROP,
                 "wait": lambda st: st["settings"]["open"] and st["settings"]["section"] == page
                 and st["settings"].get("thumbsLoading", 0) == 0 and st["settings"].get("checking", 0) == 0,
                 "settle": 1.5, "undo": [("settings", "close")]}, **extra)


def _panel(name, **extra):
    return dict({"do": [("bar", "panel", name)], "wait": lambda st, n=name: st["popout"] == n, "settle": 1.2,
                 "undo": [("popout", "close")]}, **extra)


_NOVA_ON = {"assistantEnabled": "true", "assistantRisksAccepted": "1", "assistantAgent": "claude"}
_NOVA_AGENTS = [{"id": "claude", "label": "Claude Code", "installed": True, "signedIn": True, "confined": True, "followUps": True}]
_CONTROL = {"do": [_PLAYING, lambda st: st["dock"]["media"], ("test", "weather", "true"), ("bar", "panel", "control")],
            "wait": lambda st: st["popout"] == "control", "settle": 1.5,
            "undo": [("popout", "close"), ("test", "weather", "false"), _NOT_PLAYING]}

SHOTS = {
    # ---- Getting started ----------------------------------------------------------------
    # The whole desktop: the menu bar, the control centre open, something playing on the dock
    "intro": dict(_CONTROL),
    "welcome": {"do": [("welcome", "open")], "wait": lambda st: st["welcome"]["open"], "settle": 1.5,
                "undo": [("welcome", "close")], "crop": (310, 130, 820, 640)},

    # ---- The menu bar ---------------------------------------------------------------------
    "menu-bar-start": {"do": _OPEN, "settle": 1.5, "undo": [_GONE], "crop": (0, 0, 480, 46)},
    "menu-bar-end": {"do": [("test", "barHover", "clock")],
                     "wait": lambda st: st["bar"]["label"]["shown"] and st["bar"]["label"]["opacity"] > 0.99,
                     "undo": [("test", "barHover", "")], "crop": (900, 0, 540, 84)},
    "bar-arranging": {"do": [("bar", "edit", "start")], "wait": lambda st: st["bar"]["arranging"] and st["bar"]["editor"],
                      "settle": 1.5, "undo": [("bar", "edit", "done")], "crop": (0, 0, 1440, 370)},
    "bar-menu": {"do": [("test", "barMenu", "open")], "wait": lambda st: st["barMenu"]["open"],
                 "undo": [("test", "menuKey", "Escape")], "crop": (360, 0, 480, 240)},

    # ---- The control centre and the bar's panels ------------------------------------------
    "control-centre": dict(_CONTROL, crop=(0, 0, 516, 430)),
    "panel-calendar": _panel("calendar", do=[("test", "weather", "true"), ("bar", "panel", "calendar")],
                             undo=[("popout", "close"), ("test", "weather", "false")], crop=(960, 0, 480, 520)),
    "panel-screenshot": _panel("screenshot", crop=(820, 0, 620, 330)),
    "panel-windowmode": _panel("windowmode", crop=(0, 0, 400, 480)),
    "panel-gamemode": _panel("gamemode", crop=(840, 0, 600, 520)),
    "panel-spaces": _panel("spaces", crop=(0, 0, 540, 340)),
    # (the pop-ups gone first, so only the panel shows them)
    "panel-notifications": _panel("notifications", settings={"notificationSeconds": "2"},
                                  do=_NOTIFY + [lambda st: st["notifications"]["history"] == 3 and st["notifications"]["toasts"] == 0,
                                                ("bar", "panel", "notifications")], crop=(780, 0, 660, 380)),
    "notification": {"settings": {"notificationSeconds": "30"}, "do": _NOTIFY[:1],
                     "wait": lambda st: st["notifications"]["toasts"] == 1, "settle": 1.5, "crop": (900, 0, 540, 170)},

    # ---- The dock -------------------------------------------------------------------------
    "dock": {"do": _AWAY + [_PLAYING], "wait": lambda st: st["dock"]["media"], "settle": 1.5,
             "undo": [_NOT_PLAYING, _GONE], "crop": (300, 790, 840, 110)},
    "dock-menu": {"do": _AWAY + [("dock", "menu", "docs-notes")], "wait": lambda st: st["dock"]["menu"] == "docs-notes",
                  "undo": [("dock", "closeMenu"), _GONE], "crop": (400, 560, 640, 340)},
    "dock-downloads": {"do": [("dock", "downloads")], "wait": lambda st: st["dock"]["menu"] == "other", "settle": 1.5,
                       "undo": [("dock", "closeMenu")], "crop": (440, 560, 680, 340)},

    # ---- The launcher and the emoji picker ------------------------------------------------
    "launcher": {"do": [("launcher", "open")], "wait": lambda st: st["launcher"]["open"], "undo": [("launcher", "close")],
                 "crop": (420, 170, 600, 570)},
    "launcher-search": {"do": [("launcher", "open"), ("launcher", "search", "night")],
                        "wait": lambda st: st["launcher"]["query"] == "night", "undo": [("launcher", "close")],
                        "crop": (420, 170, 600, 440)},
    "launcher-grid": {"settings": {"launcherLayout": "grid"}, "do": [("launcher", "open")],
                      "wait": lambda st: st["launcher"]["open"], "undo": [("launcher", "close")], "crop": (420, 190, 600, 350)},
    "emoji": {"do": [("picker", "emoji")], "wait": lambda st: st["picker"]["open"], "settle": 1.5,
              "undo": [("picker", "close")], "crop": (420, 170, 600, 560)},

    # ---- Nova -----------------------------------------------------------------------------
    "nova": {"settings": _NOVA_ON,
             "do": [("test", "nova", _json.dumps({"agents": _NOVA_AGENTS,
                     "asked": "make the dock icons bigger and turn on night light",
                     "answer": "Done: the dock's icons are larger now, and night light is on.",
                     "actions": [{"id": 1, "text": "Set Icon size to 56", "state": "done"},
                                 {"id": 2, "text": "Turn Night light on", "state": "done"}]})), ("assistant", "open")],
             "wait": lambda st: st["assistant"]["open"] and len(st["assistant"]["actions"]) == 2,
             "undo": [("assistant", "close"), ("test", "nova", "{}")], "crop": (420, 170, 600, 380)},
    "nova-asks": {"do": [("assistant", "confirm", "docs", '{"title": "Close Notes?", "body": "Your assistant (Claude Code) is asking to '
                          'close this window. Anything unsaved in it could be lost.", "button": "Close", "danger": true}')],
                  "wait": lambda st: st["asking"] == "Close Notes?", "settle": 1.5,
                  "undo": [("assistant", "withdraw", "docs")], "crop": (510, 310, 420, 290)},

    # ---- Windows and workspaces -----------------------------------------------------------
    "switcher": {"do": _OPEN + [("switcher", "next")],
                 "wait": lambda st: st["switcher"]["open"] and st["switcher"]["previews"] == st["switcher"]["windows"],
                 "settle": 1.5, "undo": [("switcher", "cancel"), _GONE], "crop": (20, 320, 1400, 300)},
    "overview": {"do": _OPEN + [("overview", "open")],
                 "wait": lambda st: st["overview"]["open"] and st["overview"]["previews"] == 4,
                 "settle": 1.5, "undo": [("overview", "close"), _GONE]},

    # ---- Look and feel --------------------------------------------------------------------
    "settings-appearance": _settings("appearance", do=[("settings", "find", "appearance", "Theme")],
                                     wait=lambda st: st["settings"]["open"] and st["settings"]["found"] == "Theme", settle=2.5),
    "settings-icons": _settings("icons"),
    "settings-apptheming": _settings("apptheming"),
    "wallpaper-switcher": {"do": [("wallpaper", "switcher")],
                           "wait": lambda st: st["wallpaperSwitcher"]["open"] and not st["wallpaperSwitcher"]["listing"]
                           and st["wallpaperSwitcher"]["fade"] == 1,
                           "settle": 2, "undo": [("wallpaperSwitcher", "cancel"), lambda st: not st["wallpaperSwitcher"]["switching"]]},

    # ---- Your computer --------------------------------------------------------------------
    "settings-sound": _settings("sound", do=[("settings", "find", "sound", "Sound effects")],
                                wait=lambda st: st["settings"]["open"] and st["settings"]["section"] == "sound", settle=2.5),
    "lock-screen": {"do": [("lock", "preview", "lock")], "wait": lambda st: st["lock"]["previewing"], "settle": 2,
                    "undo": [("lock", "closePreview")], "crop": (360, 180, 720, 400)},
    # (below the "Preview" note at the top, which the real one hasn't got)
    "login-screen": {"do": [("lock", "preview", "login")], "wait": lambda st: st["lock"]["previewing"], "settle": 2,
                     "undo": [("lock", "closePreview")], "crop": (0, 70, 1440, 830)},
    "screensaver": {"settings": {"screensaverStyle": "clock"}, "do": [("screensaver", "start")],
                    "wait": lambda st: st["screensaver"]["open"], "settle": 2, "undo": [("screensaver", "stop")],
                    "crop": (240, 150, 960, 600)},

    # ---- Reference ------------------------------------------------------------------------
    "settings-all": _settings("overview"),
    "settings-search": _settings("overview", do=[("settings", "page", "overview"), ("settings", "search", "dock")], settle=2),
    "settings-changed": _settings("dock", settings={"dockPreviewDelay": "1.2"}, crop=(500, 525, 660, 150)),
    "settings-shortcuts": _settings("shortcuts"),
    "settings-hotcorners": _settings("hotcorners"),
}
