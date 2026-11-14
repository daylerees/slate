"""The agents beyond Claude Code (scripts/slate_agents.py): Codex, OpenCode, Goose,
Antigravity, and a model on this computer through Ollama (scripts/ollama-agent.py). Each CLI
is a stand-in that keeps how it was started (its arguments, stdin, folder and the files
there) and replays a stream written here in the shape its documentation and source give.
Ollama is a small HTTP server in the test, and Slate's MCP server is the real one against the
fake Slate test_slate_mcp.py uses. Nothing here reaches a real agent, model or the network."""
import http.server
import json
import os
import stat
import subprocess
import sys
import threading
import time

import slate
from slate import run

import test_slate_mcp as mcp_tests

SCRIPT = slate.path("shell", "scripts", "assistant.py")
sys.path.insert(0, slate.path("shell", "scripts"))
import safe_markdown  # noqa: E402

# A stand-in agent CLI: keeps what it was given in <name>.got, answers --version and the
# sign-in check, then prints $STUB_STREAM's lines (and $STUB_ERR to stderr) and exits $STUB_EXIT
AGENT = """#!{python}
import json, os, sys, time
here = os.path.dirname(os.path.abspath(__file__))
name = os.path.basename(__file__)
a = sys.argv[1:]
if a[:1] == ["--version"]:
    print(os.environ.get("STUB_VERSION", "{version}")); sys.exit(0)
if a[:2] == ["login", "status"]:
    ok = not os.path.exists(os.path.join(here, "signed-out"))
    print("Logged in using ChatGPT" if ok else "Not logged in"); sys.exit(0 if ok else 1)
files = {{}}
for root, dirs, names in os.walk(os.getcwd()):
    for n in names:
        p = os.path.join(root, n)
        files[os.path.relpath(p, os.getcwd())] = open(p).read()
json.dump({{"args": a, "stdin": sys.stdin.read(), "cwd": os.getcwd(), "pwd": os.environ.get("PWD"), "files": files,
           "env": {{k: v for k, v in os.environ.items() if k.startswith(("SLATE_", "GOOSE_"))}}}},
          open(os.path.join(here, name + ".got"), "w"))
if os.environ.get("STUB_HANG"):
    time.sleep(60)
for l in open(os.environ["STUB_STREAM"]).read().splitlines():
    print(l, flush=True)
if os.environ.get("STUB_ERR"):
    sys.stderr.write(os.environ["STUB_ERR"] + "\\n")
sys.exit(int(os.environ.get("STUB_EXIT", "0")))
"""

VERSIONS = {"codex": "codex-cli 0.169.0", "opencode": "2.2.6", "goose": " 1.54.0", "agy": "agy 1.4.4"}


def lines(*events):
    return "\n".join(json.dumps(e) for e in events) + "\n"


# The streams, as each agent's documentation (and, for OpenCode and Goose, source) has them
CODEX = lines(
    {"type": "thread.started", "thread_id": "0199a213-81c0-7800-8aa1-bbab2a035a53"},
    {"type": "turn.started"},
    {"type": "item.completed", "item": {"id": "item_0", "type": "agent_message", "text": "Let me look."}},
    {"type": "item.started", "item": {"id": "item_1", "type": "mcp_tool_call", "server": "slate", "tool": "settings_get", "status": "in_progress"}},
    {"type": "item.completed", "item": {"id": "item_1", "type": "mcp_tool_call", "server": "slate", "tool": "settings_get", "status": "completed"}},
    {"type": "item.updated", "item": {"id": "item_2", "type": "agent_message", "text": "Glass is "}},
    {"type": "item.completed", "item": {"id": "item_2", "type": "agent_message", "text": "Glass is **off**."}},
    {"type": "turn.completed", "usage": {"input_tokens": 24763, "cached_input_tokens": 24448, "output_tokens": 122}})
OPENCODE = lines(
    {"type": "step_start", "timestamp": 1, "sessionID": "ses_4f2a1c", "part": {"type": "step-start"}},
    {"type": "tool_use", "timestamp": 2, "sessionID": "ses_4f2a1c", "part": {"type": "tool", "tool": "slate_settings_get"}},
    {"type": "text", "timestamp": 3, "sessionID": "ses_4f2a1c", "part": {"id": "p1", "messageID": "m1", "type": "text", "text": "Checking."}},
    {"type": "text", "timestamp": 4, "sessionID": "ses_4f2a1c", "part": {"id": "p2", "messageID": "m2", "type": "text", "text": "Glass is "}},
    {"type": "text", "timestamp": 5, "sessionID": "ses_4f2a1c", "part": {"id": "p3", "messageID": "m2", "type": "text", "text": "**off**."}},
    {"type": "step_finish", "timestamp": 6, "sessionID": "ses_4f2a1c", "part": {"type": "step-finish", "reason": "stop"}})
