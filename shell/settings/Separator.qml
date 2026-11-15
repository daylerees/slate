import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// (with glass the cards are see-through, and the solid divider grey all but vanished on them:
// a faint line of the text colour there, still quiet)
Rectangle {
    readonly property var win: SettingsHost.win
    width: parent ? parent.width - 32 : 0; x: 16; height: 1
    color: Config.glass ? Qt.rgba(win.text.r, win.text.g, win.text.b, 0.11) : win.divider
}
