// What's waiting to update, for apps and this computer's system (Software's engine,
// scripts/software.py daily), looked at once a day, with a calm notification at most once a day
// when anything is: "Updates are waiting", opening Software's Updates. Settings → Updates shows
// the same counts.
//
// It looks only when it's worth it: with Settings → Updates → "Tell me about app and system
// updates" on (softwareUpdateCheck), at most every 20 hours (kept in a file, so restarts don't
// count), never in game mode, and never on a metered connection (the engine waits for another).
// Never under the test suite (no network): the tests hand it what the engine would say.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string script: Quickshell.shellPath("scripts/software.py")
    readonly property string stateFile: Config.stateHome + "/slate/software-updates.json"
    readonly property real every: 20 * 3600 * 1000

    // What's known: { checked (ms), notified (ms), apps, system }
    property var known: ({})
    readonly property int apps: known.apps || 0
    readonly property int system: known.system || 0
    readonly property int waiting: apps + system
    readonly property real checkedAt: known.checked || 0
    property int looks: 0                 // (the tests: how many times it has looked)
    property int notices: 0               // (…and told you)
    Component.onCompleted: Config.softwareDailyMadeAt = Date.now()   // (…and when it was made: at Slate's start, by shell.qml)

    FileView {
        id: file
        path: root.stateFile
        printErrors: false
        onLoaded: { try { root.known = JSON.parse(text()) || {}; } catch (e) { root.known = {}; } }
    }
    function save() { file.setText(JSON.stringify(known) + "\n"); }

    // Worth looking now?
    readonly property bool due: Config.s.softwareUpdateCheck && !Config.testMode && !Config.gameMode
        && Date.now() - checkedAt > every
    // A few minutes after Slate starts (not while it's busy starting), then once an hour to see
    // whether it's due: the engine itself is only run when it is
    Timer { interval: 3 * 60 * 1000; running: true; onTriggered: root.lookIfDue() }
    Timer { interval: 3600 * 1000; running: Config.s.softwareUpdateCheck && !Config.testMode; repeat: true; onTriggered: root.lookIfDue() }
    function lookIfDue() {
        if (root.due && !run.running) { run.running = true; }
    }
    Process {
        id: run
        command: [root.script, "daily"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) { return; }
                root.found(r);
            }
        }
    }

    // What a look found (the engine's daily answer); also what Software's own look tells it, so
    // Settings shows the same counts
    function found(r) {
        if (!r || r.metered) return;            // (a metered connection: looked again later)
        looks++;
        known = Object.assign({}, known, { checked: Date.now(), apps: r.apps || 0, system: r.system || 0 });
        save();
        if (waiting > 0 && Config.s.softwareUpdateCheck && !Config.gameMode && Date.now() - (known.notified || 0) > every)
            tell();
    }
    function tookFromSoftware(apps, system) {
        known = Object.assign({}, known, { checked: Date.now(), apps: apps, system: system });
        save();
    }

    function words() {
        const a = apps === 1 ? "1 app" : apps + " apps";
        const s = system === 1 ? "1 system update" : system + " system updates";
        return apps && system ? a + " and " + s : apps ? a : s;
    }
    function tell() {
        known = Object.assign({}, known, { notified: Date.now() });
        save();
        notices++;
        notify.running = false;
        notify.running = true;
    }
    Process {
        id: notify
        command: Config.notify("Updates are waiting", root.words() + " ready to install in Software, whenever suits you.",
                               { icon: Quickshell.shellPath("assets/icon/software-64.png"),
                                 actions: ["default=Open", "open=Open Software"], wait: true })
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") Config.slateCall("software", "page", "updates")
        }
    }
}
