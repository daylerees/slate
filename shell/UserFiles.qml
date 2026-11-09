// Your own tweaks, in files kept in Slate's folder (and kept when Slate updates):
//   hypr/*.lua       the Slate session's Hyprland config loads these (session/hypr/hyprland.lua):
//                    env, variables, monitors, binds, rules, autostart, hyprland
//   user/shell.qml   loaded into Slate itself
// At start, any that are missing are made from data/user-files, with instructions in them
// (scripts/user-files.sh; one that exists is never touched). Saving a Hyprland one reloads
// Hyprland's config; saving shell.qml reloads Slate. A mistake shows in a notification:
// Hyprland's config errors, a user file that failed to load, or shell.qml's QML error.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property var hyprFiles: ["env.lua", "variables.lua", "monitors.lua", "binds.lua", "rules.lua", "autostart.lua", "hyprland.lua"]
    readonly property string hyprDir: Quickshell.shellPath("hypr")
    readonly property string userQml: Quickshell.shellPath("user/shell.qml")
    readonly property string errorsPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate-hypr-errors.txt"
    property bool ready: false        // the files exist (watching a missing file doesn't work)

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Slate", "-i", "dialog-warning", "-h", "string:x-slate-page:about", title, body]);
    }

    Process {
        running: true
        command: ["sh", Quickshell.shellPath("scripts/user-files.sh"), Quickshell.shellPath("")]
        onExited: { root.ready = true; root.loadUserQml(); }
    }

    // ---- Hyprland files: reload Hyprland's config when one is saved -------------------
    Variants {
        model: root.ready ? root.hyprFiles : []
        FileView {
            id: hf
            required property string modelData
            path: root.hyprDir + "/" + modelData
            watchChanges: true
            printErrors: false
            // Editors often save by replacing the file: watch the new one too
            onFileChanged: { reloadHypr.restart(); rearm.restart(); }
            property Timer rearm: Timer { interval: 200; onTriggered: { const p = hf.path; hf.path = ""; hf.path = p; } }
        }
    }
    // Several saves in a row (or a whole folder copied in) make one reload
    Timer { id: reloadHypr; interval: 400; onTriggered: { hyprReload.running = false; hyprReload.running = true; } }
    Process {
        id: hyprReload
        command: ["hyprctl", "reload"]
        onExited: errorCheck.restart()
    }
    // Then: anything wrong? Hyprland's own config errors, and user files that failed to load
    Timer { id: errorCheck; interval: 500; onTriggered: { errorsProc.running = false; errorsProc.running = true; } }
    Process {
        id: errorsProc
        command: ["sh", "-c", "hyprctl configerrors 2>/dev/null; cat \"$0\" 2>/dev/null", root.errorsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.split("\n").map(l => l.trim()).filter(l => l !== "").join("\n");
                if (t !== "") root.notify("Hyprland config has a problem", t.slice(0, 600));
            }
        }
    }

    // ---- user/shell.qml: loaded into Slate ---------------------------------------------
    // Made from its file directly (rather than a Loader) so a mistake in it can be shown
    // instead of only logged. Saving it reloads Slate (Quickshell does that for every file
    // it has loaded; the watch here covers it too, a moment later)
    property var userObject: null
    function loadUserQml() {
        if (userObject) { userObject.destroy(); userObject = null; }
        const c = Qt.createComponent("file://" + userQml);
        const make = () => {
            if (c.status === Component.Error) {
                notify("Your shell.qml has a mistake", c.errorString().slice(0, 600));
            } else if (c.status === Component.Ready) {
                userObject = c.createObject(root);
                if (!userObject) notify("Your shell.qml has a mistake", "It couldn't be created; see `slate log`.");
            }
        };
        if (c.status === Component.Loading) c.statusChanged.connect(make);
        else make();
    }
    FileView {
        path: root.ready ? root.userQml : ""
        watchChanges: true
        printErrors: false
        onFileChanged: userReload.restart()
    }
    Timer { id: userReload; interval: 500; onTriggered: Quickshell.reload(true) }
}
