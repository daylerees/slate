"""Settings → Assistant offers every agent Slate knows (scripts/slate_agents.py), and for
Ollama, the models on this computer. In the container none of the agent CLIs is installed, so
each is offered as not installed yet (Ollama may be, as an optional package, but nothing starts
it); Ollama's HTTP API is a small stand-in on its usual address, started here (the container
has a network of its own)."""
import http.server
import json
import threading

from live import LiveCase

LABELS = ["Claude Code", "Codex", "OpenCode", "Goose", "Antigravity", "Ollama (on this computer)",
          "Codex with Ollama (on this computer)", "A command of your own"]


class FakeOllama(http.server.BaseHTTPRequestHandler):
    models = []

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = json.dumps({"models": FakeOllama.models}).encode() if self.path == "/api/tags" else b"{}"
        self.send_response(200 if self.path == "/api/tags" else 404)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)


class AgentChoices(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("assistantAgent", "assistantLocalModel"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("settings", "close"))

    def agents(self):
        self.ipc("settings", "close")
        self.wait(lambda st: not st["settings"]["open"], "Settings to close")
        self.ipc("settings", "page", "assistant")
        st = self.wait(lambda st: st["settings"]["section"] == "assistant" and len(st["settings"]["agents"]) > 0,
                       "Settings → Assistant to find the agents", timeout=20)
        return {a["id"]: a for a in st["settings"]["agents"]}

    def test_every_agent_is_offered(self):
        a = self.agents()
        self.assertEqual([x["label"] for x in a.values()], LABELS)
        for agent in ("codex", "opencode", "goose", "antigravity"):
            self.assertFalse(a[agent]["installed"], f"{agent} isn't in the container")
        # (Ollama may be: it's an optional package, but nothing starts it here)
        self.assertEqual((a["ollama"]["running"], a["ollama"]["models"]), (False, []))

    def test_ollamas_models(self):
        """With Ollama running, its models are offered, without those that run on its servers."""
        FakeOllama.models = [{"name": "qwen3:8b", "capabilities": ["completion", "tools"]},
                             {"name": "gemma3:1b", "capabilities": ["completion"]},
                             {"name": "gpt-oss:120b-cloud", "remote_host": "https://ollama.com:443", "capabilities": ["tools"]}]
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 11434), FakeOllama)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        a = self.agents()["ollama"]
        self.assertEqual((a["installed"], a["running"], a["models"]), (True, True, ["qwen3:8b", "gemma3:1b"]))
