// A lock / login screen panel's fill (LoginScreen.qml). With glass on (Settings →
// Appearance → Glass) it looks like the rest of Slate: the wallpaper behind it frosted, the
// colour see-through, the shine rim and the gloss sheen; with glass off it isn't shown and the
// panel keeps its solid colour. That screen draws its own wallpaper, so Hyprland's blur (which
// frosts the bar) can't reach behind its panels; WallBlur draws that part instead.
//   GlassFill { screen: <the full-screen item>; wallpaper: <path>; fill: Config.surface(…); radius: parent.radius }
// Put it first inside the panel, with the panel's own colour transparent while glass is on.

import QtQuick

Item {
    id: gf
    property Item screen                   // the full-screen item the wallpaper fills
    property string wallpaper: ""          // image path
    property color fill
    property real radius
    anchors.fill: parent
    visible: Config.glass
    WallBlur {
        anchors.fill: parent
        visible: gf.wallpaper !== "" && gf.screen !== null
        wallpaper: gf.wallpaper ? "file://" + gf.wallpaper : ""
        radius: gf.radius
        pixelScale: 1
        screen: gf.screen ? Qt.size(gf.screen.width, gf.screen.height) : Qt.size(1, 1)
        // Where the panel sits on the screen (redone when it or what holds it moves)
        win: {
            const p = gf.parent, pp = p ? p.parent : null;
            if (!gf.screen) return Qt.rect(0, 0, 1, 1);
            [gf.screen.width, gf.screen.height, gf.width, gf.height, p ? p.x + p.y : 0, pp ? pp.x + pp.y : 0];
            const at = gf.mapToItem(gf.screen, 0, 0);
            return Qt.rect(at.x, at.y, gf.width, gf.height);
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: gf.radius
        color: gf.fill
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Gloss { radius: gf.radius }
    }
}
