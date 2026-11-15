import QtQuick
import qs

// (plain text, never markup: most of what the panels say is a name something else chose,
// a Wi-Fi network's, a Bluetooth device's, a track's, what you copied. One that means to
// use markup says so itself, as ForecastDay does)
Text {
    readonly property var pop: PanelHost.pop
    textFormat: Text.PlainText
    color: pop.text
    font.family: pop.bar.fontFamily
    font.pixelSize: 13
    font.weight: Font.Medium
    elide: Text.ElideRight
}
