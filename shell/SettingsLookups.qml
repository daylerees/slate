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

    property var layouts: []
    function wantLayouts() { if (!layoutsProc.done && !layoutsProc.running) layoutsProc.running = true; }
    Process {
        id: layoutsProc
        property bool done: false
        command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: { try { root.layouts = JSON.parse(text); layoutsProc.done = true; } catch (e) {} } }
    }

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
    function wantThemes(kind) {
        const p = kind === "cursors" ? cursorsProc : iconsProc;
        if (!p.done && !p.running) p.running = true;
    }
    function refreshThemes(kind) {
        const p = kind === "cursors" ? cursorsProc : iconsProc;
        p.running = false; p.running = true;
    }
    Process {
        id: cursorsProc
        property bool done: false
        command: [Quickshell.shellPath("scripts/icon-themes.py"), "--cursors"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: { try { root.cursorThemes = JSON.parse(text); cursorsProc.done = true; } catch (e) {} } }
    }
    Process {
        id: iconsProc
        property bool done: false
        command: [Quickshell.shellPath("scripts/icon-themes.py"), "--icons"]
        onStarted: root.reads++
        stdout: StdioCollector { onStreamFinished: { try { root.iconThemes = JSON.parse(text); iconsProc.done = true; } catch (e) {} } }
    }

    // The screenshot tools (Settings → Screenshots says what to install when one's missing)
    property bool hasSwash: false
    property bool hasRecorder: true
    function wantTools() { if (!toolsProc.done && !toolsProc.running) toolsProc.running = true; }
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
