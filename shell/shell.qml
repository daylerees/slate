//@ pragma AppId slate-settings
//@ pragma UseQApplication
// (AppId: the app id Slate's own windows get, so the Settings window has Slate's icon: see
// data/slate-settings.desktop and assets/icon/settings-*.png. UseQApplication: lets app tray
// menus, which are "platform menus", open when a tray icon is right-clicked.)
// Slate: a desktop shell for Hyprland (bar, dock, launcher, switchers, panels,
// notifications, settings). Run with:  slate
// Settings: settings.json here; saved state: ~/.local/state/slate; cache: ~/.cache/slate
//
// This file holds the dock (a macOS-style dock) and wires the other parts together:
// - Icons magnify near the pointer with a smooth falloff, so neighbours rise in an
//   arc and the dock widens to make room.
// - App icons are "phone app" tiles drawn by scripts/appicon.py --tile
//   and cached in ~/.cache/slate/tiles/ (a folder per icon style, Config.tileDir).
// - Hides while the workspace has windows; push the pointer to the bottom edge to
//   bring it back.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root
    // Only one of the launcher, window switcher and workspace overview shows at a
    // time: opening one closes the others
    Launcher {
        id: appLauncher
        onShownChanged: if (shown) { winSwitcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    // Clipboard history (Super+V) and emoji picker (Super+.)
    Picker {
        id: picker
        onShownChanged: if (shown) { appLauncher.closeLauncher(); winSwitcher.cancel(); wsOverview.close(); popouts.close(); }
    }
    // Records clipboard history for the picker (scripts/clipstore.py); exits with Slate
    Process {
        id: clipWatch
        // Settings → General → Clipboard history: off stops recording (what's kept stays until cleared)
        running: Config.s.clipboardHistory
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", "python3", Quickshell.shellPath("scripts/clipstore.py"), "store"]
        onRunningChanged: if (!running && Config.s.clipboardHistory) clipRestart.restart()
    }
    Timer { id: clipRestart; interval: 2000; onTriggered: if (Config.s.clipboardHistory) clipWatch.running = true }
    // A bar on every screen. The main display's (topBar, Settings → Displays) is the main one: other pieces take
    // its look and sizes, and it answers `slate ipc call bar …` (passing it to the focused
    // screen's bar). The panels open on whichever screen's bar opened them.
    Bar { id: topBar; screen: Config.primaryScreen; popouts: popouts; notifs: notifs }
    Variants {
        model: Quickshell.screens.filter(s => s !== Config.primaryScreen)
        Bar { required property var modelData; screen: modelData; primary: false; popouts: popouts; notifs: notifs }
    }
    Popouts { id: popouts; bar: topBar; notifs: notifs; powerConfirm: powerConfirm }
    PowerConfirm { id: powerConfirm }
    // slate restart / stop (bin/slate): reload in place rather than restarting the process,
    // since Quickshell can crash while shutting down and then relaunch itself
    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(true); }
    }
    // Geist ships with Slate (fonts/, SIL OFL), so it's there even if not installed system-wide
    Variants {
        model: ["Geist-Variable.ttf", "Geist-Italic-Variable.ttf", "GeistMono-Variable.ttf", "GeistMono-Italic-Variable.ttf"]
        FontLoader { required property var modelData; source: "file://" + Quickshell.shellPath("fonts/" + modelData) }
    }
    Wallpaper {}
    NightLight {}
    PolkitAgent {}          // password prompts for apps (pkexec, system settings…)
    Notifications { id: notifs; bar: topBar }
    // Settings, built afresh whenever it's closed from outside Slate (Super+Q, a title bar's close
    // button): after that the window couldn't be shown again until Slate reloaded
    LazyLoader {
        id: settingsLoader
        active: true
        SettingsWindow {
            bar: topBar; notifs: notifs
            onClosed: settingsRebuild.restart()
        }
    }
    // Out here, not in the window: it has to outlive the window it replaces. Runs twice: the first
    // time drops the old window, the second builds the new one
    Timer {
        id: settingsRebuild
        interval: 0
        onTriggered: {
            if (settingsLoader.active) { settingsLoader.active = false; restart(); }
            else settingsLoader.active = true;
        }
    }
    Variants {
        model: Quickshell.screens
        ScreenCorners { required property var modelData; screen: modelData; bar: topBar }
    }
    // Logging in: every screen starts black and fades in with the welcome sound
    Variants {
        model: Config.welcoming ? Quickshell.screens : []
        FadeIn { required property var modelData; screen: modelData }
    }
    OSD { bar: topBar; popouts: popouts }
    LockScreen { id: lockScreen }
    Screensaver { lock: lockScreen }
    HotCorners { lock: lockScreen }

    // Keep the login screen (/var/lib/slate-greeter) in step with the wallpaper and
    // settings. Does nothing until it's been set up with: sudo slate-greeter-install
    Timer { id: greeterSync; interval: 3000; onTriggered: greeterSyncRun.running = true }
    Process {
        id: greeterSyncRun
        command: ["sh", "-c", "[ -w /var/lib/slate-greeter ] && exec \"$0\" || true", Quickshell.shellPath("bin/slate-greeter-sync")]
    }
    Connections { target: Config; function onWallpaperChanged() { greeterSync.restart(); } function onSaved() { greeterSync.restart(); } function onAvatarVersionChanged() { greeterSync.restart(); } }

    // Window borders follow the theme (and the width set in Settings): accent on the active window, the bar's colour on
    // the others (60% and 85%; Hyprland cannot blur behind borders), plus dimming and gaps. Hyprland's config
    // (colors.lua) has fallbacks; these replace them, and again after a config reload.
    readonly property string borderCmd: {
        const rgba = (c, a) => "rgba(" + c.toString().slice(1, 7) + Math.round(a * 255).toString(16).padStart(2, "0") + ")";
        const active = rgba(Config.accent, 0.6), inactive = rgba(Config.tint("#0f1216"), 0.85);
        const size = Math.max(0, Math.min(12, Config.s.windowBorderSize));   // Settings → Windows
        const dim = Math.max(0, Math.min(80, Config.s.inactiveDim)) / 100;   // Settings → Windows
        // Spacing: gaps_in is added on each side of a window, so half the gap between two;
        // the screen edges get a little more. Lone windows stay gapless (workspaces.lua)
        const gap = Math.max(0, Math.min(32, Config.s.windowGap));
        const gapIn = Math.round(gap / 2), gapOut = gap > 0 ? gap + 2 : 0;
        // A window alone on its workspace: no gaps unless set (re-sending a rule replaces it).
        // Maximised and full-screen apps always fill the screen.
        const solo = Math.max(0, Math.min(32, Config.s.soloWindowGap));
        // ...with square corners only while it fills the screen (rule in windowrules.lua)
        const solos = `hl.workspace_rule({ workspace = "w[tv1]", gaps_out = ${solo}, gaps_in = 0 }); `
            + `if SOLO_SQUARE_RULE then SOLO_SQUARE_RULE:set_enabled(${solo === 0}) end; `;
        // Window mode: the float-all rule on or off (windowrules.lua); converting open
        // windows happens only when the setting changes (below)
        const mode = `if setWindowMode then setWindowMode(${Config.floatingWindows}, false) end; `
            + `if setSpareWorkspace then setSpareWorkspace(${Config.s.keepEmptyWorkspace}) end; `;
        // Floating windows' title bars (hyprbars, when built): Slate's bar colour, text, font and button colours
        const bars = `if HYPRBARS_LOADED then pcall(hl.config, { plugin = { hyprbars = { bar_color = "${rgba(Config.tint("#0f1216"), 1)}", `
            + `col = { text = "${rgba(Config.tint("#eef1f5"), 1)}" }, inactive_button_color = "${rgba(Config.tint("#3a424e"), 1)}", `
            + `bar_text_font = [==[${Config.s.fontFamily}]==], bar_text_size = ${Math.round(13 * Config.uiScale)}, bar_height = ${Math.round(13 * 2.6 * Config.uiScale)}, `
            + `bar_buttons_alignment = "${Config.s.titleButtons === "left" ? "left" : "right"}" } } }); `
            + `if HYPRBARS_IDLE then pcall(hl.config, { plugin = { hyprbars = { idle_button_color = "${rgba(Config.tint("#5a6372"), 1)}" } } }) end end; `;
        return solos + mode + bars + `ACTIVE_BORDER = { colors = { "${active}" } }; INACTIVE_BORDER = "${inactive}"; BORDER_SIZE = ${size}; `
            + `hl.config({ general = { border_size = BORDER_SIZE, gaps_in = ${gapIn}, gaps_out = ${gapOut}, col = { active_border = ACTIVE_BORDER, inactive_border = INACTIVE_BORDER } }, `
            + `decoration = { dim_inactive = ${dim > 0}, dim_strength = ${dim.toFixed(2)} } })`;
    }
    onBorderCmdChanged: borderPush.restart()
    // Title bar button colours and size (hyprbars.lua reads them when Hyprland's config loads, as
    // hyprbars can't recolour buttons later): written here, then Hyprland reloads, only
    // when they've changed
    readonly property string barButtonsLua: {
        const rgb = c => "rgb(" + c.toString().slice(1, 7) + ")";
        return `return { accent = "${rgb(Config.accent)}", accent_text = "${rgb(Config.tint("#12151a"))}", `
            + `button_size = ${Math.round(13 * 1.25 * Config.uiScale)} }\n`;
    }
    onBarButtonsLuaChanged: barButtonsSync.restart()
    FileView {
        id: barButtonsFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/hyprbars.lua"
        blockLoading: true
        printErrors: false
    }
    Timer {
        id: barButtonsSync
        interval: 1500; running: true
        onTriggered: {
            if (barButtonsFile.text() === root.barButtonsLua) return;
            barButtonsFile.setText(root.barButtonsLua);
            barButtonsReload.restart();
        }
    }
    Timer { id: barButtonsReload; interval: 300; onTriggered: Quickshell.execDetached(["hyprctl", "reload"]) }
    // Switching window mode also floats (or re-tiles) the windows already open. Only when
    // the setting changes: title bars turning up or going away just changes new windows
    Connections {
        target: Config.s
        function onWindowModeChanged() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() if setWindowMode then setWindowMode(${Config.floatingWindows}, true) end end`]);
        }
    }
    Timer { id: borderPush; interval: 300; running: true; onTriggered: Quickshell.execDetached(["hyprctl", "eval", root.borderCmd]) }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // (and see whether title bars can be used: hyprbars may have been rebuilt)
            if (event.name === "configreloaded") { borderPush.restart(); Config.checkTitleBars(); }
            // A window closed: GTK apps waiting to pick up new colours may now restart
            else if (event.name === "closewindow") gtkRefresh.restart();
        }
    }
    Timer { id: gtkRefresh; interval: 1500; onTriggered: Quickshell.execDetached([Quickshell.shellPath("scripts/refresh-gtk-apps.sh")]) }

    // File managers' folder colour (Settings → Appearance): Papirus's folder icons in a chosen
    // colour, or the one nearest the wallpaper's (scripts/folder-colour.py)
    readonly property var folderArgs: Config.s.folderColour === "auto"
        ? (Config.wallpaperAccent !== "" ? ["--auto", Config.wallpaperAccent] : [])
        : (Config.s.folderColour !== "" ? [Config.s.folderColour] : [])
    onFolderArgsChanged: folderTimer.restart()
    Timer {
        id: folderTimer
        interval: 1200; running: true
        onTriggered: if (root.folderArgs.length) { folderRun.command = [Quickshell.shellPath("scripts/folder-colour.py")].concat(root.folderArgs); folderRun.running = true; }
    }
    Process { id: folderRun }

    // Apps switched on in Settings → Appearance → App Theming follow Slate's theme:
    // scripts/apply-theme.py writes their themes from these colours, a moment after a change
    readonly property string themeJson: JSON.stringify({
        accent: Config.accent.toString(), accentText: Config.tint("#12151a").toString(),
        bg: Config.tint("#0f1216").toString(), surface: Config.tint("#1d222a").toString(),
        surfaceHigh: Config.tint("#262c35").toString(), text: Config.tint("#eef1f5").toString(),
        dim: Config.tint("#8b94a3").toString(), error: Config.tint("#f28b8b").toString(),
        light: Config.s.lightMode,
        codeFont: Config.s.codeFontFamily,
        on: Config.s.themedApps || []
    })
    onThemeJsonChanged: themeApply.restart()
    Timer { id: themeApply; interval: 1500; running: true; onTriggered: root.applyThemes() }
    function applyThemes() {
        themeProc.running = false;
        themeProc.command = ["python3", Quickshell.shellPath("scripts/apply-theme.py"), root.themeJson];
        themeProc.running = true;
    }
    Process { id: themeProc }
    // Settings → App Theming → Refresh: write every switched-on app's theme again now
    Binding { target: Config; property: "themesBusy"; value: themeProc.running }
    Connections { target: Config; function onRefreshThemes() { themeApply.stop(); root.applyThemes(); } }

    // When the login screen's code has changed, offer to install it (a notification
    // with an Update button, then a password prompt). Checked 20 s after Slate starts
    // (it reloads whenever its own code is edited) and after the greeter-only files
    // change, so a run of edits gives one prompt.
    Timer { id: greeterCodeCheck; interval: 20000; running: true; onTriggered: greeterPrompt.running = true }
    Process { id: greeterPrompt; command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--prompt"] }
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
    Switcher {
        id: winSwitcher
        bar: topBar
        onShownChanged: if (shown) { appLauncher.closeLauncher(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    WorkspaceOverview {
        id: wsOverview
        bar: topBar
        onShownChanged: if (shown) { appLauncher.closeLauncher(); winSwitcher.cancel(); popouts.close(); picker.close(); }
    }
    // Your own tweaks: the hypr/*.lua files and user/shell.qml (made with instructions in them
    // if missing; saving one reloads Hyprland's config or Slate)
    UserFiles {}
    // No "Configuration reloaded" popup when Slate reloads (after an update or a setting that
    // needs it, or a code change): it covered the top of the screen and got in the way of the
    // panels. Slate's own notice instead (a notification, kept in history like any other), for
    // a reload that worked and one that failed, and one when Hyprland reloads its config, with
    // any errors in it
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); reloadNotice.restart(); }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup(); root.reloadFailedNotice(errorString); }
    }
    // A failed reload leaves this (the previous) Slate running, so it can say so straight away.
    // Quickshell's error is a chain of "caused by @File.qml[line:col]: …"; the last link is
    // where the mistake is, so that leads
    property string lastReloadError: ""
    property var brokenFiles: []            // the files in the failed reload's error
    function reloadFailedNotice(error) {
        if (String(error) === lastReloadError) return;      // Quickshell reports a failure twice
        lastReloadError = String(error);
        const lines = String(error).split("\n").map(l => l.trim()).filter(l => l !== "");
        const links = lines.map(l => l.match(/@([^\[\]]+)\[(-?\d+):-?\d+\]:\s*(.*)$/)).filter(m => m);
        let body;
        if (links.length) {
            const cause = links[links.length - 1];
            const where = cause[1] + (parseInt(cause[2]) > 0 ? ", line " + cause[2] : "");
            const via = links.length > 1 ? links[links.length - 2][1] : "";
            body = cause[3] + " (" + where + (via ? ", used by " + via : "") + ").";
        } else {
            body = lines.slice(0, 3).join(" ");
        }
        brokenFiles = [...new Set(links.map(m => m[1]))];
        Quickshell.execDetached(["notify-send", "--app-name=Slate", "--urgency=critical", "--hint=string:x-slate-page:about",
            "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"),
            "Slate couldn't reload", body + " Still running the previous version; it reloads when you save the fix."]);
    }
    // After a failed reload Quickshell stops reloading when files change, until it's restarted.
    // So watch the files the error names, and reload as soon as one is saved
    Variants {
        model: root.brokenFiles
        FileView {
            required property string modelData
            path: Quickshell.shellPath(modelData)
            watchChanges: true
            printErrors: false
            onFileChanged: { root.brokenFiles = []; root.lastReloadError = ""; Quickshell.reload(false); }
        }
    }
    Timer {
        id: reloadNotice
        interval: 600          // once the new Slate (and its notification server) is up
        onTriggered: Quickshell.execDetached(["notify-send", "--app-name=Slate", "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"), "--hint=string:x-slate-page:about",
            "Slate reloaded", "Slate restarted on its updated files and settings."])
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") { hyprErrors.running = false; hyprErrors.running = true; } }
    }
    Process {
        id: hyprErrors
        command: ["hyprctl", "-j", "configerrors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let errs = [];
                try { errs = JSON.parse(text).filter(e => e && String(e).trim() !== ""); } catch (e) {}
                const icon = "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png");
                if (errs.length === 0)
                    Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--hint=string:x-slate-page:windows", "Hyprland settings reloaded", "Hyprland read its config again."]);
                else
                    Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--hint=string:x-slate-page:windows", "Hyprland settings have errors",
                        errs.join("\n").split("\n").slice(0, 6).join("\n")]);
            }
        }
    }
    // The welcome: the first time Slate starts, and from Settings → About
    Welcome { bar: topBar }
    // New releases: checked daily, a notification when one's out (Settings → Updates)
    readonly property bool updateAvailable: Updates.available
    // A space's colour and icon on the windows it opened (Settings → Menu Bar → Mark windows from a space)
    SpaceBadges { bar: topBar; suppressed: appLauncher.shown || winSwitcher.shown || wsOverview.shown || picker.shown || popouts.shown }

    PanelWindow {
        id: win
        // The dock is on the focused screen
        screen: Config.focusedScreen

        // ---- Settings ------------------------------------------------------
        // Pinned apps (changed from the right-click menu; saved to dock.json). On first run
        // the dock pins whichever of these common apps are installed.
        property var pinned: []
        readonly property var firstRunApps: [
            "firefox", "org.mozilla.firefox", "chromium", "google-chrome", "brave-browser",
            "kitty", "com.mitchellh.ghostty", "org.gnome.Console", "org.kde.konsole", "Alacritty", "foot",
            "org.gnome.Nautilus", "org.kde.dolphin", "thunar", "nemo",
            "code", "code-oss", "org.gnome.TextEditor", "org.kde.kate",
            "spotify", "spotify-launcher", "steam", "org.gnome.Settings"
        ]
        FileView {
            id: dockState
            path: Quickshell.env("HOME") + "/.local/state/slate/dock.json"
            blockLoading: true
            onLoaded: { try { const d = JSON.parse(text()); if (Array.isArray(d.pinned)) win.pinned = d.pinned; } catch (e) {} }
            onLoadFailed: firstRun.start()
        }
        // App entries load in the background; give them a moment before choosing
        Timer {
            id: firstRun
            interval: 1500
            onTriggered: {
                const seen = new Set();
                win.pinned = win.firstRunApps.filter(id => {
                    const e = DesktopEntries.byId(id);
                    if (!e || seen.has(e.id)) return false;
                    seen.add(e.id);
                    return true;
                }).slice(0, 8);
                win.savePinned();
            }
        }
        function savePinned() { dockState.setText(JSON.stringify({ pinned: pinned }, null, 1)); }
        function setPinned(key, on) {
            const list = pinned.filter(k => k !== key);
            if (on) list.push(key);
            pinned = list;
            savePinned();
        }
        readonly property real base: Config.s.dockIconSize           // icon size at rest (logical px)
        readonly property real maxScale: Config.s.dockMagnification  // size of the icon under the pointer
        readonly property real spread: Config.s.dockSpread           // how many icons either side grow
        readonly property real spacing: 8
        readonly property real padding: 8        // inside the dock background
        // How rounded the icons' corners are (Settings → Appearance → App icons), for the dock's own corners
        readonly property real iconCorner: {
            const shape = Config.s.iconShape;
            return shape === "circle" ? base / 2 : shape === "square" ? 0 : shape === "squircle" ? base * 0.3 : base * 0.225;
        }
        readonly property real bottomGap: 0      // gap between dock and screen edge
        readonly property int hideDelay: 700     // ms after the pointer leaves
        readonly property color bgColor: Config.surface(Config.tint("#0f1216"))      // same as the top bar
        readonly property color tileColor: Config.raised(Config.tint("#1d222a"))
        readonly property color textColor: Config.tint("#eef1f5")
        readonly property color dotColor: Config.tint("#c5ccd6")
        readonly property color activeDotColor: Config.accent
        readonly property string fontFamily: Config.s.fontFamily   // Settings → Appearance → Fonts
        readonly property int fontWeight: Font.Medium   // bar font weight 500
        readonly property real fontSize: 13             // matches the bar text
        readonly property string tileScript: Config.tileScript
        readonly property string tileDir: Config.tileDir

        // ---- Window --------------------------------------------------------
        // Which screen edge (Settings → Dock → Position; bottom becomes top when the bar is at
        // the bottom). The dock is laid out as a horizontal strip whose bottom edge meets the
        // screen; for other edges that strip is turned (stripMatrix) and each icon, label and
        // symbol is turned back (upright()), so all the layout and magnification maths stays
        // the same.
        readonly property string edge: Config.dockEdge
        readonly property bool vertical: edge === "left" || edge === "right"
        readonly property real thickness: Math.ceil(base * maxScale + padding * 2 + bottomGap + 40)
        anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
        implicitHeight: vertical ? 0 : thickness
        implicitWidth: vertical ? thickness : 0
        readonly property real stripLength: vertical ? height : width
        // strip coordinates → window coordinates
        readonly property matrix4x4 stripMatrix: {
            const T = thickness;
            if (edge === "top") return Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, T,  0, 0, 1, 0,  0, 0, 0, 1);   // mirrored
            if (edge === "left") return Qt.matrix4x4(0, -1, 0, T,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1);  // turned 90°
            if (edge === "right") return Qt.matrix4x4(0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1);  // turned + mirrored
            return Qt.matrix4x4();
        }
        // Undoes stripMatrix for an item of size w × h (about its centre), keeping it upright
        function upright(w, h) {
            const cx = w / 2, cy = h / 2;
            if (edge === "top") return Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, h,  0, 0, 1, 0,  0, 0, 0, 1);
            if (edge === "left") return Qt.matrix4x4(0, 1, 0, cx - cy,  -1, 0, 0, cy + cx,  0, 0, 1, 0,  0, 0, 0, 1);
            if (edge === "right") return Qt.matrix4x4(0, 1, 0, cx - cy,  1, 0, 0, cy - cx,  0, 0, 1, 0,  0, 0, 0, 1);
            return Qt.matrix4x4();
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "slate-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: maskBox }
        // The input area in window coordinates (hitArea is in the turned strip)
        Item {
            id: maskBox
            readonly property var box: {
                win.stripMatrix; hitArea.x; hitArea.y; hitArea.width; hitArea.height;   // re-evaluate on these
                const a = hitArea.mapToItem(win.contentItem, 0, 0), b = hitArea.mapToItem(win.contentItem, hitArea.width, hitArea.height);
                return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) };
            }
            x: box.x; y: box.y; width: box.w; height: box.h
        }

        // ---- Apps: pinned first, then anything else that's running ---------
        function entryFor(id) {
            return DesktopEntries.byId(id) ?? lookup(id);
        }
        // Best app entry for a window's app ID. Falls back to entries sharing its
        // reverse-domain prefix (org.godotengine.Editor -> org.godotengine.Godot).
        function lookup(appId) {
            const e = DesktopEntries.heuristicLookup(appId);
            if (e) return e;
            const parts = (appId || "").toLowerCase().split(".");
            if (parts.length < 3) return null;
            const prefix = parts.slice(0, 2).join(".") + ".";
            return DesktopEntries.applications.values.find(a => a.id.toLowerCase().startsWith(prefix)) ?? null;
        }
        function belongsTo(t, id, e) {
            const a = (t.appId || "").toLowerCase();
            if (a === id.toLowerCase()) return true;
            if (!e) return false;
            if (a === (e.startupClass || "").toLowerCase() || a === (e.id || "").toLowerCase()) return true;
            const h = lookup(t.appId);
            return h !== null && h.id === e.id;
        }
        property var items: {
            DesktopEntries.applications.values;   // rebuild once app entries have loaded
            const tops = ToplevelManager.toplevels.values;
            const out = [];
            const claimed = new Set();
            for (const id of pinned) {
                const e = entryFor(id);
                const wins = tops.filter(t => !claimed.has(t) && belongsTo(t, id, e));
                if (!e && wins.length === 0) continue;   // pinned app that's no longer installed
                wins.forEach(t => claimed.add(t));
                out.push({ key: id, entry: e, windows: wins });
            }
            for (const t of tops) {
                if (claimed.has(t)) continue;
                const e = lookup(t.appId);
                const key = e ? e.id : t.appId;
                const existing = out.find(o => o.key === key);
                if (existing) existing.windows.push(t);
                else out.push({ key: key, entry: e, windows: [t] });
            }
            return out;
        }

        // ---- Magnification -------------------------------------------------
        readonly property int count: items.length + 1          // +1 for the launcher
        readonly property real restWidth: count * base + (count - 1) * spacing
        property real pointerX: -1000                          // in rest-layout coordinates
        // Magnification stays frozen while the right-click menu is open
        property real hover: (mouse.containsMouse && shown) || appMenu.visible ? 1 : 0
        Behavior on hover { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        function scaleAt(i) {
            const centre = i * (base + spacing) + base / 2;
            const t = Math.abs(pointerX - centre) / (base * spread);
            const f = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return 1 + (maxScale - 1) * f * hover;
        }
        function cellX(i) {
            let x = 0;
            for (let j = 0; j < i; j++) x += base * scaleAt(j) + spacing;
            return x;
        }
        readonly property int hoveredIndex: {
            if (hover <= 0) return -1;
            const i = Math.floor((pointerX + spacing / 2) / (base + spacing));
            return i >= 0 && i < count ? i : -1;
        }

        // ---- Auto-hide -----------------------------------------------------
        readonly property bool workspaceBusy: (Hyprland.focusedWorkspace?.toplevels?.values?.length ?? 0) > 0
        property bool shown: !Config.s.dockAutoHide || (!workspaceBusy && !appLauncher.launchingNew) || mouse.containsMouse || holdTimer.running || appMenu.visible
        Timer { id: holdTimer; interval: win.hideDelay }
        readonly property real dockHeight: base + padding * 2
        property real offset: shown ? 0 : dockHeight + bottomGap + 4
        Behavior on offset { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        // Open an app's menu by its key, e.g.  slate ipc call dock menu firefox
        IpcHandler {
            target: "dock"
            function menu(key: string): void {
                const i = win.items.findIndex(it => it.key === key);
                if (i < 0) return;
                const x = (strip.width - win.restWidth) / 2 + (i + 1) * (win.base + win.spacing) + win.base / 2;
                appMenu.openFor(win.items[i], x);
            }
            function closeMenu(): void { appMenu.closeMenu(); }
        }

        // ---- Right-click menu ----------------------------------------------
        // A full-screen invisible layer while open: clicking anywhere outside the menu
        // (or pressing Escape) closes it
        PanelWindow {
            id: appMenu
            screen: win.screen          // with the dock (which follows the focused screen)
            property var app: null
            property real menuX: 0      // just inside the dock's inner edge, by the icon (screen coordinates)
            property real menuY: 0
            readonly property var entry: app ? app.entry : null
            readonly property var wins: app ? app.windows : []
            readonly property bool isPinned: app && app.key ? win.pinned.includes(app.key) : false

            // x: the icon's centre along the dock (strip coordinates)
            function openFor(a, x) {
                app = a;
                // A little off the dock: room for the menu's pointer
                const p = strip.mapToItem(win.contentItem, x, bg.y - 16);
                const sw = win.screen ? win.screen.width : 0, sh = win.screen ? win.screen.height : 0;
                menuX = p.x + (win.edge === "right" ? sw - win.width : 0);
                menuY = p.y + (win.edge === "bottom" ? sh - win.height : 0);
                visible = true;
            }
            function closeMenu() { visible = false; }

            // Rows: open windows, the app's own actions, then New Window / Pin / Quit. For the
            // launcher button: Settings and a few of the places most often wanted in it
            readonly property var rows: {
                if (!app) return [];
                const r = [];
                if (app.settingsMenu) {
                    r.push({ label: "Settings", kind: "settings", target: "overview" });
                    r.push({ kind: "sep" });
                    r.push({ label: "Appearance", kind: "settings", target: "appearance" });
                    r.push({ label: "Wallpaper", kind: "settings", target: "appearance", find: "Wallpaper" });
                    r.push({ label: "Displays", kind: "settings", target: "displays" });
                    r.push({ label: "Wi-Fi", kind: "settings", target: "wifi" });
                    r.push({ label: "Bluetooth", kind: "settings", target: "bluetooth" });
                    return r;
                }
                if (wins.length > 0) {
                    for (const w of wins) r.push({ label: w.title || app.key, kind: "window", target: w, active: w.activated });
                    r.push({ kind: "sep" });
                }
                if (entry) {
                    for (const act of entry.actions) r.push({ label: act.name, kind: "action", target: act });
                    // Only add our own "New Window" if the app doesn't provide one
                    if (!entry.actions.some(a => (a.name || "").toLowerCase() === "new window"))
                        r.push({ label: "New Window", kind: "new" });
                    r.push({ kind: "sep" });
                }
                r.push({ label: isPinned ? "Unpin from Dock" : "Pin to Dock", kind: "pin" });
                // Closes every window the app has open, whether one or several
                if (wins.length > 0) r.push({ label: wins.length === 1 ? "Close Window" : "Close " + wins.length + " Windows", kind: "quit", danger: true });
                return r;
            }
            function run(row) {
                switch (row.kind) {
                case "window": row.target.activate(); break;
                case "action": row.target.execute(); break;
                case "new": entry.execute(); break;
                case "pin": win.setPinned(app.key, !isPinned); break;
                case "quit": for (const w of wins) w.close(); break;
                case "settings": if (settingsLoader.item) settingsLoader.item.goTo(row.target, row.find || ""); break;
                }
                closeMenu();
            }

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            visible: false
            WlrLayershell.namespace: "slate-dock-menu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: appMenu.closeMenu()
            }
            Item {
                focus: appMenu.visible
                Keys.onEscapePressed: appMenu.closeMenu()
            }

            Rectangle {
                width: 240
                height: menuCol.implicitHeight + 16
                // Opens away from the dock's edge
                x: Math.max(8, Math.min(appMenu.width - width - 8,
                    win.edge === "left" ? appMenu.menuX : win.edge === "right" ? appMenu.menuX - width : appMenu.menuX - width / 2))
                y: Math.max(8, Math.min(appMenu.height - height - 8,
                    win.edge === "bottom" ? appMenu.menuY - height : win.edge === "top" ? appMenu.menuY : appMenu.menuY - height / 2))
                radius: 12
                color: win.bgColor
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside don't close

                // Pointer: a small triangle on the side facing the dock, at the icon (it slides along
                // the edge to stay on the icon when the menu is held in from the screen's edge). A
                // turned square under the menu, so only its point shows.
                Rectangle {
                    readonly property bool sideDock: win.edge === "left" || win.edge === "right"
                    // Where the icon is along the menu's edge, kept clear of the rounded corners
                    readonly property real along: sideDock
                        ? Math.max(18, Math.min(parent.height - 18, appMenu.menuY - parent.y))
                        : Math.max(18, Math.min(parent.width - 18, appMenu.menuX - parent.x))
                    z: -1
                    width: 14; height: 14
                    rotation: 45
                    color: parent.color
                    x: win.edge === "left" ? -width / 2 : win.edge === "right" ? parent.width - width / 2 : along - width / 2
                    y: win.edge === "top" ? -height / 2 : win.edge === "bottom" ? parent.height - height / 2 : along - height / 2
                }

                Column {
                    id: menuCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 1

                    Repeater {
                        model: appMenu.rows
                        delegate: Item {
                            id: menuRow
                            required property var modelData
                            width: menuCol.width
                            height: modelData.kind === "sep" ? 9 : 30

                            Rectangle {
                                visible: menuRow.modelData.kind === "sep"
                                anchors.centerIn: parent
                                width: parent.width - 16; height: 1
                                color: win.tileColor
                            }
                            Rectangle {
                                visible: menuRow.modelData.kind !== "sep"
                                anchors.fill: parent
                                radius: 7
                                color: rowHover.hovered ? Config.hover : "transparent"
                                Gloss { radius: parent.radius; opacity: (rowHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                Behavior on color { ColorAnimation { duration: 90 } }
                                Rectangle {
                                    visible: !!menuRow.modelData.active
                                    width: 5; height: 5; radius: 2.5
                                    color: win.activeDotColor
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                }
                                Text {
                                    anchors { left: parent.left; right: parent.right; leftMargin: 20; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: menuRow.modelData.label || ""
                                    color: menuRow.modelData.danger ? Config.tint("#f28b8b") : win.textColor
                                    font.family: win.fontFamily
                                    font.pixelSize: win.fontSize
                                    font.weight: win.fontWeight
                                    elide: Text.ElideRight
                                }
                                HoverHandler { id: rowHover }
                                ClickTap { onTapped: appMenu.run(menuRow.modelData) }
                            }
                        }
                    }
                }
            }
        }

        // ---- Pointer input --------------------------------------------------
        // Kept outside the turned strip: Qt mixes transformed and untransformed coordinates
        // for hover under a mirroring/rotating transform, so a pointer area inside the strip
        // thinks the pointer has left when it hasn't (top and side docks). This one sits
        // over the dock in window coordinates and maps the pointer into the strip itself.
        ClickArea {
            id: mouse
            z: 10
            anchors.fill: maskBox
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            function stripX(m) { return strip.mapFromItem(mouse, m.x, m.y).x; }
            onPositionChanged: m => win.pointerX = stripX(m) - (strip.width - win.restWidth) / 2
            onExited: holdTimer.restart()
            onClicked: m => {
                win.pointerX = stripX(m) - (strip.width - win.restWidth) / 2;
                win.clickItem(win.hoveredIndex, m.button === Qt.RightButton);
            }
        }
        // Click on dock item i (0 = the apps button)
        // ---- Launching: the icon bounces until the app's first window shows -----
        // Kept here by app key, not in the icons: the dock rebuilds its icons whenever a window
        // opens, which would cut a hop off mid-air. Each hop: up, down, a short rest.
        readonly property int hopUp: 260
        readonly property int hopDown: 260
        readonly property int hopRest: 180
        readonly property int hopCycle: hopUp + hopDown + hopRest
        readonly property int launchTimeoutMs: 12000      // give up on apps that never open a window
        // app key → { start, until }: hopping from start; until (once the app is up, or it timed
        // out) is the end of the hop in progress, so it lands before stopping
        property var launching: ({})
        property real clock: Date.now()
        FrameAnimation {
            running: Object.keys(win.launching).length > 0
            onTriggered: {
                win.clock = Date.now();
                let changed = false;
                const l = Object.assign({}, win.launching);
                for (const k in l) {
                    if (!l[k].until && win.clock - l[k].start > win.launchTimeoutMs) { win.endLaunch(k); return; }
                    if (l[k].until && win.clock >= l[k].until) { delete l[k]; changed = true; }
                }
                if (changed) win.launching = l;
            }
        }
        function startLaunch(key) {
            const l = Object.assign({}, launching);
            l[key] = { start: Date.now(), until: 0 };
            launching = l;
        }
        // The app is up: finish the hop in progress (stop now if it's resting on the dock)
        function endLaunch(key) {
            const b = launching[key];
            if (!b || b.until) return;
            const now = Date.now(), phase = (now - b.start) % hopCycle;
            const l = Object.assign({}, launching);
            l[key] = { start: b.start, until: phase < hopUp + hopDown ? now + (hopUp + hopDown - phase) : now };
            launching = l;
        }
        // How high an app's icon is now: 0 on the dock, 1 at the top of a hop
        function bounceOf(key) {
            const b = launching[key];
            if (!b) return 0;
            const phase = (clock - b.start) % hopCycle;
            if (phase < hopUp) { const p = phase / hopUp; return 1 - (1 - p) * (1 - p); }              // rising, slowing
            if (phase < hopUp + hopDown) { const q = (phase - hopUp) / hopDown; return 1 - q * q; }   // falling, speeding up
            return 0;
        }

        function clickItem(i, right) {
            if (i < 0) return;
            if (i === 0) {
                // The launcher button: opens the launcher; right-click for shortcuts to Settings pages
                if (right) appMenu.openFor({ settingsMenu: true, key: "", windows: [] }, row.x + cellX(0) + base * scaleAt(0) / 2);
                else appLauncher.shown ? appLauncher.closeLauncher() : appLauncher.openLauncher();
                return;
            }
            const item = items[i - 1];
            if (!item) return;
            if (right) {   // menu by the icon's centre along the dock
                appMenu.openFor(item, row.x + cellX(i) + base * scaleAt(i) / 2);
                return;
            }
            const wins = item.windows;
            if (wins.length === 0) { if (item.entry) { startLaunch(item.key); item.entry.execute(); } return; }
            const cur = wins.findIndex(w => w.activated);
            wins[(cur + 1) % wins.length].activate();
        }

        // ---- The strip: dock, pointer area and label, turned to face the dock's edge ----
        Item {
            id: strip
            width: win.stripLength
            height: win.thickness
            transform: Matrix4x4 { matrix: win.stripMatrix }

            // Area that takes pointer input: the dock (plus room above it while magnified),
            // or a thin strip at the screen edge while hidden
            Item {
                id: hitArea
                x: (strip.width - width) / 2
                width: Math.max(row.width + win.padding * 2, win.restWidth + win.padding * 2)
                height: !win.shown ? 2 : (win.hover > 0 ? strip.height : win.dockHeight + win.bottomGap)
                y: strip.height - height
            }


            // ---- Drawing -------------------------------------------------------
            Item {
                id: dock
                anchors.fill: parent
                transform: Translate { y: win.offset }

                Rectangle {
                    id: bg
                    width: row.width + win.padding * 2
                    height: win.dockHeight
                    x: (strip.width - width) / 2
                    y: strip.height - height - win.bottomGap
                    // Corners that follow the icons': the icons' own corner plus half the gap around
                    // them (a fully concentric corner looks too round); a pill for circles
                    radius: Config.s.iconShape === "circle" ? height / 2 : Math.min(height / 2, win.iconCorner + win.padding / 2)
                    bottomLeftRadius: 0     // flush with the screen edge
                    bottomRightRadius: 0
                    color: win.bgColor
                    Gloss { radius: parent.radius }   // glass: a sheen
                }

                Row {
                    id: row
                    spacing: win.spacing
                    x: (strip.width - width) / 2
                    y: bg.y + bg.height - win.padding - height
                    height: win.base * win.maxScale

                    // Launcher button
                    Item {
                        readonly property real s: win.scaleAt(0)
                        width: win.base * s
                        height: row.height
                        Item {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            id: launchTile
                            transform: Matrix4x4 { matrix: win.upright(launchTile.width, launchTile.height) }
                            // The same shape as the app icons (a tile when they're shown as they come)
                            IconPlate {
                                anchors.fill: parent
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true }
                            // Three soft rounded bars, as on the bar's Apps button, scaled with the tile
                            Column {
                                id: burger
                                anchors.centerIn: parent
                                readonly property real w: parent.width
                                spacing: w * 0.075
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: burger.w * 0.42; height: burger.w * 0.07
                                        radius: height / 2
                                        color: win.textColor
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: win.items
                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property real s: win.scaleAt(index + 1)
                            readonly property string tilePath: win.tileDir + "/" + modelData.key.replace(/[^A-Za-z0-9._-]/g, "_") + ".png"
                            property int version: 0
                            property string tried: ""       // the icon file last drawn for (once per file, so a broken icon isn't retried forever)
                            // Bounces while the app is starting (clicked in the dock): see win.bounceOf
                            readonly property real bounce: win.bounceOf(cell.modelData.key)
                            readonly property int windowCount: cell.modelData.windows.length
                            onWindowCountChanged: if (windowCount > 0) win.endLaunch(cell.modelData.key)
                            Component.onCompleted: if (windowCount > 0) win.endLaunch(cell.modelData.key)
                            width: win.base * s
                            height: row.height

                            Image {
                                anchors.bottom: parent.bottom
                                id: tileImg
                                width: parent.width; height: width
                                // Upright for the dock's edge, then the launch bounce (away from the edge)
                                transform: [
                                    Matrix4x4 { matrix: win.upright(tileImg.width, tileImg.height) },
                                    Translate { y: -cell.bounce * win.base * 0.4 }
                                ]
                                source: "file://" + cell.tilePath + "?v=" + cell.version + "." + Config.tileVersion
                                sourceSize: Qt.size(192, 192)
                                smooth: true
                                mipmap: true
                                cache: false
                                layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                                onStatusChanged: if (status === Image.Error && !gen.running && cell.tried !== cell.tilePath) { cell.tried = cell.tilePath; gen.running = true; }
                                IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
                                // Glass: a sheen, rounded like the icon tiles (not on icons shown as
                                // they come, which have no tile to follow)
                                Gloss {
                                    glassHint: true
                                    visible: Config.glassGloss && Config.s.iconShape !== "original"
                                    radius: parent.width * win.iconCorner / Math.max(1, win.base)
                                }
                            }

                            // Draw the tile the first time this app shows up
                            Process {
                                id: gen
                                command: Config.tileCommand(cell.modelData.entry ? cell.modelData.entry.id : cell.modelData.key, cell.tilePath)
                                onExited: cell.version++
                            }

                            // Running indicator: a short rounded bar (accent for the focused app)
                            Rectangle {
                                readonly property bool focusedApp: cell.modelData.windows.some(w => w.activated)
                                visible: cell.modelData.windows.length > 0
                                width: 12; height: 3; radius: 1.5
                                color: focusedApp ? win.activeDotColor : win.dotColor
                                // Snapped to whole device pixels: the icons move by fractions of a
                                // pixel while magnifying, which would make the bar shimmer and look
                                // like it changes length
                                readonly property real dpr: win.screen ? win.screen.devicePixelRatio : 1
                                x: Math.round((cell.x + (cell.width - width) / 2) * dpr) / dpr - cell.x
                                y: Math.round((parent.height + (win.padding - height) / 2) * dpr) / dpr
                            }

                        }
                    }
                }

                // App name above the icon under the pointer
                Rectangle {
                    id: label
                    readonly property string text: win.hoveredIndex === 0 ? "Apps"
                        : (win.hoveredIndex > 0 && win.items[win.hoveredIndex - 1]
                            ? (win.items[win.hoveredIndex - 1].entry?.name ?? win.items[win.hoveredIndex - 1].key) : "")
                    readonly property real iconSize: win.hoveredIndex >= 0 ? win.base * win.scaleAt(win.hoveredIndex) : 0
                    visible: win.hoveredIndex >= 0 && win.hover > 0.9 && text !== "" && !appMenu.visible
                    width: labelText.implicitWidth + 16
                    height: labelText.implicitHeight + 8
                    radius: 6
                    color: win.bgColor
                    Gloss { radius: parent.radius }   // glass: a sheen
                    x: row.x + win.cellX(Math.max(0, win.hoveredIndex)) + iconSize / 2 - width / 2
                    // On a side dock the label is turned upright, so its width runs across the strip
                    readonly property real across: win.vertical ? width : height
                    y: row.y + row.height - iconSize - 8 - across / 2 - height / 2
                    transform: Matrix4x4 { matrix: win.upright(label.width, label.height) }
                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: label.text.charAt(0).toUpperCase() + label.text.slice(1)   // kitty -> Kitty
                        color: win.textColor
                        font.family: win.fontFamily
                        font.weight: win.fontWeight
                        font.pixelSize: win.fontSize
                    }
                }
            }
        }
    }
}
