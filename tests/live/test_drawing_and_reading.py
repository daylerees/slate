"""Work done only when it's seen or its input changed (found in a review): Settings → Wallpaper
decoded every picture in the folder at once, Settings pages ran the same lookups every time
they opened, clipboard history was read again on every copy with the picker hidden, and the
emoji list was read separately by the picker and the launcher."""
import json
import os

from PIL import Image

from live import LiveCase


class WallpaperTiles(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("wallpaperFolder", "wallpaperShowSlate"):
            self.keep_setting(key)
        self.folder = self.s.h("Pictures", "many")
        os.makedirs(self.folder, exist_ok=True)
        for i in range(30):
            path = os.path.join(self.folder, "w%02d.png" % i)
            if not os.path.exists(path):
                Image.new("RGB", (1600, 1000), (i * 8, 80, 160)).save(path)
        self.config("wallpaperShowSlate", "false")
        self.config("wallpaperFolder", self.folder)
        self.addCleanup(lambda: self.ipc("settings", "close"))

    def test_only_tiles_near_the_view_draw_their_picture(self):
        self.ipc("settings", "page", "wallpaper")
        st = self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "wallpaper"
                       and st["settings"]["thumbsMade"] > 0 and st["settings"]["thumbsLoading"] == 0,
                       "the wallpaper page's first pictures", timeout=20)
        first = st["settings"]["thumbsMade"]
        self.assertLess(first, 30, "every picture in the folder was decoded as the page opened")
        # ...and scrolling down draws the rest
        self.ipc("test", "settingsWheel", "40")
        self.wait(lambda st: st["settings"]["thumbsMade"] > first, "more pictures once scrolled to", timeout=10)


class Lookups(LiveCase):
    def test_a_page_opened_again_looks_nothing_up_again(self):
        self.addCleanup(lambda: self.ipc("settings", "close"))
        for page in ("input", "datetime", "screenshots", "icons"):
            self.ipc("settings", "page", page)
            self.wait(lambda st: st["settings"]["section"] == page, page)
        self.s.settle(3)
        reads = self.s.state()["lookups"]
        self.assertGreater(reads, 0)
        # (Screenshots excepted: it looks for its tools each time, below)
        for page in ("input", "datetime", "icons"):
            self.ipc("settings", "page", page)
            self.wait(lambda st: st["settings"]["section"] == page, page)
        self.s.settle(1.5)
        self.assertEqual(self.s.state()["lookups"], reads, "a page opened again ran its lookups again")

    def test_screenshots_looks_for_its_tools_each_time(self):
        """A tool it says is missing is often installed from a terminal meanwhile: looked for
        each time the page opens (it was once a session, so it went on saying it was missing)."""
        self.addCleanup(lambda: self.ipc("settings", "close"))
        self.ipc("settings", "page", "screenshots")
        self.wait(lambda st: st["settings"]["section"] == "screenshots", "Screenshots")
        self.s.settle(1.5)
        reads = self.s.state()["lookups"]
        self.ipc("settings", "page", "datetime")
        self.wait(lambda st: st["settings"]["section"] == "datetime", "another page")
        self.ipc("settings", "page", "screenshots")
        self.wait(lambda st: st["settings"]["section"] == "screenshots" and st["lookups"] > reads, "the tools looked for again", timeout=8)


