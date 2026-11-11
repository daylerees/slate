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
          "keyboard", "bluetooth", "battery", "gamemode", "calendar", "windowmode"]
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
    # The cover Slate fades in from at login, with the logo (always dark, even in light mode)
    "fade-in": {"do": [("test", "fadeIn")], "wait": lambda st: st["fadeIn"]["open"], "settle": 2.0,
                "undo": [("test", "fadeInClose")]},
    "fade-in-light": {"settings": {"themeMode": "light", "lightMode": "true"}, "do": [("test", "fadeIn")],
                      "wait": lambda st: st["fadeIn"]["open"], "settle": 2.0, "undo": [("test", "fadeInClose")]},
    # The overview's other layouts (Settings → Workspaces → Moving between workspaces)
    **{f"overview-{m}": {"settings": {"overviewMoveAnimation": m}, "do": [("overview", "open")],
                         "wait": lambda st: st["overview"]["open"], "settle": 1.2, "undo": [("overview", "close")]}
       for m in ("wheel", "tilt", "orbit", "deck", "fan", "grid")},
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
SCENES["panel-battery"]["mask"] = [(825, 272, 300, 115)]
for _p in settings_pages():
    SCENES[f"settings-{_p}"] = {
        "do": [("settings", "page", _p)],
        "wait": (lambda p: lambda st: st["settings"]["open"] and st["settings"]["section"] == p)(_p),
        "settle": 1.2, "undo": [("settings", "close")],
    }

# An app held up off the dock while it's dragged: the gap it'd go into, with its placeholder
# (dashed on a plain dock, frosted on glass). Put back where it was after.
_DRAG = {
    "do": [("test", "dockDrag", "foot", 1, 40)],
    "wait": lambda st: st["dock"]["dragging"] == "foot", "settle": 1.5,
    "undo": [("test", "dockDrag", "foot", 1, 0), ("test", "dockDrop")],
}
SCENES["dock-drag"] = dict(_DRAG)
SCENES["dock-drag-glass"] = dict(_DRAG, settings={"glass": "true"}, settle=5)

# A changed setting: the dot after its label, saying it isn't the default
SCENES["settings-changed-dot"] = {
    "settings": {"dockPreviewDelay": "1.2"},
    "do": [("settings", "page", "dock")],
    "wait": lambda st: st["settings"]["open"] and st["settings"]["section"] == "dock",
    "settle": 1.2, "undo": [("settings", "close")],
}

# An assistant asking to close a window (docs/ASSISTANT.md): Slate's own words, in its
# confirmation window, Cancel first
SCENES["assistant-question"] = {
    "do": [("assistant", "confirm", "scene", '{"title": "Close Firefox?", "body": "Your assistant (Claude Code) is asking to '
            'close this window. Anything unsaved in it could be lost.", "button": "Close", "danger": true}')],
    "wait": lambda st: st["asking"] == "Close Firefox?",
    "settle": 1.2, "undo": [("assistant", "withdraw", "scene")],
}

