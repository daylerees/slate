import QtQuick

// The dimmed desktop behind a dialog (the confirmation window, the password window): fades with
// the dialog, and a click on it dismisses the dialog (it's only listening while `active`).
Rectangle {
    id: backdrop
    property real fade: 0
    property bool active: false
    signal dismissed()
    anchors.fill: parent
    color: "#000000"
    opacity: 0.45 * fade
    MouseArea { anchors.fill: parent; enabled: backdrop.active; onClicked: backdrop.dismissed() }
}
