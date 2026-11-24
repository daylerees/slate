// Accessibility → High contrast: a clear edge round a surface, in the text color, so it stands
// apart from whatever's behind it. Every raised surface gets one through its Shadow (which makes
// it on top of the surface); a surface without a shadow (Settings' cards, the bar's containers)
// puts one in itself:  ContrastEdge { radius: parent.radius }

import QtQuick

Rectangle {
    property real line: 2
    anchors.fill: parent
    z: 999
    visible: Config.s.highContrast
    color: "transparent"
    border.width: line
    border.color: Config.palette.text
    antialiasing: true
}
