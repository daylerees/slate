import QtQuick
import Quickshell

// The round icon at the top of a dialog: a Tabler glyph (its code point) on a 56 px circle.
// The circle's colour and the glyph's are the dialog's, so they're given.
Rectangle {
    id: icon
    property int code: 0
    property color glyph: Config.accent
    width: 56; height: 56; radius: Config.corner(28)
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    Text {
        anchors.centerIn: parent
        text: String.fromCodePoint(icon.code)
        color: icon.glyph
        font.family: tabler.name
        font.pixelSize: 26
    }
}
