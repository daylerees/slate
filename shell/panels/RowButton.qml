import QtQuick
import qs

// A row you can click, highlighted on hover (or blue when selected)
Rectangle {
    readonly property var pop: PanelHost.pop
    id: rb
    property bool selected: false
    property bool toggles: false       // a click turns it off again: lighter under the pointer while it's on
    property bool danger: false        // destructive: the muted hover in red
    signal clicked()
    height: 36
    radius: Config.corner(8)
    color: selected ? (toggles && rbHover.hovered ? Config.accentLit : pop.accent) : rbHover.hovered ? (danger ? Config.hoverDanger : Config.hover) : "transparent"
    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
    HoverHandler { id: rbHover }
    ClickTap { onTapped: rb.clicked() }
}
