#!/usr/bin/env python3
"""Hand a prompt from Slate's prompt window to the agent the person chose, and say what
comes back in one form whichever agent it is (docs/ASSISTANT.md, plans/assistant.md).

    assistant.py detect
        the agents Slate knows (scripts/slate_agents.py), as JSON for Settings:
        [{"id", "label", "installed", "version", "signedIn", "confined", "followUps", "url",
          "note", "signIn"}]
    assistant.py run --agent <id> --run <id> [--model <m>] [--session <s>]
                     [--command <your own>] [--bare] [--accepted <id,id>]
        the prompt on stdin; one JSON object per line on stdout:
          {"type": "start", "session": …}
          {"type": "text", "delta": …, "fresh": true?}     (fresh: replaces what's shown)
          {"type": "done", "text": …, "session": …}
          {"type": "error", "kind": …, "message": …}
        kinds: off (assistants aren't switched on), not-installed, not-accepted (an agent that
        keeps its own tools, not yet said yes to), signed-out, offline, timeout, stopped,
        server (Slate's MCP server couldn't be reached), failed.
    assistant.py briefing
        what Slate adds to a prompt, as JSON {"briefing", "context"}: for Settings to show

Slate adds two things to what the person typed, both written here and never by the agent:
the briefing (data/assistant-prompt.md, its [nova] and [shared] blocks: who the agent is
here and how to behave) and "right now" (a few lines on the moment: the time, the focused
window). Right now holds only what the status tool would answer anyway, under the same
switches, and never the user's name, host name or home folder.

The agent runs in an empty folder of its own, so no project's instructions are picked up,
with Slate's MCP server as its tools. It's stopped (SIGINT, then SIGTERM, to its whole
process group) when this is, and after two minutes. With SLATE_TEST=1 a real agent is
never started (it would reach the network): only "custom", or the one a test names in
SLATE_ASSISTANT_TEST_AGENT.
"""
import argparse
import importlib
import json
import os
import queue
import re
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SLATE_DIR = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import slate_agents  # noqa: E402

SLATE = os.environ.get("SLATE_COMMAND") or os.path.join(SLATE_DIR, "bin", "slate")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "slate", "assistant")
TIMEOUT = float(os.environ.get("SLATE_ASSISTANT_TIMEOUT") or 120)
PROMPT_MAX = 4000


