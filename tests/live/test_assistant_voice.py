"""Talking to Nova (Settings → Assistant → Voice, NovaVoice.qml): holding Super+K (its bind's
own press and let-go, run through hyprctl: a virtual keyboard's keys don't reach Hyprland's
binds, so wtype can't press it) or the microphone listens, and letting go sends what was
said; a quick press still just opens Nova. Never with the setting off, in Private Mode or once
the window's closed. The session's pw-record and whisper-cli are stand-ins
(tests/fixtures/voice, SLATE_VOICE_TOOLS): no microphone is opened, and what's "heard" is
$HOME/.voice-transcript."""
import glob
import json
import os
import threading
import time

from live import LiveCase


class NovaVoice(LiveCase):
    def setUp(self):
        super().setUp()
        for key in ("assistantEnabled", "assistantRisksAccepted", "assistantAgent", "assistantCommand",
                    "assistantVoice", "assistantKeepChat", "privateMode", "clickVolume"):
            self.keep_setting(key)
        self.home = self.s.env["HOME"]
        self.model = os.path.join(self.s.h.data, "slate", "whisper", "ggml-base.bin")
        self.addCleanup(lambda: self.ipc("test", "voiceCheck"))
        self.addCleanup(self.forget)
        self.addCleanup(lambda: self.ipc("test", "assistantAccepted", ""))
        self.addCleanup(lambda: self.ipc("test", "nova", "{}"))
        self.addCleanup(lambda: self.ipc("assistant", "close"))
        self.addCleanup(lambda: self.ipc("voice", "cancel"))
        self.config("assistantRisksAccepted", "1")
        self.config("assistantEnabled", "true")
        self.config("assistantKeepChat", "false")
        # An agent that answers at once, so what was sent can be seen arriving
        self.config("assistantAgent", "custom")
        self.config("assistantCommand", "echo ok")
        self.ipc("test", "assistantAccepted", "custom")
        self.config("assistantVoice", "true")
        self.with_model()
        self.forget()

    def with_model(self):
        """The speech model as a download leaves it (a sparse file of its size), looked for again."""
        os.makedirs(os.path.dirname(self.model), exist_ok=True)
        with open(self.model, "wb") as f:
            f.truncate(147951465)
        self.ipc("test", "voiceCheck")
        self.wait(lambda st: st["novaVoice"]["ready"], "whisper and the model to be found")

    def forget(self):
        for f in (".voice-calls", ".voice-transcript"):
            try:
                os.remove(os.path.join(self.home, f))
            except FileNotFoundError:
                pass

    def calls(self, tool):
        try:
            with open(os.path.join(self.home, ".voice-calls")) as f:
                return [c for c in map(json.loads, f) if c["tool"] == tool]
        except FileNotFoundError:
            return []

    def recordings(self):
        return glob.glob(os.path.join(self.s.h.runtime, "slate-voice-*.wav"))

    def voice(self):
        return self.s.state()["novaVoice"]

    def key(self, what):
        """Super+K pressed ("Down") or let go ("Up"): what its binds run (binds.lua)."""
        self.s.hyprctl("dispatch", "function() nova%s() end" % ("Key" + what))

    def hold_key(self, seconds):
        """Super+K held for a while, in the background."""
        self.key("Down")
        t = threading.Thread(target=lambda: (time.sleep(seconds), self.key("Up")))
        t.start()
        return t

    def tap_key(self):
        self.key("Down")
        self.key("Up")

    def test_the_binds(self):
        """Super+K (with its description) presses; the let-go is K's release with any
        modifiers, never taking the key from anything."""
        binds = [b for b in self.s.hyprctl("binds", json_out=True) if (b.get("key") or "").upper() == "K"]
        press = [b for b in binds if not b["release"]]
        let_go = [b for b in binds if b["release"]]
        self.assertEqual([(b["modmask"], b["description"]) for b in press], [(64, "Slate: Ask Nova (hold to talk)")])
        self.assertEqual([(b["modmask"], b["non_consuming"], b["has_description"]) for b in let_go], [(0, True, False)])

    def test_hold_the_key(self):
        """Held: Nova opens and listens (and says so) while the key's down; let go, what was said
        is in your bubble and sent."""
        with open(os.path.join(self.home, ".voice-transcript"), "w") as f:
            f.write(" Show seconds on the clock.")
        self.ipc("test", "sounds")
        self.config("clickVolume", "60")
        press = self.hold_key(2.5)
        st = self.wait(lambda st: st["novaVoice"]["phase"] == "listening", "it to listen while the key's held", timeout=5)
        self.assertTrue(st["assistant"]["open"])
        self.assertEqual(len(self.calls("pw-record")), 1, "the microphone wasn't opened")
        self.assertTrue(self.recordings(), "nothing being recorded while held")
        press.join(timeout=10)
        st = self.wait(lambda st: st["assistant"]["asked"] == "Show seconds on the clock.", "what was said to be sent", timeout=15)
        self.assertEqual(st["novaVoice"]["phase"], "")
        self.wait(lambda st: not st["assistant"]["working"], "the answer", timeout=15)
        self.assertEqual(len(self.calls("whisper-cli")), 1)
        self.assertEqual(self.recordings(), [], "the recording was kept")
        self.assertIn("click", self.s.state()["sounds"], "no click as it started listening")

    def test_a_quick_press_still_opens_nova(self):
        self.tap_key()
        self.wait(lambda st: st["assistant"]["open"], "Nova to open")
        self.s.settle(0.8)
        st = self.s.state()
        self.assertEqual((st["novaVoice"]["phase"], st["assistant"]["asked"]), ("", ""))
        self.assertEqual(self.calls("pw-record"), [], "a quick press opened the microphone")
        # and again closes it
        self.tap_key()
        self.wait(lambda st: not st["assistant"]["open"], "Nova to close")

    def test_the_microphone_button(self):
        """The microphone at the end of the box (it calls hold and release, as the key's timer does)."""
        self.ipc("assistant", "open")
        st = self.wait(lambda st: st["assistant"]["open"] and st["novaVoice"]["mic"], "the microphone in the box")
        self.ipc("voice", "hold")
        self.wait(lambda st: st["novaVoice"]["phase"] == "listening", "it to listen")
        self.s.settle(0.6)
        self.ipc("voice", "release")
        st = self.wait(lambda st: st["assistant"]["asked"] == "Turn on glass.", "what was said to be sent", timeout=15)
        self.assertEqual(self.recordings(), [])
        # Something typed already stays, with what was said after it
        self.wait(lambda st: not st["assistant"]["working"], "the answer", timeout=15)

    def test_not_while_off(self):
        """The setting off: holding the key just opens Nova; no microphone, no button."""
        self.config("assistantVoice", "false")
        press = self.hold_key(1.5)
        self.wait(lambda st: st["assistant"]["open"], "Nova to open")
        press.join(timeout=10)
        self.ipc("voice", "hold")
        self.s.settle(0.8)
        st = self.voice()
        self.assertEqual((st["phase"], st["mic"]), ("", False))
        self.assertEqual(self.calls("pw-record"), [], "listened with Talk to Nova off")
        self.assertEqual(self.s.state()["assistant"]["asked"], "")

    def test_not_in_private_mode(self):
        self.addCleanup(lambda: self.ipc("private", "off"))
        self.ipc("private", "on")
        self.wait(lambda st: not st["assistant"]["enabled"], "Private Mode to turn the assistant off")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.ipc("voice", "hold")
        self.s.settle(0.8)
        self.assertEqual(self.voice()["phase"], "")
        self.assertEqual(self.calls("pw-record"), [], "listened in Private Mode")
        # Turned on while it listens: it stops at once, and nothing is sent
        self.ipc("private", "off")
        self.wait(lambda st: st["assistant"]["enabled"])
        self.ipc("voice", "hold")
        self.wait(lambda st: st["novaVoice"]["phase"] == "listening", "it to listen")
        self.ipc("private", "on")
        self.wait(lambda st: st["novaVoice"]["phase"] == "", "Private Mode to stop it")
        self.s.settle(0.6)
        self.assertEqual(self.calls("whisper-cli"), [], "what was heard was written down")
        self.assertEqual(self.recordings(), [])
        self.assertEqual(self.s.state()["assistant"]["asked"], "")

    def test_closing_the_window_stops_it(self):
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.ipc("voice", "hold")
        self.wait(lambda st: st["novaVoice"]["phase"] == "listening", "it to listen")
        self.ipc("assistant", "close")
        self.wait(lambda st: st["novaVoice"]["phase"] == "", "closing to stop it")
        self.s.settle(0.6)
        self.assertEqual(self.calls("whisper-cli"), [])
        self.assertEqual(self.recordings(), [])
        self.assertEqual(self.s.state()["assistant"]["asked"], "")

    def test_without_the_model(self):
        """No model yet: Nova says where to get it, and the microphone is never opened."""
        os.remove(self.model)
        self.ipc("test", "voiceCheck")
        self.wait(lambda st: not st["novaVoice"]["model"], "the model to be missed")
        self.ipc("assistant", "open")
        self.wait(lambda st: st["assistant"]["open"])
        self.ipc("voice", "hold")
        st = self.wait(lambda st: st["novaVoice"]["note"] != "", "Nova to say why")
        self.assertIn("Settings → Assistant → Voice", st["novaVoice"]["note"])
        self.assertEqual(self.calls("pw-record"), [])

    def test_switching_on_asks_to_download(self):
        """Settings → Assistant → Voice: without the model, turning it on asks first (with its
        size); Cancel leaves it off. With the model there, it just turns on."""
        os.remove(self.model)
        self.ipc("test", "voiceCheck")
        self.wait(lambda st: not st["novaVoice"]["model"])
        self.config("assistantVoice", "false")
        self.addCleanup(lambda: self.ipc("settings", "close"))
        # (asked again if Settings was still being rebuilt after an earlier test closed it)
        for attempt in range(3):
            self.ipc("settings", "page", "assistant")
            try:
                self.wait(lambda st: st["settings"]["open"] and st["settings"]["section"] == "assistant", "the Assistant page", timeout=6)
                break
            except AssertionError:
                if attempt == 2:
                    raise
        self.ipc("test", "voiceSwitch", "true")
        st = self.wait(lambda st: st["asking"] == "Download the speech model?", "the question")
        self.assertIn("148 MB", st["askingBody"])
        self.assertIn("never leaves your computer", st["askingBody"])
        self.ipc("test", "answer", "false")
        self.wait(lambda st: not st["power"]["open"])
        self.assertEqual(self.setting("assistantVoice"), "false", "Cancel turned it on")
        self.assertFalse(self.voice()["downloading"])
        self.with_model()
        self.ipc("test", "voiceSwitch", "true")
        for _ in range(30):
            if self.setting("assistantVoice") == "true":
                break
            self.s.settle(0.1)
        self.assertEqual(self.setting("assistantVoice"), "true")
        self.assertFalse(self.s.state()["power"]["open"], "asked with the model already there")
