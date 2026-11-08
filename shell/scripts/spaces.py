#!/usr/bin/env python3
"""Spaces: save the apps on some workspaces, and their layout, and bring them back later.

    spaces.py snapshot                      the workspaces now, as JSON (for the bar's picker)
    spaces.py save <name> <colour> <icon> <ids>
                                            save workspaces (ids comma-separated, e.g. 1,3)
                                            as a space, with a colour (#rrggbb) and an icon
                                            (a Tabler codepoint, e.g. edba); one with the
                                            same name is replaced
    spaces.py delete <id>                   forget a space
    spaces.py restore <id-or-name>          open each of its workspaces as a new workspace,
                                            start its apps and put their windows back

Spaces are kept in $XDG_DATA_HOME/slate/spaces.json.

Each window is saved with the command that starts it (from the app's .desktop file, else
the process's own command line) and its place relative to the screen's usable area, so a
space comes back the same on a screen of another size.

Restoring rebuilds the tiling one split at a time. The tiled windows of a workspace are
cut into two groups along a line no window crosses (left | right, or top / bottom), and
those groups again, down to single windows: the same tree Hyprland's dwindle layout keeps.
The first window of the workspace opens alone; then for each cut, the first window of the
first group is focused, told to put the next window to its right (or below), the first
window of the second group is started, and the split is set to the saved proportion.
Floating windows are started floating and moved and sized after.
"""
import fcntl
import json
import os
import re
import shlex
import subprocess
import sys
import time
import uuid

DATA = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "slate")
STORE = os.path.join(DATA, "spaces.json")
RUNTIME = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "slate")
LOCK = os.path.join(RUNTIME, "spaces.lock")
# Which open windows came from which space, for the borders and badges Slate draws on them
# (SpaceBadges.qml): {"instance": Hyprland's instance signature, "windows": {stableId: space
# id}}. Hyprland numbers windows the same way each time it starts, so a file from another
# Hyprland session is ignored. Windows that have closed are dropped on each write.
OWNERS = os.path.join(RUNTIME, "space-windows.json")

WINDOW_TIMEOUT = 15     # seconds to wait for an app's window
TOLERANCE = 12          # px: windows this close count as touching (gaps between tiles)

APP_DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    "/usr/share/applications",
]
# Reverse-domain prefixes many unrelated apps share: never matched just by the prefix
SHARED_PREFIXES = {"org.gnome", "org.kde", "org.freedesktop", "org.gtk", "com.github", "io.github",
                   "com.gitlab", "io.gitlab", "org.gitlab", "net.sourceforge", "app.drey", "page.tesk",
                   "io.elementary", "com.system76", "org.mozilla", "com.belmoussaoui", "de.haeckerfelix"}


# ---- Hyprland ------------------------------------------------------------------------

