// Slate Software's installs, removals and updates (scripts/software.py), one at a time, in order.
// Kept out here rather than in the window (SoftwareWindow.qml) so a job carries on when the window
// goes: closed with Super+Q it's built afresh, and a job running inside it would end part-way.
// Opened again, the window shows the same job and its progress.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: jobs
    readonly property string script: Quickshell.shellPath("scripts/software.py")
    // queue: [{ what: "install"|"remove"|"update-apps"|"update-system", id, name }]; busy: the
    // one running (and its progress, 0–100); note: how the last one went, when it didn't
    property var queue: []
    property var busy: null
    property int progress: 0
    property string note: ""
    // A job ended (the window, when it's there, looks again at what's installed and waiting)
    signal done()
    // (the tests: how a job goes, "ok" or what went wrong, in place of running it; and how long it takes)
    property var pretend: undefined
    property int pretendMs: 600

    function act(what, id, name) {
        if (busy && busy.what === what && busy.id === (id || "")) return;
        if (queue.some(q => q.what === what && q.id === (id || ""))) return;
        queue = queue.concat([{ what: what, id: id || "", name: name || "" }]);
        next();
    }
    function waiting(what, id) {
        return (!!busy && busy.what === what && busy.id === id) || queue.some(q => q.what === what && q.id === id);
    }
    function next() {
        if (busy || queue.length === 0) return;
        busy = queue[0];
        queue = queue.slice(1);
        progress = 0;
        note = "";
        if (pretend === undefined) {
            run.command = [script, busy.what].concat(busy.id ? [busy.id] : []);
            run.running = true;
            return;
        }
        progress = 50;
        pretendRun.restart();
    }
    function finished() {
        busy = null;
        done();
        next();
    }
    Timer { id: pretendRun; interval: jobs.pretendMs; onTriggered: { if (jobs.pretend !== "ok") jobs.note = jobs.pretend; jobs.finished(); } }
    Process {
        id: run
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("progress ")) { jobs.progress = parseInt(line.slice(9)) || 0; return; }
                if (line === "ok" || line === "error canceled") return;
                if (line.startsWith("error ")) jobs.note = line.slice(6);
            }
        }
        onExited: jobs.finished()
    }
}
