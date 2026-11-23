"""Accessibility → every control in Settings can take the keyboard, as in the bar's panels
(test_keyboard_navigation.py's EveryPanelControl): nothing on any page, or in the sidebar, takes
a click but is left out of Tab (SettingsWindow.testUnreachable lists any that are, by what they
say and where). Settings' controls were reachable by the pointer alone (a bug)."""
import json
import re

import slate
from live import LiveCase


def settings_pages():
    block = slate.read("shell", "SettingsIndex.qml").split("readonly property var pages:")[1].split("\n    ]")[0]
    return re.findall(r"\{\s*id:\s*\"(\w+)\"", block)


class EverySettingsControl(LiveCase):
    def wait_or_none(self, check, timeout=5):
        try:
            return self.wait(check, timeout=timeout)
        except AssertionError:
            return None

    def test_nothing_takes_a_click_but_not_the_keyboard(self):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        gaps = {}
        for page in ["overview"] + settings_pages():
            self.ipc("settings", "page", page)
            if not self.wait_or_none(lambda st: st["settings"]["open"] and st["settings"]["section"] == page):
                gaps[page] = ["(didn't open)"]
                continue
            self.s.settle(0.6)
            found = json.loads(self.ipc("test", "settingsUnreachable"))
            if found:
                gaps[page] = found
        self.assertEqual(gaps, {}, "\n" + "\n".join(f"{p}: {', '.join(g[:8])}{' …' if len(g) > 8 else ''}" for p, g in gaps.items()))


class TrayMenuByKeyboard(LiveCase):
    """An app's tray menu works by keyboard, as Slate's own menus do: the bar's keyboard mode could
    open one, but it took nothing but Escape, so the keyboard was stuck there (a bug). Down and Up
    move (past separators and greyed rows), Enter chooses, Right opens a submenu, Left goes back,
    Escape goes back or closes. (Pretend rows: the test computer has no app with a menu.)"""
    ROWS = [{"text": "Open"}, {"sep": True}, {"text": "Greyed", "enabled": False},
            {"text": "More", "rows": [{"text": "Deeper"}, {"text": "Deepest"}]}, {"text": "Quit"}]

    def open_menu(self):
        # (a space first: qs ipc takes the brackets off an argument that starts with one)
        self.ipc("test", "trayMenuPretend", " " + json.dumps(self.ROWS))
        self.wait(lambda st: st["trayMenu"]["open"], "the tray menu")
        self.addCleanup(lambda: self.press("-k", "Escape", "-k", "Escape"))
        self.s.settle(0.4)

    def test_down_past_separators_and_enter_chooses(self):
        self.open_menu()
        self.press("-k", "Down", "-k", "Down", "-k", "Down")
        self.wait(lambda st: st["trayMenu"]["hot"] == 4, "Down three times: Open, More, Quit (the separator and greyed row passed)")
        self.press("-k", "Return")
        st = self.wait(lambda st: not st["trayMenu"]["open"], "the menu closed")["trayMenu"]
        self.assertEqual(st["chosen"], "Quit")

    def test_into_a_submenu_and_back(self):
        self.open_menu()
        self.press("-k", "Down", "-k", "Down", "-k", "Right")
        self.wait(lambda st: st["trayMenu"]["depth"] == 2, "Right on More: its submenu")
        self.press("-k", "Left")
        self.wait(lambda st: st["trayMenu"]["depth"] == 1 and st["trayMenu"]["open"], "Left: back to the menu")
        self.press("-k", "Escape")
        self.wait(lambda st: not st["trayMenu"]["open"], "Escape: closed")
