// Space badges: a window opened from a space (Spaces.qml) gets a 3 px border along its top
// in the space's colour, and wears the space's icon in its top left corner. When the pointer comes near, the badge fades across to the top
// right corner, out of the way; it goes back once focus moves to another window.
// Settings → Menu bar → Mark windows from a space.
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
    // Settings → Spaces. The bar's colouring and the switchers' badges use the window list
    // kept here too (Spaces.spaceOfAddress), so it's kept while any of them is on
    readonly property bool borders: Config.s.spaceBorders
    readonly property bool badges: Config.s.spaceBadges
    readonly property bool wanted: borders || badges || Config.s.spaceBarTint || Config.s.spaceSwitcherBadges

    readonly property real size: 26          // the badge
    readonly property real pad: 6            // room around it that already counts as "near"
    readonly property real inset: 8          // from the window's corner
    readonly property real zone: size + pad * 2
    readonly property real line: 3 / Config.uiScale     // the top border: 3 px on Hyprland's scale

    // stableId -> space id (Spaces.qml reads it from scripts/spaces.py's file)
    readonly property var owners: Spaces.owners
    Timer { id: ownersLater; interval: 700; onTriggered: Spaces.reloadOwners() }
    Connections { target: Spaces; function onRestoringChanged() { ownersLater.restart(); } }
    readonly property bool tracking: wanted && Object.keys(owners).length > 0

    // stableId -> { screen, x, y, w, h (Slate units on that screen), space }
    property var geo: ({})
    readonly property var keys: Object.keys(geo)

    function refresh() {
        if (!tracking) { geo = {}; Spaces.spaceOfAddress = {}; return; }
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
            if (/^(workspace|activespecial|moveworkspace)/.test(event.name)) root.startSettling();
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
        // Workspaces with a fullscreen window (only that window shows there), and how many
        // tiled windows each has (a lone one is square)
        const fullOn = {}, tiled = {};
        for (const t of tops) {
            const o = t.lastIpcObject;
            if (!o || !o.workspace) continue;
            if (o.fullscreen === 2) fullOn[o.workspace.id] = true;
            if (!o.floating && o.mapped && !o.hidden) tiled[o.workspace.id] = (tiled[o.workspace.id] || 0) + 1;
        }
        const byAddr = {};
        for (const t of tops) {
            const o = t.lastIpcObject;
            const owned = o ? owners[String(o.stableId)] : null;
            if (owned) byAddr[t.address] = owned;
        }
        Spaces.spaceOfAddress = byAddr;
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
            // The border follows the window's corners (Config.windowRadius: lone tiled and
            // maximised windows are square)
            const radius = Config.windowRadius(o, tiled[wsId]);
            out[String(o.stableId)] = { screen: scr, x: (o.at[0] - mon.x) / k, y: (o.at[1] - mon.y) / k, w: w, h: h,
                                        r: radius / k, space: space };
        }
        geo = out;
    }

    // Switching workspace slides the windows, and Hyprland doesn't say where they are on the
    // way, so borders and badges can't follow them: they vanish when a switch starts and fade
    // back in once the slide is over (Hyprland's workspace slide: 500 ms, 300 ms with fast
    // animations; animations.lua)
    readonly property int slideMs: Config.s.animations === "off" ? 0 : Config.s.animations === "fast" ? 300 : 500
    property bool settling: false
    function startSettling() {
        if (slideMs <= 0) return;
        settling = true;
        settleTimer.restart();
    }
    Timer { id: settleTimer; interval: root.slideMs + 40; onTriggered: root.settling = false }

    // The focus moved to another window: every badge goes back to its first corner
    signal resetCorners()
    Connections { target: Hyprland; function onActiveToplevelChanged() { root.resetCorners(); } }

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
            visible: !!g && !!space && (root.borders || root.badges) && !root.suppressed
            anchors { top: true; left: true }
            margins.left: g ? Math.round(g.x) : 0
            margins.top: g ? Math.round(g.y) : 0
            implicitWidth: g ? Math.round(g.w) : root.zone
            implicitHeight: root.inset - root.pad + root.zone
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-space-badge"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { item: zoneItem }

            // Hidden at once while a workspace switch slides, faded back in after. Set once
            // rather than bound to root.settling: a binding would jump to 1 when the slide
            // ends, before the fade could run
            property real reveal: 0
            Component.onCompleted: reveal = root.settling ? 0 : 1
            NumberAnimation { id: fadeIn; target: badge; property: "reveal"; to: 1; duration: 220; easing.type: Easing.OutQuad }
            Connections {
                target: root
                function onSettlingChanged() {
                    if (root.settling) { fadeIn.stop(); badge.reveal = 0; }
                    else fadeIn.restart();
                }
            }

            // The top border: the top of a window-shaped rectangle, so it follows the
            // window's rounded corners (takes no clicks: outside the mask)
            Item {
                visible: root.borders
                opacity: badge.reveal
                width: parent.width; height: root.line
                clip: true
                Rectangle {
                    width: parent.width
                    height: Math.max(root.line, badge.g ? badge.g.r * 2 + root.line : root.line)
                    radius: badge.g ? badge.g.r : 0
                    color: badge.space ? badge.space.colour : "transparent"
                }
            }

            // The badge and the room around it that counts as "near"
            Item {
                id: zoneItem
                // No badge: no size either, so the strip takes no clicks at all
                visible: root.badges
                opacity: badge.reveal
                width: root.badges ? root.zone : 0; height: width
                y: root.inset - root.pad
                x: badge.shownRight ? badge.width - root.inset - root.size - root.pad : root.inset - root.pad
                // The pointer is near: go to the other top corner
                HoverHandler { enabled: !root.settling; onHoveredChanged: if (hovered) badge.right = !badge.shownRight }

                SpaceBadge {
                    id: face
                    anchors.centerIn: parent
                    space: badge.space
                    size: root.size
                }
            }
        }
    }
}
