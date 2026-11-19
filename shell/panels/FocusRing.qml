import QtQuick
import qs

// The ring round a panel's control while it has the keyboard (Tab and the arrow keys:
// Popouts.keyStep): the accent, 2 px, just outside the control's edge. Every control in a
// panel that takes a click has one (tests/live/test_keyboard_navigation.py, EveryPanelControl)
Rectangle {
    // (round it the same as the control, a little bigger: it sits 2 px outside)
    property real round: 10
    z: 5
    visible: parent.activeFocus
    anchors { fill: parent; margins: -2 }
    color: "transparent"
    radius: Config.corner(round)
    border.width: 2
    border.color: Config.accent
}
