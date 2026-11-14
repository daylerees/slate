"""The agents Slate's prompt window can hand a prompt to (scripts/assistant.py runs them;
docs/ASSISTANT.md). Each is a command-line agent the person already has and is signed in to:
Slate stores no keys and talks to no service itself.

An agent here says how to find it, whether it's signed in, the command that runs one prompt
with Slate's MCP server as its tools, and how to read what it prints. To add one, write a
class like Claude below and put @agent above it:

    confined   True only when command() leaves the agent with Slate's tools and nothing else
               (its own shell, file and web tools switched off, no other MCP servers). False
               marks it "Keeps its own tools" in Settings, and choosing it asks first.
    briefing   "system": the agent takes a system prompt, and command() gives it the briefing
               file; "prompt": it doesn't, so the briefing goes above the first prompt.
    command(run)  the argument list. run has: model, session (a follow-up's, or ""),
               briefing (a file), mcp_config (the standard {"mcpServers": …} dict),
               mcp_config_file (the same, as a file) and command (the person's own, for custom).
    parse(line, state)  events for one line the agent printed: {"type": "start", "session"},
               {"type": "text", "delta", "fresh"?} (fresh: a new message, replacing the one
               shown), {"type": "done", "text", "session"}, {"type": "error", "kind", "message"}.
               state is a dict the adapter may keep things in between lines.

And, where an agent needs them:

    workspace  True: it runs in a folder of its own (work-<id>), for the files prepare() writes
               there (an agent that reads its settings from the folder it's started in)
    prepare(run)  write those files: run["work"] is the folder
    stdin(text)  what goes on its stdin (the prompt as it is, unless it wants it wrapped)
    opening(run)  events to send as soon as it's started (a start, for an agent that names
               its session itself)
    finish(code, state, errors)  an event once it has exited without saying done or error
               (errors: the last lines it wrote to stderr), or None to say it failed
    timeout    seconds it's given (a model on this computer is slower than a service)
    local      True: it runs a model on this computer (Settings offers its models)
"""
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

AGENTS = []


def agent(cls):
    AGENTS.append(cls())
    return cls


def by_id(agent_id):
    return next((a for a in AGENTS if a.id == agent_id), None)


def find(name):
    """A command on PATH, or where these CLIs install themselves when PATH hasn't caught up
    (Slate's own PATH is the session's, not a terminal's)."""
    extra = [os.path.expanduser(p) for p in ("~/.local/bin", "~/.npm-global/bin", "~/bin")]
    return shutil.which(name, path=os.pathsep.join([os.environ.get("PATH", "")] + extra))


def output(cmd, timeout=10):
    """(exit code, what it printed), or (None, "") if it couldn't be run."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None, ""


class Agent:
    id = ""
    label = ""
    url = ""                # where to get it
    note = ""               # a line for Settings, under its name
    confined = False
    briefing = "prompt"
    follow_ups = True       # it can continue a conversation (a session id comes back)
    sign_in = ""            # what to run in a terminal to sign in

    def installed(self):
        return False

    def version(self):
        return ""

    def signed_in(self):
        return True

    def command(self, run):
        raise NotImplementedError

    workspace = False
    timeout = 120
    local = False

    def env(self, run):
        return {}

    def parse(self, line, state):
        return []

    def prepare(self, run):
        pass

    def stdin(self, text):
        return text

    def opening(self, run):
        return []

    def finish(self, code, state, errors):
        return None

    def more(self):
        """Anything else Settings should know about it (detect)."""
        return {}


def version_in(text):
    """The first x.y.z in what a --version printed."""
    m = re.search(r"\d+\.\d+(?:\.\d+)?", text or "")
    return m.group(0) if m else ""


def at_least(version, wanted):
    try:
        return tuple(int(x) for x in version.split(".")) >= wanted
    except ValueError:
        return False


SIGNED_OUT = re.compile(r"log ?in|logged out|authenticat|unauthori[sz]ed|\b401\b|credential|api.?key|sign(ed)? ?(in|out)|not configured|no provider", re.I)
LIMIT = re.compile(r"quota|rate.?limit|RESOURCE_EXHAUSTED|usage limit|credits? (exhausted|ran out)|\b429\b", re.I)
OFFLINE = re.compile(r"connection|connect\b|disconnected|error sending request|network|fetch failed|ENOTFOUND|ECONN|timed? ?out|offline|unreachable|overloaded|unavailable|\b5\d\d\b|dns", re.I)


def trouble(agent, text, service=None):
    """An agent's own error, in Slate's words: signed out, offline, or simply failed."""
    text = str(text or "")
    if LIMIT.search(text):
        return {"type": "error", "kind": "failed", "message": "%s has reached its limit for now. Try again later." % agent.label,
                "detail": text[-300:]}
    if SIGNED_OUT.search(text):
        return {"type": "error", "kind": "signed-out",
                "message": "%s isn't signed in. Open a terminal and run %s once, then try again." % (agent.label, agent.sign_in or "it")}
    if OFFLINE.search(text):
        return {"type": "error", "kind": "offline",
                "message": "Slate couldn't reach %s just now. Your question is still here: try again in a moment." % (service or agent.label)}
    return {"type": "error", "kind": "failed", "message": "%s stopped unexpectedly." % agent.label, "detail": text[-300:]}


def slate_server(run):
    """Slate's MCP server as the run gives it: (command, args, env)."""
    s = run["mcp_config"]["mcpServers"]["slate"]
    return s["command"], list(s.get("args") or []), dict(s.get("env") or {})


