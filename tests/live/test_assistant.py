"""Assistants (docs/ASSISTANT.md): Slate's side of the gate (the `assistant` IPC and its
questions in the confirmation window), the IPC added for the tools, and Slate's MCP server
run against the real thing."""
import http.server
import json
import os
import re
import subprocess
import sys
import threading
import time

import atexit
import unittest

from live import LiveCase
from pointer import Pointer
from session import Session, in_container

META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "Tester", "version": "1"}}


def call(tool, args, mid=1):
    return {"jsonrpc": "2.0", "id": mid, "method": "tools/call", "params": {"name": tool, "arguments": args, "_meta": META}}


class Assistant(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("assistantEnabled", "assistantRisksAccepted", "assistantAskChanges", "barClockSeconds",
                    "assistantAgent", "assistantCommand", "assistantCommandBare", "barShowAssistant", "assistantKeepChat"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("test", "assistantAccepted", ""))
        self.addCleanup(lambda: self.ipc("test", "nova", "{}"))
        self.config("assistantEnabled", "false")
        self.config("assistantRisksAccepted", "0")
        self.config("assistantAskChanges", "false")

    def switch_on(self):
        """As accepting the risks in Settings → Assistant leaves it."""
        self.config("assistantRisksAccepted", "1")
        self.config("assistantEnabled", "true")

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
        self.assertEqual(set(st), {"enabled", "risksChanged", "locked", "gameMode", "askChanges", "seeTitles", "seeNotifications", "private"})
        self.assertEqual((st["enabled"], st["locked"], st["seeTitles"], st["seeNotifications"]), (False, False, True, False))
        # Setting the switch some other way switches nothing on: the risks have to be accepted too
        self.config("assistantEnabled", "true")
        self.assertFalse(self.status()["enabled"])
        self.config("assistantRisksAccepted", "1")
        self.assertTrue(self.status()["enabled"])
        # Accepted under another version of the risks: paused until they're read again
        self.config("assistantRisksAccepted", "99")
        st = self.status()
        self.assertEqual((st["enabled"], st["risksChanged"]), (False, True))

    def test_switching_on_asks(self):
        """Settings → Assistant: the switch shows the risks, and only "Switch on" switches it on."""
        self.ipc("settings", "page", "assistant")
        self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "assistant", "the Assistant page")
        self.ipc("test", "assistant", "on")
        st = self.wait(lambda st: st["asking"] == "Switch on the assistant?", "the risks")
        for part in ("What leaves your computer.", "What it can do.", "What can go wrong.", "your responsibility", "Read more"):
            self.assertIn(part, st["askingBody"])
        self.assertFalse(st["assistant"]["enabled"], "on before the risks were accepted")
        self.assertEqual(self.setting("assistantEnabled"), "false")
        self.ipc("test", "answer", "false")
        self.wait(lambda st: not st["power"]["open"])
        self.assertEqual((self.setting("assistantEnabled"), self.setting("assistantRisksAccepted")), ("false", "0"), "Cancel switched it on")
        self.ipc("test", "assistant", "on")
        self.wait(lambda st: st["asking"] == "Switch on the assistant?")
        self.ipc("test", "answer", "true")
        self.wait(lambda st: st["assistant"]["enabled"], "the assistant to be on")
        self.assertEqual((self.setting("assistantEnabled"), self.setting("assistantRisksAccepted")), ("true", "1"))
        # Reading the risks again offers to switch off
        self.ipc("test", "assistant", "risks")
        self.wait(lambda st: st["asking"] == "What using the assistant means")
        self.ipc("test", "answer", "false")
        self.wait(lambda st: not st["assistant"]["enabled"], "the assistant to be off")
        # Off needs no question
        self.switch_on()
        self.ipc("test", "assistant", "off")
        self.wait(lambda st: not st["assistant"]["enabled"])
        self.assertFalse(self.s.state()["power"]["open"])
        self.ipc("settings", "close")

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
        self.steady(self.s.state, floor=0.8)
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

    def test_radios_and_dock(self):
        """What the wifi, bluetooth, dock_pin and waste_basket_empty tools use (Radios.qml and
        the dock's IPC), and the server using it. The container has no NetworkManager or
        BlueZ, so here Wi-Fi and Bluetooth say there's none, and nothing can be turned on or
        connected."""
        for target in ("wifi", "bluetooth"):
            with self.subTest(target):
                st = json.loads(self.ipc(target, "list"))
                self.assertLessEqual({"available", "on"}, set(st))
                if not st["available"]:
                    self.assertFalse(st["on"])
                    self.assertEqual(self.ipc(target, "power", "true"), "none")
                    self.assertEqual(self.ipc(target, "connect", "Home"), "off")
        # Pinning, as the dock's menu does: at the end, and off again
        before = json.loads(self.ipc("dock", "pinned"))
        self.assertEqual(before, self.s.state()["dock"]["pinned"])

        def restore():
            for k in json.loads(self.ipc("dock", "pinned")):
                self.ipc("dock", "pin", k, "false")
            for k in before:
                self.ipc("dock", "pin", k, "true")
        self.addCleanup(restore)
        self.ipc("dock", "pin", "slate-test-app", "true")
        self.wait(lambda st: st["dock"]["pinned"][-1:] == ["slate-test-app"], "the app pinned at the end")
        self.ipc("dock", "pin", "slate-test-app", "false")
        self.wait(lambda st: "slate-test-app" not in st["dock"]["pinned"], "the app unpinned")
        # Through the server
        self.switch_on()
        text, err = self.tool("wifi", {})
        self.assertFalse(err, text)
        want = "foot" not in before
        text, err = self.tool("dock_pin", {"id": "foot", "pinned": want})
        self.assertFalse(err, text)
        self.wait(lambda st: ("foot" in st["dock"]["pinned"]) == want, "foot pinned or unpinned")
        # The waste basket: Slate's own question, then emptied as the dock does (or, where
        # gio can't, said so)
        trash = self.s.h(".local", "share", "Trash")
        for d in ("files", "info"):
            os.makedirs(os.path.join(trash, d), exist_ok=True)
        thrown = os.path.join(trash, "files", "old.txt")
        open(thrown, "w").close()
        with open(os.path.join(trash, "info", "old.txt.trashinfo"), "w") as f:
            f.write("[Trash Info]\nPath=/tmp/old.txt\nDeletionDate=2026-01-05T09:00:00\n")
        self.addCleanup(lambda: [os.remove(p) for p in (thrown, os.path.join(trash, "info", "old.txt.trashinfo"))
                                 if os.path.exists(p)])
        p = subprocess.Popen(self.server(), env=self.s.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.kill)
        p.stdin.write(json.dumps(call("waste_basket_empty", {})) + "\n")
        p.stdin.flush()
        st = self.wait(lambda st: st["asking"] == "Empty the waste basket?", "Slate's question")
        self.assertIn("The item in it will be deleted for good. Just so you know, this can't be undone.", st["askingBody"])
        self.assertTrue(os.path.exists(thrown), "emptied before the answer")
        self.ipc("test", "answer", "true")
        r = json.loads(p.stdout.readline())["result"]
        if r["isError"]:
            self.assertIn("couldn't empty the waste basket", r["content"][0]["text"])
            self.assertTrue(os.path.exists(thrown))
        else:
            self.assertFalse(os.path.exists(thrown))
        p.stdin.close()
        p.wait(timeout=10)

    def test_theme_through_the_server(self):
        """The assistant changing the theme keeps the light switch in step, as Settings does,
        and plain `config set` is left as it was (each setting on its own)."""
        for key in ("themeMode", "lightMode"):
            self.keep_setting(key)
        self.switch_on()
        text, err = self.tool("settings_set", {"key": "themeMode", "value": "light"})
        self.assertFalse(err, text)
        self.assertEqual((self.setting("themeMode"), self.setting("lightMode")), ("light", "true"))
        text, err = self.tool("settings_set", {"key": "themeMode", "value": "dark"})
        self.assertEqual((self.setting("themeMode"), self.setting("lightMode")), ("dark", "false"))
        self.ipc("config", "set", "themeMode", "light")
        self.assertEqual(self.setting("lightMode"), "false", "config set themeMode changed another setting")

    def test_a_negative_number_is_a_value(self):
        """A value that starts with a minus reaches Slate as the value (qs doesn't take it for an
        option), through the server's own direct call to qs."""
        self.keep_setting("mouseSpeed")
        self.switch_on()
        text, err = self.tool("settings_set", {"key": "mouseSpeed", "value": -0.5})
        self.assertFalse(err, text)
        self.assertEqual(float(self.setting("mouseSpeed")), -0.5)

    def test_the_server(self):
        """slate mcp against the real Slate: refused while off, then a change and a look."""
        text, err = self.tool("settings_set", {"key": "barClockSeconds", "value": True})
        self.assertTrue(err)
        self.assertIn("aren't switched on", text)
        self.assertEqual(self.setting("barClockSeconds"), "false")
        self.switch_on()
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
        self.switch_on()
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


    def test_arranging_the_bar(self):
        """bar_arrange: with nothing it only looks; a whole arrangement is checked, then set
        (what it leaves out goes to the pool, Nova's button stays where it was); and Slate's
        own comes back with reset. With "ask before changing anything", a no changes nothing."""
        self.addCleanup(lambda: self.ipc("bar", "arrange", json.dumps({"reset": True})))
        self.switch_on()
        text, err = self.tool("bar_arrange", {})
        self.assertFalse(err, text)
        now = json.loads(text)
        self.assertTrue(now["slatesOwn"])
        self.assertEqual(now["layout"][0]["items"], ["control"])
        self.assertEqual(now["names"]["wifi"], "Wi-Fi")

        layout = [{"items": ["clock"]}, {"items": ["control", "apps"]}, {"items": ["spaces", "workspaces"]},
                  {"items": ["windowtitle"]}, "space", {"items": ["wifi", "volume"], "collapse": "always", "collapseAt": "start"},
                  {"items": ["more"]}, {"items": ["power"]}]
        for bad, says in ((layout + [{"items": ["clock"]}], "two places"), ([{"items": ["kettle"]}], "nothing called"),
                          ([{"items": []}], "at least one"), ([{"items": ["clock"], "collapse": "sometimes"}], "collapse is one of")):
            with self.subTest(says):
                text, err = self.tool("bar_arrange", {"layout": bad})
                self.assertTrue(err, text)
                self.assertIn(says, text)
        self.assertTrue(json.loads(self.tool("bar_arrange", {})[0])["slatesOwn"], "a refused arrangement changed the bar")

        text, err = self.tool("bar_arrange", {"layout": layout, "leaveFirst": ["windowtitle", "wifi"], "alwaysStay": ["clock", "power"]})
        self.assertFalse(err, text)
        now = json.loads(text)
        boxes = [e for e in now["layout"] if e != "space"]
        self.assertEqual(boxes[0]["items"], ["clock"])
        self.assertEqual(boxes[1]["items"], ["control", "apps", "nova"], "Nova's button didn't stay beside Apps")
        tucked = next(e for e in boxes if "wifi" in e["items"])
        self.assertEqual((tucked["items"], tucked["collapse"], tucked["collapseAt"]), (["wifi", "volume"], "always", "start"))
        for gone in ("battery", "tray", "notifications", "windowmode", "windowicon"):
            self.assertIn(gone, now["offBar"])
        self.assertEqual(self.setting("barShowBattery"), "false")
        self.assertEqual(self.setting("barShowAssistant"), "true", "the assistant switched Nova's button")
        self.assertEqual(now["alwaysStay"], ["clock", "power"])
        self.assertEqual(now["leaveFirst"][:2], ["windowtitle", "wifi"])
        self.assertFalse(now["slatesOwn"])

        # Asked first, and a no leaves it
        self.config("assistantAskChanges", "true")
        p = subprocess.Popen(self.server(), env=self.s.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.addCleanup(p.kill)
        p.stdin.write(json.dumps(call("bar_arrange", {"reset": True})) + "\n")
        p.stdin.flush()
        st = self.wait(lambda st: st["asking"] == "Put the menu bar back as Slate starts out?", "the server's question")
        self.assertIn("Your assistant (Tester) is asking to put the menu bar back", st["askingBody"])
        self.ipc("test", "answer", "false")
        reply = json.loads(p.stdout.readline())
        self.assertTrue(reply["result"]["isError"], reply)
        p.stdin.close()
        p.wait(timeout=10)
        self.assertFalse(json.loads(self.tool("bar_arrange", {})[0])["slatesOwn"], "a no reset the bar")

        self.config("assistantAskChanges", "false")
        text, err = self.tool("bar_arrange", {"reset": True})
        self.assertFalse(err, text)
        self.assertTrue(json.loads(text)["slatesOwn"])
        self.assertEqual(self.setting("barShowBattery"), "true")


# A stand-in agent for "a command of your own": it speaks MCP to Slate's server (found in its
# environment, as a real one would), changes one setting through it and says so. No network
AGENT = r"""
import json, os, shlex, subprocess, sys
asked = sys.stdin.read()
meta = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": {}}
call = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "settings_set", "arguments": {"key": "barClockSeconds", "value": True}, "_meta": meta}}
p = subprocess.run(shlex.split(os.environ["SLATE_MCP_COMMAND"]), input=json.dumps(call) + "\n", capture_output=True, text=True)
r = json.loads(p.stdout)["result"]
print("I couldn't do that." if r["isError"] else "Done: the clock shows seconds now.")
print("You asked: " + asked.strip().splitlines()[-1])
"""


class Nova(LiveCase):
    """The prompt window (Super+K), its bar button and shortcuts, and one prompt all the way
    through with a stand-in agent."""

    def setUp(self):
        super().setUp()
        for key in ("assistantEnabled", "assistantRisksAccepted", "assistantAskChanges", "barClockSeconds",
                    "assistantAgent", "assistantCommand", "assistantCommandBare", "barShowAssistant", "assistantKeepChat"):
            self.keep_setting(key)
        self.addCleanup(lambda: self.ipc("test", "assistantAccepted", ""))
        self.addCleanup(lambda: self.ipc("test", "nova", "{}"))
        self.config("assistantRisksAccepted", "1")
        self.config("assistantEnabled", "true")
        self.config("barClockSeconds", "false")

    def nova(self):
        return self.s.state()["assistant"]

    def test_opens_and_closes(self):
        self.ipc("assistant", "toggle")
        self.wait(lambda st: st["assistant"]["open"], "the prompt window")
        self.ipc("assistant", "toggle")
        self.wait(lambda st: not st["assistant"]["open"], "it to close")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.ipc("assistant", "close")
        self.wait(lambda st: not st["assistant"]["open"])

    def test_opening_it_closes_the_overlays(self):
        """Opening it closes the launcher and a bar panel, so it has the keyboard. It's a real
        window, as Settings is: the launcher and the panels leave it open."""
        self.addCleanup(lambda: self.ipc("assistant", "close"))
        self.ipc("launcher", "open")
        self.wait(lambda st: st["launcher"]["open"])
        self.ipc("assistant", "open")
        st = self.wait(lambda st: st["assistant"]["open"])
        self.assertFalse(st["launcher"]["open"])
        self.ipc("launcher", "open")
        st = self.wait(lambda st: st["launcher"]["open"])
        self.assertTrue(st["assistant"]["open"], "the launcher closed Nova's window")
        self.ipc("launcher", "close")
        self.ipc("bar", "panel", "control")
        st = self.wait(lambda st: st["popout"] == "control")
        self.assertTrue(st["assistant"]["open"], "a bar panel closed Nova's window")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"] and st["popout"] == "", "the panel to close")

    def test_switched_off(self):
        """Off: no button on the bar, and the shortcut opens the window saying so, not a dead key."""
        self.assertTrue(self.nova()["button"])
        self.config("barShowAssistant", "false")
        self.assertFalse(self.nova()["button"])
        self.config("barShowAssistant", "true")
        self.config("assistantEnabled", "false")
        self.assertFalse(self.nova()["button"], "the button shows while the assistant is off")
        self.ipc("assistant", "ask", "turn on glass")
        st = self.wait(lambda st: st["assistant"]["open"])
        self.s.settle(0.5)
        st = self.nova()
        self.assertEqual((st["working"], st["asked"], st["enabled"]), (False, "", False), "a prompt was sent while switched off")

    def test_shortcuts(self):
        """Super+K, the assistant key and the Copilot key (Super+Shift+F23, by keycode) all open it."""
        binds = [b for b in self.s.hyprctl("binds", json_out=True) if "assistant toggle" in (b.get("arg") or "") or "Ask Nova" in (b.get("description") or "")]
        seen = {(b.get("key") or "", b.get("keycode") or 0, b.get("modmask")) for b in binds}
        self.assertEqual(len(binds), 3, f"expected three shortcuts for Nova, found {seen}")
        self.assertTrue(any(k.upper() == "K" and m == 64 for k, c, m in seen), seen)
        self.assertTrue(any(k == "XF86Assistant" and m == 0 for k, c, m in seen), seen)
        self.assertTrue(any(c == 201 and m == 65 for k, c, m in seen), seen)
        for b in binds:
            self.assertIn("Slate: Ask Nova", b.get("description") or "")

    def test_no_agent_until_one_is_chosen(self):
        """Switched on, there's no agent to start with: Slate doesn't pick one, and asking says
        one has to be chosen."""
        self.config("assistantAgent", "")
        self.assertEqual(self.nova()["agent"], "")
        self.ipc("assistant", "ask", "show seconds on the clock")
        st = self.wait(lambda st: st["assistant"]["error"] == "not-installed", "being told there's no agent")
        self.assertIn("Choose one in Settings", st["assistant"]["errorText"])
        self.assertEqual(self.setting("barClockSeconds"), "false")

    def test_a_prompt_all_the_way(self):
        """Typed → the runner → the agent (a stand-in, as a command of your own) → Slate's
        server → Slate: the setting changes, the answer shows, and the list says what it did."""
        script = os.path.join(self.s.env["HOME"], "stand-in-agent.py")
        with open(script, "w") as f:
            f.write(AGENT)
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "%s %s" % (sys.executable, script))
        # Not said yes to yet: Slate won't run a command of your own
        self.ipc("assistant", "ask", "show seconds on the clock")
        st = self.wait(lambda st: st["assistant"]["error"] == "not-accepted", "it to be refused")
        self.assertEqual(self.setting("barClockSeconds"), "false")
        self.ipc("test", "assistantAccepted", "custom")
        self.ipc("assistant", "ask", "show seconds on the clock")
        st = self.wait(lambda st: st["assistant"]["asked"] != "" and not st["assistant"]["working"] and st["assistant"]["answer"] != "",
                       "the answer", timeout=30)["assistant"]
        self.assertEqual(st["error"], "")
        self.assertEqual(st["answer"], "Done: the clock shows seconds now.\nYou asked: show seconds on the clock")
        self.assertEqual(self.setting("barClockSeconds"), "true")
        self.assertEqual([(a["text"], a["state"]) for a in st["actions"]], [("Turn Show seconds on", "done")])
        self.assertTrue(st["open"])
        # Asking again adds to the conversation; the earlier exchange stays above it
        self.assertEqual(st["turns"], 2, "the refused prompt and this one")
        self.ipc("assistant", "ask", "and again")
        st = self.wait(lambda st: st["assistant"]["turns"] == 3 and not st["assistant"]["working"], "the third exchange", timeout=30)["assistant"]
        self.assertTrue(st["answer"].endswith("You asked: and again"))
        self.ipc("assistant", "clear")
        self.wait(lambda st: st["assistant"]["turns"] == 0, "New to forget it")

    def test_an_answer_with_markdown(self):
        """An answer with a list, bold words and a code block, all the way through: the runner
        reads it (safe_markdown.py) and the window draws Slate's own blocks. The code box's Copy
        copies just the code. A picture and HTML in the same answer are shown as characters,
        and nothing is fetched: a server in the session hears no request."""
        hits = []

        class Heard(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                self.send_response(404)
                self.end_headers()

            def log_message(self, *a):
                pass
        server = http.server.HTTPServer(("127.0.0.1", 0), Heard)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        url = "http://127.0.0.1:%d/" % server.server_port
        answer = (f"I've turned on **Glass**. To do it yourself:\n\n1. Open *Settings*\n2. Go to **Appearance**\n   - switch on Glass\n\n"
                  f"```sh\nslate ipc call config set glass true\n```\n"
                  f"![chart]({url}markdown-image.png) <img src=\"{url}html-image.png\"> [the docs]({url}link)")
        script = os.path.join(self.s.env["HOME"], "markdown-agent.py")
        with open(script, "w") as f:
            f.write("import sys\nsys.stdin.read()\nprint(%r)\n" % answer)
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "%s %s" % (sys.executable, script))
        self.ipc("test", "assistantAccepted", "custom")
        self.ipc("assistant", "ask", "turn on glass")
        st = self.wait(lambda st: st["assistant"]["asked"] == "turn on glass" and not st["assistant"]["working"] and st["assistant"]["blocks"],
                       "the answer", timeout=30)["assistant"]
        self.assertEqual(st["error"], "")
        self.assertEqual(st["answer"], answer, "the answer itself (for Copy) isn't what the agent wrote")
        blocks = st["blocks"]
        self.assertEqual([b["type"] for b in blocks], ["paragraph", "list", "code", "paragraph"])
        self.assertIn({"text": "Glass", "bold": True, "italic": False, "code": False, "dim": False}, blocks[0]["runs"])
        self.assertEqual([(it["level"], it["marker"]) for it in blocks[1]["items"]], [(0, "1."), (0, "2."), (1, "•")])
        self.assertEqual(blocks[2]["text"], "slate ipc call config set glass true")
        # The picture is its description and the HTML its characters, escaped into Slate's markup
        rich = st["rich"]
        self.assertEqual(len(rich), 5, "a paragraph, three list items and the last paragraph")
        for markup in rich:
            self.assertEqual(set(re.findall(r"<(/?\w+)", markup)) - {"b", "/b", "i", "/i", "span", "/span"}, set(), markup)
        self.assertIn("[image: chart]", rich[-1])
        self.assertIn("&lt;img src=&quot;%shtml-image.png&quot;&gt;" % url, rich[-1])
        self.assertIn("<b>Glass</b>", rich[0])
        # Copy, on the code box
        self.ipc("test", "novaCopyCode", "2")
        self.wait(lambda st: st["assistant"]["copied"] == "0:code:2", "it to say it's copied")
        pasted = ""
        for _ in range(40):
            code, pasted = self.s.run(["wl-paste", "--no-newline"])
            if pasted == "slate ipc call config set glass true":
                break
            self.s.settle(0.1)
        self.assertEqual(pasted, "slate ipc call config set glass true")
        # Nothing was fetched, from the picture, the HTML or the link
        self.s.settle(1.0)
        self.assertEqual(hits, [], "the answer made Slate fetch something")
        self.s.new_log_errors()

    def test_a_streamed_answer_keeps_its_blocks(self):
        """While an answer streams in, its blocks come again whole every moment. Only a block that
        changed or is new is drawn: earlier blocks, and the exchanges above, aren't made again
        (the window counts the blocks each exchange has made)."""
        para = lambda text: {"type": "paragraph", "runs": [{"text": text}]}
        self.addCleanup(lambda: self.ipc("assistant", "close"))
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"], "the prompt window")
        self.ipc("test", "nova", json.dumps({
            "history": [{"asked": "before", "answer": "one two", "blocks": [para("one"), para("two")]}],
            "asked": "now", "working": True}))
        stream = lambda e: self.ipc("test", "novaStream", json.dumps(e))
        made = lambda: {int(k): v for k, v in self.nova()["blocksMade"].items()}
        self.wait(lambda st: made().get(0, 0) >= 2, "the earlier answer's blocks")
        before = made()
        stream({"type": "text", "delta": "First. "})
        stream({"type": "blocks", "blocks": [para("First.")]})
        self.wait(lambda st: made().get(1, 0) == before.get(1, 0) + 1, "the first block")
        first = made()[1]
        stream({"type": "blocks", "blocks": [para("First."), para("Second.")]})
        self.wait(lambda st: made()[1] == first + 1, "the second block")
        stream({"type": "blocks", "blocks": [para("First."), para("Second."), para("Third")]})
        stream({"type": "blocks", "blocks": [para("First."), para("Second."), para("Third, and more")]})
        self.wait(lambda st: made()[1] == first + 2, "the third block")
        self.s.settle(0.5)
        self.assertEqual(made()[1], first + 2, "an earlier block was made again as the answer grew")
        self.assertEqual(made().get(0, 0), before.get(0, 0), "the earlier exchange was made again")

    def test_kept_plain_answers(self):
        """A conversation kept before answers had blocks still loads, its answers plain."""
        os.makedirs(os.path.dirname(self.chat_file()), exist_ok=True)
        with open(self.chat_file(), "w") as f:
            json.dump({"session": "", "turns": [{"asked": "is glass on?", "answer": "Yes, **glass** is on.", "at": 1, "doneAt": 2,
                                                 "error": None, "actions": []}]}, f)
        self.ipc("shell", "reload")
        self.s.settle(2.5)
        st = self.wait(lambda st: st["assistant"]["turns"] == 1, "the kept conversation", timeout=20)["assistant"]
        self.assertEqual((st["asked"], st["answer"], st["blocks"], st["rich"]), ("is glass on?", "Yes, **glass** is on.", [], []))
        self.s.new_log_errors()

    def chat_file(self):
        return os.path.join(self.s.env["XDG_STATE_HOME"], "slate", "assistant", "chat.json")

    def test_the_conversation_is_kept(self):
        """Keep the conversation (on to start with): it's still there after Slate reloads,
        in a file only you can read. Switched off, the file goes and nothing more is kept."""
        self.assertEqual(self.setting("assistantKeepChat"), "true")
        feed = {"history": [{"asked": "is glass on?", "answer": "Yes, glass is on."}],
                "asked": "close the terminal", "answer": "I've left it open.", "actions": [{"id": 1, "text": "Close Terminal", "state": "declined"}]}
        self.ipc("test", "nova", json.dumps(feed))
        self.wait(lambda st: st["assistant"]["turns"] == 2)
        self.s.settle(1.2)
        with open(self.chat_file()) as f:
            kept = json.load(f)
        self.assertEqual([t["asked"] for t in kept["turns"]], ["is glass on?", "close the terminal"])
        self.assertEqual(os.stat(self.chat_file()).st_mode & 0o077, 0, "others can read the conversation")
        self.assertEqual(os.stat(os.path.dirname(self.chat_file())).st_mode & 0o077, 0, "others can look in its folder")
        self.ipc("shell", "reload")
        self.s.settle(2.5)
        st = self.wait(lambda st: st["assistant"]["turns"] == 2, "the conversation after a reload", timeout=20)["assistant"]
        self.assertEqual((st["asked"], st["answer"], st["actions"][0]["state"]), ("close the terminal", "I've left it open.", "declined"))
        self.config("assistantKeepChat", "false")
        for _ in range(30):
            if not os.path.exists(self.chat_file()):
                break
            self.s.settle(0.1)
        self.assertFalse(os.path.exists(self.chat_file()), "switching it off left the conversation on disk")
        self.ipc("test", "nova", json.dumps({"asked": "another", "answer": "one"}))
        self.s.settle(1.2)
        self.assertFalse(os.path.exists(self.chat_file()), "kept although it's switched off")
        self.s.new_log_errors()

    def test_carries_on_when_closed(self):
        """Closing the window doesn't stop a run; Stop does."""
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "sleep 30")
        self.ipc("test", "assistantAccepted", "custom")
        self.ipc("assistant", "ask", "wait a while")
        self.wait(lambda st: st["assistant"]["working"], "it to start")
        self.ipc("assistant", "close")
        self.s.settle(0.6)
        st = self.nova()
        self.assertEqual((st["open"], st["working"]), (False, True), "closing the window stopped the run")
        self.ipc("assistant", "stop")
        st = self.wait(lambda st: not st["assistant"]["working"], "it to stop", timeout=15)["assistant"]
        self.assertEqual(st["error"], "", "stopping is not an error")

    def test_stop_in_the_box(self):
        """While Nova works, Stop sits at the end of the box, and Ctrl+C there stops it too."""
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "sleep 30")
        self.ipc("test", "assistantAccepted", "custom")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"], "the prompt window")
        self.assertFalse(self.nova()["stopShown"], "Stop showed with nothing to stop")
        self.ipc("assistant", "ask", "wait a while")
        self.wait(lambda st: st["assistant"]["working"] and st["assistant"]["stopShown"], "Stop in the box")
        # A real key press, through a virtual keyboard: wtype makes a new one each time and
        # presses straight away, so a key can be lost before Slate has its keymap. -s waits a
        # moment first; and the keys the box was given say whether it arrived
        seen = self.nova()["keysSeen"]
        for _ in range(5):
            self.s.run(["wtype", "-s", "300", "-M", "ctrl", "c", "-m", "ctrl"], check=True)
            self.s.settle(0.3)
            if self.nova()["keysSeen"] > seen:
                break
        st = self.wait(lambda st: not st["assistant"]["working"], "Ctrl+C to stop it", timeout=15)["assistant"]
        self.assertEqual(st["error"], "", "stopping is not an error")
        self.wait(lambda st: not st["assistant"]["stopShown"], "Stop to go")

    def test_follows_on_for_a_few_minutes(self):
        """What you type soon after an answer follows on from it (the agent's thread is kept);
        left longer than five minutes, Nova starts afresh, with the history still on show."""
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "echo ok")
        self.ipc("test", "assistantAccepted", "custom")
        now = int(time.time() * 1000)
        for age, want in ((60, "thread-1"), (11 * 60, "")):
            with self.subTest(f"{age} seconds ago"):
                self.ipc("test", "nova", json.dumps({"asked": "is glass on?", "answer": "Yes.", "session": "thread-1",
                                                      "at": now - age * 1000, "doneAt": now - age * 1000}))
                self.ipc("assistant", "ask", "and a bit bigger")
                st = self.wait(lambda st: st["assistant"]["turns"] == 2 and not st["assistant"]["working"] and st["assistant"]["answer"] != "",
                               "the answer", timeout=30)["assistant"]
                self.assertEqual(st["session"], want)
                self.assertEqual(st["turns"], 2, "the history went with the thread")

    def test_undo_a_setting(self):
        """A setting Nova changed can be put back from its row: Undo sets the value before as
        Settings would, the row says it's undone (and is kept so), and the button goes. Changed
        again since, or one of the assistant's own, there's no Undo."""
        for key in ("dockIconSize", "themeMode", "lightMode"):
            self.keep_setting(key)
        self.config("barClockSeconds", "true")
        self.config("dockIconSize", "48")
        self.config("themeMode", "light")
        self.config("lightMode", "true")
        rows = [{"id": 1, "text": "Turn Show seconds on", "state": "done", "key": "barClockSeconds", "before": False, "after": True},
                {"id": 2, "text": "Set Icon size to 48", "state": "done", "key": "dockIconSize", "before": 32, "after": 48},
                {"id": 3, "text": "Set Theme to \"light\"", "state": "done", "key": "themeMode", "before": "dark", "after": "light"},
                {"id": 4, "text": "Close Terminal", "state": "done"},
                {"id": 5, "text": "Turn Glass on", "state": "declined", "key": "glass", "before": False, "after": True},
                {"id": 6, "text": "Turn Ask on", "state": "done", "key": "assistantAskChanges", "before": True, "after": False}]
        self.ipc("test", "nova", json.dumps({"asked": "seconds, a bigger dock and light", "answer": "Done.", "actions": rows}))
        self.wait(lambda st: st["assistant"]["undo"] == [True, True, True, False, False, False], "Undo on the settings it changed")
        self.ipc("test", "novaUndo", "0")
        st = self.wait(lambda st: st["assistant"]["undo"][0] is False, "the first Undo to go")["assistant"]
        self.assertEqual(self.setting("barClockSeconds"), "false", "Undo didn't put the setting back")
        self.assertTrue(st["actions"][0]["undone"], "the row doesn't say it's undone")
        # The theme goes back with the switch it's drawn from, as Settings sets it
        self.ipc("test", "novaUndo", "2")
        self.wait(lambda st: st["assistant"]["undo"][2] is False, "the theme's Undo to go")
        self.assertEqual((self.setting("themeMode"), self.setting("lightMode")), ("dark", "false"))
        # Changed again since: nothing to undo, and Undo (if it were pressed) leaves it alone
        self.config("dockIconSize", "40")
        self.wait(lambda st: st["assistant"]["undo"][1] is False, "Undo to go once the setting has changed")
        self.ipc("test", "novaUndo", "1")
        self.s.settle(0.3)
        self.assertEqual(self.setting("dockIconSize"), "40", "Undo changed a setting changed since")
        self.assertFalse(self.nova()["actions"][1].get("undone"), "a row said undone that wasn't")
        # The assistant's own settings never take Undo, whatever the row says
        self.assertNotIn("key", self.nova()["actions"][5])
        # Undone is kept with the conversation
        self.s.settle(1.2)
        with open(self.chat_file()) as f:
            kept = json.load(f)["turns"][-1]["actions"]
        self.assertEqual([(a.get("key"), bool(a.get("undone"))) for a in kept[:3]],
                         [("barClockSeconds", True), ("dockIconSize", False), ("themeMode", True)])

    def test_did_only_from_this_run(self):
        """What it did comes from Slate's server for the run in hand: anything else is ignored."""
        self.ipc("test", "nova", json.dumps({"asked": "x", "working": True}))
        self.ipc("assistant", "did", json.dumps({"run": "someone-else", "id": 1, "text": "Shut down", "state": "done"}))
        self.s.settle(0.3)
        self.assertEqual(self.nova()["actions"], [])

    # ---- Nova's answer (Settings → Sound): what would have played is in state()["sounds"] ----
    def answering_in(self, seconds, fail=False):
        """A stand-in agent that answers in two pieces, after `seconds` (or says nothing and fails)."""
        script = os.path.join(self.s.env["HOME"], "answering-agent.py")
        with open(script, "w") as f:
            f.write("import sys, time\nsys.stdin.read()\ntime.sleep(%s)\n" % seconds
                    + ("sys.exit(3)\n" if fail else "print('Here', flush=True)\ntime.sleep(0.2)\nprint('you are.', flush=True)\n"))
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "%s %s" % (sys.executable, script))
        self.ipc("test", "assistantAccepted", "custom")

    def answer_sounds(self, prompt, close=False, stop=False):
        """Ask (closing the window or pressing Stop as it works), wait for the end of the run,
        and say how many times Nova's answer would have played."""
        self.ipc("test", "sounds")
        self.ipc("assistant", "ask", prompt)
        self.wait(lambda st: st["assistant"]["asked"] == prompt and st["assistant"]["working"], "it to start", timeout=15)
        if close:
            self.ipc("assistant", "close")
        if stop:
            self.s.settle(1.3)
            self.ipc("assistant", "stop")
        self.wait(lambda st: st["assistant"]["asked"] == prompt and not st["assistant"]["working"], "the end of the run", timeout=30)
        return self.steady(lambda: self.s.state()["sounds"], floor=0.3).count("answered")

    def test_answer_sound(self):
        """Once for an answer you waited for with the window open, however many pieces it came in."""
        self.keep_setting("answeredVolume")
        self.config("answeredVolume", "60")
        self.answering_in(1.3)
        self.assertEqual(self.answer_sounds("what's the time?"), 1)
        self.assertEqual(self.nova()["answer"], "Here\nyou are.")
        # 0 is off
        self.config("answeredVolume", "0")
        self.assertEqual(self.answer_sounds("and now?"), 0, "played with its volume at Off")

    def test_no_answer_sound(self):
        """Not for the history, an answer that came straight back, one that came with the window
        closed (that's a notification), a run that failed or was stopped, or in game mode."""
        self.keep_setting("answeredVolume")
        self.keep_setting("gameMode")
        self.config("answeredVolume", "60")
        self.ipc("test", "sounds")
        self.ipc("test", "nova", json.dumps({"history": [{"asked": "is glass on?", "answer": "Yes, glass is on."}],
                                             "asked": "close the terminal", "answer": "I've left it open."}))
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"] and st["assistant"]["turns"] == 2)
        self.assertEqual(self.steady(lambda: self.s.state()["sounds"], floor=0.3).count("answered"), 0, "played for the history")
        # (an instant answer still has to start Python and the runner: under a busy full run that
        # alone took over the second Nova calls straight back, so for this one the window's wider)
        self.ipc("test", "novaQuickAnswer", "5000")
        self.addCleanup(lambda: self.ipc("test", "novaQuickAnswer", "1000"))
        self.answering_in(0)
        self.assertEqual(self.answer_sounds("straight back?"), 0, "played for an answer that came straight back")
        self.ipc("test", "novaQuickAnswer", "1000")
        self.answering_in(1.3)
        self.assertEqual(self.answer_sounds("while it's closed", close=True), 0, "played with the window closed")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.answering_in(1.3, fail=True)
        self.assertEqual(self.answer_sounds("this goes wrong"), 0, "played for a run that failed")
        self.assertNotEqual(self.nova()["error"], "")
        self.answering_in(30)
        self.assertEqual(self.answer_sounds("stop this", stop=True), 0, "played when stopped")
        self.config("gameMode", "true")
        self.wait(lambda st: st["gameMode"], "game mode")
        self.answering_in(1.3)
        self.assertEqual(self.answer_sounds("in a game"), 0, "played in game mode")
        self.config("gameMode", "false")
        self.assertEqual(self.answer_sounds("after the game"), 1, "silent once game mode was off again")


