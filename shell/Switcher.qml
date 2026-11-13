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
    // Live pictures of the windows (Settings → Windows → Windows show), not in game mode
    readonly property bool livePreviews: Config.s.switcherPreviews && !Config.gameMode

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
    // Settings → Windows: how the selection moves (slide: the row slides under a fixed
    // highlight; hop: the cards hop as they go; wheel: round the outside of a turning circle;
    // tilt: the others turned away in 3D either side; orbit: round a 3D ring; deck: a pile dealt
    // from; fan: a hand of cards; or instant) and how it goes to the window picked (crossfade, workspace: the
    // workspace animation, or instant)
    readonly property string moveAnim: ["slide", "hop", "wheel", "tilt", "orbit", "deck", "fan", "instant"].includes(Config.s.switcherMoveAnimation) ? Config.s.switcherMoveAnimation : "slide"
    readonly property string pickAnim: ["crossfade", "workspace", "instant"].includes(Config.s.switcherPickAnimation) ? Config.s.switcherPickAnimation : "crossfade"
    readonly property bool moveAnimated: animate && moveAnim !== "instant"
    // Going to a window with Instant: the switcher goes at once too
    property bool quickClose: false

    // The windows are repeated round the loop as often as needed to fill the
    // screen, so the strip always feels endless (a single window isn't repeated)
    readonly property int reps: windows.length < 2 ? 1
        : Math.max(1, Math.ceil((width - 80 + 2 * cardW) / (windows.length * cardW)),
                   Math.ceil(({ tilt: 9, orbit: 10, deck: 6, fan: 12 })[moveAnim] / windows.length) || 1)     // (far enough round that the strip's ends are never seen)
    // Hop and wheel need room above or below the cards
    readonly property real extraH: ({ hop: 30, wheel: 80, orbit: 70, deck: 70, fan: 80 })[moveAnim] || 0
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
        quickClose = false;
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
            // Crossfade (fadeTo), the workspace animation, or none (animations.lua)
            const how = { crossfade: "fadeTo", workspace: "hl.dispatch", instant: "instantTo" }[sw.pickAnim];
            Quickshell.execDetached(["hyprctl", "dispatch", `function() ${how}(hl.dsp.focus({ window = "address:${sw.pendingAddress}" })) end`]);
            sw.quickClose = sw.pickAnim === "instant";
            sw.shown = false;
            sw.releasing = false;
            arriveTries = 0;
            arriveCheck.restart();
        }
    }
    // In case the switch was lost (Hyprland hadn't yet seen the switcher let go of the keyboard,
    // so it ignored the focus: seen now and then when the computer's busy): look a moment later,
    // and ask again if the chosen window isn't the one in use. Plainly, without the animation,
    // and only a few times.
    property int arriveTries: 0
    Timer { id: arriveCheck; interval: 250; onTriggered: { arrived.running = false; arrived.running = true; } }
    Process {
        id: arrived
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (sw.shown || sw.pendingAddress === "") return;       // (opened again since)
                let now = "";
                try { now = JSON.parse(text).address || ""; } catch (e) {}
                if (now === sw.pendingAddress || ++sw.arriveTries > 3) return;
                Quickshell.execDetached(["hyprctl", "dispatch", `function() hl.dispatch(hl.dsp.focus({ window = "address:${sw.pendingAddress}" })) end`]);
                arriveCheck.restart();
            }
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

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: sw.quickClose ? 0 : Config.ms(200); easing.type: Easing.InOutQuad } }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown && !releasing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; enabled: sw.shown; onClicked: sw.cancel() }

    // ---- Live captures ------------------------------------------------------
    // One capture per window, drawn off-screen at exactly a card's preview size and shown on
    // each card through a copy (shotFor). The strip repeats the windows round the loop, so
    // with a capture per card the same window was captured several times over.
    function shotFor(win) {
        for (let i = 0; i < shotRepeater.count; i++) {       // (count: re-run as they're made)
            const it = shotRepeater.itemAt(i);
            if (it && it.win === win) return it;
        }
        return null;
    }
    // How many of the live captures have a picture yet (the test IPC's state)
    function previewsReady() {
        let n = 0;
        for (let i = 0; i < shotRepeater.count; i++) {
            const it = shotRepeater.itemAt(i);
            if (it && it.hasContent) n++;
        }
        return n;
    }
    // The wallpaper behind see-through windows' previews (WallBlur), decoded ahead of time at
    // WallBlur's size so it's in the image cache as the switcher opens
    Image {
        visible: false
        source: Config.hyprBlur.enabled && Config.wallpaper ? "file://" + Config.wallpaper : ""
        sourceSize: Qt.size(1600, 1000)     // (WallBlur's decodeSize)
        asynchronous: true
    }
    Item {
        x: -10000
        Repeater {
            id: shotRepeater
            model: sw.windows
            delegate: WindowPreview {
                required property var modelData
                readonly property var win: modelData
                // Fitted to a card's preview area, keeping the window's shape
                readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                width: Math.min(sw.cardW - 20, sw.previewH * ratio)
                height: width / ratio
                window: sw.livePreviews && sw.shown && modelData.wayland ? modelData.wayland : null
                running: sw.shown && !sw.releasing     // stop updating once chosen: less work during the fade
            }
        }
    }

    // Workspace dots under the switcher (as on the bar); the accent marker sits on the
    // selected window's workspace and slides as the selection moves
    Rectangle {
        id: wsPill
        anchors { top: panel.bottom; topMargin: 14; horizontalCenter: panel.horizontalCenter }
        width: wsDots.width + 28; height: 34; radius: Config.dotHolderRadius(height)
        color: sw.bar.barColor
        opacity: sw.fade
        Gloss { radius: parent.radius }   // glass: a sheen, like the bar's workspace container
        readonly property real dot: 14
        readonly property real gap: 8
        readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
        readonly property var selected: sw.strip.length ? sw.strip[Math.max(0, Math.min(sw.strip.length - 1, sw.index))] : null
        readonly property int activeIndex: Math.max(0, spaces.findIndex(w => selected && selected.workspace && w.id === selected.workspace.id))
        // Ten at most: with more workspaces, the row scrolls to keep the selected window's in
        // view and shrinks away at an end with more beyond (WorkspaceDots)
        WorkspaceDots {
            id: wsDots
            anchors.centerIn: parent
            spaces: wsPill.spaces
            activeIndex: wsPill.activeIndex
            dot: wsPill.dot; gap: wsPill.gap
            maxVisible: 10
            animate: sw.moveAnimated
            accent: sw.bar.accent
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(sw.width - 80, sw.strip.length * sw.cardW + 24)
        height: sw.cardH + 24 + sw.extraH
        radius: Config.corner(18)
        color: sw.bar.barColor
        opacity: sw.fade
        scale: 0.97 + 0.03 * sw.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        Shadow {}      // raised: Slate's shadow, with glass too
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
            anchors.horizontalCenter: list.horizontalCenter
            y: list.y + list.restY - height / 2
            width: sw.cardW; height: sw.cardH
            radius: Config.corner(12)
            color: Config.accent           // the active colour
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
            // Where a card rests: at the bottom for hop (it hops up into the room above), at the top
            // for the wheel (the others drop away round it), otherwise in the middle
            readonly property real restY: ["hop", "orbit", "deck"].includes(sw.moveAnim) ? height - sw.cardH / 2
                : sw.moveAnim === "wheel" ? sw.cardH / 2 : sw.moveAnim === "fan" ? sw.cardH / 2 + 24 : height / 2
            // Each card's distance along the strip from the middle ("side", in pixels) and the
            // wheel's turn there ("turn", in degrees), for the cards to lean and tilt by
            Path {
                id: linePath
                startX: list.width / 2 - list.len / 2; startY: list.restY
                PathAttribute { name: "side"; value: -list.len / 2 }
                PathAttribute { name: "turn"; value: 0 }
                PathLine { x: list.width / 2 + list.len / 2; y: list.restY }
                PathAttribute { name: "side"; value: list.len / 2 }
                PathAttribute { name: "turn"; value: 0 }
            }
            // The wheel: the strip bent round a circle below, the chosen card at the top
            readonly property real wheelR: Math.max(len / (2 * Math.PI) * 1.02, sw.cardW * 2.4)
            readonly property real sweep: len / wheelR * 180 / Math.PI
            readonly property real a0: (-90 - sweep / 2) * Math.PI / 180
            Path {
                id: wheelPath
                startX: list.width / 2 + list.wheelR * Math.cos(list.a0); startY: list.restY + list.wheelR + list.wheelR * Math.sin(list.a0)
                PathAttribute { name: "side"; value: -list.len / 2 }
                PathAttribute { name: "turn"; value: -list.sweep / 2 }
                PathAngleArc {
                    centerX: list.width / 2; centerY: list.restY + list.wheelR
                    radiusX: list.wheelR; radiusY: list.wheelR
                    startAngle: -90 - list.sweep / 2; sweepAngle: list.sweep
                    moveToStart: false
                }
                PathAttribute { name: "side"; value: list.len / 2 }
                PathAttribute { name: "turn"; value: list.sweep / 2 }
            }
            path: sw.moveAnim === "wheel" ? wheelPath : linePath
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: sw.moveAnimated ? Config.ms(220) : 0     // (Animations: Fast halves it, Off makes it instant)

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property var entry: Config.appEntry(modelData.wayland ? modelData.wayland.appId : "")
                readonly property string key: entry ? entry.id : (modelData.wayland ? modelData.wayland.appId : "")
                readonly property string tilePath: Config.tilePath(key)
                width: sw.cardW
                height: sw.cardH
                // Movement (sw.moveAnim): how far along it is from the middle, in cards
                readonly property real side: PathView.side ?? 0
                readonly property real t: side / sw.cardW
                readonly property string fx: sw.moveAnim
                // Hop: every card rises and falls once for each step the strip moves
                readonly property real hop: fx === "hop" ? Math.sin(Math.PI * Math.abs(list.offset - Math.round(list.offset))) : 0
                // Tilt: the others turned away, packed closer the further out they are, and
                // fading out before the strip's ends
                readonly property bool tilted: fx === "tilt"
                readonly property real packed: Math.sign(t) * (Math.min(Math.abs(t), 1) * 0.7 + Math.max(Math.abs(t) - 1, 0) * 0.28) * sw.cardW
                // Orbit: round a flat ring seen from above the front, the far side small, dim and higher
                readonly property real th: t * 0.7
                readonly property real orbitR: sw.cardW * 2.3
                // Fan: turned about a point well below, like a hand of cards; the chosen one lifted
                readonly property real fanPivot: height + height * 2.2
                readonly property real fanStep: (sw.cardW * 0.45 / fanPivot) * 180 / Math.PI
                rotation: fx === "wheel" ? (PathView.turn ?? 0) : 0
                z: fx === "orbit" ? Math.cos(th) * 10 : (tilted || fx === "deck" || fx === "fan") ? -Math.abs(t) : 0
                scale: fx === "orbit" ? 0.45 + 0.55 * (Math.cos(th) + 1) / 2 : fx === "deck" && t > 0 ? Math.max(0.5, 1 - 0.07 * t) : 1
                opacity: tilted ? Math.max(0, Math.min(1, 3.2 - Math.abs(t)))
                    // (orbit: the far side dim, and gone before the strip's ends meet behind)
                    : fx === "orbit" ? (0.35 + 0.65 * (Math.cos(th) + 1) / 2) * Math.max(0, Math.min(1, (Math.PI - Math.abs(th)) * 1.5))
                    // (deck: the cards dealt away fade as they go; the pile shows four deep)
                    : fx === "deck" ? (t < 0 ? Math.max(0, 1 + t * 1.2) : Math.max(0, Math.min(1, 4.5 - t)))
                    : fx === "fan" ? Math.max(0, Math.min(1, 5.5 - Math.abs(t))) : 1
                transform: [
                    Rotation {
                        origin.x: card.width / 2; origin.y: card.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: card.tilted ? -Math.max(-1, Math.min(1, card.t)) * 55 : 0
                    },
                    Rotation {
                        origin.x: card.width / 2; origin.y: card.fanPivot
                        angle: card.fx === "fan" ? card.t * card.fanStep : 0
                    },
                    Translate {
                        x: card.tilted ? card.packed - card.side
                         : card.fx === "orbit" ? card.orbitR * Math.sin(card.th) - card.side
                         : card.fx === "deck" ? (card.t > 0 ? card.t * 26 - card.side : card.side * 0.6)
                         : card.fx === "fan" ? -card.side : 0
                        y: -card.hop * 26
                         - (card.fx === "orbit" ? (1 - Math.cos(card.th)) * 45 : 0)
                         - (card.fx === "deck" ? (card.t > 0 ? card.t * 16 : card.t * 10) : 0)
                         - (card.fx === "fan" ? 22 * Math.max(0, 1 - Math.abs(card.t)) : 0)
                    }
                ]

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
                        // (built as the switcher opens and shown with the window's first frame, so
                        // it's ready by then: built only then, it flicked in just after)
                        visible: Config.hyprBlur.enabled && sw.livePreviews && !!o && !!o.at && !!m
                        opacity: shot.hasContent ? 1 : 0
                        anchors.fill: shot
                        // The window's own place whenever it's known (a 1×1 stand-in only when it isn't)
                        win: o && o.at && o.size && m ? Qt.rect(o.at[0] - m.x, o.at[1] - m.y, o.size[0], o.size[1]) : Qt.rect(0, 0, 1, 1)
                        // (a rotated monitor, turned on its side, swaps its width and height)
                        readonly property bool turned: !!m && ((m.lastIpcObject?.transform || 0) % 2) === 1
                        screen: m ? (turned ? Qt.size(m.height / (m.scale || 1), m.width / (m.scale || 1))
                                            : Qt.size(m.width / (m.scale || 1), m.height / (m.scale || 1))) : Qt.size(1, 1)
                        pixelScale: o && o.size ? shot.width / Math.max(1, o.size[0]) : 0.25
                        radius: Config.corner(8)
                    }
                    // The window's live capture (shared with its other cards: see shotFor), copied
                    // at its own size
                    ShaderEffectSource {
                        id: shot
                        readonly property Item capture: sw.shotFor(card.modelData)
                        readonly property bool hasContent: !!capture && capture.hasContent
                        anchors.centerIn: parent
                        // (until the capture's made: 16:10, as an empty capture is)
                        width: capture ? capture.width : Math.min(parent.width, parent.height * 16 / 10)
                        height: capture ? capture.height : width * 10 / 16
                        sourceItem: capture
                        // Without live previews (or in game mode): the window's shape and app tile instead
                        // (below). A frame from before previews were turned off stays hidden, and so
                        // does the copy until its capture exists (it has nothing to show till then)
                        visible: sw.livePreviews && !!capture
                        // Rounded, and brightened back if Hyprland dims it (it isn't focused)
                        layer.enabled: true
                        layer.effect: PreviewShape {
                            radius: Config.corner(8)
                            gain: Config.undimGain(card.modelData.activated, card.modelData.lastIpcObject ? card.modelData.lastIpcObject.class : "")
                        }
                    }
                    // Without live previews (or in game mode): an outline in the window's proportions,
                    // with the app's tile in it
                    Rectangle {
                        readonly property var o: card.modelData.lastIpcObject
                        readonly property real ratio: o && o.size && o.size[1] > 0 ? o.size[0] / o.size[1] : 16 / 10
                        visible: !sw.livePreviews
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height * ratio)
                        height: width / ratio
                        radius: Config.corner(8)
                        color: Qt.rgba(0.07, 0.08, 0.1, 0.72)
                        border.width: 1.5
                        border.color: Qt.rgba(1, 1, 1, 0.35)
                    }
                    // No capture available (or game mode): show the app's tile instead
                    Image {
                        anchors.centerIn: parent
                        visible: !sw.livePreviews || !shot.hasContent
                        width: sw.tileSize; height: sw.tileSize
                        source: card.key ? "file://" + card.tilePath + "?v=" + Config.tileVersion : ""
                        sourceSize: Qt.size(192, 192)
                        smooth: true; mipmap: true
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
                        IconGloss {}                                    // glass: a sheen, as on the dock's icons
                    }
                    // The window came from a space: its badge on the preview's top left corner
                    SpaceBadge {
                        x: shot.x - 6; y: shot.y - 6
                        size: 24
                        space: Config.s.spaceSwitcherBadges ? Spaces.spaceById(Spaces.spaceOfAddress[card.modelData.address]) : null
                    }
                    // Small app tile on the preview's corner (Settings → Windows)
                    Image {
                        visible: sw.livePreviews && shot.hasContent && Config.s.switcherAppIcons
                        x: shot.x - 6; y: shot.y + shot.height - height + 6
                        width: 30; height: 30
                        source: card.key ? "file://" + card.tilePath + "?v=" + Config.tileVersion : ""
                        sourceSize: Qt.size(96, 96)
                        smooth: true; mipmap: true
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        IconPlate { anchors.fill: parent; z: -1 }       // the tile behind, in the theme's colour
                        IconGloss {}                                    // glass: a sheen, as on the dock's icons
                    }
                }
                Text {
                    id: title
                    anchors { top: previewBox.bottom; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
                    horizontalAlignment: Text.AlignHCenter
                    text: card.modelData.title || (card.entry ? card.entry.name : card.key)
                    // (dark on the selected card, which sits on the active colour)
                    color: Math.abs(card.t) < 0.5 ? Config.tint("#12151a") : sw.bar.textColor
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
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
                topLeftRadius: Config.corner(modelData === 0 ? panel.radius : 0)
                bottomLeftRadius: Config.corner(modelData === 0 ? panel.radius : 0)
                topRightRadius: Config.corner(modelData === 1 ? panel.radius : 0)
                bottomRightRadius: Config.corner(modelData === 1 ? panel.radius : 0)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: modelData === 0 ? Config.shade(0.6) : "transparent" }
                    GradientStop { position: 1.0; color: modelData === 0 ? "transparent" : Config.shade(0.6) }
                }
            }
        }
    }
}
