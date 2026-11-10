"""scripts/spaces.py: snapshots of the workspaces, saved spaces, and the apps kept for a
restart, against fixture `hyprctl -j` replies. Restoring runs against a fake hyprctl that
opens a window for each app started, so no real app or Hyprland is ever reached."""
import json
import os
import subprocess
import sys
import time

import slate
from slate import Case, run
from stubs import Stubs, fixture_text

SCRIPT = slate.path("shell", "scripts", "spaces.py")

# The desktop entries the fixture windows are matched to
ENTRIES = {
    "com.example.Editor.desktop": "[Desktop Entry]\nName=Editor\nExec=example-editor --new-window %U\n",
    # Matched by StartupWMClass, not by its name
    "com.example.Terminal.desktop": "[Desktop Entry]\nName=Terminal\nExec=example-term\nStartupWMClass=example-term\n",
    # Indented, as some generated files are; the action's Exec must not be taken
    "example-viewer.desktop": ("  [Desktop Entry]\n  Name = Viewer\n  Exec = example-viewer %f\n"
                               "  Terminal = true\n  Path = /opt/example\n\n"
                               "[Desktop Action new]\nExec=example-viewer --other\n"),
}

EDITOR = {"desktopId": "com.example.Editor", "command": "example-editor --new-window", "terminal": False,
          "cwd": "", "name": "Editor", "class": "com.example.Editor", "title": "main.c - Editor",
          "x": 0.0, "y": 0.0, "w": 0.5, "h": 1.0, "floating": False, "fullscreen": 0}
TERM = {"desktopId": "com.example.Terminal", "command": "example-term", "terminal": False,
        "cwd": "", "name": "Terminal", "class": "example-term", "title": "~",
        "x": 0.5, "y": 0.0, "w": 0.5, "h": 1.0, "floating": False, "fullscreen": 0}
# No desktop entry: started again with the process's own command line
NOTES = {"desktopId": "", "command": "sleep 3600", "terminal": False, "cwd": "", "name": "",
         "class": "scratch-notes", "title": "Notes",
         "x": 0.25, "y": 0.25, "w": 0.5, "h": 0.5, "floating": True, "fullscreen": 0}