class PrivateModeLive(LiveCase):
    """Private Mode (PrivateMode.qml), switched over IPC as the control centre does: the setting
    follows, and assistants are off while it's on (the status says so)."""
    def test_on_and_off(self):
        self.keep_setting("privateMode")
        self.addCleanup(lambda: self.ipc("private", "off"))
        self.ipc("private", "on")
        for _ in range(30):
            if self.setting("privateMode") == "true":
                break
            self.s.settle(0.1)
        self.assertEqual(self.setting("privateMode"), "true")
        st = json.loads(self.ipc("assistant", "status"))
        self.assertTrue(st["private"], "the assistant's status doesn't say Private Mode is on")
        self.assertFalse(st["enabled"])
        self.ipc("private", "off")
        for _ in range(30):
            if self.setting("privateMode") == "false":
                break
            self.s.settle(0.1)
        self.assertFalse(json.loads(self.ipc("assistant", "status"))["private"])


class CameraNote(LiveCase):
    """The note that shows as a camera starts and stops being used (OSD.qml), and the bar's
    camera item (barShowCamera): open eye and its hover while it's on, closed one after."""
    def test_note_on_and_off(self):
        self.addCleanup(lambda: self.ipc("test", "camera", "false", ""))
        self.ipc("test", "camera", "true", "Firefox")
        self.wait(lambda st: st["osd"]["shown"] and st["osd"]["mode"] == "note", "the camera note")
        self.assertEqual(self.s.state()["osd"]["label"], "Camera on · Firefox")
        self.ipc("test", "camera", "false", "")
        self.wait(lambda st: st["osd"]["label"] == "Camera off", "the note to say the camera's off")


