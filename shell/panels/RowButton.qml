import QtQuick
import qs

// A row you can click, highlighted on hover (or blue when selected)
Rectangle {
    readonly property var pop: PanelHost.pop
    id: rb
    property bool selected: false
    property bool toggles: false       // a click turns it off again: lighter under the pointer while it's on
    property bool danger: false        // destructive: the muted hover in red
    property color hoverBase: "transparent"   // its fill while not selected (the control center's tiles: the card)
    signal clicked()
    // (the keyboard's Menu key, or Shift+F10, on it: what a right-click on it does, for a row
    // that has a menu of its own: the More panel's)
    signal menuAsked()
    // (the keyboard's Delete on it: for a row that can be removed, as the saved spaces can)
    signal removeAsked()
    // (a screen reader: a button, named by the words on it)
    Accessible.role: Accessible.Button
    Accessible.name: Config.textOf(rb)
    Accessible.onPressAction: clicked()
    // (the keyboard: a stop for Tab and the arrow keys, which the panel moves between:
    // Popouts.keyStep; Enter or Space presses; its ring)
    activeFocusOnTab: visible && enabled
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Menu || (e.key === Qt.Key_F10 && (e.modifiers & Qt.ShiftModifier))) { menuAsked(); e.accepted = true; return; }
        if (e.key === Qt.Key_Delete) { removeAsked(); e.accepted = true; return; }
        if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
        clicked();
        e.accepted = true;
    }
    FocusRing { round: 10 }
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
    HoverFill { base: rb.hoverBase; hover: rb.danger ? Config.hoverDanger : Config.hover; hovered: rbHover.hovered; gone: rb.selected; radius: rb.radius }
    HoverHandler { id: rbHover }
    ClickTap { onTapped: rb.clicked() }
}
