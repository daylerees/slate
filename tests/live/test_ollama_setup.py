"""Settings → Assistant sets up Ollama (scripts/ollama-setup.py): with Ollama running and no
model yet, Set up asks first (naming the model and its size), downloads it with progress on the
agent's row, and chooses it for Nova. Ollama is a stand-in on its usual address that serves a
pretend download. Installing it (a password, the distro's package) is the unit tests'
(tests/unit/test_ollama_setup.py). Asked for, 2026-11-21."""
import http.server
import json
import threading
import time

from live import LiveCase
from test_assistant_agents import FakeOllama

ROW = "Ollama (on this computer)"


class PullingOllama(FakeOllama):
    def do_POST(self):
        if self.path != "/api/pull":
            self.send_response(404)
            self.end_headers()
            return
        want = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}").get("model", "")
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        lines = [{"status": "pulling manifest"}] + [
            {"status": "pulling 1234", "digest": "sha256:1234", "total": 4_000_000_000, "completed": n * 500_000_000}
            for n in range(9)] + [{"status": "verifying sha256 digest"}, {"status": "success"}]
        for d in lines:
            # (listed before it says so, as Ollama does: Settings looks as soon as it hears)
            if d["status"] == "success":
                FakeOllama.models = [{"name": want, "capabilities": ["completion", "tools"]}]
            self.wfile.write((json.dumps(d) + "\n").encode())
            self.wfile.flush()
            time.sleep(0.3)


class SetUpOllama(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("assistantAgent", "assistantLocalModel"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("settings", "close"))
        FakeOllama.models = []
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 11434), PullingOllama)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.config("assistantAgent", "ollama")
        self.config("assistantLocalModel", "")

    def page(self, want, what, timeout=20):
        return self.wait(lambda st: st["settings"]["page"] is not None and want(st["settings"]["page"]), what,
                         timeout=timeout)["settings"]["page"]

    def test_downloads_a_model_and_chooses_it(self):
        self.ipc("settings", "page", "assistant")
        p = self.page(lambda p: p["setUp"], "Set up offered")
        model = p["plan"]["model"]
        self.assertTrue(p["plan"]["running"], p)
        self.assertIn("No models yet. Set up downloads " + model, p["agent"])
        self.assertIn(" GB)", p["agent"], "the download's size isn't said first")
        self.assertEqual(self.ipc("test", "settingsButton", ROW, "Set up"), "pressed")
        st = self.wait(lambda st: st["power"]["open"] and st["asking"] == "Set up Ollama?", "Slate to ask first")
        self.assertIn(model + " (about ", st["askingBody"], "the question doesn't say what it downloads, or its size")
        self.ipc("test", "answer", "true")
        p = self.page(lambda p: p["step"] == "downloading" and " of 4.0 GB" in p["agent"], "the download's progress")
        self.assertIn("You can close Settings", p["agent"])
        p = self.page(lambda p: p["step"] == "" and p["agent"] == "Ready", "ready, with the model", timeout=30)
        self.wait(lambda st: self.setting("assistantLocalModel") == model, "the model chosen for Nova")

    def test_says_no_without_the_question_answered(self):
        self.ipc("settings", "page", "assistant")
        self.page(lambda p: p["setUp"], "Set up offered")
        self.assertEqual(self.ipc("test", "settingsButton", ROW, "Set up"), "pressed")
        self.wait(lambda st: st["power"]["open"], "Slate to ask first")
        self.ipc("test", "answer", "false")
        self.s.settle(1.0)
        p = self.s.state()["settings"]["page"]
        self.assertEqual((p["step"], p["setUp"]), ("", True), "it started without a yes")
