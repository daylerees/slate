// Rounded screen corners, all four (always black, the same squircle shape the bar uses).
// Drawn here rather than by the bar, so they stay while the bar is auto-hidden.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: corners
    required property var bar
    readonly property real r: bar.screenCornerRadius
    readonly property var list: ["topLeft", "topRight", "bottomLeft", "bottomRight"]

    visible: Config.s.roundedScreenCorners
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-corners"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}          // never takes the pointer

    Repeater {
        model: corners.list
        Canvas {
            required property string modelData
            readonly property bool isRight: modelData.endsWith("Right")
            readonly property bool isBottom: modelData.startsWith("bottom")
            width: corners.r; height: corners.r
            x: isRight ? corners.width - width : 0
            y: isBottom ? corners.height - height : 0
            // The shape is drawn for the top-left corner; mirrored for the others
            transform: Scale {
                xScale: isRight ? -1 : 1; yScale: isBottom ? -1 : 1
                origin.x: corners.r / 2; origin.y: corners.r / 2
            }
            readonly property color fill: "#000000"   // always black, like a rounded screen edge
            onFillChanged: requestPaint()
            onAvailableChanged: if (available) requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d"), n = corners.bar.screenCornerShape, r = corners.r;
                ctx.reset();
                ctx.fillStyle = fill;
                ctx.beginPath();
                ctx.moveTo(0, 0);
                ctx.lineTo(r, 0);
                for (let i = 0; i <= 48; i++) {
                    const t = Math.PI / 2 * (1 - i / 48);
                    ctx.lineTo(r - r * Math.pow(Math.cos(t), 2 / n), r - r * Math.pow(Math.sin(t), 2 / n));
                }
                ctx.closePath();
                ctx.fill();
            }
        }
    }
}
