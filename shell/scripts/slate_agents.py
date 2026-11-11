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
"""
import json
import os
import re
import shutil
import subprocess

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

    def env(self, run):
        return {}

    def parse(self, line, state):
        return []


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
