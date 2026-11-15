import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A note at the foot of a page
Text {
    readonly property var win: SettingsHost.win
    width: parent.width
    topPadding: 10
    color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
}
