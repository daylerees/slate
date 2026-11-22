"""Settings → App Rules (Config.appRulesLua): a rule for an app becomes a Hyprland window rule
matched on its whole window class, and the app's next window opens where and how it says. A
changed or removed rule is made again (the old one switched off), and a class that isn't a
plain name never reaches Hyprland. Asked for, 2026-11-22."""
import json

from live import LiveCase
from test_look_and_hardware import lua, settings_in_hyprland


class AppRules(LiveCase):
    def setUp(self):
        super().setUp()
        self.keep_setting("appRules")
        self.close_windows()
        self.addCleanup(self.close_windows)

    def rules(self, rules):
        before = self.s.state()["hypr"]["pushes"]
        # (a space first: qs ipc strips the brackets from an argument starting with "[")
        self.ipc("config", "set", "appRules", " " + json.dumps(rules))
        settings_in_hyprland(self, before)

    def opened(self, cls, title):
        self.s.hyprctl("eval", 'hl.exec_cmd("foot --app-id %s -T %s sleep 30")' % (cls, title))
        for _ in range(75):
            c = next((c for c in self.s.hyprctl("clients", json_out=True) if c.get("title") == title), None)
            if c:
                self.s.settle(0.5)
                return next(c for c in self.s.hyprctl("clients", json_out=True) if c.get("title") == title)
            self.s.settle(0.2)
        self.fail(f"{title} didn't open")

    def test_where_and_how(self):
        self.rules([{"cls": "slate.ruled", "name": "Ruled", "workspace": 3, "as": "float", "monitor": ""},
                    {"cls": "slate.nothing", "name": "Nothing set", "workspace": 0, "as": "", "monitor": ""}])
        c = self.opened("slate.ruled", "Ruled")
        self.assertEqual((c["workspace"]["id"], c["floating"]), (3, True), "the rule wasn't followed")
        self.assertEqual(self.s.hyprctl("activeworkspace", json_out=True)["id"], 3, "it didn't take you there")
        # (the whole class: one that only starts the same is left alone)
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = 1 })) end")
        c = self.opened("slate.ruled.other", "Other")
        self.assertEqual((c["workspace"]["id"], c["floating"]), (1, False), "a longer class matched the rule")

    def test_changed_and_removed(self):
        self.rules([{"cls": "slate.ruled", "name": "Ruled", "workspace": 3, "as": "", "monitor": ""}])
        self.rules([{"cls": "slate.ruled", "name": "Ruled", "workspace": 0, "as": "maximize", "monitor": ""}])
        c = self.opened("slate.ruled", "Changed")
        self.assertEqual(c["workspace"]["id"], 1, "the old rule still sent it to workspace 3")
        self.assertEqual(c["fullscreen"], 1, "not maximized")
        self.close_windows()
        self.rules([])
        c = self.opened("slate.ruled", "Removed")
        self.assertEqual((c["workspace"]["id"], c["floating"], c["fullscreen"]), (1, False, 0), "a removed rule still applied")

    def test_odd_names_never_reach_hyprland(self):
        self.rules([{"cls": 'bad") end; os.exit() --', "workspace": 3, "as": "float"},
                    {"cls": "slate.ruled", "workspace": 0, "as": "float", "monitor": 'x"y'}])
        self.assertEqual(lua(self, "SLATE_APP_RULES_FOR"), "slate.ruled|0|float|", "an odd name went into the rules")
        self.assertTrue(self.s.alive(), "Hyprland or Slate went away")

    def test_read_and_put_back(self):
        """config get gives a list as JSON, and a test can put it back as it was. It gave "" for no
        rules and "[object Object]" for some, so they were never put back, and leaked into the
        tests and pictures after."""
        rules = [{"cls": "slate.ruled", "name": "Ruled", "workspace": 3, "as": "float", "monitor": ""}]
        self.rules(rules)
        saved = self.setting("appRules")
        self.assertEqual(json.loads(saved), rules)
        self.rules([])
        self.assertEqual(self.setting("appRules"), "[]")
        self.set_back("appRules", saved)
        self.wait(lambda st: json.loads(self.setting("appRules")) == rules, "the rules put back")
