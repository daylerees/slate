import QtQuick
import ".."

// A page's opening paragraph, under its title
Text {
    readonly property var win: SettingsHost.win
    width: Math.min(parent.width, win.introMeasure)
    color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
    wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
}
