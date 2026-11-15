import QtQuick
import qs

// A thin level bar: a rounded track with a fill from the start to `value` (0 … 1). The
// battery's charge and its meters, the Wi-Fi signal and the volume pop-up all use it, so
// they stay the same height and rounding. Put it where it goes and give it a width.
Rectangle {
    id: meter
    property real value: 0
    property color colour: "transparent"      // the fill
    property color trackColour: "transparent"
    // The least the fill shows, so a level of nothing still has its dot (0: none at all)
    property real minFill: height
    // How long the fill takes to change colour, or to slide to a new level (0: at once)
    property int colourMs: 0
    property int slideMs: 0
    height: 6
    radius: Config.corner(3)
    color: trackColour
    Rectangle {
        width: Math.max(meter.minFill, meter.width * meter.value)
        height: parent.height
        radius: Config.corner(3)
        color: meter.colour
        Behavior on color { enabled: meter.colourMs > 0; ColorAnimation { duration: Config.ms(meter.colourMs) } }
        Behavior on width { enabled: meter.slideMs > 0; NumberAnimation { duration: Config.ms(meter.slideMs); easing.type: Easing.OutCubic } }
    }
}
