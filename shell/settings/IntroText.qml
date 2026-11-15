import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A page's opening paragraph, under its title
Text {
    readonly property var win: SettingsHost.win
    width: Math.min(parent.width, win.introMeasure)
    color: win.dim; font.family: win.font; font.pixelSize: 13
    wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
}