VIEWER = {"desktopId": "example-viewer", "command": "example-viewer", "terminal": True,
          "cwd": "/opt/example", "name": "Viewer", "class": "Example-Viewer", "title": "photo.png",
          "x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0, "floating": False, "fullscreen": 1}


def live(win, address, rounding):
    """A window as the snapshot shows it: with what the previews need."""
    return dict(win, address=address, rounding=rounding)


class SpacesBase(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        # Only the scratch applications folder: none of this machine's apps
        self.s.env["XDG_DATA_DIRS"] = os.path.join(self.h.dir, "no-system-data")
        apps = self.h(".local", "share", "applications")
        os.makedirs(apps)
        for name, text in ENTRIES.items():
            with open(os.path.join(apps, name), "w") as f:
                f.write(text)
        self.store = self.h(".local", "share", "slate", "spaces.json")
        self.session = self.h(".local", "state", "slate", "session.json")

    def hyprland(self, clients=None):
        """Stub hyprctl with the fixture replies (the notes window gets a real process's pid,
        for its command line)."""
        if clients is None:
            notes = subprocess.Popen(["sleep", "3600"])
            self.addCleanup(notes.wait)
            self.addCleanup(notes.kill)
            clients = json.loads(fixture_text("spaces", "clients.json"))
            for c in clients:
                if c["pid"] == 0:
                    c["pid"] = notes.pid
        self.s.add("hyprctl", by_args={
            "clients": json.dumps(clients),
            "workspaces": fixture_text("spaces", "workspaces.json"),
            "monitors": fixture_text("spaces", "monitors.json"),
            "getoption": fixture_text("spaces", "getoption.json"),
        })

    def spaces(self, *args, code=0):
        c, out = run(["python3", SCRIPT, *args], env=self.s.env, timeout=30)
        self.assertEqual(c, code, out)
        return out

    def read(self, p):
        with open(p) as f:
            return json.load(f)

    def write(self, p, data):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(data if isinstance(data, str) else json.dumps(data))


class Snapshot(SpacesBase):
    def test_snapshot(self):
        self.hyprland()
        got = json.loads(self.spaces("snapshot"))
        want = [
            # Usable area 2560x1400 (the bar takes 40 at the top); oldest window first
            {"id": 1, "monitor": "DP-1", "aspect": 1.8286, "width": 2560.0,
             "windows": [live(EDITOR, "0xa1", 8), live(TERM, "0xa2", 8)]},
            # Slate's own window is left out
            {"id": 2, "monitor": "DP-1", "aspect": 1.8286, "width": 2560.0,
             "windows": [live(NOTES, "0xa3", 8)]},
            # Scaled 1.5 and turned: 720x1280. Maximised, so square; the window with no
            # command to start it again is left out
            {"id": 3, "monitor": "HDMI-A-1", "aspect": 0.5625, "width": 720.0,
             "windows": [live(VIEWER, "0xa4", 0)]},
        ]
        self.assertEqual(got, want)

    def test_only_hyprctl_reads(self):
        """A snapshot only asks; it never changes anything in Hyprland."""
        self.hyprland()
        self.spaces("snapshot")
        calls = self.s.calls("hyprctl")
        self.assertEqual(sorted(c[1] for c in calls), ["clients", "getoption", "monitors", "workspaces"])
        self.assertTrue(all(c[0] == "-j" for c in calls), calls)

    def test_lone_tile_is_square(self):
        clients = [c for c in json.loads(fixture_text("spaces", "clients.json")) if c["address"] == "0xa1"]
        self.hyprland(clients)
        got = json.loads(self.spaces("snapshot"))
        self.assertEqual([w["rounding"] for w in got[0]["windows"]], [0])

    def test_no_hyprland(self):
        """hyprctl failing (Hyprland not running) gives an empty list, not an error."""
        self.assertEqual(json.loads(self.spaces("snapshot")), [])

    def test_hyprctl_nonsense(self):
        self.s.add("hyprctl", stdout="HYPRLAND_INSTANCE_SIGNATURE not set!\n")
        self.assertEqual(json.loads(self.spaces("snapshot")), [])


class Store(SpacesBase):
    def test_save(self):
        self.hyprland()
        before = int(time.time())
        self.spaces("save", " Work ", "#3366ff", "edba", "1,3,9")
        data = self.read(self.store)
        self.assertEqual(len(data["spaces"]), 1)
        sp = data["spaces"][0]
        self.assertRegex(sp.pop("id"), r"^[0-9a-f]{12}$")
        self.assertGreaterEqual(sp.pop("saved"), before)
        # Workspace 9 isn't there; addresses and rounding aren't saved
        self.assertEqual(sp, {"name": "Work", "colour": "#3366ff", "icon": "edba", "workspaces": [
            {"monitor": "DP-1", "aspect": 1.8286, "windows": [EDITOR, TERM]},
            {"monitor": "HDMI-A-1", "aspect": 0.5625, "windows": [VIEWER]},
        ]})

    def test_same_name_replaces(self):
        """Saving under a name already used (any case) replaces that space, keeping its id."""
        self.hyprland()
        self.write(self.store, {"spaces": [
            {"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#000000", "icon": "e000", "saved": 1, "workspaces": []},
            {"id": "bbbbbbbbbbbb", "name": "Play", "colour": "#ffffff", "icon": "e001", "saved": 1, "workspaces": []},
        ]})
        self.spaces("save", "work", "#3366ff", "edba", "2")
        spaces = self.read(self.store)["spaces"]
        self.assertEqual([(s["id"], s["name"], s["colour"]) for s in spaces],
                         [("aaaaaaaaaaaa", "work", "#3366ff"), ("bbbbbbbbbbbb", "Play", "#ffffff")])
        self.assertEqual(spaces[0]["workspaces"], [{"monitor": "DP-1", "aspect": 1.8286, "windows": [NOTES]}])

    def test_nothing_to_save(self):
        self.hyprland()
        for args in (["Work", "#3366ff", "edba", "4"],       # empty workspace
                     ["Work", "#3366ff", "edba", "x,,-98"],  # nothing usable
                     ["  ", "#3366ff", "edba", "1"]):        # no name
            with self.subTest(args=args):
                out = self.spaces("save", *args, code=1)
                self.assertIn("nothing to save", out)
                self.assertFalse(os.path.exists(self.store))

    def test_bad_store_starts_afresh(self):
        self.hyprland()
        for bad in ("{not json", "[1, 2]", '{"spaces": "no"}'):
            with self.subTest(bad=bad):
                self.write(self.store, bad)
                self.spaces("save", "Work", "#3366ff", "edba", "1")
                self.assertEqual([s["name"] for s in self.read(self.store)["spaces"]], ["Work"])

    def test_delete(self):
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work"}, {"id": "bbbbbbbbbbbb", "name": "Play"}]})
        self.spaces("delete", "aaaaaaaaaaaa")
        self.assertEqual(self.read(self.store), {"spaces": [{"id": "bbbbbbbbbbbb", "name": "Play"}]})
        self.spaces("delete", "nope")
        self.assertEqual(self.read(self.store), {"spaces": [{"id": "bbbbbbbbbbbb", "name": "Play"}]})

    def test_delete_with_no_store(self):
        self.spaces("delete", "aaaaaaaaaaaa")
        self.assertEqual(self.read(self.store), {"spaces": []})

    def test_usage(self):
        for args in ([], ["save", "Work"], ["delete"], ["frobnicate"]):
            with self.subTest(args=args):
                out = self.spaces(*args, code=1)
                self.assertIn("spaces.py snapshot", out)
        self.assertEqual(self.s.calls("hyprctl"), [])


class Session(SpacesBase):
    def boot(self):
        with open("/proc/sys/kernel/random/boot_id") as f:
            return f.read().strip()

    def test_session_save(self):
        self.hyprland()
        before = int(time.time())
        self.spaces("session-save")
        data = self.read(self.session)
        self.assertGreaterEqual(data.pop("saved"), before)
        self.assertEqual(data, {
            "boot": self.boot(),
            "workspaces": [
                {"id": 1, "monitor": "DP-1", "aspect": 1.8286, "windows": [EDITOR, TERM]},
                {"id": 2, "monitor": "DP-1", "aspect": 1.8286, "windows": [NOTES]},
                {"id": 3, "monitor": "HDMI-A-1", "aspect": 0.5625, "windows": [VIEWER]},
            ],
            "active": [{"monitor": "DP-1", "workspace": 1}, {"monitor": "HDMI-A-1", "workspace": 3}],
            "focused": "DP-1",
        })
        # Saved this boot: nothing to reopen until the restart
        self.spaces("session-pending", code=1)

    def test_pending(self):
        now = int(time.time())
        ws = [{"id": 1, "monitor": "DP-1", "aspect": 1.8, "windows": [EDITOR]}]
        cases = [
            ("another boot", {"boot": "another-boot", "saved": now, "workspaces": ws}, 0, True),
            ("this boot", {"boot": self.boot(), "saved": now, "workspaces": ws}, 1, True),
            ("no apps", {"boot": "another-boot", "saved": now, "workspaces": []}, 1, True),
            ("not an object", [1, 2], 1, True),
            ("bad json", "{oops", 1, True),
            # Kept over a day ago: forgotten
            ("too old", {"boot": "another-boot", "saved": now - 2 * 86400, "workspaces": ws}, 1, False),
        ]
        for name, data, code, kept in cases:
            with self.subTest(name):
                self.write(self.session, data)
                self.spaces("session-pending", code=code)
                self.assertEqual(os.path.exists(self.session), kept)

    def test_pending_with_none(self):
        self.spaces("session-pending", code=1)

    def test_forget(self):
        self.write(self.session, {"boot": "x"})
        self.spaces("session-forget")
        self.assertFalse(os.path.exists(self.session))
        self.spaces("session-forget")       # and again, with nothing there

    def test_restore_without_pending_does_nothing(self):
        self.write(self.session, {"boot": self.boot(), "saved": int(time.time()), "workspaces": [{"id": 1}]})
        self.spaces("session-restore", "com.example.Editor")
        self.assertEqual(self.s.calls("hyprctl"), [])
        self.assertTrue(os.path.exists(self.session))


# A stand-in for Hyprland: answers -j queries from a state file, and opens a window when
# told to start an app (the app being known by a word of its command), so a restore can
# run all the way through. Every call is logged.
FAKE_HYPRCTL = r'''#!{python}
import json, re, sys
state_path, log = {state!r}, {log!r}
with open(log, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
st = json.load(open(state_path))
args = sys.argv[1:]
if args[:1] == ["-j"]:
    print(json.dumps(st.get(args[1], [])))
    sys.exit(0)
code = args[1] if args[:1] == ["dispatch"] else ""
m = re.search(r"hl\.exec_cmd\((.*), \{{ workspace = \[=\[(\d+)\]=\](, float = true)? \}}\)", code)
cls = next((c for word, c in st["apps"].items() if word in m.group(1)), None) if m else None
if cls:          # (an app it doesn't know opens no window, like one that fails to start)
    n = len(st["clients"]) + 1
    w, h = st["newsize"]
    st["clients"].append({{"address": "0xb%d" % n, "mapped": True, "hidden": False, "class": cls,
                          "initialClass": cls, "workspace": {{"id": int(m.group(2))}}, "at": [0, 0],
                          "size": [w, h], "floating": bool(m.group(3)), "stableId": 100 + n, "pid": 1}})
m = re.search(r"window\.move\(\{{ x = (-?\d+), y = (-?\d+), relative = false, window = \[=\[address:(\w+)\]=\]", code)
if m:
    for c in st["clients"]:
        if c["address"] == m.group(3):
            c["at"] = [int(m.group(1)), int(m.group(2))]
json.dump(st, open(state_path, "w"))
print("ok")
'''


class FakeHyprland:
    """For tests that restore: a hyprctl that keeps windows and workspaces, and notes what it's asked."""
    def fake_hyprland(self):
        state = os.path.join(self.h.dir, "hypr-state.json")
        self.fake_log = os.path.join(self.h.dir, "hyprctl.log")
        with open(state, "w") as f:
            json.dump({
                "monitors": [{"name": "DP-1", "width": 1920, "height": 1080, "x": 0, "y": 0, "scale": 1,
                              "transform": 0, "reserved": [0, 0, 0, 0], "focused": True,
                              "activeWorkspace": {"id": 2, "name": "2"}}],
                "workspaces": [{"id": 1, "monitor": "DP-1", "windows": 1}, {"id": 2, "monitor": "DP-1", "windows": 0}],
                "clients": [{"address": "0xa0", "mapped": True, "class": "other", "workspace": {"id": 1},
                             "at": [0, 0], "size": [1920, 1080], "stableId": 1, "pid": 1}],
                "apps": {"example-editor": "com.example.Editor", "example-term": "example-term",
                         "example-viewer": "Example-Viewer"},
                # Each new window is half the screen wide: the split's ratio "worked" first time
                "newsize": [960, 1080],
            }, f)
        p = os.path.join(self.s.dir, "hyprctl")
        with open(p, "w") as f:
            f.write(FAKE_HYPRCTL.format(python=sys.executable, state=state, log=self.fake_log))
        os.chmod(p, 0o755)

    def dispatches(self):
        with open(self.fake_log) as f:
            calls = [json.loads(l) for l in f]
        return [c[1] for c in calls if c[0] == "dispatch"]


class Restore(FakeHyprland, SpacesBase):
    def test_restore(self):
        """Two tiles side by side, then a floating terminal app: started on the first free
        workspace, split at the saved place, and the floating one moved where it was."""
        self.fake_hyprland()
        viewer = dict(VIEWER, floating=True, fullscreen=0, x=0.25, y=0.25, w=0.5, h=0.5)
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#3366ff", "icon": "edba",
                                            "saved": 1, "workspaces": [{"monitor": "DP-1", "aspect": 1.7778,
                                                                        "windows": [EDITOR, TERM, viewer]}]}]})
        self.spaces("restore", "work")
        fn = "function() hl.dispatch(%s) end"
        self.assertEqual(self.dispatches(), [
            fn % "hl.dsp.focus({ workspace = 2 })",
            "function() hl.exec_cmd([=[example-editor --new-window]=], { workspace = [=[2]=] }) end",
            fn % "hl.dsp.focus({ window = [=[address:0xb2]=] })",
            fn % "hl.dsp.layout([=[preselect r]=])",
            "function() hl.exec_cmd([=[example-term]=], { workspace = [=[2]=] }) end",
            fn % "hl.dsp.focus({ window = [=[address:0xb2]=] })",
            fn % "hl.dsp.layout([=[splitratio 1.000 exact]=])",
            "function() hl.exec_cmd((TERMINAL or 'kitty') .. ' -e ' .. [=[cd /opt/example && example-viewer]=],"
            " { workspace = [=[2]=], float = true }) end",
            fn % "hl.dsp.window.resize({ x = 960, y = 540, relative = false, window = [=[address:0xb4]=] })",
            fn % "hl.dsp.window.move({ x = 480, y = 270, relative = false, window = [=[address:0xb4]=] })",
        ])
        # Which windows came from the space, for their badges
        owners = self.read(os.path.join(self.h.runtime, "slate", "space-windows.json"))
        self.assertEqual(owners, {"instance": "", "windows": {"102": "aaaaaaaaaaaa", "103": "aaaaaaaaaaaa",
                                                              "104": "aaaaaaaaaaaa"}})
        # Everything opened: no notification
        self.assertEqual(self.s.calls("notify-send"), [])

    def test_some_apps_dont_open(self):
        """An app that never opens a window: the rest of the space still opens, and one
        notification names the one that didn't. (The wait for it is cut short for the test.)"""
        self.fake_hyprland()
        self.s.env["SLATE_SPACES_WINDOW_TIMEOUT"] = "1"
        ghost = dict(TERM, desktopId="", command="ghost-app --start", name="Ghost", **{"class": "ghost-app"})
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#3366ff", "icon": "edba",
                                            "saved": 1, "workspaces": [{"monitor": "DP-1", "aspect": 1.7778,
                                                                        "windows": [EDITOR, ghost]}]}]})
        self.spaces("restore", "work")
        started = [d for d in self.dispatches() if "exec_cmd" in d]
        self.assertEqual(len(started), 2, "both apps were started")
        owners = self.read(os.path.join(self.h.runtime, "slate", "space-windows.json"))
        self.assertEqual(list(owners["windows"].values()), ["aaaaaaaaaaaa"], "only the editor's window is the space's")
        # (spaces.py doesn't wait for notify-send: give it a moment to be logged)
        for _ in range(30):
            notes = self.s.calls("notify-send")
            if notes:
                break
            time.sleep(0.1)
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0][-2], "Some apps in Work didn't open")
        self.assertTrue(notes[0][-1].startswith("Ghost didn't open a window"), notes[0][-1])

    def test_restore_unknown(self):
        self.fake_hyprland()
        out = self.spaces("restore", "Nope", code=1)
        self.assertIn("no space called Nope", out)
        self.assertEqual(self.dispatches() if os.path.exists(self.fake_log) else [], [])


