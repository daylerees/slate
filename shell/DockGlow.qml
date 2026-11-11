// The dock's Glow hover effect (Settings → Dock → Hover effect): a thin ring just outside an
// icon's tile, with a small gap, and a soft glow off it, in the icon's colour. Fades in with
// `strength` (0…1, from how near the pointer is). Put inside the tile, filling it.

import QtQuick
import QtQuick.Effects

Item {
    id: glow
    property real strength: 0
    property color colour: Config.accent
    property real radius: 0              // the tile's corner radius
    anchors.fill: parent
    visible: strength > 0.01
    opacity: strength
    z: -2                                // behind the tile (the ring is outside it anyway)

    readonly property real gap: Math.max(2, width * 0.06)
    readonly property real line: Math.max(1.5, width * 0.04)

    // The glow off the ring
    RectangularShadow {
        anchors.fill: ring
        radius: ring.radius
        blur: glow.width * 0.4
        spread: glow.width * 0.02
        color: Qt.rgba(glow.colour.r, glow.colour.g, glow.colour.b, 0.75)
    }
    // The ring, a small gap out from the tile
    Rectangle {
        id: ring
        anchors { fill: parent; margins: -(glow.gap + glow.line) }
        radius: Config.corner(glow.radius + glow.gap + glow.line)
        color: "transparent"
        border.width: glow.line
        border.color: glow.colour
    }
}
