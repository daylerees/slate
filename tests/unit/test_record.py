"""scripts/record.sh: screen recording. `start` records (wf-recorder) and leaves a mark while it
does (its process, its file, when it started: ScreenRecorder.qml reads it); `stop` ends it and
the video is saved in the screenshot folder with a notification. The sound comes from Settings,
Private Mode stops it starting, one runs at a time, and what goes wrong is said kindly.
wf-recorder here is a stand-in that writes a little "video" and stops on an interrupt, as the
real one does."""
import json
import os
import stat
import subprocess
import time

import slate
from slate import Case, run
from stubs import Stubs

SCRIPT = slate.path("shell", "scripts", "record.sh")

RECORDER = """#!%s
import json, os, signal, sys, time
open(%r, "a").write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("STUB_RECORDER_FAILS"):
    sys.stderr.write("failed to find an output\\n")
    sys.exit(1)
out = sys.argv[sys.argv.index("-f") + 1]
open(out, "wb").write(b"a little video")
signal.signal(signal.SIGINT, lambda *a: sys.exit(0))
while True:
    time.sleep(0.05)
"""

MONITORS = json.dumps([{"name": "DP-1", "focused": True, "activeWorkspace": {"id": 1}}])


class Record(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        self.calls = os.path.join(self.h.dir, "recorder-calls")
        p = os.path.join(self.s.dir, "wf-recorder")
        with open(p, "w") as f:
            f.write(RECORDER % (__import__("sys").executable, self.calls))
        os.chmod(p, 0o755)
        self.s.add("notify-send")
        self.s.add("hyprctl", stdout=MONITORS)
        self.s.add("slurp", stdout="10,10 100x80\n")
        self.folder = os.path.join(self.h.home, "Shots")
        self.settings({})
        self.mark = os.path.join(self.h.runtime, "slate-recording")

    def settings(self, extra):
        os.makedirs(os.path.join(self.h.config, "slate"), exist_ok=True)
        with open(os.path.join(self.h.config, "slate", "settings.json"), "w") as f:
            json.dump(dict({"screenshotFolder": self.folder}, **extra), f)

    def start(self, mode="screen", env=None):
        p = subprocess.Popen(["/bin/sh", SCRIPT, "start", mode], env=dict(self.s.env, **(env or {})),
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(p.kill)
        return p

    def wait_for(self, cond, what, timeout=5):
        end = time.time() + timeout
        while time.time() < end:
            if cond():
                return
            time.sleep(0.05)
        self.fail(what)

    def recorder_args(self):
        with open(self.calls) as f:
            return [json.loads(line) for line in f]

    def notes(self):
        return [c for c in self.s.calls("notify-send")]

    def test_records_and_stops(self):
        p = self.start("screen")
        self.wait_for(lambda: os.path.exists(self.mark) and os.path.exists(self.calls), "no mark while recording")
        with open(self.mark) as f:
            pid, file, since = f.read().split("\n")[:3]
        self.assertTrue(file.startswith(self.folder + "/Screen Recording "), file)
        self.assertTrue(file.endswith(".mp4"), file)
        self.assertAlmostEqual(int(since), time.time(), delta=10)
        self.assertEqual(stat.S_IMODE(os.stat(self.mark).st_mode), 0o600, "the mark says what's being recorded: yours alone")
        self.assertEqual(self.recorder_args()[0][:3], ["-y", "-o", "DP-1"], "not the focused screen")
        self.assertNotIn("--audio", " ".join(self.recorder_args()[0]), "sound recorded without asking for it")
        code, out = run(["/bin/sh", SCRIPT, "stop"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        p.wait(timeout=10)
        self.assertFalse(os.path.exists(self.mark), "the mark stayed after it stopped")
        self.assertTrue(os.path.getsize(file) > 0, "the video wasn't kept")
        self.assertIn("Screen recording saved", json.dumps(self.notes()))

    def test_an_area(self):
        p = self.start("region")
        self.wait_for(lambda: os.path.exists(self.mark) and os.path.exists(self.calls), "no recording of the area")
        self.assertEqual(self.recorder_args()[0][:3], ["-y", "-g", "10,10 100x80"])
        run(["/bin/sh", SCRIPT, "stop"], env=self.s.env, timeout=10)
        p.wait(timeout=10)

    def test_sound_as_set(self):
        for sound, want in (("computer", "--audio=@DEFAULT_MONITOR@"), ("microphone", "--audio=@DEFAULT_SOURCE@")):
            with self.subTest(sound):
                self.settings({"recordSound": sound})
                if os.path.exists(self.calls):
                    os.remove(self.calls)
                p = self.start()
                self.wait_for(lambda: os.path.exists(self.mark) and os.path.exists(self.calls), "no recording")
                self.assertIn(want, self.recorder_args()[0])
                run(["/bin/sh", SCRIPT, "stop"], env=self.s.env, timeout=10)
                p.wait(timeout=10)

    def test_toggle_stops_the_one_going(self):
        p = self.start()
        self.wait_for(lambda: os.path.exists(self.mark) and os.path.exists(self.calls), "no recording")
        code, out = run(["/bin/sh", SCRIPT, "toggle", "region"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        p.wait(timeout=10)
        self.assertEqual(len(self.recorder_args()), 1, "toggle started a second recording")
        self.assertFalse(os.path.exists(self.mark))

    def test_one_at_a_time(self):
        p = self.start()
        self.wait_for(lambda: os.path.exists(self.mark) and os.path.exists(self.calls), "no recording")
        code, out = run(["/bin/sh", SCRIPT, "start", "screen"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertEqual(len(self.recorder_args()), 1, "a second recording started on top")
        run(["/bin/sh", SCRIPT, "stop"], env=self.s.env, timeout=10)
        p.wait(timeout=10)

    def test_not_in_private_mode(self):
        open(os.path.join(self.h.runtime, "slate-private"), "w").close()
        code, out = run(["/bin/sh", SCRIPT, "start", "screen"], env=self.s.env, timeout=10)
        self.assertEqual(code, 0, out)
        self.assertFalse(os.path.exists(self.calls), "recorded in Private Mode")
        self.assertIn("Screen recording is off", json.dumps(self.notes()))

    def test_says_what_to_install(self):
        self.s.add("wf-recorder", missing=True)
        code, out = run(["/bin/sh", SCRIPT, "start", "screen"], env=self.s.env, timeout=10)
        self.assertEqual(code, 1, out)
        self.assertIn('Install the \\"wf-recorder\\" package', json.dumps(self.notes()))

    def test_says_when_the_recorder_fails(self):
        code, out = run(["/bin/sh", SCRIPT, "start", "screen"], env=dict(self.s.env, STUB_RECORDER_FAILS="1"), timeout=10)
        self.assertEqual(code, 1, out)
        said = json.dumps(self.notes())
        self.assertIn("Slate couldn't record the screen", said)
        self.assertIn("failed to find an output", said)
        self.assertFalse(os.path.exists(self.mark))
        self.assertEqual([f for f in os.listdir(self.folder)], [], "an empty video was left behind")
