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
            + "Spaces, the dock's pinned apps, your own Hyprland tweaks and QML, and your wallpaper."
        leftPadding: 0; bottomPadding: 8
    }

    // ---- Export ----------------------------------------------------------------------------
    GroupLabel { text: "Export" }
    Group {
        ExportRow {
            id: exportRow
            label: "Export your settings"
            about: "Saves them to a file in your Documents folder. It holds your own files too, so keep it somewhere private"
            command: [transferPane.script, "export"]
            icon: 0xEB47
            savedText: f => "Saved to " + f.replace(transferPane.home, "~")
            failText: why => why !== "" ? why : "Slate couldn't save your settings. Check there's some free space, then try again"
            onFinished: files.look()
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
    function dateOf(s) { return s ? Config.dateText(new Date(s * 1000), "full") : ""; }
    function whatsIn(has) {
        const words = { settings: "settings", spaces: "Spaces", dock: "dock pins", hypr: "Hyprland tweaks", user: "your QML", wallpaper: "wallpaper" };
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
                    enabled: fileRow.modelData.ok && !transferPane.importing
                    onClicked: transferPane.askImport(fileRow.modelData)
                }
            }
        }
    }
    function askImport(f) {
        win.askQuestion({
            title: "Import these settings?",
            body: "Your settings, saved Spaces, dock pins, own Hyprland tweaks and QML, and wallpaper are replaced with the "
                + "ones in “" + f.name + "”. Slate restarts to use them; your apps and windows stay open. Yours now "
                + "are kept, and you can put them back here.\n\nA settings file can change which apps open things, how "
                + "your screen locks and what your keys do, and your own files can hold code that runs as part of your "
                + "desktop. Only import a file you made or trust.",
            button: "Import",
            run: () => {
                transferPane.importing = true;
                // (in its own session: it restarts Slate, Settings with it, and says how it went)
                Quickshell.execDetached(["setsid", "-f", transferPane.script, "import", f.path]);
            }
        });
    }
    // An import on its way: the buttons rest until Slate restarts (it says how it went then, or
    // straight away when the file's refused, and Settings opens afresh either way)
    property bool importing: false
    Timer { running: transferPane.importing; interval: 8000; onTriggered: transferPane.importing = false }

    // ---- Undo --------------------------------------------------------------------------------
    QtObject { id: lastImport; property var info: ({}) }
    FirstLook {
        running: true
        command: [transferPane.script, "last"]
        stdout: StdioCollector { onStreamFinished: { try { lastImport.info = JSON.parse(text); } catch (e) { lastImport.info = {}; } } }
    }
    GroupLabel { text: "Undo" }
    Group {
        SettingRow {
            label: "Put back your settings from before"
            detail: lastImport.info.backup
                ? "Everything your last import replaced, on " + transferPane.dateOf(lastImport.info.when) + ", comes back as it was"
                : "Nothing to put back. After an import, the settings you had before can be put back from here"
            Button {
                visible: !!lastImport.info.backup
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
    Footnote { text: "Copies of what an import replaces are kept in ~/.local/share/slate/backups. Workspace names last only until you log out, and hidden files in your own folders (like a .git folder) stay out, so they aren't saved." }
}
