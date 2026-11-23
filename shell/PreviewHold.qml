pragma Singleton

// Windows closing: every live window preview (WindowPreview.qml) holds still for a moment.
//
// A window capture asked for just as Hyprland closes that window kills Slate ("The Wayland
// connection experienced a fatal error: Invalid argument": Hyprland has closed the window and
// Slate hasn't heard yet; docs/ARCHITECTURE.md, "Workarounds for bugs elsewhere"). Windows mostly
// close several at once, and the first one closing rebuilds the lists the previews come from,
// which started fresh captures of the others, closing too. So the moment any window closes
// (Quickshell's list of windows loses one, or Hyprland's closewindow, whichever comes first),
// every preview holds: no new captures and no frames asked for (held). Each further close starts
// the moment again.
//
// And the windows Hyprland has said are closing (closing: address without "0x" -> true): a
// preview of one never captures it again. Kept a while, for previews made again from a list that
// still has the window; an address Hyprland gives a new window comes off at once.
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root
    readonly property bool held: holdTimer.running
    property var closing: ({})
    property int testHolds: 0           // (tests: how many closes have held the previews)
    property int testStopped: 0         // (tests: previews stopped as their own window closed)

    function hold() {
        holdTimer.restart();
        testHolds++;
    }
    Timer { id: holdTimer; interval: 250 }
    Timer { id: forget; interval: 10000; onTriggered: root.closing = ({}) }

    // Quickshell's list of windows losing one: usually the first word that a window closed
    Connections {
        target: ToplevelManager.toplevels
        function onObjectRemovedPre() { root.hold(); }
    }
    Connections {
        target: Config
        function onWindowClosed(address) {
            root.hold();
            const m = Object.assign({}, root.closing);
            m[String(address).replace(/^0x/, "")] = true;
            root.closing = m;
            forget.restart();
        }
        function onWindowOpened(data) {                    // "address,workspace,class,title"
            const a = data.split(",")[0].replace(/^0x/, "");
            if (root.closing[a] === undefined) return;
            const m = Object.assign({}, root.closing);
            delete m[a];
            root.closing = m;
        }
    }
}
