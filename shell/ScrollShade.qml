import QtQuick

// A soft shadow along the top or bottom edge of a scrolling list, saying there's more that
// way: it fades with the distance (px) from that end, gone just as you reach it. Every
// scrolling list has one at the top and one at the bottom (with ThinScrollbar and SmoothWheel).
Rectangle {
    id: scrollShade
    property bool atBottom: false
    // Sideways, for something that scrolls left and right: a shade down its left edge (or with
    // atBottom, its right), anchored top and bottom (the anchors give its length)
    property bool sideways: false
    property real distance: 0
    property real cornerRadius: 0      // the rounding of the corners it sits in
    // How strong, times the usual: deeper on a surface as dark as the shade itself (a dark
    // menu), where it shows only by fading what's under it into the surface
    property real depth: 1
    // It follows Settings → Appearance → Shadows like every other shadow: their color, how dark
    // (the usual strength at the default, 50%), how far it reaches (spread and softness: 18 px
    // at the defaults, 2 + 6) and how much of that is solid before it fades (the spread). But not the
    // switch: with shadows off it stays, as it says there's more to scroll to.
    // (Distance and direction don't apply: it lies along the edge it's for)
    readonly property real darkness: Math.max(0.05, Math.min(1, Number(Config.s.shadowDarkness) || 0.5)) / 0.5
    readonly property real reach: Config.shadowSpread + Config.shadowReach
    readonly property real solid: reach > 0 ? Config.shadowSpread / reach : 0
    readonly property color dark: Config.shade(Math.min(1, (Config.s.lightMode ? (atBottom ? 0.14 : 0.12) : (atBottom ? 0.38 : 0.32)) * depth * darkness))
    readonly property real thickness: Math.max(4, Math.round(18 * reach / 8))
    height: thickness
    width: thickness            // (one or the other; the anchors give the long side)
    topLeftRadius: Config.corner(sideways ? (atBottom ? 0 : cornerRadius) : (atBottom ? 0 : cornerRadius))
    topRightRadius: Config.corner(sideways ? (atBottom ? cornerRadius : 0) : (atBottom ? 0 : cornerRadius))
    bottomLeftRadius: Config.corner(sideways ? (atBottom ? 0 : cornerRadius) : (atBottom ? cornerRadius : 0))
    bottomRightRadius: Config.corner(atBottom ? cornerRadius : 0)
    opacity: Math.max(0, Math.min(1, distance / 24))
    // (dark at the edge it's for, solid for the spread's share, then fading out)
    gradient: Gradient {
        orientation: scrollShade.sideways ? Gradient.Horizontal : Gradient.Vertical
        GradientStop { position: 0; color: scrollShade.atBottom ? "transparent" : scrollShade.dark }
        GradientStop { position: scrollShade.atBottom ? 1 - scrollShade.solid : scrollShade.solid
                       color: scrollShade.dark }
        GradientStop { position: 1; color: scrollShade.atBottom ? scrollShade.dark : "transparent" }
    }
}
