import QtQuick
import qs

// A text box in a panel (the Wi-Fi password, a space's name and its colour code): a rounded
// box in the panel's card colour with the text in it, and a dim hint while it's empty.
Rectangle {
    id: field
    readonly property var pop: PanelHost.pop
    property alias text: textInput.text
    property alias input: textInput                  // the TextInput itself (focus, cursor, selection)
    property alias maximumLength: textInput.maximumLength
    property alias selectByMouse: textInput.selectByMouse
    property bool secret: false                      // dots instead of what's typed
    property string hint: ""                         // shown while it's empty
    property int hintWeight: Font.Normal
    property bool outlined: false                    // an accent outline while it has the keyboard
    property bool keepFocus: false                   // takes the keyboard when shown, and gets it back if a list lets go of it
    property real inset: 12                          // space before and after the text
    readonly property bool typing: textInput.activeFocus
    signal opened()                                  // it has just been shown
    signal accepted()
    signal textEdited()
    signal escaped()
    width: parent ? parent.width : 0
    height: 34
    radius: Config.corner(8)
    color: pop.card
    border.width: outlined && typing ? 1 : 0
    border.color: pop.accent
    TextInput {
        id: textInput
        anchors { fill: parent; leftMargin: field.inset; rightMargin: field.inset }
        verticalAlignment: TextInput.AlignVCenter
        echoMode: field.secret ? TextInput.Password : TextInput.Normal
        color: pop.text
        font.family: pop.bar.fontFamily
        font.pixelSize: 13
        focus: field.keepFocus && field.visible
        onVisibleChanged: if (visible) field.opened()
        // (its row can move as a list's order changes: the list lets go of the keyboard as it
        // moves a row, so take it back and carry on typing)
        onFocusChanged: if (field.keepFocus && !focus && visible) forceActiveFocus()
        onAccepted: field.accepted()
        onTextEdited: field.textEdited()
        Keys.onEscapePressed: field.escaped()
    }
    Label {
        visible: field.hint !== "" && textInput.text === ""
        anchors { left: parent.left; leftMargin: field.inset; verticalCenter: parent.verticalCenter }
        text: field.hint
        color: pop.dim
        font.weight: field.hintWeight
    }
}
