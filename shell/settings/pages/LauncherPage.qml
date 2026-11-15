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
    PageTitle { text: "Launcher" }
    GroupLabel { text: "Layout" }
    Group {
        SettingRow {
            label: "Layout"
            settingKey: "launcherLayout"
            detail: Config.s.launcherLayout === "grid"
                ? "Apps as a grid of icons, with the selected one's name along the bottom. Arrow keys move around it; Ctrl+Left/Right opens an app on a new workspace beside this one"
                : "Apps in a list, with descriptions. Left/Right opens an app on a new workspace beside this one"
            // Two-way switch: List | Grid
            Rectangle {
                readonly property var modes: ["list", "grid"]
                width: 184; height: 34; radius: Config.corner(9)
                color: win.well
                Rectangle {
                    width: 92 - 6; height: parent.height - 6; radius: Config.corner(7)
                    y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.s.launcherLayout)) * 92
                    color: win.accent
                    Behavior on x { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
                }
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: [{ mode: "list", label: "List", icon: 0xEC14 }, { mode: "grid", label: "Grid", icon: 0xEDBA }]
                        delegate: Item {
                            id: layoutOpt
                            required property var modelData
                            readonly property bool on: Config.s.launcherLayout === modelData.mode
                            width: 92; height: 34
                            Rectangle {
                                anchors { fill: parent; margins: 3 }
                                radius: Config.corner(7)
                                color: win.accent
                                opacity: !layoutOpt.on && layoutHover.hovered ? Config.hoverStrength : 0
                            }
                            HoverHandler { id: layoutHover }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { anchors.verticalCenter: parent.verticalCenter; text: win.glyph(layoutOpt.modelData.icon); color: layoutOpt.on ? win.accentText : win.dim; font.family: win.bar.iconFont; font.pixelSize: 15 }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: layoutOpt.modelData.label; color: layoutOpt.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                            }
                            ClickTap { onTapped: Config.s.launcherLayout = layoutOpt.modelData.mode }
                        }
                    }
                }
            }
        }
        Separator { visible: Config.s.launcherLayout === "grid" }
        SettingRow {
            visible: Config.s.launcherLayout === "grid"
            label: "Columns"
            settingKey: "launcherColumns"
            detail: "Apps across the grid; the icons get smaller the more there are"
            ValueSlider { from: 3; to: 10; stepSize: 1; value: Config.s.launcherColumns; onMoved: v => Config.s.launcherColumns = Math.round(v) }
        }
        Separator { visible: Config.s.launcherLayout === "grid" }
        SettingRow {
            visible: Config.s.launcherLayout === "grid"
            label: "Rows"
            settingKey: "launcherRows"
            detail: "Rows shown at once, which sets the launcher's height (scroll for more)"
            ValueSlider { from: 2; to: 8; stepSize: 1; value: Config.s.launcherRows; onMoved: v => Config.s.launcherRows = Math.round(v) }
        }
        Separator {}
        SettingRow {
            label: "Show descriptions"
            settingKey: "launcherDescriptions"
            detail: Config.s.launcherLayout === "grid" ? "What the selected app is, under its name at the bottom" : "A short line under each app's name"
            SettingToggle { checked: Config.s.launcherDescriptions; onToggled: v => Config.s.launcherDescriptions = v }
        }
        Separator {}
        ToggleSetting {
            label: "Most used first"
            detail: "Order apps by how often you open them (after how well they match your search)"
            key: "launcherSortByUsage"
        }
        Separator {}
        ToggleSetting {
            label: "Wrap around"
            detail: "The arrow keys go from the last result back to the first, and from the first to the last"
            key: "launcherWrap"
        }
        Separator {}
        ToggleSetting {
            label: "Recent apps first"
            detail: "Before you type: the apps you opened most recently, at the top"
            key: "launcherRecent"
        }
    }
    GroupLabel { text: "What it finds" }
    Group {
        ToggleSetting {
            label: "Forgiving search"
            detail: "Initials and little typos still find your apps: gc for GNOME Calculator, fierfox for Firefox"
            key: "launcherFuzzy"
        }
        Separator {}
        ToggleSetting {
            label: "Open windows"
            detail: "Type part of a window's title to go to it, wherever it is"
            key: "launcherWindows"
        }
        Separator {}
        ToggleSetting {
            label: "App actions"
            detail: "What apps offer besides opening, like Firefox's New Private Window"
            key: "launcherActions"
        }
        Separator {}
        ToggleSetting {
            label: "Quick toggles"
            detail: "Wi-Fi, Bluetooth, Airplane Mode, Private Mode, Do Not Disturb, night light and game mode, switched from the results"
            key: "launcherToggles"
        }
        Separator {}
        ToggleSetting {
            label: "Files and folders"
            detail: "Files you opened recently, and folders in your home by name"
            key: "launcherFiles"
        }
        Separator {}
        ToggleSetting {
            label: "Conversions"
            detail: "Units and dates beside the calculator: 5 km in miles, 72 f to c, today + 30 days"
            key: "launcherConvert"
        }
        Separator {}
        ToggleSetting {
            label: "Run commands"
            detail: "Start with > to run a command, in a terminal or on its own"
            key: "launcherCommands"
        }
        Separator {}
        ToggleSetting {
            label: "Emoji"
            detail: "Start with : to find an emoji by name (:smile); Enter copies it"
            key: "launcherEmoji"
        }
        Separator {}
        ToggleSetting {
            label: "Search the web"
            detail: "A last result that searches the web for what you typed"
            key: "launcherWeb"
        }
        Separator { visible: Config.s.launcherWeb }
        DropdownSetting {
            visible: Config.s.launcherWeb
            label: "Search engine"
            settingKey: "launcherSearchEngine"
            options: [{ value: "duckduckgo", label: "DuckDuckGo" }, { value: "google", label: "Google" }, { value: "bing", label: "Bing" },
                      { value: "brave", label: "Brave Search" }, { value: "startpage", label: "Startpage" }, { value: "ecosia", label: "Ecosia" }]
            value: Config.s.launcherSearchEngine
            onPicked: v => Config.s.launcherSearchEngine = v
        }
    }
    // (only with glass on: Appearance → Glass)
    GroupLabel { visible: Config.s.glass; text: "Glass" }
    Group {
        visible: Config.s.glass
        ToggleSetting {
            label: "Blur"
            detail: "What's behind the launcher is blurred, like frosted glass. Off, you see straight through it"
            key: "launcherBlur"
        }
        Separator {}
        SettingRow {
            label: "Opacity"
            settingKey: "launcherOpacity"
            detail: "How solid its background is: 100% can't be seen through, lower is clearer"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.launcherGlassOpacity * 100); onMoved: v => Config.s.launcherOpacity = v / 100 }
        }
    }
}
