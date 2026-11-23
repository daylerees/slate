import QtQuick
import ".."

// The box round a text field: the control colour with a sheen, an I-beam pointer, and a faint
// accent outline under the pointer (solid while typing). field: the TextInput inside it
Rectangle {
    readonly property var win: SettingsHost.win
    id: fieldFrame
    property Item field: null
    radius: Config.corner(8)
    color: win.control
    HoverHandler { id: fieldFrameHover; cursorShape: Qt.IBeamCursor }
    border.width: (fieldFrame.field && fieldFrame.field.activeFocus) || fieldFrameHover.hovered ? 1 : 0
    border.color: fieldFrame.field && fieldFrame.field.activeFocus ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.5)
}
