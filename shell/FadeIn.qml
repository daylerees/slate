// Logging in: covers a screen in the dark background Hyprland shows while Slate starts (misc.lua
// background_color, the login screen's colour), so there's no step from it, then fades it away as the welcome sound plays
// (Config.welcoming / welcomeFading). Above everything, and never takes the pointer.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-fade-in"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
        anchors.fill: parent
        color: "#0f1216"
        opacity: Config.welcomeFading ? 0 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: Config.ms(2600); easing.type: Easing.InOutQuad
                onRunningChanged: if (!running && Config.welcomeFading) Config.welcoming = false
            }
        }
    }
}