GOOSE = lines(
    {"type": "message", "message": {"id": "a1", "role": "assistant", "created": 1, "content": [{"type": "text", "text": "Let me check."}], "metadata": {}}},
    {"type": "message", "message": {"id": "a1", "role": "assistant", "created": 1, "content": [{"type": "toolRequest", "id": "t1", "toolCall": {}}], "metadata": {}}},
    {"type": "message", "message": {"id": "u1", "role": "user", "created": 2, "content": [{"type": "toolResponse", "id": "t1", "toolResult": {}}], "metadata": {}}},
    {"type": "message", "message": {"id": "a2", "role": "assistant", "created": 3, "content": [{"type": "text", "text": "Glass is "}], "metadata": {}}},
    {"type": "message", "message": {"id": "a2", "role": "assistant", "created": 3, "content": [{"type": "text", "text": "**off**."}], "metadata": {}}},
    {"type": "complete", "total_tokens": 100})
AGY = lines(
    {"event": "init", "conversation_id": "c3b66b04-872b-4fbe-a3a4-058a026ef20a", "init": {"cwd": "/x", "tools": ["run_command"], "permission_mode": "request-review"}},
    {"event": "step_update", "step_update": {"conversation_id": "c3b66b04", "step_index": 0, "state": "DONE", "step_type": "user_input"}},
    {"event": "step_update", "step_update": {"conversation_id": "c3b66b04", "step_index": 2, "state": "ACTIVE", "step_type": "agent_response", "text_delta": "Glass is "}},
    {"event": "step_update", "step_update": {"conversation_id": "c3b66b04", "step_index": 2, "state": "DONE", "step_type": "agent_response", "text_delta": "**off**.\n"}},
    {"event": "result", "result": {"conversation_id": "c3b66b04-872b-4fbe-a3a4-058a026ef20a", "status": "SUCCESS", "response": "Glass is **off**.\n", "num_turns": 1}})


class Base(mcp_tests.Base):
    def setUp(self):
        super().setUp()
        self.s.env["SLATE_COMMAND"] = mcp_tests.SLATE
        for name, version in VERSIONS.items():
            p = os.path.join(self.s.dir, name)
            with open(p, "w") as f:
                f.write(AGENT.format(python=sys.executable, version=version))
            os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)

    def stream(self, text):
        p = os.path.join(self.h.dir, "stream.jsonl")
        with open(p, "w") as f:
            f.write(text)
        return p

    def ask(self, agent, stream="", prompt="is glass on?", env=None, **opts):
        cmd = [sys.executable, SCRIPT, "run", "--agent", agent, "--run", "r1"]
        for k, v in opts.items():
            cmd += ["--" + k] + ([] if v is True else [v])
        env = dict(self.s.env, STUB_STREAM=self.stream(stream), **(env or {}))
        p = subprocess.run(cmd, input=prompt, env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 0, p.stderr)
        return [json.loads(l) for l in p.stdout.splitlines()]

    def got(self, name):
        with open(os.path.join(self.s.dir, name + ".got")) as f:
            return json.load(f)

    def detect(self):
        code, out = run([sys.executable, SCRIPT, "detect"], env=self.s.env)
        self.assertEqual(code, 0, out)
        return {a["id"]: a for a in json.loads(out)}

    def answered(self, events, text, session):
        """The stream came out as Slate's events: a start, the words, the whole answer's blocks, done."""
        self.assertEqual(events[0], {"type": "start", "session": session})
        self.assertEqual(events[-1], {"type": "done", "text": text, "session": session})
        self.assertEqual(events[-2], {"type": "blocks", "blocks": safe_markdown.parse(text)})

    def after(self, args, flag):
        return args[args.index(flag) + 1]


