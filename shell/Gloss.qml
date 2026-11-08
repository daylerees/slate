// A glossy sheen for glass (Settings → Appearance → Glass → Gloss): light catching the top of
// a shape, fading out towards its middle, with a faint bright line along the top edge. Put it
// inside a rounded shape, over its fill and under its contents:
//   Gloss { radius: parent.radius }
// It only shows with glass on (and Gloss switched on).

import QtQuick

Rectangle {
    id: g
    property real strength: 1
    anchors.fill: parent
    visible: Config.glassGloss && opacity > 0
    color: "transparent"
    // Hover highlights set opacity to show it while pointed at: it fades in and out in step
    // with their colour (appearing at once, the top half showed before the rest)
    Behavior on opacity { NumberAnimation { duration: 100 } }
    readonly property real a: (Config.s.lightMode ? 0.35 : 0.13) * strength * Config.glossAmount
    gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, g.a) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, g.a * 0.25) }
        GradientStop { position: 0.55; color: "transparent" }
        GradientStop { position: 1.0; color: "transparent" }
    }
    // The bright edge along the top, inset to stay inside the corners
    Rectangle {
        x: Math.min(g.radius, g.width / 2) * 0.6
        width: Math.max(0, g.width - 2 * x)
        y: 0.5
        height: 1
        radius: 0.5
        color: Qt.rgba(1, 1, 1, Math.min(1, g.a * 1.6))
    }
}