def hypr(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except ValueError:
        return []


def lua(code):
    """Run Lua in Hyprland (its 0.57+ config API). Returns hyprctl's reply ("ok" or an error)."""
    return subprocess.run(["hyprctl", "dispatch", "function() " + code + " end"],
                          capture_output=True, text=True).stdout.strip()


def lstr(s):
    """A Lua string literal."""
    s = str(s)
    n = 1
    while ("]" + "=" * n + "]") in s:
        n += 1
    return "[" + "=" * n + "[" + s + "]" + "=" * n + "]"


def win_sel(addr):
    return lstr("address:" + addr)


def dispatch(expr):
    return lua("hl.dispatch(" + expr + ")")


def monitor_area(m):
    """A monitor's usable area (without the bar and other reserved edges), in layout pixels."""
    scale = m.get("scale") or 1
    w, h = m["width"] / scale, m["height"] / scale
    if m.get("transform", 0) % 2:
        w, h = h, w
    left, top, right, bottom = (m.get("reserved") or [0, 0, 0, 0])[:4]
    return {"x": m["x"] + left, "y": m["y"] + top, "w": w - left - right, "h": h - top - bottom}


# ---- Finding how to start an app -------------------------------------------------------

def entry_values(path):
    """The [Desktop Entry] section of a .desktop file, parsed by hand (some generated
    files indent every line, which an INI parser misreads)."""
    vals, section = {}, None
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    section = line
                elif section == "[Desktop Entry]" and "=" in line:
                    k, v = line.split("=", 1)
                    vals.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return vals


_entries = None


def desktop_files():
    global _entries
    if _entries is None:
        _entries = {}
        for d in APP_DIRS:
            if os.path.isdir(d):
                for f in sorted(os.listdir(d)):
                    if f.endswith(".desktop") and f[:-8].lower() not in _entries:
                        _entries[f[:-8].lower()] = os.path.join(d, f)
    return _entries


def find_entry(cls):
    """The .desktop file for a window class, as Slate's dock and bar find it."""
    if not cls:
        return None
    want = cls.lower()
    by_name = desktop_files()
    for key in (want, want.split(".")[-1]):
        if key in by_name and entry_values(by_name[key]).get("Exec"):
            return by_name[key]
    for f in by_name.values():
        v = entry_values(f)
        if v.get("StartupWMClass", "").lower() == want and v.get("Exec"):
            return f
    parts = want.split(".")
    if len(parts) >= 3 and ".".join(parts[:2]) not in SHARED_PREFIXES:
        prefix = ".".join(parts[:2]) + "."
        for n, f in sorted(by_name.items()):
            if n.startswith(prefix) and entry_values(f).get("Exec"):
                return f
    return None


def exec_command(value):
    """A desktop entry's Exec= as a shell command, without its %f/%u/… field codes."""
    cmd = re.sub(r"%[fFuUdDnNickvm]", "", value).replace("%%", "%")
    return re.sub(r"\s+", " ", cmd).strip()


def launch_info(client):
    """How to start this window's app again: its desktop entry, else its command line."""
    path = find_entry(client.get("initialClass") or client.get("class"))
    if not path and client.get("class") != client.get("initialClass"):
        path = find_entry(client.get("class"))
    if path:
        v = entry_values(path)
        return {"desktopId": os.path.basename(path)[:-8], "command": exec_command(v["Exec"]),
                "terminal": v.get("Terminal", "").lower() == "true", "cwd": v.get("Path", ""),
                "name": v.get("Name", "")}
    try:
        with open(f"/proc/{client['pid']}/cmdline", "rb") as fh:
            args = [a.decode(errors="ignore") for a in fh.read().split(b"\0") if a]
    except (OSError, KeyError):
        args = []
    return {"desktopId": "", "command": shlex.join(args), "terminal": False, "cwd": "", "name": ""}


# ---- Snapshot and the store ------------------------------------------------------------

def snapshot():
    """Every normal workspace with windows: its screen and its windows, placed as fractions
    of the screen's usable area."""
    monitors = {m["name"]: m for m in hypr("monitors")}
    workspaces = {w["id"]: w for w in hypr("workspaces") if w.get("id", 0) > 0}
    clients = [c for c in hypr("clients") if c.get("mapped") and not c.get("hidden")
               and c.get("workspace", {}).get("id", 0) > 0]
    # Window rounding, for the previews (a lone tiled window and a maximised one are square:
    # see windowrules.lua)
    opt = subprocess.run(["hyprctl", "-j", "getoption", "decoration:rounding"], capture_output=True, text=True).stdout
    try:
        rounding = json.loads(opt).get("int", 0)
    except ValueError:
        rounding = 0
    out = []
    for wid in sorted(workspaces):
        ws = workspaces[wid]
        mon = monitors.get(ws.get("monitor"))
        wins = [c for c in clients if c["workspace"]["id"] == wid]
        tiled = sum(1 for c in wins if not c.get("floating"))
        if not mon or not wins:
            continue
        area = monitor_area(mon)
        # Oldest first, so apps come back in the order they were opened
        wins.sort(key=lambda c: -c.get("focusHistoryID", 0))
        items = []
        for c in wins:
            info = launch_info(c)
            if not info["command"]:
                continue
            items.append(dict(info, **{
                "class": c.get("class", ""), "title": c.get("title", ""),
                "x": round((c["at"][0] - area["x"]) / area["w"], 4),
                "y": round((c["at"][1] - area["y"]) / area["h"], 4),
                "w": round(c["size"][0] / area["w"], 4),
                "h": round(c["size"][1] / area["h"], 4),
                "floating": bool(c.get("floating")),
                "fullscreen": c.get("fullscreen", 0),
                "address": c.get("address", ""),     # for live previews; not saved
                "rounding": 0 if c.get("fullscreen") == 1 or (not c.get("floating") and tiled == 1) else rounding,
            }))
        if items:
            out.append({"id": wid, "monitor": mon["name"], "aspect": round(area["w"] / area["h"], 4),
                        "width": area["w"], "windows": items})
    return out


def load():
    try:
        with open(STORE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data.get("spaces"), list) else {"spaces": []}
    except (OSError, ValueError, AttributeError):
        return {"spaces": []}


def store(data):
    os.makedirs(DATA, exist_ok=True)
    tmp = STORE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    os.replace(tmp, STORE)


def save(name, colour, icon, ids):
    want = [int(i) for i in ids.split(",") if i.strip().lstrip("-").isdigit()]
    workspaces = [w for w in snapshot() if w["id"] in want]
    if not name.strip() or not workspaces:
        sys.exit("nothing to save")
    data = load()
    old = next((s for s in data["spaces"] if s["name"].lower() == name.strip().lower()), None)
    space = {"id": old["id"] if old else uuid.uuid4().hex[:12], "name": name.strip(), "colour": colour,
             "icon": icon,
             "saved": int(time.time()),
             "workspaces": [{"monitor": w["monitor"], "aspect": w["aspect"],
                             "windows": [{k: v for k, v in win.items() if k not in ("address", "rounding")}
                                         for win in w["windows"]]}
                            for w in workspaces]}
    if old:
        data["spaces"][data["spaces"].index(old)] = space
    else:
        data["spaces"].append(space)
    store(data)


def delete(sid):
    data = load()
    data["spaces"] = [s for s in data["spaces"] if s["id"] != sid]
    store(data)


# ---- Restoring --------------------------------------------------------------------------

def split_tree(wins):
    """Cut the tiled windows into a tree of splits along lines no window crosses.
    Returns a window, or (direction, ratio, first, second) with direction "r" (side by
    side) or "d" (one above the other), or None if they can't be cut (overlapping)."""
    if len(wins) == 1:
        return wins[0]
    x0 = min(w["px"] for w in wins); x1 = max(w["px"] + w["pw"] for w in wins)
    y0 = min(w["py"] for w in wins); y1 = max(w["py"] + w["ph"] for w in wins)
    # Try the cut across the longer side first, as dwindle splits
    axes = [("r", "px", "pw", x0, x1), ("d", "py", "ph", y0, y1)]
    if (y1 - y0) > (x1 - x0):
        axes.reverse()
    for direction, pos, size, lo, hi in axes:
        ordered = sorted(wins, key=lambda w: w[pos])
        for k in range(1, len(ordered)):
            a, b = ordered[:k], ordered[k:]
            end_a = max(w[pos] + w[size] for w in a)
            start_b = min(w[pos] for w in b)
            if end_a <= start_b + TOLERANCE:
                ta, tb = split_tree(a), split_tree(b)
                if ta is None or tb is None:
                    continue
                cut = (end_a + start_b) / 2
                ratio = max(0.1, min(1.9, 2 * (cut - lo) / max(1, hi - lo)))
                return (direction, ratio, ta, tb)
    return None


def first_leaf(node):
    while isinstance(node, tuple):
        node = node[2]
    return node


def remember(stable_id, space_id):
    """Note that a window belongs to a space."""
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    try:
        with open(OWNERS, encoding="utf-8") as fh:
            data = json.load(fh)
        if "windows" not in data:          # the first version: a bare map, from this session
            owners = data
        else:
            owners = data["windows"] if data.get("instance") == instance else {}
    except (OSError, ValueError, AttributeError):
        owners = {}
    alive = {str(c.get("stableId")) for c in hypr("clients")}
    owners = {k: v for k, v in owners.items() if k in alive}
    owners[str(stable_id)] = space_id
    os.makedirs(RUNTIME, exist_ok=True)
    tmp = OWNERS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"instance": instance, "windows": owners}, fh)
    os.replace(tmp, OWNERS)


