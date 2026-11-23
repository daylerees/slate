import QtQuick
import ".."

// Slider with its value shown alongside
Row {
    readonly property var win: SettingsHost.win
    id: valueSlider
    property real from: 0
    property real to: 1
    property real stepSize: 0.1
    property real value: 0
    property string suffix: ""
    property string zeroText: ""   // shown instead of the value at the bottom (e.g. "Off")
    // How many of the slider's units one of the setting's is: 100 for a setting kept as 0–1 and
    // shown as a percentage. Its row uses it to say what the default is, in the slider's terms
    property real per: 1
    property int decimals: 0
    signal moved(real value)
    signal released()          // let go of the slider (after moving it, or a click)
    spacing: 12
    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 56
        horizontalAlignment: Text.AlignRight
        text: valueSlider.zeroText !== "" && valueSlider.value <= valueSlider.from ? valueSlider.zeroText : valueSlider.value.toFixed(valueSlider.decimals) + valueSlider.suffix
        color: win.dim
        font.family: win.font; font.pixelSize: Config.text(12)
    }
    Item {
        width: 200; height: 24
        readonly property real frac: (valueSlider.value - valueSlider.from) / (valueSlider.to - valueSlider.from)
        id: sliderBox
        readonly property bool hot: sliderMouse.containsMouse || sliderMouse.pressed
        Rectangle {
            id: trk
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: Config.corner(3)
            color: "transparent"
            HoverFill { base: win.control; hovered: sliderBox.hot; radius: trk.radius }
            Rectangle {
                width: Math.max(6, trk.width * parent.parent.frac); height: parent.height; radius: Config.corner(3); color: win.accent
            }
        }
        // Hover: an accent halo behind the knob, which grows a little
        Rectangle {
            width: 28; height: 28; radius: Config.corner(14)
            anchors.verticalCenter: parent.verticalCenter
            x: parent.frac * (parent.width - 16) + 8 - width / 2
            color: win.accent
            opacity: sliderBox.hot ? 0.22 : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        }
        Rectangle {
            width: 16; height: 16; radius: Config.corner(8)
            anchors.verticalCenter: parent.verticalCenter
            x: parent.frac * (parent.width - 16)
            color: win.text
            Gloss { radius: parent.radius; strength: 0.6 }   // glass: a sheen
            scale: sliderBox.hot ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: Config.ms(120) } }
        }
        MouseArea {
            id: sliderMouse
            // Keep the drag once it's started here: the scrolling page around it took over
            // when the pointer drifted up or down, and the slider stopped following it
            preventStealing: true
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor      // (a hand over it, as over what's clicked)
            function set(mx) {
                const raw = valueSlider.from + Math.max(0, Math.min(1, mx / width)) * (valueSlider.to - valueSlider.from);
                valueSlider.moved(Math.round(raw / valueSlider.stepSize) * valueSlider.stepSize);
            }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x); }
            onReleased: valueSlider.released()
        }
    }
}
