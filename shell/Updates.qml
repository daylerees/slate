pragma Singleton

// Updates: looks for new Slate releases (scripts/update.py, from GitHub) about once a day,
// says so with a notification the first time each one is seen, and installs one when asked
// (Settings → Updates). Installing keeps your settings and overrides (settings.json, hypr/,
// user/) and backs up the previous copy.
//
//   slate ipc call updates check          slate ipc call updates install

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/update.py")
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/update.json"

    // What update.py last found and did
    property var state: ({})
    // The version installed (a release's tag, or "v0.4.2-15-g…" for a copy of the code past v0.4.2)
    property string installed: ""
    readonly property string latest: state.latest || ""
    readonly property bool available: !!state.newer && state.status !== "done"
    readonly property string status: state.status || "idle"     // idle, downloading, installing, done, failed
    readonly property bool busy: status === "downloading" || status === "installing"
    readonly property bool checking: checkProc.running
    readonly property string error: state.error || ""
    readonly property string notes: state.notes || ""
    // Something left to do by hand after updating (e.g. a sudo step), shown in Settings → Updates
    readonly property string note: state.note || ""
    readonly property string url: state.url || ""
    readonly property real checkedAt: (state.checked || 0) * 1000
    // The version kept as a backup (~/.config/slate.previous), to go back to; "" if none
    readonly property string previous: state.previous || ""

    FileView {
        path: Quickshell.shellPath("VERSION")
        printErrors: false
        onLoaded: root.installed = text().trim()
    }
    FileView {
        id: stateView
        path: root.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.state = JSON.parse(text()); } catch (e) {} }
    }

    function check(force) {
        if (checkProc.running) return;
        checkProc.command = ["python3", script, "check"].concat(force ? ["--force"] : []);
        checkProc.running = true;
    }
    Process {
        id: checkProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) { return; }
                root.state = r;
                if (r.notify && Config.s.updateCheck) root.announce(r.latest);
            }
        }
    }

    // Slate's own files changed by hand (they'd be replaced; the old copy is backed up)
    property var modified: null      // { known, changed: [], added: [] }
    function findModified() { if (!modProc.running) modProc.running = true; }
    Process {
        id: modProc
        command: ["python3", root.script, "modified"]
        stdout: StdioCollector { onStreamFinished: { try { root.modified = JSON.parse(text); } catch (e) { root.modified = null; } } }
    }

    // Runs on its own, so it carries on while Slate restarts on the new version
    function install() {
        if (busy) return;
        root.state = Object.assign({}, root.state, { status: "downloading", error: "" });
        Quickshell.execDetached(["setsid", "-f", "python3", script, "install"]);
    }

    // Back to the version before (your settings and overrides stay as they are now); the one
    // you leave becomes the backup, so it can be undone the same way
    function revert() {
        if (busy || previous === "") return;
        Quickshell.execDetached(["setsid", "-f", "python3", script, "revert"]);
    }

    // About a minute after Slate starts, then every few hours; update.py itself only asks
    // GitHub once in 20 hours
    Timer { interval: 60 * 1000; running: Config.s.updateCheck && !Config.testMode; onTriggered: root.check(false) }
    Timer { interval: 6 * 3600 * 1000; running: Config.s.updateCheck && !Config.testMode; repeat: true; onTriggered: root.check(false) }

    // "Slate v0.5.0 is available": clicking it (or "See what's new") opens Settings → Updates
    property string announcing: ""
    function announce(version) {
        announcing = version;
        notifyProc.running = false;
        notifyProc.running = true;
    }
    Process {
        id: notifyProc
        command: ["notify-send", "--app-name=Slate", "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"), "--hint=string:x-slate-page:updates",
            "--action=default=Open", "--action=open=See what's new", "--wait",
            "Slate " + root.announcing + " is available",
            (root.installed ? "You have " + root.installed.replace(/-.*/, "") + ". " : "") + "See what's new and update in Settings → Updates."]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") Config.slateCall("settings", "page", "updates")
        }
    }

    IpcHandler {
        target: "updates"
        function check(): void { root.check(true); }
        function install(): void { root.install(); }
        function revert(): void { root.revert(); }
    }
}
