// The on-screen keyboard's keys (Settings → Accessibility → On-screen keyboard), drawn the same
// wherever they show: on the desktop (OnScreenKeyboard.qml, which types them into the app you're
// in) and on the lock and login screens (LoginScreen.qml, into the password box). They don't
// know where their keys go: `typed(text)` for a character, `key(name)` for BackSpace, Return,
// Tab, Left or Right.
//
// Letters, a number row, Shift (once: the next letter; twice: caps lock) and a page of symbols.
// A press clicks on the desktop (`sounds`), never on the lock and login screens, which stay
// silent.

import QtQuick

Rectangle {
    id: keys
    signal typed(string text)
    signal key(string name)
    signal hide()                           // the hide key, bottom left
    property bool sounds: true
    property color keyFill: Config.palette.control
    property color keyText: Config.palette.text
    property color accentText: Config.palette.accentText
    property string fontFamily: Config.s.fontFamily
    property real keySize: 46
    readonly property real gap: 6
    property int shift: 0                   // 0 off, 1 the next letter, 2 caps lock
    property bool symbols: false
    color: Config.palette.base
    radius: Config.corner(16)
    width: keySize * 10 + gap * 9 + 28
    height: column.implicitHeight + 28

    readonly property var letterRows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    readonly property var symbolRows: ["-/:;()&@\"", ".,?!'#%*+=", "_\\|~<>[]{}"]
    function label(c) { return keys.shift > 0 ? c.toUpperCase() : c; }
    function press(c) {
        keys.typed(keys.symbols ? c : label(c));
        if (keys.shift === 1) keys.shift = 0;
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: keys.gap
        // Numbers
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: keys.gap
            Repeater { model: "1234567890".split(""); delegate: Key { required property string modelData; text: modelData; onPressed: keys.typed(modelData) } }
        }
        // Letters (or symbols)
        Repeater {
            model: 3
            delegate: Row {
                id: row
                required property int index
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: keys.gap
                Key {
                    visible: row.index === 2
                    text: keys.symbols ? "" : keys.shift === 2 ? "⇪" : "⇧"
                    wide: 1.5
                    on: keys.shift > 0
                    enabled: !keys.symbols
                    onPressed: keys.shift = (keys.shift + 1) % 3
                }
                Repeater {
                    model: (keys.symbols ? keys.symbolRows : keys.letterRows)[row.index].split("")
                    delegate: Key { required property string modelData; text: keys.symbols ? modelData : keys.label(modelData); onPressed: keys.press(modelData) }
                }
                Key { visible: row.index === 2; text: "⌫"; wide: 1.5; onPressed: keys.key("BackSpace") }
            }
        }
        // Symbols, Tab, space, arrows, Enter
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: keys.gap
            Key { text: "⌄"; onPressed: keys.hide() }
            Key { text: keys.symbols ? "abc" : "#+="; wide: 1.5; on: keys.symbols; onPressed: keys.symbols = !keys.symbols }
            Key { text: "⇥"; onPressed: keys.key("Tab") }
            Key { text: "space"; wide: 3; onPressed: keys.typed(" ") }
            Key { text: "←"; onPressed: keys.key("Left") }
            Key { text: "→"; onPressed: keys.key("Right") }
            Key { text: "↵"; wide: 1.5; on: true; onPressed: keys.key("Return") }
        }
    }

    component Key: Rectangle {
        id: k
        property string text
        property real wide: 1
        property bool on: false
        signal pressed()
        width: keys.keySize * wide + keys.gap * (wide - 1)
        height: keys.keySize
        radius: Config.corner(8)
        opacity: enabled ? 1 : 0.4
        // (on: the accent, lighter under the pointer as every accent-filled control is)
        color: on ? Config.accentFor(kHover.hovered && k.enabled) : keys.keyFill
        // (plain handlers, not Slate's ClickTap and HoverFill: the login screen's copy has only
        // what's in greeter/files, and stays silent; on the desktop the click is played here)
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Config.hover
            visible: kHover.hovered && k.enabled && !k.on
        }
        Text {
            anchors.centerIn: parent
            text: k.text
            color: k.on ? keys.accentText : keys.keyText
            font.family: keys.fontFamily; font.pixelSize: Config.text(k.text.length > 1 ? 14 : 18)
        }
        HoverHandler { id: kHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            enabled: k.enabled
            onTapped: { if (keys.sounds) Config.click(); k.pressed(); }
        }
    }
}