class Codex(Base):
    def test_detect(self):
        c = self.detect()["codex"]
        self.assertEqual((c["label"], c["installed"], c["version"], c["signedIn"], c["confined"], c["followUps"]),
                         ("Codex", True, "0.169.0", True, True, True))
        open(os.path.join(self.s.dir, "signed-out"), "w").close()
        self.assertFalse(self.detect()["codex"]["signedIn"], "codex login status says not")
        os.remove(os.path.join(self.s.dir, "codex"))
        self.s.add("codex", missing=True)
        c = self.detect()["codex"]
        self.assertEqual((c["installed"], c["signedIn"], c["version"]), (False, False, ""))

    def test_a_prompt(self):
        events = self.ask("codex", CODEX)
        self.answered(events, "Glass is **off**.", "0199a213-81c0-7800-8aa1-bbab2a035a53")
        texts = [e for e in events if e["type"] == "text"]
        self.assertEqual([(e["delta"], e.get("fresh", False)) for e in texts],
                         [("Let me look.", True), ("Glass is ", True), ("**off**.", False)])

    def test_confined(self):
        """Its own tools off, the person's config.toml left out, Slate's server for this run
        alone, approvals never asked for, the briefing as developer instructions; the prompt on
        stdin, never in its arguments."""
        self.ask("codex", CODEX, prompt="is glass on?")
        got = self.got("codex")
        a = got["args"]
        self.assertEqual(a[:2], ["exec", "--json"])
        self.assertEqual(a[-1], "-")
        for flag in ("--skip-git-repo-check", "--ignore-user-config", "--ignore-rules"):
            self.assertIn(flag, a)
        conf = dict(a[i + 1].split("=", 1) for i, x in enumerate(a) if x == "-c")
        for f in ("shell_tool", "view_image", "multi_agent", "apps", "plugins", "browser_use", "computer_use", "hooks"):
            self.assertEqual(conf["features." + f], "false", f)
        self.assertEqual((conf["web_search"], conf["sandbox_mode"], conf["approval_policy"]), ('"disabled"', '"read-only"', '"never"'))
        self.assertEqual(conf["mcp_servers.slate.command"], json.dumps(mcp_tests.SLATE))
        self.assertEqual(conf["mcp_servers.slate.args"], '["mcp"]')
        self.assertEqual(conf["mcp_servers.slate.env"], '{"SLATE_ASSISTANT_RUN" = "r1", "SLATE_ASSISTANT_AGENT" = "Codex", "SLATE_COMMAND" = %s}' % json.dumps(mcp_tests.SLATE))
        self.assertEqual(conf["mcp_servers.slate.default_tools_approval_mode"], '"approve"')
        self.assertTrue(json.loads(conf["developer_instructions"]).startswith("You are Nova"))
        self.assertTrue(got["stdin"].endswith("</slate-context>\n\nis glass on?"))
        self.assertNotIn("You are Nova", got["stdin"])
        self.assertNotIn("is glass on?", " ".join(a))
        self.assertEqual(got["cwd"], self.h(".local", "state", "slate", "assistant", "work"))

    def test_follow_up_and_model(self):
        self.ask("codex", CODEX, session="0199a213", model="gpt-5.5")
        a = self.got("codex")["args"]
        self.assertEqual(a[:3], ["exec", "resume", "--json"])
        self.assertEqual(a[-2:], ["0199a213", "-"])
        self.assertEqual(self.after(a, "-m"), "gpt-5.5")
        self.assertIn("features.shell_tool=false", a)

    def test_errors(self):
        for message, kind in (("unexpected status 401 Unauthorized: Missing bearer", "signed-out"),
                              ("stream disconnected before completion: error sending request", "offline"),
                              ("You've hit your usage limit", "failed"),
                              ("MCP client for `slate` failed to start", "server"),
                              ("something odd", "failed")):
            with self.subTest(kind):
                stream = lines({"type": "thread.started", "thread_id": "t"}, {"type": "error", "message": message},
                               {"type": "turn.failed", "error": {"message": message}})
                e = self.ask("codex", stream, env={"STUB_EXIT": "1"})[-1]
                self.assertEqual((e["type"], e["kind"]), ("error", kind))
        e = self.ask("codex", lines({"type": "turn.failed", "error": {"message": "401"}}))[-1]
        self.assertIn("run codex login once", e["message"])

    def test_exits_without_a_word(self):
        """Not signed in, it may stop before its stream says why: Slate asks and says so."""
        open(os.path.join(self.s.dir, "signed-out"), "w").close()
        e = self.ask("codex", "", env={"STUB_EXIT": "1"})[-1]
        self.assertEqual(e["kind"], "signed-out")

    def test_timeout(self):
        e = self.ask("codex", CODEX, env={"STUB_HANG": "1", "SLATE_ASSISTANT_TIMEOUT": "1.5"})[-1]
        self.assertEqual(e["kind"], "timeout")


