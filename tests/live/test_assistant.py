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

from live import LiveCase

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

    def test_only_one_at_a_time(self):
        """Opening it closes the launcher, and the launcher closes it."""
        self.ipc("launcher", "open")
        self.wait(lambda st: st["launcher"]["open"])
        self.ipc("assistant", "open")
        st = self.wait(lambda st: st["assistant"]["open"])
        self.assertFalse(st["launcher"]["open"])
        self.ipc("launcher", "open")
        st = self.wait(lambda st: st["launcher"]["open"])
        self.assertFalse(st["assistant"]["open"])
        self.ipc("launcher", "close")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.ipc("bar", "panel", "control")
        st = self.wait(lambda st: st["popout"] == "control")
        self.wait(lambda st: not st["assistant"]["open"], "the prompt window to give way to the panel")
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

    def test_did_only_from_this_run(self):
        """What it did comes from Slate's server for the run in hand: anything else is ignored."""
        self.ipc("test", "nova", json.dumps({"asked": "x", "working": True}))
        self.ipc("assistant", "did", json.dumps({"run": "someone-else", "id": 1, "text": "Shut down", "state": "done"}))
        self.s.settle(0.3)
        self.assertEqual(self.nova()["actions"], [])


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
