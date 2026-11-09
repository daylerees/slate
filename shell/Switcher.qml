// Super+Tab window switcher: a horizontal strip of open windows, most recently
// used first. Hold Super and press Tab (Shift+Tab goes back); let go of Super to
// switch. Escape cancels; clicking a window switches to it.
//
// Driven from Hyprland (config/binds.lua):
//   slate ipc call switcher next | prev | commit | cancel

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: sw
    required property var bar

    // ---- Look --------------------------------------------------------------
    readonly property real cardW: 250
    readonly property real cardH: 200
    readonly property real previewH: 140
    readonly property real tileSize: 64
    readonly property color selectColor: Config.tint("#262c35")
    readonly property color dim: Config.tint("#8b94a3")
    readonly property string tileDir: Config.tileDir

    // ---- Most recently used order (window addresses, newest first) ----------
    property var mru: []
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            const t = Hyprland.activeToplevel;
            if (!t || !t.address) return;
            sw.mru = [t.address].concat(sw.mru.filter(a => a !== t.address));
        }
    }
    function currentWindows() {
        // Normal workspaces only: the secret (special) workspace stays out of the switcher
        const all = Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id > 0 && t.title !== undefined);
        const rank = a => { const i = mru.indexOf(a); return i < 0 ? 1e6 : i; };
        return all.slice().sort((a, b) => rank(a.address) - rank(b.address));
    }

    // ---- Open / move / switch ----------------------------------------------
    property bool shown: false
    property var windows: []          // snapshot taken when opened
    property int index: 0             // position on the (repeated) strip
    property bool animate: false

    // The windows are repeated round the loop as often as needed to fill the
    // screen, so the strip always feels endless (a single window isn't repeated)
    readonly property int reps: windows.length < 2 ? 1
        : Math.max(1, Math.ceil((width - 80 + 2 * cardW) / (windows.length * cardW)))
    readonly property var strip: {
        const out = [];
        for (let r = 0; r < reps; r++) for (const w of windows) out.push(w);
        return out;
    }

    function open(step) {
        screen = Config.focusedScreen;     // open on the focused screen
        windows = currentWindows();
        if (windows.length === 0) return;
        // Jump straight to the starting window, then animate further moves
        animate = false;
        index = windows.length > 1 ? (step > 0 ? 1 : windows.length - 1) : 0;
        shown = true;
        syncStrip();
        animateTimer.restart();
    }
    // Moves animate once the switcher is up (the start position jumps)
    Timer {
        id: animateTimer
        interval: 120
        onTriggered: { sw.syncStrip(); sw.animate = true; }
    }
    function move(step) {
        if (!shown) open(step);
        else index = (index + step + strip.length) % strip.length;
        if (windows.length > 1) Config.swish(step);       // one window: nothing moves, so no swish
    }
    // The strip's position is set from here rather than bound to index: while the
    // switcher is opening (the strip rebuilding for the new windows, the window not yet
    // sized) the strip drops a new position and stays on its first card, and a binding
    // wouldn't send the same index again, so the first move skipped a window. So it's
    // sent again whenever the strip changes size or contents.
    onIndexChanged: syncStrip()
    function syncStrip() {
        if (list.count > 0 && list.currentIndex !== index) list.currentIndex = Math.max(0, Math.min(list.count - 1, index));
    }
    function commit() {
        if (!shown || releasing) return;
        const t = strip[index];
        if (!t || !t.address) { shown = false; return; }
        pendingAddress = t.address.startsWith("0x") ? t.address : "0x" + t.address;
        releasing = true;          // let go of the keyboard but stay on screen...
        focusTimer.restart();      // ...then switch and fade out together
    }
    // Let go of the keyboard (Hyprland won't switch while we hold it) without hiding yet
    property bool releasing: false
    // Focus the chosen window once the switcher has let go of the keyboard;
    // Hyprland won't move focus while it still holds it. (Wayland's own
    // "activate" request is ignored by Hyprland, so ask Hyprland directly.)
    property string pendingAddress: ""
    Timer {
        id: focusTimer
        interval: 40
        onTriggered: {
            Quickshell.execDetached(["hyprctl", "dispatch", `function() fadeTo(hl.dsp.focus({ window = "address:${sw.pendingAddress}" })) end`]);   // crossfade
            sw.shown = false;
            sw.releasing = false;
        }
    }
    function cancel() { shown = false; }

    IpcHandler {
        target: "switcher"
        function next(): void { sw.move(1); }
        function prev(): void { sw.move(-1); }
        function commit(): void { sw.commit(); }
        function cancel(): void { sw.cancel(); }
    }

    function lookup(appId) {
        if (!appId) return null;
        const e = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        if (e) return e;
        const parts = appId.toLowerCase().split(".");
        if (parts.length < 3) return null;
        const prefix = parts.slice(0, 2).join(".") + ".";
        return DesktopEntries.applications.values.find(a => a.id.toLowerCase().startsWith(prefix)) ?? null;
    }

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(200); easing.type: Easing.InOutQuad } }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown && !releasing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; enabled: sw.shown; onClicked: sw.cancel() }

    // Workspace dots under the switcher (as on the bar); the accent marker sits on the
    // selected window's workspace and slides as the selection moves
    Rectangle {
        id: wsPill
        anchors { top: panel.bottom; topMargin: 14; horizontalCenter: panel.horizontalCenter }
        width: wsDots.width + 28; height: 34; radius: 17
        color: sw.bar.barColor
        opacity: sw.fade
        Gloss { radius: parent.radius }   // glass: a sheen, like the bar's workspace container
        readonly property real dot: 14
        readonly property real gap: 8
        readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
        readonly property var selected: sw.strip.length ? sw.strip[Math.max(0, Math.min(sw.strip.length - 1, sw.index))] : null
        readonly property int activeIndex: Math.max(0, spaces.findIndex(w => selected && selected.workspace && w.id === selected.workspace.id))
        Row {
            id: wsDots
            anchors.centerIn: parent
            spacing: wsPill.gap
            Repeater {
                model: wsPill.spaces
                delegate: Rectangle {
                    required property var modelData
                    width: wsPill.dot; height: wsPill.dot; radius: Config.dotRadius(wsPill.dot)
                    color: (modelData.toplevels?.values?.length ?? 0) > 0 ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                }
            }
        }
        WorkspaceMarker {
            x: wsDots.x; y: wsDots.y
            width: wsDots.width; height: wsDots.height
            dot: wsPill.dot; step: wsPill.dot + wsPill.gap
            index: wsPill.activeIndex
            animate: sw.animate
            color: sw.bar.accent
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(sw.width - 80, sw.strip.length * sw.cardW + 24)
        height: sw.cardH + 24
        radius: 18
        color: sw.bar.barColor
        opacity: sw.fade
        scale: 0.97 + 0.03 * sw.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: !Config.glass
            shadowColor: "#000000"
            shadowOpacity: 0.45
            shadowBlur: 1.0
            shadowVerticalOffset: 8
            blurMax: 48
        }
        MouseArea { anchors.fill: parent }

        // Keyboard, for when the keys reach us directly
        Item {
            focus: sw.shown
            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Escape: sw.cancel(); break;
                case Qt.Key_Return: case Qt.Key_Enter: sw.commit(); break;
                case Qt.Key_Right: case Qt.Key_Tab: sw.move(1); break;
                case Qt.Key_Left: case Qt.Key_Backtab: sw.move(-1); break;
                default: return;
                }
                e.accepted = true;
            }
            Keys.onReleased: e => {
                if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) sw.commit();
            }
        }

        // Selection stays fixed in the middle of the screen; the windows slide past it
        Rectangle {
            anchors.centerIn: list
            width: sw.cardW; height: sw.cardH
            radius: 12
            color: sw.selectColor
            Gloss { radius: parent.radius }   // glass: a sheen
        }

        // A circular strip: the selected window is always centred and the strip
        // wraps around, moving whichever way is shorter
        PathView {
            id: list
            anchors { fill: parent; margins: 12 }
            clip: true
            interactive: false
            model: sw.strip
            onCountChanged: sw.syncStrip()
            onWidthChanged: sw.syncStrip()
            onVisibleChanged: sw.syncStrip()
            readonly property real len: Math.max(1, sw.strip.length) * sw.cardW
            path: Path {
                startX: list.width / 2 - list.len / 2; startY: list.height / 2
                PathLine { x: list.width / 2 + list.len / 2; y: list.height / 2 }
            }
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: sw.animate ? 220 : 0

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property var entry: sw.lookup(modelData.wayland ? modelData.wayland.appId : "")
                readonly property string key: entry ? entry.id : (modelData.wayland ? modelData.wayland.appId : "")
                readonly property string tilePath: sw.tileDir + "/" + key.replace(/[^A-Za-z0-9._-]/g, "_") + ".png"
                width: sw.cardW
                height: sw.cardH

                // Live preview of the window, scaled to fit, with rounded corners
                Item {
                    id: previewBox
                    anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter }
                    width: sw.cardW - 20
                    height: sw.previewH
                    // Behind a see-through window: the wallpaper blurred as on screen, from
                    // where the window is on its screen
                    WallBlur {
                        readonly property var o: card.modelData.lastIpcObject
                        readonly property var m: o ? Hyprland.monitors.values.find(x => x.id === o.monitor) ?? null : null
                        visible: Config.hyprBlur.enabled && Config.s.switcherPreviews && !!o && !!o.at && !!m && shot.hasContent
                        anchors.fill: shot
                        win: visible ? Qt.rect(o.at[0] - m.x, o.at[1] - m.y, o.size[0], o.size[1]) : Qt.rect(0, 0, 1, 1)
                        screen: m ? Qt.size(m.width / (m.scale || 1), m.height / (m.scale || 1)) : Qt.size(1, 1)
                        pixelScale: o && o.size ? shot.width / Math.max(1, o.size[0]) : 0.25
                        radius: 8
                    }
                    ScreencopyView {
                        id: shot
                        readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * ratio)
                        height: width / ratio
                        // Not in game mode: the window's shape and app tile instead (below)
                        captureSource: Config.s.switcherPreviews && !Config.gameMode && sw.shown && card.modelData.wayland ? card.modelData.wayland : null
                        live: sw.shown && !sw.releasing     // stop updating once chosen: less work during the fade
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: shotMask }
                    }
                    Item {
                        id: shotMask
                        anchors.fill: shot
                        visible: false
                        layer.enabled: true
                        Rectangle { anchors.fill: parent; radius: 8 }
                    }
                    // Game mode: an outline in the window's proportions, with the app's tile in it
                    Rectangle {
                        readonly property var o: card.modelData.lastIpcObject
                        readonly property real ratio: o && o.size && o.size[1] > 0 ? o.size[0] / o.size[1] : 16 / 10
                        visible: Config.gameMode
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * ratio)
                        height: width / ratio
                        radius: 8
                        color: Qt.rgba(0.07, 0.08, 0.1, 0.72)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                    }
                    // No capture available (or game mode): show the app's tile instead
                    Image {
                        anchors.centerIn: parent
                        visible: !shot.hasContent
                        width: sw.tileSize; height: sw.tileSize
                        source: card.key ? "file://" + card.tilePath + "?v=" + Config.tileVersion : ""
                        sourceSize: Qt.size(192, 192)
                        smooth: true; mipmap: true
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
                    }
                    // The window came from a space: its badge on the preview's top left corner
                    SpaceBadge {
                        x: shot.x - 6; y: shot.y - 6
                        size: 24
                        space: Config.s.spaceSwitcherBadges ? Spaces.spaceById(Spaces.spaceOfAddress[card.modelData.address]) : null
                    }
                    // Small app tile on the preview's corner (Settings → Windows)
                    Image {
                        visible: shot.hasContent && Config.s.switcherAppIcons
                        x: shot.x - 6; y: shot.y + shot.height - height + 6
                        width: 30; height: 30
                        source: card.key ? "file://" + card.tilePath + "?v=" + Config.tileVersion : ""
                        sourceSize: Qt.size(96, 96)
                        smooth: true; mipmap: true
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
                    }
                }
                Text {
                    id: title
                    anchors { top: previewBox.bottom; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
                    horizontalAlignment: Text.AlignHCenter
                    text: card.modelData.title || (card.entry ? card.entry.name : card.key)
                    color: sw.bar.textColor
                    font.family: sw.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                ClickArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { sw.index = card.index; sw.commit(); }
                }
            }
        }

        // Inner shadows at both ends when there are more windows than fit
        Repeater {
            model: [0, 1]
            Rectangle {
                required property int modelData
                visible: list.len > list.width
                width: 56
                anchors { top: parent.top; bottom: parent.bottom }
                x: modelData === 0 ? 0 : parent.width - width
                topLeftRadius: modelData === 0 ? panel.radius : 0
                bottomLeftRadius: modelData === 0 ? panel.radius : 0
                topRightRadius: modelData === 1 ? panel.radius : 0
                bottomRightRadius: modelData === 1 ? panel.radius : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: modelData === 0 ? Qt.rgba(0, 0, 0, 0.6) : "transparent" }
                    GradientStop { position: 1.0; color: modelData === 0 ? "transparent" : Qt.rgba(0, 0, 0, 0.6) }
                }
            }
        }
    }
}