class OpenCode(Base):
    def test_detect(self):
        c = self.detect()["opencode"]
        self.assertEqual((c["label"], c["installed"], c["version"], c["signedIn"], c["confined"], c["followUps"]),
                         ("OpenCode", True, "2.2.6", True, True, True))

    def test_an_old_one_asks_first(self):
        """Before 2.2.3 OpenCode can't keep other MCP servers out: not called confined."""
        self.s.env["STUB_VERSION"] = "2.1.0"
        self.assertFalse(self.detect()["opencode"]["confined"])
        e, = self.ask("opencode", OPENCODE)
        self.assertEqual(e["kind"], "not-accepted")
        self.assertEqual(self.ask("opencode", OPENCODE, accepted="opencode")[-1]["type"], "done")

    def test_a_prompt(self):
        events = self.ask("opencode", OPENCODE)
        self.answered(events, "Glass is **off**.", "ses_4f2a1c")
        self.assertEqual([(e["delta"], e.get("fresh", False)) for e in events if e["type"] == "text"],
                         [("Checking.", True), ("Glass is ", True), ("**off**.", False)])

    def test_confined(self):
        """Started in a folder of its own, with Slate's settings there: Slate's server alone,
        an agent that may use Slate's tools and nothing else, and policies to match."""
        self.ask("opencode", OPENCODE)
        got = self.got("opencode")
        work = self.h(".local", "state", "slate", "assistant", "work-opencode")
        self.assertEqual((got["cwd"], got["pwd"]), (work, work))
        self.assertEqual(got["args"][:8], ["run", "--format", "json", "--standalone", "--agent", "nova", "--archived"][:8])
        conf = json.loads(got["files"]["opencode.json"])
        self.assertEqual(list(conf["mcp"]["servers"]), ["slate"])
        server = conf["mcp"]["servers"]["slate"]
        self.assertEqual((server["command"], server["codemode"]), ([mcp_tests.SLATE, "mcp"], False))
        self.assertEqual(server["environment"]["SLATE_ASSISTANT_AGENT"], "OpenCode")
        nova = conf["agents"]["nova"]
        self.assertTrue(nova["system"].startswith("You are Nova"))
        self.assertEqual(nova["permissions"], [{"action": "*", "resource": "*", "effect": "deny"},
                                               {"action": "slate_*", "resource": "*", "effect": "allow"}])
        policies = [(p["action"], p["resource"], p["effect"]) for p in conf["policies"]]
        self.assertEqual(policies, [("mcp.use", "*", "deny"), ("mcp.use", "slate", "allow"), ("websearch.use", "*", "deny"),
                                    ("tool.use", "*", "deny"), ("tool.use", "slate_*", "allow")])
        self.assertNotIn("You are Nova", got["stdin"])
        mode = os.stat(os.path.join(work, "opencode.json")).st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_follow_up_and_model(self):
        self.ask("opencode", OPENCODE, session="ses_4f2a1c", model="anthropic/claude-sonnet-5-5")
        a = self.got("opencode")["args"]
        self.assertEqual((self.after(a, "--session"), self.after(a, "--model")), ("ses_4f2a1c", "anthropic/claude-sonnet-5-5"))

    def test_errors(self):
        for message, kind in (("ProviderAuthError: no credentials for anthropic", "signed-out"),
                              ("Unable to connect. Is the computer able to access the url?", "offline"),
                              ("Session failed", "failed")):
            with self.subTest(kind):
                stream = lines({"type": "error", "timestamp": 1, "sessionID": "ses_1", "error": {"type": "unknown", "message": message}})
                e = self.ask("opencode", stream, env={"STUB_EXIT": "1"})[-1]
                self.assertEqual((e["type"], e["kind"]), ("error", kind))
        e = self.ask("opencode", "", env={"STUB_EXIT": "1", "STUB_ERR": "boom"})[-1]
        self.assertEqual((e["kind"], e["detail"]), ("failed", "boom"))


