import QtQuick
import Quickshell
import "../.."
import ".."

// ---- Screenshots (scripts/screenshot.sh reads these) ----------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: screenshotsPane
    spacing: 4
    PageTitle { text: "Screenshots" }
    // (SettingsLookups.qml: looked for once, kept for the next time the page opens)
    readonly property bool hasSwash: SettingsLookups.hasSwash
    readonly property bool hasRecorder: SettingsLookups.hasRecorder
    Component.onCompleted: SettingsLookups.wantTools()
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
    // Screen recordings (scripts/record.sh reads it): saved in the same folder
    GroupLabel { text: "Recording" }
    Group {
        ToggleSetting {
            label: "Computer sound"
            detail: screenshotsPane.hasRecorder ? "What's playing goes into recordings. Recordings are saved in the screenshot folder; start one from the menu bar's Screenshot button, or with Super+Shift+Print Screen"
                : "Needs wf-recorder to record the screen (the wf-recorder package)"
            key: "recordComputerSound"
        }
        Separator {}
        ToggleSetting {
            label: "Microphone"
            detail: "What your microphone hears goes into recordings, mixed with the computer's sound when both are on"
            key: "recordMicrophone"
        }
    }
    Footnote { text: "Print Screen takes an area (drag it out), Super+Print Screen the whole screen. Super+Shift+Print Screen records an area, and stops the recording." }
}
