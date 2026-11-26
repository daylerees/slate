"""Every file parses: QML (qmllint), Lua, Python and shell scripts."""
import os
import py_compile
import re
import tempfile

import slate
from slate import Case, need, run, tool

# qmllint warnings that mean the file is broken. Everything else it says (types it can't
# infer for Quickshell's objects, unqualified access…) is noise for Slate's layout.
QML_FATAL = re.compile(r"\[(syntax|import)\]$|Duplicate binding on property .*\[duplicate-property-binding\]$")
# (a property set twice in one object stops Slate loading: "Property value set multiple times".
# The same category also covers "Cannot combine value source and binding", which loads fine)
# Slate's singletons live without a qmldir, which qmllint always notes
QML_IGNORE = re.compile(r"not declared as singleton in qmldir")


def shell_scripts():
    """Every shell script in the repo, by its first line."""
    out = []
    for rel in (slate.files("shell/bin", "") + slate.files("shell/scripts", ".sh") +
                slate.files("shell/session", "") + slate.files("shell/greeter", ".sh") +
                ["install.sh"] + slate.files("tools", ".sh")):
        try:
            with open(slate.path(rel), encoding="utf-8") as f:
                first = f.readline()
        except (UnicodeDecodeError, IsADirectoryError):
            continue
        m = re.match(r"#!\s*(?:/usr/bin/env\s+)?\S*?(bash|sh)\b", first)
        if m:
            out.append((rel, m.group(1)))
    return sorted(set(out))


_LINT = {}


def lint_qml():
    """qmllint on every QML file but the login screen's (once, for every test that reads it):
    (the files, what it said)."""
    if not _LINT:
        qmllint = need("/usr/lib/qt6/bin/qmllint", "/usr/lib64/qt6/bin/qmllint", "qmllint6")
        qml = slate.files("shell", ".qml", skip=("shell/greeter",))
        # Quickshell lets a file in a subfolder (shell/panels/) `import qs` to reach the types
        # in shell/ itself; qmllint has no such module, so it's given one: a qmldir naming them
        with tempfile.TemporaryDirectory() as imports:
            os.mkdir(os.path.join(imports, "qs"))
            lines = ["module qs"]
            for f in sorted(os.listdir(slate.SHELL)):
                if f.endswith(".qml") and f[0].isupper():
                    single = "singleton " if "pragma Singleton" in slate.read("shell", f) else ""
                    lines.append(f"{single}{f[:-4]} 1.0 {os.path.relpath(slate.path('shell', f), os.path.join(imports, 'qs'))}")
            with open(os.path.join(imports, "qs", "qmldir"), "w") as fh:
                fh.write("\n".join(lines) + "\n")
            code, out = run([qmllint, "-I", imports] + qml, cwd=slate.ROOT, timeout=300)
        _LINT["qml"], _LINT["out"] = qml, out
    return _LINT["qml"], _LINT["out"]


