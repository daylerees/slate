// The border round one of Slate's own glass windows (the launcher, Nova, the switchers…), drawn
// as Hyprland draws the active window's: its colours and, with glass and gloss, its sheen along
// a 45° gradient from the top left (Config.windowBorderColours), as wide as tiled windows'
// border (Config.windowBorderWidth; none without glass). A ring inside the window's edge, laid
// over what's in it. Use it inside the window's panel: `WindowBorder { radius: parent.radius }`

import QtQuick
import QtQuick.Shapes

Shape {
    id: ring
    property real radius: 0
    readonly property real line: Config.windowBorderWidth
    readonly property var colours: Config.windowBorderColours
    anchors.fill: parent
    z: 1000
    visible: line > 0
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        // Hyprland spreads the colours evenly across the window along 45°: from the top left
        // corner to the bottom right one's projection on that line
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: (ring.width + ring.height) / 2; y2: (ring.width + ring.height) / 2
            GradientStop { position: 0; color: ring.colours[0] }
            GradientStop { position: 1 / 6; color: ring.colours[1] }
            GradientStop { position: 2 / 6; color: ring.colours[2] }
            GradientStop { position: 3 / 6; color: ring.colours[3] }
            GradientStop { position: 4 / 6; color: ring.colours[4] }
            GradientStop { position: 5 / 6; color: ring.colours[5] }
            GradientStop { position: 1; color: ring.colours[6] }
        }
        PathRectangle {
            width: ring.width; height: ring.height
            radius: ring.radius
        }
        PathRectangle {
            x: ring.line; y: ring.line
            width: Math.max(0, ring.width - ring.line * 2); height: Math.max(0, ring.height - ring.line * 2)
            radius: Math.max(0, ring.radius - ring.line)
        }
    }
}
