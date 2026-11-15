"""session/hypr/config/gestures.lua: the touchpad gestures Slate makes (Settings → Input →
Touchpad gestures), and what each does.

gestures.lua is run under plain Lua with a stand-in for Hyprland's `hl` that keeps gestures as
Hyprland does (one per fingers and direction: a second is refused, and taking away one that
isn't there fails, both in a message rather than a Lua error), then each case's Lua is run
against it. The stand-in prints one line per
thing done, tab separated:
  GESTURE <fingers> <direction> <action>   one was made ("function" for Slate's own)
  UNSET <fingers> <direction>              one was taken away
  EXEC <command>                           a command was started
  MOVE <window> <workspace>                a window was moved (follow = false)
  REFUSED <message>                        Hyprland refused a gesture (a clash Slate should have seen)
  ERR <message>                            something failed
"""
import os

import slate
from slate import Case, run

GESTURES = slate.path("shell", "session", "hypr", "config", "gestures.lua")
SLATE_CMD = "/s/bin/slate ipc call "

STUB = r"""
local function note(...) print(table.concat({ ... }, "\t")) end
local gestures = {}         -- "fingers direction" -> action
OPEN = {}                   -- Slate's overlays open, by layer name
WINDOWS = {}                -- { address, workspace = { id, name }, pinned }
ACTIVE = 1
local events = {}
hl = {
    gesture = function(g)
        local key = g.fingers .. " " .. g.direction
        if g.action == "unset" then
            if not gestures[key] then note("REFUSED", "Can't remove a non-existent gesture " .. key); return end
            gestures[key] = nil
            note("UNSET", g.fingers, g.direction)
            return
        end
        if gestures[key] then note("REFUSED", "Gesture will be overshadowed by a previous gesture " .. key); return end
        gestures[key] = g.action
        note("GESTURE", g.fingers, g.direction, type(g.action) == "function" and "function" or tostring(g.action))
    end,
    exec_cmd = function(cmd) note("EXEC", cmd) end,
    dsp = { window = { move = function(o) return { move = o } end } },
    dispatch = function(d)
        local o = d.move
        assert(o.follow == false, "moved with the window followed")
        local address = o.window:match("^address:(.*)$")
        for _, w in ipairs(WINDOWS) do
            if w.address == address then
                w.workspace = type(o.workspace) == "number" and { id = o.workspace, name = tostring(o.workspace) }
                              or { id = -99, name = o.workspace }
            end
        end
        note("MOVE", address, tostring(o.workspace))
    end,
    on = function(event, fn) events[event] = events[event] or {}; table.insert(events[event], fn) end,
    get_windows = function() return WINDOWS end,
    get_active_workspace = function() return { id = ACTIVE, name = tostring(ACTIVE) } end,
    get_workspace_windows = function(id)
        local out = {}
        for _, w in ipairs(WINDOWS) do if w.workspace.id == id then out[#out + 1] = w end end
        return out
    end,
}
-- What the rest of Slate's config gives it (hyprland.lua, binds.lua, windowrules.lua)
SLATE = "/s/bin/slate"
function slateOverlayOpen(name) return OPEN[name] == true end
function slateIsPinned(w) return w.pinned == true end
-- A gesture made, done (as Hyprland does at the end of one), or an event happening
function swipe(fingers, direction)
    local a = gestures[fingers .. " " .. direction]
    if type(a) ~= "function" then error("no gesture of Slate's for " .. fingers .. " " .. direction) end
    a()
end
function happen(event) for _, fn in ipairs(events[event] or {}) do fn() end end
function window(address, ws, pinned) WINDOWS[#WINDOWS + 1] = { address = address, workspace = { id = ws, name = tostring(ws) }, pinned = pinned } end

local ok, err = pcall(dofile, os.getenv("STUB_CONFIG"))
if not ok then note("ERR", tostring(err)) end
ok, err = pcall((loadstring or load)(os.getenv("STUB_CASE")))
if not ok then note("ERR", tostring(err)) end
"""


