// Rounded screen corners, all four (always black, the same squircle shape the bar uses).
// Drawn here rather than by the bar, so they stay while the bar is auto-hidden.
// Each corner is its own small window, just the size of the corner and anchored to it (as the hot
// corners are), rather than one window the size of the whole screen with almost nothing in it:
// a full-screen overlay is a full-screen buffer for the compositor to hold and blend every frame.

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: corners
    required property var bar
    property var screen: null                   // the screen these four corners belong to
    readonly property real r: bar.screenCornerRadius

    Variants {
        model: ["topLeft", "topRight", "bottomLeft", "bottomRight"]
        PanelWindow {
            id: win
            required property string modelData
            readonly property bool isRight: modelData.endsWith("Right")
            readonly property bool isBottom: modelData.startsWith("bottom")

            screen: corners.screen
            visible: Config.s.roundedScreenCorners && corners.r > 0
            anchors { top: !isBottom; bottom: isBottom; left: !isRight; right: isRight }
            implicitWidth: corners.r; implicitHeight: corners.r
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-corners"
            WlrLayershell.layer: WlrLayer.Overlay
            mask: Region {}          // never takes the pointer

            Canvas {
                anchors.fill: parent
                // The shape is drawn for the top-left corner; mirrored for the others
                transform: Scale {
                    xScale: win.isRight ? -1 : 1; yScale: win.isBottom ? -1 : 1
                    origin.x: corners.r / 2; origin.y: corners.r / 2
                }
                readonly property color fill: "#000000"   // always black, like a rounded screen edge
                // Drawn again when the size or the shape changes (both come from the bar)
                readonly property real shape: corners.bar.screenCornerShape
                onFillChanged: requestPaint()
                onShapeChanged: requestPaint()
                onWidthChanged: requestPaint()
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
}