class Restorer:
    def __init__(self, space_id):
        self.space_id = space_id
        self.failed = []
        self.ratio_form = None      # which "splitratio" form this Hyprland takes, once known

    def clients(self):
        return {c["address"]: c for c in hypr("clients")}

    def launch(self, win, ws, floating=False):
        """Start an app on workspace ws and wait for its window. Returns the window's
        address, or None if none came."""
        before = set(self.clients())
        cmd = win["command"]
        if win.get("cwd"):
            cmd = "cd " + shlex.quote(win["cwd"]) + " && " + cmd
        expr = ("(TERMINAL or 'kitty') .. ' -e ' .. " + lstr(cmd)) if win.get("terminal") else lstr(cmd)
        rules = "workspace = " + lstr(str(ws)) + (", float = true" if floating else "")
        reply = lua("hl.exec_cmd(" + expr + ", { " + rules + " })")
        if reply.startswith("error"):
            print(reply, file=sys.stderr)
        want = (win.get("class") or "").lower()
        end = time.time() + WINDOW_TIMEOUT
        while time.time() < end:
            time.sleep(0.15)
            new = [c for a, c in self.clients().items() if a not in before and c.get("mapped")]
            if not new:
                continue
            new.sort(key=lambda c: (c.get("class", "").lower() != want, c["workspace"]["id"] != ws))
            c = new[0]
            if c["workspace"]["id"] != ws:
                dispatch("hl.dsp.window.move({ workspace = " + str(ws) + ", follow = false, window = "
                         + win_sel(c["address"]) + " })")
            time.sleep(0.3)        # let it settle into its place
            if c.get("stableId") is not None:
                remember(c["stableId"], self.space_id)
            return c["address"]
        self.failed.append(win.get("name") or win.get("class") or win["command"].split(" ")[0])
        return None

    def focus(self, addr):
        dispatch("hl.dsp.focus({ window = " + win_sel(addr) + " })")
        time.sleep(0.05)

    def set_ratio(self, addr, ratio, direction, parent_size):
        """Set the split the window at addr sits in. The two spellings differ between
        Hyprland versions: try one, check the window's size, and keep whichever worked."""
        want = parent_size * ratio / 2
        key = 0 if direction == "r" else 1
        forms = [self.ratio_form] if self.ratio_form else ["splitratio {:.3f} exact", "splitratio exact {:.3f}"]
        for form in forms:
            self.focus(addr)
            dispatch("hl.dsp.layout(" + lstr(form.format(ratio)) + ")")
            time.sleep(0.12)
            c = self.clients().get(addr)
            if c and abs(c["size"][key] - want) <= max(24, parent_size * 0.04):
                self.ratio_form = form
                return

    def build(self, node, addr, ws, box):
        """node's area is taken by the window at addr (its first window): split it."""
        if not isinstance(node, tuple):
            return
        direction, ratio, a, b = node
        self.focus(addr)
        dispatch("hl.dsp.layout(" + lstr("preselect " + direction) + ")")
        other = self.launch(first_leaf(b), ws)
        if other is None:
            # Its first app didn't open: carry on with the rest of that side
            rest = [w for w in leaves(b) if w is not first_leaf(b)]
            if rest:
                sub = split_tree(rest)
                if sub is not None:
                    self.build((direction, ratio, a, sub), addr, ws, box)
                    return
            self.build(a, addr, ws, box)
            return
        size = box[2] if direction == "r" else box[3]
        self.set_ratio(addr, ratio, direction, size)
        bx, by, bw, bh = box
        if direction == "r":
            box_a = (bx, by, bw * ratio / 2, bh)
            box_b = (bx + bw * ratio / 2, by, bw - bw * ratio / 2, bh)
        else:
            box_a = (bx, by, bw, bh * ratio / 2)
            box_b = (bx, by + bh * ratio / 2, bw, bh - bh * ratio / 2)
        self.build(a, addr, ws, box_a)
        self.build(b, other, ws, box_b)

    def place_floating(self, addr, win, area):
        c = self.clients().get(addr)
        if c and not c.get("floating"):
            dispatch("hl.dsp.window.float({ action = 'enable', window = " + win_sel(addr) + " })")
            time.sleep(0.1)
        w, h = round(win["w"] * area["w"]), round(win["h"] * area["h"])
        x, y = round(area["x"] + win["x"] * area["w"]), round(area["y"] + win["y"] * area["h"])
        dispatch("hl.dsp.window.resize({ x = %d, y = %d, relative = false, window = %s })" % (w, h, win_sel(addr)))
        dispatch("hl.dsp.window.move({ x = %d, y = %d, relative = false, window = %s })" % (x, y, win_sel(addr)))
        time.sleep(0.1)
        c = self.clients().get(addr)
        if c and (abs(c["at"][0] - x) > 2 or abs(c["at"][1] - y) > 2):
            # Some versions place relative to the screen: nudge it by what's left
            dispatch("hl.dsp.window.move({ x = %d, y = %d, relative = true, window = %s })"
                     % (x - c["at"][0], y - c["at"][1], win_sel(addr)))

    def restore_workspace(self, saved, ws):
        monitors = {m["name"]: m for m in hypr("monitors")}
        if saved.get("monitor") in monitors and len(monitors) > 1:
            dispatch("hl.dsp.focus({ monitor = " + lstr(saved["monitor"]) + " })")
        dispatch("hl.dsp.focus({ workspace = " + str(ws) + " })")
        time.sleep(0.2)
        mon = next((m for m in hypr("monitors") if m.get("activeWorkspace", {}).get("id") == ws), None) \
            or next(iter(hypr("monitors")), None)
        area = monitor_area(mon) if mon else {"x": 0, "y": 0, "w": 1920, "h": 1080}
        wins = saved["windows"]
        for w in wins:
            w["px"], w["py"] = w["x"] * area["w"], w["y"] * area["h"]
            w["pw"], w["ph"] = w["w"] * area["w"], w["h"] * area["h"]
        tiled = [w for w in wins if not w["floating"]]
        floating = [w for w in wins if w["floating"]]
        opened = []
        if tiled:
            tree = split_tree(tiled)
            if tree is None:
                # Overlapping tiles (e.g. a group): just open them in order
                for w in tiled:
                    a = self.launch(w, ws)
                    if a:
                        opened.append((a, w))
            else:
                first = self.launch(first_leaf(tree), ws)
                if first is None:
                    rest = [w for w in tiled if w is not first_leaf(tree)]
                    for w in rest:          # fall back to plain order
                        a = self.launch(w, ws)
                        if a:
                            opened.append((a, w))
                else:
                    self.build(tree, first, ws, (0, 0, area["w"], area["h"]))
        for w in floating:
            a = self.launch(w, ws, floating=True)
            if a:
                self.place_floating(a, w, area)
                opened.append((a, w))
        # Fullscreen and maximised windows last, once everything is in place
        by_class = {}
        for c in self.clients().values():
            if c["workspace"]["id"] == ws:
                by_class.setdefault(c.get("class", "").lower(), []).append(c["address"])
        for w in wins:
            mode = w.get("fullscreen", 0)
            if mode and by_class.get(w.get("class", "").lower()):
                addr = by_class[w["class"].lower()].pop(0)
                dispatch("hl.dsp.window.fullscreen({ mode = %s, action = 'set', window = %s })"
                         % (lstr("maximized" if mode == 1 else "fullscreen"), win_sel(addr)))