class Goose(Base):
    def test_detect(self):
        c = self.detect()["goose"]
        self.assertEqual((c["label"], c["installed"], c["version"], c["signedIn"], c["confined"]), ("Goose", True, "1.54.0", False, True),
                         "no provider set up yet")
        os.makedirs(self.h(".config", "goose"))
        with open(self.h(".config", "goose", "config.yaml"), "w") as f:
            f.write("GOOSE_MODEL: qwen3\nGOOSE_PROVIDER: ollama\n")
        c = self.detect()["goose"]
        self.assertEqual((c["signedIn"], c["confined"]), (True, True))

    def test_an_agent_as_its_provider(self):
        """A provider that is itself an agent with tools brings them along: not confined."""
        self.s.env["GOOSE_PROVIDER"] = "claude-code"
        self.assertFalse(self.detect()["goose"]["confined"])
        self.assertEqual(self.ask("goose", GOOSE)[0]["kind"], "not-accepted")

    def test_a_prompt(self):
        events = self.ask("goose", GOOSE)
        self.answered(events, "Glass is **off**.", "slate-nova-r1")
        self.assertEqual([(e["delta"], e.get("fresh", False)) for e in events if e["type"] == "text"],
                         [("Let me check.", False), ("Glass is ", True), ("**off**.", False)])

    def test_confined(self):
        """None of the person's extensions (--no-profile), Slate's server as the only one, a
        session Slate names, and the briefing as extra system instructions."""
        self.ask("goose", GOOSE)
        got = self.got("goose")
        a = got["args"]
        self.assertEqual(a[:5], ["run", "-i", "-", "--output-format", "stream-json"])
        self.assertIn("--no-profile", a)
        self.assertNotIn("--with-builtin", a)
        self.assertEqual(self.after(a, "--with-extension"), "slate:%s mcp" % mcp_tests.SLATE)
        self.assertEqual(self.after(a, "-n"), "slate-nova-r1")
        self.assertTrue(self.after(a, "--system").startswith("You are Nova"))
        self.assertNotIn("--resume", a)
        self.assertEqual(got["env"]["GOOSE_MODE"], "auto")
        self.assertEqual((got["env"]["SLATE_ASSISTANT_RUN"], got["env"]["SLATE_ASSISTANT_AGENT"]), ("r1", "Goose"))
        self.assertTrue(got["stdin"].endswith("is glass on?"))

    def test_follow_up(self):
        """A follow-up resumes the session by its name; the session keeps Slate's server."""
        events = self.ask("goose", GOOSE, session="slate-nova-r0", model="qwen3")
        self.assertEqual(events[0], {"type": "start", "session": "slate-nova-r0"})
        a = self.got("goose")["args"]
        self.assertEqual(self.after(a, "-n"), "slate-nova-r0")
        self.assertIn("--resume", a)
        self.assertNotIn("--with-extension", a)
        self.assertEqual(self.after(a, "--model"), "qwen3")

    def test_errors(self):
        auth = lines({"type": "message", "message": {"id": "a", "role": "assistant", "created": 1,
                      "content": [{"type": "error", "kind": "authentication", "message": "Invalid API key"}], "metadata": {}}})
        self.assertEqual(self.ask("goose", auth)[-1]["kind"], "signed-out")
        self.assertIn("goose configure", self.ask("goose", auth)[-1]["message"])
        e = self.ask("goose", lines({"type": "error", "error": "error sending request: connection refused"}), env={"STUB_EXIT": "1"})[-1]
        self.assertEqual(e["kind"], "offline")
        e = self.ask("goose", "", env={"STUB_EXIT": "1", "STUB_ERR": "No provider configured. Run 'goose configure' first"})[-1]
        self.assertEqual(e["kind"], "signed-out")


class Antigravity(Base):
    def test_detect(self):
        c = self.detect()["antigravity"]
        self.assertEqual((c["label"], c["installed"], c["version"], c["confined"], c["signIn"]), ("Antigravity", True, "1.4.4", False, "agy"))
        self.assertIn("mcp(slate/*)", c["note"])

    def test_asks_first(self):
        """It keeps its own tools: not run until you've said yes to it."""
        e, = self.ask("antigravity", AGY)
        self.assertEqual(e["kind"], "not-accepted")
        self.assertFalse(os.path.exists(os.path.join(self.s.dir, "agy.got")))

    def test_a_prompt(self):
        events = self.ask("antigravity", AGY, accepted="antigravity")
        self.answered(events, "Glass is **off**.", "c3b66b04-872b-4fbe-a3a4-058a026ef20a")
        got = self.got("agy")
        self.assertEqual(got["args"][:4], ["--input-format", "stream-json", "--output-format", "stream-json"])
        self.assertNotIn("-p", got["args"])
        message = json.loads(got["stdin"])
        self.assertEqual(message["event"], "user")
        text = message["message"]["content"]
        self.assertTrue(text.startswith("You are Nova"), "no system prompt of its own: the briefing goes above the prompt")
        self.assertTrue(text.endswith("is glass on?"))
        conf = json.loads(got["files"][os.path.join(".agents", "mcp_config.json")])
        self.assertEqual(conf["mcpServers"]["slate"]["command"], mcp_tests.SLATE)
        self.assertEqual(got["cwd"], self.h(".local", "state", "slate", "assistant", "work-antigravity"))

    def test_follow_up(self):
        self.ask("antigravity", AGY, accepted="antigravity", session="c3b66b04", model="gemini-3.8-flash-medium")
        a = self.got("agy")["args"]
        self.assertEqual((self.after(a, "--conversation"), self.after(a, "--model")), ("c3b66b04", "gemini-3.8-flash-medium"))
        self.assertFalse(json.loads(self.got("agy")["stdin"])["message"]["content"].startswith("You are Nova"),
                         "the briefing went again on a follow-up")

    def test_errors(self):
        for error, kind in (("authentication required", "signed-out"), ("RESOURCE_EXHAUSTED: quota", "failed"),
                            ("UNAVAILABLE: connection reset", "offline")):
            with self.subTest(kind):
                stream = lines({"event": "result", "result": {"conversation_id": "", "status": "ERROR", "response": "", "error": error}})
                e = self.ask("antigravity", stream, accepted="antigravity", env={"STUB_EXIT": "1"})[-1]
                self.assertEqual((e["type"], e["kind"]), ("error", kind))