class Picker(LiveCase):
    def index(self):
        return os.path.join(self.s.h.state, "slate", "clipboard", "index.json")

    def write(self, n):
        os.makedirs(os.path.dirname(self.index()), exist_ok=True)
        with open(self.index(), "w") as f:
            json.dump({"entries": [{"kind": "text", "text": "copied %d" % i} for i in range(n)]}, f)

    def test_clipboard_history_waits_while_the_picker_is_hidden(self):
        self.addCleanup(lambda: self.ipc("picker", "close"))
        self.write(1)
        self.ipc("picker", "clipboard")
        self.wait(lambda st: st["picker"]["open"], "the clipboard history")
        self.ipc("picker", "close")
        self.wait(lambda st: not st["picker"]["open"], "the picker to close")
        self.s.settle(0.8)
        reads = self.s.state()["picker"]["clipReads"]
        for n in (2, 3, 4):
            self.write(n)
            self.s.settle(0.5)
        self.assertEqual(self.s.state()["picker"]["clipReads"], reads, "the history was read on a copy with the picker hidden")
        # ...and opening it reads it once (it was read at every opening too, twice after a copy)
        self.ipc("picker", "clipboard")
        self.wait(lambda st: st["picker"]["clipReads"] == reads + 1, "the history read as it opened", timeout=5)
        self.s.settle(0.8)
        self.assertEqual(self.s.state()["picker"]["clipReads"], reads + 1, "read twice as it opened")
        # Closed and opened again with nothing copied meanwhile: not read at all
        self.ipc("picker", "close")
        self.wait(lambda st: not st["picker"]["open"], "the picker to close")
        self.ipc("picker", "clipboard")
        self.wait(lambda st: st["picker"]["open"], "the picker again")
        self.s.settle(0.8)
        self.assertEqual(self.s.state()["picker"]["clipReads"], reads + 1, "read again with nothing new")

    def test_clear_all_asks_first(self):
        """Clear all deleted the whole history in one click: now Slate's confirmation window
        asks, and saying no keeps everything."""
        self.addCleanup(lambda: self.ipc("power", "cancel"))
        self.addCleanup(lambda: self.ipc("picker", "close"))
        self.write(3)
        self.ipc("picker", "clipboard")
        self.wait(lambda st: st["picker"]["open"], "the clipboard history")
        self.ipc("test", "pickerClearAll")
        st = self.wait(lambda st: st["power"]["open"], "the question")
        self.assertEqual(st["power"]["title"], "Clear your clipboard history?")
        self.assertFalse(st["picker"]["open"], "the picker stayed open over the question")
        self.ipc("power", "cancel")
        self.wait(lambda st: not st["power"]["open"], "the question to close")
        self.s.settle(0.5)
        with open(self.index()) as f:
            self.assertEqual(len(json.load(f)["entries"]), 3, "the history was cleared without a yes")
        # ...and a yes clears it
        self.ipc("picker", "clipboard")
        self.wait(lambda st: st["picker"]["open"], "the clipboard history again")
        self.ipc("test", "pickerClearAll")
        self.wait(lambda st: st["power"]["open"], "the question again")
        self.ipc("test", "powerAccept")
        def cleared():
            try:
                with open(self.index()) as f:
                    return json.load(f)["entries"] == []
            except (OSError, ValueError):
                return False
        self.wait(lambda st: cleared(), "the history cleared", timeout=5)

    def test_the_emoji_list_is_read_once_for_both(self):
        self.addCleanup(lambda: self.ipc("picker", "close"))
        self.ipc("picker", "emoji")
        self.wait(lambda st: st["picker"]["emojiReads"] >= 1, "the emoji list")
        self.ipc("picker", "close")
        before = self.s.state()["picker"]["emojiReads"]
        self.addCleanup(lambda: self.ipc("launcher", "close"))
        self.ipc("launcher", "search", ":smile")
        self.s.settle(1)
        self.assertEqual(self.s.state()["picker"]["emojiReads"], before, "the launcher read the emoji list again")


class OverviewBlur(LiveCase):
    def test_one_blurred_wallpaper_for_a_monitors_cards(self):
        self.keep_setting("glass")
        self.config("glass", "true")
        self.wait(lambda st: st["overview"]["blurOn"], "Hyprland's blur on", timeout=15)
        for ws in (1, 2):
            self.s.hyprctl("dispatch", 'function() hl.exec_cmd("foot --title blur-%d sleep 60", { workspace = "%d silent" }) end' % (ws, ws))
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() for _, w in ipairs(hl.get_windows()) do if (w.title or ''):match('^blur%-') then hl.dispatch(hl.dsp.window.close({ window = 'address:' .. w.address })) end end end"))
        self.wait(lambda st: {w["workspace"] for w in st["windows"] if w["title"].startswith("blur-")} == {1, 2}, "a window on workspaces 1 and 2", timeout=15)
        self.addCleanup(lambda: self.ipc("overview", "close"))
        self.ipc("overview", "open")
        st = self.wait(lambda st: st["overview"]["open"] and st["overview"]["blurs"] > 0, "the overview's blur", timeout=10)
        self.s.settle(0.5)
        self.assertEqual(self.s.state()["overview"]["blurs"], 1, "the wallpaper was blurred more than once for one monitor's cards")


class SwitcherBlur(LiveCase):
    def test_one_blurred_wallpaper_for_a_monitors_cards(self):
        """The switcher's strip repeats its windows round the loop, and every card blurred the
        wallpaper for itself: now once for each monitor of the windows shown."""
        self.keep_setting("glass")
        self.config("glass", "true")
        self.wait(lambda st: st["overview"]["blurOn"], "Hyprland's blur on", timeout=15)
        for ws in (1, 2):
            self.s.hyprctl("dispatch", 'function() hl.exec_cmd("foot --title sblur-%d sleep 60", { workspace = "%d silent" }) end' % (ws, ws))
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() for _, w in ipairs(hl.get_windows()) do if (w.title or ''):match('^sblur%-') then hl.dispatch(hl.dsp.window.close({ window = 'address:' .. w.address })) end end end"))
        self.wait(lambda st: {w["workspace"] for w in st["windows"] if w["title"].startswith("sblur-")} == {1, 2}, "the windows", timeout=15)
        self.addCleanup(lambda: self.ipc("switcher", "cancel"))
        self.ipc("switcher", "next")
        self.wait(lambda st: st["switcher"]["open"] and st["switcher"]["blurs"] > 0, "the switcher's blur", timeout=10)
        self.s.settle(0.5)
        self.assertEqual(self.s.state()["switcher"]["blurs"], 1, "the wallpaper was blurred more than once for one monitor's cards")
