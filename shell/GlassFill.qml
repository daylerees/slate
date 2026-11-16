// A lock / login screen panel's fill (LoginScreen.qml). With glass on (Settings →
// Appearance → Glass) it looks like the bar's containers: the wallpaper behind it frosted, the
// colour see-through and the gloss sheen, with no outline; with glass off it isn't shown and the
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
    // How much glass, 0–1: the login screen eases it when someone with glass off is chosen after
    // someone with it on, or back
    property real shown: Config.glass ? 1 : 0
    anchors.fill: parent
    opacity: shown
    visible: shown > 0
    // The frosted wallpaper, crossfading when the wallpaper changes (choosing someone else on the
    // login screen): the new one loads behind, then fades in as the old one fades out
    readonly property string want: wallpaper ? "file://" + wallpaper : ""
    property Item front: frostA
    readonly property Item back: front === frostA ? frostB : frostA
    function show() {
        if (want === "") { frostA.on = false; frostB.on = false; return; }
        if (front.wallpaper === want) { front.on = true; return; }
        back.wallpaper = want;
        if (back.status === Image.Ready) swap();
    }
    function swap() { const b = back; b.on = true; front.on = false; front = b; }
    onWantChanged: show()
    Component.onCompleted: show()
    component Frost: WallBlur {
        id: frost
        property bool on: false
        anchors.fill: parent
        // (shown even while see-through, so the picture loads behind the one showing)
        visible: frost.wallpaper !== "" && gf.screen !== null
        wallpaper: ""
        opacity: on && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status === Image.Ready && frost !== gf.front && frost.wallpaper === gf.want) gf.swap()
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
    Frost { id: frostA }
    Frost { id: frostB }
    Rectangle {
        anchors.fill: parent
        radius: gf.radius
        color: gf.fill
        Gloss { radius: gf.radius }
    }
}
