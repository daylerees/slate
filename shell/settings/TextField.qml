import QtQuick
import ".."

// A text box on a row: FieldFrame round a TextInput, in Settings' look (the accent for selected
// text), with a faint hint while it's empty. `input` is the TextInput itself, for anything more
// (a validator, its own keys); `text`, what's in it.
//   TextField { width: 220; hint: "Sam Lee"; onFinished: … }
FieldFrame {
    id: box
    property alias text: input.text
    property alias input: input
    property string hint: ""
    property bool secret: false
    property int textSize: 12
    property int padding: 10
    property bool hintWhileTyping: false     // (the hint stays until something's typed, focused or not)
    signal accepted()
    signal edited()          // typed into
    signal finished()        // Enter, or left
    field: input
    width: 220; height: 30
    TextInput {
        id: input
        activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
        anchors { fill: parent; leftMargin: box.padding; rightMargin: box.padding }
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: box.win.text; selectionColor: box.win.accent
        font.family: box.win.font; font.pixelSize: Config.text(box.textSize)
        echoMode: box.secret ? TextInput.Password : TextInput.Normal
        onAccepted: box.accepted()
        onTextEdited: box.edited()
        onEditingFinished: box.finished()
    }
    Text {
        visible: input.text === "" && (box.hintWhileTyping || !input.activeFocus) && box.hint !== ""
        anchors { left: parent.left; leftMargin: box.padding; right: parent.right; rightMargin: box.padding; verticalCenter: parent.verticalCenter }
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: box.hint
        color: box.win.dim; font.family: box.win.font; font.pixelSize: Config.text(box.textSize)
    }
}
