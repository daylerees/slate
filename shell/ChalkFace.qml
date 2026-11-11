// Chalk's icon in two colours (the Colourful look): put this inside any Text that draws the
// icon (Tabler's message-chatbot), and the face in the speech bubble takes a second colour.
//   Text { text: glyph(0xF38A); color: Config.pageColour("assistant"); ChalkFace {} }
// It's the same icon drawn again in the second colour, showing only where the face is, so it
// lines up at any size. The Text's own colour is the bubble's: Config.pageColour("assistant").
// With the Colourful look off, or in a Text drawing some other icon, it draws nothing, and
// the icon is one colour like every other.

import QtQuick

Item {
    id: root
    readonly property Text icon: parent as Text
    readonly property int code: 0xF38A
    anchors.fill: parent
    visible: Config.colourful && !!icon && icon.text === String.fromCodePoint(code)

    Item {
        // Where the face is, within the icon's square
        x: Math.round(root.width * 0.29); y: Math.round(root.height * 0.27)
        width: Math.round(root.width * 0.42); height: Math.round(root.height * 0.38)
        clip: true
        Text {
            x: -parent.x; y: -parent.y
            width: root.width; height: root.height
            horizontalAlignment: root.icon ? root.icon.horizontalAlignment : Text.AlignLeft
            verticalAlignment: root.icon ? root.icon.verticalAlignment : Text.AlignTop
            text: root.visible ? root.icon.text : ""
            color: Config.tint(Config.chalkPastels[1])
            font: root.icon ? root.icon.font : Qt.font({})
        }
    }
}
