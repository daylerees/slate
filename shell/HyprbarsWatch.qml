// Hyprbars, the optional title-bar plugin (Settings → Windows → Title bars), kept honest.
// A Hyprland plugin only loads in the Hyprland it was built for, so after every Hyprland update
// Hyprbars has to be built again. This watches for that (bin/slate-build-hyprbars --status),
// keeps Config.hyprbars up to date, and does the asking:
//  - Hyprbars is chosen and floating windows need it, but it isn't loaded: the setting changes
//    to Slate's title bars (so they're never without one) and Slate asks whether to rebuild.
//    Once it's rebuilt and Hyprland has reloaded, it asks whether to switch back.
//  - Hyprland was updated but hasn't restarted: offers to rebuild now, ready for the restart.
//  - Choosing Hyprbars in Settings: its risks first, then the build.
// Builds run on their own (they outlive a Slate reload), one at a time, and wait for game mode
// to end. Nothing here runs in test mode unless a test supplies its own stand-in for the tool.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: watch
    property var confirm: null               // Slate's confirmation window (PowerConfirm.qml)
    property var welcome: null               // the Welcome window: questions wait for it to go

    readonly property string standIn: Quickshell.env("SLATE_HYPRBARS_TOOL") || ""
    readonly property string tool: standIn !== "" ? standIn : Quickshell.shellPath("bin/slate-build-hyprbars")
    readonly property bool active: !Config.isLoginScreen && (!Config.testMode || standIn !== "")
    readonly property string icon: Quickshell.shellPath("assets/icon/icon-64.png")

    // ---- What Slate has noted (kept across restarts) -----------------------------------------
    //   fallback  the Hyprland Slate switched away from Hyprbars for
    //   chosen    Hyprbars was chosen in Settings and is being built: switch to it once loaded
    //   notNow    the Hyprland "Not now" was answered for (or the build failed for): don't ask again
    //   offered   the installed Hyprland a rebuild-before-restart was offered for
    readonly property string notesPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slate/hyprbars-notes.json"
    FileView { id: notesFile; path: watch.notesPath; blockLoading: true; printErrors: false }
    property var notes: {
        try { const n = JSON.parse(notesFile.text() || "{}"); return n && typeof n === "object" ? n : {}; }
        catch (e) { return {}; }
    }
    function note(changes) {
        const n = Object.assign({}, notes, changes);
        for (const k in n) if (!n[k]) delete n[k];
        notes = n;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}" && printf %s "$1" > "$0.tmp" && mv -f "$0.tmp" "$0"', notesPath, JSON.stringify(n)]);
    }
    Binding { target: Config; property: "hyprbarsFallback"; value: !!watch.notes.fallback }

    // ---- Looking ------------------------------------------------------------------------------
    function look() { if (active && !status.running) status.running = true; else if (active) lookAgain.restart(); }
    Timer { id: lookAgain; interval: 400; onTriggered: watch.look() }
    Process {
        id: status
        running: watch.active
        command: [watch.tool, "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of text.split("\n")) { const i = line.indexOf("="); if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim(); }
                if (o.loaded === undefined) return;                  // the tool didn't answer
                const was = watch.building;
                // (just started: the tool may not have said "building" yet)
                watch.building = o.state === "building" || (was && Date.now() - watch.startedAt < 4000);
                Config.hyprbars = o;
                Config.hyprbarsKnown = true;
                if (was && !watch.building) watch.finished();
                watch.evaluate();
            }
        }
    }
    Connections {
        target: Config
        function onHyprbarsCheck() { watch.look(); }
        function onHyprbarsChoose() { watch.choose(); }
        function onHyprbarsRebuild() { watch.rebuild(); }
        function onHyprbarsReload() { Config.reloadHyprland(); }
        function onHyprbarsRemove() { watch.remove(); }
        function onAnyFloatingChanged() { watch.evaluate(); }
        function onGameModeChanged() { if (!Config.gameMode && watch.buildWaiting) watch.startBuild(); }
    }
    Connections { target: Config.s; function onTitleBarStyleChanged() { watch.evaluate(); } }

    // ---- Building -------------------------------------------------------------------------------
    property bool building: false
    property bool buildWaiting: false        // wanted, once game mode ends (a build takes a core for a minute)
    property real startedAt: 0
    Timer { running: watch.building; interval: 2000; repeat: true; onTriggered: watch.look() }
    function startBuild() {
        if (building) return;
        if (Config.gameMode) { buildWaiting = true; return; }
        buildWaiting = false;
        building = true;
        startedAt = Date.now();
        // On its own, at low priority: it carries on if Slate reloads or restarts
        Quickshell.execDetached(["sh", "-c", 'nice -n 15 "$0" >/dev/null 2>&1', tool]);
        lookAgain.restart();
    }
    // A build has just ended
    function finished() {
        const h = Config.hyprbars;
        if (h.state === "failed") {
            note({ notNow: Config.hyprbarsRunning });         // no asking again by itself
            failedNote.offline = h.error === "No internet connection";
            failedNote.command = ["notify-send", "-a", "Slate", "-i", icon, "-u", "critical", "-h", "string:x-slate-page:windows"]
                .concat(failedNote.offline ? ["-A", "retry=Retry"] : [])
                .concat(["Hyprbars couldn't be built", (h.error || "The build didn't finish") + ". Not to worry: Slate Bars are looking after your windows in the meantime."]);
            failedNote.running = false; failedNote.running = true;
        } else if (h.state === "built") {
            if (h.build === "yes" && !Config.hyprbarsLoaded) readyNotice();
            else Quickshell.execDetached(["notify-send", "-a", "Slate", "-i", icon, "-h", "string:x-slate-page:windows",
                "Hyprbars is rebuilt", "It'll be ready and waiting after your next restart."]);
        }
    }
    // Built for the running Hyprland: a Hyprland reload loads it (windows stay open)
    function readyNotice() {
        readyNote.running = false; readyNote.running = true;
    }
    Process {
        id: readyNote
        command: ["notify-send", "-a", "Slate", "-i", watch.icon, "-h", "string:x-slate-page:windows", "-A", "reload=Reload",
            "Hyprbars is ready", "Reload Hyprland whenever you like to finish up. Your windows stay open."]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "reload") Config.reloadHyprland() }
    }
    Process {
        id: failedNote
        property bool offline: false
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "retry") watch.startBuild() }
    }
    Process {
        id: offerNote
        command: ["notify-send", "-a", "Slate", "-i", watch.icon, "-h", "string:x-slate-page:windows", "-A", "rebuild=Rebuild", "-A", "later=Later",
            "Hyprland was updated", "Shall Slate rebuild Hyprbars now, so it's ready after your next restart?"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === "rebuild") watch.startBuild() }
    }
    Process { id: systemNote }

    // ---- Asking ---------------------------------------------------------------------------------
    // In Slate's confirmation window, once the login fade and the Welcome window are out of the
    // way (the window itself queues questions behind one that's already showing)
    property var asks: []
    readonly property bool clear: !!confirm && !Config.welcoming && !(welcome && welcome.shown)
    function ask(spec, yes, no) { asks = asks.concat([{ spec: spec, yes: yes, no: no }]); askSoon.restart(); }
    Timer {
        id: askSoon
        interval: 1200
        onTriggered: {
            if (watch.asks.length === 0) return;
            if (!watch.clear) { restart(); return; }
            const q = watch.asks[0];
            watch.asks = watch.asks.slice(1);
            watch.confirm.confirmWith(q.spec, q.yes, q.no || null);
            if (watch.asks.length > 0) restart();
        }
    }
    readonly property string risks: "Hyprbars is a Hyprland plugin that Slate builds on this computer. It gives every floating "
        + "window a title bar that moves with it. It stops working after each Hyprland update until it's rebuilt, which needs "
        + "a compiler, git, Hyprland's headers and an internet connection. Slate will let you know when that happens, and Slate Bars (Slate's own title bars) look after your windows until it's done."

    // ---- Deciding -------------------------------------------------------------------------------
    property bool adopted: false
    property bool askingSwitch: false
    property string askedFor: ""             // the Hyprland the rebuild question is up for
    function evaluate() {
        if (!active || !Config.hyprbarsKnown) return;
        const h = Config.hyprbars, running = Config.hyprbarsRunning;
        // Settings from before there was a choice: someone with Hyprbars working keeps it
        if (Config.titleBarStyleUnset) {
            Config.titleBarStyleUnset = false;
            if (Config.hyprbarsLoaded) Config.s.titleBarStyle = "hyprbars";
        }
        if (Config.hyprbarsLoaded) {
            // (a build from before builds were named: note which Hyprland it's for)
            if (!adopted) { adopted = true; Quickshell.execDetached([tool, "--adopt"]); }
            if (notes.chosen) {
                Config.s.titleBarStyle = "hyprbars";
                note({ chosen: false, fallback: "" });
            } else if (notes.fallback) {
                if (Config.s.titleBarStyle === "hyprbars") note({ fallback: "" });
                else if (!askingSwitch) {
                    askingSwitch = true;
                    ask({ title: "Switch back to Hyprbars?",
                          body: "Good news: Hyprbars has been rebuilt for this version of Hyprland. Your floating windows have been "
                              + "using Slate Bars in the meantime. Would you like Hyprbars back?",
                          button: "Switch to Hyprbars", cancelLabel: "Keep Slate Bars", code: 0xEB10, danger: false },
                        () => { watch.askingSwitch = false; watch.note({ fallback: "" }); Config.s.titleBarStyle = "hyprbars"; },
                        () => { watch.askingSwitch = false; watch.note({ fallback: "" }); });
                }
            }
            // Hyprland updated but not restarted: Hyprbars still works, and can be made ready
            if (Config.s.titleBarStyle === "hyprbars" && Config.hyprlandUpdated && h.next !== "yes" && !building
                    && notes.offered !== Config.hyprbarsInstalled) {
                note({ offered: Config.hyprbarsInstalled });
                offerNote.running = false; offerNote.running = true;
            }
            return;
        }
        // Not loaded. Only a concern when it's chosen and something floats
        if (Config.s.titleBarStyle !== "hyprbars" || !Config.anyFloating) return;
        Config.s.titleBarStyle = "slate";
        if (h.any !== "yes" && h.system !== "yes") return;         // never built: nothing to rebuild
        note({ fallback: running });
        if (building) return;
        if (h.build === "yes") { readyNotice(); return; }          // built already: only the reload is missing
        if (h.any !== "yes") {
            // A distro's package that doesn't match this Hyprland
            systemNote.command = ["notify-send", "-a", "Slate", "-i", icon, "-h", "string:x-slate-page:windows",
                "Hyprbars doesn't match Hyprland", "The Hyprbars from your system's package didn't load, so your floating windows are using Slate "
                + "Bars for now. Updating that package should bring it back, or Slate can build its own from Settings → Windows."];
            systemNote.running = false; systemNote.running = true;
            return;
        }
        if (notes.notNow === running || askedFor === running) return;
        askedFor = running;
        ask({ title: "Hyprbars needs rebuilding",
              body: "Hyprland was updated, and Hyprbars was built for the old version, so it can't load just now. Your floating "
                  + "windows are using Slate Bars until it's rebuilt (they take focus when clicked). Shall Slate rebuild it now? "
                  + "It takes about a minute, quietly in the background.",
              button: "Rebuild", cancelLabel: "Not now", code: 0xEB13, danger: false },
            () => { watch.askedFor = ""; watch.startBuild(); },
            () => { watch.askedFor = ""; watch.note({ notNow: running }); });
    }

    // Settings → Windows: Hyprbars picked
    function choose() {
        if (Config.hyprbarsLoaded) {
            note({ chosen: false, fallback: "" });
            Config.s.titleBarStyle = "hyprbars";
            return;
        }
        const ready = Config.hyprbarsState === "ready";
        ask({ title: "Use Hyprbars?", body: risks, button: ready ? "Use Hyprbars" : "Build and use", code: 0xEB10, danger: false },
            () => {
                watch.note({ chosen: true, fallback: "", notNow: "" });
                if (ready) watch.readyNotice(); else watch.startBuild();
            });
    }
    // Settings → Windows: Rebuild / Retry
    function rebuild() {
        // (once it's loaded again, ask whether to switch to it, unless it's already the choice)
        if (!notes.chosen && Config.s.titleBarStyle !== "hyprbars") note({ fallback: Config.hyprbarsRunning, notNow: "" });
        startBuild();
    }
    // Settings → Windows: Remove Hyprbars
    function remove() {
        ask({ title: "Remove Hyprbars?",
              body: "Your floating windows switch to Slate Bars straight away, and Slate's builds of the plugin are deleted. "
                  + "It's fully gone after your next restart, and you're welcome to build it again at any time.",
              button: "Remove", code: 0xEB41, danger: true },
            () => {
                Config.s.titleBarStyle = "slate";
                watch.note({ chosen: false, fallback: "", notNow: "", offered: "" });
                watch.buildWaiting = false;
                watch.building = false;
                removeRun.running = true;
            });
    }
    Process { id: removeRun; command: [watch.tool, "--remove"]; onExited: watch.look() }
}
