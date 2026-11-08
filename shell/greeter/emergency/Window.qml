// The emergency login screen's window (see shell.qml), on the first screen

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    required property var modelData            // { screen, greeter: shell.qml's root }
    screen: modelData.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "slate-greeter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "#0f1216"
    Box { anchors.fill: parent; greeter: modelData.greeter }
}
