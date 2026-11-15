// The dock's Glow hover effect (Settings → Dock → Hover effect): a thin ring just outside an
// icon's tile, with a small gap, and a soft glow off it, in the icon's colour. Fades in with
// `strength` (0…1, from how near the pointer is). Put inside the tile, filling it.
//
// One shader draws both (shaders/glow.frag). While Hyprland blurs behind the dock's glass, it
// does so wherever anything at all is drawn (Config.dockGlassCut): a glow drawn the usual way
// was a patch of blurred glass with a hard edge round the icon. Then the glow is drawn as light
// added to what's behind it, which Hyprland leaves clear.

import QtQuick

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
    readonly property real reach: width * 0.4         // how far the glow goes past the ring
    readonly property real out: gap + line + reach    // (from the tile's edge to the glow's)

    ShaderEffect {
        x: -glow.out; y: -glow.out
        width: glow.width + 2 * glow.out
        height: glow.height + 2 * glow.out
        readonly property vector4d tint: Qt.vector4d(glow.colour.r, glow.colour.g, glow.colour.b, 0.75)
        readonly property vector4d box: Qt.vector4d(glow.reach, glow.reach, glow.width + 2 * (glow.gap + glow.line), glow.height + 2 * (glow.gap + glow.line))
        readonly property size size: Qt.size(width, height)
        readonly property real radius: Config.corner(glow.radius + glow.gap + glow.line)
        readonly property real line: glow.line
        readonly property real reach: glow.reach
        readonly property real spread: glow.width * 0.02
        // Added light while the dock's glass blurs (game mode has no glass: drawn as usual)
        readonly property real light: Config.glass && Config.s.dockBlur ? 1 : 0
        fragmentShader: Qt.resolvedUrl("shaders/glow.frag.qsb")
    }
}
