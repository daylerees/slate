// One of the dock's own buttons: a symbol on a tile shaped like the app icons' (the launcher
// button's three bars, More's dots, Downloads' folder, the Waste Basket's bin), magnifying,
// tilting, lifting, fading and glowing with the dock's hover effect as an app's icon does.
// The launcher, Downloads and the Waste Basket are slots of the dock's own (standalone); More
// sits in one of the dock's cells, which moves it, so it only draws:
//   DockButton { dock: win; at: win.downloadsIndex; dockTop: bg.y - row.y; glyph: 0xF912 }

import QtQuick

Item {
    id: btn
    required property var dock          // the dock (Dock.qml)
    property int at: -1                 // its place along the dock (win.slotAt)
    property bool standalone: true      // a slot of its own; false inside a dock cell (More)
    property real dockTop: 0            // where the dock's background starts, in the slot (DockBacking)
    property int glyph: 0               // its symbol (Tabler); 0 for the launcher's three bars
    property var badgeInfo: null        // a badge on its corner ({ count, urgent }), if any
    readonly property real s: dock.scaleAt(at)
    opacity: standalone ? dock.fadeAt(at) : 1
    width: standalone ? dock.base * s : parent ? parent.width : 0
    height: parent ? parent.height : 0
    transform: [
        Matrix4x4 { matrix: btn.dock.tiltMatrix(btn.width, btn.height, btn.standalone ? btn.dock.tiltAt(btn.at) : 0) },
        Translate { y: btn.standalone ? -btn.dock.liftAt(btn.at) : 0; Behavior on y { enabled: btn.dock.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }}
    ]
    // (More's shows without glass too, as it always has)
    DockBacking { visible: btn.standalone ? Config.glass : true; dockTop: btn.dockTop; color: btn.dock.dockColor; radius: Config.iconCornerFor(width) }
    Item {
        id: tile
        anchors.bottom: parent.bottom
        width: parent.width; height: width
        transform: Matrix4x4 { matrix: btn.dock.upright(tile.width, tile.height) }
        DockGlow {
            strength: btn.dock.glowAt(btn.at)
            radius: Config.iconCornerFor(width)
        }
        // The same shape as the app icons (a tile when they're shown as they come)
        IconPlate {
            anchors.fill: parent
            drawSize: btn.dock.base * btn.dock.maxScale      // drawn once, magnified size
            shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
            fill: false
            color: btn.dock.tileColor
            opacity: Config.dockTileOpacity
        }
        // Glass: a sheen, rounded like the tile
        Gloss { radius: Config.iconCornerFor(parent.width); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
        // Three soft rounded bars, as on the bar's Apps button, scaled with the tile
        Column {
            id: burger
            visible: btn.glyph === 0
            opacity: Config.dockIconOpacity
            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            readonly property real w: btn.dock.symbolRef
            scale: parent.width / w
            spacing: w * 0.075
            Repeater {
                model: 3
                Rectangle {
                    width: burger.w * 0.42; height: burger.w * 0.07
                    radius: Config.corner(height / 2)
                    color: btn.dock.textColor
                }
            }
        }
        // A symbol, scaled with the tile
        Text {
            visible: btn.glyph !== 0
            opacity: Config.dockIconOpacity
            anchors.centerIn: parent
            text: btn.glyph !== 0 ? String.fromCodePoint(btn.glyph) : ""
            color: btn.dock.textColor
            font.family: "slate-tabler-icons"
            font.pixelSize: Math.round(btn.dock.symbolRef * 0.5)
            scale: parent.width / btn.dock.symbolRef
            anchors.alignWhenCentered: false
        }
        DockBadge {
            z: 2
            info: btn.badgeInfo
            color: btn.dock.activeDotColor
        }
    }
}
