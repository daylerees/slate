"""The scenes the visual tier screenshots. Each is a few IPC calls that put Slate in a state,
a check (on the "test" IPC's state) that it's there, and what to undo afterwards.

    "name": {
        "settings": {key: value},        # set first (put back afterwards)
        "do": [(target, function, *args), …],    # or ("!command", *args), run in the session
        "wait": lambda st: …,            # true once the scene is on screen
        "settle": seconds,               # extra time for images and loaders (default 0.8)
        "undo": [(target, function, *args), …],
        "mask": [(x, y, w, h), …],       # parts that change by themselves, left out of the comparison
    }

Approved screenshots are tests/visual/baselines/<name>.png, made in the container only
(tests/run --update-baselines [name…]).
"""
import re

import slate

PANELS = ["control", "spaces", "notifications", "session", "volume", "wifi", "clipboard", "screenshot",
          "keyboard", "bluetooth", "battery", "gamemode", "calendar"]
SHOW_ALL = {k: "true" for k in ("barShowSpaces", "barShowNotifications", "barShowPower", "barShowVolume", "barShowWifi",
                                "barShowClipboard", "barShowScreenshot", "barShowKeyboard", "barShowBluetooth",
                                "barShowBattery", "barShowGameMode")}


def settings_pages():
    src = slate.read("shell", "SettingsIndex.qml")
    block = src.split("readonly property var pages:")[1].split("\n    ]")[0]
    return re.findall(r"\{\s*id:\s*\"(\w+)\"", block)


SCENES = {
    "desktop": {"wait": lambda st: st["popout"] == ""},
    "desktop-light": {"settings": {"themeMode": "light", "lightMode": "true"}, "wait": lambda st: True, "settle": 1.5},
    "desktop-glass": {"settings": {"glass": "true"}, "wait": lambda st: True, "settle": 1.5},
    "bar-every-button": {"settings": SHOW_ALL, "wait": lambda st: True, "settle": 1.2},

    "launcher": {"do": [("launcher", "open")], "wait": lambda st: st["launcher"]["open"],
                 "undo": [("launcher", "close")]},
    "launcher-grid": {"settings": {"launcherLayout": "grid"}, "do": [("launcher", "open")],
                      "wait": lambda st: st["launcher"]["open"], "undo": [("launcher", "close")]},
    "launcher-search": {"do": [("launcher", "open"), ("launcher", "search", "foot")],
                        "wait": lambda st: st["launcher"]["query"] == "foot", "undo": [("launcher", "close")]},
    "picker-clipboard": {"do": [("picker", "clipboard")], "wait": lambda st: st["picker"]["open"],
                         "undo": [("picker", "close")]},
    "picker-emoji": {"do": [("picker", "emoji")], "wait": lambda st: st["picker"]["open"], "settle": 1.5,
                     "undo": [("picker", "close")]},
    "overview": {"do": [("overview", "open")], "wait": lambda st: st["overview"]["open"],
                 "undo": [("overview", "close")]},
    "lock-preview": {"do": [("lock", "preview", "lock")], "wait": lambda st: st["lock"]["previewing"], "settle": 1.5,
                     "undo": [("lock", "closePreview")]},
    "login-preview": {"do": [("lock", "preview", "login")], "wait": lambda st: st["lock"]["previewing"], "settle": 1.5,
                      "undo": [("lock", "closePreview")]},
    "power-confirm": {"do": [("power", "confirm", "logout")], "wait": lambda st: st["power"]["open"],
                      "undo": [("power", "cancel")]},
    "polkit": {"do": [("polkit", "preview")], "wait": lambda st: st["polkit"]["open"], "undo": [("polkit", "close")]},
    "screensaver": {"settings": {"screensaverStyle": "clock"}, "do": [("screensaver", "start")],
                    "wait": lambda st: st["screensaver"]["open"], "settle": 1.5, "undo": [("screensaver", "stop")]},
    "welcome": {"do": [("welcome", "open")], "wait": lambda st: st["welcome"]["open"], "settle": 1.2,
                "undo": [("welcome", "close")]},
    "dock-menu": {"do": [("dock", "menu", "foot")], "wait": lambda st: st["dock"]["menu"] == "foot",
                  "undo": [("dock", "closeMenu")]},
    "dock-downloads": {"do": [("dock", "downloads")], "wait": lambda st: st["dock"]["menu"] == "other",
                       "undo": [("dock", "closeMenu")]},
}

for _p in PANELS:
    SCENES[f"panel-{_p}"] = {
        "settings": SHOW_ALL,
        "do": [("bar", "panel", _p)], "wait": (lambda p: lambda st: st["popout"] == p)(_p), "settle": 1.0,
        "undo": [("popout", "close")],
    }
# The control centre's "Up 1 h 29 min · Hyprland 0.57.1": the host's uptime
SCENES["panel-control"]["mask"] = [(90, 105, 220, 20)]
# The battery panel's System rows (CPU, memory, disk): the host machine's, live
SCENES["panel-battery"]["mask"] = [(825, 272, 265, 115)]
for _p in settings_pages():
    SCENES[f"settings-{_p}"] = {
        "do": [("settings", "page", _p)],
        "wait": (lambda p: lambda st: st["settings"]["open"] and st["settings"]["section"] == p)(_p),
        "settle": 1.2, "undo": [("settings", "close")],
    }

# Last: its toast stays up a few seconds. On glass, so the glossy band shows (Gloss.qml)
SCENES["notification-glass"] = {
    "settings": {"glass": "true", "notificationSeconds": "30"},
    "do": [("!notify-send", "-a", "Tests", "Backup finished", "1,204 files copied to the external drive")],
    "wait": lambda st: st["notifications"]["history"] > 0, "settle": 5,     # (glass: its blur is made the first time)
    # Just the toast: the bar and dock on glass shade a little differently with what ran
    # before (desktop-glass covers them)
    "mask": [(0, 0, 1440, 40), (0, 760, 1440, 140)],
}
