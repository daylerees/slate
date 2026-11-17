import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// Settings → Backups: backups of your files with restic (scripts/backup.py; Backups.qml runs them
// on a schedule). Set up once (where to), then what and how often, the last backup, Back up now,
// the key, and restoring a file or folder, which goes beside your files, never over them.
Column {
    id: backupsPage
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Backups" }
    IntroText {
        text: "Keep copies of your files on another drive, encrypted, with past versions to go back to. Once it's set up, Slate backs up by itself, quietly."
    }

    readonly property string script: Quickshell.shellPath("scripts/backup.py")
    property var st: ({})
    property var drives: []
    property string choice: ""                  // where to set up (a drive's folder, or typed)
    property string message: ""                 // what the last thing done came to
    property bool busy: false
    readonly property bool ready: !!st.restic
    readonly property bool isSet: !!st.set

    function refresh() { status.running = false; status.running = true; }
    Process {
        id: status
        running: true
        command: ["python3", backupsPage.script, "status"]
        stdout: StdioCollector { onStreamFinished: { try { backupsPage.st = JSON.parse(text); } catch (e) {} } }
    }
    // (while one runs: its outcome, a few seconds apart)
    Timer { running: !!backupsPage.st.running || backupsPage.busy; interval: 3000; repeat: true; onTriggered: backupsPage.refresh() }
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/storage.py"), "drives"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const home = Quickshell.env("HOME");
                    backupsPage.drives = JSON.parse(text).filter(d => d.mount !== "/" && !home.startsWith(d.mount + "/") && d.mount !== home)
                        .map(d => ({ value: d.mount.replace(/\/$/, "") + "/Slate Backups", label: d.name + " (" + Config.bytesText(d.free) + " free)" }));
                    if (backupsPage.choice === "" && backupsPage.drives.length) backupsPage.choice = backupsPage.drives[0].value;
                } catch (e) {}
            }
        }
    }
    Process {
        id: setup
        property string to: ""
        command: ["python3", backupsPage.script, "setup", to]
        stdout: StdioCollector {
            onStreamFinished: {
                backupsPage.busy = false;
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                if (r.ok) { Config.s.backupTo = setup.to; backupsPage.message = r.existing ? "Found the backups already there, and carried on with them." : "All set. The first backup starts in a moment."; Config.slateCall("backups", "now"); }
                else backupsPage.message = r.error === "locked" ? "There's already a backup in that folder, made with another key. Choose another folder."
                    : "Slate couldn't set up a backup there" + (r.detail ? " (" + r.detail + ")" : "") + ". Check the drive is plugged in and can be written to.";
                backupsPage.refresh();
            }
        }
    }
    Process {
        id: keyShow
        command: ["python3", backupsPage.script, "key"]
        property string key: ""
        stdout: StdioCollector { onStreamFinished: keyShow.key = text.trim() }
    }

    // ---- Not there yet: restic (installed from here, after asking: bin/slate-system --install,
    // with your password, as App Theming's apps are), then where to ----
    property bool installing: false
    property string installSaid: ""
    Process {
        id: installer
        command: [Quickshell.shellPath("bin/slate-system"), "--install", "restic"]
        stderr: StdioCollector { id: installErr }
        onExited: code => {
            backupsPage.installing = false;
            // (126/127: the password prompt was closed or failed, so nothing started)
            if (code === 126 || code === 127) { backupsPage.installSaid = ""; return; }
            const err = (installErr.text || "").trim().split("\n").filter(l => l.trim() !== "").pop() || "";
            backupsPage.installSaid = code === 0 ? "" : "Slate couldn't install restic" + (err ? " (" + err + ")" : "") + ". You can install the restic package yourself, too";
            backupsPage.refresh();
        }
    }
    Group {
        visible: !backupsPage.ready && backupsPage.st.restic !== undefined
        SettingRow {
            label: "Backups need restic"
            detail: backupsPage.installSaid !== "" ? backupsPage.installSaid
                : backupsPage.installing ? "Installing restic…"
                : "restic makes the encrypted backups. Slate can install it from your distribution's software, which asks for your password"
            Button {
                label: backupsPage.installing ? "Installing…" : "Install"; icon: 0xEA96; primary: true
                enabled: !backupsPage.installing
                onClicked: win.ask = {
                    title: "Install restic?",
                    body: "Slate installs restic, which makes your backups, from your distribution's software. It asks for your password. Once it's in, you can set up your backups right here.",
                    button: "Install", code: 0xEA96,
                    run: () => { backupsPage.installing = true; backupsPage.installSaid = ""; installer.running = true; }
                }
            }
        }
    }
    GroupLabel { visible: backupsPage.ready && !backupsPage.isSet; text: "Set up" }
    Group {
        visible: backupsPage.ready && !backupsPage.isSet
        DropdownSetting {
            visible: backupsPage.drives.length > 0
            label: "Back up to"
            detail: "A drive of its own is best: your backups stay safe if this computer's drive fails"
            options: backupsPage.drives.concat([{ value: "other", label: "Another folder…" }])
            value: backupsPage.drives.some(d => d.value === backupsPage.choice) ? backupsPage.choice : "other"
            onPicked: v => backupsPage.choice = v === "other" ? "" : v
        }
        Separator { visible: backupsPage.drives.length > 0 }
        SettingRow {
            label: backupsPage.drives.length > 0 ? "Folder" : "Back up to"
            detail: backupsPage.drives.length > 0 ? "Or type a folder (a network folder that's mounted works too)" : "Plug in a drive, or type a folder (a network folder that's mounted works too)"
            FieldFrame {
                field: toInput
                width: 240; height: 30
                TextInput {
                    id: toInput
                    activeFocusOnTab: true
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: win.text; selectionColor: win.accent
                    font.family: win.font; font.pixelSize: Config.text(12)
                    text: backupsPage.choice
                    onEditingFinished: backupsPage.choice = text.trim()
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Set up backups"
            detail: backupsPage.message !== "" ? backupsPage.message : "Makes an encrypted backup there, and a key to open it, kept in your keyring"
            Button {
                label: backupsPage.busy ? "Setting up…" : "Set up"; icon: 0xEA5E; primary: true
                enabled: !backupsPage.busy && backupsPage.choice.startsWith("/")
                onClicked: { backupsPage.busy = true; backupsPage.message = ""; setup.to = backupsPage.choice; setup.running = true; }
            }
        }
    }

    // ---- Set up ----
    GroupLabel { visible: backupsPage.isSet; text: "Your backups" }
    Group {
        visible: backupsPage.isSet
        SettingRow {
            label: backupsPage.st.running ? "Backing up…" : "Last backup"
            detail: backupsPage.st.running ? "Quietly, in the background. You can carry on as usual"
                : !backupsPage.st.last ? "None yet"
                : (backupsPage.st.lastOk ? Config.ago(backupsPage.st.last * 1000, true)
                    + (backupsPage.st.lastSize ? " · " + Config.bytesText(backupsPage.st.lastSize) + " of files" : "")
                    : "It didn't finish" + (backupsPage.st.lastError ? " (" + backupsPage.st.lastError + ")" : ""))
                  + (!backupsPage.st.reachable ? ". The drive isn't plugged in right now" : "")
            Button {
                label: "Back up now"; icon: 0xEB13
                enabled: !backupsPage.st.running && !!backupsPage.st.reachable
                onClicked: { Config.slateCall("backups", "now"); backupsPage.busy = true; doneSoon.restart(); }
                Timer { id: doneSoon; interval: 15000; onTriggered: backupsPage.busy = false }
            }
        }
        Separator {}
        SettingRow {
            label: "Backing up to"
            detail: Config.s.backupTo.replace(Quickshell.env("HOME"), "~")
            Button {
                label: "Stop"; icon: 0xEB55
                onClicked: win.confirmer.confirmWith({
                    title: "Stop backing up here?",
                    body: "Slate won't back up to this folder any more. The backups already there stay as they are, and you can set this up again at any time.",
                    button: "Stop", code: 0xEB55, danger: false
                }, () => { Config.s.backupTo = ""; backupsPage.refresh(); })
            }
        }
        Separator {}
        DropdownSetting {
            label: "What to back up"
            settingKey: "backupWhat"
            options: [{ value: "home", label: "Your home folder" }, { value: "personal", label: "Documents, pictures, music and videos" }]
            detail: Config.s.backupWhat === "home" ? "Everything in your home folder, except caches, the Waste Basket and installed apps"
                : "Your Desktop, Documents, Pictures, Music and Videos folders"
            value: Config.s.backupWhat
            onPicked: v => Config.s.backupWhat = v
        }
        Separator {}
        DropdownSetting {
            label: "How often"
            settingKey: "backupSchedule"
            options: [{ value: "daily", label: "Every day" }, { value: "weekly", label: "Every week" }, { value: "manual", label: "Only when I ask" }]
            detail: Config.s.backupSchedule === "manual" ? "Only when you press Back up now" : "Quietly in the background, not in game mode. When the drive's away, it catches up once it's back"
            value: Config.s.backupSchedule
            onPicked: v => Config.s.backupSchedule = v
        }
        Separator {}
        SettingRow {
            label: "Your backup key"
            detail: keyShow.key !== "" ? keyShow.key
                : "Kept " + (backupsPage.st.keyIn === "keyring" ? "in your keyring" : "in a file only you can read") + ". Keep a copy somewhere safe: without it, these backups can't be opened on another computer"
            Button {
                label: keyShow.key !== "" ? "Copy" : "Show"; icon: keyShow.key !== "" ? 0xEA7A : 0xEA9A
                onClicked: keyShow.key !== "" ? Quickshell.execDetached(["wl-copy", "--", keyShow.key]) : keyShow.running = true
            }
        }
    }

    // ---- Restoring ----
    GroupLabel { visible: backupsPage.isSet; text: "Restore" }
    Group {
        id: restoreGroup
        visible: backupsPage.isSet
        property var snaps: []
        property string snap: ""
        property string folder: ""
        property var entries: []
        property bool looking: false
        property string said: ""
        Process {
            id: snapList
            command: ["python3", backupsPage.script, "snapshots"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { restoreGroup.snaps = JSON.parse(text); } catch (e) { restoreGroup.snaps = []; }
                    restoreGroup.looking = false;
                    if (restoreGroup.snaps.length) restoreGroup.open(restoreGroup.snaps[0].id, restoreGroup.snaps[0].paths[0] || "/");
                }
            }
        }
        Process {
            id: lsProc
            command: ["python3", backupsPage.script, "ls", restoreGroup.snap, restoreGroup.folder]
            stdout: StdioCollector { onStreamFinished: { try { restoreGroup.entries = JSON.parse(text); } catch (e) { restoreGroup.entries = []; } restoreGroup.looking = false; } }
        }
        Process {
            id: restoring
            property string path: ""
            command: ["python3", backupsPage.script, "restore", restoreGroup.snap, path]
            stdout: StdioCollector {
                onStreamFinished: {
                    let r = {};
                    try { r = JSON.parse(text); } catch (e) {}
                    restoreGroup.said = r.ok ? "Restored into " + r.to.replace(Quickshell.env("HOME"), "~") + ", beside your files"
                        : "Slate couldn't restore that" + (r.error ? " (" + r.error + ")" : "");
                    if (r.ok) Quickshell.execDetached(["xdg-open", r.to]);
                }
            }
        }
        function open(id, where) { snap = id; folder = where; looking = true; lsProc.running = false; lsProc.running = true; }
        SettingRow {
            label: "Restore a file or folder"
            detail: restoreGroup.said !== "" ? restoreGroup.said
                : restoreGroup.snaps.length ? "From a backup: what you restore goes into a new folder in your home, never over your files"
                : "Look through your backups and bring back a file or folder"
            Button {
                visible: !restoreGroup.snaps.length
                label: restoreGroup.looking ? "Looking…" : "Look"; icon: 0xEB1C
                enabled: !restoreGroup.looking && !!backupsPage.st.reachable
                onClicked: { restoreGroup.looking = true; snapList.running = true; }
            }
        }
        Separator { visible: restoreGroup.snaps.length > 0 }
        DropdownSetting {
            visible: restoreGroup.snaps.length > 0
            label: "Backup from"
            options: restoreGroup.snaps.map(s => ({ value: s.id, label: Qt.formatDateTime(new Date(s.time), "d MMM yyyy, HH:mm") }))
            value: restoreGroup.snap
            onPicked: v => { const s = restoreGroup.snaps.find(x => x.id === v); restoreGroup.open(v, restoreGroup.folder || (s && s.paths[0]) || "/"); }
        }
        Separator { visible: restoreGroup.snaps.length > 0 }
        SettingRow {
            visible: restoreGroup.snaps.length > 0
            label: restoreGroup.folder.replace(Quickshell.env("HOME"), "~") || "/"
            detail: restoreGroup.looking ? "Looking…" : restoreGroup.entries.length + (restoreGroup.entries.length === 1 ? " item" : " items")
            Button {
                label: "Up"; icon: 0xEA19
                visible: restoreGroup.folder !== "/" && restoreGroup.folder !== ""
                onClicked: restoreGroup.open(restoreGroup.snap, restoreGroup.folder.replace(/\/[^\/]*$/, "") || "/")
            }
            Button {
                label: "Restore this folder"; icon: 0xEB13
                onClicked: { restoreGroup.said = "Restoring…"; restoring.path = restoreGroup.folder; restoring.running = true; }
            }
        }
        Repeater {
            model: restoreGroup.snaps.length ? restoreGroup.entries.slice(0, 200) : []
            delegate: Column {
                id: entryRow
                required property var modelData
                width: parent ? parent.width : 0
                Separator {}
                ListItemRow {
                    removable: false
                    label: entryRow.modelData.name
                    detail: entryRow.modelData.dir ? "Folder" : Config.bytesText(entryRow.modelData.size)
                    Button {
                        visible: entryRow.modelData.dir
                        label: "Open"; icon: 0xEAAD
                        onClicked: restoreGroup.open(restoreGroup.snap, entryRow.modelData.path)
                    }
                    Button {
                        label: "Restore"; icon: 0xEB13
                        onClicked: { restoreGroup.said = "Restoring…"; restoring.path = entryRow.modelData.path; restoring.running = true; }
                    }
                }
            }
        }
    }
}
