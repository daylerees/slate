import QtQuick

// Slate's busy spinner: its loading icon turning, in the accent unless given a colour. Turns
// while it shows, and keeps still with Animations off and in game mode (it's a loop, not a
// transition, so its own timing, not Config.ms)
//   Spinner { visible: busy; size: 16 }
Text {
    id: spinner
    property color colour: Config.accent
    property int size: 16
    property bool spinning: true        // (false: still, though shown; as when its window's away)
    text: Config.glyph(0xF226)
    color: colour
    font.family: Config.iconFont
    font.pixelSize: size
    RotationAnimation on rotation {
        running: spinner.visible && spinning && Config.animate && !Config.gameMode
        loops: Animation.Infinite; from: 0; to: 360; duration: 900
    }
}
