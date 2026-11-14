#!/usr/bin/env python3
"""Nova with a model on this computer: Slate runs the agent itself, talking to Ollama's own
HTTP API on this computer and to Slate's MCP server as a client (docs/ASSISTANT.md). Started
by scripts/assistant.py like any agent; nothing here reaches anything but 127.0.0.1.

    ollama-agent.py --model <m> --session <s> --briefing <file> --mcp-config <file> --state <dir>
        the prompt on stdin; Slate's runner events on stdout, one JSON object per line:
        start, text (fresh: a new message), done, error (offline, not-installed, server, failed)

A run: Slate's MCP server is started (`slate mcp`, as the config file says) and its tools are
listed; the model is sent the briefing and the server's instructions as its system prompt,
the conversation so far (a follow-up's) and the prompt, with Slate's tools in Ollama's form.
While it answers with tool calls, each is made through Slate's server (so through Slate's
gate) and the answers go back to it; it stops when the model answers in words, or after
ROUNDS rounds. The conversation is kept for follow-ups in <state>/ollama/<session>.json (on
this computer, only you can read it), and forgotten after a day.

Models that run on Ollama's servers rather than this computer ("cloud" models) are refused:
with them, what you ask would leave the computer. Standard library only.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import slate_agents  # noqa: E402

ROUNDS = int(os.environ.get("SLATE_OLLAMA_ROUNDS") or 8)    # tool rounds before Slate stops it
KEEP_MESSAGES = 40                                           # of a conversation, for follow-ups
KEEP_FOR = 24 * 3600                                         # seconds a conversation is kept
SUGGESTED = "qwen3"                                          # a small model that's good with tools
WAIT = 600                    # seconds for a word from the model (on a processor alone it reads slowly)
# Room for the whole conversation: Slate's tools alone are some 5,000 tokens, and Ollama's own
# default (4,096) would quietly cut the start of it off, the briefing with it
CONTEXT = int(os.environ.get("SLATE_OLLAMA_CONTEXT") or 16384)


def emit(**event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


class Stop(Exception):
    """The run ends with this error event."""

    def __init__(self, kind, message, detail=""):
        super().__init__(message)
        self.event = {"type": "error", "kind": kind, "message": message}
        if detail:
            self.event["detail"] = str(detail)[-300:]


NOT_RUNNING = Stop("offline", "Ollama isn't running. Start it (ollama serve, or its service), then try again.")
TOO_SLOW = Stop("timeout", "The model took too long to answer. Anything already done is listed below. A smaller model answers more quickly.")


class Mcp:
    """Slate's MCP server, spoken to as a client over stdio (2025-11-25: initialize first)."""

    def __init__(self, command, args, env):
        self.proc = subprocess.Popen([command] + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, env=dict(os.environ, **env), text=True, bufsize=1)
        self.n = 0
        self.lock = threading.Lock()

    def ask(self, method, params=None, timeout=90):
        with self.lock:
            self.n += 1
            mid = self.n
            try:
                self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": mid, "method": method, "params": params or {}}) + "\n")
                self.proc.stdin.flush()
            except OSError:
                raise Stop("server", "The assistant couldn't reach Slate. Restarting Slate usually fixes this.")
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                line = self.proc.stdout.readline()
                if not line:
                    break
                try:
                    reply = json.loads(line)
                except ValueError:
                    continue
                if isinstance(reply, dict) and reply.get("id") == mid:
                    if "error" in reply:
                        raise Stop("server", "The assistant couldn't reach Slate. Restarting Slate usually fixes this.",
                                   (reply["error"] or {}).get("message", ""))
                    return reply.get("result") or {}
            raise Stop("server", "The assistant couldn't reach Slate. Restarting Slate usually fixes this.")

    def tell(self, method):
        try:
            self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
            self.proc.stdin.flush()
        except OSError:
            pass

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            self.proc.kill()


