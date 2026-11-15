// A tooltip: the small label saying what the pointer's over. One look everywhere, the dock's
// (an app's name over its icon): a rounded box in the bar's and the dock's colour, glossy with
// glass, with Slate's shadow under it, its words in the bar's font at 13 px. A host needs
// Config.shadowReach of room round it for the shadow. Every tooltip in Slate draws this bubble; where
// it goes, when it shows and how it fades stay with whatever hosts it (the dock's label, the
// label off the menu bar, a changed setting's dot in Settings):
//   Tooltip { text: "Downloads"; x: …; y: …; visible: … }
// Its words are always plain text: a tooltip often shows a name another program chose (an
// app's, a window's title, a tray icon's).

import QtQuick

Rectangle {
    id: tip
    property string text: ""
    // No wider than this, the words cut short with "…" (0: as wide as its words)
    property real maxWidth: 0
    // Over Slate's own content (inside a window, like Settings) rather than the desktop: solid,
    // as glass laid over glass shows as a lighter patch. Over the desktop (the dock's, the
    // bar's) it's the glass surface, and Hyprland blurs behind it
    property bool solid: false
    readonly property real padX: 8
    readonly property real padY: 4

    width: maxWidth > 0 ? Math.min(maxWidth, words.implicitWidth + 2 * padX) : words.implicitWidth + 2 * padX
    height: words.implicitHeight + 2 * padY
    radius: Config.corner(6)
    color: solid ? Config.tint("#0f1216") : Config.surface(Config.tint("#0f1216"))     // the bar's and the dock's
    Gloss { radius: parent.radius }   // glass: a sheen
    Shadow {}                         // raised: Slate's shadow (Settings → Appearance; off in game mode)

    Text {
        id: words
        anchors.centerIn: parent
        width: tip.maxWidth > 0 ? Math.min(implicitWidth, tip.maxWidth - 2 * tip.padX) : implicitWidth
        elide: Text.ElideRight
        textFormat: Text.PlainText        // never markup: an app's name, a window's or a tray icon's title
        text: tip.text
        color: Config.tint("#eef1f5")
        font.family: Config.s.fontFamily
        font.weight: Font.Medium
        font.pixelSize: 13
    }
}
