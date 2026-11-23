"""session/hypr/config/monitors.lua: each monitor's best mode, until one is chosen for it.

A monitor's "preferred" mode is the one it recommends, which isn't always its best: an Odyssey
G9 recommends 3840x1080 at 120 Hz, though it shows 5120x1440 at 240 Hz, and Slate started it
there with no way to tell. So until a mode is chosen (Settings → Displays, or a rule of your
own), each monitor gets its largest resolution at its fastest rate there, never slower than it
recommends, stepping down a rate when one doesn't take.

monitors.lua is run under plain Lua with a stand-in for Hyprland's `hl`, which prints one line
per monitor rule, tab separated:
  MONITOR <output> <mode>     a rule was made
  ERR <message>               something failed
"""
import os

import slate
from slate import Case, run

MONITORS = slate.path("shell", "session", "hypr", "config", "monitors.lua")


def modes(*spec, preferred=0):
    """Lua for a list of modes from "WxH@rate" strings, the one at `preferred` recommended."""
    out = []
    for i, s in enumerate(spec):
        res, rate = s.split("@")
        w, h = res.split("x")
        out.append("{ width = %s, height = %s, refresh_rate = %s%s }"
                   % (w, h, rate, ", preferred = true" if i == preferred else ""))
    return "{ " + ", ".join(out) + " }"


# The Odyssey G9 on the author's desktop, as Hyprland lists it (the recommended one first)
G9 = modes("3840x1080@120.00", "5120x1440@240.00", "5120x1440@119.98", "5120x1440@60.00",
           "3840x1080@240.00", "3840x1080@60.00", "2560x1440@239.97", "1920x1080@239.93")
G9_DESC = "Samsung Electric Company Odyssey G95SC H1AK500000"

STUB = r"""
local function note(...) print(table.concat({ ... }, "\t")) end
MONITORS = {}               -- what hl.get_monitors() gives
local events, timers = {}, {}
hl = {
    monitor = function(spec) note("MONITOR", spec.output, spec.disabled and "off" or spec.mode) end,
    get_monitors = function() return MONITORS end,
    on = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end,
    timer = function(fn, opts) table.insert(timers, fn); return {} end,
}
MONITOR1 = ""
-- A monitor: showing `now` ("WxH@rate"), with these modes
function screen(name, desc, list, now)
    local w, h, r = now:match("^(%d+)x(%d+)@([%d.]+)$")
    local m = { name = name, description = desc, enabled = true, available_modes = list,
                mode = { width = tonumber(w), height = tonumber(h), refresh_rate = tonumber(r) } }
    table.insert(MONITORS, m)
    return m
end
-- What the screen shows now (Hyprland changing it, or falling back)
function shows(m, now)
    local w, h, r = now:match("^(%d+)x(%d+)@([%d.]+)$")
    m.mode = { width = tonumber(w), height = tonumber(h), refresh_rate = tonumber(r) }
end
function happen(event, arg) for _, fn in ipairs(events[event] or {}) do fn(arg) end end
-- The timers waiting, run once each (Hyprland's oneshot)
function tick() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
-- Your own monitors.lua, loading after Slate's config
function yours(spec) hl.monitor(spec) end

local ok, err = pcall((loadstring or load)(os.getenv("STUB_BEFORE")))
if not ok then note("ERR", tostring(err)) end
ok, err = pcall(dofile, os.getenv("STUB_CONFIG"))
if not ok then note("ERR", tostring(err)) end
ok, err = pcall((loadstring or load)(os.getenv("STUB_CASE")))
if not ok then note("ERR", tostring(err)) end
"""


