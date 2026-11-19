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
    // (the keyboard: a stop for Tab and the arrow keys, which the panel moves between:
    // Popouts.keyStep; Enter or Space presses; its ring)
    activeFocusOnTab: visible && enabled
    Keys.onPressed: e => {
        if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
        toggled();
        e.accepted = true;
    }
    FocusRing { round: 13 }
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
