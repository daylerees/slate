// New apps in a place that wasn't there when Slate started. Quickshell watches the folders apps
// are listed in (applications/, in each of XDG_DATA_DIRS) only if they exist as it starts, and
// has no way to look again: on a computer that had never installed a Flatpak, the first apps
// installed from Software never showed in the launcher until Slate restarted. bin/slate makes
// your own Flatpak folder before Slate starts, and the installer the system's, so this is for
// computers set up before that (or a folder made some other way): once one appears, Slate asks
// to restart, which brings the new apps in. Your apps and windows stay open.
//
// It only looks while something's missing: every 20 seconds, a `test -d` for each. Never under
// the test suite (test checkNow / pretendAppeared stand in).

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var confirm: null
    // The applications/ folders missing when Slate started (each of XDG_DATA_HOME, XDG_DATA_DIRS)
    property var missing: []
    property bool asked: false
    readonly property var folders: {
        const home = Config.dataHome;
        const dirs = (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":").filter(d => d !== "");
        return [home].concat(dirs).map(d => d.replace(/\/$/, "") + "/applications");
    }
    // Which of these aren't there: one line each
    function look(dirs, then) {
        check.then = then;
        check.command = ["sh", "-c", 'for d; do [ -d "$d" ] || printf "%s\\n" "$d"; done', "sh"].concat(dirs);
        check.running = true;
    }
    Process {
        id: check
        property var then: null
        stdout: StdioCollector { onStreamFinished: if (check.then) check.then(text.split("\n").filter(l => l !== "")) }
    }
    Component.onCompleted: if (!Config.testMode && !Config.isLoginScreen) look(folders, gone => root.missing = gone)
    Timer {
        interval: 20000; repeat: true
        running: root.missing.length > 0 && !root.asked && !Config.testMode
        onTriggered: root.look(root.missing, gone => { if (gone.length < root.missing.length) root.appeared(); })
    }
    function appeared() {
        if (asked || !confirm) return;
        asked = true;
        confirm.confirmWith({
            title: "Restart Slate to show your new apps?",
            body: "Your new apps are in a place Slate started looking at only now, so they'll show in the launcher once Slate restarts. Your apps and windows stay open.",
            button: "Restart", cancelLabel: "Not now", code: 0xEB13, danger: false
        }, () => Config.restartSlate());
    }
}