class Syntax(Case):
    def test_qml(self):
        """qmllint on every QML file, failing on syntax errors and missing types/imports.
        The login screen's files are left out: they only make sense in its own layout, and
        static/greeter loads them for real."""
        qml, out = lint_qml()
        problems = {}
        for line in out.splitlines():
            m = re.match(r"Warning: ([^:]+\.qml):(\d*):?(\d*):? (.*)$", line)
            if m and QML_FATAL.search(line) and not QML_IGNORE.search(line):
                problems.setdefault(m.group(1), []).append(f"line {m.group(2) or '?'}: {m.group(4)}")
        for f in qml:
            with self.subTest(f):
                self.assertFalse(problems.get(f), "; ".join(problems.get(f, [])[:3]))

    def test_no_unused_imports(self):
        """Every module a QML file imports is one it uses. Settings' pages and the bar's panels
        had copied their window's whole list (Bluetooth, Networking, Pipewire, UPower…).
        (Folder imports, "..", are left to qmllint's other checks.)"""
        qml, out = lint_qml()
        lines = out.splitlines()
        unused = {}
        for i, line in enumerate(lines):
            m = re.match(r"\w+: ([^:]+\.qml):(\d+):\d+: Unused import \[unused-imports\]$", line)
            if m and i + 1 < len(lines):
                imp = lines[i + 1].strip()
                if re.match(r"import [A-Za-z][\w.]*$", imp):
                    unused.setdefault(m.group(1), []).append(imp)
        # (not the template for your own shell.qml: its imports are there for what you'll add)
        for f in [f for f in qml if not f.startswith("shell/data/user-files/")]:
            with self.subTest(f):
                self.assertFalse(unused.get(f), f"imports it doesn't use: {unused.get(f)}")

    # What each module gives a file to use: a module imported with none of these in the file is
    # unused. qmllint only says so in a file it can fully resolve, and leaves it unsaid in any
    # with an unqualified lookup (most panels and windows: they read their parent's properties),
    # so those were never checked (UpdateHold, ReloadNotices and five panels had some).
    # (QtQuick and qs give too much to list, and are left to qmllint)
    MODULE_TYPES = {
        "Quickshell.Io": r"Process|FileView\w*|IpcHandler|StdioCollector|SplitParser|Socket\w*|DataStream\w*|JsonAdapter|JsonObject",
        "Quickshell.Wayland": r"Wlr\w+|WlSession\w*|Screencopy\w*|ToplevelManager|Toplevel|IdleInhibitor|IdleMonitor",
        "Quickshell.Hyprland": r"Hyprland\w*|GlobalShortcut",
        "QtQuick.Effects": r"MultiEffect|RectangularShadow",
        "QtQuick.Shapes": r"Shape|ShapePath|LinearGradient|RadialGradient|ConicalGradient",
        "Qt.labs.folderlistmodel": r"FolderListModel",
        "QtMultimedia": r"Video|VideoOutput|MediaPlayer|AudioOutput|SoundEffect|Camera\w*|CaptureSession|ImageCapture|MediaDevices",
        "Quickshell.Bluetooth": r"Bluetooth\w*",
        "Quickshell.Services.Pipewire": r"Pw\w+|Pipewire",
        # (not Connection\w+: that's Connections, QtQuick's own, which nearly every file has)
        "Quickshell.Networking": r"Networking|Network\w+|Wifi\w+|ConnectionState|DeviceConnectionState",
        # Quickshell itself: its singleton and its types (a newer qmllint found files with none)
        "Quickshell": r"Quickshell|ShellRoot|Scope|Variants|LazyLoader|PanelWindow|FloatingWindow|PopupWindow|QsWindow|"
                      r"ScriptModel|ObjectModel|PersistentProperties|Singleton|Region|RegionShape|Intersection|PopupAnchor|"
                      r"Edges|ExclusionMode|SystemClock|ElapsedTimer|DesktopEntries|DesktopEntry|QsMenu\w*|ColorQuantizer|"
                      r"Retainable|BoundComponent|Reloadable|TransformWatcher|EasingCurve|IconImage",
        "Quickshell.Services.UPower": r"UPower\w*|PowerProfile\w*|PerformanceDegradationReason",
        "Quickshell.Services.Mpris": r"Mpris\w*",
        "Quickshell.Services.SystemTray": r"SystemTray\w*|Status|Category",
        "Quickshell.Services.Pam": r"Pam\w+",
        "Quickshell.Services.Greetd": r"Greetd\w*",
        "Quickshell.Services.Polkit": r"Polkit\w*|AuthFlow|Identity",
        "Quickshell.Services.Notifications": r"Notification|NotificationServer|NotificationUrgency|NotificationAction|NotificationCloseReason",
    }

    def test_every_imported_module_is_used(self):
        for f in slate.files("shell", ".qml"):
            if f.startswith("shell/data/user-files/"):
                continue
            src = slate.read(f)
            # (comments out: not a "//" after a colon, which is a URL in a string, "file://…")
            body = re.sub(r"(?<!:)//[^\n]*|/\*.*?\*/", "", src, flags=re.S)
            body = re.sub(r"^import [^\n]*$", "", body, flags=re.M)
            for mod in re.findall(r"^import ([A-Za-z][\w.]*)\s*$", src, re.M):
                words = self.MODULE_TYPES.get(mod)
                if not words:
                    continue
                with self.subTest(f"{f}: {mod}"):
                    self.assertRegex(body, rf"\b(?:{words})\b", f"imports {mod} and uses nothing from it")

    def test_lua(self):
        luac = need("luac", "luac5.4", "luac5.5")
        for f in slate.files("shell", ".lua"):
            with self.subTest(f):
                code, out = run([luac, "-p", "-o", os.devnull, slate.path(f)])
                self.assertEqual(code, 0, out.strip().splitlines()[0] if out.strip() else "luac failed")

    def test_python(self):
        for f in slate.files("shell", ".py") + slate.files("tools", ".py") + ["tools/check-greeter-files"] + \
                slate.files("tests", ".py") + ["tests/run"][:0]:
            with self.subTest(f):
                with tempfile.NamedTemporaryFile(suffix=".pyc") as t:
                    try:
                        py_compile.compile(slate.path(f), cfile=t.name, doraise=True)
                    except py_compile.PyCompileError as e:
                        self.fail(str(e.msg).strip().splitlines()[-1])

    def test_shell(self):
        """sh -n / bash -n on every script, and shellcheck's errors (not its warnings)."""
        shellcheck = tool("shellcheck")
        for f, interp in shell_scripts():
            with self.subTest(f):
                code, out = run([interp, "-n", slate.path(f)])
                self.assertEqual(code, 0, out.strip())
                if shellcheck:
                    code, out = run([shellcheck, "-S", "error", "-f", "gcc", slate.path(f)])
                    self.assertEqual(code, 0, out.strip().splitlines()[0] if out.strip() else "")
