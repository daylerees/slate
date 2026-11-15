import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects
import qs

// ---- Keyboard layout --------------------------------------------------
// The layouts from Settings → Input; click one to switch to it
Column {
    required property var pop
    width: 280
    spacing: 10
    PanelTitle { text: "Keyboard layout"; height: textHeight }
    Column {
        width: parent.width
        spacing: 6
        Repeater {
            model: Config.kbLayoutList
            delegate: RowButton {
                id: layoutBtn
                required property var modelData
                required property int index
                width: parent.width
                selected: index === Config.kbActive
                onClicked: Config.switchLayout(index)
                // The short code in a little key cap, then the full name
                Rectangle {
                    id: codeCap
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: Math.max(28, codeText.implicitWidth + 10); height: 22; radius: Config.corner(5)
                    color: layoutBtn.selected ? Qt.rgba(0, 0, 0, 0.15) : pop.card
                    Text {
                        id: codeText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText        // never markup
                        text: layoutBtn.modelData.code
                        color: layoutBtn.fg
                        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        font.family: pop.bar.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                    }
                }
                Label {
                    anchors { left: codeCap.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: layoutBtn.modelData.name
                    color: layoutBtn.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                }
            }
        }
    }
    Divider {}
    LinkRow {
        code: 0xEB20; text: "Keyboard settings"
        onClicked: pop.openSettingsPage("input")
    }
}