class WorkspaceModes(FakeHyprland, SpacesBase):
    """A workspace with a window mode of its own (the menu bar's workspace indicator) keeps it
    in a space, and gets it back, through Slate, before its apps reopen."""

    def setUp(self):
        super().setUp()
        self.s.env["HYPRLAND_INSTANCE_SIGNATURE"] = "test"
        self.write(os.path.join(self.h.runtime, "slate", "workspace-modes-test.json"), {"1": "floating"})

    def test_saved_with_the_space(self):
        self.hyprland()
        self.spaces("save", "Work", "#3366ff", "edba", "1,3")
        ws = self.read(self.store)["spaces"][0]["workspaces"]
        self.assertEqual(ws[0].get("mode"), "floating")
        self.assertNotIn("mode", ws[1], "a workspace following the default saves no mode")

    def test_in_the_snapshot_and_session(self):
        self.hyprland()
        got = json.loads(self.spaces("snapshot"))
        self.assertEqual([w.get("mode") for w in got], ["floating", None, None])
        self.spaces("session-save")
        self.assertEqual([w.get("mode") for w in self.read(self.session)["workspaces"]], ["floating", None, None])

    def test_set_again_on_restore(self):
        self.fake_hyprland()
        self.s.add("slate")
        self.s.env["SLATE_COMMAND"] = os.path.join(self.s.dir, "slate")
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#3366ff", "icon": "edba",
                                            "saved": 1, "workspaces": [{"monitor": "DP-1", "aspect": 1.7778, "mode": "scrolling",
                                                                        "windows": [EDITOR]}]}]})
        self.spaces("restore", "work")
        self.assertIn(["ipc", "call", "workspacemode", "set", "2", "scrolling"], self.s.calls("slate"))


