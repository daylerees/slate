// A glossy sheen for glass (Settings → Appearance → Glass → Gloss): light catching the top of
// a shape, fading out towards its middle, with a faint bright line along the top edge. Put it
// inside a rounded shape, over its fill and under its contents:
//   Gloss { radius: parent.radius }
// It only shows with glass on (and Gloss switched on).

import QtQuick
import QtQuick.Effects

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
    // The bright edge: the shape's own rounded outline, so it bends around the top corners,
    // fading out a little way down the sides
    Item {
        anchors.fill: parent
        layer.enabled: g.visible
        layer.effect: MultiEffect { maskEnabled: true; maskSource: rimFade; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        Rectangle {
            anchors.fill: parent
            radius: g.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, Math.min(1, g.a * 1.6))
        }
    }
    Item {
        id: rimFade
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            id: rimGrad
            anchors.fill: parent
            // Solid across the top and round the corners, gone by just past them
            readonly property real fadeTo: Math.min(0.6, (Math.max(g.radius, 4) + 6) / Math.max(1, g.height))
            gradient: Gradient {
                GradientStop { position: 0.0; color: "white" }
                GradientStop { position: Math.max(0.01, rimGrad.fadeTo * 0.45); color: "white" }
                GradientStop { position: rimGrad.fadeTo; color: "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
