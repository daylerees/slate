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
    // The active colour fades in and out; the muted hover is HoverFill's, there at once with the
    // pointer (as the launcher's highlight is), so moving down a list never leaves a trail
    color: selected ? (toggles && rbHover.hovered ? Config.accentLit : pop.accent) : Qt.rgba(pop.accent.r, pop.accent.g, pop.accent.b, 0)
    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
    HoverFill { hover: rb.danger ? Config.hoverDanger : Config.hover; hovered: rbHover.hovered; gone: rb.selected; radius: rb.radius }
    HoverHandler { id: rbHover }
    ClickTap { onTapped: rb.clicked() }
}
