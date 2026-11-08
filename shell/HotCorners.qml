// Hot corners: rest the pointer in a screen corner to trigger an action.
// Each corner's action and the delay are set in Settings → Hot corners.

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: hc
    property var lock: null           // LockScreen: corners stand down while locked

    function run(action) {
        const ipc = (t, f, ...a) => Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", t, f, ...a]);
        switch (action) {
        case "lock": ipc("lock", "lock"); break;
        case "launcher": ipc("launcher", "toggle"); break;
        case "overview": ipc("overview", "toggle"); break;
        case "control": ipc("bar", "panel", "control"); break;
        case "notifications": ipc("bar", "panel", "notifications"); break;
        case "screenoff": Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "off" })']); break;
        }
    }

    Variants {
        model: [
            { top: true, left: true, key: "hotCornerTopLeft" },
            { top: true, left: false, key: "hotCornerTopRight" },
            { top: false, left: true, key: "hotCornerBottomLeft" },
            { top: false, left: false, key: "hotCornerBottomRight" }
        ]
        PanelWindow {
            id: corner
            screen: Config.primaryScreen           // the main display's corners (Settings → Displays)
            required property var modelData
            readonly property string action: Config.s[modelData.key]
            visible: action !== "none"
            anchors { top: modelData.top; bottom: !modelData.top; left: modelData.left; right: !modelData.left }
            implicitWidth: 2; implicitHeight: 2
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-hotcorner"
            WlrLayershell.layer: WlrLayer.Overlay
            // Armed = allowed to fire. Locking disarms every corner; after unlocking a
            // corner re-arms straight away if the pointer is elsewhere, or once the
            // pointer leaves it (so you can't land back on the lock corner and re-lock).
            property bool armed: true
            Connections {
                target: hc.lock
                function onLockedChanged() {
                    if (hc.lock.locked) { corner.armed = false; wait.stop(); }
                    else settle.restart();
                }
            }
            Timer { id: settle; interval: 400; onTriggered: corner.armed = !hover.hovered }
            HoverHandler {
                id: hover
                // Trigger once per visit: leave the corner to go again
                onHoveredChanged: {
                    if (hovered) { if (corner.armed) wait.restart(); }
                    else { wait.stop(); if (!settle.running && !(hc.lock && hc.lock.locked)) corner.armed = true; }
                }
            }
            Timer { id: wait; interval: Config.s.hotCornerDelay; onTriggered: if (corner.armed) hc.run(corner.action) }
        }
    }
}
