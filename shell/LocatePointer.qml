// Locate the pointer (Accessibility; Super+Alt+P, slate ipc call pointer locate): rings ripple
// out from the pointer for about a second, on whichever screen it's on, over everything and never
// taking a click. With Reduce motion (or animations off), a still ring for a moment instead.
//
// Where the pointer is comes from Hyprland, in its own pixels: made relative to the monitor it's
// on, then divided by Interface size (Config.uiScale) to be in Slate's units, as Slate places
// everything (CLAUDE.md, Interface size).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    property var target: null           // the screen it's showing on
    property point at: Qt.point(0, 0)   // the pointer, in that screen, in Slate's units
    property bool showing: false
    property int shows: 0               // (the tests: how many times it has shown)

    function locate() { where.running = false; where.running = true; }
    Process {
        id: where
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: { try { const p = JSON.parse(text); root.place(p.x, p.y); } catch (e) {} }
        }
    }
    // (x, y): Hyprland's pixels on the desktop. The monitor holding them, by Hyprland's own
    // layout (its x, y and its size divided by its scale), then Slate's units within it
    function place(x, y) {
        const k = Config.uiScale || 1;
        for (const m of Hyprland.monitors.values) {
            const o = m.lastIpcObject || {};
            const mx = o.x !== undefined ? o.x : m.x, my = o.y !== undefined ? o.y : m.y;
            const sc = o.scale || m.scale || 1;
            const w = (o.width || m.width) / sc, h = (o.height || m.height) / sc;
            if (x < mx || y < my || x >= mx + w || y >= my + h) continue;
            const scr = Quickshell.screens.find(s => s.name === m.name);
            if (!scr) return;
            target = scr;
            at = Qt.point((x - mx) / k, (y - my) / k);
            shows++;
            showing = false;
            showing = true;
            done.restart();
            return;
        }
    }
    Timer { id: done; interval: Config.animate ? 1200 : 900; onTriggered: root.showing = false }

    LazyLoader {
        active: root.showing && !!root.target
        PanelWindow {
            screen: root.target
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "slate-locate-pointer"
            mask: Region {}                 // never takes the pointer
            Repeater {
                model: Config.animate ? 3 : 1
                delegate: Rectangle {
                    id: ring
                    required property int index
                    readonly property real reach: 70
                    property real grow: Config.animate ? 0 : 0.6
                    width: 2 * reach * grow; height: width
                    radius: width / 2
                    x: root.at.x - width / 2; y: root.at.y - width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Config.accent
                    opacity: Config.animate ? 1 - grow : 1
                    // (each ring a little after the one before)
                    SequentialAnimation on grow {
                        running: Config.animate
                        PauseAnimation { duration: ring.index * 180 }
                        NumberAnimation { from: 0; to: 1; duration: Config.ms(800); easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