# Chalk's prompt window (Super+K): empty, a conversation (your lines on the right, Chalk's on
# the left with what it did, one thing declined), when it went wrong, a long one scrolled,
# and before the assistant is switched on
_CHALK_ON = {"assistantEnabled": "true", "assistantRisksAccepted": "1"}
_CHALK_AGENTS = [{"id": "claude", "label": "Claude Code", "installed": True, "signedIn": True, "confined": True, "followUps": True}]
import json as _json
SCENES["assistant-empty"] = {
    "settings": _CHALK_ON,
    "do": [("test", "chalk", _json.dumps({"agents": _CHALK_AGENTS})), ("assistant", "open")],
    "wait": lambda st: st["assistant"]["open"] and st["assistant"]["agent"] == "claude",
    "undo": [("assistant", "close"), ("test", "chalk", "{}")],
}
SCENES["assistant-answer"] = {
    "settings": _CHALK_ON,
    "do": [("test", "chalk", _json.dumps({"agents": _CHALK_AGENTS,
            "history": [{"asked": "is glass on?", "answer": "No, glass is off at the moment."}],
            "asked": "turn on glass, put Firefox on workspace 2 and close the terminal",
            "answer": "I've turned glass on and moved Firefox to workspace 2. The terminal is still open, as you said no to closing it.",
            "actions": [{"id": 1, "text": "Turn Glass on", "state": "done"}, {"id": 2, "text": "Move Firefox to workspace 2", "state": "done"},
                        {"id": 3, "text": "Close Terminal", "state": "declined"}]})), ("assistant", "open")],
    "wait": lambda st: st["assistant"]["open"] and len(st["assistant"]["actions"]) == 3,
    "undo": [("assistant", "close"), ("test", "chalk", "{}")],
}
SCENES["assistant-error"] = {
    "settings": _CHALK_ON,
    "do": [("test", "chalk", _json.dumps({"agents": _CHALK_AGENTS, "asked": "turn on glass",
            "error": {"kind": "offline", "message": "Slate couldn't reach Claude just now. Your question is still here: try again in a moment.", "detail": ""}})),
           ("assistant", "open")],
    "wait": lambda st: st["assistant"]["open"] and st["assistant"]["error"] == "offline",
    "undo": [("assistant", "close"), ("test", "chalk", "{}")],
}
SCENES["assistant-long"] = {
    "settings": _CHALK_ON,
    "do": [("test", "chalk", _json.dumps({"agents": _CHALK_AGENTS,
            "history": [{"asked": "question %d" % i, "answer": "This is answer %d, long enough to wrap onto a second line in Chalk's side of the conversation." % i}
                        for i in range(1, 9)],
            "asked": "and the last one", "answer": "Here it is."})), ("assistant", "open")],
    "wait": lambda st: st["assistant"]["open"] and st["assistant"]["turns"] == 9,
    "undo": [("assistant", "close"), ("test", "chalk", "{}")],
}
SCENES["assistant-off"] = {
    "do": [("assistant", "open")],
    "wait": lambda st: st["assistant"]["open"] and not st["assistant"]["enabled"],
    "undo": [("assistant", "close")],
}
# The bar with Chalk's button, after Spaces
SCENES["bar-chalk"] = {"settings": _CHALK_ON, "wait": lambda st: st["assistant"]["button"], "settle": 1.0}

# Switching the assistant on (Settings → Assistant): the risks, in the confirmation window's long form
SCENES["assistant-risks"] = {
    "do": [("settings", "page", "assistant"), ("test", "assistant", "on")],
    "wait": lambda st: st["asking"] == "Switch on the assistant?",
    "settle": 1.2, "undo": [("power", "cancel"), ("settings", "close")],
}

# Choosing Hyprbars (Settings → Windows → Title bars): its risks, in Slate's confirmation window,
# with nothing built (the session's stand-in for slate-build-hyprbars says so)
SCENES["hyprbars-question"] = {
    "do": [("test", "hyprbars", "choose")],
    "wait": lambda st: st["asking"] == "Use Hyprbars?",
    "settle": 1.2, "undo": [("power", "cancel")],
}

# The Welcome window's "Glass or flat?" page, and the whole window on glass (it follows the
# theme in use, as it can be opened again from Settings)
SCENES["welcome-look"] = {
    "do": [("welcome", "page", "3")], "wait": lambda st: st["welcome"]["open"] and st["welcome"]["page"] == 3,
    "settle": 1.2, "undo": [("welcome", "close")],
}
SCENES["welcome-glass"] = {
    "settings": {"glass": "true"},
    "do": [("welcome", "page", "5")], "wait": lambda st: st["welcome"]["open"] and st["welcome"]["page"] == 5,
    "settle": 5, "undo": [("welcome", "close")],       # (glass: its blur is made the first time)
}

