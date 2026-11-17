// A countdown ring (the timers: Timers.qml): a full circle that empties clockwise from the top
// as `progress` goes from 1 to 0, over a faint track, with whatever's inside it in the middle
import QtQuick
import QtQuick.Shapes

Item {
    id: ring
    property real size: 100
    property real progress: 1
    property real thickness: Math.max(2, size * 0.06)
    property color colour: Config.accent
    property color trackColour: Config.tint("#2a313c")
    width: size; height: size
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.trackColour
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: (ring.size - ring.thickness) / 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: ring.colour
            strokeWidth: ring.thickness
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: ring.size / 2; centerY: ring.size / 2; radiusX: (ring.size - ring.thickness) / 2; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, ring.progress)) }
        }
    }
}
