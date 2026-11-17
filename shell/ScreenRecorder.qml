// Screen recording (the Screenshot panel's Record, Super+Shift+Print, slate ipc call record …):
// scripts/record.sh records, one at a time, and leaves $RUNTIME/slate-recording while it does
// (its process, its file, when it started). The script tells Slate when it starts and ends
// (`record changed`), and this reads the mark again: Config.recording and how long it's been,
// for the bar's indicator (the Screenshot button, red, which stops it) and the panel.
//   slate ipc call record start region|window|screen
//   slate ipc call record stop
//   slate ipc call record toggle [mode]

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property string script: Quickshell.shellPath("scripts/record.sh")
    property int started: 0                 // (the tests: recordings asked for)
    FileView {
        id: mark
        path: Config.isLoginScreen ? "" : Config.runtimeDir + "/slate-recording"
        printErrors: false
        onLoaded: root.read(text())
        onLoadFailed: root.read("")
    }
    // Read again at startup too: a recording still running from before a restart of Slate
    Component.onCompleted: mark.reload()
    function read(text) {
        const lines = (text || "").split("\n");
        Config.recording = lines[0] !== "";
        Config.recordingFile = lines[1] || "";
        Config.recordingSince = parseInt(lines[2]) || 0;
        tick();
    }
    function tick() {
        Config.recordingSeconds = Config.recording ? Math.max(0, Math.floor(Date.now() / 1000) - Config.recordingSince) : 0;
    }
    // (the input that makes it worth running: a recording going, for its clock)
    Timer { running: Config.recording; interval: 1000; repeat: true; onTriggered: root.tick() }

    function start(mode) {
        started++;
        if (Config.testMode && Quickshell.env("SLATE_TEST_RECORD") !== "1") return;
        Quickshell.execDetached([script, "start", mode || "region"]);
    }
    function stop() { Quickshell.execDetached([script, "stop"]); }
    function toggle(mode) { if (Config.recording) stop(); else start(mode); }
    IpcHandler {
        target: "record"
        function start(mode: string): void { root.start(mode); }
        function stop(): void { root.stop(); }
        function toggle(mode: string): void { root.toggle(mode); }
        function changed(): void { mark.reload(); }
    }
}