def emit(**event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def server():
    """Slate's MCP server as a module: the gate and the status tool are its."""
    return importlib.import_module("slate-mcp")


def briefing():
    """Who the agent is here: the [nova] and [shared] blocks of data/assistant-prompt.md."""
    try:
        with open(os.path.join(SLATE_DIR, "data", "assistant-prompt.md"), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return ""
    blocks, who, lines = [], None, []
    for line in text.splitlines() + ["[end]"]:
        m = re.match(r"\[(\w+)\]\s*$", line)
        if m:
            if who in ("nova", "shared") and "".join(lines).strip():
                blocks.append(" ".join(l.strip() for l in lines if l.strip()))
            who, lines = m.group(1), []
        else:
            lines.append(line)
    return "\n\n".join(blocks)


def plain(value, limit=120):
    """A value for the context block: cleaned as any tool result is, and without the
    brackets that could close the block early."""
    mcp = server()
    return mcp.clean(str(value).replace("<", " ").replace(">", " "), limit)


def context(mcp):
    """Right now, from what the status tool answers (so under the same switches). The gate
    has to have passed first."""
    st = mcp.status()
    on = lambda v: "on" if v else "off"                     # noqa: E731
    lines = ["Now: %s (%s)" % (plain(st["time"]), plain(st["timezone"], 40)),
             "Slate %s; theme: %s" % (plain(st["slate"], 30), plain(st["appearanceNow"], 10))]
    ws = st.get("workspace")
    if ws:
        name = ' "%s"' % plain(ws["name"], 40) if ws.get("name") else ""
        lines.append("Workspace %d%s is focused, with %d window%s" % (ws["id"], name, ws["windows"], "" if ws["windows"] == 1 else "s"))
    win = st.get("window")
    if win:
        title = ', "%s"' % plain(win["title"]) if win.get("title") else ""
        lines.append("Focused window: %s%s" % (plain(win["app"], 60), title))
    lines.append("Game mode: %s; Do Not Disturb: %s; night light: %s" % (on(st["gameMode"]), on(st["doNotDisturb"]), on(st["nightLight"])))
    return "<slate-context>\n" + "\n".join(lines) + "\n</slate-context>"


def write_private(path, text):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def detect():
    out = []
    for a in slate_agents.AGENTS:
        installed = a.installed()
        out.append({"id": a.id, "label": a.label, "installed": installed, "version": a.version() if installed else "",
                    "signedIn": a.signed_in() if installed else False, "confined": a.confined,
                    "followUps": a.follow_ups, "url": a.url, "note": a.note, "signIn": a.sign_in})
    print(json.dumps(out))


def run(args):
    agent = slate_agents.by_id(args.agent)
    if agent is None:
        return emit(type="error", kind="not-installed", message="There's no assistant set up yet. Slate can use Claude Code or a command of your own.")
    if os.environ.get("SLATE_TEST") == "1" and agent.id not in ("custom", os.environ.get("SLATE_ASSISTANT_TEST_AGENT")):
        return emit(type="error", kind="not-installed", message="Slate couldn't find %s. It may have been removed." % agent.label)
    if agent.id == "custom" and not (args.command or "").strip():
        return emit(type="error", kind="not-installed", message="There's no command to run yet. You can add one in Settings → Assistant.")
    if not agent.installed():
        return emit(type="error", kind="not-installed", message="Slate couldn't find %s. It may have been removed." % agent.label)
    if not agent.confined and agent.id not in [a for a in (args.accepted or "").split(",") if a]:
        return emit(type="error", kind="not-accepted",
                    message="%s keeps tools of its own, so Slate asks before using it. You can choose it in Settings → Assistant." % agent.label)
    prompt = sys.stdin.read().strip()[:PROMPT_MAX]
    if not prompt:
        return emit(type="error", kind="failed", message="There was nothing to ask.")

    # The same gate the tools go through: nothing is sent anywhere while assistants are off
    mcp = server()
    try:
        mcp.gate()
        now = context(mcp)
    except mcp.NotRunning:
        return emit(type="error", kind="server", message="The assistant couldn't reach Slate. Restarting Slate usually fixes this.")
    except mcp.Sorry as e:
        off = "aren't switched on" in str(e) or "Something's changed" in str(e)
        return emit(type="error", kind="off" if off else "failed",
                    message="The assistant isn't switched on yet." if off else "Slate isn't taking requests for the assistant just now.")

    work = os.path.join(STATE, "work")
    os.makedirs(work, mode=0o700, exist_ok=True)
    words = briefing()
    mcp_env = {"SLATE_ASSISTANT_RUN": args.run, "SLATE_ASSISTANT_AGENT": agent.label}
    if os.environ.get("SLATE_COMMAND"):
        mcp_env["SLATE_COMMAND"] = os.environ["SLATE_COMMAND"]
    config = {"mcpServers": {"slate": {"command": SLATE, "args": ["mcp"], "env": mcp_env}}}
    info = {"model": args.model or "", "session": args.session or "", "command": args.command or "",
            "briefing": os.path.join(STATE, "briefing.md"), "context_file": os.path.join(STATE, "context.txt"),
            "mcp_config": config, "mcp_config_file": os.path.join(STATE, "mcp.json"), "mcp_command": [SLATE, "mcp"]}
    write_private(info["briefing"], words + "\n")
    write_private(info["context_file"], now + "\n")
    write_private(info["mcp_config_file"], json.dumps(config, indent=1) + "\n")

    # What goes to the agent: Slate's scene, then the person's own words, marked off from it
    if args.bare and agent.id == "custom":
        text = prompt
    elif agent.briefing == "system" or info["session"]:
        text = now + "\n\n" + prompt
    else:
        text = words + "\n\n" + now + "\n\n" + prompt

    env = dict(os.environ, SLATE_ASSISTANT_RUN=args.run, **agent.env(info))
    try:
        proc = subprocess.Popen(agent.command(info), cwd=work, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
    except OSError:
        return emit(type="error", kind="not-installed", message="Slate couldn't find %s. It may have been removed." % agent.label)

    def stop():
        """SIGINT ends a turn cleanly; SIGTERM for an agent that doesn't take the hint."""
        for sig, wait in ((signal.SIGINT, 2), (signal.SIGTERM, 2), (signal.SIGKILL, 1)):
            try:
                os.killpg(proc.pid, sig)
            except OSError:
                return
            try:
                proc.wait(timeout=wait)
                return
            except subprocess.TimeoutExpired:
                pass

    def stopped(*_):
        stop()
        emit(type="error", kind="stopped", message="Stopped.")
        os._exit(0)
    signal.signal(signal.SIGTERM, stopped)
    signal.signal(signal.SIGINT, stopped)

    lines, errors = queue.Queue(), []

    def read_out():
        for raw in proc.stdout:
            lines.put(raw.decode("utf-8", errors="replace").rstrip("\n"))
        lines.put(None)

    def read_err():
        for raw in proc.stderr:
            errors.append(raw.decode("utf-8", errors="replace").strip())
            del errors[:-5]
    threading.Thread(target=read_out, daemon=True).start()
    threading.Thread(target=read_err, daemon=True).start()
    try:
        proc.stdin.write(text.encode("utf-8"))
        proc.stdin.close()
    except OSError:
        pass

    state, finished, last, until = {}, False, "", time.monotonic() + TIMEOUT
    while True:
        try:
            line = lines.get(timeout=max(0.05, until - time.monotonic()))
        except queue.Empty:
            line = False
        if time.monotonic() > until and line is not None:
            stop()
            return emit(type="error", kind="timeout", message="That took longer than Slate waits. Anything already done is listed below.")
        if line is None:
            break
        if line is False:
            continue
        last = line or last
        for event in agent.parse(line, state):
            if finished:
                continue
            emit(**event)
            if event["type"] in ("done", "error"):
                finished = True
                if event["type"] == "error":
                    stop()
    code = proc.wait()
    if finished:
        return
    if agent.id == "custom" and code == 0:
        return emit(type="done", text=state.get("text", "").strip(), session="")
    if agent.id != "custom" and not agent.signed_in():
        return emit(type="error", kind="signed-out",
                    message="%s isn't signed in. Open a terminal and run %s once, then try again." % (agent.label, agent.sign_in or "it"))
    detail = (errors[-1] if errors else last)[-300:]
    emit(type="error", kind="failed", message="%s stopped unexpectedly." % (agent.label if agent.id != "custom" else "Your command"),
         detail=server().clean(detail, 300))


def main():
    p = argparse.ArgumentParser(prog="assistant.py", add_help=False)
    p.add_argument("what", choices=["detect", "run", "briefing"])
    p.add_argument("--agent", default="")
    p.add_argument("--run", default="")
    p.add_argument("--model", default="")
    p.add_argument("--session", default="")
    p.add_argument("--command", default="")
    p.add_argument("--accepted", default="")
    p.add_argument("--bare", action="store_true")
    try:
        args = p.parse_args()
    except SystemExit:
        sys.exit(__doc__)
    if args.what == "detect":
        detect()
    elif args.what == "briefing":
        mcp, now = server(), ""
        try:
            mcp.gate()
            now = context(mcp)
        except (mcp.NotRunning, mcp.Sorry):
            pass
        print(json.dumps({"briefing": briefing(), "context": now}))
    else:
        run(args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
