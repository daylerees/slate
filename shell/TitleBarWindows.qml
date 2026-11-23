// The windows, as Slate's own title bars need them (TitleBar.qml, one per screen): one look at
// Hyprland's list for all of them, where each used to start a `hyprctl -j clients` of its own
// seven times a second, floating window or not, locked or not.
//
// Hyprland doesn't say when a window moves, is resized or raised, so while there's a floating
// window for a bar to follow, this looks a few times a second (not while its bar is dragging it:
// the drag knows where the window is). With none, it only looks when Hyprland says something
// that could bring one: a window opening, closing, floating, changing workspace, and so on.
// Not at all while the screen's locked; once more when it's unlocked.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var bars: []             // the title bars (shell.qml's Variants: its instances)
    property var lock: null           // LockScreen: nothing to follow while locked
    readonly property bool locked: !!lock && lock.locked

    // Every window, bottom to top, as last looked at; looked() once each bar may pick from it
    property var clients: []
    signal looked(var list)

    // A bar has a floating window in front on its screen (or doesn't know its screen yet, so
    // can't tell): something that may move without Hyprland saying so
    readonly property bool following: bars.some(b => !!b.o || !b.mon)
    // A window's being moved by something other than its bar: look more often, to keep up
    readonly property bool hurried: bars.some(b => b.movingElsewhere)
    // (a bar that's dragging knows where its window is; another screen's still has to look)
    readonly property bool anyResting: bars.some(b => !b.dragging && b.sizing === "")

    Process {
        id: clientsQuery
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: root.take(text) }
        onExited: if (root.again) rerun.restart()
    }
    function take(text) {
        let list = null;
        try { list = JSON.parse(text); } catch (e) {}
        if (list) {
            clients = list;
            looked(list);
            // (the tests wait on this to know Slate has caught up: counted after the bars have picked)
            if (Config.testMode) Config.titleBarLooks++;
        }
        if (again) rerun.restart();
    }
    // Asked while a look was already under way: that one may have started before whatever
    // prompted this, so look again once it's back. (The few-times-a-second look used to cover
    // for this; with no floating window there isn't one, and a window that opened just then
    // would have got no bar)
    property bool again: false
    Timer { id: rerun; interval: 0; onTriggered: if (root.again) root.query() }
    function query() {
        if (locked) return;
        if (clientsQuery.running) { again = true; return; }
        again = false;
        clientsQuery.running = true;
    }

    Timer {
        interval: root.hurried ? 50 : 150; repeat: true
        running: root.following && root.anyResting && !root.locked
        // (the next tick will do if this one's look isn't back yet)
        onTriggered: if (!clientsQuery.running) root.query()
    }
    // What can bring a floating window in front, take it away or change which it is, that
    // Hyprland does say: at once
    // (Config.windowsChanged: those events, among them a workspace sent to another screen,
    // which takes its windows along, and a reload of Hyprland's config, which can change which float)
    Connections {
        target: Config
        enabled: root.bars.length > 0
        function onWindowsChanged() { root.query(); }
    }
    // Unlocked: whatever happened meanwhile. New bars (a workspace went floating, a screen was
    // plugged in, Slate reloaded): each asks as it starts, and once more here when all are in
    onLockedChanged: if (!locked && bars.length > 0) query()
    onBarsChanged: if (bars.length > 0) query()
}
