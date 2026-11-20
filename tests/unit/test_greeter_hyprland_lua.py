"""greeter/hyprland.lua: the login screen starts each monitor as your desktop shows it.

A monitor changing mode goes black for a few seconds. The login screen used the monitor's own
recommended mode (an Odyssey G9 says 3840x1080 at 120 Hz), and your desktop changed it back to
the one you use, so every login went black twice, and a face could be recognized while it was
black, the login screen never seen. slate-greeter-sync writes your displays to the login screen's
folder (tests/unit/test_greeter_sync.py); this reads them. It's data from your account, so a
line that isn't right is skipped rather than handed to Hyprland.

The file is run under plain Lua with a stand-in for Hyprland's `hl`, which prints a line per
monitor rule: MONITOR <output> <mode> <scale> <transform> <position> <cm> <bitdepth> <supports_hdr>
"""
import os

import slate
from slate import Case, run

CONFIG = slate.path("shell", "greeter", "hyprland.lua")
G9 = "Samsung Electric Company Odyssey G95SC H1AK500000"

STUB = r"""
local function note(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; print(table.concat(t, "\t")) end
MONITORS = {}
local events, timers = {}, {}
hl = {
    config = function() end,
    exec_cmd = function(c) note("EXEC", c) end,
    monitor = function(s) note("MONITOR", s.output, s.mode, s.scale, s.transform, s.position, s.cm, s.bitdepth, s.supports_hdr) end,
    get_monitors = function() return MONITORS end,
    on = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end,
    timer = function(fn, opts) table.insert(timers, fn); return {} end,
}
SLATE_GREETER_DISPLAYS = os.getenv("STUB_DISPLAYS")
function happen(event) for _, fn in ipairs(events[event] or {}) do fn() end end
function tick() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end end
local ok, err = pcall(dofile, os.getenv("STUB_CONFIG"))
if not ok then note("ERR", tostring(err)) end
ok, err = pcall((loadstring or load)(os.getenv("STUB_CASE") or ""))
if not ok then note("ERR", tostring(err)) end
"""


class GreeterHyprlandLua(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "luajit", "lua5.1")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)
        self.file = os.path.join(self.h.dir, "displays")

    def do(self, lines, case=""):
        """Load it with these lines as the displays file (None: no file), then case; the
        monitor rules made, as lists of fields."""
        if lines is None:
            if os.path.exists(self.file):
                os.remove(self.file)
        else:
            with open(self.file, "w") as f:
                f.write("".join(l + "\n" for l in lines))
        env = dict(self.h.env, STUB_CONFIG=CONFIG, STUB_DISPLAYS=self.file, STUB_CASE=case)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        rows = [l.split("\t") for l in out.splitlines()]
        self.assertEqual([r for r in rows if r[0] == "ERR"], [])
        return [r[1:] for r in rows if r[0] == "MONITOR"]

    def test_your_monitor_starts_as_your_desktop_has_it(self):
        self.assertEqual(self.do([f"{G9}\t5120x1440@240.00\t1.250000\t0\t0\t0\tauto"]),
                         [[f"desc:{G9}", "5120x1440@240.00", "1.25", "0", "0x0", "auto", "nil", "0"]])

    def test_hdr_as_settings_writes_it(self):
        rules = self.do([f"A\t1920x1080@60.00\t1\t0\t0\t0\ton\t1.20\t1.00",
                         f"B\t1920x1080@60.00\t1\t1\t1920\t-100\toff",
                         f"C\t1920x1080@60.00\t1\t0\t0\t0\t"])
        self.assertEqual([r[0] for r in rules], ["desc:A", "desc:B", "desc:C"])
        self.assertEqual(rules[0][5:], ["hdr", "10", "0"])
        self.assertEqual(rules[1][3:], ["1", "1920x-100", "auto", "8", "-1"])
        self.assertEqual(rules[2][5:], ["nil", "nil", "nil"], "HDR left as Hyprland has it")

    def test_nothing_without_the_file(self):
        """Not synced yet (or a new install): Hyprland's own choice, as before."""
        self.assertEqual(self.do(None), [])

    def test_a_line_that_isnt_right_is_skipped(self):
        bad = [
            "",
            "\t1920x1080@60\t1\t0\t0\t0\t",                       # no description
            "A\tpreferred\t1\t0\t0\t0\t",                         # not a mode
            "A\t1920x1080@60; rm -rf\t1\t0\t0\t0\t",
            "A\t1920x1080@60\tbig\t0\t0\t0\t",                    # scale
            "A\t1920x1080@60\t1\t9\t0\t0\t",                      # rotation
            "A\t1920x1080@60\t1\t1.5\t0\t0\t",
            "A\t1920x1080@60\t1\t0\tleft\t0\t",                   # position
            "A\t1920x1080@60\t1\t0\t0\t0\tmaybe",                 # HDR
            "A\t1920x1080@60\t1\t0\t0",                           # too short
        ]
        self.assertEqual(self.do(bad + ["Good\t1920x1080@60\t1\t0\t0\t0\t"]),
                         [["desc:Good", "1920x1080@60", "1", "0", "0x0", "nil", "nil", "nil"]])

    def test_a_mode_that_doesnt_take_steps_down_a_rate(self):
        """Hyprland fell back (the cable can't carry 240 Hz now): the next slower rate at that
        size, then it stops once one takes."""
        case = f"""
        MONITORS = {{ {{ name = "DP-3", description = "{G9}", mode = {{ width = 3840, height = 1080, refresh_rate = 120 }},
            available_modes = {{ {{ width = 3840, height = 1080, refresh_rate = 120 }}, {{ width = 5120, height = 1440, refresh_rate = 240 }},
                                 {{ width = 5120, height = 1440, refresh_rate = 119.98 }}, {{ width = 5120, height = 1440, refresh_rate = 60 }} }} }} }}
        happen("hyprland.start")
        tick()
        MONITORS[1].mode = {{ width = 5120, height = 1440, refresh_rate = 119.98 }}
        tick()
        tick()
        """
        rules = self.do([f"{G9}\t5120x1440@240.00\t1.25\t0\t0\t0\tauto"], case)
        self.assertEqual([r[1] for r in rules], ["5120x1440@240.00", "5120x1440@119.98"])

    def test_a_mode_that_takes_is_left(self):
        case = f"""
        MONITORS = {{ {{ name = "DP-3", description = "{G9}", mode = {{ width = 5120, height = 1440, refresh_rate = 239.99899 }},
            available_modes = {{ {{ width = 5120, height = 1440, refresh_rate = 119.98 }} }} }} }}
        happen("hyprland.start"); tick(); tick()
        """
        self.assertEqual(len(self.do([f"{G9}\t5120x1440@240.00\t1.25\t0\t0\t0\tauto"], case)), 1)
