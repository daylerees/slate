import QtQuick

// A link at the foot of a panel ("Keyboard settings", "Show all and search"…): an icon,
// then what it does
RowButton {
    id: link
    property int code: 0
    property string text: ""
    property color iconColor: pop.dim
    property color textColor: pop.text
    width: parent ? parent.width : 0
    Icon {
        id: linkIcon
        code: link.code; font.pixelSize: 16; color: link.iconColor
        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    }
    Label {
        anchors { left: linkIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
        text: link.text; color: link.textColor; font.weight: Font.Normal
    }
}
