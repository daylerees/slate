// A space's badge: its icon on its colour (Spaces.qml). Shown on windows that came from a
// space: in their corner (SpaceBadges.qml), in the window switcher and the workspace overview.
//   SpaceBadge { space: Spaces.spaceById(Spaces.spaceOfAddress[toplevel.address]); size: 22 }
// Hidden while `space` is null.

import QtQuick
import Quickshell

Rectangle {
    id: b
    property var space: null
    property real size: 26
    visible: !!space
    width: size; height: size
    radius: Config.corner(Math.round(size * 0.31))
    color: space ? space.colour : "transparent"
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.22)
    Text {
        anchors.centerIn: parent
        text: b.space ? String.fromCodePoint(Spaces.iconOf(b.space)) : ""
        color: "#1b1f26"
        // Tabler icons (fonts/tabler.ttf), loaded by the bar
        font.family: "slate-tabler-icons"
        font.pixelSize: Math.round(b.size * 0.58)
    }
}
