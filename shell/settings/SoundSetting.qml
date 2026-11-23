import QtQuick
import ".."

// One of Slate's sounds: a play button to hear it, and a volume slider, Off at 0; letting go
// of the slider plays it too, at that volume
SettingRow {
    id: soundSetting
    property string which              // Config.soundSettings key
    property string sample             // sounds/<sample>.wav to play as a preview
    property bool available: true
    readonly property bool audible: available && Config.soundVolume(which) > 0
    Row {
        spacing: 6
        // Play: the sound at its volume (dimmed while it's off, with nothing to hear). A plain
        // TapHandler, not ClickTap: the sound it plays is its own feedback
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: Config.corner(14)
            opacity: soundSetting.audible ? 1 : 0.4
            color: "transparent"
            HoverFill { base: win.control; hovered: playHover.hovered && soundSetting.audible; radius: parent.radius }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1      // the triangle looks centred a touch right
                text: Config.glyph(0xED46)                // play
                color: soundSetting.audible ? win.text : win.dim
                font.family: win.bar.iconFont; font.pixelSize: 14
            }
            HoverHandler { id: playHover; cursorShape: soundSetting.audible ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: soundSetting.audible; onTapped: Config.playSound(soundSetting.sample, soundSetting.which) }
        }
        ValueSlider {
            anchors.verticalCenter: parent.verticalCenter
            enabled: soundSetting.available
            opacity: enabled ? 1 : 0.4
            from: 0; to: 100; stepSize: 5; suffix: "%"; zeroText: "Off"
            value: soundSetting.available ? Config.soundVolume(soundSetting.which) : 0
            onMoved: v => Config.s[Config.soundSettings[soundSetting.which][0]] = Math.round(v)
            onReleased: Config.playSound(soundSetting.sample, soundSetting.which)
        }
    }
}
