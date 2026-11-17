import QtQuick

// A button at the foot of a dialog (the confirmation window, the password window). The primary
// one wears the accent, a little lighter under the pointer (the lit accent rule), or the danger
// colour for something destructive; the other is a quiet fill that the muted hover takes over.
// The colours are the dialog's own, so they're given.
//   focused: a keyboard focus ring just outside it (the confirmation window)
//   dimmed: it can't be used yet (the password window, until something's typed)
Rectangle {
    id: btn
    property string label: ""
    property bool primary: false
    property bool focused: false
    property bool ring: false
    property bool dimmed: false
    property bool danger: false
    property color fill: "transparent"           // the quiet button's colour
    property color textColor: "white"
    property color accentText: "black"
    property color dangerColor: "red"
    readonly property alias hovered: hh.hovered
    signal clicked()
    height: 40
    radius: Config.corner(10)
    readonly property color base: primary ? (danger ? dangerColor : Config.accentFor(hh.hovered)) : fill
    color: primary ? base : "transparent"
    HoverFill { base: btn.base; hovered: hh.hovered; gone: btn.primary; radius: btn.radius }
    opacity: dimmed ? 0.55 : 1
    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
    Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    HoverHandler { id: hh }
    // Keyboard focus ring, just outside the button
    Rectangle {
        visible: btn.ring
        anchors { fill: parent; margins: -4 }
        radius: Config.corner(parent.radius + 4)
        color: "transparent"
        border.width: 2
        border.color: btn.primary ? btn.base : btn.textColor
        opacity: btn.focused ? (btn.primary ? 0.55 : 0.35) : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    }
    ClickTap { onTapped: btn.clicked() }
    Text {
        anchors.centerIn: parent
        text: btn.label
        color: btn.primary ? btn.accentText : btn.textColor
        font.family: Config.s.fontFamily
        font.pixelSize: Config.text(13)
        font.weight: Font.DemiBold
    }
}