class NovaWindowChecks:
    """Nova's window is a real one, as Settings is: Hyprland floats it in the middle, pins it to
    every workspace, moves it by its header, resizes it by its edges and slides it back under
    the menu bar when it's let go over it. Driven as a person would: a real pointer
    (tests/lib/pointer.py: pressed, moved and let go through Hyprland) and real keys, and read
    back from Hyprland (hyprctl clients). `scale` is the Interface size the session runs at:
    Hyprland's pixels are Slate's units times it."""
    scale = 1

    def open_nova(self):
        for key in ("assistantEnabled", "assistantRisksAccepted", "glass"):
            self.keep_setting(key)
        self.config("assistantRisksAccepted", "1")
        self.config("assistantEnabled", "true")
        self.config("glass", "true")
        self.addCleanup(lambda: self.ipc("test", "novaSizeReset"))
        self.addCleanup(lambda: self.ipc("assistant", "close"))
        self.ipc("assistant", "close")
        self.wait(lambda st: not st["assistant"]["open"], "Nova's window to be closed")
        self.s._until(lambda: self.client() is None, 5, "Hyprland to let go of Nova's window")
        self.ipc("test", "novaSizeReset")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"] and st["assistant"]["window"]["mapped"], "Nova's window")
        return self.placed()

    def client(self):
        """Nova's window as Hyprland has it (its place and size in Hyprland's pixels), or None."""
        for c in self.s.hyprctl("clients", json_out=True):
            if c.get("class") == "slate-settings" and c.get("title") == "Nova" and c.get("mapped"):
                return c
        return None

    def placed(self):
        """Nova's window once Hyprland has stopped moving it (its open animation, a slide)."""
        def read():
            c = self.client()
            return None if not c else (tuple(c["at"]), tuple(c["size"]))
        self.steady(read)
        c = self.client()
        self.assertIsNotNone(c, "Nova's window isn't there")
        return c

    def pointer(self):
        return Pointer(self.s.env, self.s.width, self.s.height)

    def u(self, v):
        """Slate's units, in Hyprland's pixels."""
        return round(v * self.scale)

    def test_a_floating_window_in_the_middle_with_the_keyboard(self):
        """It opens as a floating window pinned to every workspace, in the middle of the screen,
        at the size it comes at, and has the keyboard straight away: Escape closes it."""
        c = self.open_nova()
        win = self.s.state()["assistant"]["window"]
        self.assertTrue(c["floating"], "it isn't floating")
        self.assertTrue(c["pinned"], "it isn't on every workspace")
        self.assertAlmostEqual(c["size"][0], self.u(win["openW"]), delta=2)
        self.assertAlmostEqual(c["size"][1], self.u(win["openH"]), delta=2)
        m = self.s.monitor()
        self.assertAlmostEqual(c["at"][0] + c["size"][0] / 2, m["width"] / 2, delta=3, msg=f"not in the middle: {c['at']}")
        self.assertGreaterEqual(c["at"][1], m["reserved"][1], "it's over the menu bar")
        self.assertLessEqual(c["at"][1] + c["size"][1], m["height"] - m["reserved"][3])
        self.wait(lambda st: st["assistant"]["window"]["focused"], "it to have the keyboard")
        # Escape, a real key press (wtype: -s waits for the keymap; the keys the box was given
        # say whether it arrived)
        seen = self.s.state()["assistant"]["keysSeen"]
        for _ in range(5):
            self.s.run(["wtype", "-s", "300", "-k", "Escape"], check=True)
            self.s.settle(0.3)
            if self.s.state()["assistant"]["keysSeen"] > seen:
                break
        self.wait(lambda st: not st["assistant"]["open"], "Escape to close it")
        self.s._until(lambda: self.client() is None, 5, "the window to go")

    def test_on_every_workspace_and_in_no_list(self):
        """Pinned, it goes with you to another workspace and stays open. It isn't one of your
        windows: not in the window switcher, the overview, the dock or the bar's title."""
        self.open_nova()
        self.addCleanup(lambda: self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = 1 })) end"))
        self.addCleanup(lambda: self.ipc("overview", "close"))
        st = self.wait(lambda st: st["assistant"]["window"]["focused"] and st["assistant"]["listed"] is not None, "it to have the keyboard")
        self.assertEqual(st["assistant"]["listed"], {"switcher": False, "overview": False, "title": False})
        self.assertFalse(any(x.get("key") == "slate-settings" for x in st["dock"]["slots"]), "it's in the dock")
        self.ipc("overview", "open")
        st = self.wait(lambda st: st["overview"]["open"], "the overview")
        self.s.settle(0.5)
        self.assertFalse(self.s.state()["assistant"]["listed"]["overview"], "it's in the overview")
        self.ipc("overview", "close")
        self.wait(lambda st: not st["overview"]["open"])
        self.s.hyprctl("dispatch", "function() hl.dispatch(hl.dsp.focus({ workspace = 2 })) end")
        self.s._until(lambda: self.s.monitor()["activeWorkspace"]["id"] == 2, 5, "workspace 2")
        self.s.settle(0.5)
        self.assertTrue(self.s.state()["assistant"]["open"], "it closed going to another workspace")
        c = self.client()
        self.assertEqual(c["workspace"]["id"], 2, "it stayed behind on the workspace it opened on")

    def test_dragged_by_its_header_with_the_pointer(self):
        """Pressed on its header, moved and let go, Hyprland moves the window with the pointer."""
        c = self.open_nova()
        grab = (c["at"][0] + self.u(120), c["at"][1] + self.u(28))
        with self.pointer() as ptr:
            ptr.drag(grab, (grab[0] - 160, grab[1] + 96))
        self.s._until(lambda: self.client()["at"] != c["at"], 5, "the window to follow the pointer")
        d = self.placed()
        self.assertAlmostEqual(d["at"][0], c["at"][0] - 160, delta=3)
        self.assertAlmostEqual(d["at"][1], c["at"][1] + 96, delta=3)
        self.assertEqual(d["size"], c["size"], "moving it changed its size")

    def test_slides_back_under_the_menu_bar(self):
        """Dragged by its header up over the menu bar (or down past it, with the bar at the
        bottom) and let go, it's put back below the bar, as every floating window is
        (slateKeepUnderBar): with no title bar of Slate's to make room for, its top at the bar's
        edge."""
        self.keep_setting("barPosition")
        for edge, toward in (("top", -2000), ("bottom", 2000)):
            with self.subTest(edge):
                self.config("barPosition", edge)
                self.wait(lambda st: st["barEdge"] == edge)
                side = {"top": 1, "bottom": 3}[edge]
                self.s._until(lambda: self.s.monitor()["reserved"][side] > 0, 8, f"nothing kept clear for the bar on the {edge}")
                self.s.settle(0.5)
                m = self.s.monitor()
                c = self.open_nova()
                grab = (c["at"][0] + self.u(120), c["at"][1] + self.u(28))
                with self.pointer() as ptr:
                    ptr.drag(grab, (grab[0], max(1, grab[1] + toward)))
                self.s._until(lambda: self.client()["at"] != c["at"], 5, "the window to move")
                d = self.placed()
                if edge == "top":
                    self.assertEqual(d["at"][1], m["reserved"][1], f"not back below the bar: {d['at']}")
                else:
                    self.assertEqual(d["at"][1], m["height"] - m["reserved"][3] - 40, f"not back above the bar: {d['at']}")

    def test_resized_by_its_edges_and_kept(self):
        """Its edges resize it, as any window's do (Hyprland), never smaller than its least; the
        size it's left at is kept: closed and opened again, it's that size, in the middle."""
        c = self.open_nova()
        mid = c["at"][1] + c["size"][1] // 2
        right = c["at"][0] + c["size"][0] + 2          # (just outside the edge: Hyprland's grab area)
        with self.pointer() as ptr:
            ptr.drag((right, mid), (right + 100, mid))
        self.s._until(lambda: self.client()["size"][0] > c["size"][0], 5, "it to get wider")
        d = self.placed()
        self.assertAlmostEqual(d["size"][0], c["size"][0] + 100, delta=4)
        self.assertEqual(d["at"][0], c["at"][0], "its left edge moved")
        # Its bottom edge, up much further than it can go: no shorter than its least
        bottom = d["at"][1] + d["size"][1] + 2
        x = d["at"][0] + d["size"][0] // 2
        with self.pointer() as ptr:
            ptr.drag((x, bottom), (x, d["at"][1] + 20))
        self.s._until(lambda: self.client()["size"][1] < d["size"][1], 5, "it to get shorter")
        e = self.placed()
        win = self.s.state()["assistant"]["window"]
        self.assertAlmostEqual(e["size"][1], self.u(win["minH"]), delta=2, msg="not as short as it goes")
        # Kept: the size, in Slate's units, and again once it's opened again
        self.wait(lambda st: abs(st["assistant"]["window"]["wantW"] * self.scale - e["size"][0]) <= 2
                  and abs(st["assistant"]["window"]["wantH"] * self.scale - e["size"][1]) <= 2, "its size to be kept")
        self.ipc("assistant", "close")
        self.s._until(lambda: self.client() is None, 5, "the window to go")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["window"]["mapped"], "it to open again")
        again = self.placed()
        self.assertAlmostEqual(again["size"][0], e["size"][0], delta=2, msg="it didn't keep its width")
        self.assertAlmostEqual(again["size"][1], e["size"][1], delta=2, msg="it didn't keep its height")
        self.assertAlmostEqual(again["at"][0] + again["size"][0] / 2, self.s.monitor()["width"] / 2, delta=3, msg="it didn't open in the middle")

    def test_steps_aside_while_the_bar_is_arranged(self):
        """While the menu bar's being arranged, Nova steps out of the way as Settings does (its
        window hidden, Hyprland fading it), still open, and comes back once that's done."""
        self.open_nova()
        self.addCleanup(lambda: self.ipc("bar", "edit", "done"))
        self.ipc("test", "arrange", "start", "", "", "")
        self.wait(lambda st: st["bar"]["arranging"], "arranging to start")
        self.s._until(lambda: self.client() is None, 5, "Nova's window to step aside")
        self.assertTrue(self.s.state()["assistant"]["open"], "Nova closed instead of stepping aside")
        self.ipc("bar", "edit", "done")
        self.wait(lambda st: not st["bar"]["arranging"], "arranging to end")
        self.s._until(lambda: self.client() is not None, 5, "Nova's window to come back")

    def test_closed_by_hyprland_and_opened_again(self):
        """Closed from outside Slate (Super+Q: Hyprland closes it), it opens again the next time,
        built afresh, with the conversation still there."""
        self.open_nova()
        self.ipc("test", "nova", json.dumps({"asked": "Still here?", "answer": "Yes."}))
        self.addCleanup(lambda: self.ipc("test", "nova", "{}"))
        addr = self.client()["address"]
        self.s.hyprctl("dispatch", f'function() hl.dispatch(hl.dsp.window.close({{ window = "address:{addr}" }})) end')
        self.wait(lambda st: not st["assistant"]["open"], "it to close")
        self.s._until(lambda: self.client() is None, 5, "the window to go")
        self.ipc("assistant", "open")
        st = self.wait(lambda st: st["assistant"]["open"] and st["assistant"]["window"]["mapped"], "it to open again")
        self.assertEqual((st["assistant"]["turns"], st["assistant"]["answer"]), (1, "Yes."), "the conversation went with the window")
        # Slate goes by the new window, not the closed one (which Hyprland's list can keep a while
        # after it's gone): it has the keyboard, so Super+K closes it, and closed it's gone
        self.wait(lambda st: st["assistant"]["window"]["focused"], "the new window to have the keyboard")
        self.ipc("assistant", "toggle")
        self.wait(lambda st: not st["assistant"]["open"] and not st["assistant"]["window"]["mapped"], "Super+K to close the new window")


class NovaWindow(NovaWindowChecks, LiveCase):
    pass


class NovaWindowAt125(NovaWindow):
    """All of the above at 125% Interface size, in a Slate of its own."""
    scale = 1.25

    @classmethod
    def setUpClass(cls):
        if not in_container():
            raise unittest.SkipTest("live tests run in the test container")
        Session.stop_shared()
        cls.s = Session(settings={"uiScale": 1.25})
        atexit.register(cls.s.stop)
        cls.s.start()

    @classmethod
    def tearDownClass(cls):
        cls.s.stop()
