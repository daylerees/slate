import QtQuick
import Quickshell
import "../.."
import ".."

// ---- Startup apps: opened at each login (Config.atLogin) ---------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: startupPane
    spacing: 4
    PageTitle { text: "Startup Apps" }
    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
        .slice().sort((a, b) => a.name.localeCompare(b.name))
    GroupLabel { text: "At login" }
    Group {
        SettingRow {
            visible: (Config.s.startupApps || []).length === 0
            label: "Nothing opens at login just yet"
            detail: "Add your favorites below, and they'll be ready and waiting each time you log in"
        }
        Repeater {
            model: Config.s.startupApps || []
            delegate: Column {
                id: startRow
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: startRow.index > 0 }
                ListItemRow {
                    readonly property var entry: DesktopEntries.byId(startRow.modelData)
                    label: entry ? entry.name : startRow.modelData
                    detail: entry ? (entry.genericName || entry.comment || "") : "Not installed"
                    // Asks first, in Slate's confirmation window (by its id, not its
                    // place: the list may have changed by the time it's answered)
                    onRemoved: {
                        const id = startRow.modelData, name = entry ? entry.name : id;
                        win.ask = {
                            title: "Remove " + name + " from startup?",
                            body: name + " won't open by itself when you log in any more. The app itself stays installed, "
                                + "and you're welcome to add it back here at any time.",
                            button: "Remove", destructive: true,
                            run: () => Config.s.startupApps = (Config.s.startupApps || []).filter(a => a !== id)
                        };
                    }
                }
            }
        }
        Separator {}
        DropdownSetting {
            label: "Add an app"
            detail: "It opens each time you log in. Type to find it"
            searchable: true
            noneLabel: "Choose"
            value: ""
            options: startupPane.all.filter(e => !(Config.s.startupApps || []).includes(e.id))
                .map(e => ({ value: e.id, label: e.name, detail: e.genericName || e.comment || "", app: e.id }))
            onPicked: v => Config.s.startupApps = (Config.s.startupApps || []).concat([v])
        }
    }
    Footnote { text: "Apps started in ~/.config/slate/hypr/autostart.lua still open too." }
    // Your apps from last time (Config.reopenMode): kept as you log out, restart or shut down
    GroupLabel { text: "Your apps from last time" }
    Group {
        DropdownSetting {
            label: "Reopen your apps"
            settingKey: "reopenApps"
            detail: ({
                always: "As you log in, the apps you had open come back on the same workspaces, just where you left them",
                never: "Slate doesn't keep them, and every login starts fresh"
            })[Config.reopenMode] ?? "As you log in, Slate asks whether to bring back the apps you had open, on the same workspaces and just where you left them"
            options: [{ value: "ask", label: "Ask" }, { value: "always", label: "Always" }, { value: "never", label: "Never" }]
            value: Config.reopenMode
            // (and the old restart switch out of the way, or Ask and Always would still read as Never)
            onPicked: v => { Config.s.reopenAppsAfterRestart = true; Config.s.reopenApps = v; }
        }
    }
}
