import QtQuick
import ".."

// A round icon button (the header's back and close): under the pointer, the muted hover fill
// at once and a glyph that brightens
Rectangle {
    readonly property var win: SettingsHost.win
    id: iconButton
    property int icon                  // a Tabler glyph's code point
    signal clicked()
    // (a screen reader: a button, named for what its icon means)
    property string name: ({ [0xEB55]: "Close", [0xEA19]: "Back", [0xEA60]: "Previous", [0xEA61]: "Next" })[icon] || ""
    Accessible.role: Accessible.Button
    Accessible.name: name
    Accessible.onPressAction: clicked()
    width: 34; height: 34; radius: Config.corner(17)
    color: iconButtonHover.hovered ? Config.hover : "transparent"
    Text {
        anchors.centerIn: parent
        text: win.glyph(iconButton.icon)
        color: iconButtonHover.hovered ? win.text : win.dim
        // (with the fill behind it, not ahead of it)
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        font.family: win.bar.iconFont; font.pixelSize: 18
    }
    HoverHandler { id: iconButtonHover }
    ClickTap { onTapped: iconButton.clicked() }
}
