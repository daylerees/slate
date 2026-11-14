// The desktop wallpaper: one background layer per screen, filling it (cropped to fit).
// Changing it cross-fades from the old image to the new one (WallpaperFill.qml).
// Set it from Settings → Appearance, or:  slate ipc call wallpaper set <path>
// It can also change by itself (Settings → Wallpaper → Change wallpaper): at each login
// or every so often, to another image from the wallpaper folder. The accent and tint follow
// the new image when they're set to come from the wallpaper.
//   slate ipc call wallpaper next      change to another one now
//   slate ipc call wallpaper switcher  the wallpaper switcher (Super+Alt+W: WallpaperSwitcher.qml)

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    required property var bar                 // the main bar: the switcher takes its look
    readonly property alias switcher: switcherWin
    property string desktopShowing: ""      // (the tests': the picture really on the first screen's desktop)

    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { Config.s.wallpaper = path; }
        function get(): string { return Config.wallpaper; }
        function next(): void { root.changeWallpaper(); }
        // (open: the next one along, as pressing its shortcut again does)
        function switcher(): void { switcherWin.open(); }
    }

    // For the desktop's right-click menu: a Slate command, or one of the default apps (the
    // terminal / file manager the shortcuts open, as set in Hyprland's config or Settings)
    function slateCall(args) { Config.slateCall(...args); }
    function openApp(variable) {
        Quickshell.execDetached(["hyprctl", "dispatch",
            `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. ${variable}) end`]);
    }

    // The wallpapers that come with Slate
    readonly property string ownFolder: Quickshell.shellPath("wallpapers")

    // ---- The wallpapers to choose from -------------------------------------------
    // As Settings → Wallpaper shows them: the images in the folder by name (small ones left
    // out when it hides them), then the wallpapers that come with Slate, while it shows them.
    // listWallpapers(then) reads the folder and hands then() the list (paths)
    readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
    function listWallpapers(then) { lister.then = then; lister.running = false; lister.running = true; }
    Process {
        id: lister
        property var then: null
        command: [Quickshell.shellPath("scripts/image-sizes.py"), root.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                let sizes = {};
                try { sizes = JSON.parse(text); } catch (e) {}       // (no such folder: Slate's own may still do)
                const min = Config.s.wallpaperMinSize.split("x").map(Number);
                const ok = Object.keys(sizes).filter(n => !Config.s.wallpaperHideSmall || (sizes[n][0] >= min[0] && sizes[n][1] >= min[1]))
                    .sort().map(n => root.folder + "/" + n);
                if (Config.s.wallpaperShowSlate) for (let i = 0; i < slateFiles.count; i++) ok.push(slateFiles.get(i, "filePath"));
                const then = lister.then;
                lister.then = null;
                if (then) then(ok);
            }
        }
    }
    FolderListModel {
        id: slateFiles
        folder: Config.s.wallpaperShowSlate ? "file://" + root.ownFolder : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
    }

    // ---- Changing by itself ------------------------------------------------------
    readonly property string mode: Config.s.wallpaperChange
    readonly property int everyMinutes: parseInt(mode) || 0
    // Images still to show this round, in a shuffled order, so each one comes up once
    // before any repeats
    property var queue: []
    property string queueFolder: ""
    function changeWallpaper() { listWallpapers(ok => root.changeFrom(ok)); }
    function changeFrom(ok) {
        if (ok.length === 0) return;
        const current = Config.s.wallpaper;
        let q = root.queueFolder === root.folder ? root.queue.filter(p => ok.includes(p) && p !== current) : [];
        if (q.length === 0) {
            q = ok.filter(p => p !== current);
            for (let i = q.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [q[i], q[j]] = [q[j], q[i]]; }
        }
        if (q.length === 0) return;          // only the current one
        Config.s.wallpaper = q[0];
        root.queue = q.slice(1);
        root.queueFolder = root.folder;
    }
    // Every so often
    Timer {
        interval: Math.max(1, root.everyMinutes) * 60000
        running: root.everyMinutes > 0
        repeat: true
        onTriggered: if (!Config.wallpaperSwitching) root.changeWallpaper()     // (not while you're choosing one)
    }
    // At login (Config.atLogin: once per login, not when Slate restarts); turning the
    // setting on later waits for the next login
    Connections {
        target: Config
        function onAtLogin() { if (root.mode === "login") root.changeWallpaper(); }
    }

    // The wallpaper switcher (Super+Alt+W)
    WallpaperSwitcher { id: switcherWin; bar: root.bar; wallpapers: root }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: Config.tint("#0f1216")          // plain slate until (or if no) image loads
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-wallpaper"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Right-click the desktop: a menu of things to do from here. (A plain MouseArea: the
            // desktop isn't a button, so the pointer stays an arrow over it)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: m => desktopMenu.openAt(m.x, m.y)
            }
            DesktopMenu {
                id: desktopMenu
                screen: win.modelData
                items: [
                    { label: "App launcher", icon: 0xEBB6, run: () => root.slateCall(["launcher", "open"]) },
                    { label: "Terminal", icon: 0xEBEF, run: () => root.openApp("TERMINAL") },
                    { label: "Files", icon: 0xEAAD, run: () => root.openApp("FILE_MANAGER") },
                    { separator: true },
                    { label: "Change wallpaper…", icon: 0xEB0A, run: () => root.slateCall(["settings", "page", "wallpaper"]) },
                    { label: "Next wallpaper", icon: 0xF000, run: () => root.changeWallpaper() },
                    { separator: true },
                    { label: "Display settings", icon: 0xEA89, run: () => root.slateCall(["settings", "page", "displays"]) },
                    { label: "Settings", icon: 0xEB20, run: () => root.slateCall(["settings", "open"]) }
                ]
            }

            WallpaperFill {
                anchors.fill: parent
                path: Config.wallpaper
                pixelRatio: win.modelData.devicePixelRatio || 1
                onShowingChanged: if (win.modelData === Quickshell.screens[0]) root.desktopShowing = showing
            }
        }
    }
}
