import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A wallpaper in Settings → Appearance: its thumbnail and name; click to use it. For the
// images in your folder and the ones that come with Slate
Item {
    readonly property var win: SettingsHost.win
    id: tile
    property real tileW: 200
    property bool small: false           // too small to be a wallpaper: hidden
    property string title: ""            // under it, in place of the file's name
    signal picked()
    required property string filePath
    required property string fileName
    readonly property bool current: Config.wallpaper === filePath
    visible: !tile.small
    width: tile.tileW
    height: width * 10 / 16 + 26
    Rectangle {
        id: thumbFrame
        width: parent.width; height: parent.width * 10 / 16
        radius: Config.corner(10)
        color: win.card
        border.width: parent.current ? 3 : wallHover.hovered ? 1 : 0
        border.color: parent.current ? win.accent : Config.tint("#4a5360")
        Item {
            anchors { fill: parent; margins: parent.parent.current ? 3 : 0 }
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: thumbMask }
            Image {
                anchors.fill: parent
                // (nothing decoded for a tile that's hidden as too small to be a wallpaper)
                source: tile.small ? "" : "file://" + filePath
                // Decoded at twice the tile's width, in steps of 64 so resizing the window
                // doesn't decode every picture again at each pixel
                sourceSize.width: Math.max(64, Math.ceil(tile.tileW * 2 / 64) * 64)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                // (counted while loading, for the tests: win.thumbsLoading)
                property bool counted: false
                function count() {
                    const l = status === Image.Loading;
                    if (l !== counted) { win.thumbsLoading += l ? 1 : -1; counted = l; }
                }
                onStatusChanged: count()
                Component.onCompleted: count()
                Component.onDestruction: if (counted) win.thumbsLoading -= 1
            }
            Item {
                id: thumbMask
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: Config.corner(8) }
            }
        }
        // Tick on the wallpaper in use
        Rectangle {
            visible: parent.parent.current
            anchors { right: parent.right; top: parent.top; margins: 8 }
            width: 24; height: 24; radius: Config.corner(12)
            color: win.accent
            Text { anchors.centerIn: parent; text: win.glyph(0xEA5E); color: win.accentText; font.family: win.bar.iconFont; font.pixelSize: 15 }
        }
    }
    Text {
        anchors { top: thumbFrame.bottom; topMargin: 6; left: parent.left; right: parent.right }
        textFormat: Text.PlainText        // never markup: a file's name
        text: tile.title || fileName
        color: parent.current ? win.text : win.dim
        font.family: win.font; font.pixelSize: Config.text(11)
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
    }
    HoverHandler { id: wallHover }
    ClickTap { onTapped: tile.picked() }
}
