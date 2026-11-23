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
                Button { label: "Preview"; onClicked: { win.visible = false; Config.slateCall("lock", "preview", "lock"); } }
                Button { icon: 0xEAE2; label: "Lock now"; primary: true; onClicked: { win.visible = false; Config.slateCall("lock", "lock"); } }
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
    GroupLabel { text: "Unlocking" }
    Group {
        SettingRow {
            label: "Face, Fingerprint & Keys"
            detail: "Unlock the lock screen by looking at your camera, with your password still there"
            Button { label: "Open"; onClicked: win.goTo("unlock", "") }
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
                Button { label: "Preview"; onClicked: { win.visible = false; Config.slateCall("lock", "preview", "login"); } }
                Button {
                    visible: greeterRow.state !== "" && !greeterRow.used
                    enabled: greeterRow.info.greetd === "yes" && !greeterRun.running
                    opacity: enabled ? 1 : 0.4
                    label: "Install"
                    onClicked: win.askQuestion(Object.assign({
                        run: () => greeterRow.run([], "Installing…",
                            "Installed; shows at your next logout or restart", "Slate couldn't install it")
                    }, win.loginScreenInstallQuestion))
                }
                Button {
                    visible: greeterRow.used && greeterRow.state === "outdated"
                    enabled: !greeterRun.running
                    label: "Update"
                    onClicked: win.askQuestion(Object.assign({
                        run: () => greeterRow.run(["--code-only"], "Updating…",
                            "Updated; shows at your next logout or restart", "Slate couldn't update it")
                    }, win.loginScreenUpdateQuestion))
                }
                Button {
                    visible: greeterRow.used && greeterRow.info.backup === "yes"
                    enabled: !greeterRun.running
                    label: "Switch back"
                    onClicked: win.askQuestion({
                        title: "Switch back to your old login screen?",
                        body: "greetd goes back to the login screen it had before Slate's, from your next logout or restart. "
                            + "You're welcome to install Slate's again at any time.",
                        button: "Switch back", code: 0xEAE2,
                        run: () => greeterRow.run(["--revert"], "Switching back…",
                            "Switched back; your old login screen shows at your next logout or restart", "Slate couldn't switch it back")
                    })
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
    // The firewall (scripts/firewall.py status, read without a password): which one this
    // computer has, and whether it's on
    GroupLabel { text: "Firewall" }
    Group {
        id: fw
        readonly property string script: Quickshell.shellPath("scripts/firewall.py")
        // { kind: ufw | firewalld | nixos | none, on: true | false | null, allow: {…},
        //   install: the package to offer, canChange }, or {} until it's answered
        property var info: ({})
        readonly property string kind: info.kind || ""
        readonly property string name: kind === "ufw" ? "ufw" : kind === "firewalld" ? "firewalld" : ""
        function take(text) { try { info = JSON.parse(text); } catch (e) { info = {}; } }
        // Changing it (firewall.py set / allow: your password each time): what it's doing now,
        // and how the last change went ("" when it went through)
        property string doing: ""
        property string problem: ""
        function change(args, doing) {
            fw.doing = doing;
            fw.problem = "";
            changeProc.command = [fw.script].concat(args);
            changeProc.running = true;
        }
        Process {
            id: changeProc
            stderr: StdioCollector { id: changeSaid }
            onExited: code => {
                fw.doing = "";
                fw.problem = code === 0 ? "" : (changeSaid.text.trim().split("\n").pop() || "Slate couldn't change the firewall");
                fw.refresh();
            }
        }
        // No firewall: install the distro's usual one (slate-system --install, your password).
        // It arrives off, for you to turn on
        function install() {
            const pkg = fw.info.install;
            if (!pkg) return;
            fw.doing = "Installing " + pkg + "…";
            fw.problem = "";
            installProc.command = [Quickshell.shellPath("bin/slate-system"), "--install", pkg];
            installProc.running = true;
        }
        Process {
            id: installProc
            onExited: code => {
                fw.doing = "";
                fw.problem = code === 0 ? "" : "Slate couldn't install " + (fw.info.install || "it") + ". Check you're online, then try again";
                fw.refresh();
            }
        }
        // Off asks first: it makes the computer easier to reach
        function askOff() {
            win.askQuestion({
                title: "Turn the firewall off?",
                body: "Anything on your network will be able to try to reach this computer, including things you haven't allowed. "
                    + "You can turn it back on here at any time.",
                button: "Turn off", destructive: true, code: 0xEAE2,
                run: () => fw.change(["set", "off"], "Turning it off…")
            });
        }
        function refresh() { fwProc.running = false; fwProc.running = true; }
        // (the tests: what the script would say, looked at again as soon as it's given)
        Connections { target: win; enabled: Config.testMode; function onPretendPollsChanged() { fw.refresh(); } }
        FirstLook {
            id: fwProc
            running: true
            command: [fw.script, "status"]
            stdout: StdioCollector { onStreamFinished: fw.take(win.pretendPolls.firewall ?? text) }
        }
        SettingRow {
            id: fwRow
            label: "Firewall"
            detail: fw.doing !== "" ? fw.doing
                : fw.problem !== "" ? fw.problem
                : fw.kind === "" ? "Looking…"
                : fw.kind === "none" ? "There's no firewall on this computer yet, so anything on your network can try to reach it"
                    + (fw.info.install ? ". Install " + fw.info.install + " and you can turn it on here"
                       : ". Install your distro's firewall (ufw or firewalld) and you can turn it on here")
                : fw.kind === "nixos" ? (fw.info.on === true ? "On. " : fw.info.on === false ? "Off. " : "")
                    + "It's set in your NixOS configuration (networking.firewall), so change it there"
                : fw.info.on === true ? "On: other computers can only reach this one in the ways you allow (" + fw.name + ")"
                : fw.info.on === false ? "Off: anything on your network can try to reach this computer (" + fw.name + ")"
                : "Slate couldn't tell whether " + fw.name + " is on just now"
            // (one or the other: a Row leaves out what's hidden, and the row's slot doesn't)
            Row {
            // (NixOS's: only said, as it's changed in its configuration)
            Text {
                visible: fw.kind === "nixos" && fw.info.on !== null && fw.info.on !== undefined
                text: fw.info.on ? "On" : "Off"
                color: fw.info.on ? win.text : win.dim
                font.family: win.font; font.pixelSize: Config.text(13)
            }
            Button {
                visible: fw.kind === "none" && !!fw.info.install
                enabled: fw.doing === ""
                icon: 0xEA96; label: "Install " + (fw.info.install || "")
                onClicked: fw.install()
            }
            SettingToggle {
                visible: fw.info.canChange === true
                enabled: fw.doing === ""
                checked: fw.info.on === true
                Accessible.name: "Firewall"
                onToggled: v => { if (v) fw.change(["set", "on"], "Turning it on…"); else fw.askOff(); }
            }
            }
        }
        // What it lets in (firewall.py allow: the same few ports each, from your own network
        // only), where Slate can change it. They count while it's on
        // What it lets in (firewall.py allow: the same few ports each, from your own network
        // only), where Slate can change it; they count while it's on
        function allow(id, on) { fw.change(["allow", id, on ? "on" : "off"], on ? "Letting it in…" : "Closing it again…"); }
        Separator { visible: fw.info.canChange === true }
        SettingRow {
            visible: fw.info.canChange === true
            label: "KDE Connect"
            detail: "Your phone and this computer finding each other, for notifications, files and the clipboard (KDE Connect and GSConnect)"
            needsMet: fw.info.on === true
            needs: "Needs the firewall to be on"
            needsPage: "lock"; needsLabel: "Firewall"
            SettingToggle {
                enabled: fw.doing === ""
                checked: !!fw.info.allow && fw.info.allow.kdeconnect === true
                Accessible.name: "KDE Connect"
                onToggled: v => fw.allow("kdeconnect", v)
            }
        }
        Separator { visible: fw.info.canChange === true }
        SettingRow {
            visible: fw.info.canChange === true
            label: "File sharing"
            detail: "Other computers on your network opening folders you share (Samba)"
            needsMet: fw.info.on === true
            needs: "Needs the firewall to be on"
            needsPage: "lock"; needsLabel: "Firewall"
            SettingToggle {
                enabled: fw.doing === ""
                checked: !!fw.info.allow && fw.info.allow.samba === true
                Accessible.name: "File sharing"
                onToggled: v => fw.allow("samba", v)
            }
        }
        Separator { visible: fw.info.canChange === true }
        SettingRow {
            visible: fw.info.canChange === true
            label: "Remote login"
            detail: "Logging in to this computer from another one on your network (SSH)"
            needsMet: fw.info.on === true
            needs: "Needs the firewall to be on"
            needsPage: "lock"; needsLabel: "Firewall"
            SettingToggle {
                enabled: fw.doing === ""
                checked: !!fw.info.allow && fw.info.allow.ssh === true
                Accessible.name: "Remote login"
                onToggled: v => fw.allow("ssh", v)
            }
        }
        Separator { visible: fw.info.canChange === true }
        SettingRow {
            visible: fw.info.canChange === true
            label: "Game streaming"
            detail: "Steam Remote Play, and game downloads from your other computers"
            needsMet: fw.info.on === true
            needs: "Needs the firewall to be on"
            needsPage: "lock"; needsLabel: "Firewall"
            SettingToggle {
                enabled: fw.doing === ""
                checked: !!fw.info.allow && fw.info.allow.steam === true
                Accessible.name: "Game streaming"
                onToggled: v => fw.allow("steam", v)
            }
        }
    }
    Footnote {
        visible: fw.info.canChange === true
        text: "Each lets in only what it needs, and only from your own network. Whatever you do yourself, like browsing and downloading, works as usual with the firewall on."
    }
}
