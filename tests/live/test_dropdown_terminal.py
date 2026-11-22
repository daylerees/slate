"""The drop-down terminal (Super+`; binds.lua shared.dropdown, windowrules.lua placeDropdown,
Settings → Windows): the shortcut brings a terminal down across the top of the screen under the
bar, on a special workspace of its own; again puts it away, and again brings back the same one.
A changed height places it again. It's Slate's own, so the dock and the launcher leave it out.
Asked for, 2026-11-22."""
from live import LiveCase

CLASS = "org.slate.dropdown"
GAP = 10                            # (windowrules.lua DROPDOWN_GAP)


class DropdownTerminal(LiveCase):
    def setUp(self):
        super().setUp()
        self.keep_setting("dropdownHeight")
        self.config("dropdownHeight", "45")
        self.close_windows()
        self.addCleanup(self.close_windows)
        self.addCleanup(self.hide)

    def term(self):
        return next((c for c in self.s.hyprctl("clients", json_out=True) if c.get("class") == CLASS and c.get("mapped")), None)

    def showing(self):
        m = next(m for m in self.s.hyprctl("monitors", json_out=True) if m.get("focused"))
        return (m.get("specialWorkspace") or {}).get("name") == "special:dropdown"

    def hide(self):
        if self.showing():
            self.s.hyprctl("dispatch", 'function() hl.dispatch(hl.dsp.workspace.toggle_special("dropdown")) end')

    def shortcut(self, want_showing, what):
        """What Super+` does (binds.lua's dropdownTerminal; the key itself is test_the_shortcut's),
        then the terminal showing (or not)."""
        self.s.hyprctl("dispatch", "function() dropdownTerminal() end")
        for _ in range(50):
            if self.term() and self.showing() == want_showing:
                return self.term()
            self.s.settle(0.2)
        self.fail(f"Super+` didn't {what}: terminal {self.term()}, showing {self.showing()}")

    def test_the_shortcut(self):
        """Super+` is bound, described for Settings → Shortcuts."""
        binds = self.s.run(["hyprctl", "binds"])[1].split("\n\n")
        grave = [b for b in binds if "key: grave" in b and "modmask: 64" in b]
        self.assertEqual(len(grave), 1, grave)
        self.assertIn("description: Apps: Show or hide the drop-down terminal", grave[0])

    def placed(self, height):
        m = next(m for m in self.s.hyprctl("monitors", json_out=True) if m.get("focused"))
        top = m["reserved"][1]
        return [GAP, top + GAP], [m["width"] - 2 * GAP, int(m["height"] * height)]

    def test_down_away_and_back(self):
        t = self.shortcut(True, "bring the terminal down")
        self.assertEqual(t["workspace"]["name"], "special:dropdown")
        self.assertTrue(t["floating"])
        at, size = self.placed(0.45)
        t = self.steady(self.term, floor=0.4)
        self.assertEqual((t["at"], t["size"]), (at, size), "not across the top under the bar")
        first = t["address"]
        self.shortcut(False, "put it away")
        self.assertEqual(self.term()["address"], first, "putting it away closed it")
        t = self.shortcut(True, "bring it back")
        self.assertEqual(t["address"], first, "a new terminal came, not the same one")

    def test_a_new_height_places_it_again(self):
        self.shortcut(True, "bring the terminal down")
        self.config("dropdownHeight", "60")
        at, size = self.placed(0.60)
        # (a pixel either way: resized while open, foot answers a pixel taller than asked, as
        # terminals may; placed as it opens it's exact, test_down_away_and_back)
        for _ in range(40):
            t = self.term()
            if t["at"] == at and t["size"][0] == size[0] and abs(t["size"][1] - size[1]) <= 2:
                return
            self.s.settle(0.2)
        t = self.term()
        self.fail(f"not placed again at the new height: {t['at']} {t['size']}, wanted {at} {size}")

    def test_not_a_running_app(self):
        """With only the drop-down terminal open, the dock shows no app as running."""
        self.shortcut(True, "bring the terminal down")
        st = self.steady(lambda: self.s.state()["dock"]["slots"], floor=0.6)
        self.assertEqual([x for x in st if x.get("windows")], [], "the dock shows the drop-down terminal as a running app")
