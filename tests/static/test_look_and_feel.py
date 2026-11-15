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
        page = slate.read("shell", "settings", "pages", "UpdatesPage.qml")
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


# Slate's own windows with a glass border (the panel each one draws), and how many each draws
BORDERED_WINDOWS = {"Launcher.qml": 1, "Assistant.qml": 1, "Switcher.qml": 1, "Picker.qml": 1,
                    "WallpaperSwitcher.qml": 1, "BarEditor.qml": 2}


class WindowBorders(Case):
    def test_slates_windows_share_the_window_border(self):
        """The border round Slate's own windows (the launcher, Nova, the switchers, the pickers,
        the bar's arranging panel) is one shared definition, drawn as Hyprland draws the active
        window's (the same colours and glass sheen, from one function both use), as wide as
        Settings → Windows → Window borders (in Hyprland's pixels, so divided by the Interface
        size), none without glass."""
        cfg = slate.read("shell", "Config.qml")
        self.assertRegex(cfg, r"readonly property var activeBorderSheen: borderSheen\(accent, 0\.6,")
        self.assertRegex(cfg, r"readonly property var windowBorderColours: activeBorderSheen\.")
        self.assertRegex(cfg, r"readonly property real windowBorderWidth: glass \? [^\n]*s\.windowBorderSize[^\n]*/ uiScale : 0")
        look = slate.read("shell", "HyprlandLook.qml")
        self.assertIn("sheen(Config.activeBorderSheen)", look, "Hyprland's active border isn't the shared sheen")
        self.assertNotIn("toWhite", look, "Hyprland's border sheen worked out on its own")
        ring = slate.read("shell", "WindowBorder.qml")
        self.assertIn("Config.windowBorderColours", ring)
        self.assertIn("Config.windowBorderWidth", ring)
        for f, n in BORDERED_WINDOWS.items():
            src = slate.read("shell", f)
            with self.subTest(f):
                self.assertEqual(len(re.findall(r"\bWindowBorder \{ radius: parent\.radius \}", src)), n, "not the shared window border")
                self.assertNotRegex(src, r"border\.(width|color): Config\.windowBorder", "a plain border instead of the shared one")
                self.assertNotIn("Config.glassEdge", src, "a border of its own")
                self.assertNotRegex(src, r"border\.width: Config\.glass \? 1 : 0", "a border of its own")


# The muted hover in a color binding: Config.hover itself (not hoverStrength), its red, or
# hoverOn(); a file's own color properties set from them (BarEditor's controlLit) count too
_HOVER = r"Config\.hover\b(?!Strength)|Config\.hoverDanger\b|Config\.hoverOn\("


def _objects(src):
    """Each { } block's own text (what's nested in it left out) and the line it starts on."""
    stack, own, out = [], {}, []
    for i, ch in enumerate(src):
        if ch == "{":
            stack.append(i)
            own[i] = []
        elif ch == "}":
            if stack:
                s = stack.pop()
                out.append((src.count("\n", 0, s) + 1, "".join(own.pop(s))))
        elif stack:
            own[stack[-1]].append(ch)
    return out


def _binding(text, prop):
    """`prop: …` in an object's own text, with the lines that carry it on (starting ? or :)."""
    m = re.search(rf"^[ \t]*{prop}:(.*(?:\n[ \t]*[?:].*)*)", text, re.M)
    return m.group(1) if m else ""


class HoverTracksThePointer(Case):
    # Everywhere: the menu bar's hovers and the login screen's too (an exception there once let
    # the bar's fade). Nothing is skipped
    SKIP = ()
    SKIP_FILES = ()

    def test_the_muted_hover_never_fades(self):
        """Under the pointer the muted hover is there at once and gone at once, as the launcher's
        highlight is (moved by the pointer, it doesn't slide or fade: Launcher.qml's moveMs).
        A fade on each row's hover (90-100 ms in menus, panels and Settings) left a trail of
        half-lit rows behind a pointer moving down a list, and read as lag. So nothing whose
        color is the muted hover fades its color; where a row is also selectable, the active
        color fades on the row and the hover is HoverFill's, which never fades."""
        for f in slate.files("shell", ".qml", skip=self.SKIP):
            if f in self.SKIP_FILES:
                continue
            src = slate.read(f)
            names = [_HOVER] + [rf"\b{n}\b" for n in re.findall(rf"property color (\w+):[^\n]*(?:{_HOVER})", src)]
            hover = re.compile("|".join(names))
            for line, text in _objects(src):
                with self.subTest(f"{f}:{line}"):
                    if hover.search(_binding(text, "color")):
                        self.assertNotIn("Behavior on color", text, "the muted hover fades: drop the fade, or put the hover in a HoverFill")
                    # (a hover drawn as the accent at the hover's strength, shown by opacity)
                    o = _binding(text, "opacity")
                    if re.search(r"\b(Config\.|bar\.|wd\.)?hoverStrength\b", o) and re.search(r"\.hovered\b|\blit\b", o):
                        self.assertNotIn("Behavior on opacity", text, "the muted hover fades in and out")

    def test_hover_fill_fades_only_with_selection(self):
        """HoverFill shows its hover layer at once; only `gone` (selected, or let go of) fades."""
        src = slate.read("shell", "HoverFill.qml")
        self.assertEqual(src.count("Behavior on"), 1, "HoverFill animates more than its `gone` fade")
        self.assertRegex(src, r"opacity: gone \? 0 : 1\s*\n\s*Behavior on opacity \{ NumberAnimation \{ duration: Config\.ms\(")
        self.assertEqual(len(re.findall(r"visible: !?hf\.hovered", src)), 2, "the base and hover layers swap on hovered, at once")


class DockBackings(Case):
    def test_dock_backings_follow_glass(self):
        """A dock tile's backing (DockBacking: the dock's glass behind a lifted tile) shows with
        glass only: DockBacking decides that itself, and a tile that narrows it further keeps
        `&& Config.glass`. More's once set its own `visible`, and showed a backing with glass off."""
        import glob, os
        for path in sorted(glob.glob(os.path.join(slate.ROOT, "shell", "*.qml"))):
            src = open(path, encoding="utf-8").read()
            for m in re.finditer(r"\bDockBacking \{([^{}]*)\}", src):
                with self.subTest(os.path.basename(path)):
                    vis = re.search(r"\bvisible:([^\n]*)", m.group(1))
                    if vis:
                        self.assertRegex(vis.group(1), r"&& Config\.glass\s*$", "a DockBacking that shows without glass")
        self.assertIn("visible: Config.glass", slate.read("shell", "DockBacking.qml"))
