// Settings → Accessibility → Screen reader (Super+Alt+S): Orca reading the screen aloud. Turned
// on, Slate says a screen reader is on (GNOME's screen-reader-enabled, which the accessibility
// bus follows, so apps and Slate itself open up to it) and starts Orca if it isn't running;
// turned off, the reverse. Nothing is touched at startup while it's off. (Slate also starts with
// Qt's accessibility on while it's on: bin/slate, screen_reader.) Orca is optional: without it,
// Settings says what to install.
//   slate ipc call screenreader toggle

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property bool on: Config.s.screenReader
    property int applied: 0                 // (the tests: how many times it acted)
    Process {
        running: true
        command: ["sh", "-c", "command -v orca"]
        onExited: code => Config.orcaAvailable = code === 0
    }
    onOnChanged: apply()
    Component.onCompleted: if (on) apply()
    function apply() {
        applied++;
        if (Config.testMode || Config.isLoginScreen) return;
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.a11y.applications", "screen-reader-enabled", on ? "true" : "false"]);
        if (on) Quickshell.execDetached(["sh", "-c", "command -v orca >/dev/null && { pgrep -x orca >/dev/null || exec setsid -f orca; }"]);
        else Quickshell.execDetached(["pkill", "-x", "orca"]);
    }
    IpcHandler {
        target: "screenreader"
        function toggle(): void { Config.s.screenReader = !Config.s.screenReader; }
    }
}
