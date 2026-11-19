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
    id: lockCol
    spacing: 4
    readonly property var minutes: win.minuteOptions([0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60])
    PageTitle { text: "Security" }
    GroupLabel { text: "Locking" }
    Group {
        SettingRow {
            label: "Lock screen"
            detail: "Super+L, the power menu, or a hot corner"
            Row {
                spacing: 8
                Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "preview", "lock"]); } }
                Button { icon: 0xEAE2; label: "Lock now"; primary: true; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "lock"]); } }
            }
        }
        Separator {}
        ToggleSetting {
            label: "Power menu on the lock screen"
            detail: "Lets anyone at the keyboard suspend, restart, shut down or log you out without your password"
            key: "lockScreenPowerMenu"
        }
        Separator {}
        ToggleSetting {
            label: "Lock before sleep"
            // (Slate hears that the computer's about to sleep from systemd or elogind)
            needsMet: Config.hasLogind
            needs: "Needs systemd or elogind, and neither is running"
            detail: "Lock the screen whenever the computer suspends or hibernates"
            key: "lockBeforeSleep"
        }
    }
    GroupLabel { text: "Login screen" }
    Group {
        SettingRow {
            id: greeterRow
            // From slate-greeter-sync --status: state (not-installed, outdated, current),
            // greetd (yes/no), dm (the display manager in use), used (yes/no), backup (yes/no)
            property var info: ({})
            property string status: ""
            readonly property string state: info.state || ""
            // Installed and switched on: greetd starts it (not switched back since)
            readonly property bool used: (state === "outdated" || state === "current") && info.used === "yes"
            readonly property string dm: info.dm || "none"
            readonly property string enable: info.enable || ""
            label: "Slate login screen"
            detail: status !== "" ? status
                : state === "" ? ""
                : !used && info.greetd !== "yes" ? "Optional. Replaces your computer's login screen with one that matches Slate. "
                    + "It runs on greetd, which isn't installed: install greetd with your package manager first"
                : !used ? "Optional. Replaces your computer's login screen with one that matches Slate; "
                    + "until then, your computer keeps its own"
                // (the command is the one for this computer's init system: bin/slate-init)
                : dm === "none" ? "Installed, but greetd isn't switched on. "
                    + (enable !== "" ? "To switch it on, in a terminal:  " + enable : "Switch the greetd service on with your init system")
                : dm !== "greetd" && dm !== "unknown" ? "Installed, but your computer starts " + dm + " instead. "
                    + ((info.switch || "") !== "" ? "To switch, in a terminal:  " + info.switch
                       : "Switch " + dm + " off and greetd on with your init system")
                : state === "outdated" ? "Its design has changed since it was installed. Update asks for your password"
                : "Installed; follows your wallpaper and theme automatically"
            function refresh() { status = ""; greeterCheck.running = true; }
            FirstLook {
                id: greeterCheck
                running: true
                command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const o = {};
                        for (const line of text.split("\n")) { const i = line.indexOf("="); if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim(); }
                        greeterRow.info = o;
                    }
                }
            }
            // Install, update or switch back, asking for your password (pkexec, through
            // slate-system, which runs the installer's root-owned copy). Says what
            // went wrong when it fails; cancelling the password prompt changes nothing
            Process {
                id: greeterRun
                property string done: ""
                property string failed: ""
                stderr: StdioCollector { id: greeterErr }
                onExited: code => {
                    const why = greeterErr.text.trim().split("\n").filter(l => l !== "")[0] || "";
                    greeterRow.status = code === 0 ? done
                        : code === 126 || code === 127 ? ""                   // password prompt cancelled
                        : failed + (why !== "" ? ": " + why : "");
                    greeterCheck.running = true;
                }
            }
            function run(args, doing, done, failed) {
                status = doing;
                greeterRun.done = done; greeterRun.failed = failed;
                greeterRun.command = [Quickshell.shellPath("bin/slate-system"), "--root", "slate-greeter-install"].concat(args);
                greeterRun.running = true;
            }
            Row {
                spacing: 8
                Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "preview", "login"]); } }
                Button {
                    visible: greeterRow.state !== "" && !greeterRow.used
                    enabled: greeterRow.info.greetd === "yes" && !greeterRun.running
                    opacity: enabled ? 1 : 0.4
                    label: "Install"
                    onClicked: win.ask = Object.assign({
                        run: () => greeterRow.run([], "Installing…",
                            "Installed; shows at your next logout or restart", "Slate couldn't install it")
                    }, win.loginScreenInstallQuestion)
                }
                Button {
                    visible: greeterRow.used && greeterRow.state === "outdated"
                    enabled: !greeterRun.running
                    label: "Update"
                    onClicked: win.ask = Object.assign({
                        run: () => greeterRow.run(["--code-only"], "Updating…",
                            "Updated; shows at your next logout or restart", "Slate couldn't update it")
                    }, win.loginScreenUpdateQuestion)
                }
                Button {
                    visible: greeterRow.used && greeterRow.info.backup === "yes"
                    enabled: !greeterRun.running
                    label: "Switch back"
                    onClicked: win.ask = {
                        title: "Switch back to your old login screen?",
                        body: "greetd goes back to the login screen it had before Slate's, from your next logout or restart. "
                            + "You're welcome to install Slate's again at any time.",
                        button: "Switch back", code: 0xEAE2,
                        run: () => greeterRow.run(["--revert"], "Switching back…",
                            "Switched back; your old login screen shows at your next logout or restart", "Slate couldn't switch it back")
                    }
                }
            }
        }
    }
    GroupLabel { text: "When you're away" }
    Group {
        ChoiceSetting {
            label: "Lock after"
            settingKey: "idleLockMinutes"
            options: lockCol.minutes
            value: Config.s.idleLockMinutes
            onPicked: v => Config.s.idleLockMinutes = v
        }
        Separator {}
        ChoiceSetting {
            label: "Turn the screen off after"
            settingKey: "idleScreenOffMinutes"
            detail: "Moving the mouse or pressing a key turns it back on"
            options: lockCol.minutes
            value: Config.s.idleScreenOffMinutes
            onPicked: v => Config.s.idleScreenOffMinutes = v
        }
        Separator {}
        ChoiceSetting {
            label: "Suspend after"
            needsMet: Config.canSuspend
            needs: "This computer can't suspend"
            settingKey: "idleSuspendMinutes"
            options: lockCol.minutes
            value: Config.s.idleSuspendMinutes
            onPicked: v => Config.s.idleSuspendMinutes = v
        }
        Separator {}
        ToggleSetting {
            label: "Wait while media plays"
            detail: "You're not counted as away while something plays full screen, or an app is keeping the screen awake"
            key: "idleRespectInhibitors"
        }
    }
}
