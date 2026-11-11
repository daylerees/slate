// The shadow under anything raised: panels, menus, the launcher, notifications, Chalk…
// One look for all of them: dark, with a light tint of the theme (Config.shadowColour),
// sitting close under the surface. Put it inside the surface it belongs to:
//   Rectangle { radius: 18; …; Shadow {} }
// It fills its parent, takes its rounding, and is drawn behind it (z: -1), reaching `reach`
// pixels past its edges, so the window needs that much room round the surface. Being a child,
// it fades, slides and scales with the surface. A surface that clips itself can't have it
// inside: give that one a Shadow beside it instead, with the surface's place and size.
//
// The surface's own shape is cut out of the shadow (shaders/shadow.frag), so nothing dark lies
// under it. That's what lets glass have shadows: a see-through surface would show one, and
// Hyprland would blur behind it. For the same reason it's kept fainter than the point where
// Hyprland starts blurring behind Slate's glass (Config.glassCut). Off in game mode.

import QtQuick

Item {
    id: root
    // The surface's rounding: one radius, or each corner
    property real radius: parent && parent.radius !== undefined ? parent.radius : 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomRightRadius: radius
    property real bottomLeftRadius: radius
    property real blur: 22             // how far it reaches before it's gone (px)
    property real dropX: 0             // where it sits: straight down unless the surface hangs
    property real dropY: 3             // off an edge (a panel under the bar)
    property real strength: 1          // 1: Slate's usual; a small surface can ask for less
    // A rounded rectangle taken out of the surface (in this item's coordinates; none if it has
    // no width), for a surface that isn't a box: the menu bar with its flared corners is a
    // band with the desktop's rounded shape taken out of it
    property rect hole: Qt.rect(0, 0, 0, 0)
    property real holeRadius: 0
    readonly property real reach: Math.ceil(blur + Math.max(Math.abs(dropX), Math.abs(dropY)))

    anchors.fill: parent
    z: -1
    visible: !Config.gameMode && width > 0 && height > 0

    ShaderEffect {
        x: -root.reach; y: -root.reach
        width: root.width + 2 * root.reach
        height: root.height + 2 * root.reach
        readonly property color tint: Qt.rgba(Config.shadowColour.r, Config.shadowColour.g, Config.shadowColour.b,
                                              Config.shadowStrength * root.strength)
        readonly property vector4d box: Qt.vector4d(root.reach, root.reach, root.width, root.height)
        readonly property vector4d radii: Qt.vector4d(root.topLeftRadius, root.topRightRadius, root.bottomRightRadius, root.bottomLeftRadius)
        readonly property size size: Qt.size(width, height)
        readonly property point drop: Qt.point(root.dropX, root.dropY)
        readonly property real blur: root.blur
        readonly property vector4d hole: Qt.vector4d(root.hole.x + root.reach, root.hole.y + root.reach, root.hole.width, root.hole.height)
        readonly property real holeRadius: root.holeRadius
        fragmentShader: Qt.resolvedUrl("shaders/shadow.frag.qsb")
    }
}
