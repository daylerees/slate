import QtQuick

// Slate's one switch: a track with a sliding knob. Settings, the bar editor, the confirmation
// window, the Welcome window and the launcher all draw it here, so a change to the look is made
// once. The track is 42 × 24 unless a caller sizes it; the knob is 6 px smaller than the track's
// height, and the corners follow Config.corner.
//
// Two ways to use it:
//   - on its own (the default): it has its own hover and tap handlers, a soft accent ring under
//     the pointer, and emits toggled(value) when pressed.
//   - `plain: true`: just the drawing. Whatever row it sits in does the pressing, and passes
//     `hovered` (the row's own hover) so the lit accent follows the pointer.
// The colours belong to whoever's window it is, so they're given: onColor (the default is the
// accent, a little lighter under the pointer: the lit accent rule in docs/CONVENTIONS.md),
// offColor, knobOn and knobOff. `hoverFill` gives the off track the muted hover over `fillBase`.
Rectangle {
    // (a screen reader: a check box, on or off, that it can switch)
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: toggled(!checked)
    Accessible.onPressAction: toggled(!checked)
    id: sw
    property bool checked: false
    property bool plain: false
    property bool hovered: own.hovered
    property bool hoverFill: false
    property color fillBase: "transparent"
    property color onColor: Config.accentFor(hovered)
    property color offColor: "transparent"
    property color knobOn: Config.tint("#12151a")
    property color knobOff: "white"
    property color ringColor: Config.accent
    property int colorMs: 120
    property int knobMs: 140
    property int knobEasing: Easing.OutCubic
    signal toggled(bool value)

    width: 42; height: 24; radius: Config.corner(height / 2)
    color: checked ? onColor : offColor
    Behavior on color { ColorAnimation { duration: Config.ms(sw.colorMs) } }

    HoverFill { base: sw.fillBase; hovered: sw.hovered; gone: sw.checked; radius: sw.radius; visible: sw.hoverFill }

    // Under the pointer: a soft accent ring around the switch
    Rectangle {
        visible: !sw.plain
        anchors { fill: parent; margins: -3 }
        radius: Config.corner(height / 2)
        color: "transparent"
        border.width: 2; border.color: sw.ringColor
        opacity: sw.hovered ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
    }
    HoverHandler { id: own; enabled: !sw.plain }

    Rectangle {
        z: 1                       // (above a sheen a caller lays on the track)
        width: sw.height - 6; height: width; radius: Config.corner(width / 2)
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 3 : 3
        color: sw.checked ? sw.knobOn : sw.knobOff
        Behavior on x { NumberAnimation { duration: Config.ms(sw.knobMs); easing.type: sw.knobEasing } }
    }
    ClickTap { enabled: !sw.plain; onTapped: sw.toggled(!sw.checked) }
}
