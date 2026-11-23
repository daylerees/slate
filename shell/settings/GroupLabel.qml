import QtQuick
import ".."

// A section's heading in Settings. Plain text, never markup: some name an app or a version from
// the network (App Rules' rules, Updates' "What's new in …")
Text {
    readonly property var win: SettingsHost.win
    textFormat: Text.PlainText
    color: win.dim
    font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
    topPadding: 14; bottomPadding: 6; leftPadding: 4
}
