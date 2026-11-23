import QtQuick
import ".."

Text {
    readonly property var win: SettingsHost.win
    color: win.dim
    font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
    topPadding: 14; bottomPadding: 6; leftPadding: 4
}
