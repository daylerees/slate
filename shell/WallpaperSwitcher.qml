// The wallpaper switcher (Super+Alt+W): a row of your wallpapers across the lower half of the
// screen, starting at the one you have. Left and Right (the wheel, or a click on another)
// look at each in turn: it fills the screen over your windows, and Slate's colours follow it
// when they come from the wallpaper. Enter (or a click on the one chosen) keeps it, as choosing
// it in Settings does; Escape, or a click away from the row, puts yours back as it was.
//
// Looking is light: only Slate's own colours change (Config.wallpaperPreview), never its
// settings, and nothing reloads. What's slow or reaches outside Slate (App theming, folder
// colours, title bar buttons, window borders, the login screen) waits until it closes, and
// then happens once, for the one kept (shell.qml: heldBack).
//
// The bar and dock stay in sight above it (they go up a layer meanwhile: Bar.qml and the dock
// in shell.qml) but take no clicks.
//
//   slate ipc call wallpaper switcher                         open (again: the next one)
//   slate ipc call wallpaperSwitcher next | prev | keep | cancel

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    required property var bar                 // the main bar: its look
    required property var wallpapers          // Wallpaper.qml: listWallpapers()

    // ---- Look --------------------------------------------------------------
    readonly property real thumbW: 200
    readonly property real thumbH: 125         // (16:10)
    readonly property real cardW: thumbW + 16
    readonly property real cardH: thumbH + 44

    // ---- State -------------------------------------------------------------
    property bool shown: false
    property var walls: []                     // the wallpapers (paths), as Settings lists them
    property int index: 0
    property string original: ""               // the wallpaper you had when it opened
    property var screenOn: null                // the focused screen, where the row shows
    property bool listing: false               // (reading the folder)
    property bool animate: false               // the row slides once it's open (it opens in place)
    readonly property string selected: index >= 0 && index < walls.length ? walls[index] : ""

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(150); easing.type: Easing.InOutQuad } }
    readonly property bool onScreen: shown || fade > 0
    Binding { target: Config; property: "wallpaperSwitching"; value: root.onScreen }

    function open() {
        if (shown) { move(1); return; }        // (its shortcut again: the next one)
        screenOn = Config.focusedScreen;
        original = Config.s.wallpaper;
        walls = original !== "" ? [original] : [];        // (until the folder's read)
        index = 0;
        animate = false;
        Config.wallpaperColourMemo = ({});
        shown = true;
        Config.rememberWallpaperColours(original);         // (to put back at once)
        listing = true;
        wallpapers.listWallpapers(list => root.listed(list));
    }
    function listed(list) {
        listing = false;
        if (!shown) return;
        const at = selected;
        // The one you have, even if it's from elsewhere (set from a file, or by an agent)
        walls = original === "" || list.includes(original) ? list : [original].concat(list);
        index = Math.max(0, walls.indexOf(at));
        settleIn.restart();
        thumbs = ({}); thumbsDone = false;
        thumbMaker.command = [Quickshell.shellPath("scripts/thumbnails.py")].concat(walls);
        thumbMaker.running = false; thumbMaker.running = true;
        // Every wallpaper's colours, nearest yours first, so the theme follows each at once
        const order = walls.map((p, i) => ({ p, d: Math.min(Math.abs(i - index), walls.length - Math.abs(i - index)) }))
            .sort((a, b) => a.d - b.d).map(x => x.p);
        colourMaker.command = [Quickshell.shellPath("scripts/wallpaper-colours.py")].concat(order);
        colourMaker.running = false; colourMaker.running = true;
    }
    // (scripts/wallpaper-colours.py: kept on disk, so after the first time they're all there at once)
    Process {
        id: colourMaker
        stdout: SplitParser {
            onRead: line => {
                if (!root.shown) return;
                try {
                    const c = JSON.parse(line);
                    if (!Config.isHex(c.accent) || !Config.isHex(c.tone) || Config.wallpaperColourMemo[c.path]) return;
                    const m = Object.assign({}, Config.wallpaperColourMemo);
                    m[c.path] = { accent: c.accent, tone: c.tone };
                    Config.wallpaperColourMemo = m;
                } catch (e) {}
            }
        }
    }
    // The cards' pictures: small ones from the shared thumbnail cache (scripts/thumbnails.py),
    // made once for any that aren't there, so a card never reads a whole wallpaper. One that
    // can't be made shows the image itself once the rest are done
    property var thumbs: ({})
    property bool thumbsDone: false
    Process {
        id: thumbMaker
        stdout: SplitParser {
            onRead: line => {
                try {
                    const t = JSON.parse(line);
                    const m = Object.assign({}, root.thumbs);
                    m[t.path] = t.thumb;
                    root.thumbs = m;
                } catch (e) {}
            }
        }
        onExited: root.thumbsDone = true
    }
    // Opens on yours, in place; moves slide after that
    Timer { id: settleIn; interval: 120; onTriggered: root.animate = true }
    function move(step) {
        if (!shown) { open(); return; }
        if (walls.length < 2) return;          // one wallpaper: nothing moves, so no swish
        index = (index + step + walls.length) % walls.length;
        Config.swish(step);
    }
    // A card clicked: the chosen one is kept; another is looked at
    function pick(i) {
        if (!shown || i < 0 || i >= walls.length) return;
        if (i === index) { keep(); return; }
        const step = i > index ? 1 : -1;
        index = i;
        Config.swish(step);
    }
    // Looking at one: on screen a moment after the selection rests (holding a key down
    // runs past the ones in between without loading each)
    onSelectedChanged: if (shown) lookSoon.restart()
    Timer {
        id: lookSoon
        interval: 60
        onTriggered: if (root.shown) Config.wallpaperPreview = root.selected === root.original ? "" : root.selected
    }
    // The wallpapers to read ahead: three each way from the one chosen, nearest first, once it's
    // on screen (cover, below)
    property int aheadOf: -1
    readonly property var ahead: {
        if (aheadOf < 0 || walls.length < 2) return [];
        const out = [];
        for (const d of [1, -1, 2, -2, 3, -3]) {
            const p = walls[(aheadOf + d + walls.length) % walls.length];
            if (p !== walls[aheadOf] && !out.includes(p)) out.push(p);
        }
        return out;
    }
    onShownChanged: if (!shown) { aheadOf = -1; colourMaker.running = false; thumbMaker.running = false; }
    // Once it's gone from the screen, everything it held is let go: the cards (and their small
    // pictures), the lists, and the colours worked out. (The cover's picture and the ones read
    // ahead are let go as it closes: their paths empty)
    onOnScreenChanged: if (!onScreen) {
        walls = []; index = 0; thumbs = ({}); thumbsDone = false;
        Config.wallpaperColourMemo = ({});
        gc();
    }
    // (the tests': what the cover on the focused screen really shows, and a look at one then
    // straight back to another the moment the first is in, quicker than any key)
    property string coverShowing: ""
    property bool standing: false           // (the small picture standing in for a full one)
    property string flipTo: ""
    property string flipFrom: ""
    function testFlip(a, b) { flipFrom = a; flipTo = b; Config.wallpaperPreview = a === original ? "" : a; }
    onCoverShowingChanged: {
        if (shown && coverShowing !== "" && coverShowing === selected) aheadOf = index
        if (flipTo !== "" && coverShowing === flipFrom) {
            const b = flipTo; flipTo = ""; flipFrom = "";
            Qt.callLater(() => Config.wallpaperPreview = b === original ? "" : b);     // (the next moment: well within the old one being let go)
        }
    }
    function keep() {
        if (!shown) return;
        lookSoon.stop();
        const path = selected;
        if (path !== "" && path !== Config.s.wallpaper) Config.s.wallpaper = path;
        Config.wallpaperPreview = "";
        Config.saveColourCache(path);
        shown = false;
    }
    function cancel() {
        if (!shown) return;
        lookSoon.stop();
        Config.wallpaperPreview = "";          // (and its colours, back at once: Config.wallpaperColourMemo)
        shown = false;
    }

    IpcHandler {
        target: "wallpaperSwitcher"
        function open(): void { root.open(); }
        function next(): void { root.move(1); }
        function prev(): void { root.move(-1); }
        function keep(): void { root.keep(); }
        function cancel(): void { root.cancel(); }
        function testFlip(a: string, b: string): void { root.testFlip(a, b); }
    }

    // A wallpaper's name: Slate's own as Settings names them ("Ember", "Ember (plain)"), yours by file
    function nameOf(path) {
        const file = path.replace(/^.*\//, "");
        if (path.indexOf(Quickshell.shellPath("wallpapers") + "/") === 0)
            return file.replace(/^slate-/, "").replace(/\.[^.]*$/, "").replace(/-plain$/, " (plain)").replace(/^./, c => c.toUpperCase());
        return file.replace(/\.[^.]*$/, "");
    }

    // ---- On every screen: the wallpaper over the windows; the row on the focused one ----
    // Two layers per screen: the wallpaper on the top layer, over the windows (the bar and dock
    // go up to the overlay meanwhile, above it), and, on the overlay, the row and what takes
    // the keys and clicks, so the row stays in sight and in reach above anything (a fullscreen
    // window draws over the top layer). The wallpaper takes no input; what's under the row's
    // layer, the bar and dock included, is a click away from the row
    Variants {
        model: Quickshell.screens
        Scope {
            id: scr
            required property var modelData
            readonly property bool main: !!root.screenOn && modelData.name === root.screenOn.name

            PanelWindow {
                id: cover
                screen: scr.modelData
                visible: root.onScreen
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "slate-wallpaper-preview"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {}
                // The wallpaper being looked at, fading in over the windows so all of it is seen
                // (they come back as it fades out). Only loaded while it's open: no second copy
                // kept otherwise
                WallpaperFill {
                    id: coverFill
                    anchors.fill: parent
                    path: root.onScreen ? Config.wallpaper : ""
                    pixelRatio: scr.modelData.devicePixelRatio || 1
                    fadeMs: 200
                    onShowingChanged: if (scr.main) root.coverShowing = showing
                    opacity: root.fade
                }
                // Until the full picture's in: its small one, filling the screen, so every move
                // answers at once and in step with the colours (a big picture takes longer to
                // read than a small one, which made moving along feel uneven). The full one fades
                // in under it, then it goes; one already read ahead never shows this at all.
                // (The cards' own small picture, at the cards' size: already in memory)
                Image {
                    id: stand
                    anchors.fill: parent
                    readonly property string small: root.thumbs[Config.wallpaper] || ""
                    source: root.onScreen && small !== "" ? "file://" + small : ""
                    sourceSize: Qt.size(root.thumbW * 2, root.thumbH * 2)
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    smooth: true
                    // Wanted while the full picture isn't in: shown at once; once it is, kept a
                    // moment longer, while the full one fades in under it, then faded away
                    readonly property bool wanted: !coverFill.ready && Config.wallpaper !== "" && status === Image.Ready
                    property real level: 0
                    onLevelChanged: if (scr.main) root.standing = level > 0
                    opacity: level * root.fade
                    onWantedChanged: {
                        if (wanted) { goAway.stop(); fadeAway.stop(); level = 1; }
                        else if (level > 0) goAway.restart();
                    }
                    Timer { id: goAway; interval: Config.ms(200); onTriggered: fadeAway.restart() }
                    NumberAnimation { id: fadeAway; target: stand; property: "level"; to: 0; duration: Config.ms(150) }
                    onSourceChanged: if (source.toString() === "") { goAway.stop(); fadeAway.stop(); level = 0; }
                }
                // The pictures either side of the one chosen, read ahead at the size the cover
                // draws them (and shared with it: WallpaperFill's images are cached), so moving
                // on shows the next at once. Nearest first, and only once the chosen one is on
                // screen, so they never hold it up; let go when the switcher closes
                Repeater {
                    model: root.shown ? root.ahead : []
                    Image {
                        required property string modelData
                        visible: false
                        asynchronous: true
                        cache: true
                        // (Slate's own are read whole, as WallpaperFill reads them)
                        readonly property bool own: modelData.indexOf(Quickshell.shellPath("wallpapers") + "/") === 0
                        sourceSize.width: own ? 0 : coverFill.width * coverFill.pixelRatio
                        sourceSize.height: own ? 0 : coverFill.height * coverFill.pixelRatio
                        source: "file://" + modelData
                    }
                }
            }

            PanelWindow {
                id: front
                screen: scr.modelData
                readonly property bool main: scr.main
                onVisibleChanged: if (visible && main) Qt.callLater(() => keys.forceActiveFocus())
                visible: root.onScreen
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "slate-wallpaper-switcher"
                WlrLayershell.layer: WlrLayer.Overlay
                // The keys go to the focused screen's, where the row is
                WlrLayershell.keyboardFocus: front.main && root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                // A click away from the row (the bar and dock included) puts yours back
                MouseArea { anchors.fill: parent; enabled: root.shown; acceptedButtons: Qt.AllButtons; onClicked: root.cancel() }

                Rectangle {
                    id: panel
                    visible: front.main
                    width: Math.min(front.width - 80, Math.max(1, root.walls.length) * root.cardW + 24)
                    height: root.cardH + 24 + hint.height + 8
                    x: (front.width - width) / 2
                    // In the lower half, clear of the dock
                    y: Math.max(front.height / 2, Math.min(front.height * 0.72 - height / 2, front.height - height - 110))
                    radius: Config.corner(18)
                    color: root.bar.barColor
                    opacity: root.fade
                    scale: 0.97 + 0.03 * root.fade
                    // Glass: a thin light rim, and the wallpaper blurred behind, as Hyprland blurs it
                    border.width: Config.glassShine ? 1 : 0
                    border.color: Config.glassEdge
                    Shadow {}
                    WallBlur {
                        z: -1
                        visible: Config.glass && Config.hyprBlur.enabled && Config.wallpaper !== ""
                        anchors.fill: parent
                        win: Qt.rect(panel.x, panel.y, panel.width, panel.height)
                        screen: Qt.size(front.width, front.height)
                        pixelScale: 1
                        radius: panel.radius
                    }
                    MouseArea { anchors.fill: parent }        // (a click on the panel itself does nothing)
                    WheelHandler {
                        property real gathered: 0
                        onWheel: e => {
                            gathered += e.angleDelta.y !== 0 ? e.angleDelta.y : e.angleDelta.x;
                            while (gathered <= -120) { gathered += 120; root.move(1); }
                            while (gathered >= 120) { gathered -= 120; root.move(-1); }
                        }
                    }

                    // Keyboard
                    Item {
                        id: keys
                        focus: front.main && root.shown
                        Keys.onPressed: e => {
                            switch (e.key) {
                            case Qt.Key_Escape: root.cancel(); break;
                            case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: root.keep(); break;
                            case Qt.Key_Right: case Qt.Key_Down: case Qt.Key_Tab: root.move(1); break;
                            case Qt.Key_Left: case Qt.Key_Up: case Qt.Key_Backtab: root.move(-1); break;
                            default: return;
                            }
                            e.accepted = true;
                        }
                    }

                    ListView {
                        id: list
                        x: 12; y: 12
                        width: parent.width - 24
                        height: root.cardH
                        orientation: ListView.Horizontal
                        interactive: false
                        clip: true
                        model: root.walls
                        cacheBuffer: root.cardW * 2
                        // The chosen one kept towards the middle as the row scrolls (at the ends,
                        // the row rests against the edge instead of leaving a gap)
                        preferredHighlightBegin: (width - root.cardW) / 2
                        preferredHighlightEnd: (width + root.cardW) / 2
                        highlightRangeMode: ListView.ApplyRange
                        highlightMoveDuration: root.animate ? Config.ms(220) : 0
                        highlightMoveVelocity: -1
                        highlightResizeDuration: 0
                        // The chosen one: the active colour, with a sheen in glass, as the window switcher's
                        highlight: Rectangle {
                            radius: Config.corner(12)
                            color: Config.accent
                            Gloss { radius: parent.radius }
                        }
                        // (set from here rather than bound: the list puts its own back as its model changes)
                        function sync() { if (count > 0 && currentIndex !== root.index) currentIndex = Math.max(0, Math.min(count - 1, root.index)); }
                        Connections { target: root; function onIndexChanged() { list.sync(); } function onWallsChanged() { list.sync(); } }
                        onCountChanged: sync()
                        onWidthChanged: sync()

                        delegate: Item {
                            id: card
                            required property string modelData
                            required property int index
                            readonly property bool chosen: index === root.index
                            width: root.cardW
                            height: root.cardH
                            // Under the pointer (not the chosen one): the muted hover
                            Rectangle {
                                anchors.fill: parent
                                radius: Config.corner(12)
                                color: !card.chosen && cardClick.containsMouse ? Config.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            }
                            // The picture: small, made once from the file (never the full image)
                            Rectangle {
                                id: frame
                                anchors { top: parent.top; topMargin: 8; horizontalCenter: parent.horizontalCenter }
                                width: root.thumbW; height: root.thumbH
                                radius: Config.corner(8)
                                color: Config.tint("#1d222a")
                                Image {
                                    anchors.fill: parent
                                    source: root.thumbs[card.modelData] ? "file://" + root.thumbs[card.modelData]
                                        : root.thumbsDone ? "file://" + card.modelData : ""
                                    sourceSize: Qt.size(root.thumbW * 2, root.thumbH * 2)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Config.ms(160) } }
                                    layer.enabled: true
                                    layer.effect: PreviewShape { radius: Config.corner(8) }
                                }
                            }
                            Text {
                                anchors { top: frame.bottom; topMargin: 8; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                                horizontalAlignment: Text.AlignHCenter
                                text: root.nameOf(card.modelData)
                                // (dark on the chosen one, which sits on the active colour)
                                color: card.chosen ? Config.tint("#12151a") : root.bar.textColor
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                font.family: root.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                                elide: Text.ElideMiddle
                            }
                            ClickArea {
                                id: cardClick
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.pick(card.index)
                            }
                        }
                    }
                    // Soft shades at the ends while there are more past them
                    Repeater {
                        model: [0, 1]
                        Rectangle {
                            required property int modelData
                            // (left: once scrolled along; right: while there are more beyond)
                            opacity: (modelData === 0 ? !list.atXBeginning : !list.atXEnd) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Config.ms(160) } }
                            width: 56
                            height: parent.height
                            x: modelData === 0 ? 0 : parent.width - width
                            topLeftRadius: modelData === 0 ? panel.radius : 0
                            bottomLeftRadius: modelData === 0 ? panel.radius : 0
                            topRightRadius: modelData === 1 ? panel.radius : 0
                            bottomRightRadius: modelData === 1 ? panel.radius : 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: modelData === 0 ? Config.shade(0.6) : "transparent" }
                                GradientStop { position: 1.0; color: modelData === 0 ? "transparent" : Config.shade(0.6) }
                            }
                        }
                    }
                    // Nothing to choose from
                    Text {
                        visible: !root.listing && root.walls.length === 0
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 12; leftMargin: 20; rightMargin: 20 }
                        height: root.cardH
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "No wallpapers here yet. Pictures in your wallpaper folder (Settings → Wallpaper) will show up here"
                        color: Config.tint("#8b94a3")
                        font.family: root.bar.fontFamily; font.pixelSize: 13
                    }
                    // What the keys do
                    Text {
                        id: hint
                        opacity: root.walls.length > 0 ? 1 : 0
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                        width: parent.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: "Enter keeps it · Esc puts yours back"
                        color: Config.tint("#8b94a3")
                        font.family: root.bar.fontFamily; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
