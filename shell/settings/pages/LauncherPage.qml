import QtQuick
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
            SegmentedChoice {
                options: [{ value: "list", label: "List", icon: 0xEC14 }, { value: "grid", label: "Grid", icon: 0xEDBA }]
                iconSize: 15
                value: Config.s.launcherLayout
                onPicked: v => Config.s.launcherLayout = v
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
