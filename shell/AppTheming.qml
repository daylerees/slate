// Other apps follow Slate's theme: GTK apps picking up new colours, the folder colour, the icon
// theme and Settings → App Theming, with the notices about themes an app update undid.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var hold: null                  // UpdateHold.qml

    // GTK apps waiting to pick up new colours (scripts/refresh-gtk-apps.sh's flag file, there while
    // any are): a window closing starts the script only then, looked for without a process (the
    // script used to start on every close)
    FileView {
        id: gtkFlag
        path: Config.cacheHome + "/slate/gtk4-refresh"
        printErrors: false
        property bool closed: false              // (a window closed: look whether the flag's there)
        onLoaded: if (closed) { closed = false; gtkRefresh.restart(); }
        onLoadFailed: closed = false
    }
    property int gtkRefreshes: 0                 // (the tests: how many times the script was started)
    Connections {
        target: Config
        // A window closed: GTK apps waiting to pick up new colours may now restart
        function onWindowClosed() {
            gtkFlag.closed = true;
            gtkFlag.reload();
        }
    }
    Timer { id: gtkRefresh; interval: 1500; onTriggered: { root.gtkRefreshes++; Quickshell.execDetached([Quickshell.shellPath("scripts/refresh-gtk-apps.sh")]); } }

    // File managers' folder colour (Settings → Appearance): Papirus's folder icons in a chosen
    // colour, or the one nearest the wallpaper's (scripts/folder-colour.py)
    readonly property var folderArgs: Config.s.folderColour === "auto"
        ? (Config.wallpaperAccent !== "" ? ["--auto", Config.wallpaperAccent] : [])
        : (Config.s.folderColour !== "" ? [Config.s.folderColour] : [])
    onFolderArgsChanged: folderTimer.restart()
    Timer {
        id: folderTimer
        interval: 1200; running: true
        onTriggered: if (!root.hold.heldBack(folderTimer) && root.folderArgs.length) { folderRun.command = [Quickshell.shellPath("scripts/folder-colour.py")].concat(root.folderArgs); folderRun.running = true; }
    }
    Process { id: folderRun }

    // The icon theme (Settings → Icons → Icon theme): set for GTK, Qt and KDE apps, then the
    // folder colour made again on top of it (it's built on whichever theme is in use; a theme
    // that isn't Papirus has no coloured folders, so that does nothing). Slate's own tiles
    // follow by themselves (Config.tileDir has the theme in it)
    // ("" goes back to the theme this computer had before one was chosen, Config.s.iconThemeBefore)
    readonly property string iconThemeWanted: Config.iconThemeChosen !== "" ? Config.iconThemeChosen
        : (/^[\w.+-]+$/.test(Config.s.iconThemeBefore) ? Config.s.iconThemeBefore : "")
    onIconThemeWantedChanged: iconThemeTimer.restart()
    Timer { id: iconThemeTimer; interval: 800; onTriggered: if (root.iconThemeWanted !== "" && !Config.testMode) { iconThemeRun.running = false; iconThemeRun.running = true; } }
    Process {
        id: iconThemeRun
        command: [Quickshell.shellPath("scripts/folder-colour.py"), "--icon-theme", root.iconThemeWanted]
        onExited: folderTimer.restart()
    }

    // Apps switched on in Settings → App Theming follow Slate's theme:
    // scripts/apply-theme.py writes their themes from these colours, a moment after a change
    readonly property string themeJson: JSON.stringify({
        accent: Config.accent.toString(), accentText: Config.palette.accentText.toString(),
        bg: Config.palette.base.toString(), surface: Config.palette.card.toString(),
        surfaceHigh: Config.palette.divider.toString(), text: Config.palette.text.toString(),
        dim: Config.palette.dim.toString(), error: Config.palette.danger.toString(),
        light: Config.s.lightMode,
        codeFont: Config.s.codeFontFamily,
        // The cursor size set in Settings (0 = not set): Slate's own environment still has the
        // size from when it started, so apps would get the old one back without this
        cursorSize: Config.s.cursorSize,
        // ...and its theme (Settings → Input → Pointer style; "" = as the session set it)
        cursorTheme: Config.s.cursorTheme,
        // Whether the pointer and the code font reach other apps' own settings too (Settings →
        // Input, Settings → Appearance; off until chosen, and undone when switched off)
        pointerInApps: Config.s.pointerInApps,
        codeFontInApps: Config.s.codeFontInApps,
        // Accessibility → Text size: GTK apps' text grows to match (only with GTK themed)
        textScale: Config.textScale,
        // Quick Look on Dolphin's and Thunar's menus (Settings → Default Apps; off until chosen)
        quickLookInFileManagers: Config.s.quickLookInFileManagers,
        on: Config.s.themedApps || []
    })
    onThemeJsonChanged: themeApply.restart()
    // (only when they've changed since: the wallpaper switcher closed without keeping one
    // leaves them as they were)
    Timer { id: themeApply; interval: 1500; running: true; onTriggered: if (!root.hold.heldBack(themeApply) && root.themeJson !== root.themeApplied) root.applyThemes() }
    property string themeApplied: ""
    function applyThemes() {
        themeApplied = themeJson;
        themeProc.running = false;
        themeProc.command = ["python3", Quickshell.shellPath("scripts/apply-theme.py"), root.themeJson];
        themeProc.running = true;
    }
    Process {
        id: themeProc
        // What it says about themes an app's update had undone (Spotify's by Spicetify, Discord's
        // by Vencord): "restored <id> <name>" where it put one back, "lost <id> <name>" where
        // it couldn't. Passed on as a notification
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const m = line.match(/^(restored|lost) (\S+) (.+)$/);
                    if (m) root.themeNotice(m[1], m[2], m[3]);
                    // "adopt pointer" / "adopt code-font": an older Slate had set that one already
                    // (it used to, without asking), so its switch goes on and it's kept, now
                    // recorded and undoable (the script says how it tells)
                    if (line === "adopt pointer") Config.s.pointerInApps = true;
                    else if (line === "adopt code-font") Config.s.codeFontInApps = true;
                }
            }
        }
    }
    function themeNotice(kind, id, name) {
        if (kind === "restored") {
            if (id === "spotify") {
                spotifyNote.command = Config.notify(name + "'s theme is back",
                    name + " was updated, which took Slate's theme with it. Slate has put it back for you: restart " + name + " to see it.",
                    { page: "apptheming", actions: ["restart=Restart Spotify"] });
                spotifyNote.running = false; spotifyNote.running = true;
            } else Quickshell.execDetached(Config.notify(name + "'s theme is back",
                name + " was updated, which took Slate's theme with it. Slate has put it back for you: restart " + name + " to see it.",
                { page: "apptheming" }));
        } else Quickshell.execDetached(Config.notify(name + " lost its theme",
            id === "discord" ? name + " was updated, which removed Vencord. Once you've installed Vencord again, Slate's theme will come back with it."
                             : name + " was updated, and Slate couldn't patch the new version just yet. Refresh in Settings → App Theming is worth a try a little later.",
            { page: "apptheming" }));
    }
    Process {
        id: spotifyNote
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "restart")
                Quickshell.execDetached(["sh", "-c", 'exec "$(command -v spicetify || echo "$HOME/.spicetify/spicetify")" restart'])
        }
    }
    // An update of Spotify or Discord takes Slate's theme out of it (it's patched in). Looked
    // for every few minutes while either is themed; applying the themes again puts it back
    // Whether that look-out is running (the test suite checks it's idle when nothing is themed)
    readonly property bool staleWatching: themeStaleTimer.running
    Timer {
        id: themeStaleTimer
        interval: 300000
        repeat: true
        running: !Config.testMode && (Config.s.themedApps || []).some(a => a === "spotify" || a === "discord")
        onTriggered: if (!themeProc.running && !themeStale.running) themeStale.running = true
    }
    Process {
        id: themeStale
        command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--stale", root.themeJson]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.applyThemes() }
    }
    // Settings → App Theming → Refresh: write every switched-on app's theme again now
    Binding { target: Config; property: "themesBusy"; value: themeProc.running }
    Connections { target: Config; function onRefreshThemes() { themeApply.stop(); root.applyThemes(); } }
}
