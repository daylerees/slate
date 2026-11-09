// Logging out, restarting or shutting down: fades a screen to black as the goodbye sound
// plays (Config.leaving, over Config.leaveFade). Above everything, and swallows clicks so
// nothing is pressed on the way out.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-fade-out"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0
        NumberAnimation on opacity { to: 1; duration: Config.leaveFade; easing.type: Easing.InOutQuad }
    }
}
