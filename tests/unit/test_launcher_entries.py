"""scripts/launcher-entries.py: the dock badges and progress apps publish over D-Bus, read
from canned dbus-monitor output."""
import json

import slate
from slate import Case, run
from stubs import Stubs, fixture_text

SCRIPT = slate.path("shell", "scripts", "launcher-entries.py")
MATCH = "type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'"
SIGNAL = ("signal time=1762700001.1 sender=:1.87 -> destination=(null destination) serial=7 "
          "path=/com/canonical/unity/launcherentry/1; interface=com.canonical.Unity.LauncherEntry; member=Update\n")


def update(uri, *props):
    """One Update signal as dbus-monitor prints it; props are (name, "type value")."""
    out = SIGNAL + f'   string "{uri}"\n   array [\n'
    for name, v in props:
        out += f'      dict entry(\n         string "{name}"\n         variant             {v}\n      )\n'
    return out + "   ]\n"


class LauncherEntries(Case):
    scratch = True

    def lines(self, monitor_output):
        s = Stubs(self.h)
        s.add("dbus-monitor", stdout=monitor_output)
        code, out = run(["python3", SCRIPT], env=s.env, timeout=10)
        self.assertEqual(code, 0, out)
        # It only ever listens on the session bus, for this one signal
        self.assertEqual(s.calls("dbus-monitor")[-1:], [["--session", MATCH]])
        return [json.loads(l) for l in out.splitlines()]

    def test_capture(self):
        """Each change prints the app's whole state so far."""
        chat = {"app": "org.example.Chat"}
        files = {"app": "org.example.Files"}
        self.assertEqual(self.lines(fixture_text("launcher-entries", "updates.txt")), [
            dict(chat, count=3, countVisible=True),
            # The quicklist isn't a property the dock shows
            dict(files, progress=0.4, progressVisible=True),
            dict(chat, count=5, countVisible=True, urgent=True),
            dict(files, progress=1.0, progressVisible=False),
            dict(chat, count=5, countVisible=False, urgent=False),
        ])

    def test_value_types(self):
        cases = [
            ("int32 7", 7), ("uint32 7", 7), ("int64 12", 12), ("uint64 0", 0),
            ("double 0.25", 0.25), ("boolean true", True), ("boolean false", False),
        ]
        for raw, want in cases:
            with self.subTest(raw):
                got = self.lines(update("application://a.desktop", ("count", raw)))
                self.assertEqual(got, [{"app": "a", "count": want}])

    def test_unreadable_value_left_out(self):
        got = self.lines(update("application://a.desktop", ("count", "array of bytes []"), ("urgent", "boolean true")))
        self.assertEqual(got, [{"app": "a", "urgent": True}])

    def test_no_properties(self):
        self.assertEqual(self.lines(update("application://a.desktop")), [{"app": "a"}])

    def test_uri_without_scheme_ignored(self):
        """An app id that isn't an application:// URI says nothing, and doesn't swallow the
        next app's signal."""
        got = self.lines(update("org.example.Bare.desktop", ("count", "int64 1"))
                         + update("application://b.desktop", ("count", "int64 2")))
        self.assertEqual(got, [{"app": "b", "count": 2}])

    def test_other_signals_ignored(self):
        other = SIGNAL.replace("member=Update", "member=Query") + '   string "application://a.desktop"\n   array [\n   ]\n'
        self.assertEqual(self.lines(other), [])

    def test_nothing_said(self):
        self.assertEqual(self.lines(""), [])

    def test_no_dbus_monitor(self):
        s = Stubs(self.h)
        s.add("dbus-monitor", missing=True)
        code, out = run(["python3", SCRIPT], env=s.env, timeout=10)
        self.assertEqual(code, 1)
        self.assertIn("dbus-monitor isn't installed", out)
