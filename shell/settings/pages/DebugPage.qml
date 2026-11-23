import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// Debug: fixes you shouldn't normally need (a tile on All Settings, not in the sidebar)
Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Debug" }
    IntroText {
        text: "Fixes for when something hasn't caught up. Slate normally does all of this by itself, so you shouldn't need them."
        leftPadding: 0; bottomPadding: 8
    }
    GroupLabel { text: "Reload" }
    Group {
        SettingRow {
            label: "Reload everything"
            detail: "Reloads Hyprland's config and restarts Slate from scratch (the bar, dock, panels and this window), "
                + "then comes back here. Your apps and windows stay open. For when something looks stuck or out of date"
            Button { label: "Reload"; icon: 0xEB13; onClicked: Config.reloadEverything() }
        }
    }
    GroupLabel { text: "Login screen" }
    Group {
        SettingRow {
            id: resyncRow
            property bool installed: false
            property string status: ""
            label: "Resync the login screen"
            detail: status !== "" ? status
                : !installed ? "Only for Slate's own login screen, which isn't set up"
                : "The login screen copies your wallpaper, settings, picture and font whenever you change them in Slate. "
                  + "Use this if you changed one outside Slate (replaced the wallpaper file, changed your picture, name "
                  + "or keyboard layout elsewhere) and the login screen hasn't caught up"
            Process {
                running: true
                command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--check"]
                stdout: StdioCollector { onStreamFinished: { const t = text.trim(); resyncRow.installed = t === "outdated" || t === "current"; } }
            }
            Process {
                id: resyncRun
                command: [Quickshell.shellPath("bin/slate-greeter-sync")]
                onExited: code => resyncRow.status = code === 0 ? "Resynced just now" : "Slate couldn't resync. Is the login screen set up?"
            }
            Button {
                enabled: resyncRow.installed
                opacity: enabled ? 1 : 0.4
                label: "Resync"
                onClicked: { resyncRow.status = "Resyncing…"; resyncRun.running = true; }
            }
        }
    }
    GroupLabel { text: "Logs" }
    Group {
        DropdownSetting {
            label: "Log detail"
            settingKey: "logLevel"
            detail: "How much Slate writes to its log. Turn it up while tracking down a problem, then back down. Changing it restarts Slate"
            options: [{ value: "normal", label: "Normal" }, { value: "detailed", label: "Detailed" }, { value: "everything", label: "Everything" }]
            value: Config.s.logLevel || "normal"
            // Asks first: changing it restarts Slate
            onPicked: v => {
                if (v === (Config.s.logLevel || "normal")) return;
                const name = ({ normal: "Normal", detailed: "Detailed", everything: "Everything" })[v];
                win.ask = {
                    title: "Restart Slate?",
                    body: "Log detail changes to " + name + " when Slate restarts. Your apps and windows stay open. "
                        + "The bar, dock and Settings step away for a moment, then Settings opens again right here.",
                    button: "Restart",
                    run: () => { Config.s.logLevel = v; Config.logLevelEdited(); }
                };
            }
        }
        Separator {}
        SettingRow {
            id: exportRow
            property string saved: ""          // the file, once exported
            property string status: ""
            label: "Export recent logs"
            detail: status !== "" ? status
                : "Saves Slate's recent log and details about your system to a text file in Downloads, to attach "
                  + "when reporting a problem. Your location is left out; look the file over before sharing it, as "
                  + "the log can name apps, windows and file paths"
            Process {
                id: exportRun
                command: [Quickshell.shellPath("bin/slate-logs")]
                stdout: StdioCollector { onStreamFinished: exportRow.saved = text.trim() }
                onExited: code => exportRow.status = code === 0 && exportRow.saved !== ""
                    ? "Saved to " + exportRow.saved.replace(Quickshell.env("HOME"), "~") + ". Look it over before sharing it"
                    : "Slate couldn't save the logs"
            }
            Row {
                spacing: 8
                Button { visible: exportRow.saved !== ""; label: "Show"; onClicked: Quickshell.execDetached(["xdg-open", exportRow.saved.substring(0, exportRow.saved.lastIndexOf("/"))]) }
                Button { label: "Export"; onClicked: { exportRow.saved = ""; exportRow.status = "Saving…"; exportRun.running = true; } }
            }
        }
    }
    GroupLabel { text: "Start over" }
    Group {
        SettingRow {
            label: "Factory reset"
            detail: "Puts Slate back as it was when first installed: every setting to its default, and your dock pins, "
                + "saved Spaces, launcher history, notifications, clipboard history, display layout and app theming "
                + "forgotten. You'll be asked twice before anything changes, and can choose to clear your own files "
                + "(~/.config/slate/hypr and user/) as well. Everything is kept in a backup folder "
                + "(~/.local/share/slate/backups)"
            // (whether unlocking without the password is set up: the reset turns it off too, with
            // your password, so the question says so)
            FileView { id: unlockSetUp; path: "/etc/pam.d/slate-lock"; printErrors: false; property bool on: false
                       onLoaded: on = true; onLoadFailed: on = false }
            Button {
                label: "Reset…"
                destructive: true
                onClicked: win.ask = {
                    title: "Reset Slate?",
                    body: "Every setting goes back to its default, and Slate forgets your dock pins, saved Spaces, launcher "
                        + "history, notifications, clipboard history, display layout and app theming. Your apps and "
                        + "windows stay open.",
                    option: { label: "Also clear my own files",
                              detail: "Your Hyprland tweaks (~/.config/slate/hypr) and your own QML (user/) go back to the blank versions Slate starts with" },
                    button: "Continue",
                    run: userFiles => win.askAfter({
                        title: userFiles ? "Erase everything, including your own files?" : "Erase all of Slate's settings?",
                        body: "This is the last step. Straight away, Slate forgets every setting, your dock pins, saved Spaces, "
                            + "launcher and clipboard history, notifications, display layout and app theming"
                            + (userFiles ? ", and your own files are replaced with blank ones: every keybind, monitor, "
                                + "window rule and autostart you added in ~/.config/slate/hypr, and your QML in user/" : "")
                            + ". Slate restarts and the welcome tour opens."
                            + (unlockSetUp.on ? " Unlocking with your face, a fingerprint or a key is turned off too, so Slate asks for your password first." : "")
                            + "\n\nThere's no undo in Settings. The old files are "
                            + "moved to ~/.local/share/slate/backups, and you'd have to copy them back by hand.",
                        button: userFiles ? "Erase everything" : "Erase and reset",
                        destructive: true,
                        run: () => Quickshell.execDetached(["setsid", "-f", Quickshell.shellPath("bin/slate-factory-reset")]
                            .concat(userFiles ? ["--user-files"] : []))
                    })
                }
            }
        }
    }
}
