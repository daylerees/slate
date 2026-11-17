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

// Laid out like the other panels: the title with its switch, a line of status, a
// section (a dim heading over rows), then a link to the settings it touches
Column {
    required property var pop
    width: 300
    spacing: 10
    PanelTitle {
        text: "Game Mode"
        Switch {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: Config.gameMode
            onToggled: Config.setGameMode(!Config.gameMode)
        }
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: pop.dim
        font.pixelSize: Config.text(12)
        font.weight: Font.Normal
        text: Config.gameMode ? "On: these are off for smoother games. Turning it off puts them back as you had them"
            : "Turns off what costs the most to draw, for smoother games. Your settings come back when you turn it off"
    }
    Divider {}
    Heading { text: Config.gameMode ? "Turned off" : "Turns off" }
    Column {
        width: parent.width
        Repeater {
            model: [
                { code: 0xF4CF, label: "Glass and blur" },
                { code: 0xEB2F, label: "See-through windows" },
                { code: 0xEC6C, label: "Shadows" },
                { code: 0xEA38, label: "Animations" },
                { code: 0xEA9B, label: "Live window previews (shapes instead)" },
                { code: 0xEA35, label: "Notification pop-ups (they still go to the list)" },
                { code: 0xEB63, label: "Ignoring the touchpad while you type" }
            ].concat(Config.s.pointerTrail ? [{ code: 0xF1D4, label: "The pointer's trail" }] : [])
            delegate: Item {
                required property var modelData
                width: parent.width; height: 32
                Icon {
                    id: gmIcon
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    code: parent.modelData.code; font.pixelSize: 16
                    color: Config.gameMode ? pop.accent : pop.dim
                }
                Label {
                    anchors { left: gmIcon.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.label; font.weight: Font.Normal
                    elide: Text.ElideRight
                }
            }
        }
    }
    Divider {}
    LinkRow {
        code: 0xEB20; text: "Appearance settings"
        onClicked: pop.openSettingsPage("appearance")
    }
}
