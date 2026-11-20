// The login screen: kept in step with the wallpaper and settings, and offered an update (and
// the system's packages) when Slate's code has changed.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    property var hold: null                  // UpdateHold.qml

    // Keep the login screen (/var/lib/slate-greeter) in step with the wallpaper and
    // settings: the shared look, when that folder is yours, and your own look in its people/
    // folder, which everyone can keep theirs in. Does nothing until it's been set up with:
    // sudo slate-greeter-install
    Timer { id: greeterSync; interval: 3000; onTriggered: if (!root.hold.heldBack(greeterSync)) greeterSyncRun.running = !Config.testMode }
    Process {
        id: greeterSyncRun
        command: ["sh", "-c", "{ [ -w /var/lib/slate-greeter ] || [ -w /var/lib/slate-greeter/people ]; } && exec \"$0\" || true", Quickshell.shellPath("bin/slate-greeter-sync")]
    }
    Connections { target: Config; function onWallpaperChanged() { greeterSync.restart(); } function onSaved() { greeterSync.restart(); } function onAvatarVersionChanged() { greeterSync.restart(); } }
    // Your displays too (the login screen starts each monitor as your desktop has it): when
    // Settings → Displays keeps a change, a monitor comes or goes, and once a little after Slate
    // starts, by when each monitor has its best mode (session/hypr/config/monitors.lua)
    FileView {
        path: Config.stateHome + "/slate/displays.json"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); greeterSync.restart(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name.startsWith("monitoradded") || e.name.startsWith("monitorremoved")) greeterSync.restart(); }
    }
    Timer { interval: 10000; running: !Config.testMode; onTriggered: greeterSync.restart() }

    // When the login screen's code has changed, offer to install it (a notification
    // with an Update button, then a password prompt). Checked 20 s after Slate starts
    // (it reloads whenever its own code is edited) and after the greeter-only files
    // change, so a run of edits gives one prompt.
    Timer { id: greeterCodeCheck; interval: 20000; running: !Config.testMode; onTriggered: greeterPrompt.running = !Config.testMode }
    Process { id: greeterPrompt; command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--prompt"] }
    // When this version of Slate needs packages you don't have, or changes the login session,
    // offer to install them (a notification with an Install button, then a password prompt).
    // Updates from Settings do this as they install; this catches the rest (a copy put in place
    // by hand, a package removed since). Checked once, 25 s after Slate starts.
    Timer { interval: 25000; running: !Config.testMode; onTriggered: systemPrompt.running = true }
    Process { id: systemPrompt; command: [Quickshell.shellPath("bin/slate-system"), "--prompt"] }
    Variants {
        model: ["greeter/files", "greeter/shell.qml", "greeter/LoginWindow.qml", "greeter/run-greeter.sh", "greeter/fonts.conf",
            "greeter/hyprland.lua", "greeter/emergency/shell.qml", "greeter/emergency/Window.qml", "greeter/emergency/Box.qml",
            "scripts/wallpaper-accent.py"]
        FileView {
            required property var modelData
            path: Quickshell.shellPath(modelData)
            watchChanges: true
            onFileChanged: { reload(); greeterCodeCheck.restart(); }
        }
    }
}
