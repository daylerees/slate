pragma Singleton

// What Settings pages look up from the computer and that doesn't change while Slate runs (or
// changes only when Slate itself does something): the keyboard layouts there are, the time
// zones, the pointer and icon themes installed, whether the screenshot tools are there. Read
// the first time a page asks (want…), then kept: the pages used to run the same lookups every
// time they opened. A theme installed from Settings asks again (refreshThemes)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int reads: 0                        // (the tests: how many lookups have run)

    // (the keyboard layouts: Config reads them once as Slate starts, for the names it shows)
    readonly property var layouts: Config.xkbList
    function wantLayouts() {}

    property var zones: []
    function wantZones() { if (!zonesProc.done && !zonesProc.running) zonesProc.running = true; }
    Process {
        id: zonesProc
        property bool done: false
        command: [Quickshell.shellPath("bin/slate-init"), "timedate", "zones"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: {
            root.zones = text.trim().split("\n").filter(z => z !== "").map(z => ({ value: z, label: z.replace(/_/g, " ") }));
            zonesProc.done = root.zones.length > 0;
        } }
    }

    // Pointer and icon themes (scripts/icon-themes.py): kind "cursors" or "icons"
    property var cursorThemes: []
    property var iconThemes: []
    // (read again when the page opens if the list is over a minute old: a theme installed with
    // the package manager meanwhile shows up)
    function wantThemes(kind) {
        const p = kind === "cursors" ? cursorsProc : iconsProc;
        if (p.running) return;
        if (!p.done || Date.now() - p.readAt > 60000) p.running = true;
    }
    function refreshThemes(kind) {
        const p = kind === "cursors" ? cursorsProc : iconsProc;
        p.running = false; p.running = true;
    }
    Process {
        id: cursorsProc
        property bool done: false
        property real readAt: 0
        command: [Quickshell.shellPath("scripts/icon-themes.py"), "--cursors"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: { try { root.cursorThemes = JSON.parse(text); cursorsProc.done = true; cursorsProc.readAt = Date.now(); } catch (e) {} } }
    }
    Process {
        id: iconsProc
        property bool done: false
        property real readAt: 0
        command: [Quickshell.shellPath("scripts/icon-themes.py"), "--icons"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: { try { root.iconThemes = JSON.parse(text); iconsProc.done = true; iconsProc.readAt = Date.now(); } catch (e) {} } }
    }

    // The screenshot tools (Settings → Screenshots says what to install when one's missing):
    // looked for every time the page opens, as one's often installed from a terminal meanwhile
    // (a single cheap check). Taken to be there until it answers, so the page doesn't say one
    // is missing for a moment when it isn't
    property bool hasSwash: true
    property bool hasRecorder: true
    function wantTools() { if (!toolsProc.running) toolsProc.running = true; }
    Process {
        id: toolsProc
        property bool done: false
        command: ["sh", "-c", "command -v swash >/dev/null && echo swash; command -v wf-recorder >/dev/null && echo wf-recorder; true"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: {
            const have = text.split("\n");
            root.hasSwash = have.includes("swash");
            root.hasRecorder = have.includes("wf-recorder");
            toolsProc.done = true;
        } }
    }
}
