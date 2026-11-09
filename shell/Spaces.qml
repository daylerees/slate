pragma Singleton

// Spaces: saved sets of workspaces, with their apps and layout, brought back in one click
// (the Spaces button on the bar, between Apps and the workspaces). scripts/spaces.py does
// the saving and restoring; this keeps the list for the bar and runs it.
//
//   slate ipc call spaces restore <name>     slate ipc call spaces list

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string script: Quickshell.shellPath("scripts/spaces.py")
    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/slate/spaces.json"

    property var list: []                 // saved spaces, from spaces.json
    property var live: []                 // the workspaces now (snapshot), for New Space
    property string restoring: ""         // id of the space being brought back ("" = none)
    readonly property var restoringSpace: spaceById(restoring)

    // Which open windows came from which space: stableId -> space id, from scripts/spaces.py
    // (only this Hyprland session's: window ids start over each session; the first version of
    // the file was a bare map). A file can only be watched once it exists, so it's made empty
    // at start if missing; reloadOwners() reads it again for changes that slip past the watch
    // (the script replaces the file rather than writing into it).
    property var owners: ({})
    // Window address (as Quickshell gives it) -> space id, for open windows that came from a
    // space; kept up to date by SpaceBadges.qml (the bar uses it for the focused window)
    property var spaceOfAddress: ({})
    readonly property string ownersPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate/space-windows.json"
    function reloadOwners() { ownersFile.reload(); }
    function spaceById(id) { return id ? list.find(s => s.id === id) ?? null : null; }
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$0\")\" && { [ -e \"$0\" ] || echo '{\"windows\":{}}' > \"$0\"; }", root.ownersPath]
        onExited: ownersFile.reload()
    }
    FileView {
        id: ownersFile
        path: root.ownersPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text()) || {};
                root.owners = d.windows === undefined ? d
                    : d.instance === Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? d.windows : {};
            } catch (e) { root.owners = {}; }
        }
        onLoadFailed: root.owners = {}
    }

    // Pastel colours to pick from, and icons (Tabler codepoints)
    readonly property var colours: ["#f4a6a6", "#f7b9a1", "#f9cb9c", "#f6dc8e", "#e4e59a", "#c6e3a0",
        "#a8ddb5", "#9fd9cb", "#9ad4e0", "#a3c8f0", "#aab8f2", "#bca9ee", "#d3a8e8", "#eaa9d9",
        "#f2a9c4", "#d9c3a5", "#c8ced6"]
    readonly property var icons: [0xEDBA, 0xEA77, 0xEBEF, 0xEBB8, 0xEB01, 0xEAFC, 0xF1D2, 0xEA46, 0xEA39,
        0xECF7, 0xEB54, 0xEAE5, 0xEAED, 0xEA54, 0xEAFA, 0xEB0A, 0xEAC1, 0xEB2E, 0xEABE, 0xEA38, 0xEC45,
        0xEF0E, 0xEBD2, 0xEA59, 0xEA53, 0xEB04, 0xEAAD, 0xEA76, 0xEAF8, 0xEB30, 0xED4F, 0xEA48, 0xEA88,
        0xEB1F, 0xEBF2, 0xEABD, 0xEB25, 0xEB84, 0xEC2C, 0xEC08, 0xEB35, 0xEB10, 0xEB6D, 0xEA89]

    FileView {
        path: root.file
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.list = JSON.parse(text()).spaces || []; } catch (e) { root.list = []; } }
        onLoadFailed: root.list = []
    }

    // ---- Doing things ----------------------------------------------------------------
    function refreshLive() { snap.running = false; snap.running = true; }
    Process {
        id: snap
        command: ["python3", root.script, "snapshot"]
        stdout: StdioCollector { onStreamFinished: { try { root.live = JSON.parse(text); } catch (e) { root.live = []; } } }
    }

    function save(name, colour, icon, workspaceIds) {
        Quickshell.execDetached(["python3", script, "save", name, String(colour), Number(icon).toString(16), workspaceIds.join(",")]);
    }
    function remove(id) {
        list = list.filter(s => s.id !== id);
        Quickshell.execDetached(["python3", script, "delete", id]);
    }
    function restore(id) {
        if (restorer.running) return;
        restoring = id;
        restorer.command = ["python3", script, "restore", id];
        restorer.running = true;
    }
    Process {
        id: restorer
        stderr: StdioCollector { id: restorerErr }
        onExited: code => {
            if (code !== 0) console.warn("spaces: restore failed:", restorerErr.text.trim());
            root.restoring = "";
        }
    }

    // Helpers for drawing a space
    function iconOf(space) { const n = parseInt(space && space.icon || "", 16); return isNaN(n) ? 0xEDBA : n; }
    function appCount(space) { return (space.workspaces || []).reduce((n, w) => n + (w.windows || []).length, 0); }
    // Each app once, in order (for the row of icons)
    function apps(space) {
        const seen = {}, out = [];
        for (const w of space.workspaces || [])
            for (const win of w.windows || []) {
                const k = win.desktopId || win["class"];
                if (!seen[k]) { seen[k] = true; out.push(k); }
            }
        return out;
    }

    IpcHandler {
        target: "spaces"
        // Bring a space back by its name (or id)
        function restore(name: string): void {
            const s = root.list.find(x => x.id === name || x.name.toLowerCase() === name.toLowerCase());
            if (s) root.restore(s.id);
        }
        function list(): string { return root.list.map(s => s.name).join("\n"); }
    }
}
