import QtQuick
import ".."

// A search box: a magnifier, the text, a hint while it's empty, and (clearable) an × that
// empties it; outlined in the accent while it has the keyboard. Its keys (Up, Down, Enter…) come
// to the page through keyPressed (set e.accepted to keep one from the text box). `input` is the
// TextInput, for focus and anything more.
//   SearchField { id: find; hint: "Search shortcuts"; onKeyPressed: e => … }
Rectangle {
    id: box
    readonly property var win: SettingsHost.win
    property alias text: input.text
    property alias input: input
    property string hint: ""
    property int iconSize: 16
    property int textSize: 13
    property int edge: 14            // from the sides to the magnifier and the ×
    property int gap: 10             // from the magnifier to the text
    property bool clearable: false
    property int clearSize: 16
    signal keyPressed(var e)
    height: 40; radius: Config.corner(10)
    color: win.card
    border.width: input.activeFocus ? 1 : 0; border.color: win.accent
    // (anywhere in it gives the text the keyboard, with the I-beam over it)
    HoverHandler { cursorShape: Qt.IBeamCursor }
    TapHandler { onTapped: input.forceActiveFocus() }
    Text {
        id: glass
        anchors { left: parent.left; leftMargin: box.edge; verticalCenter: parent.verticalCenter }
        text: Config.glyph(0xEB1C)
        color: box.win.dim; font.family: Config.iconFont; font.pixelSize: box.iconSize
    }
    TextInput {
        id: input
        activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
        anchors { left: glass.right; leftMargin: box.gap; right: clear.visible || box.clearable ? clear.left : parent.right
                  rightMargin: box.clearable ? 8 : box.edge; verticalCenter: parent.verticalCenter }
        color: box.win.text; font.family: box.win.font; font.pixelSize: Config.text(box.textSize)
        selectionColor: box.win.accent; selectedTextColor: box.win.accentText
        clip: true
        Keys.onPressed: e => box.keyPressed(e)
        Text {
            visible: input.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: box.hint
            color: box.win.dim; font: input.font
        }
    }
    Text {
        id: clear
        visible: box.clearable && input.text !== ""
        anchors { right: parent.right; rightMargin: box.edge; verticalCenter: parent.verticalCenter }
        text: Config.glyph(0xEB55)
        color: clearHover.hovered ? box.win.text : box.win.dim
        // (with the fill behind it, not ahead of it)
        font.family: Config.iconFont; font.pixelSize: box.clearSize
        HoverHandler { id: clearHover }
        ClickTap { onTapped: { input.text = ""; input.forceActiveFocus(); } }
    }
}
