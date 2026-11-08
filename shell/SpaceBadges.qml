// Space badges: a window opened from a space (Spaces.qml) wears that space's icon and colour
// in its top left corner. When the pointer comes near, the badge fades across to the top
// right corner, out of the way; it goes back once focus moves to another window.
// Settings → Menu bar → Space badges on windows.
//
// scripts/spaces.py notes which windows it opened for which space (by Hyprland's stable
// window id, which isn't reused like addresses are). Each badge sits in a surface of its
// own above the window's top edge, placed from Hyprland's window positions: those are read again on
// Hyprland's window and workspace events, and every half second while any badge is up
// (Hyprland sends no event when a window is resized or dragged).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    // A Slate overlay is open (launcher, panels, switchers): badges step aside
    property bool suppressed: false
    readonly property bool wanted: Config.s.spaceBadges

    readonly property real size: 26          // the badge
    readonly property real pad: 6            // room around it that already counts as "near"
    readonly property real inset: 8          // from the window's corner
    readonly property real zone: size + pad * 2

    // stableId -> space id, from scripts/spaces.py. A file can only be watched once it
    // exists, so it's made empty at start if missing; it's also read again just after
    // windows open or close, in case a change slipped past the watch (the script replaces
    // the file rather than writing into it)
    property var owners: ({})
    readonly property string ownersPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate/space-windows.json"
    Process {
        running: true
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$0\")\" && { [ -e \"$0\" ] || echo '{}' > \"$0\"; }", root.ownersPath]
        onExited: ownersFile.reload()
    }
    Timer { id: ownersLater; interval: 700; onTriggered: ownersFile.reload() }
    Connections { target: Spaces; function onRestoringChanged() { ownersLater.restart(); } }
    FileView {
        id: ownersFile
        path: root.ownersPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.owners = JSON.parse(text()) || {}; } catch (e) { root.owners = {}; } }
        onLoadFailed: root.owners = {}
    }
    readonly property bool tracking: wanted && Object.keys(owners).length > 0

    // stableId -> { screen, x, y, w, h (Slate units on that screen), space }
    property var geo: ({})
    readonly property var keys: Object.keys(geo)

    function refresh() {
        if (!tracking) { geo = {}; return; }
        Hyprland.refreshToplevels();
        readTimer.restart();
    }
    // Each monitor's position and which workspaces it's showing, by Hyprland's monitor id.
    // From hyprctl rather than Quickshell's monitor objects, whose active workspace isn't
    // always filled in. Read at start and when workspaces, focus or monitors change.
    property var mons: ({})
    Process {
        id: monProc
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = {};
                    for (const x of JSON.parse(text))
                        m[x.id] = { name: x.name, x: x.x, y: x.y,
                                    active: (x.activeWorkspace && x.activeWorkspace.id) || 0,
                                    special: (x.specialWorkspace && x.specialWorkspace.id) || 0 };   // no id when none is open
                    root.mons = m;
                    root.read();
                } catch (e) {}
            }
        }
    }
    Timer { id: monLater; interval: 60; onTriggered: { monProc.running = false; monProc.running = true; } }
    // Hyprland answers the refresh a moment later
    Timer { id: readTimer; interval: 90; onTriggered: root.read() }
    Timer { interval: 500; repeat: true; running: root.tracking; onTriggered: root.refresh() }
    Timer { id: soon; interval: 60; onTriggered: root.refresh() }
    onTrackingChanged: refresh()
    onOwnersChanged: refresh()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow") ownersLater.restart();
            if (/^(workspace|focusedmon|activespecial|moveworkspace|monitor)/.test(event.name)) monLater.restart();
            if (!root.tracking) return;
            if (/^(openwindow|closewindow|movewindow|changefloatingmode|fullscreen|workspace|focusedmon|activespecial|moveworkspace|activewindow)/.test(event.name))
                soon.restart();
        }
    }

    function read() {
        const out = {};
        const tops = Hyprland.toplevels.values;
        // Workspaces with a fullscreen window: only that window shows there
        const fullOn = {};
        for (const t of tops) {
            const o = t.lastIpcObject;
            if (o && o.fullscreen === 2 && o.workspace) fullOn[o.workspace.id] = true;
        }
        for (const t of tops) {
            const o = t.lastIpcObject;
            if (!o || !o.at || !o.size || !o.mapped || o.hidden) continue;
            const space = owners[String(o.stableId)];
            if (!space) continue;
            const mon = mons[o.monitor], wsId = o.workspace ? o.workspace.id : 0;
            if (!mon || !wsId) continue;
            // Only on a workspace that's showing (a special one only while it's open)
            const showing = wsId > 0 ? (mon.active === wsId && mon.special === 0) : mon.special === wsId;
            if (!showing || o.fullscreen === 2 || fullOn[wsId]) continue;
            const scr = Quickshell.screens.find(s => s.name === mon.name);
            if (!scr) continue;
            const k = Config.uiScale;
            const w = o.size[0] / k, h = o.size[1] / k;
            if (w < zone * 2 + inset * 2 || h < zone + inset * 2) continue;     // too small to wear one     // too small to wear one
            out[String(o.stableId)] = { screen: scr, x: (o.at[0] - mon.x) / k, y: (o.at[1] - mon.y) / k, w: w, h: h, space: space };
        }
        geo = out;
    }

    // The focus moved to another window: every badge goes back to its first corner
    signal resetCorners()
    Connections { target: Hyprland; function onActiveToplevelChanged() { root.resetCorners(); } }

    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    Variants {
        model: root.keys
        // A strip along the window's top edge, clear and letting the pointer through
        // except where the badge is, so the badge changes corners by fading out and back
        // in at the other end of the strip rather than moving the surface (which Hyprland
        // would slide across)
        PanelWindow {
            id: badge
            required property string modelData
            readonly property var g: root.geo[modelData] ?? null
            readonly property var space: g ? Spaces.list.find(s => s.id === g.space) ?? null : null
            // Which top corner it should be in, and the one it's drawn in (they differ
            // while it fades out to move)
            property bool right: false
            property bool shownRight: false
            onRightChanged: hop.restart()
            Connections { target: root; function onResetCorners() { badge.right = false; } }
            SequentialAnimation {
                id: hop
                NumberAnimation { target: face; property: "opacity"; to: 0; duration: 90; easing.type: Easing.InQuad }
                ScriptAction { script: badge.shownRight = badge.right }
                NumberAnimation { target: face; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutQuad }
            }

            screen: g ? g.screen : null
            visible: !!g && !!space && root.wanted && !root.suppressed
            anchors { top: true; left: true }
            margins.left: g ? Math.round(g.x) : 0
            margins.top: g ? Math.round(g.y + root.inset - root.pad) : 0
            implicitWidth: g ? Math.round(g.w) : root.zone
            implicitHeight: root.zone
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-space-badge"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: zoneItem }

            // The badge and the room around it that counts as "near"
            Item {
                id: zoneItem
                width: root.zone; height: root.zone
                x: badge.shownRight ? badge.width - root.inset - root.size - root.pad : root.inset - root.pad
                // The pointer is near: go to the other top corner
                HoverHandler { onHoveredChanged: if (hovered) badge.right = !badge.shownRight }

                Rectangle {
                    id: face
                    anchors.centerIn: parent
                    width: root.size; height: root.size
                    radius: 8
                    color: badge.space ? badge.space.colour : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.22)
                    Text {
                        anchors.centerIn: parent
                        text: badge.space ? String.fromCodePoint(Spaces.iconOf(badge.space)) : ""
                        color: "#1b1f26"
                        font.family: tabler.name
                        font.pixelSize: 15
                    }
                }
            }
        }
    }
}
