"""Slate's runtime folder: where the marks, locks and this login's notes go. It's
$XDG_RUNTIME_DIR; without one, a folder of your own that only you can open
($XDG_STATE_HOME/slate/run), never /tmp, where anyone on the computer could put a file of the
same name first. The QML, the shell scripts, the Python scripts and Hyprland's config read and
write the same files there, so each works the folder out by the same rule: checked here."""
import os
import re
import stat

import slate
from slate import Case, run

SHELL_SCRIPTS = (("shell", "bin", "slate"), ("shell", "bin", "slate-build-hyprbars"), ("shell", "scripts", "screenshot.sh"))
PYTHON_SCRIPTS = (("shell", "scripts", "spaces.py"), ("shell", "scripts", "voice.py"), ("shell", "scripts", "launcher-entries.py"),
                  ("shell", "scripts", "software.py"))
QML = ("Config.qml", "UserFiles.qml", "SettingsWindow.qml", "Spaces.qml", "PrivateMode.qml", "shell.qml")


def shell_rule(parts):
    m = re.search(r'^RUNTIME="\$\{XDG_RUNTIME_DIR:-\}"\n\[ -n "\$RUNTIME" \] \|\| \{.*\}\n', slate.read(*parts), re.M)
    return m.group(0) if m else None


def python_rule(parts):
    m = re.search(r"^def runtime_dir\(\):\n(?:    .*\n)+", slate.read(*parts), re.M)
    return m.group(0) if m else None


def lua_rule():
    m = re.search(r'^local runtimeDir = .*?^end\n', slate.read("shell", "session", "hypr", "hyprland.lua"), re.M | re.S)
    return m.group(0) if m else None


class RuntimeDir(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.own = os.path.join(self.h.state, "slate", "run")
        self.without = {k: v for k, v in self.h.env.items() if k != "XDG_RUNTIME_DIR"}
        self.without["XDG_STATE_HOME"] = self.h.state

    def shell(self, parts, env):
        code, out = run(["sh", "-c", shell_rule(parts) + 'printf %s "$RUNTIME"'], env=env)
        self.assertEqual(code, 0, out)
        return out

    def python(self, parts, env):
        code, out = run(["python3", "-c", "import os, sys\n" + python_rule(parts) + "sys.stdout.write(runtime_dir())"], env=env)
        self.assertEqual(code, 0, out)
        return out

    def test_one_rule_in_every_script(self):
        rules = {"/".join(p): shell_rule(p) for p in SHELL_SCRIPTS}
        self.assertNotIn(None, rules.values(), rules)
        self.assertEqual(len(set(rules.values())), 1, "the shell scripts work the folder out differently")
        rules = {"/".join(p): python_rule(p) for p in PYTHON_SCRIPTS}
        self.assertNotIn(None, rules.values(), rules)
        self.assertEqual(len(set(rules.values())), 1, "the Python scripts work the folder out differently")

    def test_xdg_runtime_dir_when_there_is_one(self):
        for parts in SHELL_SCRIPTS:
            self.assertEqual(self.shell(parts, self.h.env), self.h.runtime)
        for parts in PYTHON_SCRIPTS:
            self.assertEqual(self.python(parts, self.h.env), self.h.runtime)
        self.assertFalse(os.path.exists(self.own), "made a folder of its own though $XDG_RUNTIME_DIR is set")

    def test_a_folder_of_your_own_without_one(self):
        """…the same one from the shell and from Python, and closed to everyone else, even when
        it was already there and open."""
        for kind, scripts, work in (("shell", SHELL_SCRIPTS, self.shell), ("python", PYTHON_SCRIPTS, self.python)):
            for parts in scripts:
                with self.subTest("/".join(parts)):
                    if os.path.isdir(self.own):
                        os.chmod(self.own, 0o755)
                    self.assertEqual(work(parts, self.without), self.own)
                    self.assertEqual(stat.S_IMODE(os.stat(self.own).st_mode), 0o700)
        # (an empty $XDG_RUNTIME_DIR is none at all)
        empty = dict(self.without, XDG_RUNTIME_DIR="")
        self.assertEqual(self.shell(SHELL_SCRIPTS[0], empty), self.own)
        self.assertEqual(self.python(PYTHON_SCRIPTS[0], empty), self.own)

    def test_state_home_defaults_to_the_home_folder(self):
        env = {k: v for k, v in self.without.items() if k != "XDG_STATE_HOME"}
        want = os.path.join(env["HOME"], ".local", "state", "slate", "run")
        self.assertEqual(self.shell(SHELL_SCRIPTS[0], env), want)
        self.assertEqual(self.python(PYTHON_SCRIPTS[0], env), want)

    def test_hyprlands_config_agrees(self):
        lua = slate.need("lua", "lua5.4", "luajit")
        rule = lua_rule()
        self.assertTrue(rule, "hyprland.lua's runtimeDir has moved")
        for env, want in ((self.h.env, self.h.runtime), (self.without, self.own), (dict(self.without, XDG_RUNTIME_DIR=""), self.own)):
            code, out = run([lua, "-e", rule + "io.write(runtimeDir)"], env=env)
            self.assertEqual((code, out), (0, want))

    def test_qml_agrees(self):
        config = slate.read("shell", "Config.qml")
        self.assertIn('readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")\n'
                      '        || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slate/run")', config)
        # …made, and closed, when it's Slate's own
        self.assertIn("""command: ["sh", "-c", 'mkdir -p "$0" && chmod 700 "$0"', root.runtimeDir]""", config)
        for name in sorted(os.listdir(slate.path("shell"))):
            if name.endswith(".qml"):
                src = slate.read("shell", name)
                uses = len(re.findall(r'Quickshell\.env\("XDG_RUNTIME_DIR"\)', src))
                self.assertEqual(uses, 2 if name == "Config.qml" else 0, name + " works the runtime folder out for itself")

    def test_nothing_falls_back_to_tmp(self):
        for top in ("bin", "scripts", "session", "greeter", "."):
            folder = slate.path("shell", top)
            for dirpath, _, names in os.walk(folder) if top != "." else [(folder, [], os.listdir(folder))]:
                for name in names:
                    p = os.path.join(dirpath, name)
                    if not os.path.isfile(p) or name.endswith((".png", ".ttf", ".wav", ".jpg", ".so")):
                        continue
                    try:
                        with open(p, encoding="utf-8") as f:
                            src = f.read()
                    except UnicodeDecodeError:
                        continue
                    for n, line in enumerate(src.splitlines(), 1):
                        with self.subTest(os.path.relpath(p, slate.ROOT), line=n):
                            self.assertNotRegex(line, r"""["']/tmp["']|:-/tmp\}|or "/tmp"|\|\| "/tmp\"""")
