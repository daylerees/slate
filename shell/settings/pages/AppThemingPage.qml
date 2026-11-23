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
    PageTitle { text: "App Theming" }
    IntroText { text: "Apps you switch on follow Slate's colors, light or dark, and the accent (even one picked from the wallpaper). Slate backs up a config before changing it, and switching an app off puts it back." }
    GroupLabel { text: "Refresh" }
    Group {
        SettingRow {
            id: themeRefresh
            label: "Refresh themes"
            detail: "Puts the themes of the apps you've switched on back in place, if an app update or reset has overwritten one"
            property bool asked: false       // Refresh was clicked (shows Done when it finishes)
            property bool done: false
            Connections {
                target: Config
                function onThemesBusyChanged() {
                    if (!Config.themesBusy && themeRefresh.asked) { themeRefresh.asked = false; themeRefresh.done = true; doneTimer.restart(); }
                }
            }
            Timer { id: doneTimer; interval: 2500; onTriggered: themeRefresh.done = false }
            Button {
                icon: themeRefresh.done ? 0xEA5E : 0xEB13
                label: Config.themesBusy && themeRefresh.asked ? "Refreshing…" : themeRefresh.done ? "Done" : "Refresh"
                onClicked: { if (Config.themesBusy) return; themeRefresh.done = false; themeRefresh.asked = true; Config.refreshThemes(); }
            }
        }
    }
    GroupLabel { text: "Apps" }
    Group {
        id: appTheming
        // What scripts/apply-theme.py can theme, and which are installed: [{id, label, detail,
        // installed, about, url, packages}] (scripts/slate_apps.py)
        // (what search already read as Slate started, SettingsIndex.themeApps; asked again only
        // when it hasn't anything yet, or when you come back to Settings, below)
        property var apps: SettingsIndex.themeApps
        Process {
            id: appsQuery
            Component.onCompleted: if (SettingsIndex.themeApps.length === 0) running = true
            command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--apps"]
            stdout: StdioCollector { onStreamFinished: { try { appTheming.apps = JSON.parse(text); } catch (e) {} } }
        }
        // Asked again whenever you come back to Settings: an app installed meanwhile (from
        // Software, say) shows as installed without leaving the page and coming back
        function recheck() { appsQuery.running = false; appsQuery.running = true; }
        Connections {
            target: Hyprland
            function onActiveToplevelChanged() { if (win && win.isFocused()) appTheming.recheck(); }
        }
        // Installing one (its Install button, after asking): from the distro's own repositories,
        // with your password (bin/slate-system --install); a notification says how it went
        property string installing: ""          // the app's id, while it installs
        function install(app) {
            const go = () => {
                appTheming.installing = app.id;
                installer.app = app;
                installer.command = [Quickshell.shellPath("bin/slate-system"), "--install"].concat(app.packages.split(" "));
                installer.running = true;
            };
            const q = {
                title: "Install " + app.label + "?",
                body: app.about + ". Slate installs " + app.packages.split(" ").join(", ")
                    + " from your distribution's software, which asks for your password. Once it's in, you can switch on its theme right here.",
                button: "Install"
            };
            // (in Slate's confirmation window, like shutting down or emptying the waste basket)
            win.askQuestion(Object.assign({ run: go, code: 0xEA96 }, q));
        }
        Process {
            id: installer
            property var app: null
            stderr: StdioCollector { id: installErr }
            onExited: code => {
                const a = installer.app;
                appTheming.installing = "";
                appsQuery.running = false; appsQuery.running = true;         // installed now?
                if (!a) return;
                // 126/127: the password prompt was closed or failed, so it didn't start
                if (code === 126 || code === 127) return;
                const err = (installErr.text || "").trim().split("\n").filter(l => l.trim() !== "").pop() || "";
                // (Config.notify puts "--" first: the package manager's last line is the text, even
                // if it starts with a dash)
                Quickshell.execDetached(Config.notify(code === 0 ? a.label + " is installed" : "Slate couldn't install " + a.label,
                    code === 0 ? "Switch on its theme in Settings → App Theming." : (err || "The package manager stopped with an error."),
                    { page: "apptheming" }));
            }
        }
        function isOn(id) { return (Config.s.themedApps || []).indexOf(id) >= 0; }
        function setOn(id, on) {
            const list = (Config.s.themedApps || []).filter(x => x !== id);
            if (on) list.push(id);
            Config.s.themedApps = list;
        }
        Repeater {
            model: appTheming.apps
            delegate: Column {
                id: appRow
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: appRow.index > 0 }
                SettingRow {
                    id: appSetting
                    readonly property var app: appRow.modelData
                    readonly property bool usable: app.installed || appTheming.isOn(app.id)
                    // Its app, to open (the first of its desktop entries that's installed)
                    readonly property var entry: {
                        DesktopEntries.applications.values;         // (again as apps come and go)
                        for (const id of (app.desktop || [])) { const e = DesktopEntries.byId(id); if (e) return e; }
                        return null;
                    }
                    label: app.label
                    // What it is, then what Slate does to it
                    detail: (app.about ? app.about + ". " : "") + app.detail
                    // Under the description: its website, and Install when it isn't installed
                    below: [
                        Button {
                            visible: !!appSetting.app.url
                            icon: 0xEA99; label: "Website"
                            onClicked: Qt.openUrlExternally(appSetting.app.url)
                        },
                        // Installed: open it (as the launcher does)
                        Button {
                            visible: appSetting.app.installed && !!appSetting.entry
                            primary: true
                            icon: 0xEFE6          // app window
                            label: "Open"
                            onClicked: if (appSetting.entry) appSetting.entry.execute()
                        },
                        // Not installed: install it from the distro's software, where it's there
                        Button {
                            readonly property var app: appSetting.app
                            visible: !app.installed && !appTheming.isOn(app.id) && app.packages !== ""
                            primary: true
                            icon: 0xEA96
                            label: appTheming.installing === app.id ? "Installing…" : "Install"
                            opacity: appTheming.installing !== "" && appTheming.installing !== app.id ? 0.5 : 1
                            onClicked: if (appTheming.installing === "") appTheming.install(app)
                        }
                    ]
                    // The switch, kept where it sat above the chip (the chip's room left under it)
                    Column {
                        spacing: 8
                        SettingToggle {
                            visible: appSetting.usable
                            checked: appTheming.isOn(appSetting.app.id)
                            onToggled: v => appTheming.setOn(appSetting.app.id, v)
                        }
                        Item { visible: appSetting.usable; width: 1; height: 24 }
                    }
                    // On the right, level with the buttons: whether it's installed
                    belowRight: [
                        Rectangle {
                            readonly property bool on: appSetting.app.installed
                            // Installed: Slate's pastel green when colourful (as Power's), else the accent
                            readonly property color tone: Config.colourful ? Config.tint("#a6d3a0") : win.accent
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: chipRow.implicitWidth + 18; height: 24; radius: Config.corner(12)
                            color: on ? Qt.rgba(tone.r, tone.g, tone.b, 0.16) : win.control
                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    visible: parent.parent.on
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Config.glyph(0xEA5E)          // tick
                                    color: parent.parent.tone; font.family: win.bar.iconFont; font.pixelSize: 13
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.on ? "Installed" : "Not installed"
                                    color: parent.parent.on ? parent.parent.tone : win.dim
                                    font.family: win.font; font.pixelSize: Config.text(11); font.weight: Font.Medium
                                }
                            }
                        }
                    ]
                }
            }
        }
    }
}
