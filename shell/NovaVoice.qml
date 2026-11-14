// Talking to Nova (Settings → Assistant → Voice): hold Super+K, or the microphone in Nova's
// window, and say what you want. While it's held, and only then, Slate records from your
// default microphone; let go and whisper.cpp turns it into text on this computer, the text
// goes in Nova's box and is sent. The recording is deleted straight after (scripts/voice.py).
//   slate ipc call voice hold      start listening (the shortcut, after it's been held a moment)
//   slate ipc call voice release   stop, and send what was said
//   slate ipc call voice cancel    stop, and send nothing
// Never listens with the setting off, in Private Mode (which mutes the microphones anyway),
// while the screen is locked, or with Nova's window closed: closing it, locking the screen,
// Private Mode or the setting going off while it listens stops it and nothing is sent.
// Listening starts with Slate's click (Settings → Sound → Click sound); Nova's window shows
// it's listening for as long as it is. Game mode changes nothing here: it isn't an effect.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: voice
    visible: false
    property var window: null            // Nova's window (Assistant.qml)
    property var model: null             // what's there (VoiceModel.qml)
    property bool locked: false          // the screen is locked
    // "" (not listening), "starting", "listening" or "transcribing"
    property string phase: ""
    // A line for Nova's window when something stopped it ("" when there's nothing to say)
    property string note: ""
    readonly property bool on: Config.s.assistantVoice && Config.assistantOn
    readonly property bool busy: phase !== ""
    readonly property bool allowed: on && !Config.s.privateMode && !locked && !!window && !window.working
    // Released before it had started: stop as soon as it has
    property bool letGo: false

    function hold() {
        if (busy || listener.running || !window) return;
        if (!window.shown) window.openWindow();
        note = "";
        if (!Config.s.assistantVoice || !Config.assistantOn || Config.s.privateMode || locked) return;
        if (window.working) { say("Nova is still working on the last one. You can talk again when it's done."); return; }
        if (model && model.looked && !model.ready) {
            model.check();          // (installed since? the next try finds it)
            say(model.whisper === "" ? "Slate needs whisper.cpp to understand you. Install it (whisper-cpp on most systems), then try again."
                : !model.recorder ? "Slate needs pw-record (part of PipeWire's tools) to hear your microphone."
                : "Slate needs its speech model first. You can download it in Settings → Assistant → Voice.");
            return;
        }
        letGo = false;
        phase = "starting";
        listener.running = true;
    }
    function release() {
        if (phase === "starting") { letGo = true; return; }
        if (phase !== "listening") return;
        phase = "transcribing";
        listener.write("stop\n");
    }
    function cancel() {
        if (!busy) return;
        phase = "";
        listener.signal(15);
    }
    function say(text) { note = text; noteGone.restart(); }
    Timer { id: noteGone; interval: 8000; onTriggered: voice.note = "" }

    // Anything that means it mustn't listen any more stops it, and nothing is sent
    onAllowedChanged: if (!allowed && phase !== "transcribing") cancel()
    Connections {
        target: voice.window
        function onShownChanged() { if (!voice.window.shown) voice.cancel(); }
    }

    function handle(e) {
        if (!e || !e.type) return;
        if (e.type === "listening") {
            if (phase !== "starting") return;
            phase = "listening";
            Config.click();
            if (letGo) release();
        } else if (e.type === "transcribing") phase = "transcribing";
        else if (e.type === "text") {
            phase = "";
            const text = String(e.text || "").trim();
            if (text === "" || !window || !allowed) return;
            window.sendSpoken(text);
        } else if (e.type === "error") {
            phase = "";
            if (e.kind !== "private") say(String(e.message || ""));
            if ((e.kind === "no-model" || e.kind === "no-whisper") && model) model.check();
        }
    }
    Process {
        id: listener
        command: ["python3", Quickshell.shellPath("scripts/voice.py"), "listen"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => { try { voice.handle(JSON.parse(line)); } catch (e) {} } }
        onExited: voice.phase = ""
    }

    IpcHandler {
        target: "voice"
        function hold(): void { voice.hold(); }
        function release(): void { voice.release(); }
        function cancel(): void { voice.cancel(); }
    }
}
