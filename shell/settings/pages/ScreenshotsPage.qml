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

// ---- Screenshots (scripts/screenshot.sh reads these) ----------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: screenshotsPane
    spacing: 4
    PageTitle { text: "Screenshots" }
    property bool hasSwash: false
    Process { running: true; command: ["sh", "-c", "command -v swash"]; onExited: code => screenshotsPane.hasSwash = code === 0 }
    readonly property string home: Quickshell.env("HOME")
    readonly property string folder: Config.s.screenshotFolder || (home + "/Pictures/Screenshots")
    readonly property date example: Config.clockDate(new Date())
    GroupLabel { text: "Saving" }
    Group {
        DropdownSetting {
            label: "After taking one"
            settingKey: "screenshotAfter"
            detail: screenshotsPane.hasSwash ? "Every screenshot is saved to the folder below and copied. Marking one up and saving updates that file"
                : "Every screenshot is saved to the folder below and copied (swash, for marking up, isn't installed)"
            options: [{ value: "edit", label: "Open it to mark up" }, { value: "save", label: "Just show a notification" }]
            value: Config.s.screenshotAfter
            onPicked: v => Config.s.screenshotAfter = v
        }
        Separator {}
        DropdownSetting {
            label: "Save to"
            settingKey: "screenshotFolder"
            detail: screenshotsPane.folder.replace(screenshotsPane.home, "~")
            options: [{ value: "", label: "Pictures/Screenshots" }, { value: screenshotsPane.home + "/Pictures", label: "Pictures" },
                      { value: screenshotsPane.home + "/Desktop", label: "Desktop" }, { value: screenshotsPane.home + "/Downloads", label: "Downloads" }]
            value: Config.s.screenshotFolder
            onPicked: v => Config.s.screenshotFolder = v
        }
        Separator {}
        DropdownSetting {
            label: "File names"
            settingKey: "screenshotName"
            options: [{ value: "default", label: "Screenshot " + Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd HH.mm.ss") },
                      { value: "compact", label: Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd_HH-mm-ss") },
                      { value: "gnome", label: "Screenshot from " + Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd HH-mm-ss") }]
            value: Config.s.screenshotName
            onPicked: v => Config.s.screenshotName = v
        }
        Separator {}
        SettingRow {
            label: "Screenshot folder"
            Button {
                icon: 0xFAF7; label: "Open"
                onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && xdg-open \"$0\"", screenshotsPane.folder])
            }
        }
    }
    Footnote { text: "Print Screen takes an area (drag it out), Super+Print Screen the whole screen." }
}