def write_json(path, data):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)


@agent
class Claude(Agent):
    """Claude Code, one prompt at a time (`claude -p`), with every tool of its own switched
    off and only Slate's server given: checked against 2.1.319. Slate's server is passed for
    the run alone (--strict-mcp-config, --mcp-config), so nothing in the person's own Claude
    Code setup changes; --restricted keeps their settings files (and so their hooks) out of
    it, and their subscription login still works with it. Not --bare: that needs an API key."""
    id = "claude"
    label = "Claude Code"
    url = "https://claude.com/claude-code"
    note = "Slate switches off its own tools, so it works through Slate's alone"
    confined = True
    briefing = "system"
    sign_in = "claude"

    def installed(self):
        return bool(find("claude"))

    def version(self):
        code, out = output([find("claude") or "claude", "--version"])
        return out.split()[0] if code == 0 and out else ""

    def signed_in(self):
        code, out = output([find("claude") or "claude", "auth", "status"])
        if code != 0:
            return False
        try:
            return bool(json.loads(out).get("loggedIn"))
        except (ValueError, AttributeError):
            return True

    def command(self, run):
        cmd = [find("claude") or "claude", "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
               "--strict-mcp-config", "--mcp-config", json.dumps(run["mcp_config"]),
               "--tools", "", "--allowedTools", "mcp__slate__*", "--permission-mode", "dontAsk",
               "--restricted", "--disable-slash-commands", "--system-prompt-file", run["briefing"]]
        if run.get("model"):
            cmd += ["--model", run["model"]]
        if run.get("session"):
            cmd += ["--resume", run["session"]]
        return cmd

    def parse(self, line, state):
        try:
            d = json.loads(line)
        except ValueError:
            return []
        if not isinstance(d, dict):
            return []
        kind = d.get("type")
        if kind == "system" and d.get("subtype") == "init":
            servers = {s.get("name"): s.get("status") for s in d.get("mcp_servers") or [] if isinstance(s, dict)}
            if servers.get("slate") not in ("connected", "pending"):
                return [{"type": "error", "kind": "server",
                         "message": "The assistant started but couldn't reach Slate. Restarting Slate usually fixes this."}]
            return [{"type": "start", "session": str(d.get("session_id") or "")}]
        if kind == "stream_event":
            event = d.get("event") or {}
            if event.get("type") == "message_start":
                state["fresh"] = True           # a new message: the one before it was said on the way
            delta = event.get("delta") or {}
            if event.get("type") == "content_block_delta" and delta.get("type") == "text_delta" and delta.get("text"):
                out = {"type": "text", "delta": delta["text"]}
                if state.pop("fresh", False):
                    out["fresh"] = True
                return [out]
            return []
        if kind == "result":
            text = d.get("result") if isinstance(d.get("result"), str) else ""
            if d.get("is_error") or d.get("subtype") != "success":
                if re.search(r"log ?in|authenticat|401|credential|sign(ed)? ?(in|out)", text, re.I) or d.get("api_error_status") == 401:
                    return [{"type": "error", "kind": "signed-out",
                             "message": "Claude Code isn't signed in. Open a terminal and run claude once, then try again."}]
                if re.search(r"connection|network|fetch failed|ENOTFOUND|ECONN|timed? ?out|offline|overloaded|5\d\d", text, re.I):
                    return [{"type": "error", "kind": "offline",
                             "message": "Slate couldn't reach Claude just now. Your question is still here: try again in a moment."}]
                return [{"type": "error", "kind": "failed", "message": "Claude Code stopped unexpectedly.", "detail": text[-300:]}]
            return [{"type": "done", "text": text, "session": str(d.get("session_id") or "")}]
        return []


def briefing_text(run):
    try:
        with open(run["briefing"], encoding="utf-8") as fh:
            return fh.read().strip()
    except (OSError, KeyError):
        return ""


