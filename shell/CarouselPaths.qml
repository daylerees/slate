import QtQuick

// The two paths the window switcher's and the overview's strips run along: a straight line
// (slide, hop, tilt, orbit, deck, fan) and, for the wheel, the same strip bent round a circle
// below it with the chosen card at the top. Each point carries "side" (its distance along the
// strip from the middle, in pixels) and "turn" (the wheel's turn there, in degrees), which the
// cards read as PathView.side and PathView.turn to lean and tilt by. Only the numbers differ
// between the two windows, so they're given:
//   viewWidth: the PathView's width     len: the whole strip's length, in pixels
//   restY: where a card rests, down the view     wheelFloor: the wheel's smallest radius
//   PathView { path: moveAnim === "wheel" ? paths.wheel : paths.line }
Item {
    id: paths
    property real viewWidth: 0
    property real len: 0
    property real restY: 0
    property real wheelFloor: 0

    readonly property real wheelR: Math.max(len / (2 * Math.PI) * 1.02, wheelFloor)
    readonly property real sweep: len / wheelR * 180 / Math.PI
    readonly property real a0: (-90 - sweep / 2) * Math.PI / 180
    readonly property alias line: linePath
    readonly property alias wheel: wheelPath

    Path {
        id: linePath
        startX: paths.viewWidth / 2 - paths.len / 2; startY: paths.restY
        PathAttribute { name: "side"; value: -paths.len / 2 }
        PathAttribute { name: "turn"; value: 0 }
        PathLine { x: paths.viewWidth / 2 + paths.len / 2; y: paths.restY }
        PathAttribute { name: "side"; value: paths.len / 2 }
        PathAttribute { name: "turn"; value: 0 }
    }
    Path {
        id: wheelPath
        startX: paths.viewWidth / 2 + paths.wheelR * Math.cos(paths.a0); startY: paths.restY + paths.wheelR + paths.wheelR * Math.sin(paths.a0)
        PathAttribute { name: "side"; value: -paths.len / 2 }
        PathAttribute { name: "turn"; value: -paths.sweep / 2 }
        PathAngleArc {
            centerX: paths.viewWidth / 2; centerY: paths.restY + paths.wheelR
            radiusX: paths.wheelR; radiusY: paths.wheelR
            startAngle: -90 - paths.sweep / 2; sweepAngle: paths.sweep
            moveToStart: false
        }
        PathAttribute { name: "side"; value: paths.len / 2 }
        PathAttribute { name: "turn"; value: paths.sweep / 2 }
    }
}
