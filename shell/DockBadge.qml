// An app's badge on the dock: its unread count (or "!" when it asks for attention) as a pill on
// its icon's top corner, in the accent, with glass's sheen. Put it inside the icon's tile:
//   DockBadge { info: win.badgeFor(app); color: win.activeDotColor }
// It sizes itself to the tile; More's grid gives it a fixed size of its own.

import QtQuick

Rectangle {
    id: badge
    property var info: null             // { count, urgent } (win.badgeFor / win.moreBadge)
    property bool glossy: true          // glass's sheen
    property real textSize: Math.round(height * 0.62)
    property real pad: height * 0.5     // room beside the number
    readonly property string text: !info ? "" : info.count > 99 ? "99+" : info.count > 0 ? String(info.count)
        : info.urgent ? "!" : ""
    visible: text !== ""
    height: Math.round((parent ? parent.height : 0) * 0.38)
    width: Math.max(height, badgeText.implicitWidth + pad)
    radius: Config.corner(height / 2)
    x: (parent ? parent.width : 0) - width * 0.75; y: -height * 0.25
    Gloss { radius: parent.radius; visible: badge.glossy && Config.glassGloss }
    Text {
        id: badgeText
        anchors.centerIn: parent
        text: badge.text
        color: Config.palette.accentText
        font.family: Config.s.fontFamily; font.weight: Font.DemiBold
        font.pixelSize: Config.text(badge.textSize)
    }
}
