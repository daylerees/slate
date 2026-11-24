import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// Import & Export: your Slate settings in one file, to keep or to take to another computer
// (scripts/settings-transfer.py does the work)
Column {
    id: transferPane
    readonly property var win: SettingsHost.win
    readonly property string script: Quickshell.shellPath("scripts/settings-transfer.py")
    readonly property string home: Quickshell.env("HOME")
    spacing: 4
    PageTitle { text: "Import & Export" }
    IntroText {
        text: "Keep your Slate settings in one file, or take them to another computer: every setting, your saved "
            + "Spaces, your own Hyprland tweaks and QML, and your wallpaper."
        leftPadding: 0; bottomPadding: 8
    }

    // ---- Export ----------------------------------------------------------------------------
    GroupLabel { text: "Export" }
    Group {
        SettingRow {
            id: exportRow
            property string saved: ""          // the file, once made
            property string status: ""
            label: "Export your settings"
            detail: status !== "" ? status
                : "Saves them to a file in your Documents folder. It holds your own files too, so keep it somewhere private"
            Process {
                id: exportRun
                command: [transferPane.script, "export"]
                stdout: StdioCollector { onStreamFinished: exportRow.saved = text.trim() }
                onExited: code => {
                    exportRow.status = code === 0 && exportRow.saved !== ""
                        ? "Saved to " + exportRow.saved.replace(transferPane.home, "~")
                        : "Slate couldn't save your settings. Check there's some free space, then try again";
                    files.look();
                }
            }
            Row {
                spacing: 8
                Button { visible: exportRow.saved !== ""; label: "Show"; onClicked: Quickshell.execDetached(["xdg-open", exportRow.saved.substring(0, exportRow.saved.lastIndexOf("/"))]) }
                Button { icon: 0xEB47; label: "Export"; enabled: !exportRun.running; onClicked: { exportRow.saved = ""; exportRow.status = "Saving…"; exportRun.running = true; } }
            }
        }
    }

    // ---- Import ----------------------------------------------------------------------------
    GroupLabel { text: "Import" }
    // The settings files in Downloads, Documents, the Desktop and your home folder, newest first
    QtObject {
        id: files
        property var list: []
        property bool looked: false
        function look() { listRun.running = false; listRun.running = true; }
    }
    // (FirstLook: counted while it runs, so the tests picture the page once the list is there)
    FirstLook {
        id: listRun
        running: true
        command: [transferPane.script, "list"]
        stdout: StdioCollector { onStreamFinished: { try { files.list = JSON.parse(text); } catch (e) { files.list = []; } files.looked = true;
                                                     transferPane.win.transferFiles = files.list.map(f => f.name + (f.ok ? "" : " (unreadable)")); } }
    }
    // Looked at again whenever you come back to this page (a file downloaded meanwhile)
    Connections { target: transferPane.win; function onVisibleChanged() { if (transferPane.win.visible) files.look(); } }
    function dateOf(s) { return s ? Config.dateText(new Date(s * 1000), "full") : ""; }
    function whatsIn(has) {
        const words = { settings: "settings", spaces: "Spaces", hypr: "Hyprland tweaks", user: "your QML", wallpaper: "wallpaper" };
        return Config.listText((has || []).map(h => words[h]).filter(w => !!w));
    }
    Group {
        SettingRow {
            visible: files.looked && files.list.length === 0
            label: "No settings files yet"
            detail: "Put a file exported from Slate (it ends in .slate-settings) in your Downloads or Documents folder and it'll show up here"
            Button { label: "Look again"; onClicked: files.look() }
        }
        Repeater {
            model: files.list
            delegate: SettingRow {
                id: fileRow
                required property var modelData
                required property int index
                label: modelData.name
                detail: !modelData.ok ? modelData.why
                    : "In " + modelData.folder + (modelData.made ? " · made " + transferPane.dateOf(modelData.made) : "")
                      + " · " + transferPane.whatsIn(modelData.has)
                Button {
                    icon: 0xEA96
                    label: "Import…"
                    enabled: fileRow.modelData.ok && !importRun.running
                    onClicked: transferPane.askImport(fileRow.modelData)
                }
            }
        }
    }
    function askImport(f) {
        win.askQuestion({
            title: "Import these settings?",
            body: "Your settings, saved Spaces, own Hyprland tweaks and QML, and wallpaper are replaced with the ones in "
                + "“" + f.name + "”. Slate restarts to use them; your apps and windows stay open. Yours now are kept, "
                + "and you can put them back here.\n\nYour own files can hold code that runs as part of your desktop, so "
                + "only import a file you made or trust.",
            button: "Import",
            run: () => { importRun.command = ["setsid", "-f", transferPane.script, "import", f.path]; importRun.running = true; }
        });
    }
    // (in its own session: it restarts Slate, Settings with it, and says how it went)
    Process { id: importRun }

    // ---- Undo --------------------------------------------------------------------------------
    QtObject { id: lastImport; property var info: ({}) }
    FirstLook {
        running: true
        command: [transferPane.script, "last"]
        stdout: StdioCollector { onStreamFinished: { try { lastImport.info = JSON.parse(text); } catch (e) { lastImport.info = {}; } } }
    }
    GroupLabel { visible: !!lastImport.info.backup; text: "Before your last import" }
    Group {
        visible: !!lastImport.info.backup
        SettingRow {
            label: "Put back your settings from before"
            detail: "Everything the import replaced on " + transferPane.dateOf(lastImport.info.when) + " comes back, as it was"
            Button {
                label: "Undo import…"
                onClicked: win.askQuestion({
                    title: "Put back your settings from before?",
                    body: "Slate goes back to the settings, Spaces, own files and wallpaper you had before your last import, "
                        + "and restarts to use them. Your apps and windows stay open.",
                    button: "Put back",
                    run: () => Quickshell.execDetached(["setsid", "-f", transferPane.script, "undo"])
                })
            }
        }
    }
    Footnote { text: "Copies of what an import replaces are kept in ~/.local/share/slate/backups. Workspace names last only until you log out, so they aren't saved." }
}
