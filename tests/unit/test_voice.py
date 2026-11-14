"""scripts/voice.py: talking to Nova (Settings → Assistant → Voice). Recording and whisper.cpp
are stand-ins (tests/fixtures/voice: pw-record writes silence, whisper-cli "hears" a file), so
no microphone is opened; the model download is served from a local file or a server in the
test, never the network."""
import glob
import hashlib
import http.server
import json
import os
import signal
import subprocess
import sys
import threading
import time

import slate
from stubs import Stubs, fixture

SCRIPT = slate.path("shell", "scripts", "voice.py")
SCRIPTS = slate.path("shell", "scripts")
sys.path.insert(0, SCRIPTS)
import voice  # noqa: E402


class Voice(slate.Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)
        # whisper.cpp as this computer might have it, hidden: only the stand-in is found
        for name in voice.WHISPER + ("pw-record",):
            self.s.add(name, missing=True)
        self.env = dict(self.s.env, SLATE_VOICE_TOOLS=fixture("voice"))
        self.model = os.path.join(self.h.data, "slate", "whisper", voice.MODEL["name"])

    def with_model(self):
        """The model as a download leaves it (its size is what's checked; a sparse file)."""
        os.makedirs(os.path.dirname(self.model), exist_ok=True)
        with open(self.model, "wb") as f:
            f.truncate(voice.MODEL["size"])

    def calls(self, tool=None):
        try:
            with open(self.h(".voice-calls")) as f:
                calls = [json.loads(l) for l in f if l.strip()]
        except FileNotFoundError:
            return []
        return [c for c in calls if tool is None or c["tool"] == tool]

    def recordings(self):
        return glob.glob(os.path.join(self.h.runtime, "slate-voice-*.wav"))

    def status(self):
        out = self.ok(["python3", SCRIPT, "status"], env=self.env)
        return json.loads(out)

    # ---- listening ------------------------------------------------------------------------
    def listen(self, hold=0.8, end="stop", env=None):
        """Start listening, hold for a while, then say stop (or close stdin, or SIGTERM).
        Returns (exit code, the events)."""
        p = subprocess.Popen(["python3", SCRIPT, "listen"], env=env or self.env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        first = p.stdout.readline()
        events = [json.loads(first)] if first.strip() else []
        if events and events[0]["type"] == "listening":
            time.sleep(hold)
            self.assertTrue(self.recordings() or end == "now", "nothing was being recorded while held")
            if end == "stop":
                p.stdin.write("stop\n")
                p.stdin.flush()
            elif end == "close":
                p.stdin.close()
            elif end == "term":
                p.send_signal(signal.SIGTERM)
        rest, _ = p.communicate(timeout=30)
        events += [json.loads(l) for l in rest.splitlines() if l.strip()]
        return p.returncode, events

    def test_listens_and_writes_it_down(self):
        self.with_model()
        code, events = self.listen()
        self.assertEqual(code, 0, events)
        self.assertEqual([e["type"] for e in events], ["listening", "transcribing", "text"])
        self.assertEqual(events[-1]["text"], "Turn on glass.", "whisper's [BLANK_AUDIO] wasn't taken out")
        self.assertEqual(self.recordings(), [], "the recording was kept after it was written down")
        rec, = self.calls("pw-record")
        self.assertEqual(rec["args"][:6], ["--rate", "16000", "--channels", "1", "--format", "s16"])
        self.assertTrue(rec["args"][-1].startswith(self.h.runtime + "/"), "recorded outside $XDG_RUNTIME_DIR")
        w, = self.calls("whisper-cli")
        a = w["args"]
        self.assertEqual(a[a.index("-m") + 1], self.model)
        self.assertEqual(a[a.index("-f") + 1], rec["args"][-1])
        self.assertGreater(w["wav"], 44, "whisper was given an empty recording")
        self.assertIn("-nt", a)
        self.assertEqual(a[a.index("-l") + 1], "auto", "C.UTF-8 isn't a language: whisper works it out")

    def test_language_from_the_locale(self):
        self.with_model()
        for lang, want in (("de_DE.UTF-8", "de"), ("en_GB.UTF-8", "en"), ("pt_BR", "pt"), ("C", "auto"), ("xx_YY.UTF-8", "auto")):
            with self.subTest(lang):
                env = dict(self.env, LC_ALL=lang)
                code, events = self.listen(hold=0.5, env=env)
                self.assertEqual(code, 0, events)
                a = self.calls("whisper-cli")[-1]["args"]
                self.assertEqual(a[a.index("-l") + 1], want)

    def test_your_words_as_said(self):
        self.with_model()
        with open(self.h(".voice-transcript"), "w") as f:
            f.write("  Put Firefox on\n workspace 2 (music) please. ")
        code, events = self.listen()
        self.assertEqual(events[-1], {"type": "text", "text": "Put Firefox on workspace 2 please."})

    def test_let_go_too_soon(self):
        """A tap isn't words: nothing is written down, and it says how to do it."""
        self.with_model()
        code, events = self.listen(hold=0.05)
        self.assertEqual(events[-1]["kind"], "nothing-heard")
        self.assertEqual(self.calls("whisper-cli"), [])
        self.assertEqual(self.recordings(), [])

    def test_nothing_but_noise(self):
        self.with_model()
        with open(self.h(".voice-transcript"), "w") as f:
            f.write("[ Silence ]")
        code, events = self.listen()
        self.assertEqual((code, events[-1]["kind"]), (4, "nothing-heard"))
        self.assertIn("didn't catch any words", events[-1]["message"])
        self.assertEqual(self.recordings(), [])

    def test_slate_gone_or_cancelled(self):
        """stdin closing without "stop" (Slate gone, or cancelled) and SIGTERM: nothing is
        written down, and the recording is deleted all the same."""
        self.with_model()
        for end in ("close", "term"):
            with self.subTest(end):
                code, events = self.listen(end=end)
                self.assertEqual(code, 5, events)
                self.assertEqual([e["type"] for e in events], ["listening"])
                self.assertEqual(self.recordings(), [], "a recording was left behind")
        self.assertEqual(self.calls("whisper-cli"), [], "it was written down anyway")

    def test_never_past_the_limit(self):
        """A key that's never let go: it stops by itself, and what was said is written down."""
        self.with_model()
        # (stdin stays open, as Slate's does while the key is held)
        p = subprocess.Popen(["python3", "-c", "import sys; sys.path.insert(0, %r); import voice; sys.exit(voice.listen(limit=1))" % SCRIPTS],
                             env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        events = [json.loads(l) for l in p.stdout]
        p.wait(timeout=30)
        p.stdin.close()
        self.assertEqual([e["type"] for e in events], ["listening", "transcribing", "text"])
        self.assertEqual(self.recordings(), [])
        self.assertEqual(voice.MAX_SECONDS, 60)

    def test_never_in_private_mode(self):
        self.with_model()
        open(os.path.join(self.h.runtime, "slate-private"), "w").close()
        code, events = self.listen()
        self.assertEqual((code, [e.get("kind") for e in events]), (2, ["private"]))
        self.assertEqual(self.calls("pw-record"), [], "the microphone was opened in Private Mode")
        self.assertTrue(self.status()["private"])

    def test_without_whisper(self):
        """whisper.cpp isn't installed: it says what to install, and the microphone is never opened."""
        env = dict(self.env)
        tools = os.path.join(self.h.dir, "only-recorder")
        os.makedirs(tools)
        os.symlink(fixture("voice", "pw-record"), os.path.join(tools, "pw-record"))
        env["SLATE_VOICE_TOOLS"] = tools
        self.with_model()
        st = json.loads(self.ok(["python3", SCRIPT, "status"], env=env))
        self.assertEqual((st["whisper"], st["model"], st["recorder"]), ("", True, True))
        code, events = self.listen(env=env)
        self.assertEqual((code, events[-1]["kind"]), (2, "no-whisper"))
        self.assertIn("whisper-cpp", events[-1]["message"])
        self.assertEqual(self.calls("pw-record"), [])

    def test_older_names(self):
        """Older packages call it whisper-cpp or whisper.cpp: found all the same."""
        for name in ("whisper-cpp", "whisper.cpp"):
            with self.subTest(name):
                tools = os.path.join(self.h.dir, "old-" + name)
                os.makedirs(tools)
                os.symlink(fixture("voice", "whisper-cli"), os.path.join(tools, name))
                st = json.loads(self.ok(["python3", SCRIPT, "status"], env=dict(self.env, SLATE_VOICE_TOOLS=tools)))
                self.assertEqual(st["whisper"], os.path.join(tools, name))

    def test_without_the_model(self):
        st = self.status()
        self.assertEqual((st["whisper"], st["model"]), (fixture("voice", "whisper-cli"), False))
        code, events = self.listen()
        self.assertEqual((code, events[-1]["kind"]), (2, "no-model"))
        self.assertIn("Settings → Assistant → Voice", events[-1]["message"])
        self.assertEqual(self.calls("pw-record"), [])
        # Half a model (a download cut short and left by hand) isn't one
        os.makedirs(os.path.dirname(self.model), exist_ok=True)
        with open(self.model, "wb") as f:
            f.write(b"x" * 1000)
        self.assertFalse(self.status()["model"])

    def test_no_microphone(self):
        self.with_model()
        open(self.h(".voice-no-mic"), "w").close()
        code, events = self.listen(end="now")
        self.assertEqual(events[-1]["kind"], "no-mic")
        self.assertIn("Slate couldn't hear your microphone", events[-1]["message"])
        self.assertEqual(self.recordings(), [])

    def test_whisper_fails(self):
        self.with_model()
        open(self.h(".voice-fail"), "w").close()
        code, events = self.listen()
        self.assertEqual((code, events[-1]["kind"]), (3, "failed"))
        self.assertIn("failed to load model", events[-1]["detail"])
        self.assertEqual(self.recordings(), [])

    # ---- the model ------------------------------------------------------------------------
    def download(self, url, size, sha):
        p = subprocess.run(["python3", "-c", "import sys; sys.path.insert(0, %r); import voice; "
                            "sys.exit(voice.download(url=%r, size=%d, sha256=%r, every=0))" % (SCRIPTS, url, size, sha)],
                           env=self.env, capture_output=True, text=True, timeout=60)
        return p.returncode, [json.loads(l) for l in p.stdout.splitlines()]

    def served(self, data):
        src = os.path.join(self.h.dir, "model-source.bin")
        with open(src, "wb") as f:
            f.write(data)
        return "file://" + src

    def test_the_model_is_the_real_one(self):
        """The fixed address, size and checksum (whisper.cpp's base model on Hugging Face)."""
        self.assertEqual(voice.MODEL["url"], "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
        self.assertEqual(voice.MODEL["size"], 147951465)
        self.assertRegex(voice.MODEL["sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(voice.model_path().endswith("/slate/whisper/ggml-base.bin"))

    def test_download(self):
        data = os.urandom(300000)
        code, events = self.download(self.served(data), len(data), hashlib.sha256(data).hexdigest())
        self.assertEqual(code, 0, events)
        self.assertEqual(events[-1], {"type": "done"})
        progress = [e for e in events if e["type"] == "progress"]
        self.assertGreater(len(progress), 2, "no progress along the way")
        self.assertEqual(progress[-1]["done"], len(data))
        with open(self.model, "rb") as f:
            self.assertEqual(f.read(), data)
        self.assertFalse(os.path.exists(self.model + ".part"))
        self.assertEqual(os.stat(os.path.dirname(self.model)).st_mode & 0o777, 0o700)

    def test_download_over_http(self):
        data = os.urandom(200000)

        class Serve(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *a):
                pass
        srv = http.server.HTTPServer(("127.0.0.1", 0), Serve)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.shutdown)
        code, events = self.download("http://127.0.0.1:%d/ggml-base.bin" % srv.server_port, len(data), hashlib.sha256(data).hexdigest())
        self.assertEqual((code, events[-1]["type"]), (0, "done"), events)
        self.assertEqual(os.path.getsize(self.model), len(data))

    def test_download_checksum_wrong(self):
        """Not the model expected (changed, cut short or too long): nothing is kept."""
        data = os.urandom(100000)
        for name, size, sha in (("checksum", len(data), "0" * 64), ("too short", len(data) + 5, hashlib.sha256(data).hexdigest()),
                                ("too long", len(data) - 5, hashlib.sha256(data).hexdigest())):
            with self.subTest(name):
                code, events = self.download(self.served(data), size, sha)
                self.assertEqual((code, events[-1]["kind"]), (4, "checksum"), events)
                self.assertIn("wasn't the one it expected", events[-1]["message"])
                self.assertFalse(os.path.exists(self.model), "a model that didn't match was kept")
                self.assertFalse(os.path.exists(self.model + ".part"))

    def test_download_offline(self):
        code, events = self.download("file://" + os.path.join(self.h.dir, "nowhere.bin"), 10, "0" * 64)
        self.assertEqual((code, events[-1]["kind"]), (3, "offline"))
        self.assertIn("Check you're online", events[-1]["message"])
        self.assertFalse(os.path.exists(self.model))
        self.assertFalse(os.path.exists(self.model + ".part"))

    def test_download_stopped(self):
        """Cancel (SIGTERM) part way: what came so far is deleted."""
        data = os.urandom(200000)

        class Slow(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data[:65536])
                self.wfile.flush()
                time.sleep(20)

            def log_message(self, *a):
                pass
        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Slow)
        srv.daemon_threads = True
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.shutdown)
        p = subprocess.Popen(["python3", "-c", "import sys; sys.path.insert(0, %r); import voice; "
                              "sys.exit(voice.download(url=%r, size=%d, sha256=%r, every=0))"
                              % (SCRIPTS, "http://127.0.0.1:%d/m" % srv.server_port, len(data), "0" * 64)],
                             env=self.env, stdout=subprocess.PIPE, text=True)
        for line in p.stdout:
            e = json.loads(line)
            if e["type"] == "progress" and e["done"] > 0:
                break
        self.assertTrue(os.path.exists(self.model + ".part"))
        p.send_signal(signal.SIGTERM)
        rest = p.stdout.read()
        p.wait(timeout=10)
        self.assertEqual(p.returncode, 5)
        self.assertEqual(json.loads(rest.splitlines()[-1])["kind"], "stopped")
        self.assertFalse(os.path.exists(self.model + ".part"))
        self.assertFalse(os.path.exists(self.model))

    def test_delete(self):
        self.with_model()
        self.assertTrue(self.status()["model"])
        self.ok(["python3", SCRIPT, "delete"], env=self.env)
        self.assertFalse(os.path.exists(self.model))
        self.assertFalse(self.status()["model"])

    def test_clean_text(self):
        self.assertEqual(voice.clean_text(" [BLANK_AUDIO]\n Hello there. \n (wind blowing) *coughs*"), "Hello there.")
        self.assertEqual(voice.clean_text(""), "")
        self.assertEqual(len(voice.clean_text("a " * 3000)), 2000)
