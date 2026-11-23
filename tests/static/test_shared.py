"""Things Slate draws or works out in one place for every window: if a file starts doing it
its own way again, the copies drift apart (they did, once)."""
import os
import re

import slate
from slate import Case

SHELL = slate.path("shell")


def qml_files():
    return slate.qml_names()


class Shared(Case):
    def test_only_toggle_draws_the_switch_track(self):
        """Every on/off switch is Toggle.qml: nobody else draws a 42 x 24 track with a knob."""
        for name in qml_files():
            if name == "Toggle.qml":
                continue
            with self.subTest(name):
                self.assertNotRegex(slate.read("shell", name), r"width:\s*42;\s*height:\s*24",
                                    f"{name} draws its own switch: use Toggle.qml")

    def test_state_and_cache_folders_come_from_config(self):
        """~/.local/state and ~/.cache are worked out once (Config.stateHome / cacheHome). The
        paths that deliberately stay at HOME (dock.json, the tiles and so on) don't read the
        XDG variables at all."""
        for name in qml_files():
            if name == "Config.qml":
                continue
            with self.subTest(name):
                self.assertNotRegex(slate.read("shell", name), r"XDG_(STATE|CACHE)_HOME",
                                    f"{name} reads the XDG folder itself: use Config.stateHome / cacheHome")

    def test_notices_are_built_by_config_notify(self):
        """Slate's notices go through Config.notify (one place for the icon, the page they open
        and the "--" before the words). Files not yet moved over are listed here."""
        not_yet = {"Config.qml", "Assistant.qml", "SettingsWindow.qml", "Updates.qml"}
        for name in qml_files():
            if name in not_yet:
                continue
            with self.subTest(name):
                self.assertNotIn('"notify-send"', slate.read("shell", name),
                                 f"{name} builds a notify-send call itself: use Config.notify")

    def test_times_ago_come_from_config(self):
        """A time like "2 min ago" is Config.ago; no window works the minutes out again.
        (Settings' Updates page rounds and words its own: "just now", "checked 5 min ago".)"""
        for name in qml_files():
            if name in ("Config.qml", "SettingsWindow.qml"):
                continue
            with self.subTest(name):
                self.assertNotIn('" min ago"', slate.read("shell", name),
                                 f"{name} words its own 'min ago': use Config.ago")

    def test_the_carousel_is_shared(self):
        """The switcher's and the overview's strips run on the same paths, motion maths, repeat
        count, capture lookup and window outline: only CarouselPaths.qml draws the paths, only
        CardMotion.qml works out how a card moves, only WindowShape.qml draws an outline."""
        for name in ("Switcher.qml", "WorkspaceOverview.qml"):
            src = slate.read("shell", name)
            with self.subTest(name):
                for own in ("PathAttribute", "PathAngleArc", "fanStep", "Qt.rgba(0.07, 0.08, 0.1, 0.72)"):
                    self.assertNotIn(own, src, f"{name} has its own copy of {own}")
                for shared in ("CarouselPaths {", "CardMotion {", "WindowShape {", "Carousel.reps(", "Carousel.shotFor("):
                    self.assertIn(shared, src, f"{name} should use {shared}")

    def test_dialogs_share_their_card(self):
        """The confirmation window and the password window are built from the same backdrop,
        card, round icon and buttons; neither draws its own."""
        for name in ("PowerConfirm.qml", "PolkitAgent.qml"):
            src = slate.read("shell", name)
            with self.subTest(name):
                for shared in ("DialogBackdrop {", "DialogCard {", "DialogIcon {", "DialogButton {"):
                    self.assertIn(shared, src, f"{name} should use {shared}")
                self.assertNotIn("component DialogButton", src)
                self.assertNotIn("width: 56; height: 56", src)

    def test_one_way_to_run_in_a_terminal(self):
        """Running something in your terminal goes through Config.inTerminalLua / runInTerminal,
        which use the session's TERMINAL_RUN (the flag each terminal wants). Settings → Assistant's
        Sign in built `TERMINAL .. " -e …"` by hand, which WezTerm, GNOME Terminal, Ptyxis and Xfce
        Terminal don't take (a bug)."""
        # (every QML file, Settings' pages and the login screen's included)
        names = sorted(os.path.relpath(os.path.join(d, f), SHELL) for d, _, fs in os.walk(SHELL) for f in fs if f.endswith(".qml"))
        self.assertIn("settings/pages/AssistantPage.qml", names)
        for name in names:
            if name == "Config.qml":
                continue
            with self.subTest(name):
                src = slate.read("shell", name)
                self.assertNotIn("TERMINAL_RUN or", src, f"{name} builds its own terminal line: use Config.inTerminalLua")
                self.assertNotRegex(src, r"TERMINAL \.\. .\s*-e", f"{name} runs the terminal with -e by hand: use Config.runInTerminal")
        self.assertIn("Config.runInTerminal(", slate.read("shell", "settings", "pages", "AssistantPage.qml"))
        self.assertIn("Config.runInTerminal(", slate.read("shell", "Assistant.qml"))

    def test_about_opens_your_settings_file(self):
        """About → Settings file → Open file opened a settings.json next to the page's own file,
        which isn't there (a bug): it's yours, in your Slate folder."""
        src = slate.read("shell", "settings", "pages", "AboutPage.qml")
        line = next(l for l in src.split("\n") if 'label: "Open file"' in l)
        self.assertIn('Config.userDir + "/settings.json"', line)


class Migrations(Case):
    def test_each_says_until_when_and_is_gone_by_then(self):
        """Code that reads settings in an older form says until when it's kept ("Migration, kept
        until YYYY-MM"), and is taken out once that's passed: this fails then, as the reminder."""
        import datetime
        today = datetime.date.today().strftime("%Y-%m")
        found, late = 0, []
        for root, _, files in os.walk(SHELL):
            for f in files:
                if not f.endswith((".qml", ".lua", ".py", ".sh")):
                    continue
                path = os.path.join(root, f)
                for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                    for until in re.findall(r"Migration, kept until (\d{4}-\d{2})", line):
                        found += 1
                        if until < today:
                            late.append(f"{os.path.relpath(path, SHELL)}:{n} (until {until})")
        self.assertGreater(found, 0)
        self.assertEqual(late, [], "these migrations are past their date: take them out")