class GesturesLua(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.lua = slate.need("lua", "luajit", "lua5.1")
        self.stub = os.path.join(self.h.dir, "stub.lua")
        with open(self.stub, "w") as f:
            f.write(STUB)

    def do(self, case):
        """Run case (Lua) after loading gestures.lua: what was done, as lists of fields."""
        env = dict(self.h.env, STUB_CONFIG=GESTURES, STUB_CASE=case)
        code, out = run([self.lua, self.stub], env=env)
        self.assertEqual(code, 0, out)
        lines = [line.split("\t") for line in out.splitlines()]
        self.assertEqual([l for l in lines if l[0] in ("ERR", "REFUSED")], [])
        return lines

    def commands(self, lines):
        return [l[1].removeprefix(SLATE_CMD) for l in lines if l[0] == "EXEC"]

    def test_made_with_the_fingers_chosen(self):
        lines = self.do('setGestures(true, 3, "desktop")')
        self.assertEqual(lines, [["GESTURE", "3", "horizontal", "workspace"], ["GESTURE", "3", "up", "function"],
                                 ["GESTURE", "3", "down", "function"], ["GESTURE", "3", "pinchin", "function"],
                                 ["GESTURE", "3", "pinchout", "function"]])
        lines = self.do('setGestures(true, 4, "desktop")')
        self.assertEqual({tuple(l[1:3]) for l in lines}, {("4", d) for d in ("horizontal", "up", "down", "pinchin", "pinchout")})

    def test_changing_fingers_or_turning_off_takes_slates_away(self):
        lines = self.do('setGestures(true, 3, "desktop"); print("--"); setGestures(true, 4, "desktop"); '
                        'print("--"); setGestures(false, 4, "desktop")')
        first, second, third = "\n".join("\t".join(l) for l in lines).split("--")
        self.assertEqual(second.count("UNSET\t3"), 5)
        self.assertEqual(second.count("GESTURE\t4"), 5)
        self.assertEqual(third.count("UNSET\t4"), 5)
        self.assertNotIn("GESTURE", third)

    def test_made_once_for_the_same_settings(self):
        """Slate sends its settings to Hyprland whenever any of them changes (a slider being
        dragged): the gestures are only made again when theirs change, never in the middle of one."""
        lines = self.do('setGestures(true, 3, "desktop"); print("--"); setGestures(true, 3, "launcher"); '
                        'setGestures(true, 3, "desktop")')
        after = lines[lines.index(["--"]) + 1:]
        self.assertEqual(after, [])

    def test_yours_stay(self):
        """A gesture of your own on the same fingers and direction (your hyprland.lua, made
        first) is kept: Slate's is left out, and turning Slate's off leaves yours alone."""
        lines = self.do('hl.gesture({ fingers = 3, direction = "up", action = "fullscreen" }); print("--"); '
                        'setGestures(true, 3, "desktop"); print("--"); setGestures(false, 3, "desktop")')
        text = "\n".join("\t".join(l) for l in lines)
        _, made, off = text.split("--")
        self.assertNotIn("\tup\t", made)
        self.assertEqual(made.count("GESTURE"), 4)
        self.assertNotIn("\tup", off)
        self.assertEqual(off.count("UNSET"), 4)

    def test_yours_in_a_wider_direction_stay_too(self):
        """Yours sideways (left or right) or up and down together (vertical) would hide
        Slate's on those fingers: Slate leaves those out, and the rest are made."""
        for yours, left_out in (("left", {"horizontal"}), ("right", {"horizontal"}), ("vertical", {"up", "down"}),
                                ("swipe", {"horizontal", "up", "down"}), ("pinch", {"pinchin", "pinchout"}),
                                ("zoomin", {"pinchin"})):
            with self.subTest(yours=yours):
                lines = self.do(f'hl.gesture({{ fingers = 4, direction = "{yours}", action = "close" }}); '
                                'setGestures(true, 4, "desktop")')
                made = {l[2] for l in lines if l[0] == "GESTURE" and l[3] != "close"}
                self.assertEqual(made, {"horizontal", "up", "down", "pinchin", "pinchout"} - left_out)
        lines = self.do('hl.gesture({ fingers = 3, direction = "left", action = "close" }); setGestures(true, 4, "desktop")')
        self.assertEqual(len([l for l in lines if l[0] == "GESTURE" and l[1] == "4"]), 5, "other fingers aren't affected")
        lines = self.do('hl.gesture({ fingers = 4, direction = "left", mods = "SUPER", action = "close" }); '
                        'setGestures(true, 4, "desktop")')
        self.assertEqual(len([l for l in lines if l[0] == "GESTURE" and l[1] == "4"]), 6, "one with keys held doesn't clash")

    def test_up_opens_the_overview(self):
        self.assertEqual(self.commands(self.do('setGestures(true, 3, "desktop"); swipe(3, "up")')), ["overview open"])
        self.assertEqual(self.commands(self.do('OPEN["slate-overview"] = true; setGestures(true, 3, "desktop"); swipe(3, "up")')), [])
        self.assertEqual(self.commands(self.do('OPEN["slate-launcher"] = true; setGestures(true, 3, "desktop"); swipe(3, "up")')),
                         ["launcher close"])

    def test_down_closes_what_is_open_first(self):
        for open_, closed in (("slate-overview", "overview close"), ("slate-launcher", "launcher close")):
            for down in ("desktop", "launcher"):
                with self.subTest(open=open_, down=down):
                    lines = self.do(f'window("0x1", 1); OPEN["{open_}"] = true; setGestures(true, 3, "{down}"); swipe(3, "down")')
                    self.assertEqual(self.commands(lines), [closed])
                    self.assertFalse([l for l in lines if l[0] == "MOVE"])

    def test_down_opens_the_launcher_when_chosen(self):
        self.assertEqual(self.commands(self.do('setGestures(true, 4, "launcher"); swipe(4, "down")')), ["launcher open"])

    def test_pinch(self):
        self.assertEqual(self.commands(self.do('setGestures(true, 3, "desktop"); swipe(3, "pinchin")')), ["launcher open"])
        self.assertEqual(self.commands(self.do('OPEN["slate-launcher"] = true; setGestures(true, 3, "desktop"); swipe(3, "pinchin")')), [])
        self.assertEqual(self.commands(self.do('OPEN["slate-launcher"] = true; setGestures(true, 3, "desktop"); swipe(3, "pinchout")')),
                         ["launcher close"])
        self.assertEqual(self.commands(self.do('setGestures(true, 3, "desktop"); swipe(3, "pinchout")')), [])

    def test_show_the_desktop_and_back(self):
        """Down moves this workspace's windows (not Slate's pinned ones, nor another
        workspace's) aside; up, or down again, brings them back where they were, in order."""
        setup = ('window("0xa", 1); window("0xb", 1); window("0xnova", 1, true); window("0xc", 2); '
                 'setGestures(true, 3, "desktop"); ')
        for back in ('swipe(3, "up")', 'swipe(3, "down")', 'happen("workspace.active")',
                     'happen("window.open")', 'happen("workspace.special_active")'):
            with self.subTest(back=back):
                lines = self.do(setup + 'swipe(3, "down"); assert(desktopShowing()); print("--"); ' + back
                                + '; assert(not desktopShowing())')
                moves = [l for l in lines if l[0] in ("MOVE", "--")]
                self.assertEqual(moves, [["MOVE", "0xa", "special:slate-desktop"], ["MOVE", "0xb", "special:slate-desktop"],
                                         ["--"], ["MOVE", "0xa", "1"], ["MOVE", "0xb", "1"]])
                self.assertEqual(self.commands(lines), [])

    def test_nothing_to_hide(self):
        lines = self.do('window("0xnova", 1, true); setGestures(true, 3, "desktop"); swipe(3, "down"); '
                        'assert(not desktopShowing())')
        self.assertFalse([l for l in lines if l[0] == "MOVE"])

    def test_a_reload_brings_hidden_windows_back(self):
        """A reload forgets which windows it hid: any still on the hidden workspace come back to
        the one you're on, rather than being lost there."""
        lines = self.do('window("0xa", 1); WINDOWS[1].workspace = { id = -99, name = "special:slate-desktop" }; '
                        'ACTIVE = 2; dofile(os.getenv("STUB_CONFIG"))')
        self.assertIn(["MOVE", "0xa", "2"], lines)