def toml(value):
    """A value for `codex -c key=value`, written as TOML (JSON's strings, lists and numbers are
    TOML's too; tables are written inline)."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, dict):
        return "{" + ", ".join("%s = %s" % (json.dumps(k), toml(v)) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "[" + ", ".join(toml(v) for v in value) + "]"
    return json.dumps(value, ensure_ascii=False)


@agent
class Codex(Agent):
    """OpenAI's Codex CLI, one prompt at a time (`codex exec --json`), checked against
    codex-cli 0.169 and its configuration reference. Everything is given for the run alone with
    -c, and --ignore-user-config leaves the person's config.toml (their MCP servers, profiles
    and hooks) out of it, so nothing in their own setup changes; their sign-in still works.
    Its own tools are switched off: commands (features.shell_tool), web search, images,
    subagents, apps, plugins, browser and computer use, memories and bundled skills; what's
    left (editing files) meets a read-only sandbox and never asks. Slate's tools run without
    Codex asking (Slate's own gate asks), and the briefing is its developer instructions."""
    id = "codex"
    label = "Codex"
    url = "https://developers.openai.com/codex/cli"
    note = "Slate switches off its own tools, so it works through Slate's alone"
    confined = True
    briefing = "system"
    sign_in = "codex login"
    OFF = ["shell_tool", "view_image", "multi_agent", "apps", "plugins", "remote_plugin", "memories", "browser_use",
           "computer_use", "hooks", "goals"]

    def installed(self):
        return bool(find("codex"))

    def version(self):
        code, out = output([find("codex") or "codex", "--version"])
        return version_in(out) if code == 0 else ""

    def signed_in(self):
        code, _ = output([find("codex") or "codex", "login", "status"])
        return code == 0

    def settings(self, run):
        cmd, args, env = slate_server(run)
        pairs = [("mcp_servers.slate.command", cmd), ("mcp_servers.slate.args", args), ("mcp_servers.slate.env", env),
                 ("mcp_servers.slate.required", True), ("mcp_servers.slate.default_tools_approval_mode", "approve"),
                 ("developer_instructions", briefing_text(run)), ("approval_policy", "never"),
                 ("sandbox_mode", "read-only"), ("web_search", "disabled"), ("skills.bundled.enabled", False)]
        pairs += [("features." + f, False) for f in self.OFF]
        out = []
        for key, value in pairs:
            out += ["-c", "%s=%s" % (key, toml(value))]
        return out

    def options(self, run):
        opts = ["--json", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules"] + self.settings(run)
        if run.get("model"):
            opts += ["-m", run["model"]]
        return opts

    def command(self, run):
        codex = find("codex") or "codex"
        if run.get("session"):
            return [codex, "exec", "resume"] + self.options(run) + [run["session"], "-"]
        return [codex, "exec"] + self.options(run) + ["-"]

    def parse(self, line, state):
        try:
            d = json.loads(line)
        except ValueError:
            return []
        if not isinstance(d, dict):
            return []
        kind = d.get("type")
        if kind == "thread.started":
            state["session"] = str(d.get("thread_id") or "")
            return [{"type": "start", "session": state["session"]}]
        if kind in ("item.started", "item.updated", "item.completed"):
            item = d.get("item") or {}
            if item.get("type") != "agent_message" or not isinstance(item.get("text"), str):
                return []
            text, out = item["text"], {"type": "text"}
            if item.get("id") != state.get("item"):
                state["item"], state["sent"] = item.get("id"), ""
                out["fresh"] = True             # a new message: the one before was said on the way
            sent = state["sent"]
            if not text.startswith(sent):
                out["fresh"], sent = True, ""
            state["sent"] = state["answer"] = text
            if len(text) == len(sent) and not out.get("fresh"):
                return []
            out["delta"] = text[len(sent):]
            return [out]
        if kind == "turn.completed":
            return [{"type": "done", "text": state.get("answer", ""), "session": state.get("session", "")}]
        if kind == "turn.failed":
            return [self.trouble(str((d.get("error") or {}).get("message") or state.get("error") or ""))]
        if kind == "error":
            state["error"] = str(d.get("message") or "")       # (it may still carry on: reconnecting)
        return []

    def trouble(self, text):
        if re.search(r"\bmcp\b", text, re.I) and "slate" in text.lower():
            return {"type": "error", "kind": "server",
                    "message": "The assistant started but couldn't reach Slate. Restarting Slate usually fixes this."}
        return trouble(self, text, "OpenAI")

    def finish(self, code, state, errors):
        text = state.get("error") or (errors[-1] if errors else "")
        return self.trouble(text) if text and code != 0 else None


@agent
class Custom(Agent):
    """A command of your own: Slate runs it as typed, with the prompt on its stdin, and shows
    whatever it prints. Where to find Slate's MCP server is in its environment. One prompt,
    one answer. Slate can't confine a command it didn't write."""
    id = "custom"
    label = "A command of your own"
    note = "Slate runs it as you typed it. What it can see and do beyond Slate's tools is up to the command"
    confined = False
    briefing = "prompt"
    follow_ups = False

    def installed(self):
        return True

    def command(self, run):
        return ["sh", "-c", run.get("command") or "exit 127"]

    def env(self, run):
        return {"SLATE_MCP_COMMAND": " ".join(run["mcp_command"]), "SLATE_MCP_CONFIG": run["mcp_config_file"],
                "SLATE_ASSISTANT_BRIEFING": run["briefing"], "SLATE_ASSISTANT_CONTEXT": run["context_file"]}

    def parse(self, line, state):
        state["text"] = state.get("text", "") + line + "\n"
        return [{"type": "text", "delta": line + "\n"}]

    def finish(self, code, state, errors):
        if code == 0:
            return {"type": "done", "text": state.get("text", "").strip(), "session": ""}
        return None