class FakeOllama:
    """Ollama's HTTP API as far as Slate uses it: /api/tags lists `models`, and each /api/chat
    streams the next of `replies` (a list of messages; a message with tool_calls asks for
    tools). What was asked is kept in `asked`."""

    def __init__(self, models, replies):
        self.models, self.replies, self.asked = models, list(replies), []
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def send(self, code, body):
                self.send_response(code)
                self.send_header("Content-Type", "application/x-ndjson")
                self.end_headers()
                self.wfile.write(body.encode("utf-8"))

            def do_GET(self):
                if self.path == "/api/tags":
                    return self.send(200, json.dumps({"models": fake.models}))
                self.send(404, "{}")

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                fake.asked.append(body)
                reply = fake.replies.pop(0) if len(fake.replies) > 1 else fake.replies[0]
                chunks = []
                words = reply.get("content", "")
                for i in range(0, len(words), 6):           # (a few words at a time, as it streams)
                    chunks.append({"model": body["model"], "message": {"role": "assistant", "content": words[i:i + 6]}, "done": False})
                if reply.get("tool_calls"):
                    chunks.append({"model": body["model"], "message": {"role": "assistant", "content": "", "tool_calls": reply["tool_calls"]}, "done": False})
                chunks.append({"model": body["model"], "message": {"role": "assistant", "content": ""}, "done": True, "done_reason": "stop"})
                self.send(200, "".join(json.dumps(c) + "\n" for c in chunks))

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


MODELS = [{"name": "qwen3:8b", "model": "qwen3:8b", "size": 5225388164, "capabilities": ["completion", "tools", "thinking"]},
          {"name": "gemma3:1b", "model": "gemma3:1b", "size": 815319791, "capabilities": ["completion"]},
          {"name": "gpt-oss:120b-cloud", "model": "gpt-oss:120b-cloud", "remote_model": "gpt-oss:120b", "remote_host": "https://ollama.com:443",
           "size": 384, "capabilities": ["completion", "tools"]}]


def call(name, **args):
    return {"id": "call_1", "function": {"index": 0, "name": name, "arguments": args}}


