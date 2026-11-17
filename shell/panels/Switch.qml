import QtQuick
import qs

// An on/off switch, as in the Wi-Fi, Bluetooth, game mode and notifications panels
Rectangle {
    // (a screen reader: a check box it can switch)
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: toggled()
    Accessible.onPressAction: toggled()
    // (the keyboard: a stop for Tab and the arrow keys; Enter or Space presses; its ring)
    activeFocusOnTab: visible && enabled
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) toggled();
        else if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
            const next = nextItemInFocusChain(e.key === Qt.Key_Down);
            if (next) next.forceActiveFocus(Qt.TabFocusReason);
        } else return;
        e.accepted = true;
    }
    Rectangle {
        z: 5
        visible: parent.activeFocus
        anchors { fill: parent; margins: -2 }
        color: "transparent"
        radius: Config.corner(13)
        border.width: 2
        border.color: Config.accent
    }
    readonly property var pop: PanelHost.pop
    id: onOff
    property bool checked: false
    signal toggled()
    width: 40; height: 22; radius: Config.corner(11)
    color: checked ? Config.accentFor(onOffHover.hovered) : pop.card
    HoverHandler { id: onOffHover }
    Rectangle {
        width: 16; height: 16; radius: Config.corner(8)
        anchors.verticalCenter: parent.verticalCenter
        x: onOff.checked ? parent.width - width - 3 : 3
        color: onOff.checked ? pop.accentText : pop.text
        Behavior on x { NumberAnimation { duration: Config.ms(120) } }
    }
    ClickTap { onTapped: onOff.toggled() }
}
