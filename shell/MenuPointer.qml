// The little point on a menu's edge, towards what it's for (a dock icon, a tray icon): a turned
// square, cut so only the part outside the menu is drawn. With glass the menu is see-through,
// and a whole square tucked under it showed through as a diamond.
// Put it in the menu's box:  MenuPointer { edge: "bottom"; along: …; color: parent.color }

import QtQuick

Item {
    id: p
    property string edge: "bottom"        // the menu's side it's on: top, bottom, left or right
    property real along: 0                // where along that side (from the menu's left, or top)
    property color color: "black"
    property real size: 14                // the turned square's side
    readonly property real reach: Math.round(size / Math.SQRT2)     // how far it sticks out
    readonly property bool across: edge === "top" || edge === "bottom"
    x: across ? along - reach : edge === "left" ? -reach : parent.width
    y: across ? (edge === "top" ? -reach : parent.height) : along - reach
    width: across ? reach * 2 : reach
    height: across ? reach : reach * 2
    clip: true
    Rectangle {
        width: p.size; height: p.size
        rotation: 45
        color: p.color
        // Centred on the menu's edge, which is this box's inner side
        x: (p.across ? p.reach : p.edge === "left" ? p.reach : 0) - width / 2
        y: (p.across ? (p.edge === "top" ? p.reach : 0) : p.reach) - height / 2
    }
}
