// Hot corners: rest the pointer in a screen corner to trigger an action.
// Each corner's action and the delay are set in Settings → Hot Corners.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: hc
    property var lock: null           // LockScreen: corners stand down while locked

    function run(action) {
        const ipc = (...args) => Config.slateCall(...args);
        switch (action) {
        case "lock": ipc("lock", "lock"); break;
        case "launcher": ipc("launcher", "toggle"); break;
        case "overview": ipc("overview", "toggle"); break;
        case "control": ipc("bar", "panel", "control"); break;
        case "notifications": ipc("bar", "panel", "notifications"); break;
        case "screenoff":
            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "off" })']);
            hc.screensOff = true;
            break;
        }
    }

    // Is this point (Hyprland's pixels, as `hyprctl cursorpos` gives it) in that corner of the
    // screen, give or take 4 px? (Qt keeps a screen's top-left in Hyprland's pixels and only
    // its size in Slate's, Interface size: so the point's made relative to the screen first,
    // in Hyprland's pixels, then brought to Slate's scale to meet its width and height)
    function inCorner(sc, left, top, x, y) {
        if (!sc) return false;
        const k = Config.uiScale || 1, p = { x: (x - sc.x) / k, y: (y - sc.y) / k };
        const cx = left ? 0 : sc.width;
        const cy = top ? 0 : sc.height;
        return Math.abs(p.x - cx) <= 4 && Math.abs(p.y - cy) <= 4;
    }
    // (the tests: that corner, "topLeft", "bottomRight"…, of the main display, where they are)
    function pointIn(name, x, y) { return inCorner(Config.primaryScreen, name.endsWith("Left"), name.startsWith("top"), x, y); }

    // Screens turned off from a corner: back on at your next mouse movement or key press.
    // Hyprland won't wake them by itself (mouse_move/key_press_enables_dpms are off), and the
    // idle screen-off (LockScreen.qml) only wakes the screens it turned off. This waits for a
    // second with no input first (so pulling out of the corner doesn't undo it), then the
    // first input after that turns them back on. Not held back by apps that keep the screen
    // awake (a video): those would stop it ever going idle, leaving the screens dark
    property bool screensOff: false
    IdleMonitor {
        enabled: hc.screensOff
        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: {
            if (isIdle || !hc.screensOff) return;
            hc.screensOff = false;
            Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "on" })']);
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
            // Armed = allowed to fire. Locking disarms every corner. While locked, the lock
            // screen has the pointer, so a corner never hears it leave: one used to lock
            // stayed "pointed at" and never re-armed until Slate reloaded. So unlocking
            // starts the pointer tracking afresh and, a moment later, asks Hyprland where the
            // pointer really is: elsewhere, the corner re-arms; still in it, it waits until the
            // pointer leaves (so you can't land back on the lock corner and re-lock).
            property bool armed: true
            Connections {
                target: hc.lock
                function onLockedChanged() {
                    if (hc.lock.locked) { corner.armed = false; wait.stop(); }
                    else { hover.enabled = false; settle.restart(); }
                }
            }
            Timer { id: settle; interval: 400; onTriggered: { hover.enabled = true; cursorCheck.running = true; } }
            Process {
                id: cursorCheck
                command: ["hyprctl", "-j", "cursorpos"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let inCorner = false;
                        try {
                            const q = JSON.parse(text);
                            inCorner = hc.inCorner(corner.screen, corner.modelData.left, corner.modelData.top, q.x, q.y);
                        } catch (e) {}
                        corner.armed = !inCorner;     // in it: armed again once the pointer leaves
                    }
                }
            }
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
