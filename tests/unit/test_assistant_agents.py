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
