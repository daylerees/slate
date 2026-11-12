// The shadow under anything raised: panels, menus, the launcher, notifications, Nova…
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
// Hyprland starts blurring behind Slate's glass (Config.glassCut). Off in game mode, and with
// Settings → Appearance → Shadows off (Config.shadowsOn).

import QtQuick

Item {
    id: root
    // The surface's rounding: one radius, or each corner
    property real radius: Config.corner(parent && parent.radius !== undefined ? parent.radius : 0)
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomRightRadius: radius
    property real bottomLeftRadius: radius
    // Its look is Slate's one shadow (Settings → Appearance → Shadows: Config.shadowReach, the
    // spread, the direction and distance), the same everywhere: only a surface hanging off an
    // edge (a panel under the bar) sets which way it falls, away from that edge
    readonly property real blur: Config.shadowReach      // how soft its edge is (px)
    property real spread: Config.shadowSpread            // how far its full darkness reaches past the surface (px)
    property real dropX: Config.shadowDX                 // where it sits, from the surface
    property real dropY: Config.shadowDY
    property real strength: 1          // 1: Slate's usual; a small surface can ask for less
    // A rounded rectangle taken out of the surface (in this item's coordinates; none if it has
    // no width), for a surface that isn't a box: the menu bar with its flared corners is a
    // band with the desktop's rounded shape taken out of it
    property rect hole: Qt.rect(0, 0, 0, 0)
    property real holeRadius: 0
    // No shadow along one edge of the surface, where it joins something else (a panel coming out
    // of the bar: the curved joins beside it there would lie on the shadow, and on glass show
    // darker for it). "top" / "bottom" / "left" / "right": none within fadeFrom px of that edge
    // (and beyond it), then growing to full over fadeOver px. "": everywhere, as usual
    property string fadeEdge: ""
    property real fadeFrom: 0
    property real fadeOver: 12
    // A menu's pointer (MenuPointer.qml), as part of the surface: the square it's cut from,
    // turned 45°, with its centre at pointAt (in this item's coordinates) and sides pointSize
    // long (0: none). The shadow follows it, and none lies under it to show through
    property point pointAt: Qt.point(0, 0)
    property real pointSize: 0
    // Cast from one straight edge alone (the menu bar: its inner edge, facing into the screen):
    // castNormal the way the shadow falls ((0, 1) down, (0, -1) up, (1, 0) right, (-1, 0)
    // left; (0, 0): the whole shape casts, as usual), castLine where that edge is (in this
    // item's coordinates, along castNormal's axis). The shape still keeps it from under itself
    property point castNormal: Qt.point(0, 0)
    property real castLine: 0
    // A panel's curved joins to the bar, as part of the surface (Popouts.qml), so the shadow
    // follows them: each a square (in this item's coordinates; none if it has no width) less a
    // disk of joinRadius centred at joinCentreA / B
    property rect joinA: Qt.rect(0, 0, 0, 0)
    property rect joinB: Qt.rect(0, 0, 0, 0)
    property point joinCentreA: Qt.point(0, 0)
    property point joinCentreB: Qt.point(0, 0)
    property real joinRadius: 0
    // Another shadow already under this one, with the same look, cast from one straight edge
    // (castNormal / castLine's way), underStrength dark (0: none): the bar's, under a panel's.
    // Only what this one adds over it is drawn, so they come to the darker of the two, not both
    property point underNormal: Qt.point(0, 0)
    property real underLine: 0
    property real underStrength: 0
    // (and as far again as a menu's pointer sticks out: its shadow reaches past its tip)
    readonly property real reach: Math.ceil(Math.max(blur, 0.5) * 1.1 + spread + (joinRadius > 0 ? joinRadius : 0) + Math.max(Math.abs(dropX), Math.abs(dropY)) + (pointSize > 0 ? pointSize / Math.SQRT2 : 0))

    anchors.fill: parent
    z: -1
    visible: Config.shadowsOn && width > 0 && height > 0

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
        readonly property vector4d fade: Qt.vector4d(root.fadeEdge === "left" ? 1 : root.fadeEdge === "right" ? -1 : 0,
                                                     root.fadeEdge === "top" ? 1 : root.fadeEdge === "bottom" ? -1 : 0,
                                                     root.fadeFrom, root.fadeOver)
        readonly property vector4d point: Qt.vector4d(root.pointAt.x + root.reach, root.pointAt.y + root.reach, root.pointSize, 0)
        readonly property real spread: root.spread
        readonly property vector4d joinA: Qt.vector4d(root.joinA.x + root.reach, root.joinA.y + root.reach, root.joinA.width, root.joinA.height)
        readonly property vector4d joinB: Qt.vector4d(root.joinB.x + root.reach, root.joinB.y + root.reach, root.joinB.width, root.joinB.height)
        readonly property vector4d joinC: Qt.vector4d(root.joinCentreA.x + root.reach, root.joinCentreA.y + root.reach,
                                                      root.joinCentreB.x + root.reach, root.joinCentreB.y + root.reach)
        readonly property real joinR: root.joinRadius
        readonly property vector4d under: root.underStrength > 0
            ? Qt.vector4d(root.underNormal.x, root.underNormal.y, (root.underLine + root.reach) * (root.underNormal.x + root.underNormal.y), root.underStrength)
            : Qt.vector4d(0, 0, 0, 0)
        readonly property vector4d edge: Qt.vector4d(root.castNormal.x, root.castNormal.y,
                                                     (root.castLine + root.reach) * (root.castNormal.x + root.castNormal.y), 0)
        fragmentShader: Qt.resolvedUrl("shaders/shadow.frag.qsb")
    }
}
