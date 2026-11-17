import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// Settings → Storage: each drive and how full it is, what's using your space by kind, your
// biggest folders, and gentle ways to free some (scripts/storage.py). The kinds take a while to
// measure: the last measurement shows at once, and a fresh one replaces it when it's done.
Column {
    id: storagePage
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Storage" }
    IntroText { text: "How full your drives are, and what's using the space. Freeing some never touches your own files without asking." }

    property var drives: []
    property bool drivesRead: false
    property var measured: ({})
    property bool measuring: false
    readonly property string script: Quickshell.shellPath("scripts/storage.py")
    Process {
        running: true
        command: ["python3", storagePage.script, "drives"]
        stdout: StdioCollector { onStreamFinished: { try { storagePage.drives = JSON.parse(text); } catch (e) {} storagePage.drivesRead = true; } }
    }
    Process {
        running: true
        command: ["python3", storagePage.script, "cached"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (d.kinds && !storagePage.measured.kinds) storagePage.measured = d; } catch (e) {} } }
    }
    Process {
        id: measure
        running: true
        command: ["python3", storagePage.script, "kinds"]
        onRunningChanged: storagePage.measuring = running
        stdout: StdioCollector { onStreamFinished: { try { storagePage.measured = JSON.parse(text); } catch (e) {} } }
    }
    function again() { measure.running = false; measure.running = true; }
    Process {
        id: clearing
        command: ["python3", storagePage.script, "clear-caches"]
        stdout: StdioCollector { onStreamFinished: storagePage.again() }
    }

    GroupLabel { text: "Drives" }
    Group {
        Repeater {
            model: storagePage.drives
            delegate: Column {
                id: driveRow
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: driveRow.index > 0 }
                SettingRow {
                    label: driveRow.modelData.name
                    detail: Config.bytesText(driveRow.modelData.free) + " free of " + Config.bytesText(driveRow.modelData.size)
                        + (driveRow.modelData.name !== driveRow.modelData.mount ? " · " + driveRow.modelData.mount : "")
                    Meter {
                        width: 180
                        value: driveRow.modelData.used / driveRow.modelData.size
                        colour: driveRow.modelData.free < Math.max(5e9, driveRow.modelData.size * 0.1) ? Config.tint("#f28b8b") : win.accent
                        trackColour: win.control
                    }
                }
            }
        }
        SettingRow {
            visible: storagePage.drives.length === 0
            label: storagePage.drivesRead ? "Slate couldn't find any drives to measure" : "Looking at your drives…"
        }
    }

    GroupLabel { text: "What's using your space" }
    // (by the page, not `parent`: a row's parent is the group's own column, not the group)
    readonly property var kinds: measured.kinds || ({})
    readonly property real most: Math.max(1, ...Object.values(kinds))
    Group {
        Repeater {
            model: [{ id: "apps", label: "Apps", detail: "Installed apps and the system" },
                    { id: "documents", label: "Documents" }, { id: "downloads", label: "Downloads" },
                    { id: "pictures", label: "Pictures" }, { id: "videos", label: "Videos" }, { id: "music", label: "Music" },
                    { id: "caches", label: "Caches", detail: "Apps' temporary files: they're made again when needed" },
                    { id: "trash", label: "Waste Basket" },
                    { id: "other", label: "Everything else in your home folder", detail: "Settings, app data and other files" }]
            delegate: Column {
                id: kindRow
                required property var modelData
                required property int index
                readonly property real bytes: storagePage.kinds[modelData.id] || 0
                width: parent ? parent.width : 0
                Separator { visible: kindRow.index > 0 }
                SettingRow {
                    label: kindRow.modelData.label
                    detail: (storagePage.measured.kinds ? Config.bytesText(kindRow.bytes) : "Measuring…") + (kindRow.modelData.detail ? " · " + kindRow.modelData.detail : "")
                    Meter {
                        width: 180
                        value: kindRow.bytes / storagePage.most
                        colour: win.accent
                        trackColour: win.control
                    }
                }
            }
        }
    }
    Footnote {
        text: storagePage.measuring ? "Measuring again… this can take a minute."
            : storagePage.measured.at ? "Measured " + Config.ago(storagePage.measured.at * 1000, true).toLowerCase() + "." : ""
    }

    GroupLabel { text: "Free up space" }
    Group {
        SettingRow {
            label: "Empty the Waste Basket"
            detail: storagePage.measured.kinds ? Config.bytesText(storagePage.measured.kinds.trash || 0) + " in it" : ""
            Button {
                label: "Empty"; icon: 0xEB41; destructive: true
                onClicked: win.confirmer.confirmWith({
                    title: "Empty the waste basket?",
                    body: "Everything in it will be deleted for good. Just so you know, this can't be undone.",
                    button: "Empty", code: 0xEB41, danger: true
                }, () => { Quickshell.execDetached(["gio", "trash", "--empty"]); emptied.restart(); })
                Timer { id: emptied; interval: 1500; onTriggered: storagePage.again() }
            }
        }
        Separator {}
        SettingRow {
            label: "Clear old caches"
            detail: "Thumbnails, and apps' temporary files nothing has used for a month. Apps make them again when they need them"
            Button {
                label: "Clear"; icon: 0xEB41; destructive: true
                onClicked: win.confirmer.confirmWith({
                    title: "Clear old caches?",
                    body: "Thumbnails and temporary files apps haven't used for a month will be deleted. Your own files stay as they are, and apps make what they need again.",
                    button: "Clear", code: 0xEB41, danger: true
                }, () => { clearing.running = false; clearing.running = true; })
            }
        }
    }

    GroupLabel { text: "Your biggest folders" }
    Group {
        Repeater {
            model: storagePage.measured.biggest || []
            delegate: Column {
                id: bigRow
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: bigRow.index > 0 }
                SettingRow {
                    label: bigRow.modelData.name
                    detail: Config.bytesText(bigRow.modelData.size) + (bigRow.modelData.name.startsWith(".") ? " · a hidden folder, kept by apps" : "")
                    Button {
                        label: "Open"; icon: 0xEAAD
                        // (an absolute path, from storage.py: never taken for an option. No "--": xdg-open
                        // would open a file called that)
                        onClicked: Quickshell.execDetached(["xdg-open", bigRow.modelData.path])
                    }
                }
            }
        }
        SettingRow { visible: !(storagePage.measured.biggest || []).length; label: storagePage.measuring ? "Measuring…" : "Nothing measured yet" }
    }

    GroupLabel { text: "Warnings" }
    Group {
        ToggleSetting {
            label: "Warn when a drive is nearly full"
            detail: "A calm notification once a drive has less than a tenth of its space (or 5 GB) left. Once each time"
            key: "storageWarning"
        }
    }
}
