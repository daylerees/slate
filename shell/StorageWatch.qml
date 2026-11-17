// Settings → Storage → Warn when a drive is nearly full: every ten minutes (free space is what
// changes, and a statvfs per drive costs nothing) each drive is checked, and once one has less
// than 10% (or 5 GB) left, a calm notification says so: once, until it has room again (15%).
// scripts/storage.py drives.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var warned: ({})               // mount → true, while it's still short of room
    property int checks: 0                  // (the tests)
    property string said: ""                // (the tests: the last warning's drive)
    function low(d) { return d.free < Math.max(5e9, d.size * 0.10); }
    function roomy(d) { return d.free > Math.max(7.5e9, d.size * 0.15); }
    function heard(list) {
        checks++;
        const w = Object.assign({}, warned);
        for (const d of list) {
            if (d.removable) continue;
            if (low(d) && !w[d.mount]) {
                w[d.mount] = true;
                said = d.name;
                if (!Config.testMode)
                    Quickshell.execDetached(Config.notify((d.name === "This computer" ? "Your computer" : d.name) + " is nearly full",
                        "There's " + Config.bytesText(d.free) + " left. Settings → Storage shows what's using the space, with ways to free some.",
                        { page: "storage" }));
            } else if (roomy(d) && w[d.mount]) delete w[d.mount];
        }
        warned = w;
    }
    Process {
        id: look
        command: ["python3", Quickshell.shellPath("scripts/storage.py"), "drives"]
        stdout: StdioCollector { onStreamFinished: { try { root.heard(JSON.parse(text)); } catch (e) {} } }
    }
    // (the input that makes it worth running: the setting; a look at startup too)
    Timer {
        running: Config.s.storageWarning && !Config.isLoginScreen
        interval: 600000; repeat: true; triggeredOnStart: true
        onTriggered: { look.running = false; look.running = true; }
    }
    IpcHandler {
        target: "storage"
        function check(): void { look.running = false; look.running = true; }
        // (the tests: as if the drives were these)
        function testDrives(json: string): void { if (Config.testMode) root.heard(JSON.parse(json)); }
        function state(): string { return JSON.stringify({ checks: root.checks, said: root.said, warned: Object.keys(root.warned) }); }
    }
}
