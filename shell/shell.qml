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
import Qt.labs.folderlistmodel
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

ShellRoot {
    id: root
    // Logging in: every screen starts black and fades in with the welcome sound.
    // First, so its windows open before the wallpaper and bar
    Variants {
        model: Config.welcoming ? Quickshell.screens : []
        FadeIn { required property var modelData; screen: modelData }
    }
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
    // Logging out, restarting, shutting down: every screen fades to black with the goodbye sound
    Variants {
        model: Config.leaving ? Quickshell.screens : []
        FadeOut { required property var modelData; screen: modelData }
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
        // Glass (with its gloss): a sheen on the borders, as Hyprland can draw one. Its gradients
        // spread their colours evenly, so the light is the first of several: a bright catch on
        // the top left corner, fading within the first sixth or so into the colour itself, a
        // touch deeper at the far corner (how strong follows Glass → Gloss). Hyprland's angles
        // put the first colour at the left for 0°, the top for 90°: 45° is the top left.
        // Without glass (or in game mode), flat
        const toWhite = (c, k) => Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1);
        const g = Config.glassGloss ? Math.min(1, Config.glossAmount) : 0;
        const sheen = (base, a, light, soft, deep) => [rgba(toWhite(base, light * g), Math.min(1, a + 0.3 * g)), rgba(toWhite(base, soft * g), a),
            rgba(base, a), rgba(base, a), rgba(base, a), rgba(base, a), rgba(Qt.darker(base, 1 + deep * g), a)].map(c => `"${c}"`).join(", ");
        const activeColors = g > 0 ? sheen(Config.accent, 0.6, 0.75, 0.3, 0.2) : `"${active}"`;
        const inactiveBorder = g > 0
            ? `{ colors = { ${sheen(Config.tint("#0f1216"), 0.85, 0.3, 0.1, 0)} }, angle = 45 }`
            : `"${inactive}"`;
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
        return solos + mode + bars + `ACTIVE_BORDER = { colors = { ${activeColors} }${g > 0 ? ", angle = 45" : ""} }; INACTIVE_BORDER = ${inactiveBorder}; BORDER_SIZE = ${size}; `
            + `hl.config({ general = { border_size = BORDER_SIZE, gaps_in = ${gapIn}, gaps_out = ${gapOut}, col = { active_border = ACTIVE_BORDER, inactive_border = INACTIVE_BORDER } }, `
            + `decoration = { dim_inactive = ${dim > 0}, dim_strength = ${dim.toFixed(2)} } })`;
    }
    onBorderCmdChanged: borderPush.restart()
    // Title bar button colours and size (hyprbars.lua reads them when Hyprland's config loads, as
    // hyprbars can't recolour buttons later): written here, then Hyprland reloads, only when
    // they've changed and title bars are showing (floating mode). In tiling mode there are none to
    // recolour, so the reload waits until floating mode comes on: a reload makes the screen
    // flicker, and the accent changes with every theme preset and, from the wallpaper, with it
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
            if (Config.floatingWindows) barButtonsReload.restart();
            else root.barButtonsStale = true;
        }
    }
    // Written while there were no title bars; Hyprland hasn't read them yet
    property bool barButtonsStale: false
    Connections {
        target: Config
        function onFloatingWindowsChanged() { if (Config.floatingWindows && root.barButtonsStale) barButtonsReload.restart(); }
    }
    Timer { id: barButtonsReload; interval: 300; onTriggered: { root.barButtonsStale = false; Config.reloadHyprland(); } }
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
        target: Config
        // Hyprland reloaded: borders go back (and see whether title bars can be used: hyprbars
        // may have been rebuilt), and check the config for errors
        function onHyprConfigReloaded() {
            borderPush.restart();
            Config.checkTitleBars();
            root.barButtonsStale = false;
            hyprErrors.running = false; hyprErrors.running = true;
        }
    }
    Connections {
        target: Hyprland
        // A window closed: GTK apps waiting to pick up new colours may now restart
        function onRawEvent(event) { if (event.name === "closewindow") gtkRefresh.restart(); }
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
        // The cursor size set in Settings (0 = not set): Slate's own environment still has the
        // size from when it started, so apps would get the old one back without this
        cursorSize: Config.s.cursorSize,
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
    // (hyprErrors runs again whenever Hyprland reloads: see onHyprConfigReloaded above)
    Process {
        id: hyprErrors
        command: ["hyprctl", "-j", "configerrors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let errs = [];
                try { errs = JSON.parse(text).filter(e => e && String(e).trim() !== ""); } catch (e) {}
                const icon = "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png");
                // No news when Slate reloaded it itself (to apply a setting); errors always show
                if (errs.length === 0 && Config.ownHyprReload()) return;
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
    // Nothing reads this, but keep it: it's what creates the Updates singleton at start (its
    // daily check and the "updates" IPC), as singletons are only made when first used
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
        // Icon size at rest (logical px): as set in Settings, shrunk only when that many icons
        // wouldn't fit along the screen's edge (a short screen, a side dock, lots of apps open),
        // with room left at the ends for the dock's padding and the magnified icons
        readonly property real base: Math.max(16, Math.min(Config.s.dockIconSize,
            (stripLength - 48 - padding * 2 - (count - 1) * spacing) / Math.max(1, count)))
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
        function belongsTo(t, id, e) {
            const a = (t.appId || "").toLowerCase();
            if (a === id.toLowerCase()) return true;
            if (!e) return false;
            if (a === (e.startupClass || "").toLowerCase() || a === (e.id || "").toLowerCase()) return true;
            const h = Config.appEntry(t.appId);
            return h !== null && h.id === e.id;
        }
        property var items: {
            DesktopEntries.applications.values;   // rebuild once app entries have loaded
            const tops = ToplevelManager.toplevels.values;
            const out = [];
            const claimed = new Set();
            for (const id of pinned) {
                const e = Config.appEntry(id);
                const wins = tops.filter(t => !claimed.has(t) && belongsTo(t, id, e));
                if (!e && wins.length === 0) continue;   // pinned app that's no longer installed
                wins.forEach(t => claimed.add(t));
                out.push({ key: id, entry: e, windows: wins, pinned: true });
            }
            for (const t of tops) {
                if (claimed.has(t)) continue;
                const e = Config.appEntry(t.appId);
                const key = e ? e.id : t.appId;
                const existing = out.find(o => o.key === key);
                if (existing) existing.windows.push(t);
                else out.push({ key: key, entry: e, windows: [t], pinned: false });
            }
            return out;
        }

        // ---- Magnification -------------------------------------------------
        // ---- The dock's slots, in order ---------------------------------------------
        // The launcher, what's playing (while something is) and a divider, the pinned apps, a
        // divider, the other running apps, a divider, Downloads and the Waste Basket. Each slot knows its
        // place (at); everything that finds or places one goes through this list
        readonly property var slots: {
            const s = [];
            const add = o => { o.at = s.length; s.push(o); };
            add({ kind: "launcher" });
            const dividers = Config.s.dockDivider;
            if (mediaShown) {
                add({ kind: "media" });
                if (dividers && items.length > 0) add({ kind: "divider" });     // and one after it
            }
            items.forEach((it, i) => {
                // between the pinned apps and the others (when there are both)
                if (dividers && i > 0 && !it.pinned && items[i - 1].pinned) add({ kind: "divider" });
                add({ kind: "app", item: it });
            });
            if (dividers && items.length > 0 && (downloadsShown || trashShown)) add({ kind: "divider" });
            if (downloadsShown) add({ kind: "downloads" });
            if (trashShown) add({ kind: "trash" });
            return s;
        }
        // The slots drawn by the apps' Repeater: the apps and the dividers between them
        readonly property var middleSlots: slots.filter(x => x.kind === "app" || x.kind === "divider")
        function slotAt(i) { return i >= 0 && i < slots.length ? slots[i] : null; }
        function indexOfKind(kind) { const x = slots.find(o => o.kind === kind); return x ? x.at : -1; }
        readonly property int count: slots.length
        readonly property real dividerWide: 0.35     // a divider's width, in icons

        // ---- Badges and progress (Settings → Dock → Badges and progress) -------------
        // What apps publish for their icons (an unread count, how far a download or copy has
        // got, a call for attention: scripts/launcher-entries.py), and for apps that don't, how
        // many of their notifications are unread
        property var launcherEntries: ({})       // app id (lower case) → its latest state
        Process {
            running: Config.s.dockBadges
            command: [Quickshell.shellPath("scripts/launcher-entries.py")]
            stdout: SplitParser {
                onRead: line => {
                    try {
                        const e = JSON.parse(line);
                        const m = Object.assign({}, win.launcherEntries);
                        m[e.app.toLowerCase()] = e;
                        win.launcherEntries = m;
                    } catch (err) {}
                }
            }
        }
        // An app's badge: { count (0: none), progress (0…1, or -1: none), urgent }
        function badgeFor(app) {
            if (!Config.s.dockBadges || !app || !app.key) return { count: 0, progress: -1, urgent: false };
            const id = app.entry ? app.entry.id : app.key;
            const le = launcherEntries[id.toLowerCase()] || launcherEntries[app.key.toLowerCase()] || null;
            const published = le && le.countVisible && le.count > 0 ? le.count : 0;
            const unread = notifs.unreadByApp[id] || 0;
            return { count: published || unread, progress: le && le.progressVisible ? Math.max(0, Math.min(1, le.progress || 0)) : -1, urgent: !!(le && le.urgent) };
        }

        // ---- Downloads (Settings → Dock → Downloads) -------------------------------
        // A stack before the Waste Basket: click for a grid of the newest downloads (pictures
        // as thumbnails), right-click to open the folder. The folder is the desktop's own
        // (xdg-user-dir DOWNLOAD), else ~/Downloads
        readonly property bool downloadsShown: Config.s.dockShowDownloads && downloadsDir !== ""
        property string downloadsDir: ""
        Process {
            running: Config.s.dockShowDownloads && win.downloadsDir === ""
            command: ["sh", "-c", "d=$(xdg-user-dir DOWNLOAD 2>/dev/null); [ -n \"$d\" ] && [ \"$d\" != \"$HOME\" ] && echo \"$d\" || echo \"$HOME/Downloads\""]
            stdout: StdioCollector { onStreamFinished: win.downloadsDir = text.trim() }
        }
        FolderListModel {
            id: downloadsFiles
            folder: win.downloadsShown ? "file://" + win.downloadsDir : ""
            showDirs: true; showHidden: false; showDotAndDotDot: false
            sortField: FolderListModel.Time          // newest first
        }
        // The newest 24, without downloads still arriving (.part, .crdownload…). However big the
        // folder (it's read in the background), only these are ever looked at; the grid shows
        // three rows and scrolls for the rest, and Open Downloads is there for everything
        readonly property var recentDownloads: {
            const out = [];
            for (let i = 0; i < downloadsFiles.count && out.length < 24; i++) {
                const name = downloadsFiles.get(i, "fileName");
                if (/\.(part|crdownload|download|tmp)$/i.test(name)) continue;
                out.push({ name: name, path: downloadsFiles.get(i, "filePath"), dir: downloadsFiles.get(i, "fileIsDir") });
            }
            return out;
        }
        // How a download is shown: pictures as themselves, the rest as a glyph for their kind
        function downloadKind(d) {
            if (d.dir) return { glyph: 0xEAAD };
            const ext = (d.name.split(".").pop() || "").toLowerCase();
            if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "svg"].includes(ext)) return { image: true };
            if (ext === "pdf") return { glyph: 0xFB10 };
            if (["zip", "tar", "gz", "xz", "bz2", "zst", "7z", "rar", "deb", "rpm", "appimage", "iso"].includes(ext)) return { glyph: 0xED4E };
            if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"].includes(ext)) return { glyph: 0xEAFC };
            if (["mp4", "mkv", "webm", "mov", "avi", "m4v"].includes(ext)) return { glyph: 0xEAFA };
            if (["sh", "py", "js", "ts", "json", "lua", "c", "cpp", "h", "rs", "go", "qml", "html", "css"].includes(ext)) return { glyph: 0xEBD0 };
            if (["txt", "md", "log", "csv", "doc", "docx", "odt", "rtf"].includes(ext)) return { glyph: 0xEAA2 };
            return { glyph: 0xEAA4 };
        }
        function openDownloads() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. FILE_MANAGER .. " '${downloadsDir.replace(/'/g, "")}'") end`]);
        }

        // ---- Media (Settings → Dock → Media controls) ----------------------------------
        // What's playing, right after the launcher button, while a media app has a track: its
        // album art, with Previous / Play-Pause / Next across it under the pointer
        readonly property var player: Mpris.players.values.find(p => p.isPlaying)
            ?? Mpris.players.values.find(p => (p.trackTitle || "") !== "") ?? null
        readonly property bool mediaShown: Config.s.dockShowMedia && !!player && (player.trackTitle || "") !== ""
        readonly property int mediaIndex: indexOfKind("media")
        // How many icons wide it is: along a bottom or top dock, a rectangle with the album art
        // and the controls beside it; on a side dock, one icon (the controls show over the art
        // under the pointer), as a wide tile doesn't fit there
        readonly property bool mediaArt: Config.s.dockMediaArt     // Settings → Dock → Album art
        readonly property real mediaWide: vertical ? 1 : mediaArt ? 3.2 : 2.4
        // Where the track is (for the progress bar): players don't announce it as it moves, so
        // it's asked for each second while the bar can be seen
        Timer {
            interval: 1000; repeat: true
            running: win.mediaShown && win.shown && !!win.player && win.player.isPlaying && win.mediaWide > 1
            onTriggered: win.player.positionChanged()
        }
        // A click on it. Wide: the art goes to the app playing, then Previous / Play-Pause /
        // Next in thirds of the rest. One icon: Previous on its left third, Next on its right
        // Which part of it the pointer's on: "art" (wide), "previous", "toggle" or "next"
        function mediaControlAt() {
            const along = (pointerX - slotStart(mediaIndex)) / (mediaWide * base);    // 0 … 1 across it
            if (mediaWide > 1) {
                const art = mediaArt ? 1 / mediaWide : 0;        // the art: a square at the start
                if (along <= art) return "art";
                const third = (along - art) / (1 - art);
                return third < 1 / 3 ? "previous" : third > 2 / 3 ? "next" : "toggle";
            }
            return along < 1 / 3 ? "previous" : along > 2 / 3 ? "next" : "toggle";
        }
        // Go to the app that's playing: its window if one's open (by the app the player names),
        // else asking the player to show itself
        function showPlayer() {
            const p = player;
            if (!p) return;
            const id = (p.desktopEntry || "").toLowerCase(), name = (p.identity || "").toLowerCase();
            const app = items.find(it => it.windows.length > 0 && (
                (id !== "" && (it.key.toLowerCase() === id || (it.entry && it.entry.id.toLowerCase() === id)))
                || (name !== "" && it.entry && (it.entry.name || "").toLowerCase() === name)));
            if (app) app.windows[0].activate();
            else if (p.canRaise) p.raise();
        }
        function mediaClick() {
            const p = player;
            if (!p) return;
            const control = mediaControlAt();
            if (control === "art") { showPlayer(); return; }
            if (control === "previous") { if (p.canGoPrevious) p.previous(); }
            else if (control === "next") { if (p.canGoNext) p.next(); }
            else if (p.canTogglePlaying) p.togglePlaying();
        }

        // ---- Waste Basket (Settings → Dock → Waste Basket) ----------------------------
        // The bin after the apps: click to open it in the file manager, right-click to empty
        // it. The desktop's own (freedesktop) trash, so it's the same bin the file managers use
        readonly property bool trashShown: Config.s.dockShowTrash
        readonly property int trashIndex: indexOfKind("trash")         // always last
        readonly property int downloadsIndex: indexOfKind("downloads")
        readonly property string trashDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"
        // What's in it, watched (the folder made first if nothing's been thrown away yet, so
        // there's something to watch)
        property bool trashReady: false
        Process {
            running: win.trashShown && !win.trashReady
            command: ["mkdir", "-p", win.trashDir]
            onExited: win.trashReady = true
        }
        FolderListModel {
            id: trashFiles
            folder: win.trashShown && win.trashReady ? "file://" + win.trashDir : ""
            showDirs: true; showHidden: true; showDotAndDotDot: false
        }
        readonly property int trashCount: trashShown ? trashFiles.count : 0
        // Opened in the file manager the shortcuts use (FILE_MANAGER, Hyprland's variable)
        function openTrash() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. FILE_MANAGER .. " trash:///") end`]);
        }
        function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]); }
        // Slots along the dock: each an icon wide, except what's playing (mediaWide). Where one
        // starts at rest, and how wide it is in icons
        function slotWidth(i) {
            const k = slotAt(i) ? slotAt(i).kind : "";
            return k === "media" ? mediaWide : k === "divider" ? dividerWide : 1;
        }
        // Where each slot starts at rest (worked out once per change of the slots)
        readonly property var slotStarts: {
            const out = [];
            let x = 0;
            for (let i = 0; i < slots.length; i++) { out.push(x); x += slotWidth(i) * base + spacing; }
            out.push(x - spacing);                   // the end
            return out;
        }
        function slotStart(i) { return slotStarts[Math.max(0, Math.min(i, slotStarts.length - 1))]; }
        readonly property real restWidth: Math.max(0, slotStarts[slotStarts.length - 1])
        property real pointerX: -1000                          // in rest-layout coordinates
        // Magnification stays frozen while the right-click menu is open
        property real hover: (mouse.containsMouse && shown) || appMenu.visible || dragKey !== "" || fileDrag ? 1 : 0
        Behavior on hover { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }

        function scaleAt(i) {
            const w = slotWidth(i);
            const centre = slotStart(i) + w * base / 2;
            // (from its nearest edge, for a wide slot: it grows as soon as the pointer's on it)
            const t = Math.max(0, Math.abs(pointerX - centre) - (w - 1) * base / 2) / (base * spread);
            const f = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return 1 + (maxScale - 1) * f * hover;
        }
        function cellX(i) {
            let x = 0;
            for (let j = 0; j < i; j++) x += base * slotWidth(j) * scaleAt(j) + spacing;
            return x;
        }
        readonly property int hoveredIndex: {
            if (hover <= 0) return -1;
            for (let i = 0; i < count; i++)
                if (pointerX < slotStart(i) + slotWidth(i) * base + spacing / 2) return pointerX >= slotStart(i) - spacing / 2 ? i : -1;
            return -1;
        }

        // ---- Auto-hide -----------------------------------------------------
        // Something on the workspace the dock would cover: a tiled window. Floating ones don't
        // count (the dock stays open over a workspace of just floating windows), except in
        // floating windows mode, where every window floats. A window whose details Hyprland
        // hasn't given yet (one just opened) doesn't count until they come, a moment later:
        // counted as tiled, a new floating window briefly hid the dock
        readonly property bool workspaceBusy: {
            const tops = Hyprland.focusedWorkspace?.toplevels?.values ?? [];
            if (Config.floatingWindows) return tops.length > 0;
            return tops.some(t => t.lastIpcObject && t.lastIpcObject.floating === false);
        }
        // Which windows float comes from Hyprland's window details: fetched again when a window
        // opens, moves or changes floating (only while that matters to the dock)
        Connections {
            target: Hyprland
            enabled: Config.s.dockAutoHide && !Config.floatingWindows
            function onRawEvent(event) {
                switch (event.name) {
                case "openwindow": case "changefloatingmode": case "movewindow": case "movewindowv2":
                    floatCheck.restart();
                }
            }
        }
        // (and once at start, so the windows already open have their details)
        Timer { id: floatCheck; interval: 30; running: true; onTriggered: Hyprland.refreshToplevels() }
        property bool shown: !Config.s.dockAutoHide || (!workspaceBusy && !appLauncher.launchingNew) || mouse.containsMouse || holdTimer.running || appMenu.visible || previewPop.visible || dragKey !== "" || fileDrag
        Timer { id: holdTimer; interval: win.hideDelay }
        readonly property real dockHeight: base + padding * 2
        property real offset: shown ? 0 : dockHeight + bottomGap + 4
        Behavior on offset { NumberAnimation { duration: Config.ms(260); easing.type: Easing.OutCubic } }

        // Open an app's menu by its key, e.g.  slate ipc call dock menu firefox
        IpcHandler {
            target: "dock"
            function menu(key: string): void {
                const sl = win.slots.find(o => o.kind === "app" && o.item.key === key);
                if (!sl) return;
                const x = (strip.width - win.restWidth) / 2 + win.slotStart(sl.at) + win.base / 2;
                appMenu.openFor(sl.item, x);
            }
            function closeMenu(): void { appMenu.closeMenu(); }
            // An app's window previews, as pausing on it does:  slate ipc call dock preview firefox
            function preview(key: string): void {
                const sl = win.slots.find(o => o.kind === "app" && o.item.key === key);
                if (!sl || sl.item.windows.length === 0 || win.previewMode === "off") return;
                win.previewApp = sl.item;
                const x = (strip.width - win.restWidth) / 2 + win.slotStart(sl.at) + win.base / 2;
                const p = strip.mapToItem(win.contentItem, x, bg.y - 16);
                const sw = win.screen ? win.screen.width : 0, sh = win.screen ? win.screen.height : 0;
                previewPop.atX = p.x + (win.edge === "right" ? sw - win.width : 0);
                previewPop.atY = p.y + (win.edge === "bottom" ? sh - win.height : 0);
            }
            function closePreview(): void { win.previewApp = null; }
            // The Downloads stack's grid, as clicking it does:  slate ipc call dock downloads
            function downloads(): void {
                if (!win.downloadsShown) return;
                const i = win.downloadsIndex;
                appMenu.openFor({ downloadsGrid: true, key: "", windows: [] }, (strip.width - win.restWidth) / 2 + win.slotStart(i) + win.base / 2);
            }
        }

        // ---- Right-click menu ----------------------------------------------
        // A full-screen invisible layer while open: clicking anywhere outside the menu
        // (or pressing Escape) closes it
        // ---- Dragging --------------------------------------------------------------
        // A pinned app dragged along the dock moves among the pinned ones (saved when it's let
        // go); dragged up off the dock, it's let go of to unpin it. Files dragged in from a
        // file manager: onto the Waste Basket to bin them, onto an app to open them in it
        property string dragCandidate: ""        // the pinned app pressed on (dragging once it moves)
        property string dragKey: ""              // the pinned app being dragged
        property bool dragAway: false            // pulled off the dock: letting go unpins it
        property bool fileDrag: false            // files being dragged over the dock
        function dragTo(stripPoint) {
            dragAway = stripPoint.y < bg.y - base;
            if (dragAway) return;
            const sl = slotAt(hoveredIndex);
            if (!sl || sl.kind !== "app" || !sl.item.pinned || sl.item.key === dragKey) return;
            // Into the place of the pinned app under the pointer
            const list = pinned.filter(k => k !== dragKey);
            const at = list.indexOf(sl.item.key);
            const from = pinned.indexOf(dragKey), to = pinned.indexOf(sl.item.key);
            list.splice(to > from ? at + 1 : at, 0, dragKey);
            pinned = list;
        }
        function endDrag() {
            if (dragKey !== "") {
                if (dragAway) setPinned(dragKey, false);
                else savePinned();
            }
            dragKey = ""; dragCandidate = ""; dragAway = false;
        }
        // Files let go of over slot i
        function dropFiles(i, urls) {
            const sl = slotAt(i);
            const paths = urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
            if (!sl || paths.length === 0) return false;
            if (sl.kind === "trash") { Quickshell.execDetached(["gio", "trash"].concat(paths)); return true; }
            if (sl.kind === "app" && sl.item.entry) {
                Quickshell.execDetached([Quickshell.shellPath("scripts/open-with.sh"), sl.item.entry.id].concat(paths));
                return true;
            }
            return false;
        }

        // ---- Window previews (Settings → Dock → Window previews) -----------------------
        // Pause on an app with windows open (for Settings' number of seconds; 0: never) and a
        // panel shows a card for each: a live picture of it, or in game mode (no live pictures)
        // its title and the app's icon; click one to go to it. It stays while the pointer moves
        // onto it
        readonly property string previewMode: Config.s.dockPreviewDelay <= 0 ? "off" : Config.gameMode ? "titles" : "live"
        property var previewApp: null            // the app being previewed ({ key, entry, windows })
        property bool previewHeld: false         // the pointer's on the panel
        Timer { id: previewDwell; interval: Math.max(100, Config.s.dockPreviewDelay * 1000); onTriggered: win.showPreview() }
        Timer { id: previewLeave; interval: 300; onTriggered: if (!win.previewHeld && !win.pointedApp) win.previewApp = null }
        // The app under the pointer, while it has windows (null otherwise)
        readonly property var pointedApp: {
            const sl = hover > 0.5 && !appMenu.visible ? slotAt(hoveredIndex) : null;
            return sl && sl.kind === "app" && sl.item.windows.length > 0 ? sl.item : null;
        }
        onPointedAppChanged: {
            if (previewMode === "off") return;
            if (pointedApp && previewApp) showPreview();       // already showing: switch at once
            else if (pointedApp) previewDwell.restart();
            else { previewDwell.stop(); previewLeave.restart(); }
        }
        function showPreview() {
            const sl = slots.find(o => o.kind === "app" && pointedApp && o.item.key === pointedApp.key);
            if (!sl) return;
            previewApp = sl.item;
            const p = strip.mapToItem(win.contentItem, row.x + cellX(sl.at) + base * scaleAt(sl.at) / 2, bg.y - 16);
            const sw = win.screen ? win.screen.width : 0, sh = win.screen ? win.screen.height : 0;
            previewPop.atX = p.x + (win.edge === "right" ? sw - win.width : 0);
            previewPop.atY = p.y + (win.edge === "bottom" ? sh - win.height : 0);
        }
        Connections { target: appMenu; function onVisibleChanged() { if (appMenu.visible) win.previewApp = null; } }

        PanelWindow {
            id: previewPop
            screen: win.screen
            property real atX: 0          // by the icon, just off the dock (screen coordinates)
            property real atY: 0
            readonly property var wins: win.previewApp ? win.previewApp.windows : []
            visible: !!win.previewApp && wins.length > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "slate-dock-previews"
            WlrLayershell.layer: WlrLayer.Overlay
            mask: Region { item: previewBox }           // only the panel takes the pointer

            // A card's size: live pictures are wider than title-only cards
            readonly property real cardW: win.previewMode === "live" ? 220 : 200
            readonly property real cardH: win.previewMode === "live" ? 160 : 48

            Rectangle {
                id: previewBox
                readonly property real wanted: previewPop.wins.length * (previewPop.cardW + 8) + 8
                width: Math.min(wanted, previewPop.width - 32)
                height: win.previewMode === "live" ? previewPop.cardH + 16 : Math.min(previewPop.wins.length * (previewPop.cardH + 4) + 12, previewPop.height - 32)
                x: Math.max(8, Math.min(previewPop.width - width - 8,
                    win.edge === "left" ? previewPop.atX : win.edge === "right" ? previewPop.atX - width : previewPop.atX - width / 2))
                y: Math.max(8, Math.min(previewPop.height - height - 8,
                    win.edge === "bottom" ? previewPop.atY - height : win.edge === "top" ? previewPop.atY : previewPop.atY - height / 2))
                radius: 12
                color: win.bgColor
                Gloss { radius: parent.radius }   // glass: a sheen
                HoverHandler {
                    onHoveredChanged: { win.previewHeld = hovered; if (!hovered) previewLeave.restart(); }
                }

                // Live: the windows side by side (scrolling sideways when there are many)
                Flickable {
                    id: previewScroll
                    visible: win.previewMode === "live"
                    anchors { fill: parent; margins: 8 }
                    contentWidth: previewRow.width
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Row {
                        id: previewRow
                        spacing: 8
                        Repeater {
                            model: win.previewMode === "live" ? previewPop.wins : []
                            delegate: Rectangle {
                                id: liveCard
                                required property var modelData
                                width: previewPop.cardW; height: previewPop.cardH
                                radius: 8
                                color: liveHover.hovered ? Config.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                Gloss { radius: parent.radius; opacity: liveHover.hovered ? 1 : 0 }
                                ScreencopyView {
                                    id: liveShot
                                    readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
                                    width: Math.min(parent.width - 12, (parent.height - 34) * ratio)
                                    height: width / ratio
                                    captureSource: previewPop.visible ? liveCard.modelData : null
                                    live: previewPop.visible
                                    // Rounded, and brightened back if Hyprland dims it (it isn't focused)
                                    layer.enabled: true
                                    layer.effect: PreviewShape { radius: 6; gain: Config.undimGain(liveCard.modelData.activated, liveCard.modelData.appId) }
                                }
                                Text {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                                    horizontalAlignment: Text.AlignHCenter
                                    text: liveCard.modelData.title || ""
                                    elide: Text.ElideRight
                                    color: liveCard.modelData.activated ? win.activeDotColor : win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                HoverHandler { id: liveHover }
                                ClickTap { onTapped: { liveCard.modelData.activate(); win.previewApp = null; } }
                            }
                        }
                    }
                }

                // Titles: the windows one above another, each with the app's icon
                Flickable {
                    id: titleScroll
                    visible: win.previewMode === "titles"
                    anchors { fill: parent; margins: 6 }
                    contentHeight: titleCol.height
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    SmoothWheel { flick: titleScroll }
                    Column {
                        id: titleCol
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: win.previewMode === "titles" ? previewPop.wins : []
                            delegate: Rectangle {
                                id: titleCard
                                required property var modelData
                                width: titleCol.width; height: previewPop.cardH
                                radius: 8
                                color: titleHover.hovered ? Config.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                Gloss { radius: parent.radius; opacity: titleHover.hovered ? 1 : 0 }
                                AppTile {
                                    id: titleIcon
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: 28; height: 28
                                    app: win.previewApp ? (win.previewApp.entry ? win.previewApp.entry.id : win.previewApp.key) : ""
                                }
                                Text {
                                    anchors { left: titleIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: titleCard.modelData.title || ""
                                    elide: Text.ElideRight
                                    color: titleCard.modelData.activated ? win.activeDotColor : win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                                }
                                HoverHandler { id: titleHover }
                                ClickTap { onTapped: { titleCard.modelData.activate(); win.previewApp = null; } }
                            }
                        }
                    }
                }
            }
        }

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
                if (app.mediaMenu) {
                    const p = win.player;
                    if (!p) return r;
                    r.push({ label: p.isPlaying ? "Pause" : "Play", kind: "media-toggle" });
                    if (p.canGoNext) r.push({ label: "Next", kind: "media-next" });
                    if (p.canGoPrevious) r.push({ label: "Previous", kind: "media-previous" });
                    {
                        r.push({ kind: "sep" });
                        r.push({ label: "Show " + (p.identity || "the player"), kind: "media-raise" });
                    }
                    return r;
                }
                if (app.downloadsGrid || app.downloadsMenu) {
                    r.push({ label: "Open Downloads", kind: "downloads-open" });
                    return r;
                }
                if (app.trashMenu) {
                    r.push({ label: "Open", kind: "trash-open" });
                    if (win.trashCount > 0) {
                        r.push({ kind: "sep" });
                        r.push({ label: "Empty Waste Basket…", kind: "trash-empty", danger: true });
                    }
                    return r;
                }
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
                // Kills the app outright, for one that's stopped responding to Close
                if (wins.length > 0) r.push({ label: "Force Quit", kind: "kill", danger: true });
                return r;
            }
            // Hyprland's window addresses for these windows; scripts/force-quit.sh kills their processes
            function forceQuit(list) {
                const addrs = Hyprland.toplevels.values.filter(t => t.wayland && list.includes(t.wayland)).map(t => t.address.startsWith("0x") ? t.address : "0x" + t.address);
                if (addrs.length > 0) Quickshell.execDetached([Quickshell.shellPath("scripts/force-quit.sh")].concat(addrs));
            }
            function run(row) {
                switch (row.kind) {
                case "window": row.target.activate(); break;
                case "action": row.target.execute(); break;
                case "new": entry.execute(); break;
                case "pin": win.setPinned(app.key, !isPinned); break;
                case "quit": for (const w of wins) w.close(); break;
                case "kill": forceQuit(wins); break;
                case "settings": if (settingsLoader.item) settingsLoader.item.goTo(row.target, row.find || ""); break;
                case "trash-open": win.openTrash(); break;
                case "downloads-open": win.openDownloads(); break;
                case "media-toggle": if (win.player) win.player.togglePlaying(); break;
                case "media-next": if (win.player) win.player.next(); break;
                case "media-previous": if (win.player) win.player.previous(); break;
                case "media-raise": win.showPlayer(); break;
                case "trash-empty": {
                    // Asks first, in the same confirmation window as shutting down and the rest
                    const n = win.trashCount;
                    powerConfirm.confirmWith({
                        title: "Empty the waste basket?",
                        body: (n === 1 ? "The item in it is" : "The " + n + " items in it are") + " deleted for good. This can't be undone.",
                        button: "Empty", code: 0xEB41, danger: true
                    }, () => win.emptyTrash());
                    break;
                }
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
                // Wider for Downloads' grid (four across)
                width: appMenu.app && appMenu.app.downloadsGrid ? 4 * 88 + 16 : 240
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

                    // Downloads: the newest, four across; click one to open it
                    Text {
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid && win.recentDownloads.length === 0
                        width: menuCol.width; height: 40
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: "Nothing downloaded yet"
                        color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                        font.family: Config.s.fontFamily; font.pixelSize: 13
                    }
                    Flickable {
                        id: dlScroll
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid && win.recentDownloads.length > 0
                        width: menuCol.width
                        height: Math.min(dlGrid.height, 3 * 92)        // three rows; the rest scroll
                        contentHeight: dlGrid.height
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        SmoothWheel { flick: dlScroll }
                        Grid {
                        id: dlGrid
                        columns: 4
                        Repeater {
                            model: appMenu.app && appMenu.app.downloadsGrid ? win.recentDownloads : []
                            delegate: Item {
                                id: dl
                                required property var modelData
                                readonly property var kind: win.downloadKind(modelData)
                                width: 88; height: 92
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: dlHover.hovered ? Config.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                    Gloss { radius: parent.radius; opacity: dlHover.hovered ? 1 : 0 }
                                }
                                // The file: a picture as itself, anything else as its kind on a tile
                                Item {
                                    id: dlIcon
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8; width: 52; height: 52
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: !dl.kind.image || dlThumb.status !== Image.Ready
                                        radius: 10
                                        color: win.tileColor
                                        Gloss { radius: parent.radius; glassHint: true }
                                        Text {
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(dl.kind.glyph || 0xEB0A)
                                            color: win.textColor
                                            font.family: "slate-tabler-icons"; font.pixelSize: 24
                                        }
                                    }
                                    Image {
                                        id: dlThumb
                                        anchors.fill: parent
                                        visible: !!dl.kind.image && status === Image.Ready
                                        source: dl.kind.image ? "file://" + dl.modelData.path : ""
                                        sourceSize: Qt.size(128, 128)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        layer.enabled: visible
                                        layer.effect: MultiEffect { maskEnabled: true; maskSource: dlThumbMask }
                                    }
                                    Item {
                                        id: dlThumbMask
                                        anchors.fill: parent
                                        visible: false
                                        layer.enabled: true
                                        Rectangle { anchors.fill: parent; radius: 8 }
                                    }
                                }
                                Text {
                                    anchors { top: dlIcon.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
                                    horizontalAlignment: Text.AlignHCenter
                                    text: dl.modelData.name
                                    elide: Text.ElideMiddle
                                    color: win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 11
                                }
                                HoverHandler { id: dlHover }
                                ClickTap {
                                    onTapped: { Qt.openUrlExternally("file://" + dl.modelData.path); appMenu.closeMenu(); }
                                }
                            }
                        }
                        }
                    }
                    Rectangle {
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid
                        width: menuCol.width; height: 9; color: "transparent"
                        Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: win.tileColor }
                    }

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
                                Behavior on color { ColorAnimation { duration: Config.ms(90) } }
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
            property point pressedAt
            property bool dragged: false        // moved far enough to be a drag, not a click
            onPressed: m => {
                pressedAt = Qt.point(m.x, m.y);
                dragged = false;
                const sl = win.slotAt(win.hoveredIndex);
                win.dragCandidate = m.button === Qt.LeftButton && sl && sl.kind === "app" && sl.item.pinned ? sl.item.key : "";
            }
            onPositionChanged: m => {
                win.pointerX = stripX(m) - (strip.width - win.restWidth) / 2;
                if (!pressed || win.dragCandidate === "") return;
                if (!dragged && Math.hypot(m.x - pressedAt.x, m.y - pressedAt.y) > 8) {
                    dragged = true;
                    win.dragKey = win.dragCandidate;
                    win.previewApp = null;
                }
                if (dragged) win.dragTo(strip.mapFromItem(mouse, m.x, m.y));
            }
            onReleased: win.endDrag()
            onExited: holdTimer.restart()
            onClicked: m => {
                if (dragged) return;            // a drag, not a click
                win.pointerX = stripX(m) - (strip.width - win.restWidth) / 2;
                win.clickItem(win.hoveredIndex, m.button === Qt.RightButton);
            }
        }
        // Files dragged over the dock (from a file manager): it shows and magnifies as for the
        // pointer, and they're dropped on the slot under them (see win.dropFiles)
        DropArea {
            z: 11
            anchors.fill: maskBox
            onEntered: d => {
                win.fileDrag = d.hasUrls;
                if (!d.hasUrls) d.accepted = false;
            }
            onPositionChanged: d => win.pointerX = strip.mapFromItem(this, d.x, d.y).x - (strip.width - win.restWidth) / 2
            onExited: { win.fileDrag = false; holdTimer.restart(); }
            onDropped: d => {
                win.pointerX = strip.mapFromItem(this, d.x, d.y).x - (strip.width - win.restWidth) / 2;
                if (d.hasUrls && win.dropFiles(win.hoveredIndex, d.urls)) d.acceptProposedAction();
                win.fileDrag = false;
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
            if (!b || !Config.animate) return 0;       // Animations off (or game mode): no hop
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
            if (mediaShown && i === mediaIndex) {
                // What's playing: the control under the pointer; right-click for them all
                if (right) appMenu.openFor({ mediaMenu: true, key: "", windows: [] }, row.x + cellX(i) + base * slotWidth(i) * scaleAt(i) / 2);
                else mediaClick();
                return;
            }
            if (downloadsShown && i === downloadsIndex) {
                // Downloads: the grid of the newest; right-click just to open the folder
                appMenu.openFor(right ? { downloadsMenu: true, key: "", windows: [] } : { downloadsGrid: true, key: "", windows: [] },
                    row.x + cellX(i) + base * scaleAt(i) / 2);
                return;
            }
            if (trashShown && i === trashIndex) {
                // The waste basket: opens it; right-click to empty it
                if (right) appMenu.openFor({ trashMenu: true, key: "", windows: [] }, row.x + cellX(i) + base * scaleAt(i) / 2);
                else openTrash();
                return;
            }
            const sl = slotAt(i);
            if (!sl || sl.kind !== "app") return;          // (a divider does nothing)
            const item = sl.item;
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
                                drawSize: win.base * win.maxScale      // drawn once, magnified size
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

                    // What's playing (see win.mediaShown): the album art cut to the icons' shape (or the
                    // theme's tile with a note when there's none), a sheen with glass, and under the
                    // pointer Previous / Play-Pause / Next across it on a dark wash
                    Item {
                        id: mediaCell
                        visible: win.mediaShown
                        readonly property real s: win.scaleAt(win.mediaIndex)
                        readonly property bool pointed: win.hoveredIndex === win.mediaIndex && win.hover > 0.5 && !appMenu.visible
                        readonly property string under: pointed ? win.mediaControlAt() : ""
                        width: win.base * win.mediaWide * s
                        height: row.height

                        // Along a bottom or top dock: a rectangle, the album art at its start and the
                        // controls beside it (the one under the pointer brighter)
                        Item {
                            id: mediaWideTile
                            visible: win.mediaWide > 1
                            anchors.bottom: parent.bottom
                            width: parent.width; height: win.base * mediaCell.s
                            readonly property real corner: Config.s.iconShape === "circle" ? height / 2
                                : height * win.iconCorner / Math.max(1, win.base)
                            readonly property bool hasArt: wideArt.status === Image.Ready
                            // The art sits inside the tile, this far in from its edges. Album covers are
                            // square, so it's rounded a little (as music apps show them), whatever the
                            // icon shape: following the tile's own curve cut too far into the artwork
                            readonly property real inset: Math.round(height * 0.12)
                            readonly property real artCorner: Math.max(3, Math.round((height - inset * 2) * 0.16))
                            Rectangle {
                                anchors.fill: parent
                                radius: mediaWideTile.corner
                                color: win.tileColor
                                Gloss { radius: parent.radius; glassHint: true }   // glass: a sheen
                            }
                            // The art, cut to the tile's corners; a note on a faint square without it
                            Item {
                                id: wideArtBox
                                visible: win.mediaArt
                                x: mediaWideTile.inset; y: mediaWideTile.inset
                                width: win.mediaArt ? height : 0; height: parent.height - mediaWideTile.inset * 2
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: wideArtMask }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: !mediaWideTile.hasArt
                                    color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.06)
                                    Text {
                                        anchors.centerIn: parent
                                        text: String.fromCodePoint(0xEAFC)      // music
                                        color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                                        font.family: "slate-tabler-icons"
                                        font.pixelSize: Math.round(parent.height * 0.5)
                                    }
                                }
                                Image {
                                    id: wideArt
                                    anchors.fill: parent
                                    source: win.player ? (win.player.trackArtUrl || "") : ""
                                    sourceSize: Qt.size(192, 192)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true; mipmap: true
                                }
                            }
                            Item {
                                id: wideArtMask
                                anchors.fill: wideArtBox
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: mediaWideTile.artCorner }
                            }
                            // A faint edge round the art, so a dark cover still stands off the tile
                            Rectangle {
                                anchors.fill: wideArtBox
                                visible: win.mediaArt && mediaWideTile.hasArt
                                radius: mediaWideTile.artCorner
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.12)
                            }
                            // Previous, Play/Pause, Next: evenly across the rest of the tile (a little above
                            // the middle, to leave room for the progress bar beneath)
                            Row {
                                id: mediaControls
                                anchors { left: wideArtBox.right; right: parent.right; rightMargin: mediaWideTile.inset; leftMargin: win.mediaArt ? 0 : mediaWideTile.inset }
                                y: (parent.height - height) / 2 - parent.height * 0.08
                                Repeater {
                                    model: [
                                        { id: "previous", code: 0xF693, size: 0.34, on: !!win.player && win.player.canGoPrevious },
                                        { id: "toggle", code: win.player && win.player.isPlaying ? 0xF690 : 0xF691, size: 0.42, on: !!win.player && win.player.canTogglePlaying },
                                        { id: "next", code: 0xF694, size: 0.34, on: !!win.player && win.player.canGoNext }
                                    ]
                                    delegate: Item {
                                        id: mediaButton
                                        required property var modelData
                                        width: parent.width / 3; height: mediaWideTile.height * 0.62
                                        // A soft circle behind the one under the pointer
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.height; height: width; radius: width / 2
                                            readonly property bool lit: mediaCell.under === mediaButton.modelData.id && mediaButton.modelData.on
                                            color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, lit ? 0.14 : 0)
                                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                            // Glass: a sheen on it while it shows (fading with it)
                                            Gloss { radius: parent.radius; opacity: parent.lit ? 1 : 0 }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(parent.modelData.code)
                                            color: win.textColor
                                            opacity: !parent.modelData.on ? 0.3 : mediaCell.under === parent.modelData.id ? 1 : 0.75
                                            Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                                            font.family: "slate-tabler-icons"
                                            font.pixelSize: Math.round(mediaWideTile.height * parent.modelData.size)
                                        }
                                    }
                                }
                            }
                            // How far through the track: a slim bar under the controls (only for
                            // players that say how long the track is)
                            Rectangle {
                                readonly property bool known: !!win.player && win.player.lengthSupported && win.player.length > 0
                                visible: known
                                x: mediaControls.x + parent.height * 0.12
                                width: mediaControls.width - parent.height * 0.24
                                y: parent.height - mediaWideTile.inset - height - parent.height * 0.04
                                height: Math.max(2, Math.round(parent.height * 0.05)); radius: height / 2
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.15)
                                Rectangle {
                                    width: parent.known ? parent.width * Math.max(0, Math.min(1, win.player.position / win.player.length)) : 0
                                    height: parent.height; radius: parent.radius
                                    color: win.activeDotColor
                                }
                            }
                        }

                        // On a side dock: one icon, the controls over the art under the pointer
                        Item {
                            id: mediaTile
                            visible: win.mediaWide === 1
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(mediaTile.width, mediaTile.height) }
                            readonly property real corner: Config.s.iconShape === "circle" ? width / 2
                                : width * win.iconCorner / Math.max(1, win.base)
                            readonly property bool hasArt: win.mediaArt && mediaArt.status === Image.Ready
                            // No art: the tile the launcher button has, with a note on it
                            IconPlate {
                                anchors.fill: parent
                                visible: !mediaTile.hasArt
                                drawSize: win.base * win.maxScale
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                            }
                            Text {
                                visible: !mediaTile.hasArt && !mediaCell.pointed
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xEAFC)          // music
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(parent.width * 0.5)
                            }
                            // The art, cut to the icons' shape
                            Item {
                                anchors.fill: parent
                                visible: mediaTile.hasArt
                                layer.enabled: visible
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: mediaMask }
                                Image {
                                    id: mediaArt
                                    anchors.fill: parent
                                    source: win.player ? (win.player.trackArtUrl || "") : ""
                                    sourceSize: Qt.size(192, 192)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true; mipmap: true
                                }
                            }
                            Item {
                                id: mediaMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: mediaTile.corner }
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: mediaTile.corner; glassHint: true }
                            // Under the pointer: the controls on a dark wash (over art or tile alike,
                            // so they read the same in light and dark)
                            Rectangle {
                                anchors.fill: parent
                                radius: mediaTile.corner
                                color: "black"
                                opacity: mediaCell.pointed ? 0.5 : 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: mediaTile.width * 0.04
                                opacity: mediaCell.pointed ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                                Repeater {
                                    model: [
                                        { code: 0xF693, size: 0.22, on: !!win.player && win.player.canGoPrevious },
                                        { code: win.player && win.player.isPlaying ? 0xF690 : 0xF691, size: 0.3, on: !!win.player && win.player.canTogglePlaying },
                                        { code: 0xF694, size: 0.22, on: !!win.player && win.player.canGoNext }
                                    ]
                                    delegate: Text {
                                        required property var modelData
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(modelData.code)
                                        color: "white"
                                        opacity: modelData.on ? 1 : 0.35
                                        font.family: "slate-tabler-icons"
                                        font.pixelSize: Math.round(mediaTile.width * modelData.size)
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: win.middleSlots
                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property bool isApp: modelData.kind === "app"
                            // The app in this slot ({ key, entry, windows, pinned }; none for a divider)
                            readonly property var app: isApp ? modelData.item : ({ key: "", entry: null, windows: [], pinned: false })
                            readonly property real s: win.scaleAt(modelData.at)
                            readonly property var badge: win.badgeFor(isApp ? app : null)
                            readonly property string tilePath: isApp ? Config.tilePath(app.key) : ""
                            property int version: 0
                            property string tried: ""       // the icon file last drawn for (once per file, so a broken icon isn't retried forever)
                            // Bounces while the app is starting (clicked in the dock): see win.bounceOf
                            readonly property real bounce: win.bounceOf(cell.app.key)
                            readonly property int windowCount: cell.app.windows.length
                            onWindowCountChanged: if (windowCount > 0) win.endLaunch(cell.app.key)
                            Component.onCompleted: if (windowCount > 0) win.endLaunch(cell.app.key)
                            width: win.base * win.slotWidth(modelData.at) * s
                            height: row.height

                            // A divider: a faint line across the dock, between the pinned apps and
                            // the others (and before Downloads and the Waste Basket)
                            Rectangle {
                                visible: !cell.isApp
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: win.base * 0.12
                                width: 1; height: win.base * 0.76
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.2)
                            }

                            Image {
                                visible: cell.isApp
                                // Being dragged off the dock to unpin it: faded, as it's about to go
                                opacity: win.dragAway && cell.app.key === win.dragKey ? 0.35 : 1
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                                anchors.bottom: parent.bottom
                                id: tileImg
                                width: parent.width; height: width
                                // Upright for the dock's edge, then the launch bounce (away from the edge)
                                transform: [
                                    Matrix4x4 { matrix: win.upright(tileImg.width, tileImg.height) },
                                    Translate { y: -cell.bounce * win.base * 0.4 }
                                ]
                                source: cell.isApp ? "file://" + cell.tilePath + "?v=" + cell.version + "." + Config.tileVersion : ""
                                sourceSize: Qt.size(192, 192)
                                smooth: true
                                mipmap: true
                                cache: false
                                layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                                onStatusChanged: if (cell.isApp && status === Image.Error && !gen.running && cell.tried !== cell.tilePath) { cell.tried = cell.tilePath; gen.running = true; }
                                // The tile behind, in the theme's colour: drawn once at its magnified size
                                // and shrunk, not redrawn on every frame as the dock magnifies
                                IconPlate { anchors.fill: parent; z: -1; drawSize: win.base * win.maxScale }
                                // Glass: a sheen, rounded like the icon tiles (not on icons shown as
                                // they come, which have no tile to follow)
                                Gloss {
                                    glassHint: true
                                    visible: Config.glassGloss && Config.s.iconShape !== "original"
                                    radius: parent.width * win.iconCorner / Math.max(1, win.base)
                                }
                                // How far a download or copy has got: a slim bar near the icon's foot
                                Rectangle {
                                    visible: cell.badge.progress >= 0
                                    z: 2
                                    x: parent.width * 0.15; width: parent.width * 0.7
                                    y: parent.height * 0.8; height: Math.max(3, parent.height * 0.08); radius: height / 2
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * cell.badge.progress)
                                        height: parent.height; radius: parent.radius
                                        color: win.activeDotColor
                                    }
                                }
                                // An unread count (or "!" when the app asks for attention): a pill on the
                                // icon's top corner, in the accent, with glass's sheen
                                Rectangle {
                                    readonly property string text: cell.badge.count > 99 ? "99+" : cell.badge.count > 0 ? String(cell.badge.count)
                                        : cell.badge.urgent ? "!" : ""
                                    visible: text !== ""
                                    z: 2
                                    height: Math.round(parent.height * 0.38)
                                    width: Math.max(height, badgeText.implicitWidth + height * 0.5)
                                    radius: height / 2
                                    x: parent.width - width * 0.75; y: -height * 0.25
                                    color: win.activeDotColor
                                    Gloss { radius: parent.radius }
                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: parent.text
                                        color: Config.tint("#12151a")
                                        font.family: Config.s.fontFamily; font.weight: Font.DemiBold
                                        font.pixelSize: Math.round(parent.height * 0.62)
                                    }
                                }
                            }

                            // Draw the tile the first time this app shows up
                            Process {
                                id: gen
                                command: Config.tileCommand(cell.app.entry ? cell.app.entry.id : cell.app.key, cell.tilePath)
                                onExited: cell.version++
                            }

                            // Running indicator: a short rounded bar (accent for the focused app)
                            Rectangle {
                                readonly property bool focusedApp: cell.app.windows.some(w => w.activated)
                                visible: cell.app.windows.length > 0
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
                    // Downloads: a stack, the folder-and-arrow on a tile like the launcher button's
                    Item {
                        visible: win.downloadsShown
                        readonly property real s: win.scaleAt(win.downloadsIndex)
                        width: win.base * s
                        height: row.height
                        Item {
                            id: downloadsTile
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(downloadsTile.width, downloadsTile.height) }
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                            }
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true }
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF912)       // folder-down
                                color: win.textColor
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(parent.width * 0.5)
                            }
                        }
                    }

                    // The waste basket: the bin on a tile like the launcher button's (and Downloads'),
                    // outlined while empty and filled once something's in it
                    Item {
                        visible: win.trashShown
                        readonly property real s: win.scaleAt(win.trashIndex)
                        width: win.base * s
                        height: row.height
                        Item {
                            id: trashTile
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(trashTile.width, trashTile.height) }
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale      // drawn once, magnified size
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true }
                            // The bin, as Downloads' folder is drawn: outlined while it's empty, filled
                            // once there's something in it
                            Text {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(win.trashCount > 0 ? 0xF783 : 0xEB41)     // trash-filled / trash
                                color: win.textColor
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(parent.width * 0.5)
                            }
                        }
                    }
                }

                // App name above the icon under the pointer
                Rectangle {
                    id: label
                    readonly property string text: win.dragAway ? "Remove from Dock"
                        : win.hoveredIndex === 0 ? "Apps"
                        : win.downloadsShown && win.hoveredIndex === win.downloadsIndex ? "Downloads"
                        : win.trashShown && win.hoveredIndex === win.trashIndex
                            ? (win.trashCount > 0 ? "Waste Basket · " + win.trashCount + (win.trashCount === 1 ? " item" : " items") : "Waste Basket")
                        : win.mediaShown && win.hoveredIndex === win.mediaIndex
                            ? win.player.trackTitle + (win.player.trackArtist ? " · " + win.player.trackArtist : "")
                        : (win.slotAt(win.hoveredIndex) && win.slotAt(win.hoveredIndex).kind === "app"
                            ? (win.slotAt(win.hoveredIndex).item.entry?.name ?? win.slotAt(win.hoveredIndex).item.key) : "")
                    readonly property real iconSize: win.hoveredIndex >= 0 ? win.base * win.scaleAt(win.hoveredIndex) : 0
                    readonly property real slotLength: win.hoveredIndex >= 0 ? iconSize * win.slotWidth(win.hoveredIndex) : 0
                    visible: win.hoveredIndex >= 0 && win.hover > 0.9 && text !== "" && !appMenu.visible
                    width: labelText.implicitWidth + 16
                    height: labelText.implicitHeight + 8
                    radius: 6
                    color: win.bgColor
                    Gloss { radius: parent.radius }   // glass: a sheen
                    x: row.x + win.cellX(Math.max(0, win.hoveredIndex)) + slotLength / 2 - width / 2
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
