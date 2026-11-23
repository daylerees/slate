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
            detail: win.notifs && win.notifs.quietWhy !== ""
                ? "On by itself " + win.notifs.quietWhy + ". Switching it off lets notifications through till then"
                : "Quietens pop-ups so you can focus (critical ones still show). Nothing's lost: everything still goes to history"
            SettingToggle { checked: win.notifs ? win.notifs.quiet : false; onToggled: v => { if (win.notifs) win.notifs.setQuiet(v); } }
        }
        Separator {}
        SoundSetting {
            label: "Sound"
            detail: "A soft chime when a notification pops up (also in Sound settings)"
            which: "notification"; sample: "notification"
        }
    }
    // Do Not Disturb by itself (Notifications.qml: autoWhy), and who still gets through
    GroupLabel { text: "Quiet by itself" }
    Group {
        ToggleSetting {
            label: "On a schedule"
            detail: "Do Not Disturb comes on at the times you choose. Switching it off by hand lasts until the next change"
            key: "dndSchedule"
        }
        Separator { visible: Config.s.dndSchedule }
        DropdownSetting {
            visible: Config.s.dndSchedule
            label: "From"
            settingKey: "dndFrom"
            searchable: true        // (48 half-hours: type 7 to get to the morning)
            value: Config.s.dndFrom
            options: win.halfHours(0, 23.5)
            onPicked: v => Config.s.dndFrom = v
        }
        Separator { visible: Config.s.dndSchedule }
        DropdownSetting {
            visible: Config.s.dndSchedule
            label: "Until"
            settingKey: "dndTo"
            searchable: true        // (48 half-hours: type 7 to get to the morning)
            value: Config.s.dndTo
            options: win.halfHours(0, 23.5)
            onPicked: v => Config.s.dndTo = v
        }
        Separator { visible: Config.s.dndSchedule }
        DropdownSetting {
            visible: Config.s.dndSchedule
            label: "On"
            settingKey: "dndDays"
            options: [{ value: "every", label: "Every day" }, { value: "weekdays", label: "Weekdays" }, { value: "weekends", label: "Weekends" }]
            value: Config.s.dndDays
            onPicked: v => Config.s.dndDays = v
        }
        Separator {}
        ToggleSetting {
            label: "While a window is full screen"
            detail: "A film, a game or a presentation isn't interrupted"
            key: "dndFullscreen"
        }
        Separator {}
        ToggleSetting {
            label: "During calls"
            detail: "While an app is using your microphone"
            key: "dndCalls"
        }
    }
    GroupLabel { text: "Still let through" }
    Group {
        Repeater {
            model: Config.s.dndAllowed || []
            delegate: Column {
                id: allowedRow
                required property string modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: allowedRow.index > 0 }
                ListItemRow {
                    label: allowedRow.modelData
                    detail: "Its notifications pop up even while Do Not Disturb is on"
                    onRemoved: Config.s.dndAllowed = (Config.s.dndAllowed || []).filter(a => a !== allowedRow.modelData)
                }
            }
        }
        Separator { visible: (Config.s.dndAllowed || []).length > 0 }
        DropdownSetting {
            id: allowAdd
            label: "Add an app"
            detail: options.length > 0 ? "Apps that have sent you notifications. Urgent notifications always get through"
                : "Apps show up here once they've sent you a notification"
            noneLabel: "Choose"
            value: ""
            options: {
                const seen = [], apps = {};
                for (const h of (win.notifs ? win.notifs.history : []))
                    if (h.appName && seen.indexOf(h.appName) < 0 && (Config.s.dndAllowed || []).indexOf(h.appName) < 0) {
                        seen.push(h.appName);
                        apps[h.appName] = h.entryId || "";
                    }
                return seen.sort((a, b) => a.localeCompare(b)).map(n => ({ value: n, label: n, app: apps[n] }));
            }
            onPicked: v => { if (v) Config.s.dndAllowed = (Config.s.dndAllowed || []).concat([v]); }
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
                        // By keyboard: a stop for Tab, Enter or Space does what a click does, with the ring while it has the keyboard
                        activeFocusOnTab: visible && enabled
                        Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { Config.s.notificationPosition = modelData; e.accepted = true; } }
                        FocusRing { round: 6 }
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
