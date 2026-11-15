import QtQuick
import qs

// A panel's title row: its name on the left; anything put inside it (a switch, a count)
// anchors itself, usually to the right
Item {
    readonly property var pop: PanelHost.pop
    property alias text: titleLabel.text
    // An icon straight after the title, to click (the pencil that renames a workspace);
    // the title shortens before the two would overflow
    property int editCode: 0
    signal editClicked()
    width: parent ? parent.width : 0
    height: 26
    // How tall the title is by itself: a panel whose title has no switch beside it sets
    // `height: textHeight`, so the row is only as tall as its words
    readonly property real textHeight: titleLabel.implicitHeight
    Label {
        id: titleLabel
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 15
        width: Math.min(implicitWidth, parent.width - (titleEdit.visible ? 30 : 0))
        elide: Text.ElideRight
    }
    Item {
        id: titleEdit
        visible: parent.editCode !== 0
        anchors { left: titleLabel.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
        width: 24; height: 24
        Rectangle { anchors.fill: parent; radius: Config.corner(6); color: titleEditHover.hovered ? Config.hover : "transparent" }
        Icon { anchors.centerIn: parent; code: parent.parent.editCode; font.pixelSize: 16; color: pop.accent }
        HoverHandler { id: titleEditHover }
        ClickArea { anchors.fill: parent; onClicked: parent.parent.editClicked() }
    }
}