# Without systemd or elogind (seatd alone): the Power page's lid and power button rows greyed,
# with why, and the power menu without Suspend, Restart and Shut down
SCENES["settings-power-no-login-service"] = {
    "do": [("test", "system", "none"), ("settings", "page", "power")],
    "wait": lambda st: st["system"]["logind"] == "none" and st["settings"]["open"] and st["settings"]["section"] == "power",
    "settle": 1.2, "undo": [("settings", "close"), ("test", "system", "")],
}
SCENES["panel-session-no-login-service"] = {
    "do": [("test", "system", "none"), ("bar", "panel", "session")],
    "wait": lambda st: st["system"]["logind"] == "none" and st["popout"] == "session",
    "settle": 1.2, "undo": [("popout", "close"), ("test", "system", "")],
}

# A workspace with a name of its own: the window mode panel's title (with its pencil), and the
# question that renames it
SCENES["panel-windowmode-named"] = {
    "do": [("workspacename", "set", "1", "Coding"), ("bar", "panel", "windowmode")],
    "wait": lambda st: st["popout"] == "windowmode" and st["workspaceNames"].get("1") == "Coding",
    "settle": 1.2, "undo": [("popout", "close"), ("workspacename", "set", "1", "")],
}
SCENES["rename-workspace"] = {
    "do": [("workspacename", "set", "1", "Coding"), ("test", "renameWorkspace")],
    "wait": lambda st: st["asking"] == "Rename \u201cCoding\u201d",
    "settle": 1.2, "undo": [("power", "cancel"), ("workspacename", "set", "1", "")],
}

# The secret workspace showing with nothing on it: the note in the middle saying so
SCENES["secret-empty"] = {
    "do": [("!hyprctl", "dispatch", "function() hl.dispatch(hl.dsp.workspace.toggle_special()) end")],
    "wait": lambda st: len(st["secretEmpty"]) == 1,
    "settle": 1.2,
    "undo": [("!hyprctl", "dispatch", "function() hl.dispatch(hl.dsp.workspace.toggle_special()) end")],
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

# The dock magnified under the pointer, on glass, with whole icons (tiles behind them): Slate's
# tiles above the dock keep the dock's glass behind their frosting (DockBacking.qml)
SCENES["dock-magnified-glass"] = {
    "settings": {"glass": "true", "iconFill": "false"},
    # (the Apps button: the slot most lifted, with its neighbours part way)
    "do": [("test", "dockHover", 0)],
    "wait": lambda st: True, "settle": 5,       # (glass: its blur is made the first time)
    "undo": [("test", "dockHover", -1)],
}

# Settings → Displays lists the switched-off virtual screen by name: Virtual-1 here, Virtual-2
# on GitHub's runners
SCENES["settings-displays"]["mask"] = [(505, 538, 220, 24)]

# Settings → Displays with HDR on (the test screen can't really show HDR: Slate remembers
# displays that could, in displays.json, which is what this sets up; its name is "")
_HDR = '{"": {"hdrCapable": true, "hdr": "on"}}'
SCENES["settings-displays-hdr"] = {
    "do": [("!sh", "-c", 'mkdir -p "$HOME/.local/state/slate" && printf %s \'' + _HDR + '\' > "$HOME/.local/state/slate/displays.json"'),
           ("settings", "find", "displays", "HDR")],
    "wait": lambda st: st["settings"]["open"] and st["settings"]["section"] == "displays", "settle": 2,
    "undo": [("settings", "close"), ("!sh", "-c", 'rm -f "$HOME/.local/state/slate/displays.json"')],
}

# About → What Slate is using: its memory and processor right now
SCENES["settings-about"]["mask"] = [(512, 505, 630, 90)]

# The launcher's scrollbar: its length follows how many apps have loaded so far
SCENES["launcher"]["mask"] = [(978, 250, 14, 420)]

