import QtQuick
import Quickshell
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
    // The update's progress: how much has downloaded, and the step it's on
    readonly property real got: Updates.state.got || 0
    readonly property real size: Updates.state.size || 0
    function mb(bytes) { return (bytes / 1e6).toFixed(1) + " MB"; }
    function downloadText() {
        return "Step 1 of 2: downloading" + (size > 0 ? ", " + mb(got) + " of " + mb(size) : got > 0 ? ", " + mb(got) + " so far" : "")
            + ". Your apps and windows stay open";
    }
    function installText() {
        return Updates.how === "shared"
            ? "Once an administrator's password is given, Slate downloads and installs it, then restarts on the new version. Your apps and windows stay open"
            : "Step 2 of 2: installing. This can take a minute, then Slate restarts on the new version. Your apps and windows stay open";
    }
    // (for the tests: what the newest version's row says, which of its buttons show, and where
    // its Update button and the notes are, in the page's own units)
    readonly property var testState: ({
        label: latestRow.label, detail: latestRow.detail,
        update: updateButton.visible, check: checkButton.visible, meter: downloadMeter.visible ? downloadMeter.value : -1,
        // (from each one's own y, so it follows the page as it lays out: mapToItem alone is
        // worked out once, before the notes had come)
        rowY: Math.round(versionGroup.y + latestRow.parent.y + latestRow.y), rowH: Math.round(latestRow.height),
        buttonY: Math.round(versionGroup.y + latestRow.parent.y + latestRow.y + updateButton.parent.y + updateButton.y
                            + (updateButton.parent.parent ? updateButton.parent.parent.y : 0)),
        notes: notesLabel.visible, notesY: Math.round(notesLabel.y)
    })
    // What updating will do, said before it starts
    function howText() {
        return Updates.how === "packaged" ? "Your system's own updates bring it"
            : Updates.how === "shared" ? "Updating asks for an administrator's password, then Slate restarts on the new version"
            : "Updating takes a minute or so, then Slate restarts on the new version";
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
        id: versionGroup
        SettingRow {
            label: "Installed version"
            detail: Updates.installed === "" ? "Unknown: this copy of Slate wasn't installed with a version"
                : updatesPane.nice(Updates.installed)
        }
        Separator {}
        // The newest version, and updating to it, together: where it says there's a new version
        // is where its button is, and where the update's progress shows
        SettingRow {
            id: latestRow
            readonly property bool offering: Updates.available || Updates.busy || Updates.status === "failed"
            readonly property bool canUpdate: Updates.how !== "packaged"
            label: Updates.busy ? "Updating to " + updatesPane.latest + "…"
                : Updates.status === "failed" ? "The update didn't finish"
                : Updates.available ? "Slate " + updatesPane.latest + " is available"
                : "Latest version"
            detail: Updates.status === "downloading" ? updatesPane.downloadText()
                : Updates.status === "installing" ? updatesPane.installText()
                : Updates.status === "failed" ? Updates.error
                : Updates.checking ? "Checking…"
                : Updates.error !== "" ? Updates.error
                : updatesPane.latest === "" ? "Not checked yet"
                : Updates.available ? (Updates.state.published ? "Released " + updatesPane.when(Updates.state.published) + ". " : "") + updatesPane.howText()
                : updatesPane.latest + ": you're up to date"
                  + (Updates.checkedAt > 0 ? " · checked " + updatesPane.ago(Updates.checkedAt) : "")
            below: [
                Meter {
                    id: downloadMeter
                    visible: Updates.status === "downloading" && updatesPane.size > 0
                    width: Math.min(320, latestRow.width - 32)
                    value: updatesPane.size > 0 ? Math.min(1, updatesPane.got / updatesPane.size) : 0
                    colour: win.accent
                    trackColour: win.control
                    minFill: 0
                    slideMs: 200
                }
            ]
            Row {
                spacing: 8
                // (while it updates: turning, as Bluetooth's search does)
                Spinner {
                    visible: Updates.busy
                    anchors.verticalCenter: parent.verticalCenter
                    colour: win.accent
                }
                Button {
                    visible: Updates.status === "failed" && Updates.state.log !== undefined
                    label: "Show log"
                    onClicked: Quickshell.execDetached(["xdg-open", Updates.state.log])
                }
                Button {
                    id: checkButton
                    visible: !Updates.busy && (!latestRow.offering || !latestRow.canUpdate)
                    label: Updates.checking ? "Checking…" : "Check now"; icon: 0xEB13
                    onClicked: Updates.check(true)
                }
                Button {
                    id: updateButton
                    visible: latestRow.offering && latestRow.canUpdate && !Updates.busy
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
        Separator {}
        ToggleSetting {
            label: "Check for updates"
            detail: "Once a day, and Slate lets you know when there's a new version"
            key: "updateCheck"
        }
    }

    // ---- A new version: what's new in it, right under where it says it's there ----
    GroupLabel {
        id: notesLabel
        visible: latestRow.offering
        text: "What's new in " + updatesPane.latest
    }
    Group {
        visible: latestRow.offering
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
        Separator { visible: Updates.notes !== "" && (changedNote.visible || releaseRow.visible) }
        // Slate's own files changed by hand: an update replaces them (the old copy is kept)
        Text {
            id: changedNote
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
            id: releaseRow
            visible: Updates.url !== ""
            label: "Release page"
            detail: "The full notes and downloads, on GitHub"
            Button { label: "Open"; icon: 0xEA99; onClicked: Qt.openUrlExternally(Updates.url) }
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
