import QtQuick
import qs

Text {
    readonly property var pop: PanelHost.pop
    property int code: 0
    text: pop.glyph(code)
    color: pop.text
    font.family: pop.bar.iconFont
    font.pixelSize: 18
}
