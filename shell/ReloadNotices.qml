// Slate's own notices for a reload that worked and one that failed (instead of Quickshell's popup).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    // No "Configuration reloaded" popup when Slate reloads (after an update or a setting that
    // needs it, or a code change): it covered the top of the screen and got in the way of the
    // panels. Slate's own notice instead (a notification, kept in history like any other), for
    // a reload that worked and one that failed, and one when Hyprland reloads its config, with
    // any errors in it
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); reloadNotice.restart(); }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup(); root.reloadFailedNotice(errorString); }
    }
    // A failed reload leaves this (the previous) Slate running, so it can say so straight away.
    // Quickshell's error is a chain of "caused by @File.qml[line:col]: …"; the last link is
    // where the mistake is, so that leads
    property string lastReloadError: ""
    property var brokenFiles: []            // the files in the failed reload's error
    function reloadFailedNotice(error) {
        if (String(error) === lastReloadError) return;      // Quickshell reports a failure twice
        lastReloadError = String(error);
        const lines = String(error).split("\n").map(l => l.trim()).filter(l => l !== "");
        const links = lines.map(l => l.match(/@([^\[\]]+)\[(-?\d+):-?\d+\]:\s*(.*)$/)).filter(m => m);
        let body;
        if (links.length) {
            const cause = links[links.length - 1];
            const where = cause[1] + (parseInt(cause[2]) > 0 ? ", line " + cause[2] : "");
            const via = links.length > 1 ? links[links.length - 2][1] : "";
            body = cause[3] + " (" + where + (via ? ", used by " + via : "") + ").";
        } else {
            body = lines.slice(0, 3).join(" ");
        }
        brokenFiles = [...new Set(links.map(m => m[1]))];
        Quickshell.execDetached(Config.notify("Slate couldn't reload",
            body + " Nothing's lost: the previous version is still running, and Slate will reload as soon as you save the fix.",
            { urgent: true, page: "about" }));
    }
    // After a failed reload Quickshell stops reloading when files change, until it's restarted.
    // So watch the files the error names, and reload as soon as one is saved
    Variants {
        model: root.brokenFiles
        FileView {
            required property string modelData
            path: Quickshell.shellPath(modelData)
            watchChanges: true
            printErrors: false
            onFileChanged: { root.brokenFiles = []; root.lastReloadError = ""; Config.restartSlate(); }
        }
    }
    Timer {
        id: reloadNotice
        interval: 600          // once the new Slate (and its notification server) is up
        onTriggered: Quickshell.execDetached(Config.notify("Slate reloaded",
            "All fresh: Slate is running on its updated files and settings.", { page: "about" }))
    }
}
