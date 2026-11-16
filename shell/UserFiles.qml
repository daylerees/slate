// Your own tweaks, in files kept in your Slate folder (Config.userDir: ~/.config/slate, wherever
// Slate's code is; kept when Slate updates):
//   hypr/*.lua       the Slate session's Hyprland config loads these (session/hypr/hyprland.lua):
//                    env, variables, monitors, binds, rules, autostart, hyprland
//   user/shell.qml   loaded into Slate itself
// At start, any that are missing are made from data/user-files, with instructions in them
// (scripts/user-files.sh; one that exists is never touched). Saving a Hyprland one reloads
// Hyprland's config; saving shell.qml reloads Slate. A mistake shows in a notification:
// shell.qml's QML error from here, and Hyprland's config errors and a user file that failed to
// load from shell.qml (hyprErrors, which runs whenever Hyprland has reloaded).

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property var hyprFiles: ["env.lua", "variables.lua", "monitors.lua", "binds.lua", "rules.lua", "autostart.lua", "hyprland.lua"]
    readonly property string hyprDir: Config.userDir + "/hypr"
    readonly property string userQml: Config.userDir + "/user/shell.qml"
    readonly property string errorsPath: Config.runtimeDir + "/slate-hypr-errors.txt"
    property bool ready: false        // the files exist (watching a missing file doesn't work)

    function notify(title, body) {
        Quickshell.execDetached(Config.notify(title, body, { icon: "dialog-warning", page: "about" }));
    }

    Process {
        running: true
        command: ["sh", Quickshell.shellPath("scripts/user-files.sh"), Config.userDir]
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
    // (anything wrong is reported by shell.qml's hyprErrors once Hyprland says it has reloaded,
    // user files that failed to load included: it reads errorsPath)
    Process {
        id: hyprReload
        command: ["hyprctl", "reload"]
    }

    // ---- user/shell.qml: loaded into Slate ---------------------------------------------
    // Made from its text, as if it were a file at the top of Slate's code (wherever your folder
    // is), so Slate's pieces (Config, Spaces…) work in it the same in every install. (Made as
    // user/shell.qml there instead, they weren't found: that folder is its own module.) Named
    // the way Quickshell names Slate's own files (Qt.resolvedUrl here: qs:@/qs/…), so it shares
    // Slate's one Config: named by its path on disk, it was given a second copy of its own
    // Made here rather than by a Loader so a mistake in it can be shown instead of only logged.
    // Saving it reloads Slate (the watch below)
    property var userObject: null
    FileView { id: userText; path: root.ready ? root.userQml : ""; blockLoading: true; printErrors: false }
    function loadUserQml() {
        if (userObject) { userObject.destroy(); userObject = null; }
        userText.reload();
        const text = userText.text();
        if (!text) return;               // (none: nothing to load)
        try {
            userObject = Qt.createQmlObject(text, root, Qt.resolvedUrl("your-shell.qml"));
        } catch (e) {
            const errs = (e && e.qmlErrors) ? e.qmlErrors.map(q => "line " + q.lineNumber + ": " + q.message).join("\n") : String(e);
            notify("Slate couldn't load your shell.qml", errs.slice(0, 600) + "\n\nSlate keeps running without it; it'll load as soon as the file is saved again.");
        }
    }
    FileView {
        path: root.ready ? root.userQml : ""
        watchChanges: true
        printErrors: false
        onFileChanged: userReload.restart()
    }
    Timer { id: userReload; interval: 500; onTriggered: Config.restartSlate() }
}
