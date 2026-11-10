// Slate's mark, drawn as vectors so it's crisp at any size: a slab of slate tilted up to
// the right (or, with `flat`, seen straight on: the menu bar's), with the accent colour along
// its top edge. Drawn on an 18×18 grid; set `size` to scale it. Used on the bar (control
// centre), the dock (apps) and Slate's notifications.

import QtQuick
import QtQuick.Shapes

Item {
    id: mark
    property real size: 18
    property color accent: Config.accent
    property color body: Config.tint("#566173")
    property bool flat: false
    width: size; height: size

    Shape {
        width: 18; height: 18
        scale: mark.size / 18
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            // Body (a round join on a thin outline of the same colour rounds the corners)
            fillColor: mark.body
            strokeColor: mark.body
            strokeWidth: 1.6
            joinStyle: ShapePath.RoundJoin
            startX: 3.4; startY: mark.flat ? 5.7 : 7.6
            PathLine { x: 14.6; y: mark.flat ? 5.7 : 4.6 }
            PathLine { x: 14.6; y: mark.flat ? 14.1 : 13.4 }
            PathLine { x: 3.4; y: mark.flat ? 14.1 : 16.4 }
            PathLine { x: 3.4; y: mark.flat ? 5.7 : 7.6 }
        }
        ShapePath {
            // Accent edge along the top
            fillColor: "transparent"
            strokeColor: mark.accent
            strokeWidth: 2.4
            capStyle: ShapePath.RoundCap
            startX: 3.3; startY: mark.flat ? 4.1 : 6.4
            PathLine { x: 14.7; y: mark.flat ? 4.1 : 3.4 }
        }
    }
}