class Ollama(Base):
    def setUp(self):
        super().setUp()
        self.s.add("ollama", missing=True)

    def serve(self, replies, models=MODELS):
        fake = FakeOllama(models, replies)
        self.addCleanup(fake.close)
        self.s.env["SLATE_OLLAMA_URL"] = fake.url
        return fake

    def test_detect(self):
        """Its models, without those that run on Ollama's servers; and whether it's running."""
        a = self.detect()["ollama"]
        self.assertEqual((a["installed"], a["running"], a["signedIn"]), (False, False, False))
        self.serve([{}])
        a = self.detect()["ollama"]
        self.assertEqual((a["installed"], a["running"], a["signedIn"], a["confined"], a["local"]), (True, True, True, True, True))
        self.assertEqual([(m["name"], m["tools"]) for m in a["models"]], [("qwen3:8b", True), ("gemma3:1b", False)])
        self.serve([{}], models=[])
        a = self.detect()["ollama"]
        self.assertEqual((a["running"], a["signedIn"], a["models"]), (True, False, []))

    def test_a_tool_round(self):
        """The model asks for a tool; Slate calls it through its own server (and gate), hands the
        answer back, and the model's words are the answer."""
        fake = self.serve([{"content": "Let me look.", "tool_calls": [call("settings_get", key="glass")]},
                           {"content": "Glass is **off** at the moment."}])
        events = self.ask("ollama")
        session = events[0]["session"]
        self.assertRegex(session, r"^[0-9a-f]{32}$")
        self.answered(events, "Glass is **off** at the moment.", session)
        texts = [e for e in events if e["type"] == "text"]
        self.assertTrue(texts[0]["fresh"])
        self.assertEqual("".join(e["delta"] for e in texts), "Let me look.Glass is **off** at the moment.")
        self.assertEqual([e.get("fresh", False) for e in texts if e["delta"].startswith("Glass")], [True])
        first, second = fake.asked
        self.assertEqual(first["model"], "qwen3:8b", "the first model that can use tools")
        self.assertTrue(first["stream"])
        self.assertEqual(first["messages"][0]["role"], "system")
        self.assertTrue(first["messages"][0]["content"].startswith("You are Nova"))
        self.assertIn("Find a setting with settings_search", first["messages"][0]["content"])
        self.assertEqual(first["messages"][-1]["role"], "user")
        self.assertTrue(first["messages"][-1]["content"].endswith("</slate-context>\n\nis glass on?"))
        names = [t["function"]["name"] for t in first["tools"]]
        self.assertIn("settings_set", names)
        self.assertEqual(first["tools"][0]["type"], "function")
        self.assertIn("properties", first["tools"][names.index("settings_get")]["function"]["parameters"])
        said = second["messages"][-1]
        self.assertEqual((said["role"], said["tool_name"]), ("tool", "settings_get"))
        self.assertEqual(json.loads(said["content"])["value"], True)
        self.assertEqual(second["messages"][-2]["tool_calls"][0]["function"]["name"], "settings_get")
        # Through Slate's own server: the gate was asked, and the activity log has it
        self.assertEqual([(a["tool"], a["who"]) for a in self.activity()], [("settings_get", "Ollama (on this computer)")])

    def test_a_change_through_the_gate(self):
        self.serve([{"tool_calls": [call("settings_set", key="glass", value=False)]}, {"content": "Glass is off."}])
        self.assertEqual(self.ask("ollama", prompt="turn off glass")[-1]["text"], "Glass is off.")
        self.assertEqual(self.setting("glass"), False)

    def test_a_plain_answer_and_a_follow_up(self):
        fake = self.serve([{"content": "Hello. What can I do on your desktop?"}])
        events = self.ask("ollama", prompt="hi", model="gemma3:1b")
        session = events[-1]["session"]
        self.assertEqual(events[-1]["text"], "Hello. What can I do on your desktop?")
        self.assertEqual(fake.asked[0]["model"], "gemma3:1b")
        kept = self.h(".local", "state", "slate", "assistant", "ollama", session + ".json")
        self.assertEqual(os.stat(kept).st_mode & 0o777, 0o600)
        # A follow-up carries the conversation on, and keeps its session
        events = self.ask("ollama", prompt="and again", session=session)
        self.assertEqual(events[0]["session"], session)
        msgs = fake.asked[-1]["messages"]
        self.assertEqual([m["role"] for m in msgs], ["system", "user", "assistant", "user"])
        self.assertTrue(msgs[1]["content"].endswith("hi"))
        # One that's been forgotten starts afresh
        events = self.ask("ollama", prompt="x", session="0" * 32)
        self.assertNotEqual(events[0]["session"], "0" * 32)

    def test_not_running(self):
        e, = self.ask("ollama")
        self.assertEqual((e["kind"], e["message"]), ("not-installed", "Slate couldn't find Ollama (on this computer). It may have been removed."))
        self.s.add("ollama", stdout="ollama version is 0.40.16")      # (installed, but not running)
        e, = self.ask("ollama")
        self.assertEqual(e["kind"], "offline")
        self.assertTrue(e["message"].startswith("Ollama isn't running."))

    def test_no_models(self):
        self.serve([{}], models=[])
        e, = self.ask("ollama")
        self.assertEqual(e["kind"], "not-installed")
        self.assertIn("ollama pull qwen3", e["message"])
        self.serve([{}])
        e, = self.ask("ollama", model="llama9")
        self.assertIn("doesn't have llama9", e["message"])

    def test_never_a_cloud_model(self):
        """A model that runs on Ollama's servers would take what you ask off the computer."""
        fake = self.serve([{"content": "hi"}])
        e, = self.ask("ollama", model="gpt-oss:120b-cloud")
        self.assertEqual(e["kind"], "not-installed")
        self.assertIn("runs on Ollama's servers", e["message"])
        self.assertEqual(fake.asked, [])

    def test_round_cap(self):
        """A model that keeps calling tools is stopped after a few rounds."""
        fake = self.serve([{"tool_calls": [call("settings_get", key="glass")]}])
        e = self.ask("ollama", env={"SLATE_OLLAMA_ROUNDS": "3"})[-1]
        self.assertEqual((e["type"], e["kind"]), ("error", "failed"))
        self.assertIn("stopped it after 3 rounds", e["message"])
        self.assertEqual(len(fake.asked), 3)

    def test_odd_tool_calls(self):
        """A tool that doesn't exist, or arguments that aren't an object, go back as words."""
        fake = self.serve([{"tool_calls": [call("run_shell", command="ls")]},
                           {"tool_calls": [{"function": {"name": "settings_get", "arguments": "[1]"}}]},
                           {"content": "Sorry."}])
        self.assertEqual(self.ask("ollama")[-1]["text"], "Sorry.")
        self.assertTrue(fake.asked[1]["messages"][-1]["content"].startswith("There's no tool called run_shell."))
        self.assertEqual(fake.asked[2]["messages"][-1]["content"], "Error: the arguments have to be a JSON object.")
        self.assertEqual(self.activity(), [])

    def test_slate_off(self):
        """While assistants are off, nothing is sent to the model."""
        fake = self.serve([{"content": "hi"}])
        self.put_state(enabled=False)
        self.assertEqual(self.ask("ollama")[0]["kind"], "off")
        self.assertEqual(fake.asked, [])

    def test_never_in_test_mode(self):
        fake = self.serve([{"content": "hi"}])
        e, = self.ask("ollama", env={"SLATE_TEST": "1"})
        self.assertEqual(e["kind"], "not-installed")
        self.assertEqual(fake.asked, [])


