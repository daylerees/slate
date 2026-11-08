pragma Singleton

// Shared settings for the bar, dock, launcher, switchers and notifications.
// Saved to settings.json next to this file; changed from the Settings window
// (slate ipc call settings toggle). Use as  Config.s.<name>

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

Singleton {
    id: root
    readonly property alias s: adapter
    signal saved()                         // settings.json changed (here or on disk)

    // The accent in use: picked by hand, or taken from the wallpaper
    readonly property color accent: {
        const a = Qt.lighter(s.accentFromWallpaper && wallpaperAccent !== "" ? wallpaperAccent : s.accent, 1.0);
        // Light mode: a deeper shade so it stands out on light backgrounds
        return s.lightMode ? Qt.hsla(a.hslHue < 0 ? 0 : a.hslHue, Math.max(a.hslSaturation, 0.45), 0.42, 1) : a;
    }
    property string wallpaper: s.wallpaper
    property string wallpaperAccent: ""
    property string wallpaperTone: ""      // overall hue/saturation of the wallpaper

    // Every theme colour goes through tint():
    //  - Light mode flips the greys (dark backgrounds become light, light text
    //    becomes dark) and deepens coloured ones so they read on a light background.
    //  - Background tint shifts the greys toward the wallpaper's hue, keeping
    //    their lightness.
    // With both off the colour comes back unchanged (the default dark slate).
    function tint(hex) {
        const light = s.lightMode;
        const toned = s.toneFromWallpaper && wallpaperTone !== "";
        if (!light && !toned) return hex;
        const c = Qt.lighter(hex, 1.0);
        const neutral = c.hslSaturation < 0.3;
        const surface = c.hslLightness < 0.5;          // backgrounds (vs text) in the dark theme
        let h = c.hslHue, sat = c.hslSaturation, l = c.hslLightness;
        if (light) l = neutral ? 1 - l : Math.min(l, 0.45);
        if (toned && neutral) {
            const t = Qt.lighter(wallpaperTone, 1.0);
            if (t.hslHue >= 0) h = t.hslHue;
            sat = Math.min(0.32, Math.max(sat, t.hslSaturation * (surface ? 0.45 : 0.22)));
        }
        return Qt.hsla(h < 0 ? 0 : h, sat, l, c.a);
    }

    // Sunrise and sunset on a date at Settings' location, in minutes after local midnight
    // (NOAA's approximation; good to a minute or two). Polar day/night clamp to 0 / 1440.
    function sunTimes(date) {
        const rad = Math.PI / 180;
        const start = new Date(date.getFullYear(), 0, 0);
        const n = Math.floor((date - start) / 86400000);
        const g = 2 * Math.PI / 365 * (n - 1);
        const eq = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
            + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const lat = s.latitude * rad;
        const x = Math.cos(90.833 * rad) / (Math.cos(lat) * Math.cos(decl)) - Math.tan(lat) * Math.tan(decl);
        const ha = Math.acos(Math.max(-1, Math.min(1, x))) / rad;
        const offset = -date.getTimezoneOffset();
        const clamp = m => Math.max(0, Math.min(1440, m));
        return { rise: clamp(720 - 4 * (s.longitude + ha) - eq + offset), set: clamp(720 - 4 * (s.longitude - ha) - eq + offset) };
    }
    function clockText(minutes) {
        const m = Math.round(minutes);
        return String(Math.floor(m / 60) % 24).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
    }

    // Change a setting from the command line, as the Settings window does:
    //   slate ipc call config set barPosition bottom      slate ipc call config get barPosition
    IpcHandler {
        target: "config"
        function set(key: string, value: string): void {
            const cur = root.s[key];
            if (cur === undefined) return;
            if (key === "barPosition") { root.moveBar(value); return; }
            if (key === "dockPosition") { root.moveDock(value); return; }
            root.s[key] = typeof cur === "boolean" ? value === "true" : typeof cur === "number" ? Number(value) : value;
        }
        function get(key: string): string { return String(root.s[key]); }
    }

    // ---- App icon tint: 0 (off) to 1 (fully in the accent colour); see IconTint.qml
    readonly property real iconTint: s.tintIcons ? Math.max(0, Math.min(100, s.iconTintStrength)) / 100 : 0

    // ---- Workspace indicators: circles, or rounded squares (Settings → Appearance)
    function dotRadius(size) { return s.workspaceShape === "square" ? size * 0.28 : size / 2; }

    // ---- Account picture ------------------------------------------------------------
    // AccountsService's picture for this user (shared with GNOME, KDE and the login
    // screen). Changing it keeps the same path, so avatarUrl carries a version number to
    // make images load the new one.
    readonly property string avatarPath: "/var/lib/AccountsService/icons/" + Quickshell.env("USER")
    property int avatarVersion: 0
    readonly property string avatarUrl: "file://" + avatarPath + "?v=" + avatarVersion
    property bool avatarBusy: false
    property string avatarError: ""
    function setAvatar(path) {
        if (avatarBusy || !path) return;
        avatarBusy = true;
        avatarError = "";
        path = String(path);
        if (path.startsWith("file://")) path = decodeURIComponent(path.slice(7));   // from a file dialog
        avatarProc.command = [Quickshell.shellPath("scripts/set-avatar.sh"), path];
        avatarProc.running = true;
    }
    Process {
        id: avatarProc
        stderr: StdioCollector { id: avatarErr }
        onExited: code => {
            root.avatarBusy = false;
            if (code === 0) root.avatarVersion++;
            else root.avatarError = avatarErr.text.trim().split("\n").pop() || "Couldn't change the picture";
        }
    }

    // ---- Where the bar and dock sit ------------------------------------------------
    readonly property bool barAtBottom: s.barPosition === "bottom"
    readonly property string barEdge: s.barPosition
    readonly property bool barVertical: s.barPosition === "left" || s.barPosition === "right"
    readonly property string dockEdge: s.dockPosition
    // The bar and dock never share an edge: moving one onto the other's edge sends the other
    // to the opposite edge. Both change in one step (Settings and `slate ipc call config set`
    // use these), because the settings store can undo a second change made while the first is
    // still being saved.
    function opposite(e) { return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[e] || "bottom"; }
    function moveBar(v) {
        if (s.dockPosition === v) s.dockPosition = opposite(v);
        s.barPosition = v;
    }
    function moveDock(v) {
        if (s.barPosition === v) s.barPosition = opposite(v);
        s.dockPosition = v;
    }
    // After a hand edit of settings.json, or older settings with both at the bottom: the dock moves
    function separateBarAndDock() { if (s.dockPosition === s.barPosition) s.dockPosition = opposite(s.barPosition); }
    Component.onCompleted: Qt.callLater(separateBarAndDock)

    // ---- Light/dark by time of day (themeMode "auto") -------------------------------
    // Light from sunrise to sunset at Settings' location, else 07:00–19:00
    readonly property string themeMode: s.themeMode !== "" ? s.themeMode : (s.lightMode ? "light" : "dark")
    function lightHours(date) {
        if (s.locationName !== "") { const st = sunTimes(date); return { from: st.rise, to: st.set }; }
        return { from: 7 * 60, to: 19 * 60 };
    }
    function applyAutoTheme() {
        if (themeMode !== "auto") return;
        const now = new Date(), h = lightHours(now), t = now.getHours() * 60 + now.getMinutes();
        const light = t >= h.from && t < h.to;
        if (s.lightMode !== light) s.lightMode = light;
    }
    onThemeModeChanged: applyAutoTheme()
    Timer { interval: 60000; running: root.themeMode === "auto"; repeat: true; triggeredOnStart: true; onTriggered: root.applyAutoTheme() }

    // The wallpaper (Settings → Appearance, or ipc call wallpaper set <path>); drawn by Wallpaper.qml.
    // The login screen sets this to its own copy instead.
    onWallpaperChanged: refreshWallpaperAccent()
    // ---- Screens -------------------------------------------------------------
    // The screen with Hyprland's focus: launcher, switcher, overview and the like open there
    readonly property var focusedScreen: {
        const m = Hyprland.focusedMonitor;
        const all = Quickshell.screens;
        return (m && all.find(s => s.name === m.name)) || all[0] || null;
    }
    // The main display (Settings → Displays): its bar is the main one. Saved by the
    // monitor's description; the first screen when unset or not connected
    readonly property var primaryScreen: {
        const all = Quickshell.screens, d = s.mainDisplay;
        const m = d ? Hyprland.monitors.values.find(x => x.description === d || x.name === d) : null;
        return (m && all.find(x => x.name === m.name)) || all[0] || null;
    }
    // Every bar (one per screen) registers here, so commands can reach the focused one
    property var bars: []
    function barFor(screen) {
        return bars.find(b => b.screen && screen && b.screen.name === screen.name) || bars.find(b => b.primary) || null;
    }

    // ---- A fresh login ----------------------------------------------------------
    // Once per Hyprland session, not when Slate restarts within it: a marker in the runtime
    // folder, named after this Hyprland session, says Slate has already started. atLogin
    // fires a moment after Slate starts, once its settings have loaded (the wallpaper can
    // change, startup apps open).
    signal atLogin()
    readonly property string loginMarker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate-started-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "session")
    Process {
        running: true
        command: ["sh", "-c", "[ -e \"$0\" ] && exit 1; touch \"$0\"", root.loginMarker]
        onExited: code => { if (code === 0) loginSettle.start(); }
    }
    Timer { id: loginSettle; interval: 2500; onTriggered: root.atLogin() }
    // Startup apps (Settings → Startup apps)
    onAtLogin: {
        for (const id of (s.startupApps || [])) {
            const e = DesktopEntries.byId(id);
            if (e) e.execute();
        }
    }

    // ---- Settings Hyprland applies (session/hypr/config/slate.lua) -----------------------
    // Only the ones changed in Settings; the rest stay as Hyprland's config has them
    function appCommand(id) {
        const e = id ? DesktopEntries.byId(id) : null;
        if (!e || !e.command || e.command.length === 0) return "";
        return e.command.filter(a => !/^%[a-zA-Z]$/.test(a))
            .map(a => /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(a) ? a : "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
    }
    readonly property string hyprSettings: {
        const t = [];
        const q = v => JSON.stringify(String(v));
        const onOff = v => v === "on" ? "true" : "false";
        if (s.kbLayouts !== "") t.push(`kb_layout = ${q(s.kbLayouts)}, kb_variant = ${q(s.kbVariants)}`);
        if (s.capsLock !== "" || s.kbSwitch !== "") {
            const opts = [];
            const caps = { ctrl: "caps:ctrl_modifier", escape: "caps:escape", off: "caps:none" }[s.capsLock];
            const sw = { alt_shift: "grp:alt_shift_toggle", ctrl_space: "grp:ctrl_space_toggle", caps: "grp:caps_toggle" }[s.kbSwitch];
            if (caps && !(sw === "grp:caps_toggle")) opts.push(caps);
            if (sw) opts.push(sw);
            t.push(`kb_options = ${q(opts.join(","))}`);
        }
        if (s.keyRepeatDelay > 0) t.push(`repeat_delay = ${s.keyRepeatDelay}`);
        if (s.keyRepeatRate > 0) t.push(`repeat_rate = ${s.keyRepeatRate}`);
        if (s.mouseSpeed >= -1) t.push(`sensitivity = ${s.mouseSpeed.toFixed(2)}`);
        if (s.mouseAccel !== "") t.push(`accel_profile = ${q(s.mouseAccel)}`);
        if (s.mouseNaturalScroll !== "") t.push(`natural_scroll = ${onOff(s.mouseNaturalScroll)}`);
        if (s.touchpadSpeed >= -1) t.push(`tp_sensitivity = ${s.touchpadSpeed.toFixed(2)}`);
        if (s.touchpadScrollSpeed > 0) t.push(`tp_scroll = ${s.touchpadScrollSpeed.toFixed(2)}`);
        if (s.touchpadNaturalScroll !== "") t.push(`tp_natural_scroll = ${onOff(s.touchpadNaturalScroll)}`);
        if (s.touchpadTapToClick !== "") t.push(`tp_tap = ${onOff(s.touchpadTapToClick)}`);
        if (s.touchpadIgnoreWhileTyping !== "") t.push(`tp_dwt = ${onOff(s.touchpadIgnoreWhileTyping)}`);
        // Focus: follows the pointer (1), or a click, with scrolling still reaching the window under it (2)
        if (s.focusFollowsMouse !== "") t.push(`follow_mouse = ${s.focusFollowsMouse === "on" ? 1 : 2}`);
        if (s.cursorSize > 0) t.push(`cursor_size = ${s.cursorSize}`);
        if (s.animations !== "") t.push(`animations = ${q(s.animations)}`);
        const apps = { terminal: s.defaultTerminal, browser: s.defaultBrowser, file_manager: s.defaultFileManager,
                       editor: s.defaultEditor, calculator: s.defaultCalculator };
        for (const k in apps) { const c = appCommand(apps[k]); if (c) t.push(`${k} = ${q(c)}`); }
        t.push(`lid_action = ${q(s.lidAction)}, power_key_action = ${q(s.powerKeyAction)}`);
        return `if slateApply then slateApply({ ${t.join(", ")} }) end`;
    }
    onHyprSettingsChanged: hyprPush.restart()
    Timer { id: hyprPush; interval: 400; running: true; onTriggered: Quickshell.execDetached(["hyprctl", "eval", root.hyprSettings]) }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") hyprPush.restart(); }
    }

    // ---- Keyboard layouts (for the menu bar's switcher) ---------------------------------
    // The layouts in use (set in Settings → Keyboard & mouse, or Hyprland's own config), their
    // names, and which one is active (Hyprland's activelayout event says when it changes)
    property var xkbNames: ({})
    property string hyprLayouts: ""
    property string hyprVariants: ""
    readonly property var kbLayoutList: {
        const set = s.kbLayouts !== "";
        const ls = (set ? s.kbLayouts : hyprLayouts).split(",");
        const vs = (set ? s.kbVariants : hyprVariants).split(",");
        return ls.map(l => l.trim()).filter(l => l !== "").map((l, i) => {
            const v = (vs[i] || "").trim();
            const key = v ? l + ":" + v : l;
            return { layout: l, variant: v, name: xkbNames[key] || xkbNames[l] || key, code: l.toUpperCase() };
        });
    }
    property int kbActive: 0
    function switchLayout(i) {
        const n = kbLayoutList.length;
        if (n < 2) return;
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(((i % n) + n) % n)]);
    }
    function refreshKeyboard() { kbState.running = false; kbState.running = true; kbOptions.running = false; kbOptions.running = true; }
    Process {
        id: kbState
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(text).keyboards.find(k => k.main);
                    if (k && k.active_layout_index !== undefined) root.kbActive = k.active_layout_index;
                } catch (e) {}
            }
        }
    }
    Process {
        id: kbOptions
        running: true
        command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:kb_layout", "input:kb_variant"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const o = JSON.parse(text); root.hyprLayouts = o["input:kb_layout"] || "us"; root.hyprVariants = o["input:kb_variant"] || ""; } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const m = {}; for (const o of JSON.parse(text)) m[o.value] = o.label; root.xkbNames = m; } catch (e) {}
            }
        }
    }
    Timer { id: kbLater; interval: 400; onTriggered: root.refreshKeyboard() }
    onKbLayoutListChanged: kbLater.restart()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout" || event.name === "configreloaded") kbLater.restart();
        }
    }

    // ---- Lid and power button (Settings → Power) --------------------------------------
    // When an action is chosen, the system's own handling (logind) is held back while Slate
    // runs, and Hyprland does the action (slate.lua). Restarted when the choice changes.
    readonly property string inhibitWhat: [s.lidAction !== "" ? "handle-lid-switch" : "", s.powerKeyAction !== "" ? "handle-power-key" : ""]
        .filter(x => x !== "").join(":")
    onInhibitWhatChanged: { inhibitor.running = false; inhibitRestart.restart(); }
    Timer { id: inhibitRestart; interval: 200; onTriggered: inhibitor.running = root.inhibitWhat !== "" }
    Process {
        id: inhibitor
        running: false
        command: ["systemd-inhibit", "--what=" + root.inhibitWhat, "--who=Slate", "--why=Slate handles the lid and power button (Settings → Power)",
                  "--mode=block", "sleep", "infinity"]
    }

    // ---- Power profile on battery / plugged in (Settings → Power) ------------------------
    // Set when the power source changes (and as Slate starts); changing it by hand afterwards
    // sticks until the next change
    function applyPowerProfile() {
        const want = UPower.onBattery ? s.profileOnBattery : s.profileOnAC;
        const p = { "power-saver": PowerProfile.PowerSaver, "balanced": PowerProfile.Balanced, "performance": PowerProfile.Performance }[want];
        if (p === undefined) return;
        if (p === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return;
        PowerProfiles.profile = p;
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.applyPowerProfile(); }
    }
    Timer { interval: 3000; running: true; onTriggered: root.applyPowerProfile() }

    // ---- App icons ----------------------------------------------------------------
    // Drawn by scripts/appicon.py in the shape and style from Settings → Appearance → App
    // icons, and cached per style (the default keeps the original folder)
    readonly property string tileScript: Quickshell.shellPath("scripts/appicon.py")
    // The tile behind icons that don't fill their shape (IconPlate.qml): slate, following the theme
    readonly property color iconPlateColor: tint("#2a313c")
    readonly property string tileDir: Quickshell.env("HOME") + "/.cache/slate/tiles"
        + (s.iconShape === "tile" && s.iconFill ? "" : "/" + s.iconShape + (s.iconFill ? "" : "-whole"))
    readonly property var tileStyle: ["--shape", s.iconShape, s.iconFill ? "--fill" : "--whole"]
    // Command to draw one app's icon: tileCommand(app id or class, file). Built from the
    // settings themselves, not tileStyle: right after a change tileStyle can still hold the
    // old style while the file is already in the new style's folder (the script also goes
    // by the folder, so the two can't disagree)
    function tileCommand(app, path) {
        return [tileScript, "--tile", app, path, "192", "--shape", s.iconShape, s.iconFill ? "--fill" : "--whole"];
    }
    // Changing the style draws every installed app's icon in it, in the background (and at
    // startup, any that are missing); tileVersion goes up when that's done, to reload images
    property int tileVersion: 0
    onTileDirChanged: tileAll.restart()
    Timer { id: tileAll; interval: 600; running: true; onTriggered: { tileAllRun.running = false; tileAllRun.running = true; } }
    Process {
        id: tileAllRun
        command: [root.tileScript, "--tile-all", root.tileDir, "192"].concat(root.tileStyle)
        onExited: root.tileVersion++
    }

    // ---- Interface size ---------------------------------------------------------
    // Settings → Appearance → Interface size scales all of Slate through Qt (QT_SCALE_FACTOR,
    // set by bin/slate when it starts Slate), so the scale in use is the one Slate started
    // with; changing the setting restarts Slate (SettingsWindow). Hyprland's own pieces
    // (title bars) and anything mixing Hyprland's screen positions with Slate's use uiScale.
    readonly property real uiScale: {
        const v = parseFloat(Quickshell.env("QT_SCALE_FACTOR") || "1");
        return v > 0 ? v : 1;
    }
    // Called when the setting is changed from Settings (not when the file loads, so a
    // mismatch can never restart Slate over and over): restarts Slate a moment after the
    // last change, then reopens Settings where it was
    function uiScaleEdited() { scaleRestart.restart(); }
    Timer {
        id: scaleRestart
        interval: 1200
        onTriggered: {
            if (Math.abs(root.s.uiScale - root.uiScale) < 0.001) return;
            const slate = Quickshell.shellPath("bin/slate");
            Quickshell.execDetached(["setsid", "-f", "sh", "-c",
                `sleep 0.5; "${slate}" restart --full; for i in $(seq 40); do sleep 0.25; "${slate}" ipc call settings page appearance >/dev/null 2>&1 && break; done`]);
        }
    }

    // Floating window mode needs title bars: the hyprbars plugin loaded, with Slate's patch
    // (it adds idle_button_color). Without them Slate stays tiling and Settings hides the
    // choice. The saved setting is kept, so floating comes back once hyprbars is (re)built,
    // e.g. after a Hyprland update stops the old build loading. Rechecked when Hyprland's
    // config reloads (shell.qml).
    property bool titleBarsAvailable: false
    readonly property bool floatingWindows: s.windowMode === "floating" && titleBarsAvailable
    function checkTitleBars() { titleBarsCheck.running = true; }
    Process {
        id: titleBarsCheck
        running: true
        command: ["sh", "-c", "hyprctl plugin list -j | grep -q '\"name\": *\"hyprbars\"' "
            + "&& hyprctl getoption plugin:hyprbars:idle_button_color -j | grep -q '\"option\"'"]
        onExited: code => root.titleBarsAvailable = code === 0
    }

    function refreshWallpaperAccent() {
        if (wallpaper === "") return;
        picker.command = [Qt.resolvedUrl("scripts/wallpaper-accent.py").toString().replace("file://", ""), wallpaper];
        picker.running = true;
    }
    Process {
        id: picker
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (/^#[0-9a-f]{6}$/i.test(lines[0])) root.wallpaperAccent = lines[0];
                if (lines[1] && /^#[0-9a-f]{6}$/i.test(lines[1])) root.wallpaperTone = lines[1];
            }
        }
    }

    FileView {
        id: file
        path: Qt.resolvedUrl("settings.json").toString().replace("file://", "")
        watchChanges: true
        // Reload when something else edits the file. Our own writes also trigger this; reloading
        // then could read the file between two quick changes and undo them, so skip those.
        property real lastWrite: 0
        onFileChanged: {
            if (Date.now() - lastWrite < 600) return;
            reload();
            root.saved();
            Qt.callLater(root.separateBarAndDock);
        }
        // Write any change straight back to disk
        onAdapterUpdated: { lastWrite = Date.now(); writeAdapter(); root.saved(); }
        // First run: create the file with the defaults (SettingsData.qml)
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }

        adapter: SettingsData { id: adapter }
    }

    // ---- Defaults --------------------------------------------------------------------
    // A spare copy of the settings, never loaded from disk, so it holds the defaults
    SettingsData { id: defaults }
    function defaultOf(key) { return defaults[key]; }
    // Put these settings back to their defaults (Settings → each page's Restore defaults)
    // Settings Hyprland applies (hyprSettings): putting one back to "not set here" reloads
    // Hyprland's config, so its own value (or your hyprland.lua's) is used again
    readonly property var hyprKeys: ["kbLayouts", "kbVariants", "kbSwitch", "capsLock", "keyRepeatDelay", "keyRepeatRate",
        "mouseSpeed", "mouseAccel", "mouseNaturalScroll", "touchpadSpeed", "touchpadScrollSpeed", "touchpadNaturalScroll",
        "touchpadTapToClick", "touchpadIgnoreWhileTyping", "focusFollowsMouse", "animations", "cursorSize",
        "defaultTerminal", "defaultBrowser", "defaultFileManager", "defaultEditor", "defaultCalculator"]
    Timer { id: hyprReload; interval: 300; onTriggered: Quickshell.execDetached(["hyprctl", "reload"]) }
    function sameValue(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function resetKeys(keys) {
        for (const k of keys) {
            if (defaults[k] === undefined) continue;
            if (k === "barPosition") moveBar(defaults[k]);
            else if (k === "dockPosition") moveDock(defaults[k]);
            else if (!sameValue(root.s[k], defaults[k])) {
                root.s[k] = defaults[k];
                if (k === "uiScale") uiScaleEdited();
                if (hyprKeys.includes(k)) hyprReload.restart();
            }
        }
    }
    // How many of these differ from their defaults
    function changedCount(keys) {
        let n = 0;
        for (const k of keys) if (defaults[k] !== undefined && !sameValue(root.s[k], defaults[k])) n++;
        return n;
    }
}
