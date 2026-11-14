// Slate's own title bar (an experiment: Settings → Windows → Title bars → Slate). Instead of the
// hyprbars plugin, which has to be rebuilt for every Hyprland, a bar drawn by Slate sits on the
// floating window in front (the topmost, not just the focused one: with focus following the
// pointer, a window behind can have focus), so its bar, on the layer above windows, never
// covers another window. Bring another window forward and the bar moves to it.
// Its title and app icon, close and maximise (on the side set in Settings), double-click to
// maximise, and drag to move the window. One per screen (shell.qml); shows on the one the
// window's on.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: tb
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-titlebar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the bar takes the pointer
    mask: shown ? barRegion : noRegion
    Region { id: barRegion; item: bar }
    Region { id: noRegion }

    // ---- The window -------------------------------------------------------------------
    readonly property var monitor: Hyprland.monitorFor(tb.screen)
    readonly property var mon: monitor ? monitor.lastIpcObject : null
    // The floating window on top here: Hyprland lists windows bottom to top (raising one moves
    // it to the end), so it's the last floating one on this screen's workspace (or pinned)
    property var o: null
    property var clients: []                         // every window, as last looked at
    // Maximising or restoring: the bar keeps away while the window animates to its new place,
    // and comes back once Hyprland says where it ended up
    property bool placing: false
    // Moved or resized by something else (dragged by its own header, Super+drag, its edges):
    // Hyprland doesn't say, so it shows as the window's place or size changing between looks.
    // The bar keeps away until it's been still a moment (and looks more often meanwhile)
    property bool movingElsewhere: false
    property string lastGeo: ""
    Timer { id: stillFor; interval: 500; onTriggered: tb.movingElsewhere = false }
    onMovingElsewhereChanged: Config.titleBarAway = movingElsewhere
    property bool placedLook: false                  // the next look at the windows ends it
    Timer { id: placed; interval: Config.ms(420) + 60; onTriggered: { tb.placedLook = true; tb.query(); } }
    readonly property int wsId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    function pickTop(text) {
        let list;
        try { list = JSON.parse(text); } catch (e) { return; }
        if (!mon || dragging || sizing !== "") return;
        let top = null;
        for (const c of list) {
            if (!c.mapped || c.hidden || !c.floating || c.monitor !== mon.id) continue;
            if (!c.pinned && !(c.workspace && c.workspace.id === wsId)) continue;
            top = c;
        }
        // (the same window, changed, and not by us)
        const geo = top ? [top.address, top.at, top.size].join() : "";
        if (top && o && top.address === o.address && geo !== lastGeo && !placing && !sized && !moved) {
            movingElsewhere = true;
            stillFor.restart();
        }
        lastGeo = geo;
        o = top;
        clients = list;
        if (placedLook) { placedLook = false; placing = false; }
        if (Config.testMode) { if (top) Config.titleBarSeen = geo; Config.titleBarLooks++; }
    }
    Process {
        id: clientsQuery
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector { onStreamFinished: tb.pickTop(text) }
    }
    function query() { if (!clientsQuery.running) clientsQuery.running = true; }
    readonly property string address: o && o.address ? String(o.address) : ""
    // Where the window is (its top left, in this screen's coordinates) and its size. Mid-drag,
    // where the drag puts it.
    // Dragging: past a few pixels (so clicks and double-clicks still work), the bar steps aside,
    // the pointer jumps to the middle of the window and a small move handle takes its place
    // there; the window then follows it, centred on it. A layer can't be locked to a window,
    // so the window may be a frame behind, but round the handle in its middle that barely
    // shows (a bar on its edge drifted visibly). Let go and the bar's back
    property bool dragging: false
    property bool moved: false                       // dragged past a few pixels (not a click)
    property point handle: Qt.point(0, 0)            // the move handle, under the pointer
    // Resizing from the bar's top corners: past a few pixels the bar steps aside and the
    // pointer goes to that corner of the window, which then follows it (the opposite bottom
    // corner stays put)
    property string sizing: ""                       // "left" or "right" while a corner's held
    property bool sized: false                       // dragged past a few pixels
    readonly property real minW: 160
    readonly property real minH: 90
    property point dragAt: Qt.point(0, 0)            // where the drag has asked for the window
    // Two kinds of numbers meet in this file. Hyprland's pixels: a window's `at` and `size`,
    // the monitor's place and size (`o`, `mon`, `clients`), and everything sent to Hyprland.
    // Slate's units, which Qt draws `s` times larger (Settings → Appearance → Interface size):
    // everything drawn here and every pointer position. They're converted once, where they
    // meet: what's read from Hyprland is divided by `s` just below, and what's sent goes
    // through toHypr(). Everything between (winX…, dragAt, handle, the bar) is Slate's units
    // on this screen, so sizes are plain numbers, never multiplied by `s`: Qt does that.
    // (They can be fractions: a window 333 of Hyprland's pixels along is at 266.4 at 125%)
    readonly property real s: Config.uiScale || 1
    function toHypr(v) { return Math.round(v * s); }
    readonly property real winX: dragging ? dragAt.x : (o && o.at && mon ? (o.at[0] - mon.x) / s : 0)
    readonly property real winY: dragging ? dragAt.y : (o && o.at && mon ? (o.at[1] - mon.y) / s : 0)
    readonly property real winW: o && o.size ? o.size[0] / s : 0
    readonly property real winH: o && o.size ? o.size[1] / s : 0
    // On this screen, floating, not full screen or maximised, on the workspace showing here
    readonly property bool wanted: !!o && !!mon && o.floating === true && (o.fullscreen || 0) === 0
        && o.monitor === mon.id && (o.pinned || (!!o.workspace && o.workspace.id === wsId))
        && address !== "" && winW > 0
    // Kept away for a moment after switching workspace (the windows slide; the bar can't)
    property bool settling: false
    Timer { id: settle; interval: Config.ms(360) + 60; onTriggered: tb.settling = false }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { tb.settling = true; settle.restart(); }
    }
    readonly property bool shown: wanted && !settling
    // The bar itself: not while the window's being moved, resized or placed
    readonly property bool barWanted: shown && !moved && !sized && !placing && !movingElsewhere
    onBarWantedChanged: {
        if (barWanted) fadeIn.restart();
        else { fadeIn.stop(); bar.opacity = 0; }
    }
    onShownChanged: Config.titleBarOn = shown ? address : (Config.titleBarOn === address ? "" : Config.titleBarOn)
    onAddressChanged: if (shown) Config.titleBarOn = address
    // (the title bars go altogether when nothing floats any more: then it's on no window)
    Component.onDestruction: if (Config.titleBarOn === address) Config.titleBarOn = ""
    visible: shown || bar.opacity > 0

    // Hyprland doesn't say when a window moves, is resized or raised, so look a few times a
    // second (not while dragging: the drag knows where the window is), and at once when
    // windows open, close, change focus, float or go full screen
    Timer {
        interval: tb.movingElsewhere ? 50 : 150; repeat: true
        running: !tb.dragging && tb.sizing === ""
        onTriggered: tb.query()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "activewindowv2", "movewindowv2", "changefloatingmode",
                 "fullscreen", "workspacev2", "focusedmonv2", "pin"].includes(event.name)) tb.query();
        }
    }
    onWsIdChanged: query()
    Component.onCompleted: { Hyprland.refreshMonitors(); query(); if (barWanted) fadeIn.restart(); }

    // ---- Look -------------------------------------------------------------------------
    // The bar's height in Hyprland's pixels: the same number Hyprland is told to keep clear
    // above a floating window (SLATE_TITLEBAR_HEIGHT, shell.qml), and here in Slate's units
    readonly property int barPx: Math.round(13 * 2.6 * s)
    readonly property real barH: barPx / s
    // The window's corners: Hyprland draws its border just outside it, the outer edge's curve
    // the rounding plus the border. The bar sits on that edge and wraps round its top corners
    // (none for a window Slate's maximised: it fills the screen, with only the bar above it)
    readonly property bool flat: !!o && Config.titleBarRestore[String(o.address)] !== undefined
    // (the border's width and the rounding are Hyprland's settings, in its pixels)
    readonly property real border: flat ? 0 : Math.max(0, Math.min(12, Config.s.windowBorderSize)) / s
    readonly property real r: flat ? 0 : Config.windowRounding / s + border
    // A little see-through (Hyprland blurs what's behind it: windowrules.lua)
    readonly property color barColor: Qt.rgba(barSolid.r, barSolid.g, barSolid.b, 0.85)
    readonly property color barSolid: Config.tint("#0f1216")
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property bool buttonsLeft: Config.s.titleButtons === "left"
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    Rectangle {
        id: bar
        // On the window's top edge (border included), its top corners rounded like the window's
        x: tb.winX - tb.border; y: tb.winY - tb.border - tb.barH
        width: tb.winW + 2 * tb.border; height: tb.barH
        color: tb.barColor
        topLeftRadius: Config.corner(Math.min(tb.r, height)); topRightRadius: Config.corner(Math.min(tb.r, height))
        // Its bottom corners reach down round the window's rounded top corners, their inner
        // edge following the window's curve
        Shape {
            x: 0; y: bar.height; width: tb.r; height: tb.r
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: tb.barColor; strokeColor: "transparent"; strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: tb.r; y: 0 }
                PathArc { x: 0; y: tb.r; radiusX: tb.r; radiusY: tb.r; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
        }
        Shape {
            x: bar.width - tb.r; y: bar.height; width: tb.r; height: tb.r
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: tb.barColor; strokeColor: "transparent"; strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: tb.r; y: 0 }
                PathLine { x: tb.r; y: tb.r }
                PathArc { x: 0; y: 0; radiusX: tb.r; radiusY: tb.r; direction: PathArc.Counterclockwise }
            }
        }
        // Gone at once when it steps aside; fades in when it comes back (tb.barWanted)
        opacity: 0
        NumberAnimation { id: fadeIn; target: bar; property: "opacity"; to: 1; duration: Config.ms(160); easing.type: Easing.OutCubic }

        // Drag to move the window; double-click to maximise. (A drag area: silent)
        MouseArea {
            anchors.fill: parent
            // (positions on the screen: the bar itself moves under the pointer as the window does)
            onPressed: mouse => { const p = mapToItem(null, mouse.x, mouse.y); tb.dragPress(p.x, p.y); }
            // While moving, the handle stands in for the pointer
            cursorShape: tb.moved ? Qt.BlankCursor : Qt.ArrowCursor
            onPositionChanged: mouse => { const p = mapToItem(null, mouse.x, mouse.y); tb.dragTo(p.x, p.y); }
            onReleased: tb.dragRelease()
            onDoubleClicked: tb.maximise()
        }

        // The top corners: drag to resize the window from that corner
        Repeater {
            model: ["left", "right"]
            MouseArea {
                id: corner
                required property string modelData
                readonly property bool atLeft: modelData === "left"
                readonly property real grip: Math.max(tb.r, 18)
                x: atLeft ? 0 : bar.width - grip; y: 0
                width: grip; height: grip
                z: 2
                // (hover on: without it the resize arrow only showed while the button was held)
                hoverEnabled: true
                cursorShape: atLeft ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                HoverHandler {
                    id: cornerHover
                    cursorShape: corner.atLeft ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                }
                onPressed: mouse => { const p = mapToItem(null, mouse.x, mouse.y); tb.sizePress(modelData, p.x, p.y); }
                onPositionChanged: mouse => { const p = mapToItem(null, mouse.x, mouse.y); tb.sizeTo(p.x, p.y); }
                onReleased: tb.sizeRelease()
            }
        }

        // Title, with the app's icon
        // (sized by what's in it, so it's centred on the bar; the title's own width is capped,
        // clear of the buttons on both sides)
        Row {
            anchors.centerIn: parent
            spacing: 8
            Image {
                id: titleIcon
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: width
                readonly property var entry: tb.o ? Config.appEntry(tb.o.class || "") : null
                source: entry ? "file://" + Config.tilePath(entry.id) + "?v=" + Config.tileVersion : ""
                visible: source !== ""
                sourceSize: Qt.size(64, 64)
                smooth: true; mipmap: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, bar.width - 2 * (buttons.width + 24) - (titleIcon.visible ? titleIcon.width + 8 : 0)))
                textFormat: Text.PlainText        // never markup: the window's title is the app's to choose
                text: tb.o ? (tb.o.title || tb.o.class || "") : ""
                color: tb.textColor
                font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        // Close and maximise
        Row {
            id: buttons
            anchors.verticalCenter: parent.verticalCenter
            x: tb.buttonsLeft ? 12 : parent.width - width - 12
            spacing: 8
            layoutDirection: tb.buttonsLeft ? Qt.RightToLeft : Qt.LeftToRight
            Repeater {
                model: [{ act: "maximise", glyph: 0xEAEA }, { act: "close", glyph: 0xEB55 }]
                delegate: Rectangle {
                    id: btn
                    required property var modelData
                    width: 18; height: width; radius: Config.corner(width / 2)
                    readonly property bool danger: modelData.act === "close"
                    color: btnArea.containsMouse ? (danger ? Config.tint("#f28b8b") : Config.accent) : Config.tint("#3a424e")
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(btn.modelData.glyph)
                        // (it comes in with the colour behind it, not ahead of it)
                        opacity: btnArea.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                        color: Config.tint("#12151a")
                        font.family: tabler.name; font.pixelSize: 12
                    }
                    ClickArea {
                        id: btnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: btn.danger ? tb.close() : tb.maximise()
                    }
                }
            }
        }
    }

    // While resizing or moving, the cursor is held wherever the pointer goes: it's been moved
    // off the bar (to the window's corner or middle), where nothing of ours sets one, so it
    // went back to the arrow. Takes no clicks
    MouseArea {
        anchors.fill: parent
        z: 100
        visible: tb.sizing !== "" || tb.moved
        acceptedButtons: Qt.NoButton
        cursorShape: tb.moved ? Qt.BlankCursor : tb.sizing === "left" ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
    }

    // The move handle: a small rounded square with the move arrows, under the pointer
    Rectangle {
        id: handleBox
        readonly property real size: 44
        x: tb.handle.x - size / 2; y: tb.handle.y - size / 2
        width: size; height: size; radius: Config.corner(12)
        color: tb.barColor
        border.width: 1; border.color: Config.glass ? Config.glassEdge : Config.tint("#2a313c")
        opacity: tb.moved ? 1 : 0
        scale: tb.moved ? 1 : 0.8
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF22F)          // arrows-move
            color: tb.textColor
            font.family: tabler.name; font.pixelSize: 22
        }
    }

    // ---- Doing things -----------------------------------------------------------------
    // Dragging the bar, by where the pointer is on this screen (the bar's MouseArea; the tests
    // drive the same three through the `test` IPC target, there being no pointer to move)
    property point dragGrab: Qt.point(0, 0)
    function dragPress(px, py) {
        dragAt = Qt.point(winX, winY);
        dragGrab = Qt.point(px, py);
        moved = false;
        dragging = true;
    }
    function dragTo(px, py) {
        if (!dragging) return;
        if (!moved) {
            if (Math.abs(px - dragGrab.x) + Math.abs(py - dragGrab.y) < 4) return;   // (a click so far)
            // Start: the pointer to the middle of the window, the handle with it
            unflatten();
            moved = true;
            // (a whole pixel of Hyprland's, which is where the pointer can be put)
            const cx = toHypr(winX + winW / 2), cy = toHypr(winY + winH / 2);
            handle = Qt.point(cx / s, cy / s);
            dragAt = Qt.point(winX, winY);
            if (mon) Hyprland.dispatch(`function() hl.dispatch(hl.dsp.cursor.move({ x = ${cx + mon.x}, y = ${cy + mon.y} })) end`);
            return;
        }
        // The window's middle follows the pointer (kept clear of the screen's top, room
        // for the bar)
        handle = Qt.point(px, py);
        dragAt = Qt.point(px - winW / 2, Math.max(barH + border, py - winH / 2));
        move();          // (pointer movement comes once a frame at most: no need to hold it back)
    }
    function dragRelease() {
        if (!dragging) return;
        if (moved) move();
        dragging = false;
        moved = false;
        Hyprland.dispatch("function() slateDragEnd() end");
        query();
    }
    // Resizing from a top corner ("left" or "right"), likewise
    property point sizeGrab: Qt.point(0, 0)
    property point sizeFrom: Qt.point(0, 0)              // the window's corner, as it started
    property rect sizeGeo: Qt.rect(0, 0, 0, 0)           // the window, as it started
    function sizePress(side, px, py) {
        sizeGrab = Qt.point(px, py);
        sizeGeo = Qt.rect(winX, winY, winW, winH);
        sized = false;
        sizing = side;
    }
    function sizeTo(px, py) {
        if (sizing === "") return;
        const atLeft = sizing === "left", geo = sizeGeo;
        if (!sized) {
            if (Math.abs(px - sizeGrab.x) + Math.abs(py - sizeGrab.y) < 4) return;
            // Start: the bar steps aside, the pointer to the window's corner
            unflatten();
            sized = true;
            sizeFrom = Qt.point(atLeft ? geo.x : geo.x + geo.width, geo.y);
            if (mon) Hyprland.dispatch(`function() hl.dispatch(hl.dsp.cursor.move({ x = ${toHypr(sizeFrom.x) + mon.x}, y = ${toHypr(sizeFrom.y) + mon.y} })) end`);
            return;
        }
        const dx = px - sizeFrom.x, dy = py - sizeFrom.y;
        const w = Math.max(minW, atLeft ? geo.width - dx : geo.width + dx);
        // (kept clear of the screen's top, room for the bar)
        const top = Math.max(barH + border, geo.y + dy);
        const h = Math.max(minH, geo.y + geo.height - top);
        resize(atLeft ? geo.x + geo.width - w : geo.x, geo.y + geo.height - h, w, h);
    }
    function sizeRelease() {
        if (sizing === "") return;
        const done = sized;
        sizing = ""; sized = false;
        if (done) { Hyprland.dispatch("function() slateDragEnd() end"); query(); }
    }
    // (the tests) where the bar is drawn on this screen, in Slate's units, and what it's doing;
    // and a pretend pointer on it: "press", "move", "release" (the bar), "pressLeft",
    // "pressRight", "size", "sizeEnd" (its corners), at x, y on this screen in Slate's units
    function testState() {
        return { screen: screen ? screen.name : "", address: address, shown: shown, moved: moved, sized: sized,
                 x: bar.x, y: bar.y, w: bar.width, h: bar.height, handle: [handle.x, handle.y] };
    }
    function testPointer(what, x, y) {
        if (what === "press") dragPress(x, y);
        else if (what === "move") dragTo(x, y);
        else if (what === "release") dragRelease();
        else if (what === "pressLeft" || what === "pressRight") sizePress(what === "pressLeft" ? "left" : "right", x, y);
        else if (what === "size") sizeTo(x, y);
        else if (what === "sizeEnd") sizeRelease();
    }
    // Moving or resizing a maximised window: it's not maximised any more, so its frame's back
    function unflatten() {
        if (!flat) return;
        const r = Object.assign({}, Config.titleBarRestore);
        delete r[String(o.address)];
        Config.titleBarRestore = r;
        Hyprland.dispatch(`function() slateFlat("${address}", false) end`);
    }
    // Resizing it: its top left and size (Slate's units on this screen; sent in Hyprland's pixels)
    function resize(x, y, w, h) {
        if (!mon || address === "") return;
        Hyprland.dispatch(`function() slateDragResize("${address}", ${toHypr(x) + mon.x}, ${toHypr(y) + mon.y}, ${toHypr(w)}, ${toHypr(h)}) end`);
    }
    // Moving the window to where the drag has got (sent in Hyprland's pixels)
    function move() {
        if (!mon || address === "") return;
        const x = toHypr(dragAt.x) + mon.x, y = toHypr(dragAt.y) + mon.y;
        Hyprland.dispatch(`function() slateDragMove("${address}", ${x}, ${y}) end`);
    }
    function maximise() { if (address !== "") Config.titleBarMaximise(address); }
    // Maximise: the window fills the screen's usable part (without the reserved edges), less its
    // bar at the top, with no border, rounding or shadow: the bar's its only frame. Again, and
    // it goes back to where it was, as it was. (Hyprland's own maximise fills that part
    // entirely, with no room for the bar)
    Connections { target: Config; function onTitleBarMaximise(a) { tb.toggleMaximise(a); } }
    property var lastPlaced: ({})      // window → { max, at }: how Slate last placed it, and when
    function sameAddress(a, b) { return String(a).replace(/^0x/, "") === String(b).replace(/^0x/, ""); }
    function toggleMaximise(addr) {
        const c = clients.find(x => sameAddress(x.address, addr));
        if (!c || !mon || c.monitor !== mon.id) return;          // (another screen's bar does it)
        const sc = mon.scale || 1, turned = (mon.transform || 0) % 2 === 1;
        const W = (turned ? mon.height : mon.width) / sc, H = (turned ? mon.width : mon.height) / sc;
        const res = mon.reserved || [0, 0, 0, 0];                 // left, top, right, bottom
        // (all of this is in Hyprland's pixels, the bar's height too)
        const x = mon.x + res[0], y = mon.y + res[1] + barPx;
        const w = W - res[0] - res[2], h = H - res[1] - res[3] - barPx;
        const key = String(c.address);
        const saved = Config.titleBarRestore[key];
        const near = (a, b) => Math.abs(a - b) <= 3;
        // Whether it's maximised now. From where Hyprland last said the window is; but that's
        // looked up a few times a second, so straight after Slate itself has placed the window
        // it can still be the place before. Then it's what Slate did that counts: asked twice
        // in quick succession, the second maximised again rather than putting the window back
        const last = lastPlaced[key];
        const isMax = last && Date.now() - last.at < 2000 ? last.max
            : near(c.at[0], x) && near(c.at[1], y) && near(c.size[0], w) && near(c.size[1], h);
        const r = Object.assign({}, Config.titleBarRestore);
        let to, flatNow;
        if (isMax && saved) { to = saved; delete r[key]; flatNow = false; }
        else { if (!saved) r[key] = [c.at[0], c.at[1], c.size[0], c.size[1]]; to = [x, y, w, h]; flatNow = true; }
        Config.titleBarRestore = r;
        lastPlaced = Object.assign({}, lastPlaced, { [key]: { max: flatNow, at: Date.now() } });
        placing = true;
        placedLook = false;
        placed.restart();
        Hyprland.dispatch(`function() slatePlace("${c.address}", ${Math.round(to[0])}, ${Math.round(to[1])}, ${Math.round(to[2])}, ${Math.round(to[3])}, ${flatNow}) end`);
        query();
    }
    function close() {
        if (address === "") return;
        Hyprland.dispatch(`function() hl.dispatch(hl.dsp.window.close({ window = "address:${address}" })) end`);
    }
}