class CodexLocal(Base):
    def test_a_prompt(self):
        fake = FakeOllama(MODELS, [{}])
        self.addCleanup(fake.close)
        self.s.env["SLATE_OLLAMA_URL"] = fake.url
        self.s.add("ollama", stdout="ollama version is 0.40.16")
        a = self.detect()["codex-local"]
        self.assertEqual((a["installed"], a["signedIn"], a["followUps"], a["local"]), (True, True, False, True))
        events = self.ask("codex-local", CODEX)
        self.assertEqual(events[-1]["type"], "done")
        args = self.got("codex")["args"]
        self.assertEqual(args[args.index("--local-provider") - 1:args.index("--local-provider") + 2], ["--oss", "--local-provider", "ollama"])
        self.assertEqual(self.after(args, "-m"), "qwen3:8b")
        self.assertIn("features.shell_tool=false", args)
        self.assertEqual(fake.asked, [], "Codex talks to Ollama itself")
        # Ollama's default room runs out after a tool or two (seen with codex-cli 0.169 and qwen3:8b)
        small = '{"error":{"message":"request (4264 tokens) exceeds the available context size (4096 tokens), try increasing it"}}'
        e = self.ask("codex-local", lines({"type": "thread.started", "thread_id": "t"}, {"type": "turn.failed", "error": {"message": small}}))[-1]
        self.assertEqual(e["kind"], "failed")
        self.assertIn("OLLAMA_CONTEXT_LENGTH", e["message"])


class Detect(Base):
    def test_every_agent(self):
        a = self.detect()
        self.assertEqual(list(a), ["claude", "codex", "opencode", "goose", "antigravity", "ollama", "codex-local", "custom"])
        self.assertEqual({k: v["confined"] for k, v in a.items()},
                         {"claude": True, "codex": True, "opencode": True, "goose": True, "antigravity": False,
                          "ollama": True, "codex-local": True, "custom": False})
        for k, v in a.items():
            if k != "custom":
                self.assertTrue(v["url"].startswith("https://"), k)
                self.assertTrue(v["note"] and v["signIn"], k)
        self.assertEqual([k for k, v in a.items() if v["local"]], ["ollama", "codex-local"])

    def test_none_installed(self):
        for name in VERSIONS:
            os.remove(os.path.join(self.s.dir, name))
            self.s.add(name, missing=True)
        self.s.add("ollama", missing=True)
        a = self.detect()
        for k in ("codex", "opencode", "goose", "antigravity", "ollama", "codex-local"):
            self.assertEqual((a[k]["installed"], a[k]["signedIn"]), (False, False), k)
