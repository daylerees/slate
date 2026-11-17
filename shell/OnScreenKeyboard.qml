// The on-screen keyboard on the desktop (Settings → Accessibility → On-screen keyboard; Super+Alt+K):
// Slate's keys (OnScreenKeys.qml) at the bottom of the screen you're on, typing into the app
// you're in through wtype (Wayland's virtual keyboard). It never takes the keyboard itself, so
// what you're typing into keeps it. Its hide key puts it away; Super+Alt+K brings it back.
// The lock and login screens have the same keys inside them (LoginScreen.qml), as nothing else
// can show over them.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    // Put away (its hide key) until asked for again; the setting stays on
    property bool hidden: false
    readonly property bool shown: Config.s.onScreenKeyboard && !hidden && !Config.isLoginScreen
    property bool haveWtype: true
    property int sent: 0                    // (the tests: keys sent)
    property string last: ""                // (…and the last)
    function toggle() {
        if (!Config.s.onScreenKeyboard) { Config.s.onScreenKeyboard = true; hidden = false; return; }
        hidden = !hidden;
    }
    Connections { target: Config.s; function onOnScreenKeyboardChanged() { root.hidden = false; } }

    Process {
        running: true
        command: ["sh", "-c", "command -v wtype"]
        onExited: code => { root.haveWtype = code === 0; Config.wtypeAvailable = root.haveWtype; }
    }
    // Each key, as wtype types it: text after "--" (it can start with a dash), names with -k
    function send(args) {
        sent++;
        last = args.join(" ");
        if (!haveWtype || Config.testMode) return;
        Quickshell.execDetached(["wtype"].concat(args));
    }

    LazyLoader {
        active: root.shown
        PanelWindow {
            screen: Config.focusedScreen
            color: "transparent"
            anchors { bottom: true }
            // (above the dock when it's at the bottom, whether it's showing or not: windows go
            // under the dock, so its room isn't kept; the keyboard's own room is, below)
            margins.bottom: 12 + (Config.s.dockPosition === "bottom" ? Config.s.dockIconSize + 28 : 0)
            // (room round the keys for their shadow)
            implicitWidth: keys.width + 2 * Config.shadowReach
            implicitHeight: keys.height + 2 * Config.shadowReach
            // (its space kept, as the dock's is: it sits above the dock, and windows make room for
            // it, so what you're typing into isn't hidden under it)
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: implicitHeight
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "slate-osk"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            OnScreenKeys {
                id: keys
                anchors.centerIn: parent
                Shadow {}
                onTyped: t => root.send(["--", t])
                onKey: name => root.send(["-k", name])
                onHide: root.hidden = true
            }
        }
    }
}
