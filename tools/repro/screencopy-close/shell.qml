// Quickshell's live ScreencopyView and a window closing: nothing of Slate's, just a live preview of
// every window. With three windows open, close all three at once (one hyprctl dispatch closing
// each); Quickshell 0.3.2 died ("The Wayland connection experienced a fatal error: Invalid
// argument") in 3 of 4 tries. Run it beside Slate:  qs -n -p tools/repro/screencopy-close
// If it survives a handful of tries on a new Quickshell, see "Workarounds for bugs elsewhere"
// in docs/ARCHITECTURE.md.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    PanelWindow {
        anchors { top: true; right: true }
        margins { top: 60; right: 20 }
        implicitWidth: 420; implicitHeight: 120
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        color: "#202020"
        Row {
            spacing: 6
            Repeater {
                model: Hyprland.toplevels.values.map(t => t.address)
                delegate: ScreencopyView {
                    required property string modelData
                    readonly property var tl: Hyprland.toplevels.values.find(t => t.address === modelData) ?? null
                    width: 100; height: 100
                    captureSource: tl && tl.wayland ? tl.wayland : null
                    live: true
                }
            }
        }
    }
}
