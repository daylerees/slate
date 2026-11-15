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

// ---- Default apps: what Slate's shortcuts open (and links and folders, for the browser
// and file manager) ----------------------------------------------------------------
Column {
    readonly property var win: SettingsHost.win
    id: defaultAppsPane
    spacing: 4
    PageTitle { text: "Default Apps" }
    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
        .slice().sort((a, b) => a.name.localeCompare(b.name))
    // Apps of a kind (by their categories), or every app if none say so
    function optionsFor(cats) {
        const fit = all.filter(e => (e.categories || []).some(c => cats.includes(c)));
        return (fit.length > 0 ? fit : all).map(e => ({ value: e.id, label: e.name }));
    }
    function nameOf(id) { const e = id ? DesktopEntries.byId(id) : null; return e ? e.name : ""; }
    // (each a dropdown with a search box, as Settings' other long lists are)
    GroupLabel { text: "Apps" }
    Group {
        DropdownSetting {
            label: "Terminal"
            detail: "Super+Enter"
            settingKey: "defaultTerminal"
            searchable: true
            noneLabel: "Slate's own choice"
            value: Config.s.defaultTerminal
            options: defaultAppsPane.optionsFor(["TerminalEmulator"])
            onPicked: v => Config.s.defaultTerminal = v
        }
        Separator {}
        DropdownSetting {
            label: "Web browser"
            detail: "Links open in it"
            settingKey: "defaultBrowser"
            searchable: true
            noneLabel: "Slate's own choice"
            value: Config.s.defaultBrowser
            options: defaultAppsPane.optionsFor(["WebBrowser"])
            onPicked: v => {
                Config.s.defaultBrowser = v;
                Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", v + ".desktop"]);
            }
        }
        Separator {}
        DropdownSetting {
            label: "Files"
            detail: "Super+E, and folders open in it"
            settingKey: "defaultFileManager"
            searchable: true
            noneLabel: "Slate's own choice"
            value: Config.s.defaultFileManager
            options: defaultAppsPane.optionsFor(["FileManager"])
            onPicked: v => {
                Config.s.defaultFileManager = v;
                Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "inode/directory"]);
            }
        }
        Separator {}
        DropdownSetting {
            label: "Text editor"
            detail: "Super+T, and text files open in it"
            settingKey: "defaultEditor"
            searchable: true
            noneLabel: "Slate's own choice"
            value: Config.s.defaultEditor
            options: defaultAppsPane.optionsFor(["TextEditor"])
            onPicked: v => {
                Config.s.defaultEditor = v;
                Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "text/plain"]);
            }
        }
        Separator {}
        DropdownSetting {
            label: "Calculator"
            detail: "Super+C and the calculator key"
            settingKey: "defaultCalculator"
            searchable: true
            noneLabel: "Slate's own choice"
            value: Config.s.defaultCalculator
            options: defaultAppsPane.optionsFor(["Calculator"])
            onPicked: v => Config.s.defaultCalculator = v
        }
    }
    Footnote { text: "Ones not chosen here use those in ~/.config/slate/hypr/variables.lua (or Slate's own defaults)." }
}
