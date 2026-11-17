// Settings → Backups: backing up on a schedule (scripts/backup.py, restic). Once an hour, while a
// schedule is set (the input that makes it worth running), it asks whether a backup is due
// ("due": set up, the drive there, a day or a week since the last good one) and runs one at low
// priority. Never in game mode; nothing at the login screen or in the tests. A notification only
// when one fails, or when it's been a week without a backup because the drive wasn't there.
//   slate ipc call backups now        (back up now)

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property string script: Quickshell.shellPath("scripts/backup.py")
    readonly property bool scheduled: Config.s.backupTo !== "" && Config.s.backupSchedule !== "manual"
    property bool running: false
    property string lastNudge: ""               // (the day the "a week without" note was given)
    signal finished(bool ok)
    function now() {
        if (running || Config.testMode) return;
        running = true;
        run.running = true;
    }
    Process {
        id: ask
        command: ["python3", root.script, "due"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "yes") root.now();
                else if (a === "no: away") root.maybeNudge();
            }
        }
    }
    Process {
        id: run
        command: ["python3", root.script, "run"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.running = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                root.finished(!!r.ok);
                if (!r.ok && r.error && r.error !== "away")
                    Quickshell.execDetached(Config.notify("Slate couldn't back up your files",
                        "The backup stopped before it was done" + (r.error.length > 3 ? " (" + r.error + ")" : "") + ". Settings → Backups can try again.",
                        { page: "backups" }));
            }
        }
    }
    // A week without a good backup because the drive wasn't there: say so once a day at most
    Process {
        id: nudge
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = {};
                try { s = JSON.parse(text); } catch (e) { return; }
                const day = new Date().toDateString();
                if (root.lastNudge === day) return;
                if (s.last && Date.now() / 1000 - s.last < 7 * 86400) return;
                root.lastNudge = day;
                Quickshell.execDetached(Config.notify("It's been a while since your last backup",
                    "Plug in the drive your backups go to, and Slate will back up your files by itself.", { page: "backups" }));
            }
        }
    }
    function maybeNudge() { nudge.running = false; nudge.running = true; }
    Timer {
        running: root.scheduled && !Config.gameMode && !Config.isLoginScreen && !Config.testMode
        interval: 3600000; repeat: true; triggeredOnStart: true
        onTriggered: { ask.running = false; ask.running = true; }
    }
    IpcHandler {
        target: "backups"
        function now(): void { root.now(); }
    }
}
