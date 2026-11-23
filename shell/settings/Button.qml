import QtQuick
import ".."

Rectangle {
    readonly property var win: SettingsHost.win
    id: btn
    property string label
    // (a screen reader: a button, by its label)
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: clicked()
    property bool primary: false
    property bool destructive: false
    property int icon: 0          // optional Tabler glyph before the label
    property bool compactLabel: false   // with an icon: show just the icon (narrow window)
    signal clicked()
    width: btnRow.implicitWidth + 28; height: 32; radius: Config.corner(8)
    color: primary ? Config.accentFor(btnHover.hovered) : "transparent"
    HoverFill { base: win.control; hover: parent.destructive ? Config.hoverDanger : Config.hover; hovered: btnHover.hovered; gone: parent.primary; radius: parent.radius }
    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
    readonly property color fg: primary ? win.accentText : destructive ? win.danger : win.text
    Row {
        id: btnRow
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: btn.icon !== 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon ? Config.glyph(btn.icon) : ""
            color: btn.fg
            font.family: win.bar.iconFont; font.pixelSize: 15
        }
        Text {
            visible: !(btn.compactLabel && btn.icon !== 0)
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.fg
            font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
        }
    }
    HoverHandler { id: btnHover }
    ClickTap { onTapped: btn.clicked() }
}
