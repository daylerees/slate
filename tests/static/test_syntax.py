"""Every file parses: QML (qmllint), Lua, Python and shell scripts."""
import os
import py_compile
import re
import tempfile

import slate
from slate import Case, need, run, tool

# qmllint warnings that mean the file is broken. Everything else it says (types it can't
# infer for Quickshell's objects, unqualified access…) is noise for Slate's layout.
QML_FATAL = re.compile(r"\[(syntax|import)\]$")
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


class Syntax(Case):
    def test_qml(self):
        """qmllint on every QML file, failing on syntax errors and missing types/imports.
        The login screen's files are left out: they only make sense in its own layout, and
        static/greeter loads them for real."""
        qmllint = need("/usr/lib/qt6/bin/qmllint", "/usr/lib64/qt6/bin/qmllint", "qmllint6")
        qml = slate.files("shell", ".qml", skip=("shell/greeter",))
        code, out = run([qmllint] + qml, cwd=slate.ROOT, timeout=300)
        problems = {}
        for line in out.splitlines():
            m = re.match(r"Warning: ([^:]+\.qml):(\d*):?(\d*):? (.*)$", line)
            if m and QML_FATAL.search(line) and not QML_IGNORE.search(line):
                problems.setdefault(m.group(1), []).append(f"line {m.group(2) or '?'}: {m.group(4)}")
        for f in qml:
            with self.subTest(f):
                self.assertFalse(problems.get(f), "; ".join(problems.get(f, [])[:3]))

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
