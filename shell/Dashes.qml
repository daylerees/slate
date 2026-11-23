import QtQuick
import QtQuick.Shapes

// A dashed outline just inside its parent, following its rounded corners: where something can
// go (the bar being arranged, the gap a dragged app leaves on the dock)
//   Dashes { colour: …; line: 1.5 }
Shape {
    id: dashes
    property color colour: Config.accent
    property real line: 1
    property real radius: parent && parent.radius !== undefined ? parent.radius : 0
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: dashes.colour
        strokeWidth: dashes.line
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 2.5]
        fillColor: "transparent"
        PathRectangle {
            x: dashes.line / 2; y: dashes.line / 2
            width: Math.max(0, dashes.width - dashes.line); height: Math.max(0, dashes.height - dashes.line)
            radius: Config.corner(Math.max(0, dashes.radius - dashes.line / 2))
        }
    }
}
