"""The sessions you can log in to are listed in three places: the lock screen's (LockScreen.qml,
for the login screen's preview), the login screen's (greeter/shell.qml) and the emergency login
screen's (greeter/emergency/shell.qml). The emergency one only looked in /usr/share, so on
NixOS it found none (a bug). Each one's command is run on the same folders, and all find the same
sessions: every folder in XDG_DATA_DIRS, the first of each name winning, none made up."""
import json
import os
import re

import slate
from slate import Case, run

FILES = (("shell", "LockScreen.qml"), ("shell", "greeter", "shell.qml"), ("shell", "greeter", "emergency", "shell.qml"))


def command(parts):
    src = slate.read(*parts)
    line = next(l for l in src.split("\n") if 'command: ["sh", "-c", "IFS=:; seen=;' in l or
                ("wayland-sessions" in l and 'command: ["sh", "-c",' in l))
    return json.loads(re.search(r'command: \["sh", "-c", ("(?:[^"\\]|\\.)*")\]', line).group(1))


class SessionLists(Case):
    scratch = True

    def session(self, d, name, title):
        os.makedirs(os.path.join(d, "wayland-sessions"), exist_ok=True)
        with open(os.path.join(d, "wayland-sessions", name + ".desktop"), "w") as f:
            f.write(f"[Desktop Entry]\nName={title}\nExec=start-{name}\n")

    def found(self, parts, dirs):
        code, out = run(["sh", "-c", command(parts)], env=dict(self.h.env, XDG_DATA_DIRS=dirs), timeout=10)
        self.assertEqual(code, 0, out)
        # (the first two fields are the name and Exec in the lock screen's, id and name in the others':
        # compared by the Exec, which all have)
        return sorted(l.split("\t")[-1] if parts[-1] == "LockScreen.qml" else l.split("\t")[2]
                      for l in out.split("\n") if l.strip())

    def test_all_three_agree(self):
        a, b, empty = (os.path.join(self.h.dir, n) for n in ("a", "b", "empty"))
        self.session(a, "slate", "Slate")
        self.session(a, "hyprland", "Hyprland")
        self.session(b, "hyprland", "Hyprland (another)")      # (the first of a name wins)
        self.session(b, "sway", "Sway")
        os.makedirs(empty)
        for parts in FILES:
            with self.subTest(file="/".join(parts)):
                self.assertEqual(self.found(parts, f"{a}:{empty}:{b}"), ["start-hyprland", "start-slate", "start-sway"])
                self.assertEqual(self.found(parts, empty), [], "made up a session with none there")
