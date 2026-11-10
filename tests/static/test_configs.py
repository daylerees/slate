"""Slate's Hyprland config loads, and the login screen's file list and load test pass."""
import os
import re

import slate
from slate import Case, need


class Configs(Case):
    scratch = True

    def test_hyprland_session_config(self):
        """Hyprland --verify-config on Slate's session config, installed in a scratch home
        (it reads ~/.config/slate), with and without a user's own files."""
        hyprland = need("Hyprland")
        dest = self.h.install_slate()
        conf = os.path.join(dest, "session", "hypr", "hyprland.lua")
        for case in ("fresh install", "with user files"):
            with self.subTest(case):
                if case == "with user files":
                    # The files Slate creates for you (scripts/user-files.sh copies these)
                    src = slate.path("shell", "data", "user-files", "hypr")
                    if os.path.isdir(src):
                        os.makedirs(os.path.join(dest, "hypr"), exist_ok=True)
                        for n in os.listdir(src):
                            with open(os.path.join(src, n)) as i, open(os.path.join(dest, "hypr", n), "w") as o:
                                o.write(i.read())
                code, out = slate.run([hyprland, "--verify-config", "-c", conf], env=self.h.env, timeout=60)
                clean = re.sub(r"\x1b\[[0-9;]*m", "", out)
                result = clean.partition("Config parsing result:")[2].strip()
                problem = " ".join(l.strip() for l in result.splitlines() if l.strip())[:300]
                self.assertTrue(code == 0 and result.startswith("config ok"), problem or f"exit {code}")
                # A mistake in a user file is skipped and noted here rather than failing the load
                slate_errors = [l.strip() for l in clean.splitlines() if "[slate] error" in l]
                errfile = os.path.join(self.h.runtime, "slate-hypr-errors.txt")
                if os.path.exists(errfile):
                    with open(errfile) as f:
                        slate_errors += f.read().split("\n")
                slate_errors = [e for e in slate_errors if e.strip()]
                self.assertFalse(slate_errors, "; ".join(slate_errors[:2]))


class Greeter(Case):
    def test_file_list(self):
        """tools/check-greeter-files: the login screen's file list has what its code loads."""
        self.ok(["python3", slate.path("tools", "check-greeter-files")], "check-greeter-files",
                logname="check-greeter-files.txt")

    def test_loads(self):
        """slate-greeter-check --source: the login screen and the emergency one load."""
        need("qs")
        self.ok([slate.path("shell", "bin", "slate-greeter-check"), "--source", slate.SHELL],
                "the login screen", logname="slate-greeter-check.txt", timeout=180)


class SwitcherKeys(Case):
    """Keys while a switcher is open (the test session can't press keys, so these read the code)."""

    def test_super_arrows_move_the_window_switcher(self):
        """Super+Left/Right move through the open window switcher rather than switching workspace,
        in Slate's shortcuts and in Hyprland + Slate Extras."""
        src = slate.read("shell", "session", "hypr", "config", "binds.lua")
        # Slate's set, then (inside "if HYPR_KEYS") Hyprland's with Slate's extras
        slate_set, hypr_set = src.split("if HYPR_KEYS then", 1)
        for name, part, guard in (("Slate's", slate_set, "if switcherIsOpen()"), ("Extras", hypr_set, "if EXTRAS and switcherIsOpen()")):
            for cmd in ('sw("next")', 'sw("prev")'):
                with self.subTest(set=name, cmd=cmd):
                    self.assertIn(f"{guard} then {cmd}", part)

    def test_up_goes_to_the_workspace(self):
        """In the overview, Up goes to the chosen workspace (on the grid it moves up a row)."""
        src = slate.read("shell", "WorkspaceOverview.qml")
        line = next(l for l in src.splitlines() if "case Qt.Key_Up:" in l)
        self.assertIn("ov.choose()", line)
        self.assertIn("ov.moveRow(-1)", line)
