// A menu's surface: its card and the little point on its edge, towards what it's for (the
// desktop where it was clicked, the bar, a dock or tray icon), filled as one shape. The point
// was once a turned square of its own against the card: where the two met, both edges were
// drawn half see-through, and with glass Hyprland left that row unblurred (it blurs only behind
// what's solid enough), a light gap between the menu and its point.
// Put it first in the menu's box, which then has no colour of its own:
//   MenuSurface { edge: "top"; along: …; color: …; radius: parent.radius }
// (edge "": no point. Shadow takes the same point: pointAt / pointSize)

import QtQuick
import QtQuick.Shapes

Shape {
    id: s
    property string edge: ""              // the side the point's on: top, bottom, left, right, or none
    property real along: 0                // where along that side (from the left, or the top)
    property color color: "black"
    property real radius: 0
    property real size: 14                // the point is a square this size turned 45°, half showing
    readonly property real reach: Math.round(size / Math.SQRT2)     // how far it sticks out
    readonly property bool across: edge === "top" || edge === "bottom"
    // Where the point's centre is on the card's edge, for Shadow's pointAt
    readonly property point pointAt: edge === "top" ? Qt.point(along, 0) : edge === "bottom" ? Qt.point(along, height)
        : edge === "left" ? Qt.point(0, along) : Qt.point(width, along)
    readonly property real pointSize: edge === "" ? 0 : size
    anchors.fill: parent
    z: -1
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        fillColor: s.color
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.WindingFill
        PathRectangle { width: s.width; height: s.height; radius: s.radius }
        // The point, its base a pixel inside the card and wound the same way round as the card
        // (clockwise), so the two fill as one, with no edge between them
        PathPolyline {
            path: {
                const w = s.width, h = s.height, r = s.reach, a = s.along, i = 1;
                if (s.edge === "top") return [Qt.point(a - r - i, i), Qt.point(a, -r), Qt.point(a + r + i, i), Qt.point(a - r - i, i)];
                if (s.edge === "bottom") return [Qt.point(a + r + i, h - i), Qt.point(a, h + r), Qt.point(a - r - i, h - i), Qt.point(a + r + i, h - i)];
                if (s.edge === "left") return [Qt.point(i, a + r + i), Qt.point(-r, a), Qt.point(i, a - r - i), Qt.point(i, a + r + i)];
                if (s.edge === "right") return [Qt.point(w - i, a - r - i), Qt.point(w + r, a), Qt.point(w - i, a + r + i), Qt.point(w - i, a - r - i)];
                return [];
            }
        }
    }
}
