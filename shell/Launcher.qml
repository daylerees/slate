// Type-to-search app launcher, styled like the bar and using the dock's app tiles.
// Open/close from anywhere with:  slate ipc call launcher toggle   (or open / close)
// Open with a search typed:       slate ipc call launcher search <text>

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    // ---- Settings ----------------------------------------------------------
    // Fits small screens: never wider or taller than the screen allows
    readonly property real panelWidth: Math.max(300, Math.min(560, width - 32))
    // The grid: as tall as its rows of square cells (search box, rows, name strip), within the screen
    readonly property real gridCellSize: Math.floor((panelWidth - 42) / gridColumns)
    readonly property real panelHeight: Math.max(260, Math.min(gridMode ? 134 + gridRows * gridCellSize : 520, height - 120))
    readonly property real rowHeight: 52
    // As tall as the results need (never taller than panelHeight), so it shrinks as a search
    // narrows them: the search box and margins (and the grid's name strip), then a row per
    // result in the list or per row of icons in the grid, and at least one row
    readonly property real chromeHeight: gridMode ? 134 : 86
    readonly property real fittedHeight: Math.min(panelHeight,
        chromeHeight + Math.max(1, Math.ceil(results.length / (gridMode ? gridColumns : 1))) * (gridMode ? gridCellSize : rowHeight))
    // List or grid (Settings → Launcher → Layout). The grid shows just bigger icons; the
    // selected one's name is in a strip along the bottom of the launcher
    readonly property bool gridMode: Config.s.launcherLayout === "grid"
    // Columns and visible rows (Settings → Launcher): the columns share out the launcher's
    // width into square cells, so the icons scale with them; the rows set its height
    readonly property int gridColumns: Math.max(3, Math.min(10, Config.s.launcherColumns))
    readonly property int gridRows: Math.max(2, Math.min(8, Config.s.launcherRows))
    // From the launcher's width and the columns, not the view's cells: switching layouts, the
    // cells briefly span the whole row, which made icons huge (or stretched) for a moment
    readonly property real gridTile: Math.round(gridCellSize * 0.62)
    readonly property real tileSize: 36
    readonly property int fadeMs: 200
    readonly property real dropDistance: 18   // how far the panel drops as it fades in
    readonly property color barColor: Config.surface(Config.tint("#0f1216"))      // same as the top bar
    readonly property color fieldColor: Config.raised(Config.tint("#1d222a"))    // bar capsules
    readonly property color selectColor: Config.tint("#262c35")
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent        // theme accent (Settings → Appearance)
    readonly property color accentText: Config.tint("#12151a")      // text on the accent
    readonly property int slideMs: 140
    readonly property string fontFamily: Config.s.fontFamily   // Settings → Appearance → Fonts
    readonly property string tileScript: Config.tileScript
    readonly property string tileDir: Config.tileDir

    // ---- Open / close ------------------------------------------------------
    property bool shown: false
    property real openedAt: 0
    property bool slideHighlight: false
    // Last pointer position (window coordinates) seen over the list. Hover only changes
    // the selection when the pointer itself moves, not when rows slide under it.
    property var lastPointer: null
    property int openedOnWorkspace: -1
    // Typed in since opening: only then does the launcher animate its height. Otherwise
    // (the app list still filling in on the first opening after Slate starts) it grew in
    // steps as the apps arrived
    property bool typed: false
    function openLauncher() {
        screen = Config.focusedScreen;     // open on the focused screen
        lastPointer = null;
        openedOnWorkspace = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
        slideHighlight = false;
        Qt.callLater(() => root.slideHighlight = true);
        search.text = "";
        typed = false;
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        openedAt = Date.now();
        shown = true;
    }
    function closeLauncher() { shown = false; }

    IpcHandler {
        target: "launcher"
        function toggle(): void { if (root.shown) root.closeLauncher(); else root.openLauncher(); }
        function open(): void { root.openLauncher(); }
        function close(): void { root.closeLauncher(); }
        function search(query: string): void { root.openLauncher(); search.text = query; }
        // Launch whatever is selected (Hyprland's Super+Enter uses this after
        // switching to an empty workspace, so the app opens there)
        function launchSelected(): void { root.launch(root.results[list.currentIndex]); }
        // Open the selected app on an empty workspace (Super+Enter)
        function launchOnNewWorkspace(): void { root.launchOnNewWorkspace(root.results[list.currentIndex]); }
        function launchLeft(): void { root.launchBeside(root.results[list.currentIndex], -1); }
        function launchRight(): void { root.launchBeside(root.results[list.currentIndex], 1); }
    }

    // Switching workspace closes the launcher. Changes right after opening are
    // ignored, so "jump to an empty workspace and open the launcher" still works.
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
            if (!root.shown || id === root.openedOnWorkspace) return;   // not an actual switch
            if (Date.now() - root.openedAt > 400) root.closeLauncher();
            else root.openedOnWorkspace = id;   // switched just before opening (Super+Alt+Down)
        }
    }

    // Fade in and out; the window stays mapped until the fade-out finishes
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }

    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown && !releasing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---- Apps --------------------------------------------------------------
    readonly property var apps: {
        const seen = new Set();
        return DesktopEntries.applications.values
            .filter(a => !a.noDisplay && a.name && !seen.has(a.id) && seen.add(a.id))
            .concat([slateSettingsApp])
            .sort((a, b) => a.name.localeCompare(b.name));
    }
    // Lock / suspend / log out / restart / shut down: found by searching, ranked with apps
    // (kept out of the list shown before you type)
    readonly property var sessionActions: [
        { action: "lock", id: "slate-lock", name: "Lock", genericName: "Lock screen", comment: "Lock the screen (Super+L)", keywords: ["lock", "screen", "away"], icon: 0xEAE2 },
        { action: "suspend", id: "slate-suspend", name: "Suspend", genericName: "Sleep", comment: "Lock, then put the computer to sleep", keywords: ["sleep", "suspend", "standby"], icon: 0xF228 },
        { action: "logout", id: "slate-logout", name: "Log out", genericName: "Sign out", comment: "End your session (asks first)", keywords: ["logout", "log off", "sign out", "exit", "session"], icon: 0xEBA8 },
        { action: "reboot", id: "slate-reboot", name: "Restart", genericName: "Reboot", comment: "Restart the computer (asks first)", keywords: ["reboot", "restart"], icon: 0xEB13 },
        { action: "shutdown", id: "slate-shutdown", name: "Shut down", genericName: "Power off", comment: "Turn the computer off (asks first)", keywords: ["shutdown", "power off", "turn off", "halt"], icon: 0xEB0D, danger: true }
    ]

    // Slate's settings, listed and searched like an installed app
    readonly property var slateSettingsApp: ({
        setting: true, app: true, id: "slate-settings", name: "Slate Settings", page: "overview",
        genericName: "Settings", comment: "Theme, wallpaper, menu bar, dock, notifications and more",
        keywords: ["settings", "preferences", "configuration", "control panel", "options", "slate"]
    })

    function score(a, q) {
        const name = a.name.toLowerCase();
        if (name.startsWith(q)) return 0;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 1;
        if (name.includes(q)) return 2;
        const extra = [a.genericName, a.comment, a.id, (a.keywords || []).join(" ")].join(" ").toLowerCase();
        if (extra.includes(q)) return 3;
        return -1;
    }
    // ---- Calculator ----------------------------------------------------------
    // When the search contains a maths operator and reads as a sum, the answer
    // shows as the first result; Enter (or a click) copies it.
    // Understands + - * / % ^ ( ), × ÷, decimals, sqrt sin cos tan asin acos atan
    // log (base 10) ln abs round floor ceil, and pi / e. Trig works in degrees.
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    function calculate(text) {
        const src = text.replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, "").replace(/\*\*/g, "^").trim();
        if (!/[0-9]/.test(src) || !/[-+*\/%^()]/.test(src)) return null;
        const toks = src.match(/\d*\.?\d+(?:e[-+]?\d+)?|[a-z]+|[-+*\/%^()]|\S/gi);
        if (!toks) return null;
        let i = 0;
        const peek = () => toks[i], next = () => toks[i++];
        const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;
        const fns = { sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
            ln: Math.log, log: Math.log10, sin: x => Math.sin(rad(x)), cos: x => Math.cos(rad(x)), tan: x => Math.tan(rad(x)),
            asin: x => deg(Math.asin(x)), acos: x => deg(Math.acos(x)), atan: x => deg(Math.atan(x)) };
        const consts = { pi: Math.PI, e: Math.E };
        function expr() {          // + and -
            let v = term();
            while (peek() === "+" || peek() === "-") v = next() === "+" ? v + term() : v - term();
            return v;
        }
        function term() {          // * / %, and implied multiply like 2(3) or 2pi
            let v = unary();
            for (;;) {
                const t = peek();
                if (t === "*" || t === "/" || t === "%") { next(); const r = unary(); v = t === "*" ? v * r : t === "/" ? v / r : v % r; }
                else if (t === "(" || (t && /^[a-z]/i.test(t))) v *= unary();
                else return v;
            }
        }
        function unary() {
            if (peek() === "-") { next(); return -unary(); }
            if (peek() === "+") { next(); return unary(); }
            return power();
        }
        function power() {         // ^ binds tightest and groups to the right
            const b = atom();
            if (peek() === "^") { next(); return Math.pow(b, unary()); }
            return b;
        }
        function atom() {
            const t = next();
            if (t === undefined) throw "end";
            if (t === "(") { const v = expr(); if (next() !== ")") throw "paren"; return v; }
            if (/^\d*\.?\d+(e[-+]?\d+)?$/i.test(t)) return parseFloat(t);
            const w = t.toLowerCase();
            if (consts[w] !== undefined) return consts[w];
            if (fns[w]) { return fns[w](power()); }
            throw "token";
        }
        try {
            const v = expr();
            if (i !== toks.length || !isFinite(v)) return null;
            return v;
        } catch (e) { return null; }
    }
    function formatNumber(v) {
        if (Math.abs(v) >= 1e15 || (v !== 0 && Math.abs(v) < 1e-9)) return v.toExponential(6).replace(/\.?0+e/, "e");
        return String(Number(v.toPrecision(12)));
    }
    readonly property var calcResult: {
        const v = calculate(search.text);
        return v === null ? null : { calc: true, id: "", name: formatNumber(v), expr: search.text.trim() };
    }

    readonly property var results: (calcResult ? [calcResult] : []).concat(appResults, settingResults)

    // ---- Slate settings (after apps) ---------------------------------------------
    // Pages and individual settings (SettingsIndex), opening Settings at the setting
    readonly property var pageIcons: SettingsIndex.pageIcons
    readonly property var pageNames: SettingsIndex.pageNames
    readonly property var settingResults: SettingsIndex.search(search.text, 4).map(e => ({
        setting: true, id: "setting:" + e.page + ":" + e.label, name: e.label, page: e.page,
        comment: "Settings → " + pageNames[e.page] + (e.group && e.group !== e.label ? " → " + e.group : ""), icon: pageIcons[e.page]
    }))
    readonly property var appResults: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return apps.slice().sort((x, y) => uses(y) - uses(x) || x.name.localeCompare(y.name));
        return apps.concat(sessionActions)
            .map(a => ({ a: a, s: score(a, q) }))
            .filter(x => x.s >= 0)
            .sort((x, y) => x.s - y.s || uses(y.a) - uses(x.a) || x.a.name.localeCompare(y.a.name))
            .map(x => x.a);
    }

    // How often each app has been opened from here (for usage sorting)
    property var counts: ({})
    FileView {
        id: usage
        path: Quickshell.env("HOME") + "/.local/state/slate/launcher.json"
        blockLoading: true
        onLoaded: { try { root.counts = JSON.parse(text()).counts || {}; } catch (e) {} }
    }
    function uses(a) { return Config.s.launcherSortByUsage ? (counts[a.id] || 0) : 0; }

    function launch(entry) {
        if (!entry) return;
        if (entry.calc) {          // calculator: copy the answer
            Quickshell.execDetached(["wl-copy", entry.name]);
            closeLauncher();
            return;
        }
        if (entry.app) {           // count it like an app, for usage sorting
            const c2 = Object.assign({}, counts); c2[entry.id] = (c2[entry.id] || 0) + 1; counts = c2;
            usage.setText(JSON.stringify({ counts: c2 }, null, 1));
        }
        if (entry.action) {        // lock / suspend / log out / restart / shut down
            const slate = Quickshell.shellPath("bin/slate");
            if (entry.action === "lock") Quickshell.execDetached([slate, "ipc", "call", "lock", "lock"]);
            else if (entry.action === "suspend") Quickshell.execDetached(["sh", "-c", "\"$0\" ipc call lock lock; sleep 0.6; systemctl suspend", slate]);
            else Quickshell.execDetached([slate, "ipc", "call", "power", "confirm", entry.action]);   // asks first
            closeLauncher();
            return;
        }
        if (entry.setting) {       // a Slate setting: open Settings on its page
            // Straight to the setting on its page (just the page for the Slate Settings app itself)
            Quickshell.execDetached(entry.app
                ? [Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "page", entry.page]
                : [Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "find", entry.page, entry.name]);
            closeLauncher();
            return;
        }
        const c = Object.assign({}, counts);
        c[entry.id] = (c[entry.id] || 0) + 1;
        counts = c;
        usage.setText(JSON.stringify({ counts: c }, null, 1));
        // The secret workspace is showing: open the app there, not on the workspace behind it
        const special = specialShown();
        if (special !== "" && entry.command && entry.command.length > 0) launchOn(entry, special);
        else entry.execute();
        closeLauncher();
    }

    // ---- The secret (special) workspace, per monitor ("" = hidden), from Hyprland's events
    property var specialOpen: ({})
    function specialShown() {
        const mon = Hyprland.focusedMonitor;
        return mon ? (specialOpen[mon.name] || "") : "";
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // The app we started for the secret workspace has its window: focus it, which
            // shows that workspace again (launching moves focus back to the workspace behind
            // it, which hides the secret one)
            if (event.name === "openwindow" && root.specialTarget !== "") {
                const f = event.data.split(",");             // address,workspace,class,title
                if (f[1] === root.specialTarget) {
                    root.specialTarget = "";
                    Quickshell.execDetached(["hyprctl", "dispatch",
                        "function() hl.dispatch(hl.dsp.focus({ window = 'address:0x" + f[0] + "' })) end"]);
                }
                return;
            }
            if (event.name !== "activespecial") return;     // "special:name,monitor"
            const i = event.data.lastIndexOf(",");
            const o = Object.assign({}, root.specialOpen);
            o[event.data.slice(i + 1)] = event.data.slice(0, i);
            root.specialOpen = o;
        }
    }
    Process {
        // Already showing when Slate starts
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = {};
                    for (const m of JSON.parse(text)) o[m.name] = (m.specialWorkspace && m.specialWorkspace.name) || "";
                    root.specialOpen = o;
                } catch (e) {}
            }
        }
    }
    // Waiting for a window on the secret workspace (cleared after a while if none comes)
    property string specialTarget: ""
    Timer { id: specialTargetTimeout; interval: 20000; onTriggered: root.specialTarget = "" }
    // Start an app through Hyprland with a rule putting its window on that workspace
    function launchOn(entry, workspace) {
        specialTarget = workspace;
        specialTargetTimeout.restart();
        const q = a => "'" + String(a).replace(/'/g, "'\\''") + "'";
        let cmd = entry.command.map(q).join(" ");
        if (entry.workingDirectory) cmd = "cd " + q(entry.workingDirectory) + " && " + cmd;
        const lua = (entry.runInTerminal ? "TERMINAL .. ' -e ' .. " : "") + "[==[" + cmd + "]==]";
        // "silent": just put the window there. Without it Hyprland also switches to that
        // workspace, and switching to the secret one while it's showing hides it
        Quickshell.execDetached(["hyprctl", "dispatch",
            "function() hl.exec_cmd(" + lua + ", { workspace = [==[" + workspace + " silent]==] }) end"]);
    }
    // Close first: Hyprland won't switch workspace while the launcher holds the
    // keyboard. Then jump to an empty workspace, then start the app there.
    property var pendingEntry: null
    // While true the dock stays hidden, so it doesn't pop up on the empty workspace
    // before the new app's window arrives
    property bool launchingNew: false
    Timer { id: launchingNewTimeout; interval: 4000; onTriggered: root.launchingNew = false }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { if (root.launchingNew && !root.pendingEntry && Hyprland.activeToplevel) root.launchingNew = false; }
    }

    // Where to open it: a new workspace after the last one in use (Super+Enter; newWorkspace
    // in workspaces.lua, or the first empty one on a Hyprland config without it), or one directly to
    // the left / right of the current workspace (Left / Right on an app; see
    // besideWorkspace in ~/.config/hypr/config/workspaces.lua)
    readonly property string newTarget: '(newWorkspace and newWorkspace() or "emptym")'
    property string pendingTarget: newTarget
    function launchBeside(entry, dir) {
        if (!entry || entry.calc || entry.setting || entry.action) return;
        pendingTarget = "besideWorkspace(" + (dir > 0 ? 1 : -1) + ")";
        startNewWorkspaceLaunch(entry);
    }
    function launchOnNewWorkspace(entry) {
        if (!entry || entry.calc || entry.setting || entry.action) return;
        pendingTarget = newTarget;
        startNewWorkspaceLaunch(entry);
    }
    function startNewWorkspaceLaunch(entry) {
        pendingEntry = entry;
        launchingNew = true;
        launchingNewTimeout.restart();
        releasing = true;          // let go of the keyboard but stay on screen...
        newWsTimer.restart();      // ...then switch and fade out together
    }
    property bool releasing: false
    Timer {
        id: newWsTimer
        interval: 40
        onTriggered: {
            Quickshell.execDetached(["hyprctl", "dispatch", "function() fadeTo(hl.dsp.focus({ workspace = " + root.pendingTarget + " })) end"]);   // crossfade (see animations.lua)
            root.closeLauncher();
            root.releasing = false;
            newWsLaunch.restart();
        }
    }
    Timer {
        id: newWsLaunch
        interval: 150
        onTriggered: { if (root.pendingEntry) root.launch(root.pendingEntry); root.pendingEntry = null; }
    }

    function capitalised(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""; }

    // Click outside the panel to close
    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        onClicked: root.closeLauncher()
    }

    Rectangle {
        id: panel
        width: root.panelWidth
        // Shrinks and grows with the results, smoothly; the top stays put (where a full-height
        // launcher's would be), so the search box doesn't move while typing
        height: root.fittedHeight
        Behavior on height { enabled: root.shown && root.typed; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - root.panelHeight) / 2)
        radius: 18
        color: root.barColor
        opacity: root.fade
        scale: 0.98 + 0.02 * root.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        // Soft drop shadow so it stands out over windows
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: !Config.glass
            shadowColor: "#000000"
            shadowOpacity: 0.45
            shadowBlur: 1.0
            shadowVerticalOffset: 8
            blurMax: 48
        }
        transform: Translate { y: -root.dropDistance * (1 - root.fade) }

        // Swallow clicks so they don't close the launcher
        MouseArea { anchors.fill: parent }

        // ---- Search box --------------------------------------------------
        Rectangle {
            id: field
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 44
            radius: 10
            color: root.fieldColor

            // Magnifying glass
            Item {
                id: glass
                width: 18; height: 18
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                Rectangle {
                    x: 0; y: 0
                    width: 13; height: 13; radius: 6.5
                    color: "transparent"
                    border.color: root.dimTextColor
                    border.width: 2
                }
                Rectangle {
                    x: 10.5; y: 12
                    width: 7; height: 2; radius: 1
                    color: root.dimTextColor
                    rotation: 45
                    transformOrigin: Item.Left
                }
            }

            Text {
                anchors { left: glass.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Search apps"
                color: root.dimTextColor
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                visible: search.text === ""
            }

            TextInput {
                id: search
                anchors { left: glass.right; right: parent.right; leftMargin: 10; rightMargin: 14; verticalCenter: parent.verticalCenter }
                color: root.textColor
                selectionColor: root.accent
                selectedTextColor: root.barColor
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                focus: root.shown
                clip: true
                onTextChanged: { list.currentIndex = 0; if (root.shown) root.typed = true; }

                Keys.onPressed: event => {
                    const n = list.count;
                    const i = list.currentIndex;
                    // Items per row (1 in the list) and per page
                    const across = root.gridMode ? list.columns : 1;
                    const page = Math.max(1, Math.floor(list.height / list.cellHeight) - 1) * across;
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    switch (event.key) {
                    case Qt.Key_Escape: root.closeLauncher(); break;
                    // Open the app on a new workspace to the left / right (Ctrl in the grid, where
                    // the arrows move between apps)
                    case Qt.Key_Left:
                        if (root.gridMode && !ctrl) list.currentIndex = Math.max(0, i - 1);
                        else root.launchBeside(root.results[i], -1);
                        break;
                    case Qt.Key_Right:
                        if (root.gridMode && !ctrl) list.currentIndex = Math.min(n - 1, i + 1);
                        else root.launchBeside(root.results[i], 1);
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter: root.launch(root.results[i]); break;
                    case Qt.Key_Down: list.currentIndex = Math.min(n - 1, i + across); break;
                    case Qt.Key_Up: list.currentIndex = Math.max(0, i - across); break;
                    case Qt.Key_Tab: list.currentIndex = Math.min(n - 1, i + 1); break;
                    case Qt.Key_Backtab: list.currentIndex = Math.max(0, i - 1); break;
                    case Qt.Key_PageDown: list.currentIndex = Math.min(n - 1, i + page); break;
                    case Qt.Key_PageUp: list.currentIndex = Math.max(0, i - page); break;
                    default: return;
                    }
                    event.accepted = true;
                }
            }
        }

        // ---- Apps: a list, or a grid (Settings → Launcher → Layout) ---------
        // One GridView for both: in the list it has a single full-width column
        GridView {
            id: list
            anchors { top: field.bottom; left: parent.left; right: parent.right; bottom: root.gridMode ? nameStrip.top : parent.bottom; margins: 14; rightMargin: listFits ? 14 : 28 }
            // Rows use the full width when they all fit (no scrollbar); the grid's cells are a fixed size
            readonly property bool listFits: !root.gridMode && contentHeight <= height
            anchors.bottomMargin: root.gridMode ? 4 : 14
            clip: true
            // A fresh copy when the layout changes, so every item is made again for it (items
            // made for the list don't lay themselves out again properly as grid cells)
            model: root.gridMode ? root.results.slice() : root.results
            SmoothWheel { flick: list }
            boundsBehavior: Flickable.StopAtBounds
            readonly property int columns: root.gridMode ? root.gridColumns : 1
            cellWidth: root.gridMode ? root.gridCellSize : width
            cellHeight: root.gridMode ? root.gridCellSize : root.rowHeight
            // Selection slides between items instead of jumping
            highlightFollowsCurrentItem: false
            // The selected item shaded in the accent colour
            highlight: Rectangle {
                // In the grid, just a little bigger than the icon, centred in its cell
                readonly property real gridBox: Math.round(root.gridTile * 1.24)
                width: root.gridMode ? gridBox : list.cellWidth
                height: root.gridMode ? gridBox : list.cellHeight
                radius: root.gridMode ? gridBox * 0.22 : 10
                color: root.accent
                Gloss { radius: parent.radius }   // glass: a sheen on the selection
                x: (list.currentItem ? list.currentItem.x : 0) + (root.gridMode ? (list.cellWidth - gridBox) / 2 : 0)
                y: (list.currentItem ? list.currentItem.y : 0) + (root.gridMode ? (list.cellHeight - gridBox) / 2 : 0)
                // Smoothed: a new target (the next key press) carries on at the current speed,
                // where an eased slide restarted fast on each press and lurched when keys repeat
                Behavior on x {
                    enabled: root.slideHighlight
                    SmoothedAnimation { duration: root.slideMs; velocity: -1 }
                }
                Behavior on y {
                    enabled: root.slideHighlight
                    SmoothedAnimation { duration: root.slideMs; velocity: -1 }
                }
            }

            // Keep the selection on screen: scroll just enough when it moves past an edge
            SmoothedAnimation {
                id: scrollAnim
                target: list
                property: "contentY"
                duration: root.slideMs
                velocity: -1
            }
            onCurrentIndexChanged: {
                if (currentIndex < 0) return;
                const top = Math.floor(currentIndex / columns) * cellHeight;
                const bottom = top + cellHeight;
                // From where it's already heading (keys pressed quickly), so the scroll carries on
                const from = scrollAnim.running ? scrollAnim.to : contentY;
                let to = from;
                if (top < from) to = top;
                else if (bottom > from + height) to = bottom - height;
                if (to === from) return;
                if (root.slideHighlight) {
                    scrollAnim.to = to;
                    scrollAnim.restart();       // a smoothed restart keeps its current speed
                } else {
                    scrollAnim.stop();
                    contentY = to;
                }
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool calc: !!modelData.calc
                readonly property bool setting: !!modelData.setting
                readonly property bool action: !!modelData.action
                // Rows drawn with an icon glyph rather than an app tile
                readonly property bool glyphTile: (setting && !modelData.app) || action
                readonly property string tilePath: root.tileDir + "/" + modelData.id.replace(/[^A-Za-z0-9._-]/g, "_") + ".png"
                readonly property string detail: calc ? modelData.expr + " · Enter to copy" : (modelData.genericName || modelData.comment || "")
                readonly property bool selected: GridView.isCurrentItem
                // The list's text and calculator tile sit on the accent while selected; their
                // colours fade over as the highlight slides in and out
                readonly property bool onAccent: selected && !root.gridMode
                readonly property int fadeMs: root.slideHighlight ? root.slideMs : 0
                property int version: 0
                property string tried: ""          // drawn once per icon file (a new icon style is a new file)
                width: list.cellWidth
                height: list.cellHeight

                // List: the tile on the left of the row. Grid: a bigger tile in the middle of its cell
                Image {
                    id: tile
                    // Placed by x/y, not anchors: switching layouts by changing anchors could leave it
                    // briefly pinned to both the row's left and its centre, which stretched it to
                    // most of the row's width, and it stayed that size
                    width: root.gridMode ? root.gridTile : root.tileSize; height: width
                    x: root.gridMode ? Math.round((parent.width - width) / 2) : 10
                    y: Math.round((parent.height - height) / 2)
                    visible: !row.calc && !row.setting && !row.action
                    source: row.calc || row.setting || row.action ? "" : "file://" + row.tilePath + "?v=" + row.version + "." + Config.tileVersion
                    sourceSize: Qt.size(192, 192)
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                    onStatusChanged: if (!row.calc && !row.setting && !row.action && status === Image.Error && !gen.running && row.tried !== row.tilePath) { row.tried = row.tilePath; gen.running = true; }
                    // The tile behind, in the theme's colour. Solid on the highlight: with glass it's
                    // see-through, and the accent behind would show through it
                    IconPlate {
                        anchors.fill: parent; z: -1
                        color: row.selected && Config.glass ? Config.iconTileFor(app, Config.tint("#2a313c"), true) : Config.iconTileFor(app, Config.iconPlateColor)
                        Behavior on color { ColorAnimation { duration: row.fadeMs } }
                    }
                }
                // Calculator tile
                Rectangle {
                    visible: row.calc
                    anchors.fill: tile
                    radius: 9
                    // Swapped round on the accent highlight, so it doesn't vanish into it
                    color: row.onAccent ? root.accentText : root.accent
                    Behavior on color { ColorAnimation { duration: row.fadeMs } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB80)
                        color: row.onAccent ? root.accent : root.accentText
                        Behavior on color { ColorAnimation { duration: row.fadeMs } }
                        font.family: tabler.name
                        font.pixelSize: 20
                    }
                }
                // Slate Settings (the app-like entry): Slate's app icon
                Image {
                    visible: row.setting && !!row.modelData.app
                    anchors.fill: tile
                    source: visible ? "file://" + Quickshell.shellPath("assets/icon/settings-128.png") : ""
                    sourceSize: Qt.size(128, 128)
                    smooth: true; mipmap: true
                }
                // Settings / session action tile: an icon glyph
                Rectangle {
                    visible: row.glyphTile
                    anchors.fill: tile
                    radius: 9
                    // Solid on the highlight: with glass it's see-through, and its icon would
                    // vanish into the accent behind it
                    color: row.selected && Config.glass ? Config.tint("#1d222a") : root.fieldColor
                    Behavior on color { ColorAnimation { duration: row.fadeMs } }
                    border.width: 1; border.color: root.selectColor
                    Text {
                        anchors.centerIn: parent
                        text: row.glyphTile ? String.fromCodePoint(row.modelData.icon) : ""
                        // A setting's icon takes its page's colour in colourful mode, as in Settings
                        color: row.modelData.danger ? Config.tint("#f28b8b")
                            : row.setting ? Config.pageColour(row.modelData.page) : root.accent
                        font.family: tabler.name
                        font.pixelSize: 19
                    }
                }
                // Draw the tile if this app doesn't have one yet
                Process {
                    id: gen
                    command: Config.tileCommand(row.modelData.id, row.tilePath)
                    onExited: row.version++
                }

                // Name and description (the list only: the grid shows them in the strip at the bottom)
                Column {
                    visible: !root.gridMode
                    anchors { left: tile.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.calc ? "= " + row.modelData.name : root.capitalised(row.modelData.name)
                        color: row.onAccent ? root.accentText : root.textColor
                        Behavior on color { ColorAnimation { duration: row.fadeMs } }
                        font.family: root.fontFamily
                        font.pixelSize: row.calc ? 16 : 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: row.calc || row.setting || row.action || (Config.s.launcherDescriptions && row.detail !== "" && row.detail !== row.modelData.name)
                        text: row.calc ? row.detail : root.capitalised(row.detail)
                        color: row.onAccent ? Qt.rgba(root.accentText.r, root.accentText.g, root.accentText.b, 0.72) : root.dimTextColor
                        Behavior on color { ColorAnimation { duration: row.fadeMs } }
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                ClickArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: m => {
                        const g = mapToItem(null, m.x, m.y);
                        const last = root.lastPointer;
                        root.lastPointer = Qt.point(g.x, g.y);
                        if (!last || Math.abs(g.x - last.x) + Math.abs(g.y - last.y) < 2) return;
                        if (list.currentIndex !== row.index) list.currentIndex = row.index;
                    }
                    onClicked: root.launch(row.modelData)
                }
            }
        }

        // Grid: the selected app's name (and what it is) along the bottom of the launcher
        Item {
            id: nameStrip
            visible: root.gridMode
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
            height: root.gridMode ? 44 : 0
            readonly property var item: root.results[list.currentIndex] ?? null
            readonly property string detail: !item ? "" : item.calc ? item.expr + " · Enter to copy"
                : (item.genericName || item.comment || "")
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: root.selectColor }
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: 2; leftMargin: 6; rightMargin: 6 }
                spacing: 1
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: !nameStrip.item ? "" : nameStrip.item.calc ? "= " + nameStrip.item.name : root.capitalised(nameStrip.item.name)
                    color: root.textColor
                    font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: nameStrip.detail !== "" && Config.s.launcherDescriptions
                    horizontalAlignment: Text.AlignHCenter
                    text: nameStrip.item && nameStrip.item.calc ? nameStrip.detail : root.capitalised(nameStrip.detail)
                    color: root.dimTextColor
                    font.family: root.fontFamily; font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }

        // Scrollbar (ThinScrollbar, as everywhere), only when the list overflows
        ThinScrollbar {
            id: scrollbar
            flick: list
            color: root.textColor
            anchors { top: list.top; bottom: list.bottom; left: list.right; leftMargin: 8 }
        }

        // Shadow at the bottom while there's more to scroll to
        Rectangle {
            anchors { left: list.left; right: list.right; bottom: list.bottom }
            height: 36
            // Fades with the distance from the end, gone just as you reach it
            opacity: Math.max(0, Math.min(1, (list.originY + list.contentHeight - list.height - list.contentY) / 24))
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: root.barColor }
            }
        }

        Text {
            anchors.centerIn: list
            visible: list.count === 0
            text: "No apps match"
            color: root.dimTextColor
            font.family: root.fontFamily
            font.pixelSize: 14
        }
    }
}
