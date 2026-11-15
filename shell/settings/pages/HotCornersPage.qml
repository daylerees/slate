import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: hcCol
    spacing: 4
    readonly property var actions: [
        { value: "none", label: "Nothing" },
        { value: "lock", label: "Lock screen" },
        { value: "launcher", label: "App launcher" },
        { value: "overview", label: "Workspace overview" },
        { value: "control", label: "Control Center" },
        { value: "notifications", label: "Notifications" },
        { value: "screenoff", label: "Turn screen off" }
    ]
    PageTitle { text: "Hot Corners" }
    IntroText { text: "Rest the pointer in a corner of the screen to run an action." }
    // The screen, with each corner's action; click one to set it below
    property string corner: "TopLeft"
    readonly property string cornerName: ({ TopLeft: "Top left", TopRight: "Top right", BottomLeft: "Bottom left", BottomRight: "Bottom right" })[corner]
    GroupLabel { text: "Corners" }
    Group {
        Item {
            width: parent.width
            height: cornerPicker.height + 24
            HotCornerPicker {
                id: cornerPicker
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 24)
                selected: hcCol.corner
                actions: hcCol.actions
                accent: win.accent; textColor: win.text; dimColor: win.dim
                fontFamily: win.font; iconFont: win.bar.iconFont
                onPicked: c => hcCol.corner = c
            }
        }
        Separator {}
        DropdownSetting {
            label: hcCol.cornerName
            detail: "What resting the pointer in this corner does"
            options: hcCol.actions
            value: Config.s["hotCorner" + hcCol.corner]
            onPicked: v => Config.s["hotCorner" + hcCol.corner] = v
        }
    }
    GroupLabel { text: "Timing" }
    Group {
        SettingRow {
            label: "Delay"
            settingKey: "hotCornerDelay"
            detail: "How long to rest in the corner before it triggers"
            ValueSlider { from: 0; to: 1500; stepSize: 50; suffix: " ms"; value: Config.s.hotCornerDelay; onMoved: v => Config.s.hotCornerDelay = v }
        }
    }
}