class WorkspaceNames(FakeHyprland, SpacesBase):
    """A workspace you've named (the pencil on the window mode panel) keeps its name in a space
    and in the session, and gets it back, through Slate, on the workspace its apps reopen on."""

    def setUp(self):
        super().setUp()
        self.s.env["HYPRLAND_INSTANCE_SIGNATURE"] = "test"
        self.write(os.path.join(self.h.runtime, "slate", "workspace-names-test.json"), {"3": "Coding", "9": "Gone", "1": "  "})

    def test_saved_with_the_space(self):
        self.hyprland()
        self.spaces("save", "Work", "#3366ff", "edba", "1,3")
        space = self.read(self.store)["spaces"][0]
        self.assertEqual(space["name"], "Work", "the space's own name is another thing")
        ws = space["workspaces"]
        self.assertNotIn("name", ws[0], "an unnamed workspace saves no name")
        self.assertEqual(ws[1].get("name"), "Coding")

    def test_in_the_snapshot_and_session(self):
        self.hyprland()
        got = json.loads(self.spaces("snapshot"))
        self.assertEqual([w.get("name") for w in got], [None, None, "Coding"])
        self.spaces("session-save")
        self.assertEqual([w.get("name") for w in self.read(self.session)["workspaces"]], [None, None, "Coding"])

    def test_set_again_on_restore(self):
        """On the workspace the space opens on (a new one), not the number it was saved from."""
        self.fake_hyprland()
        self.s.add("slate")
        self.s.env["SLATE_COMMAND"] = os.path.join(self.s.dir, "slate")
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#3366ff", "icon": "edba",
                                            "saved": 1, "workspaces": [{"monitor": "DP-1", "aspect": 1.7778, "name": "Coding",
                                                                        "windows": [EDITOR]}]}]})
        self.spaces("restore", "work")
        self.assertIn(["ipc", "call", "workspacename", "set", "2", "Coding"], self.s.calls("slate"))

    def test_spaces_from_before_names(self):
        """Older spaces have no name on their workspaces: they restore, numbered, as before."""
        self.fake_hyprland()
        self.s.add("slate")
        self.s.env["SLATE_COMMAND"] = os.path.join(self.s.dir, "slate")
        self.write(self.store, {"spaces": [{"id": "aaaaaaaaaaaa", "name": "Work", "colour": "#3366ff", "icon": "edba",
                                            "saved": 1, "workspaces": [{"monitor": "DP-1", "aspect": 1.7778, "windows": [EDITOR]}]}]})
        self.spaces("restore", "work")
        self.assertFalse([c for c in self.s.calls("slate") if "workspacename" in c])

    def test_no_names_file(self):
        os.remove(os.path.join(self.h.runtime, "slate", "workspace-names-test.json"))
        self.hyprland()
        self.assertEqual([w.get("name") for w in json.loads(self.spaces("snapshot"))], [None, None, None])
