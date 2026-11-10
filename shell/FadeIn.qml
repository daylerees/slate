// Logging in: covers a screen in the dark background Hyprland shows while Slate starts (misc.lua
// background_color, the login screen's colour), so there's no step from it. Slate's logo fades
// in on it, then the cover and logo fade away together as the welcome sound plays
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

        // The logo: rises gently into place while the cover waits for the welcome sound.
        // The cover is always dark, so it keeps its dark-theme colours in light mode too.
        SlateLogo {
            id: logo
            dark: true
            size: Math.round(Math.min(parent.width, parent.height) * 0.075)
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -size * 0.1
            opacity: 0
            scale: 0.96
            Component.onCompleted: { opacity = 1; scale = 1; }
            Behavior on opacity { NumberAnimation { duration: Config.ms(1100); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Config.ms(1400); easing.type: Easing.OutCubic } }
        }
    }
}
