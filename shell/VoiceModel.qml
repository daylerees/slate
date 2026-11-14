// Talking to Nova: what's there for it (whisper.cpp, the speech model), and the model's
// download and deletion (scripts/voice.py). Settings → Assistant → Voice shows it; Nova's
// window asks it whether it can listen. Nothing here listens: NovaVoice.qml does, while held.
//   check()     look again (as it starts)
//   download()  fetch the model (asked first in Settings: about 148 MB), with progress
//   cancel()    stop a download (what came so far is deleted)
//   remove()    delete the model

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: vm
    visible: false
    readonly property string script: Quickshell.shellPath("scripts/voice.py")
    property string whisper: ""          // whisper.cpp's program, "" when it isn't installed
    property bool model: false           // the speech model is downloaded (and was checked)
    property real size: 147951465        // its size, in bytes (from the script)
    property bool recorder: true         // pw-record is there
    property bool looked: false
    readonly property bool ready: whisper !== "" && model && recorder
    readonly property string sizeText: Math.round(size / 1e6) + " MB"
    // A download: how far (0-1), and what went wrong ("" when nothing has)
    readonly property bool downloading: fetch.running
    property real progress: 0
    property string error: ""

    function check() { look.running = false; look.running = true; }
    function download() {
        if (fetch.running) return;
        error = ""; progress = 0;
        fetch.running = true;
    }
    function cancel() { if (fetch.running) fetch.signal(15); }
    function remove() { cancel(); drop.running = true; }

    Component.onCompleted: check()
    Process {
        id: look
        command: ["python3", vm.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    vm.whisper = String(s.whisper || "");
                    vm.model = !!s.model;
                    vm.recorder = !!s.recorder;
                    if (s.size) vm.size = s.size;
                } catch (e) {}
                vm.looked = true;
            }
        }
    }
    Process {
        id: fetch
        command: ["python3", vm.script, "download"]
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (x) { return; }
                if (e.type === "progress" && e.total > 0) vm.progress = Math.min(1, e.done / e.total);
                else if (e.type === "error" && e.kind !== "stopped") vm.error = String(e.message || "");
            }
        }
        onExited: vm.check()
    }
    Process {
        id: drop
        command: ["python3", vm.script, "delete"]
        onExited: vm.check()
    }
}
