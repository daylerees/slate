import QtQuick

// The card in the middle of a dialog (the confirmation window, the password window): Slate's
// raised surface that eases in with `fade`, and swallows clicks so they don't reach the
// backdrop behind. The caller gives its width and height, and what goes on it.
Rectangle {
    id: card
    property real fade: 0
    anchors.centerIn: parent
    radius: Config.corner(18)
    opacity: fade
    scale: 0.94 + 0.06 * fade
    Shadow {}      // raised: Slate's shadow, with glass too

    MouseArea { anchors.fill: parent }    // swallow clicks inside the card
}