def ollama(path, body=None, timeout=None):
    """A request to Ollama: the response, open for reading."""
    req = urllib.request.Request(slate_agents.ollama_url() + path, method="POST" if body is not None else "GET",
                                 data=json.dumps(body).encode("utf-8") if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    try:
        return urllib.request.urlopen(req, timeout=timeout or WAIT)
    except urllib.error.HTTPError as e:
        try:
            why = json.loads(e.read().decode("utf-8")).get("error", "")
        except (ValueError, OSError, AttributeError):
            why = ""
        raise OllamaError(e.code, str(why))
    except TimeoutError:
        raise TOO_SLOW
    except urllib.error.URLError as e:
        raise TOO_SLOW if isinstance(e.reason, TimeoutError) else NOT_RUNNING
    except OSError:
        raise NOT_RUNNING


class OllamaError(Exception):
    def __init__(self, code, why):
        super().__init__(why)
        self.code, self.why = code, why


def choose_model(wanted):
    """The model to use: the one chosen, or (none chosen) the first that can use tools."""
    models = slate_agents.ollama_models()
    if models is None:
        raise NOT_RUNNING
    if not models:
        raise Stop("not-installed", "Ollama doesn't have a model yet. Open a terminal and run ollama pull %s, then try again." % SUGGESTED)
    if wanted:
        found = next((m for m in models if m["name"] == wanted or m["name"] == wanted + ":latest"), None)
        if found is None:
            if re.search(r"[-:]cloud\b", wanted):
                raise Stop("not-installed", "%s runs on Ollama's servers, not this computer, so Slate won't use it. "
                           "Choose another model in Settings → Assistant." % wanted)
            raise Stop("not-installed", "Ollama doesn't have %s on this computer. Choose another model in Settings → Assistant, "
                       "or run ollama pull %s." % (wanted, wanted))
        return found["name"]
    return next((m["name"] for m in models if m["tools"]), models[0]["name"])


def as_tools(tools):
    """Slate's MCP tools in Ollama's form."""
    out = []
    for t in tools:
        if isinstance(t, dict) and isinstance(t.get("name"), str):
            out.append({"type": "function", "function": {
                "name": t["name"], "description": str(t.get("description") or t.get("title") or ""),
                "parameters": t.get("inputSchema") if isinstance(t.get("inputSchema"), dict) else {"type": "object", "properties": {}}}})
    return out


def tool_text(result):
    """What a tool answered, as the words the model gets back."""
    words = [c.get("text", "") for c in result.get("content") or [] if isinstance(c, dict) and c.get("type") == "text"]
    text = "\n".join(w for w in words if w) or "Done."
    return ("Error: " + text) if result.get("isError") else text


def sessions_dir(state):
    return os.path.join(state, "ollama")


def session_path(state, session):
    return os.path.join(sessions_dir(state), re.sub(r"[^\w-]", "", session) + ".json")


def load(state, session):
    """A follow-up's conversation so far ([] if there's none, or it's been forgotten)."""
    if not session:
        return []
    try:
        with open(session_path(state, session), encoding="utf-8") as fh:
            msgs = json.load(fh).get("messages")
        return [m for m in msgs if isinstance(m, dict) and m.get("role") in ("user", "assistant", "tool")] if isinstance(msgs, list) else []
    except (OSError, ValueError, AttributeError):
        return []


def save(state, session, messages):
    kept = messages[-KEEP_MESSAGES:]
    while kept and kept[0].get("role") != "user":          # (start at a prompt, never mid-round)
        kept = kept[1:]
    slate_agents.write_json(session_path(state, session), {"messages": kept})
    now = time.time()
    try:
        for name in os.listdir(sessions_dir(state)):
            p = os.path.join(sessions_dir(state), name)
            if now - os.path.getmtime(p) > KEEP_FOR:
                os.remove(p)
    except OSError:
        pass


def chat(model, messages, tools, think):
    """One round with the model: its words go out as they come; (words, tool calls)."""
    body = {"model": model, "messages": messages, "tools": tools, "stream": True, "options": {"num_ctx": CONTEXT}}
    if think is not None:
        body["think"] = think
    words, calls, fresh = "", [], True
    with ollama("/api/chat", body) as r:
        for raw in reading(r):
            try:
                d = json.loads(raw.decode("utf-8"))
            except ValueError:
                continue
            if d.get("error"):
                raise OllamaError(500, str(d["error"]))
            m = d.get("message") or {}
            if isinstance(m.get("content"), str) and m["content"]:
                out = {"type": "text", "delta": m["content"]}
                if fresh:
                    out["fresh"], fresh = True, False
                emit(**out)
                words += m["content"]
            for c in m.get("tool_calls") or []:
                if isinstance(c, dict) and isinstance(c.get("function"), dict):
                    calls.append(c)
            if d.get("done"):
                break
    return words, calls


def reading(r):
    """The lines of a streamed answer; a stall is too slow, a dropped connection not running."""
    while True:
        try:
            raw = r.readline()
        except TimeoutError:
            raise TOO_SLOW
        except OSError:
            raise NOT_RUNNING
        if not raw:
            return
        yield raw


def run(args, prompt):
    model = choose_model(args.model)
    with open(args.mcp_config, encoding="utf-8") as fh:
        server = json.load(fh)["mcpServers"]["slate"]
    try:
        with open(args.briefing, encoding="utf-8") as fh:
            briefing = fh.read().strip()
    except OSError:
        briefing = ""
    mcp = Mcp(server["command"], list(server.get("args") or []), dict(server.get("env") or {}))
    try:
        hello = mcp.ask("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                       "clientInfo": {"name": "slate-ollama", "title": "Ollama", "version": "1"}}, timeout=30)
        mcp.tell("notifications/initialized")
        listed = mcp.ask("tools/list", timeout=30).get("tools") or []
        tools = as_tools(listed)
        names = {t["function"]["name"] for t in tools}
        system = "\n\n".join(x for x in (briefing, str(hello.get("instructions") or "")) if x)

        session = args.session if load(args.state, args.session) else uuid.uuid4().hex
        history = load(args.state, args.session)
        emit(type="start", session=session)
        talk = history + [{"role": "user", "content": prompt}]
        think = False                       # (a thinking model is quicker without, and Slate never shows it)
        for _ in range(ROUNDS):
            try:
                words, calls = chat(model, [{"role": "system", "content": system}] + talk, tools, think)
            except OllamaError as e:
                if think is not None and "think" in e.why.lower():
                    think = None            # (a model that can't think says so: ask again without)
                    words, calls = chat(model, [{"role": "system", "content": system}] + talk, tools, think)
                else:
                    raise
            said = {"role": "assistant", "content": words}
            if calls:
                said["tool_calls"] = calls
            talk.append(said)
            if not calls:
                save(args.state, session, talk)
                return emit(type="done", text=words.strip(), session=session)
            for c in calls:
                f = c["function"]
                name = str(f.get("name") or "")
                given = f.get("arguments")
                if isinstance(given, str):
                    try:
                        given = json.loads(given)
                    except ValueError:
                        given = None
                if name not in names:
                    answer = "There's no tool called %s. The tools are: %s." % (name[:60], ", ".join(sorted(names)))
                elif not isinstance(given, dict):
                    answer = "Error: the arguments have to be a JSON object."
                else:
                    answer = tool_text(mcp.ask("tools/call", {"name": name, "arguments": given}, timeout=120))
                talk.append({"role": "tool", "tool_name": name, "content": answer})
        save(args.state, session, talk)
        raise Stop("failed", "The model kept using tools without answering, so Slate stopped it after %d rounds. "
                   "Anything already done is listed below. A bigger model may do better." % ROUNDS)
    finally:
        mcp.close()


def main():
    p = argparse.ArgumentParser(prog="ollama-agent.py")
    p.add_argument("--model", default="")
    p.add_argument("--session", default="")
    p.add_argument("--briefing", default="")
    p.add_argument("--mcp-config", required=True)
    p.add_argument("--state", default="")
    args = p.parse_args()
    args.state = args.state or os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                                            "slate", "assistant")
    prompt = sys.stdin.read().strip()
    try:
        run(args, prompt)
    except Stop as e:
        emit(**e.event)
    except OllamaError as e:
        if e.code == 404:
            emit(type="error", kind="not-installed", message="Ollama doesn't have that model on this computer. "
                 "Choose another one in Settings → Assistant.", detail=e.why[-300:])
        else:
            emit(type="error", kind="failed", message="Ollama couldn't answer that.", detail=e.why[-300:])


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
