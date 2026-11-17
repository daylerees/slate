// Slate Software's installs, removals and updates (scripts/software.py), one at a time, in order.
// Each runs as a process of its own (`software.py job …`), not inside Slate, and keeps how it's
// going in a file this follows (Slate's runtime folder: slate/software-job.json): a reload or restart of
// Slate (or the window closed with Super+Q) can't cut a job off, and Slate picks up one still
// running when it starts again, with its progress. (What's queued behind it is Slate's own, and
// starts again from the window.)

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: jobs
    readonly property string script: Quickshell.shellPath("scripts/software.py")
    readonly property string jobFile: Config.runtimeDir + "/slate/software-job.json"
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
        const j = queue[0];
        queue = queue.slice(1);
        progress = 0;
        note = "";
        if (pretend !== undefined) {
            busy = j;
            progress = 50;
            pretendRun.restart();
            return;
        }
        // Its own process: told which job it is (token), so an older job's file isn't taken for it
        j.token = String(Date.now());
        busy = j;
        Quickshell.execDetached([script, "job", j.token, j.what].concat(j.id ? [j.id] : []));
        alive.restart();
    }
    // (the tests: a pretend job still going ends now, as a new pretend starts)
    function endPretend() { if (pretendRun.running) { pretendRun.stop(); finished(); } }
    function finished() {
        busy = null;
        alive.stop();
        done();
        next();
    }
    Timer { id: pretendRun; interval: jobs.pretendMs; onTriggered: { if (jobs.pretend !== "ok") jobs.note = jobs.pretend; jobs.finished(); } }

    // ---- Following the job's file -----------------------------------------------------------
    function take(state) {
        if (!state || !state.token) return;
        const mine = !!busy && busy.token === state.token;
        if (!mine) {
            // A job running when Slate started (or reloaded): picked up, unless it's finished
            if (busy || state.done || pretend !== undefined) return;
            busy = { what: state.what, id: state.id || "", name: "", token: state.token, pid: state.pid };
            alive.restart();
        }
        busy.pid = state.pid;
        progress = state.progress || 0;
        if (!state.done) return;
        const r = String(state.result || "");
        if (r.startsWith("error ") && r !== "error canceled") note = r.slice(6);
        finished();
    }
    FileView {
        id: file
        path: jobs.jobFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { jobs.take(JSON.parse(text())); } catch (e) {} }
    }
    // While a job runs: is it still there? (a job ended without saying so, say by a power cut,
    // would otherwise stay "running"), and the file read again in case a change was missed.
    // Only while one runs
    Timer {
        id: alive
        interval: 3000
        repeat: true
        onTriggered: {
            file.reload();
            if (jobs.busy && jobs.busy.pid) { check.command = ["kill", "-0", String(jobs.busy.pid)]; check.running = true; }
        }
    }
    Process {
        id: check
        onExited: code => {
            if (code === 0 || !jobs.busy) return;
            // Gone without finishing (its file says so if it did): read it once more, then let it go
            file.reload();
            Qt.callLater(() => { if (jobs.busy && jobs.busy.pid && !check.running) { jobs.note = "Slate lost track of that, so it may not have finished. Have a look, then try again if you need to."; jobs.finished(); } });
        }
    }
}
