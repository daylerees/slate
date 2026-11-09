"""scripts/launcher-entries.py: the dock badges and progress apps publish over D-Bus, read
from canned dbus-monitor output."""
import json
import os
import signal
import stat
import subprocess
import time

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

    def state_file(self):
        return os.path.join(self.h.runtime, "slate", "launcher-entries.json")

    def forget(self):
        if os.path.exists(self.state_file()):
            os.remove(self.state_file())

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
                self.forget()               # (each from an empty session: no count from the last)
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

    # ---- Kept for the session: Slate restarting doesn't lose the badges -----------------------

    def test_remembered_after_a_restart(self):
        """Apps only speak when a count changes; after Slate restarts (a new listener), the
        counts so far come first, before anything new (they used to be lost until the app
        spoke again)."""
        self.lines(update("application://a.desktop", ("count", "int64 3"), ("count-visible", "boolean true"))
                   + update("application://b.desktop", ("progress", "double 0.5")))
        with open(self.state_file()) as f:
            self.assertEqual(set(json.load(f)), {"a", "b"})
        got = self.lines(update("application://b.desktop", ("progress", "double 0.75")))
        self.assertEqual(got, [{"app": "a", "count": 3, "countVisible": True},
                               {"app": "b", "progress": 0.5},
                               {"app": "b", "progress": 0.75}])

    def test_damaged_state_starts_afresh(self):
        for bad in ("{half", "[]", '{"a": 5}'):
            with self.subTest(bad):
                os.makedirs(os.path.dirname(self.state_file()), exist_ok=True)
                with open(self.state_file(), "w") as f:
                    f.write(bad)
                self.assertEqual(self.lines(update("application://c.desktop", ("count", "int64 1"))),
                                 [{"app": "c", "count": 1}])

    def test_stops_with_slate(self):
        """When whatever started it goes (Slate, killed by a full restart), it and its
        dbus-monitor stop too: they used to run on, one more copy each restart."""
        s = Stubs(self.h)
        pids = os.path.join(self.h.dir, "pids")
        # A dbus-monitor that listens forever, as the real one does
        fake = os.path.join(s.dir, "dbus-monitor")
        with open(fake, "w") as f:
            f.write("#!/bin/sh\necho $$ >> '%s'\nexec sleep 300\n" % pids)
        os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)
        # Its parent: started in the background, then the parent exits (as Slate's process does)
        subprocess.run(["sh", "-c", "python3 '%s' >/dev/null 2>&1 & echo $! >> '%s'; sleep 1" % (SCRIPT, pids)],
                       env=s.env, timeout=10)
        with open(pids) as f:
            started = [int(p) for p in f.read().split()]
        self.assertEqual(len(started), 2, "the listener and its dbus-monitor")
        def alive(pid):
            try:
                os.kill(pid, 0)
                with open(f"/proc/{pid}/stat") as st:
                    return st.read().split()[2] != "Z"
            except (OSError, FileNotFoundError):
                return False
        try:
            for _ in range(50):
                if not any(alive(p) for p in started):
                    break
                time.sleep(0.1)
            self.assertFalse([p for p in started if alive(p)], "still running after their parent went")
        finally:
            for p in started:
                try:
                    os.kill(p, signal.SIGKILL)
                except OSError:
                    pass

    def test_monitor_stops_with_it(self):
        """When Slate stops the listener (every reload does), its dbus-monitor goes too: it used
        to be left running, one more each reload."""
        s = Stubs(self.h)
        pids = os.path.join(self.h.dir, "pids")
        fake = os.path.join(s.dir, "dbus-monitor")
        with open(fake, "w") as f:
            f.write("#!/bin/sh\necho $$ >> '%s'\nexec sleep 300\n" % pids)
        os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)
        p = subprocess.Popen(["python3", SCRIPT], env=s.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        monitor = None
        try:
            for _ in range(50):
                if os.path.exists(pids) and open(pids).read().strip():
                    monitor = int(open(pids).read().split()[0])
                    break
                time.sleep(0.1)
            self.assertIsNotNone(monitor, "dbus-monitor didn't start")
            p.terminate()
            p.wait(5)
            for _ in range(50):
                try:
                    os.kill(monitor, 0)
                    with open(f"/proc/{monitor}/stat") as st:
                        if st.read().split()[2] == "Z":
                            break
                except (OSError, FileNotFoundError):
                    break
                time.sleep(0.1)
            else:
                self.fail("dbus-monitor still running after the listener was stopped")
        finally:
            p.kill()
            if monitor:
                try:
                    os.kill(monitor, signal.SIGKILL)
                except OSError:
                    pass
