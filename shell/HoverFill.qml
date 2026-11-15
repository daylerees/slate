// A control's own fill, giving way to the muted hover under the pointer (Config.hover takes a
// fill's place, it isn't laid over it). Animating one colour from a solid fill to the
// see-through hover instead passes through colours brighter than either end, which showed as a
// flash each time the pointer came or went.
//   Rectangle { color: current ? accent : "transparent"; HoverFill { base: grey; hovered: h.hovered; gone: current; radius: parent.radius } }
// gone: neither shows (the control is selected, and wears the active colour itself)
//
// The hover comes and goes at once, with the pointer, as the launcher's highlight does: a fade
// trailed behind a pointer moving down a list, a row or two lit at a time. Only `gone` fades
// (the control being selected, or let go of), in step with the active colour it wears.
// With nothing of its own under it (base "transparent"), it's the hover alone: the muted hover
// of a row that's also selectable (RowButton, Settings' sidebar). Its parent's colour then
// fades between the accent at no strength (Qt.rgba(a.r, a.g, a.b, 0)) and the accent, so the
// fade never darkens on the way, as it would from "transparent" (black at no strength).

import QtQuick

Item {
    id: hf
    property color base: "transparent"
    property color hover: Config.hover          // (Config.hoverDanger for something destructive)
    property bool hovered: false
    property bool gone: false
    property real radius: 0
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    anchors.fill: parent
    z: -1
    opacity: gone ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    Rectangle {
        anchors.fill: parent
        topLeftRadius: hf.topLeftRadius; topRightRadius: hf.topRightRadius
        bottomLeftRadius: hf.bottomLeftRadius; bottomRightRadius: hf.bottomRightRadius
        color: hf.base
        visible: !hf.hovered
    }
    Rectangle {
        anchors.fill: parent
        topLeftRadius: hf.topLeftRadius; topRightRadius: hf.topRightRadius
        bottomLeftRadius: hf.bottomLeftRadius; bottomRightRadius: hf.bottomRightRadius
        color: hf.hover
        visible: hf.hovered
    }
}
