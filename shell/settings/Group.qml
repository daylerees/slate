import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// Rounded card holding a few rows
Rectangle {
    readonly property var win: SettingsHost.win
    default property alias rows: groupCol.data
    width: parent ? parent.width : 0
    height: groupCol.implicitHeight + 8
    radius: Config.corner(12)
    color: win.card
    Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
    ContrastEdge { radius: parent.radius }   // high contrast: a clear edge
    Column { id: groupCol; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 } }
}