def leaves(node):
    if not isinstance(node, tuple):
        return [node]
    return leaves(node[2]) + leaves(node[3])


def notify(summary, body):
    try:
        subprocess.Popen(["notify-send", "-a", "Slate", "-i", "view-grid", summary, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def restore(key):
    space = next((s for s in load()["spaces"] if s["id"] == key or s["name"].lower() == key.lower()), None)
    if not space:
        sys.exit("no space called " + key)
    os.makedirs(RUNTIME, exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit("a space is already being restored")
    # New workspaces after the last one with windows (an empty spare there gets used)
    taken = {w["id"] for w in hypr("workspaces") if w.get("id", 0) > 0 and w.get("windows", 0) > 0}
    nxt = max(taken, default=0) + 1
    r = Restorer(space["id"])
    first_ws = None
    for saved in space["workspaces"]:
        while nxt in taken:
            nxt += 1
        ws = nxt
        nxt += 1
        first_ws = first_ws or ws
        r.restore_workspace(saved, ws)
    if first_ws and len(space["workspaces"]) > 1:
        dispatch("hl.dsp.focus({ workspace = " + str(first_ws) + " })")
    if r.failed:
        names = sorted(set(r.failed))
        notify("Some apps in " + space["name"] + " didn't open",
               ", ".join(names) + " didn't open a window (an app that's already open may"
               " just switch to its existing window).")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]
    if cmd == "snapshot":
        print(json.dumps(snapshot()))
    elif cmd == "save" and len(args) == 5:
        save(args[1], args[2], args[3], args[4])
    elif cmd == "delete" and len(args) == 2:
        delete(args[1])
    elif cmd == "restore" and len(args) == 2:
        time.sleep(0.3)        # let the bar's panel let go of the keyboard first
        restore(args[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
