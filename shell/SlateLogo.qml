// Slate's logo: a detailed version of the mark (the bar's slab, with depth and shading)
// beside the word "slate" in the interface font. Vector and themed, so it's crisp at any
// size and follows the accent, light mode and background tint. Set `size` (mark height).

import QtQuick
import QtQuick.Shapes

Row {
    id: logo
    property real size: 72
    property color accent: Config.accent
    property bool dark: false              // true: dark-theme colours whatever the theme (on a dark cover)
    property color textColor: shade("#eef1f5")
    property bool showText: true           // false: just the mark
    function shade(hex) { return dark ? Qt.lighter(hex, 1.0) : Config.tint(hex); }
    spacing: size * 0.22

    Item {
        id: mark
        width: logo.size; height: logo.size
        anchors.verticalCenter: parent.verticalCenter
        // Colours of the slab
        readonly property color face: logo.shade("#5d6879")
        readonly property color faceLow: logo.shade("#384150")
        readonly property color side: logo.shade("#242a34")

        Shape {
            // Drawn on a 64×64 grid
            width: 64; height: 64
            scale: logo.size / 64
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer

            // Thickness: the slab's side, showing below and to the left of the face
            ShapePath {
                fillColor: mark.side
                strokeColor: mark.side
                strokeWidth: 3
                joinStyle: ShapePath.RoundJoin
                startX: 10.5; startY: 25.5
                PathLine { x: 13; y: 24.8 }
                PathLine { x: 13; y: 56 }
                PathLine { x: 51.5; y: 45.6 }
                PathLine { x: 50; y: 49.5 }
                PathLine { x: 10.5; y: 60 }
                PathLine { x: 10.5; y: 25.5 }
            }
            // Face, shaded from the lit top edge down
            ShapePath {
                strokeColor: "transparent"
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 32; y1: 14; x2: 32; y2: 56
                    GradientStop { position: 0; color: mark.face }
                    GradientStop { position: 1; color: mark.faceLow }
                }
                // Rounded parallelogram: straight sides, small arcs at the corners
                startX: 16; startY: 24.2
                PathLine { x: 50.5; y: 14.8 }
                PathArc { x: 54; y: 17.6; radiusX: 3.4; radiusY: 3.4 }
                PathLine { x: 54; y: 42.6 }
                PathArc { x: 51.6; y: 45.8; radiusX: 3.4; radiusY: 3.4 }
                PathLine { x: 17.2; y: 55.2 }
                PathArc { x: 13; y: 52.4; radiusX: 3.4; radiusY: 3.4 }
                PathLine { x: 13; y: 27.4 }
                PathArc { x: 16; y: 24.2; radiusX: 3.4; radiusY: 3.4 }
            }
            // A faint grain line across the face, like split stone
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, Config.s.lightMode && !logo.dark ? 0.28 : 0.14)
                strokeWidth: 1.1
                capStyle: ShapePath.RoundCap
                startX: 14.5; startY: 42.4
                PathLine { x: 52.5; y: 32 }
            }
            // Accent edge along the top, with a slight sheen (a lighter line on its upper half)
            ShapePath {
                fillColor: "transparent"
                strokeColor: logo.accent
                strokeWidth: 4.2
                capStyle: ShapePath.RoundCap
                startX: 14.2; startY: 22.2
                PathLine { x: 53; y: 11.6 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.lighter(logo.accent, 1.18)
                strokeWidth: 1.4
                capStyle: ShapePath.RoundCap
                startX: 18; startY: 20.2
                PathLine { x: 49; y: 11.8 }
            }
        }
    }

    Text {
        visible: logo.showText
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -logo.size * 0.03
        text: "slate"
        color: logo.textColor
        font.family: Config.s.fontFamily
        font.pixelSize: logo.size * 0.64
        font.weight: Font.Medium
        font.letterSpacing: logo.size * 0.035
    }
}
