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
    spacing: 4
    PageTitle { text: "Notifications" }
    GroupLabel { text: "Do Not Disturb & sound" }
    Group {
        SettingRow {
            label: "Do Not Disturb"
            detail: "Quietens pop-ups so you can focus (critical ones still show). Nothing's lost: everything still goes to history"
            SettingToggle { checked: win.notifs ? win.notifs.dnd : false; onToggled: v => { if (win.notifs) win.notifs.dnd = v; } }
        }
        Separator {}
        SoundSetting {
            label: "Sound"
            detail: "A soft chime when a notification pops up (also in Sound settings)"
            which: "notification"; sample: "notification"
        }
    }
    GroupLabel { text: "Pop-ups" }
    Group {
        SettingRow {
            label: "Position"
            settingKey: "notificationPosition"
            detail: "Where new notifications appear on screen"
            // A small screen: click a spot to put notifications there
            Rectangle {
                width: 168; height: 104; radius: Config.corner(10)
                color: win.well
                border.width: 1; border.color: win.controlHoverSolid
                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 } height: 9; topLeftRadius: Config.corner(9); topRightRadius: Config.corner(9); color: win.outline }
                Repeater {
                    model: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: Config.s.notificationPosition === modelData
                        width: 44; height: 22; radius: Config.corner(6)
                        x: [8, (168 - 44) / 2, 168 - 44 - 8][index % 3]
                        y: index < 3 ? 16 : 104 - 22 - 8
                        color: current ? win.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        HoverFill { base: win.divider; hovered: spotHover.hovered; gone: parent.current; radius: parent.radius }
                        HoverHandler { id: spotHover }
                        ClickTap { onTapped: Config.s.notificationPosition = parent.modelData }
                    }
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Stay on screen for"
            settingKey: "notificationSeconds"
            detail: "When the app doesn't choose its own time"
            ValueSlider { from: 2; to: 15; stepSize: 1; suffix: " s"; value: Config.s.notificationSeconds; onMoved: v => Config.s.notificationSeconds = v }
        }
        Separator {}
        SettingRow {
            label: "Most at once"
            settingKey: "notificationMaxToasts"
            ValueSlider { from: 1; to: 8; stepSize: 1; value: Config.s.notificationMaxToasts; onMoved: v => Config.s.notificationMaxToasts = v }
        }
    }
    // (only with glass on: Appearance → Glass)
    GroupLabel { visible: Config.s.glass; text: "Glass" }
    Group {
        visible: Config.s.glass
        ToggleSetting {
            label: "Blur"
            detail: "What's behind a notification is blurred, like frosted glass. Off, you see straight through it"
            key: "notificationBlur"
        }
        Separator {}
        SettingRow {
            label: "Opacity"
            settingKey: "notificationOpacity"
            detail: "How solid a notification's background is: 100% can't be seen through, lower is clearer"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.notificationOpacity * 100); onMoved: v => Config.s.notificationOpacity = v / 100 }
        }
        Separator {}
        SettingRow {
            label: "Hover opacity"
            settingKey: "notificationHoverOpacity"
            detail: "How solid it is while the pointer's on it, to read it by"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.notificationHoverOpacity * 100); onMoved: v => Config.s.notificationHoverOpacity = v / 100 }
        }
    }
    GroupLabel { text: "History" }
    Group {
        SettingRow {
            label: "Clear notification history"
            detail: win.notifs ? win.notifs.history.length + " saved" : ""
            Button { label: "Clear"; destructive: true; onClicked: if (win.notifs) win.notifs.clearAll() }
        }
    }
}
