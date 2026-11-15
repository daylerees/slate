// The test stand-in for hyprpicker's freeze (see hyprpicker beside this): the picture it took,
// over the whole screen on a layer named as hyprpicker's is.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprpicker"
        color: "black"
        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("SLATE_TEST_FROZEN")
            cache: false
        }
    }
}
