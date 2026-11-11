"""Assistants (docs/ASSISTANT.md): Slate's side of the gate (the `assistant` IPC and its
questions in the confirmation window), the IPC added for the tools, and Slate's MCP server
run against the real thing."""
import json
import os
import subprocess
import sys
import time

from live import LiveCase

META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "Tester", "version": "1"}}


def call(tool, args, mid=1):
    return {"jsonrpc": "2.0", "id": mid, "method": "tools/call", "params": {"name": tool, "arguments": args, "_meta": META}}


class Assistant(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("assistantEnabled", "assistantAskChanges", "barClockSeconds"):
            self.keep_setting(key)
        self.config("assistantEnabled", "false")
        self.config("assistantAskChanges", "false")

    def status(self):
        return json.loads(self.ipc("assistant", "status"))

    def ask(self, qid, title="Close Firefox?", **more):
        self.ipc("assistant", "confirm", qid, json.dumps(dict({"title": title, "body": "Your assistant is asking.",
                                                               "button": "Close", "danger": True}, **more)))

    def server(self):
        return [sys.executable, os.path.join(self.s.slate_dir, "scripts", "slate-mcp.py")]

    def tool(self, name, args):
        p = subprocess.run(self.server(), input=json.dumps(call(name, args)) + "\n", env=self.s.env, timeout=60,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        r = json.loads(p.stdout)["result"]
        return r["content"][0]["text"], r["isError"]

    def test_off_to_start_with(self):
        st = self.status()
        self.assertEqual(set(st), {"enabled", "locked", "gameMode", "askChanges", "seeTitles", "seeNotifications"})
        self.assertEqual((st["enabled"], st["locked"], st["seeTitles"], st["seeNotifications"]), (False, False, True, False))
        self.config("assistantEnabled", "true")
        self.assertTrue(self.status()["enabled"])

    def test_a_question(self):
        """A question shows in Slate's confirmation window; the answer is read once."""
        self.ask("q1")
        st = self.wait(lambda st: st["asking"] == "Close Firefox?", "the question")
        self.assertEqual(st["askingBody"], "Your assistant is asking.")
        self.assertEqual(st["assistant"]["waiting"], 1)
        self.assertEqual(self.ipc("assistant", "answer", "q1"), "", "answered before anyone did")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: not st["power"]["open"], "the question to close")
        self.assertEqual(self.ipc("assistant", "answer", "q1"), "yes")
        self.assertEqual(self.ipc("assistant", "answer", "q1"), "", "the answer was kept after it was read")
        self.assertEqual(self.s.state()["assistant"]["waiting"], 0)

    def test_a_no(self):
        self.ask("q2")
        self.wait(lambda st: st["asking"] == "Close Firefox?")
        self.ipc("test", "answer", "false")
        self.wait(lambda st: not st["power"]["open"])
        self.assertEqual(self.ipc("assistant", "answer", "q2"), "no")

    def test_withdrawn(self):
        """A question the server stops waiting for goes away, showing or still waiting its turn."""
        self.ask("q3", "First?")
        self.ask("q4", "Second?")
        self.wait(lambda st: st["asking"] == "First?")
        self.ipc("assistant", "withdraw", "q4")
        self.ipc("assistant", "withdraw", "q3")
        self.wait(lambda st: not st["power"]["open"], "the question to go")
        self.s.settle(0.8)
        st = self.s.state()
        self.assertFalse(st["power"]["open"], "the withdrawn second question came up")
        self.assertEqual(st["assistant"]["waiting"], 0)
        self.assertEqual(self.ipc("assistant", "answer", "q3"), "")

    def test_questions_take_turns(self):
        self.ask("q5", "First?")
        self.ask("q6", "Second?")
        self.wait(lambda st: st["asking"] == "First?")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["asking"] == "Second?", "the second question")
        self.ipc("test", "answer", "false")
        self.wait(lambda st: not st["power"]["open"])
        self.assertEqual((self.ipc("assistant", "answer", "q5"), self.ipc("assistant", "answer", "q6")), ("yes", "no"))

    def test_new_ipc(self):
        """What the tools needed that Slate couldn't be asked before."""
        self.ipc("notifications", "dnd", "true")
        self.wait(lambda st: st["notifications"]["dnd"], "Do Not Disturb on")
        self.assertEqual(self.ipc("notifications", "dndGet"), "true")
        self.ipc("notifications", "dnd", "false")
        self.wait(lambda st: not st["notifications"]["dnd"])
        self.assertIsInstance(json.loads(self.ipc("notifications", "list")), list)
        vol = self.ipc("osd", "volumeGet")
        if vol:
            self.assertEqual(set(json.loads(vol)), {"volume", "muted"})
        self.ipc("osd", "volumeSet", "30")
        media = self.ipc("media", "info")
        if media:
            self.assertEqual(set(json.loads(media)), {"app", "title", "artist", "playing"})
        self.assertEqual(self.ipc("launcher", "launch", "no-such-app"), "unknown")
        self.assertFalse(self.s.state()["launcher"]["open"])

    def test_theme_through_config(self):
        """config set themeMode keeps the light switch in step, as Settings does."""
        for key in ("themeMode", "lightMode"):
            self.keep_setting(key)
        self.config("themeMode", "light")
        self.assertEqual(self.setting("lightMode"), "true")
        self.config("themeMode", "dark")
        self.assertEqual(self.setting("lightMode"), "false")

    def test_the_server(self):
        """slate mcp against the real Slate: refused while off, then a change and a look."""
        text, err = self.tool("settings_set", {"key": "barClockSeconds", "value": True})
        self.assertTrue(err)
        self.assertIn("aren't switched on", text)
        self.assertEqual(self.setting("barClockSeconds"), "false")
        self.config("assistantEnabled", "true")
        text, err = self.tool("settings_set", {"key": "barClockSeconds", "value": True})
        self.assertFalse(err, text)
        self.assertEqual((json.loads(text)["before"], json.loads(text)["now"]), (False, True))
        self.assertEqual(self.setting("barClockSeconds"), "true")
        text, err = self.tool("status", {})
        self.assertFalse(err, text)
        self.assertIn("doNotDisturb", json.loads(text))
        text, err = self.tool("settings_search", {"query": "glass"})
        self.assertEqual(json.loads(text)["settings"][0]["key"], "glass")

    def test_the_server_asks(self):
        """With "ask before changing anything" on, the change waits for your yes in the
        confirmation window, in Slate's words."""
        self.config("assistantEnabled", "true")
        self.config("assistantAskChanges", "true")
        p = subprocess.Popen(self.server(), env=self.s.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.kill)
        p.stdin.write(json.dumps(call("settings_set", {"key": "barClockSeconds", "value": True})) + "\n")
        p.stdin.flush()
        st = self.wait(lambda st: st["asking"] == "Change Show seconds to on?", "the server's question")
        self.assertIn("Your assistant (Tester) is asking to change this setting.", st["askingBody"])
        self.assertEqual(self.setting("barClockSeconds"), "false", "changed before the answer")
        self.ipc("test", "answer", "true")
        reply = json.loads(p.stdout.readline())
        self.assertFalse(reply["result"]["isError"], reply)
        self.assertEqual(self.setting("barClockSeconds"), "true")
        p.stdin.close()
        p.wait(timeout=10)
        time.sleep(0.2)
