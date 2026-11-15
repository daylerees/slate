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
    // Text and icons on it: the plain colour, or the dark one on the active colour (what the
    // row's own words, and the Icons in it, take, so each needn't say it again)
    readonly property color fg: selected ? pop.accentText : pop.text
    readonly property color fgDim: selected ? pop.accentText : pop.dim
    height: 36
    radius: Config.corner(8)
    color: selected ? (toggles && rbHover.hovered ? Config.accentLit : pop.accent) : rbHover.hovered ? (danger ? Config.hoverDanger : Config.hover) : "transparent"
    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
    HoverHandler { id: rbHover }
    ClickTap { onTapped: rb.clicked() }
}
