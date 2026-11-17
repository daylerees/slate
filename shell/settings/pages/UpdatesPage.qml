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
import "../../NotificationText.js" as NotificationText
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: updatesPane
    spacing: 4
    readonly property var mod: Updates.modified
    readonly property var touched: mod && mod.known ? mod.changed.concat(mod.added) : []
    readonly property string latest: Updates.latest
    function when(iso) { return iso ? Config.dateText(new Date(iso), "full") : ""; }
    function ago(ms) {
        const m = Math.max(0, Math.round((Date.now() - ms) / 60000));
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Config.dateText(new Date(ms), "day");
    }
    // "v0.4.2-15-gabc123" (a copy of the code past a release) reads as "v0.4.2 + 15 changes"
    function nice(v) {
        const m = /^(v[\d.]+)-(\d+)-g/.exec(v || "");
        return m ? m[1] + " + " + m[2] + " changes" : v;
    }
    Component.onCompleted: { Updates.check(false); Updates.findModified(); }

    PageTitle { text: "Updates" }
    IntroText {
        text: Updates.how === "packaged"
            ? "Slate came with your system's packages, so it updates with the rest of your system. Slate still lets you know when there's a new version."
            : "Slate looks for a new version once a day and lets you know with a notification. Updating keeps your settings and your own tweaks (settings.json, hypr/ and user/ in ~/.config/slate), and keeps the version you had, so you can go back to it."
              + (Updates.how === "shared" ? " Slate is installed for everyone on this computer, so updating asks for an administrator's password." : "")
    }
    GroupLabel { text: "Version" }
    Group {
        SettingRow {
            label: "Installed version"
            detail: Updates.installed === "" ? "Unknown: this copy of Slate wasn't installed with a version"
                : updatesPane.nice(Updates.installed)
        }
        Separator {}
        SettingRow {
            label: Updates.available ? "Slate " + updatesPane.latest + " is available" : "Latest version"
            detail: Updates.checking ? "Checking…"
                : Updates.error !== "" && Updates.status !== "failed" ? Updates.error
                : updatesPane.latest === "" ? "Not checked yet"
                : (Updates.available ? "Released " + updatesPane.when(Updates.state.published) : updatesPane.latest + ": you're up to date")
                  + (Updates.checkedAt > 0 ? " · checked " + updatesPane.ago(Updates.checkedAt) : "")
            Button { label: Updates.checking ? "Checking…" : "Check now"; icon: 0xEB13; onClicked: Updates.check(true) }
        }
        Separator {}
        ToggleSetting {
            label: "Check for updates"
            detail: "Once a day, and Slate lets you know when there's a new version"
            key: "updateCheck"
        }
    }

    // ---- Apps and the system (Software): what's waiting, and the daily notification ----
    GroupLabel { text: "Apps and this computer's system" }
    Group {
        SettingRow {
            label: SoftwareUpdates.waiting === 0 ? "Apps and system updates" : SoftwareUpdates.words() + " waiting"
            detail: (SoftwareUpdates.checkedAt === 0 ? "Not checked yet" : SoftwareUpdates.waiting === 0 ? "You're up to date" : "Ready to install in Software")
                + (SoftwareUpdates.checkedAt > 0 ? " · checked " + updatesPane.ago(SoftwareUpdates.checkedAt) : "")
            Button { label: "Open Software"; icon: 0xEA96; onClicked: Config.slateCall("software", "page", "updates") }
        }
        Separator {}
        ToggleSetting {
            label: "Tell me about app and system updates"
            detail: "Once a day, a notification when updates are waiting for your apps or this computer's system (never in game mode or on a metered connection)"
            key: "softwareUpdateCheck"
        }
    }

    // ---- A new version: what's new, and updating ----
    GroupLabel {
        visible: Updates.available || Updates.busy || Updates.status === "failed"
        text: "What's new in " + updatesPane.latest
    }
    Group {
        visible: Updates.available || Updates.busy || Updates.status === "failed"
        Text {
            x: 16; width: parent.width - 32
            visible: Updates.notes !== ""
            topPadding: 12; bottomPadding: 8
            // (from the network: pictures and links to anything but the web are taken out first)
            text: NotificationText.safeMarkdown(Updates.notes)
            textFormat: Text.MarkdownText
            color: win.text; linkColor: win.accent
            font.family: win.font; font.pixelSize: Config.text(13)
            wrapMode: Text.Wrap
            onLinkActivated: link => { if (NotificationText.openable(link)) Qt.openUrlExternally(link); }
        }
        Separator { visible: Updates.notes !== "" }
        // Slate's own files changed by hand: an update replaces them (the old copy is kept)
        Text {
            x: 16; width: parent.width - 32
            visible: updatesPane.touched.length > 0 && !Updates.busy
            topPadding: 12; bottomPadding: 4
            text: "You've changed some of Slate's own files, outside settings.json, hypr/ and user/. Updating replaces them; your versions stay in " + Updates.kept + ":\n"
                + updatesPane.touched.slice(0, 8).map(f => "  · " + f).join("\n")
                + (updatesPane.touched.length > 8 ? "\n  · and " + (updatesPane.touched.length - 8) + " more" : "")
            color: win.danger; font.family: win.font; font.pixelSize: Config.text(12)
            wrapMode: Text.Wrap
        }
        SettingRow {
            label: Updates.status === "downloading" ? "Downloading " + updatesPane.latest + "…"
                : Updates.status === "installing" ? "Installing " + updatesPane.latest + "…"
                : Updates.status === "failed" ? "The update didn't finish"
                : "Update to " + updatesPane.latest
            detail: Updates.status === "installing" ? "Slate restarts on the new version when it's done"
                : Updates.status === "failed" ? Updates.error
                : Updates.how === "packaged" ? "Your system's own updates bring it"
                : Updates.how === "shared" ? "Asks for an administrator's password, then Slate restarts on the new version"
                : "Takes a moment; Slate restarts on the new version"
            Row {
                spacing: 8
                Button { visible: Updates.url !== ""; label: "Release page"; icon: 0xEA99; onClicked: Qt.openUrlExternally(Updates.url) }
                Button {
                    visible: Updates.status === "failed" && Updates.state.log !== undefined
                    label: "Show log"
                    onClicked: Quickshell.execDetached(["xdg-open", Updates.state.log])
                }
                Button {
                    visible: !Updates.busy && Updates.how !== "packaged"
                    primary: true
                    icon: 0xEA96
                    label: Updates.status === "failed" ? "Try again" : "Update now"
                    onClicked: {
                        // Over files you've changed, ask first (in Slate's confirmation window)
                        if (updatesPane.touched.length === 0) { Updates.install(); return; }
                        win.ask = {
                            title: "Update over your changes?",
                            body: "You've changed some of Slate's own files. Updating replaces them, and your versions stay in "
                                + Updates.kept + ". Your settings.json, hypr/ and user/ aren't touched.",
                            button: "Update anyway", code: 0xEA96,
                            run: () => Updates.install()
                        };
                    }
                }
            }
        }
    }

    GroupLabel { visible: Updates.status === "done" || Updates.status === "reverted"; text: "Latest change" }
    // ---- Just updated, or went back ----
    Group {
        visible: Updates.status === "done" || Updates.status === "reverted"
        SettingRow {
            label: Updates.status === "done" ? "Updated to " + updatesPane.nice(Updates.installed) : "Back on " + updatesPane.nice(Updates.installed)
            detail: Updates.status === "done" ? (Updates.note !== "" ? Updates.note : "Your settings and tweaks came along. The version before is kept, below")
                : "Your settings and tweaks stayed as they were. The version you left is kept, below"
            Button { visible: Updates.status === "done" && Updates.url !== ""; label: "What's new"; icon: 0xEA99; onClicked: Qt.openUrlExternally(Updates.url) }
        }
    }

    // ---- The version kept as a backup ----
    GroupLabel { visible: Updates.previous !== ""; text: "Previous version" }
    Group {
        visible: Updates.previous !== ""
        SettingRow {
            label: "Go back to " + (Updates.previous === "unknown" ? "the previous version" : updatesPane.nice(Updates.previous))
            detail: "Kept in " + Updates.kept + ". Your settings and tweaks stay as they are now, and the version you leave is kept instead, so you can switch back"
                + (Updates.how === "shared" ? ". Asks for an administrator's password" : "")
            Button {
                enabled: !Updates.busy
                label: "Go back"
                onClicked: win.ask = {
                    title: "Go back to " + (Updates.previous === "unknown" ? "the previous version" : updatesPane.nice(Updates.previous)) + "?",
                    body: "Slate switches to the version kept in " + Updates.kept + " and restarts. Your settings and tweaks "
                        + "stay as they are now, and the version you leave is kept instead, so you can switch back."
                        + (Updates.how === "shared" ? " It asks for an administrator's password." : ""),
                    button: "Go back", code: 0xEA60,
                    run: () => Updates.revert()
                }
            }
        }
    }
}
