// Type-to-search app launcher, styled like the bar and using the dock's app tiles.
// Open/close from anywhere with:  slate ipc call launcher toggle   (or open / close)
// Open with a search typed:       slate ipc call launcher search <text>

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth

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

    // ---- Open / close ------------------------------------------------------
    property var notifs: null            // Notifications (for the Do Not Disturb toggle), from shell.qml
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
        // Start an app by its desktop entry's id (as the launcher would: counted, and on the
        // secret workspace when that's showing). Only an app: no command, file or address
        function launch(id: string): string {
            const app = DesktopEntries.applications.values.find(a => a.id === id && !a.noDisplay);
            if (!app) return "unknown";
            root.launch(app);
            return "ok";
        }
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
    Behavior on fade { NumberAnimation { duration: Config.ms(root.fadeMs); easing.type: Easing.OutCubic } }

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
        return Config.s.launcherFuzzy ? fuzzyScore(name, q) : -1;
    }

    // ---- Forgiving search (Settings → Launcher → Forgiving search) ---------------------
    // Initials ("gc" → GNOME Calculator, "vsc" → Visual Studio Code) and a slip or two in a
    // word ("fierfox" → Firefox): after every exact match
    function fuzzyScore(name, q) {
        const words = name.split(/[\s\-_.]+/).filter(w => w !== "");
        if (q.length >= 2 && words.map(w => w[0]).join("").startsWith(q)) return 4;
        if (q.length >= 4) {
            const allowed = q.length >= 8 ? 2 : 1;
            for (const w of words)
                if (w.length >= q.length - 1 && editDistance(w.slice(0, q.length), q) <= allowed) return 5;
        }
        return -1;
    }
    // How many letters differ between two words (a swap of neighbours counts as one)
    function editDistance(a, b) {
        const d = [];
        for (let i = 0; i <= a.length; i++) { d.push([i]); }
        for (let j = 1; j <= b.length; j++) d[0][j] = j;
        for (let i = 1; i <= a.length; i++)
            for (let j = 1; j <= b.length; j++) {
                const cost = a[i - 1] === b[j - 1] ? 0 : 1;
                d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
            }
        return d[a.length][b.length];
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

    // What's typed, and what kind of search it is: "> command" runs it, ":name" finds emoji,
    // anything else searches everything (each part can be switched off in Settings → Launcher)
    readonly property string query: search.text.trim()
    readonly property string mode: query.startsWith(">") && Config.s.launcherCommands ? "command"
        : query.startsWith(":") && Config.s.launcherEmoji ? "emoji" : "normal"
    readonly property var results: mode === "command" ? commandResults
        : mode === "emoji" ? emojiResults
        : (calcResult ? [calcResult] : []).concat(convertResult ? [convertResult] : [], appResults, actionResults,
            windowResults, toggleResults, settingResults, fileResults, webResults)

    // ---- The list's rows, kept in step with the results -------------------------------
    // Each result has a key that stays the same while it's in the results (its kind, id and
    // name), and the list holds just those keys: typing a letter adds, removes and moves rows,
    // rather than handing the list a new array that made it draw every row again (and every
    // icon flash) on each key. A row looks its result up by key, so its text can still change
    // (the calculator's answer, a toggle's state) without the row being made again.
    ListModel { id: resultModel }
    function keyOf(r) {
        const kind = r.kind || (r.calc ? "calc" : r.action ? "session" : r.setting ? "setting" : "app");
        return kind === "calc" ? "calc" : kind + ":" + (r.id || "") + ":" + r.name;
    }
    readonly property var resultKeys: {
        const seen = {};
        return results.map(r => { const k = keyOf(r); seen[k] = (seen[k] || 0) + 1; return seen[k] > 1 ? k + "#" + seen[k] : k; });
    }
    readonly property var resultByKey: {
        const m = {};
        resultKeys.forEach((k, i) => m[k] = results[i]);
        return m;
    }
    property string syncedQuery: ""
    onResultKeysChanged: syncResults()
    onGridModeChanged: { resultModel.clear(); syncResults(); }     // a layout's rows are made for it
    function syncResults() {
        const keys = resultKeys, wanted = new Set(keys);
        for (let i = resultModel.count - 1; i >= 0; i--)
            if (!wanted.has(resultModel.get(i).rid)) resultModel.remove(i);
        for (let i = 0; i < keys.length; i++) {
            if (i < resultModel.count && resultModel.get(i).rid === keys[i]) continue;
            let j = -1;
            for (let k = i + 1; k < resultModel.count; k++) if (resultModel.get(k).rid === keys[i]) { j = k; break; }
            if (j >= 0) resultModel.move(j, i, 1);
            else resultModel.insert(i, { rid: keys[i] });
        }
        // A new search starts at the top
        if (syncedQuery !== search.text) {
            syncedQuery = search.text;
            list.currentIndex = 0;
            list.positionViewAtBeginning();
        }
    }
    Component.onCompleted: syncResults()

    // ---- App actions (Settings → Launcher → App actions) -------------------------------
    // What an app offers besides opening (Firefox's New Private Window and so on): its own
    // when its name is typed, or found by name ("private")
    readonly property var actionResults: {
        const q = query.toLowerCase();
        if (mode !== "normal" || !Config.s.launcherActions || q.length < 2) return [];
        const out = [];
        for (const a of apps) {
            if (!a.actions || a.actions.length === 0) continue;
            const ofApp = a.name.toLowerCase().startsWith(q);
            for (const act of a.actions) {
                const n = (act.name || "").toLowerCase();
                if (!ofApp && !n.includes(q)) continue;
                out.push({ kind: "appaction", id: a.id, name: act.name, comment: a.name, run: () => act.execute() });
                if (out.length >= 6) return out;
            }
        }
        return out;
    }

    // ---- Open windows (Settings → Launcher → Open windows) -----------------------------
    // A window by its title (or its app's name): Enter goes to it, wherever it is
    readonly property var windowResults: {
        const q = query.toLowerCase();
        if (mode !== "normal" || !Config.s.launcherWindows || q.length < 2) return [];
        const out = [];
        for (const t of ToplevelManager.toplevels.values) {
            const e = Config.appEntry(t.appId);
            const appName = e ? e.name : (t.appId || "");
            if (!((t.title || "") + " " + appName).toLowerCase().includes(q)) continue;
            out.push({ kind: "window", id: e ? e.id : (t.appId || ""), name: t.title || appName,
                comment: "Open window · " + appName, run: () => t.activate() });
            if (out.length >= 5) break;
        }
        return out;
    }

    // ---- Quick toggles (Settings → Launcher → Quick toggles) ---------------------------
    // Wi-Fi, Bluetooth, Do Not Disturb, night light and game mode, switched from the results
    readonly property var toggles: [
        { name: "Wi-Fi", words: "wifi wi-fi wireless network internet", icon: 0xEB52,
          on: () => Networking.wifiEnabled, set: v => Networking.wifiEnabled = v, can: () => true },
        { name: "Bluetooth", words: "bluetooth bt wireless", icon: 0xEA37,
          on: () => !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled,
          set: v => { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = v; }, can: () => !!Bluetooth.defaultAdapter },
        { name: "Do Not Disturb", words: "dnd do not disturb notifications quiet silence focus", icon: 0xECE9,
          on: () => !!root.notifs && root.notifs.dnd, set: v => { if (root.notifs) root.notifs.dnd = v; }, can: () => !!root.notifs },
        { name: "Night Light", words: "night light nightlight warm blue light", icon: 0xEAF8,
          on: () => Config.s.nightLight, set: v => Config.s.nightLight = v, can: () => true },
        { name: "Game Mode", words: "game gaming mode performance", icon: 0xF1D2,
          on: () => Config.s.gameMode, set: v => Config.setGameMode(v), can: () => true }
    ]
    readonly property var toggleResults: {
        const q = query.toLowerCase();
        if (mode !== "normal" || !Config.s.launcherToggles || q.length < 2) return [];
        return toggles.filter(t => t.can() && (t.name.toLowerCase().includes(q) || t.words.split(" ").some(w => w.startsWith(q))))
            .map(t => {
                const on = t.on();
                return { kind: "toggle", toggleOn: on, icon: t.icon, name: t.name,
                    comment: (on ? "On" : "Off") + " · Enter to turn it " + (on ? "off" : "on"), run: () => t.set(!on) };
            });
    }

    // ---- Files and folders (Settings → Launcher → Files and folders) -------------------
    // Files you opened recently (the desktop's own list, which most apps add to) and folders
    // in your home by name (up to three deep, not hidden ones)
    property var recentFiles: []
    FileView {
        path: Config.s.launcherFiles ? (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/recently-used.xbel" : ""
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = [], seen = new Set();
            const re = /<bookmark\s+href="file:\/\/([^"]+)"[^>]*?modified="([^"]+)"/g;
            const found = [];
            let m;
            const t = text();
            while ((m = re.exec(t)) !== null) found.push({ path: decodeURIComponent(m[1]), when: m[2] });
            found.sort((a, b) => a.when < b.when ? 1 : -1);
            for (const f of found) if (!seen.has(f.path)) { seen.add(f.path); out.push(f.path); if (out.length >= 200) break; }
            root.recentFiles = out;
        }
    }
    property var foundFolders: []
    Process {
        id: folderFind
        stdout: StdioCollector { onStreamFinished: root.foundFolders = text.split("\n").filter(l => l !== "") }
    }
    // Looked for a moment after typing stops (find, standard everywhere)
    Timer {
        id: folderSoon
        interval: 180
        onTriggered: {
            const q = root.query.replace(/[*?\[\]\\]/g, "");
            if (q.length < 2) { root.foundFolders = []; return; }
            folderFind.running = false;
            folderFind.command = ["sh", "-c", 'find "$HOME" -mindepth 1 -maxdepth 3 -type d -not -path "*/.*" -iname "*$1*" 2>/dev/null | head -n 4', "sh", q];
            folderFind.running = true;
        }
    }
    onQueryChanged: if (Config.s.launcherFiles && mode === "normal") folderSoon.restart()
    function fileGlyph(path, dir) {
        if (dir) return 0xEAAD;
        const ext = (path.split(".").pop() || "").toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "svg"].includes(ext)) return 0xEB0A;
        if (ext === "pdf") return 0xFB10;
        if (["zip", "tar", "gz", "xz", "bz2", "zst", "7z", "rar"].includes(ext)) return 0xED4E;
        if (["mp3", "flac", "ogg", "opus", "wav", "m4a"].includes(ext)) return 0xEAFC;
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext)) return 0xEAFA;
        return 0xEAA2;
    }
    function shortPath(p) { const h = Quickshell.env("HOME"); return p.startsWith(h) ? "~" + p.slice(h.length) : p; }
    readonly property var fileResults: {
        const q = query.toLowerCase();
        if (mode !== "normal" || !Config.s.launcherFiles || q.length < 2) return [];
        const out = [];
        for (const f of recentFiles) {
            const base = f.split("/").pop();
            if (!base.toLowerCase().includes(q)) continue;
            out.push({ kind: "file", icon: fileGlyph(f, false), name: base, comment: "Recent · " + shortPath(f),
                run: () => Qt.openUrlExternally("file://" + f) });
            if (out.length >= 4) break;
        }
        for (const d of foundFolders)
            out.push({ kind: "file", icon: 0xEAAD, name: d.split("/").pop(), comment: "Folder · " + shortPath(d),
                run: () => Qt.openUrlExternally("file://" + d) });
        return out;
    }

    // ---- Run a command (Settings → Launcher → Run commands): "> command" ---------------
    readonly property var commandResults: {
        const cmd = query.slice(1).trim();
        if (cmd === "") return [{ kind: "hint", icon: 0xEBEF, name: "Type a command to run", comment: "In a terminal, or on its own" }];
        const q = s => "'" + s.replace(/'/g, "'\\''") + "'";
        // In the terminal the shortcuts use (TERMINAL, Hyprland's variable), kept open after
        const inTerminal = cmd + "; printf '\\n[finished: press Enter to close]'; read _";
        return [
            { kind: "command", icon: 0xEBEF, name: cmd, comment: "Run in a terminal",
              run: () => Quickshell.execDetached(["hyprctl", "dispatch",
                  "function() hl.exec_cmd(TERMINAL .. [==[ -e sh -c ]==] .. [==[" + q(inTerminal) + "]==]) end"]) },
            { kind: "command", icon: 0xEBEF, name: cmd, comment: "Run on its own (no terminal)",
              run: () => Quickshell.execDetached(["sh", "-c", cmd]) }
        ];
    }

    // ---- Search the web (Settings → Launcher → Search the web) -------------------------
    readonly property var searchEngines: ({
        duckduckgo: { name: "DuckDuckGo", url: "https://duckduckgo.com/?q=" },
        google: { name: "Google", url: "https://www.google.com/search?q=" },
        bing: { name: "Bing", url: "https://www.bing.com/search?q=" },
        brave: { name: "Brave Search", url: "https://search.brave.com/search?q=" },
        startpage: { name: "Startpage", url: "https://www.startpage.com/do/search?q=" },
        ecosia: { name: "Ecosia", url: "https://www.ecosia.org/search?q=" }
    })
    readonly property var webResults: {
        if (mode !== "normal" || !Config.s.launcherWeb || query.length < 2) return [];
        const e = searchEngines[Config.s.launcherSearchEngine] || searchEngines.duckduckgo;
        const q = query;
        return [{ kind: "web", icon: 0xF9E7, name: "Search the web for “" + q + "”", comment: e.name,
            run: () => Qt.openUrlExternally(e.url + encodeURIComponent(q)) }];
    }

    // ---- Emoji (Settings → Launcher → Emoji): ":name" -----------------------------------
    // The emoji picker's list (data/emoji.json), read the first time it's wanted
    property var emojiList: []
    FileView {
        path: root.mode === "emoji" || root.emojiList.length > 0 ? Quickshell.shellPath("data/emoji.json") : ""
        onLoaded: { try { root.emojiList = JSON.parse(text()); } catch (e) {} }
    }
    readonly property var emojiResults: {
        const q = query.slice(1).trim().toLowerCase();
        if (q === "") return [{ kind: "hint", icon: 0xEAF7, name: "Type a name, like :smile", comment: "Enter copies the emoji" }];
        const starts = [], within = [];
        for (const e of emojiList) {
            const name = e[1].toLowerCase();
            if (name.startsWith(q) || name.split(" ").some(w => w.startsWith(q))) starts.push(e);
            else if ((e[2] || "").includes(q)) within.push(e);
            if (starts.length >= 40) break;
        }
        return starts.concat(within).slice(0, 40).map(e => ({ kind: "emoji", emoji: e[0], name: e[1], comment: "Enter to copy",
            run: () => Quickshell.execDetached(["wl-copy", e[0]]) }));
    }

    // ---- Conversions (Settings → Launcher → Conversions) -------------------------------
    // "5 km in miles", "72 f to c", "2 gb in mib", "today + 30 days": shown like a sum, Enter copies
    readonly property var unitTable: ({
        // length (metres)
        mm: ["length", 0.001], cm: ["length", 0.01], m: ["length", 1], metre: ["length", 1], meter: ["length", 1], km: ["length", 1000],
        in: ["length", 0.0254], inch: ["length", 0.0254], ft: ["length", 0.3048], foot: ["length", 0.3048], feet: ["length", 0.3048],
        yd: ["length", 0.9144], yard: ["length", 0.9144], mi: ["length", 1609.344], mile: ["length", 1609.344],
        // mass (kilograms)
        mg: ["mass", 1e-6], g: ["mass", 0.001], gram: ["mass", 0.001], kg: ["mass", 1], kilo: ["mass", 1], t: ["mass", 1000], tonne: ["mass", 1000],
        oz: ["mass", 0.028349523125], ounce: ["mass", 0.028349523125], lb: ["mass", 0.45359237], lbs: ["mass", 0.45359237], pound: ["mass", 0.45359237],
        st: ["mass", 6.35029318], stone: ["mass", 6.35029318],
        // volume (litres)
        ml: ["volume", 0.001], cl: ["volume", 0.01], l: ["volume", 1], litre: ["volume", 1], liter: ["volume", 1],
        tsp: ["volume", 0.00492892159], tbsp: ["volume", 0.0147867648], floz: ["volume", 0.0295735296], cup: ["volume", 0.2365882365],
        pt: ["volume", 0.473176473], pint: ["volume", 0.473176473], qt: ["volume", 0.946352946], quart: ["volume", 0.946352946],
        gal: ["volume", 3.785411784], gallon: ["volume", 3.785411784],
        // speed (metres a second)
        kph: ["speed", 1 / 3.6], kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], knot: ["speed", 0.514444], kn: ["speed", 0.514444], mps: ["speed", 1],
        // data (bytes)
        b: ["data", 1], byte: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
        kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        // time (seconds)
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], second: ["time", 1], min: ["time", 60], minute: ["time", 60],
        h: ["time", 3600], hr: ["time", 3600], hour: ["time", 3600], day: ["time", 86400], week: ["time", 604800], year: ["time", 31557600],
        // temperature (worked out on its own)
        c: ["temp", 0], celsius: ["temp", 0], f: ["temp", 0], fahrenheit: ["temp", 0], k: ["temp", 0], kelvin: ["temp", 0]
    })
    function unitOf(word) {
        const w = word.toLowerCase().replace(/°/g, "").replace(/\s+/g, "");
        return unitTable[w] ? w : (w.endsWith("s") && unitTable[w.slice(0, -1)] ? w.slice(0, -1) : (w.endsWith("es") && unitTable[w.slice(0, -2)] ? w.slice(0, -2) : ""));
    }
    function convert(text) {
        // A date: today / now / tomorrow / yesterday plus or minus days, weeks, months or years
        const d = /^(today|now|tomorrow|yesterday)(?:\s*([+-])\s*(\d+)\s*(day|week|month|year)s?)?$/i.exec(text);
        if (d && (d[2] || d[1].toLowerCase() !== "today")) {
            const t = new Date();
            const base = d[1].toLowerCase();
            if (base === "tomorrow") t.setDate(t.getDate() + 1);
            if (base === "yesterday") t.setDate(t.getDate() - 1);
            if (d[2]) {
                const n = parseInt(d[3]) * (d[2] === "-" ? -1 : 1), u = d[4].toLowerCase();
                if (u === "day") t.setDate(t.getDate() + n);
                else if (u === "week") t.setDate(t.getDate() + 7 * n);
                else if (u === "month") t.setMonth(t.getMonth() + n);
                else t.setFullYear(t.getFullYear() + n);
            }
            return Config.dateText(t, "long");
        }
        // Units: "<number> <unit> in|to <unit>"
        const m = /^(-?[\d.,]+)\s*([a-zA-Z°]+(?:\s?[a-zA-Z]+)?)\s+(?:in|to|as|into)\s+([a-zA-Z°]+(?:\s?[a-zA-Z]+)?)$/i.exec(text);
        if (!m) return null;
        const v = parseFloat(m[1].replace(/,/g, ""));
        const a = unitOf(m[2]), b = unitOf(m[3]);
        if (isNaN(v) || !a || !b) return null;
        const ua = unitTable[a], ub = unitTable[b];
        if (ua[0] !== ub[0]) return null;
        let r;
        if (ua[0] === "temp") {
            const k = a[0] === "c" ? v + 273.15 : a[0] === "f" ? (v - 32) * 5 / 9 + 273.15 : v;
            r = b[0] === "c" ? k - 273.15 : b[0] === "f" ? (k - 273.15) * 9 / 5 + 32 : k;
        } else r = v * ua[1] / ub[1];
        return String(Number(r.toPrecision(6))) + " " + m[3].trim();       // six figures is plenty
    }
    readonly property var convertResult: {
        if (mode !== "normal" || !Config.s.launcherConvert) return null;
        const r = convert(query);
        return r === null ? null : { calc: true, id: "", name: r, expr: query };
    }

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
        if (q === "") {
            const all = apps.slice().sort((x, y) => uses(y) - uses(x) || x.name.localeCompare(y.name));
            if (!Config.s.launcherRecent) return all;
            // The few opened most recently first (Settings → Launcher → Recent apps first)
            const recent = all.filter(a => lastUsed[a.id]).sort((x, y) => lastUsed[y.id] - lastUsed[x.id]).slice(0, 4);
            return recent.concat(all.filter(a => !recent.includes(a)));
        }
        return apps.concat(sessionActions.filter(a => a.action === "suspend" ? Config.canSuspend
                : (a.action === "reboot" || a.action === "shutdown") ? Config.canPowerOff : true))
            .map(a => ({ a: a, s: score(a, q) }))
            .filter(x => x.s >= 0)
            .sort((x, y) => x.s - y.s || uses(y.a) - uses(x.a) || x.a.name.localeCompare(y.a.name))
            .map(x => x.a);
    }

    // How often each app has been opened from here (for usage sorting)
    property var counts: ({})
    property var lastUsed: ({})          // app id → when it was last opened from here (ms)
    FileView {
        id: usage
        path: Quickshell.env("HOME") + "/.local/state/slate/launcher.json"
        blockLoading: true
        onLoaded: { try { const d = JSON.parse(text()); root.counts = d.counts || {}; root.lastUsed = d.last || {}; } catch (e) {} }
    }
    function uses(a) { return Config.s.launcherSortByUsage ? (counts[a.id] || 0) : 0; }
    // One more open of this entry, saved
    function countUse(id) {
        const updated = Object.assign({}, counts);
        updated[id] = (updated[id] || 0) + 1;
        counts = updated;
        const last = Object.assign({}, lastUsed);
        last[id] = Date.now();
        lastUsed = last;
        usage.setText(JSON.stringify({ counts: updated, last: last }, null, 1));
    }

    function launch(entry) {
        if (!entry || entry.kind === "hint") return;
        if (entry.run) {           // a window, toggle, file, command, web search, emoji or app action
            entry.run();
            closeLauncher();
            return;
        }
        if (entry.calc) {          // calculator: copy the answer
            Quickshell.execDetached(["wl-copy", entry.name]);
            closeLauncher();
            return;
        }
        if (entry.app) countUse(entry.id);     // the Slate Settings app: counted like an app
        if (entry.action) {        // lock / suspend / log out / restart / shut down
            if (entry.action === "lock") Config.slateCall("lock", "lock");
            else if (entry.action === "suspend") Quickshell.execDetached(["sh", "-c", "\"$0\" ipc call lock lock; sleep 0.6; \"$1\" suspend", Config.slateCommand, Quickshell.shellPath("bin/slate-init")]);
            else Config.slateCall("power", "confirm", entry.action);   // asks first
            closeLauncher();
            return;
        }
        if (entry.setting) {       // a Slate setting: open Settings on its page
            // Straight to the setting on its page (just the page for the Slate Settings app itself)
            if (entry.app) Config.slateCall("settings", "page", entry.page);
            else Config.slateCall("settings", "find", entry.page, entry.name);
            closeLauncher();
            return;
        }
        countUse(entry.id);
        // The secret workspace is showing: open the app there, not on the workspace behind it
        const special = specialShown();
        if (special !== "" && entry.command && entry.command.length > 0) launchOn(entry, special);
        else entry.execute();
        closeLauncher();
    }

    // ---- The secret (special) workspace showing on the focused monitor ("" = hidden: Config.specialOpen)
    function specialShown() {
        const mon = Hyprland.focusedMonitor;
        return mon ? (Config.specialOpen[mon.name] || "") : "";
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
        if (!entry || entry.calc || entry.setting || entry.action || entry.run) return;
        pendingTarget = "besideWorkspace(" + (dir > 0 ? 1 : -1) + ")";
        startNewWorkspaceLaunch(entry);
    }
    function launchOnNewWorkspace(entry) {
        if (!entry || entry.calc || entry.setting || entry.action || entry.run) return;
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
        Behavior on height { enabled: root.shown && root.typed; NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - root.panelHeight) / 2)
        radius: 18
        color: root.barColor
        opacity: root.fade
        scale: 0.98 + 0.02 * root.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Shadow { blur: 26; dropY: 5 }      // raised: Slate's shadow, with glass too
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
                text: "Search apps, windows, files and more"
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
                    // Settings → Launcher → Wrap around: past the end back to the start, and the
                    // other way (in the grid, to the same column at the other end)
                    case Qt.Key_Down:
                        if (i + across < n) list.currentIndex = i + across;
                        else if (Config.s.launcherWrap) list.currentIndex = i % across;
                        else list.currentIndex = n - 1;
                        break;
                    case Qt.Key_Up:
                        if (i - across >= 0) list.currentIndex = i - across;
                        else if (Config.s.launcherWrap) {
                            // the same column in the last row (or the last item, if that row is short)
                            const lastRow = Math.floor((n - 1) / across) * across;
                            list.currentIndex = Math.min(n - 1, lastRow + i % across);
                        } else list.currentIndex = 0;
                        break;
                    case Qt.Key_Tab: list.currentIndex = i + 1 < n ? i + 1 : (Config.s.launcherWrap ? 0 : n - 1); break;
                    case Qt.Key_Backtab: list.currentIndex = i > 0 ? i - 1 : (Config.s.launcherWrap ? n - 1 : 0); break;
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
            // Rows use the full width when they all fit (no scrollbar); the grid's cells are a fixed size.
            // Worked out from the results and the panel's room, not this view's own count or
            // height: those are signalled again as the width this sets changes (a binding loop)
            readonly property bool listFits: !root.gridMode && root.chromeHeight + root.results.length * root.rowHeight <= root.panelHeight
            anchors.bottomMargin: root.gridMode ? 4 : 14
            clip: true
            // The results' keys (see syncResults), emptied and filled again when the layout
            // changes, so every item is made again for it (items made for the list don't lay
            // themselves out again properly as grid cells)
            model: resultModel
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
                // (flat, with glass too: no sheen on the selection)
                x: (list.currentItem ? list.currentItem.x : 0) + (root.gridMode ? (list.cellWidth - gridBox) / 2 : 0)
                y: (list.currentItem ? list.currentItem.y : 0) + (root.gridMode ? (list.cellHeight - gridBox) / 2 : 0)
                // Smoothed: a new target (the next key press) carries on at the current speed,
                // where an eased slide restarted fast on each press and lurched when keys repeat
                Behavior on x {
                    enabled: root.slideHighlight && Config.animate
                    SmoothedAnimation { duration: Config.ms(root.slideMs); velocity: -1 }
                }
                Behavior on y {
                    enabled: root.slideHighlight && Config.animate
                    SmoothedAnimation { duration: Config.ms(root.slideMs); velocity: -1 }
                }
            }

            // Keep the selection on screen: scroll just enough when it moves past an edge
            SmoothedAnimation {
                id: scrollAnim
                target: list
                property: "contentY"
                duration: Config.ms(root.slideMs)
                velocity: -1
            }
            onCurrentIndexChanged: {
                if (currentIndex < 0) return;
                // (from the list's own starting point: rows added above move it, so it isn't
                // always 0, and going by 0 scrolled the results out of sight)
                const top = originY + Math.floor(currentIndex / columns) * cellHeight;
                const bottom = top + cellHeight;
                // From where it's already heading (keys pressed quickly), so the scroll carries on
                const from = scrollAnim.running ? scrollAnim.to : contentY;
                let to = from;
                if (top < from) to = top;
                else if (bottom > from + height) to = bottom - height;
                if (to === from) return;
                if (root.slideHighlight && Config.animate) {
                    scrollAnim.to = to;
                    scrollAnim.restart();       // a smoothed restart keeps its current speed
                } else {
                    scrollAnim.stop();
                    contentY = to;
                }
            }

            delegate: Item {
                id: row
                required property string rid
                required property int index
                readonly property var modelData: root.resultByKey[rid] || ({ name: "", id: "" })
                readonly property bool calc: !!modelData.calc
                readonly property bool setting: !!modelData.setting
                readonly property bool action: !!modelData.action
                readonly property string kind: modelData.kind || ""
                // An app's tile: apps, and a window or app action (their app's tile)
                readonly property bool appTile: !calc && !setting && !action && (kind === "" || kind === "window" || kind === "appaction")
                readonly property bool emojiTile: kind === "emoji"
                // Rows drawn with an icon glyph rather than an app tile
                readonly property bool glyphTile: (setting && !modelData.app) || action || (kind !== "" && !appTile && !emojiTile)
                readonly property string tilePath: Config.tilePath(modelData.id)
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
                    visible: row.appTile
                    source: row.appTile ? "file://" + row.tilePath + "?v=" + row.version + "." + Config.tileVersion : ""
                    sourceSize: Qt.size(192, 192)
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                    onStatusChanged: if (row.appTile && status === Image.Error && !gen.running && row.tried !== row.tilePath) { row.tried = row.tilePath; gen.running = true; }
                    // The tile behind, in the theme's colour. Solid on the highlight: with glass it's
                    // see-through, and the accent behind would show through it
                    IconPlate {
                        anchors.fill: parent; z: -1
                        color: row.selected && Config.glass ? Config.iconTileFor(app, Config.tint("#2a313c"), true) : Config.iconTileFor(app, Config.iconPlateColor)
                        Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
                    }
                    IconGloss {}                // glass: a sheen on the tile, as on the dock's icons
                }
                // Calculator tile
                Rectangle {
                    visible: row.calc
                    anchors.fill: tile
                    radius: 9
                    // Swapped round on the accent highlight, so it doesn't vanish into it
                    color: row.onAccent ? root.accentText : root.accent
                    Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB80)
                        color: row.onAccent ? root.accent : root.accentText
                        Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
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
                    Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
                    border.width: 1; border.color: root.selectColor
                    Text {
                        anchors.centerIn: parent
                        text: row.glyphTile ? String.fromCodePoint(row.modelData.icon) : ""
                        // A setting's icon takes its page's colour in colourful mode, as in Settings
                        // (a toggle in the accent while it's on, dim while it's off)
                        color: row.modelData.danger ? Config.tint("#f28b8b")
                            : row.setting ? Config.pageColour(row.modelData.page)
                            : row.kind === "toggle" && !row.modelData.toggleOn ? root.dimTextColor : root.accent
                        font.family: tabler.name
                        font.pixelSize: 19
                    }
                }
                // Emoji: the emoji itself, on a tile like the glyphs'
                Rectangle {
                    visible: row.emojiTile
                    anchors.fill: tile
                    radius: 9
                    color: row.selected && Config.glass ? Config.tint("#1d222a") : root.fieldColor
                    border.width: 1; border.color: root.selectColor
                    Text {
                        anchors.centerIn: parent
                        text: row.emojiTile ? row.modelData.emoji : ""
                        font.family: "Noto Color Emoji"
                        font.pixelSize: Math.round(parent.height * 0.6)
                    }
                }
                // Draw the tile if this app doesn't have one yet
                Process {
                    id: gen
                    command: Config.tileCommand(row.modelData.id, row.tilePath)
                    onExited: row.version++
                }

                // A quick toggle: a switch at the end of its row showing whether it's on (the list only)
                Rectangle {
                    id: toggleSwitch
                    visible: row.kind === "toggle" && !root.gridMode
                    readonly property bool on: !!row.modelData.toggleOn
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 36; height: 20; radius: 10
                    // On the accent highlight, the track can't be the accent too: it takes the
                    // highlight's dark text colour instead. Off, it's an outline with a solid knob,
                    // so it reads on the bright highlight as well as on the panel
                    readonly property color ink: row.onAccent ? root.accentText : root.textColor
                    color: on ? (row.onAccent ? root.accentText : root.accent)
                        : Qt.rgba(ink.r, ink.g, ink.b, row.onAccent ? 0.08 : 0.1)
                    border.width: on ? 0 : 1.5
                    border.color: Qt.rgba(ink.r, ink.g, ink.b, row.onAccent ? 0.75 : 0.4)
                    Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
                    Gloss { radius: parent.radius }   // glass: a sheen
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        anchors.verticalCenter: parent.verticalCenter
                        x: toggleSwitch.on ? parent.width - width - 3 : 3
                        color: toggleSwitch.on ? (row.onAccent ? root.accent : root.accentText) : toggleSwitch.ink
                        Behavior on x { NumberAnimation { duration: Config.ms(120) } }
                    }
                }

                // Name and description (the list only: the grid shows them in the strip at the bottom)
                Column {
                    visible: !root.gridMode
                    anchors { left: tile.right; leftMargin: 12; right: toggleSwitch.visible ? toggleSwitch.left : parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text {
                        width: parent.width
                        // (apps' names capitalised; a command, file or window's title as it is)
                        text: row.calc ? "= " + row.modelData.name : row.kind === "" ? root.capitalised(row.modelData.name) : row.modelData.name
                        color: row.onAccent ? root.accentText : root.textColor
                        Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
                        font.family: root.fontFamily
                        font.pixelSize: row.calc ? 16 : 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: row.calc || row.setting || row.action || row.kind !== "" || (Config.s.launcherDescriptions && row.detail !== "" && row.detail !== row.modelData.name)
                        text: row.calc ? row.detail : root.capitalised(row.detail)
                        color: row.onAccent ? Qt.rgba(root.accentText.r, root.accentText.g, root.accentText.b, 0.72) : root.dimTextColor
                        Behavior on color { ColorAnimation { duration: Config.ms(row.fadeMs) } }
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
                    text: !nameStrip.item ? "" : nameStrip.item.calc ? "= " + nameStrip.item.name
                        : !nameStrip.item.kind ? root.capitalised(nameStrip.item.name) : nameStrip.item.name
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
            text: "Nothing matches that. Try another word"
            color: root.dimTextColor
            font.family: root.fontFamily
            font.pixelSize: 14
        }
    }
}
