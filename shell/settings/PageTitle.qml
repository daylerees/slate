import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A page names itself; the title is drawn in the fixed header above the scrolling page
Item {
    readonly property var win: SettingsHost.win
    property string text
    width: 1; height: 0
    visible: false
    onTextChanged: win.pageTitle = text
    Component.onCompleted: win.pageTitle = text
}
