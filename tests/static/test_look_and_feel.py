"""Places that must follow docs/CONVENTIONS.md "Look and feel", found by reading the code:
scrolling views get shades, a scrollbar and smooth wheel; the title bar's buttons hover with
the muted hover, not the active colour; questions go through Slate's confirmation window."""
import os
import re

import slate
from slate import Case

# Files whose scrolling views were brought in line (the others keep their own checks)
SCROLLING = ["Popouts.qml"] + ["panels/" + n for n in os.listdir(slate.path("shell", "panels")) if n.endswith("Panel.qml")] + ["TrayMenu.qml", "Picker.qml", "SettingsWindow.qml", "AvatarPicker.qml", "BarEditor.qml"]

SCROLLING_PANELS = ["Popouts.qml"] + [f for f in SCROLLING if f.startswith("panels/")]


class Scrolling(Case):
    def test_every_scrolling_view_has_shades_scrollbar_and_smooth_wheel(self):
        """Anything that scrolls shows a soft shadow along its top edge once scrolled down and along
        its bottom edge while there's more below (ScrollShade, two), a ThinScrollbar and
        SmoothWheel. The Picker's list and grid share one pair, which follow root.view()."""
        for f in SCROLLING:
            src = slate.read("shell", f)
            for m in re.finditer(r"^\s*(?:Flickable|ListView|GridView)\s*\{\s*\n\s*id:\s*(\w+)", src, re.M):
                v = m.group(1)
                view = rf"(?:{v}|root\.view\(\))" if f == "Picker.qml" else v
                with self.subTest(f"{f}: {v}"):
                    self.assertRegex(src, rf"SmoothWheel\s*\{{\s*flick:\s*{v}\b", "no smooth wheel")
                    self.assertRegex(src, rf"ThinScrollbar\s*\{{[^}}]{{0,200}}?flick:\s*{view}", "no scrollbar")
                    # (one shade at the top, one at the bottom: each says how far it is from its end)
                    self.assertGreaterEqual(len(re.findall(rf"distance:[^\n]*{view}\.contentY", src)), 2, "shades missing")
                    self.assertRegex(src, rf"atBottom:\s*true", "no shade at the bottom")

    def test_no_hand_drawn_shades_or_scrollbars(self):
        """The shades and the bar are the shared ScrollShade and ThinScrollbar, never drawn again
        in a panel (Spaces, the notifications) or a dropdown (a 1 px bar)."""
        for f in SCROLLING_PANELS + ["SettingsWindow.qml"]:
            src = slate.read("shell", f)
            self.assertNotIn("Config.shade(Config.s.lightMode ? 0.12 : 0.32)", src, f"{f} draws a scroll shade of its own")
            self.assertNotIn("GradientStop { position: 0.0; color: pop.bg }", src, f"{f} draws a scroll shade of its own")
            self.assertNotRegex(src, r"width: 1\s*\n\s*height: Math\.max\(16, track", f"{f} draws a scrollbar of its own")


class TitleBarHover(Case):
    def test_title_bar_buttons_use_the_muted_hover(self):
        """Hovering is the muted hover (red for close), never the active colour or a solid red."""
        src = slate.read("shell", "TitleBar.qml")
        block = src[src.index('model: [{ act: "maximise"'):]
        block = block[:block.index("ClickArea")]
        self.assertNotIn("Config.accent", block, "a title bar button hovers in the active color")
        self.assertNotIn('Config.tint("#f28b8b")', block, "close hovers in a solid red")
        self.assertIn("Config.hoverDanger", block)
        self.assertIn("Config.hover", block)


class Questions(Case):
    def test_updates_confirm_in_slates_confirmation_window(self):
        """Updating over your changes and going back are asked with win.ask (PowerConfirm), not
        by a second click on the same button."""
        src = slate.read("shell", "SettingsWindow.qml")
        page = src[src.index("id: updatesPage"):src.index("id: webcamPage")]
        self.assertNotIn("confirmUpdate", page)
        self.assertNotIn("confirmRevert", page)
        self.assertNotRegex(page, r"(?i)click again")
        self.assertEqual(len(re.findall(r"win\.ask\s*=", page)), 2, "Update anyway and Go back both ask")
        self.assertIn("Updates.install()", page)
        self.assertIn("Updates.revert()", page)

    def test_welcome_asks_in_slates_confirmation_window(self):
        """The Welcome window has no confirmation card of its own: its light mode question goes
        through the confirmation window it's handed."""
        welcome = slate.read("shell", "Welcome.qml")
        self.assertNotIn("askCard", welcome)
        self.assertIn("confirmer.confirmWith(", welcome)
        self.assertRegex(slate.read("shell", "shell.qml"), r"Welcome \{[^}]*confirmer: powerConfirm")


class Greying(Case):
    def test_what_the_system_lacks_is_said_by_the_row(self):
        """A setting that can't be used because this computer has no systemd/elogind or no time
        service says so with its row's needs line, not by greying itself out with enabled:."""
        src = slate.read("shell", "SettingsWindow.qml")
        for expr in ("Config.canInhibit", "Config.hasLogind", "Config.canSuspend", "dateTimePane.canSet"):
            with self.subTest(expr):
                self.assertNotRegex(src, rf"\benabled:\s*{re.escape(expr)}\b")
                self.assertRegex(src, rf"\bneedsMet:\s*{re.escape(expr)}\s*\n\s*needs:\s*\"[^\"]{{12,}}\"")


class Sliders(Case):
    def test_the_hue_slider_keeps_its_drag(self):
        """Like ValueSlider: the scrolling page mustn't take the drag when the pointer drifts."""
        src = slate.read("shell", "SettingsWindow.qml")
        block = src.split("// Hue slider", 1)[1].split("MouseArea {", 1)[1][:400]
        self.assertIn("preventStealing: true", block)


class SpacesSave(Case):
    def test_save_lights_the_accent_under_the_pointer(self):
        src = slate.read("shell", "panels", "SpacesPanel.qml")
        self.assertRegex(src, r"spacesView\.canSave \? \(spSaveHover\.hovered \? Config\.accentLit : pop\.accent\)")
