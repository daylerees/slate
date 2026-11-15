import QtQuick
import qs

Rectangle {
    readonly property var pop: PanelHost.pop
    width: parent ? parent.width : 0
    height: 1
    color: pop.card
}
