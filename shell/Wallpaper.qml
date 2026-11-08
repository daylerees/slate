// The desktop wallpaper: one background layer per screen, filling it (cropped to fit).
// Changing it cross-fades from the old image to the new one.
// Set it from Settings → Appearance, or:  slate ipc call wallpaper set <path>
// It can also change by itself (Settings → Appearance → Change wallpaper): at each login
// or every so often, to another image from the wallpaper folder. The accent and tint follow
// the new image when they're set to come from the wallpaper.
//   slate ipc call wallpaper next      change to another one now

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { Config.s.wallpaper = path; }
        function get(): string { return Config.wallpaper; }
        function next(): void { root.changeWallpaper(); }
    }

    // For the desktop's right-click menu: a Slate command, or one of the default apps (the
    // terminal / file manager the shortcuts open, as set in Hyprland's config or Settings)
    function slateCall(args) { Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call"].concat(args)); }
    function openApp(variable) {
        Quickshell.execDetached(["hyprctl", "dispatch",
            `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. ${variable}) end`]);
    }

    // ---- Changing by itself ------------------------------------------------------
    readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
    readonly property string mode: Config.s.wallpaperChange
    readonly property int everyMinutes: parseInt(mode) || 0
    // Images still to show this round, in a shuffled order, so each one comes up once
    // before any repeats
    property var queue: []
    property string queueFolder: ""
    function changeWallpaper() { lister.running = false; lister.running = true; }
    Process {
        id: lister
        command: [Quickshell.shellPath("scripts/image-sizes.py"), root.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                let sizes = {};
                try { sizes = JSON.parse(text); } catch (e) { return; }
                // The same images Settings shows: small ones left out when it hides them
                const min = Config.s.wallpaperMinSize.split("x").map(Number);
                const ok = Object.keys(sizes).filter(n => !Config.s.wallpaperHideSmall || (sizes[n][0] >= min[0] && sizes[n][1] >= min[1]))
                    .map(n => root.folder + "/" + n);
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
        }
    }
    // Every so often
    Timer {
        interval: Math.max(1, root.everyMinutes) * 60000
        running: root.everyMinutes > 0
        repeat: true
        onTriggered: root.changeWallpaper()
    }
    // At login (Config.atLogin: once per login, not when Slate restarts); turning the
    // setting on later waits for the next login
    Connections {
        target: Config
        function onAtLogin() { if (root.mode === "login") root.changeWallpaper(); }
    }

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

            // Right-click the desktop: a menu of things to do from here
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

            // Two images take turns: the new one loads hidden, then fades in over the old
            property int front: 0
            readonly property var images: [imgA, imgB]
            readonly property string wanted: Config.wallpaper ? "file://" + Config.wallpaper : ""
            onWantedChanged: {
                const back = images[1 - front];
                if (images[front].source.toString() === wanted) return;
                back.opacity = 0;
                back.source = wanted;
            }

            component Layer: Image {
                id: layer
                // A few pixels past each edge: some wallpapers have a stray light or dark row or
                // column at the very edge, which would show as a line along the screen edge
                anchors { fill: parent; margins: -4 }
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                sourceSize.width: win.width * (win.modelData.devicePixelRatio || 1)
                sourceSize.height: win.height * (win.modelData.devicePixelRatio || 1)
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
                onStatusChanged: {
                    if (status !== Image.Ready || source.toString() !== win.wanted) return;
                    const i = win.images.indexOf(layer);
                    if (i === win.front && opacity === 1) return;
                    z = 1; win.images[1 - i].z = 0;
                    opacity = 1;
                    win.front = i;
                    retire.restart();
                }
            }
            Layer { id: imgA; Component.onCompleted: source = win.wanted }
            Layer { id: imgB }
            // Once the new image is in, drop the old one to free its memory
            Timer {
                id: retire
                interval: 700
                onTriggered: { const old = win.images[1 - win.front]; old.opacity = 0; old.source = ""; }
            }
        }
    }
}
