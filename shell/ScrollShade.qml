import QtQuick

// A soft shadow along the top or bottom edge of a scrolling list, saying there's more that
// way: it fades with the distance (px) from that end, gone just as you reach it. Every
// scrolling list has one at the top and one at the bottom (with ThinScrollbar and SmoothWheel).
Rectangle {
    id: scrollShade
    property bool atBottom: false
    property real distance: 0
    property real cornerRadius: 0      // the rounding of the corners it sits in
    height: 18
    topLeftRadius: Config.corner(atBottom ? 0 : cornerRadius); topRightRadius: Config.corner(atBottom ? 0 : cornerRadius)
    bottomLeftRadius: Config.corner(atBottom ? cornerRadius : 0); bottomRightRadius: Config.corner(atBottom ? cornerRadius : 0)
    opacity: Math.max(0, Math.min(1, distance / 24))
    gradient: Gradient {
        GradientStop { position: 0; color: scrollShade.atBottom ? "transparent" : Config.shade(Config.s.lightMode ? 0.12 : 0.32) }
        GradientStop { position: 1; color: scrollShade.atBottom ? Config.shade(Config.s.lightMode ? 0.14 : 0.38) : "transparent" }
    }
}
