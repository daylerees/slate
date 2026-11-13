// A control's own fill, giving way to the muted hover under the pointer (Config.hover takes a
// fill's place, it isn't laid over it). The two cross-fade as layers. Animating one colour from
// a solid fill to the see-through hover instead passes through colours brighter than either
// end, which showed as a flash each time the pointer came or went.
//   Rectangle { color: current ? accent : "transparent"; HoverFill { base: grey; hovered: h.hovered; gone: current; radius: parent.radius } }
// gone: neither shows (the control is selected, and wears the active colour itself)

import QtQuick

Item {
    id: hf
    property color base
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
    Rectangle {
        anchors.fill: parent
        topLeftRadius: hf.topLeftRadius; topRightRadius: hf.topRightRadius
        bottomLeftRadius: hf.bottomLeftRadius; bottomRightRadius: hf.bottomRightRadius
        color: hf.base
        opacity: hf.gone || hf.hovered ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    }
    Rectangle {
        anchors.fill: parent
        topLeftRadius: hf.topLeftRadius; topRightRadius: hf.topRightRadius
        bottomLeftRadius: hf.bottomLeftRadius; bottomRightRadius: hf.bottomRightRadius
        color: hf.hover
        opacity: !hf.gone && hf.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    }
}