class MonitorsLua(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "luajit", "lua5.1")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)

    def saved(self, lua):
        """Settings → Displays having kept something: its displays.lua."""
        d = os.path.join(self.h.state, "slate")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "displays.lua"), "w") as f:
            f.write(lua)

    def vkms(self, *outputs):
        """vkms's screens in a stand-in /sys (or none): where monitors.lua is told to look."""
        root = os.path.join(self.h.dir, "sys")
        for out in outputs:
            os.makedirs(os.path.join(root, "faux", "vkms", "drm", "card0", f"card0-{out}"), exist_ok=True)
        return f'SLATE_VKMS_DIRS = "{root}/faux/vkms/drm/card*/card*-*"\n'

    def do(self, case, before="", tests=False):
        """Load monitors.lua (with `before` run first: the monitors already there), then case:
        the rules made after Slate's own default one, as (output, mode)."""
        if "SLATE_VKMS_DIRS" not in before:
            before = self.vkms() + before            # (never this computer's own /sys)
        env = dict(self.h.env, STUB_CONFIG=MONITORS, STUB_BEFORE=before, STUB_CASE=case, SLATE_TEST="1" if tests else "")
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        lines = [line.split("\t") for line in out.splitlines()]
        self.assertEqual([l for l in lines if l[0] == "ERR"], [])
        rules = [(l[1], l[2]) for l in lines if l[0] == "MONITOR"]
        self.assertEqual(rules[0], ("", "preferred"), "Slate's default rule comes first")
        return rules[1:]

    def best(self, lua_modes):
        """slateBestModes for a list of modes, as Python strings."""
        env = dict(self.h.env, STUB_CONFIG=MONITORS, STUB_BEFORE=self.vkms(),
                   STUB_CASE="for _, m in ipairs(slateBestModes(%s)) do print('BEST\\t' .. m) end" % lua_modes)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        return [l.split("\t")[1] for l in out.splitlines() if l.startswith("BEST\t")]

    # ---- Choosing --------------------------------------------------------------------

    def test_a_screen_that_recommends_less_gets_its_largest_and_fastest(self):
        """The G9: 5120x1440, at 240 Hz, then its slower rates down to the recommended 120."""
        self.assertEqual(self.best(G9), ["5120x1440@240.00", "5120x1440@119.98"])

    def test_a_screen_already_at_its_best_is_left_alone(self):
        self.assertEqual(self.best(modes("2560x1440@165.00", "2560x1440@60.00", "1920x1080@165.00")), [])
        # (rates that differ only in the hundredths are the same rate)
        self.assertEqual(self.best(modes("2560x1600@120.00", "2560x1600@119.99", "1920x1200@120.00")), [])

    def test_a_faster_rate_at_the_recommended_size(self):
        """A monitor recommending 60 Hz that also has 165 Hz at that size."""
        self.assertEqual(self.best(modes("2560x1440@59.95", "2560x1440@165.00", "2560x1440@144.00")),
                         ["2560x1440@165.00", "2560x1440@144.00", "2560x1440@59.95"])

    def test_never_slower_than_recommended(self):
        """A TV recommending 3840x2160 at 60 Hz that lists 4096x2160 at 24 Hz stays as it is."""
        self.assertEqual(self.best(modes("3840x2160@60.00", "4096x2160@24.00", "4096x2160@30.00",
                                         "3840x2160@30.00", "1920x1080@60.00")), [])

    def test_the_recommended_one_when_none_is_marked(self):
        """Without a preferred flag, the first mode is the recommended one (Hyprland lists it first)."""
        self.assertEqual(self.best(modes("1920x1080@60.00", "2560x1440@60.00", preferred=-1)), ["2560x1440@60.00"])

    def test_nothing_to_choose_from(self):
        self.assertEqual(self.best("{}"), [])
        self.assertEqual(self.best("nil"), [])

    # ---- Applying ------------------------------------------------------------------

    def test_given_by_description_on_a_reload(self):
        """Monitors already there (a reload) get their best mode as the config loads, by
        description like Settings saves them, before Settings' own rules so those win."""
        rules = self.do("", before=f'screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@120.00")')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "5120x1440@240.00")])

    def test_a_reload_keeps_the_rate_that_took(self):
        """If 240 Hz didn't take and 120 Hz did, a reload doesn't try 240 Hz again."""
        rules = self.do("", before=f'screen("DP-3", "{G9_DESC}", {G9}, "5120x1440@119.98")')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "5120x1440@119.98")])

    def test_given_as_a_monitor_arrives_and_steps_down_when_a_rate_does_not_take(self):
        """At login (or plugged in): the fastest first; if the screen is still on its old mode a
        moment later (Hyprland fell back), the next rate; once one takes, nothing more."""
        rules = self.do(f'''
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@120.00")
            happen("monitor.added", g9)
            tick()                                   -- 240 Hz didn't take: still 3840x1080@120
            shows(g9, "5120x1440@119.98")
            tick()                                   -- 120 Hz did
            tick()
        ''')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "5120x1440@240.00"), (f"desc:{G9_DESC}", "5120x1440@119.98")])

    def test_once_at_login(self):
        """Hyprland starting and the monitor arriving both happen at login: one try, not two."""
        rules = self.do(f'''
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@120.00")
            happen("monitor.added", g9)
            happen("hyprland.start")
        ''')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "5120x1440@240.00")])

    def test_a_mode_chosen_in_settings_is_left_alone(self):
        """Settings → Displays saved one for this monitor: it isn't replaced as it arrives."""
        self.saved(f'hl.monitor({{ output = "desc:{G9_DESC}", mode = "3840x1080@60.00", position = "0x0" }})\n')
        rules = self.do(f'''
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@60.00")
            happen("monitor.added", g9)
        ''')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "3840x1080@60.00")])

    def test_your_own_rule_is_left_alone(self):
        """A rule of your own (by port name, in your monitors.lua) wins, and isn't replaced."""
        rules = self.do(f'''
            yours({{ output = "DP-3", mode = "2560x1440@239.97" }})
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "2560x1440@239.97")
            happen("monitor.added", g9)
        ''')
        self.assertEqual(rules, [("DP-3", "2560x1440@239.97")])

    def test_a_change_made_in_settings_while_running_is_left_alone(self):
        """Settings applies a mode (hyprctl eval) and the monitor is unplugged and plugged back."""
        rules = self.do(f'''
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@120.00")
            hl.monitor({{ output = "desc:{G9_DESC}", mode = "3840x1080@240.00" }})
            happen("monitor.added", g9)
        ''')
        self.assertEqual(rules, [(f"desc:{G9_DESC}", "3840x1080@240.00")])

    def test_a_monitor_that_is_off_is_left_alone(self):
        rules = self.do(f'''
            local g9 = screen("DP-3", "{G9_DESC}", {G9}, "3840x1080@120.00")
            g9.enabled = false
            happen("monitor.added", g9)
        ''')
        self.assertEqual(rules, [])

    def test_a_screen_that_does_not_say_what_it_is_is_left_alone(self):
        """A virtual machine's screen, or the tests' vkms, has no make, model or serial, and
        lists every size up to 4096x2160: given the largest, Hyprland drew an unseen 4K screen
        on the author's desktop and lagged. It keeps the mode it recommends."""
        vkms = modes("1024x768@60.00", "4096x2160@60.00", "2560x1600@59.99", "1920x1080@60.00")
        rules = self.do(f'''
            local v = screen("Virtual-1", "", {vkms}, "1024x768@60.00")
            happen("monitor.added", v)
        ''', before=f'screen("Virtual-2", "", {vkms}, "1024x768@60.00")')
        self.assertEqual(rules, [])

    # ---- The tests' screen (vkms) -------------------------------------------------------

    def test_the_tests_screen_is_off(self):
        """Slate's live tests need vkms loaded on this computer, and its screen was turned on and
        drawn on your own desktop, unseen: Hyprland stayed busy and the desktop lagged (Bug,
        2026-11-20). It's off as the config loads."""
        self.assertEqual(self.do("", before=self.vkms("Virtual-1")), [("Virtual-1", "off")])

    def test_left_on_in_the_tests_own_session(self):
        """The tests turn on the one they use themselves (tests/lib/session.py)."""
        self.assertEqual(self.do("", before=self.vkms("Virtual-1"), tests=True), [])

    def test_a_virtual_machines_screen_stays_on(self):
        """A virtual machine's screen is "Virtual-1" too, but isn't vkms's: left alone."""
        vm = modes("1280x800@60.00", "1920x1080@60.00")
        rules = self.do('local v = screen("Virtual-1", "", %s, "1280x800@60.00"); happen("monitor.added", v)' % vm)
        self.assertEqual(rules, [])

    def test_loaded_while_you_are_logged_in(self):
        """vkms loaded after login: its screen goes off as it arrives."""
        vk = modes("1024x768@60.00", "4096x2160@60.00")
        rules = self.do('local v = screen("Virtual-1", "", %s, "1024x768@60.00"); happen("monitor.added", v)' % vk,
                        before=self.vkms("Virtual-1"))
        self.assertEqual(rules, [("Virtual-1", "off"), ("Virtual-1", "off")])

    def test_your_own_rule_for_it_wins(self):
        """A rule of your own for it (to use it on purpose) is left as it is when it arrives."""
        vk = modes("1024x768@60.00")
        rules = self.do('yours({ output = "Virtual-1", mode = "1024x768@60.00" }); '
                        'local v = screen("Virtual-1", "", %s, "1024x768@60.00"); happen("monitor.added", v)' % vk,
                        before=self.vkms("Virtual-1"))
        self.assertEqual(rules, [("Virtual-1", "off"), ("Virtual-1", "1024x768@60.00")])


    def test_no_shell_is_started_without_the_virtual_screens_folder(self):
        """The tests' virtual screen is looked for at every config load and screen plugged in: on a
        real computer, with no vkms folder, that's no shell at all (it started one each time)."""
        case = ("SLATE_VKMS_DIRS = nil\n"
                "local opened = io.open\n"
                "io.open = function(path, mode) if tostring(path):match('vkms') then return nil end return opened(path, mode) end\n"
                "local started = 0\n"
                "io.popen = function() started = started + 1; return nil end\n"
                "slateTestScreens()\n"
                "print('STARTED\\t' .. started)\n")
        env = dict(self.h.env, STUB_CONFIG=MONITORS, STUB_BEFORE=self.vkms(), STUB_CASE=case)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        self.assertIn("STARTED\t0", out.splitlines())
