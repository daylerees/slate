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

// ---- Shortcuts: Slate's keyboard shortcuts, as Hyprland has them (with descriptions) ----
Column {
    readonly property var win: SettingsHost.win
    id: shortcutsPane
    spacing: 4
    PageTitle { text: "Shortcuts" }
    property var binds: []
    Process {
        id: bindsProc
        running: true
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { shortcutsPane.binds = JSON.parse(text).filter(b => b.has_description && b.description && b.submap === ""); } catch (e) {} } }
    }
    // The keys, as caps: modifiers then the key
    function keysOf(b) {
        if (b.key === "SUPER_L") return ["Super"];
        const m = b.modmask, keys = [];
        if (m & 64) keys.push("Super");
        if (m & 4) keys.push("Ctrl");
        if (m & 8) keys.push("Alt");
        if (m & 1) keys.push("Shift");
        const names = { Return: "Enter", period: ".", grave: "`", Minus: "−", Plus: "+", Print: "Print Screen", Escape: "Esc",
                        Space: "Space", Tab: "Tab", Left: "←", Right: "→", Up: "↑", Down: "↓",
                        "mouse:272": "Drag", "mouse:273": "Right-drag", mouse_up: "Scroll up", mouse_down: "Scroll down" };
        let k = b.key || (b.keycode ? "code:" + b.keycode : "");
        const code = /^code:(\d+)$/.exec(k);
        if (code) k = String(+code[1] === 19 ? 0 : +code[1] - 9);
        else k = names[k] !== undefined ? names[k] : (k.length === 1 ? k.toUpperCase() : k);
        if (k) keys.push(k);
        return keys;
    }
    // A different set: read the shortcuts again once Hyprland has reloaded with it
    Connections {
        target: Config
        function onKeysetApplied() { bindsAgain.restart(); }
    }
    Timer { id: bindsAgain; interval: 500; onTriggered: { bindsProc.running = false; bindsProc.running = true; } }
    readonly property var order: ["Apps", "Slate", "Windows", "Workspaces", "Monitors"]
    // What's typed in the search box. The rows below are all built once, and a search
    // only shows or hides them: rebuilding about a hundred rows for every key typed was slow
    readonly property string query: findKeys.text.toLowerCase().trim()
    function matches(row) { return !query || row.hay.includes(query); }
    readonly property var groups: {
        const g = {};
        for (const b of binds) {
            const i = b.description.indexOf(": ");
            const group = i > 0 ? b.description.slice(0, i) : "Other";
            const text = i > 0 ? b.description.slice(i + 2) : b.description;
            const keys = keysOf(b);
            if (!g[group]) g[group] = [];
            if (!g[group].some(r => r.text === text && r.keys.join() === keys.join()))
                g[group].push({ text: text, keys: keys, hay: (text + " " + keys.join(" ")).toLowerCase() });
        }
        return Object.keys(g).sort((a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99)).map(k => ({ name: k, rows: g[k] }));
    }

    GroupLabel { text: "Shortcut set" }
    // Which set of shortcuts (binds.lua); changing it reloads Hyprland's config
    Group {
        DropdownSetting {
            label: "Shortcut set"
            settingKey: "keyset"
            options: [{ value: "slate", label: "Slate" },
                      { value: "hyprland", label: "Hyprland Defaults" },
                      { value: "hyprland-extras", label: "Hyprland + Slate Extras" }]
            value: Config.s.keyset
            onPicked: v => Config.setKeyset(v)
            detail: Config.s.keyset === "hyprland" ? "Hyprland's own default shortcuts (Super+Q terminal, Super+C close, Super+R launcher, Super+1–0 workspaces)"
                : Config.s.keyset === "hyprland-extras" ? "Hyprland's defaults, plus Slate's shortcuts where the keys are free (clipboard on Super+Shift+V, color picker on Super+Shift+P, overview on Super+Ctrl+Down)"
                : "Slate's own shortcuts (Super+Q close, Super+Space or tap Super for the launcher, Super+Tab to switch windows)"
        }
    }
    Item { width: 1; height: 6 }

    Rectangle {
        width: parent.width; height: 40; radius: Config.corner(10)
        color: win.card
        border.width: findKeys.activeFocus ? 1 : 0; border.color: win.accent
        Text {
            id: keysGlass
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: Config.glyph(0xEB1C); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
        }
        TextInput {
            activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
            id: findKeys
            anchors { left: keysGlass.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            color: win.text; font.family: win.font; font.pixelSize: Config.text(13); clip: true
            selectionColor: win.accent; selectedTextColor: win.accentText
            Text { visible: findKeys.text === ""; text: "Search shortcuts"; color: win.dim; font: findKeys.font; anchors.verticalCenter: parent.verticalCenter }
        }
    }
    Repeater {
        model: shortcutsPane.groups
        delegate: Column {
            id: keyGroup
            required property var modelData
            width: parent ? parent.width : 0
            spacing: 4
            // The first of its rows the search shows (-1: none, and the group hides)
            readonly property int firstShown: { shortcutsPane.query; return keyGroup.modelData.rows.findIndex(r => shortcutsPane.matches(r)); }
            visible: firstShown >= 0
            GroupLabel { textFormat: Text.PlainText; text: keyGroup.modelData.name }
            Group {
                Repeater {
                    model: keyGroup.modelData.rows
                    delegate: Column {
                        id: keyRow
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        visible: shortcutsPane.matches(keyRow.modelData)
                        Separator { visible: keyRow.index > keyGroup.firstShown }
                        SettingRow {
                            label: keyRow.modelData.text
                            Row {
                                spacing: 4
                                Repeater {
                                    model: keyRow.modelData.keys
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: Math.max(26, capText.implicitWidth + 14); height: 24; radius: Config.corner(6)
                                        color: win.divider
                                        border.width: 1; border.color: win.controlHoverSolid
                                        Text { id: capText; anchors.centerIn: parent; text: parent.modelData; color: win.text; font.family: win.font; font.pixelSize: Config.text(11); font.weight: Font.Medium }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Footnote { text: "Add or change shortcuts in ~/.config/slate/hypr/binds.lua (with a description = \"Group: what it does\" to list them here)." }
}
