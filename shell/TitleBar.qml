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
    readonly property real minW: Math.round(160 * s)
    readonly property real minH: Math.round(90 * s)
    property point dragAt: Qt.point(0, 0)            // where the drag has asked for the window
    readonly property real winX: dragging ? dragAt.x : (o && o.at && mon ? o.at[0] - mon.x : 0)
    readonly property real winY: dragging ? dragAt.y : (o && o.at && mon ? o.at[1] - mon.y : 0)
    readonly property real winW: o && o.size ? o.size[0] : 0
    readonly property real winH: o && o.size ? o.size[1] : 0
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
    readonly property real s: Config.uiScale || 1
    readonly property real barH: Math.round(13 * 2.6 * s)
    // The window's corners: Hyprland draws its border just outside it, the outer edge's curve
    // the rounding plus the border. The bar sits on that edge and wraps round its top corners
    // (none for a window Slate's maximised: it fills the screen, with only the bar above it)
    readonly property bool flat: !!o && Config.titleBarRestore[String(o.address)] !== undefined
    readonly property real border: flat ? 0 : Math.max(0, Math.min(12, Config.s.windowBorderSize))
    readonly property real r: flat ? 0 : Config.windowRounding + border
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
            property point grab: Qt.point(0, 0)
            property point start: Qt.point(0, 0)
            // (positions on the screen: the bar itself moves under the pointer as the window does)
            onPressed: mouse => {
                tb.dragAt = Qt.point(tb.winX, tb.winY);
                const p = mapToItem(null, mouse.x, mouse.y);
                grab = Qt.point(p.x, p.y);
                start = tb.dragAt;
                tb.moved = false;
                tb.dragging = true;
            }
            // While moving, the handle stands in for the pointer
            cursorShape: tb.moved ? Qt.BlankCursor : Qt.ArrowCursor
            onPositionChanged: mouse => {
                if (!tb.dragging) return;
                const p = mapToItem(null, mouse.x, mouse.y), px = p.x, py = p.y;
                if (!tb.moved) {
                    if (Math.abs(px - grab.x) + Math.abs(py - grab.y) < 4) return;   // (a click so far)
                    // Start: the pointer to the middle of the window, the handle with it
                    tb.unflatten();
                    tb.moved = true;
                    const cx = Math.round(tb.winX + tb.winW / 2), cy = Math.round(tb.winY + tb.winH / 2);
                    tb.handle = Qt.point(cx, cy);
                    tb.dragAt = Qt.point(tb.winX, tb.winY);
                    if (tb.mon) Hyprland.dispatch(`function() hl.dispatch(hl.dsp.cursor.move({ x = ${cx + tb.mon.x}, y = ${cy + tb.mon.y} })) end`);
                    return;
                }
                // The window's middle follows the pointer (kept clear of the screen's top, room
                // for the bar)
                tb.handle = Qt.point(px, py);
                tb.dragAt = Qt.point(px - tb.winW / 2, Math.max(tb.barH + tb.border, py - tb.winH / 2));
                tb.move();          // (pointer movement comes once a frame at most: no need to hold it back)
            }
            onReleased: {
                if (!tb.dragging) return;
                if (tb.moved) tb.move();
                tb.dragging = false;
                tb.moved = false;
                Hyprland.dispatch("function() slateDragEnd() end");
                tb.query();
            }
            onDoubleClicked: tb.maximise()
        }

        // The top corners: drag to resize the window from that corner
        Repeater {
            model: ["left", "right"]
            MouseArea {
                id: corner
                required property string modelData
                readonly property bool atLeft: modelData === "left"
                readonly property real grip: Math.max(tb.r, Math.round(18 * tb.s))
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
                property point grab: Qt.point(0, 0)
                property point from: Qt.point(0, 0)              // the window's corner, as it started
                property rect geo: Qt.rect(0, 0, 0, 0)           // the window, as it started
                onPressed: mouse => {
                    const p = mapToItem(null, mouse.x, mouse.y);
                    grab = Qt.point(p.x, p.y);
                    geo = Qt.rect(tb.winX, tb.winY, tb.winW, tb.winH);
                    tb.sized = false;
                    tb.sizing = modelData;
                }
                onPositionChanged: mouse => {
                    if (tb.sizing === "") return;
                    const p = mapToItem(null, mouse.x, mouse.y);
                    if (!tb.sized) {
                        if (Math.abs(p.x - grab.x) + Math.abs(p.y - grab.y) < 4) return;
                        // Start: the bar steps aside, the pointer to the window's corner
                        tb.unflatten();
                        tb.sized = true;
                        from = Qt.point(atLeft ? geo.x : geo.x + geo.width, geo.y);
                        if (tb.mon) Hyprland.dispatch(`function() hl.dispatch(hl.dsp.cursor.move({ x = ${Math.round(from.x + tb.mon.x)}, y = ${Math.round(from.y + tb.mon.y)} })) end`);
                        return;
                    }
                    const dx = p.x - from.x, dy = p.y - from.y;
                    const w = Math.max(tb.minW, atLeft ? geo.width - dx : geo.width + dx);
                    // (kept clear of the screen's top, room for the bar)
                    const top = Math.max(tb.barH + tb.border, geo.y + dy);
                    const h = Math.max(tb.minH, geo.y + geo.height - top);
                    tb.resize(atLeft ? geo.x + geo.width - w : geo.x, geo.y + geo.height - h, w, h);
                }
                onReleased: {
                    if (tb.sizing === "") return;
                    const done = tb.sized;
                    tb.sizing = ""; tb.sized = false;
                    if (done) { Hyprland.dispatch("function() slateDragEnd() end"); tb.query(); }
                }
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
                width: Math.round(16 * tb.s); height: width
                readonly property var entry: tb.o ? Config.appEntry(tb.o.class || "") : null
                source: entry ? "file://" + Config.tilePath(entry.id) + "?v=" + Config.tileVersion : ""
                visible: source !== ""
                sourceSize: Qt.size(64, 64)
                smooth: true; mipmap: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, bar.width - 2 * (buttons.width + 24) - (titleIcon.visible ? titleIcon.width + 8 : 0)))
                text: tb.o ? (tb.o.title || tb.o.class || "") : ""
                color: tb.textColor
                font.family: Config.s.fontFamily; font.pixelSize: Math.round(13 * tb.s); font.weight: Font.Medium
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
                    width: Math.round(18 * tb.s); height: width; radius: Config.corner(width / 2)
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
                        font.family: tabler.name; font.pixelSize: Math.round(12 * tb.s)
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
        readonly property real size: Math.round(44 * tb.s)
        x: tb.handle.x - size / 2; y: tb.handle.y - size / 2
        width: size; height: size; radius: Config.corner(Math.round(12 * tb.s))
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
            font.family: tabler.name; font.pixelSize: Math.round(22 * tb.s)
        }
    }

    // ---- Doing things -----------------------------------------------------------------
    // Moving or resizing a maximised window: it's not maximised any more, so its frame's back
    function unflatten() {
        if (!flat) return;
        const r = Object.assign({}, Config.titleBarRestore);
        delete r[String(o.address)];
        Config.titleBarRestore = r;
        Hyprland.dispatch(`function() slateFlat("${address}", false) end`);
    }
    // Resizing it: its top left and size (this screen's coordinates)
    function resize(x, y, w, h) {
        if (!mon || address === "") return;
        Hyprland.dispatch(`function() slateDragResize("${address}", ${Math.round(x + mon.x)}, ${Math.round(y + mon.y)}, ${Math.round(w)}, ${Math.round(h)}) end`);
    }
    // Moving the window to where the drag has got (Hyprland coordinates)
    function move() {
        if (!mon || address === "") return;
        const x = Math.round(dragAt.x + mon.x), y = Math.round(dragAt.y + mon.y);
        Hyprland.dispatch(`function() slateDragMove("${address}", ${x}, ${y}) end`);
    }
    function maximise() { if (address !== "") Config.titleBarMaximise(address); }
    // Maximise: the window fills the screen's usable part (without the reserved edges), less its
    // bar at the top, with no border, rounding or shadow: the bar's its only frame. Again, and
    // it goes back to where it was, as it was. (Hyprland's own maximise fills that part
    // entirely, with no room for the bar)
    Connections { target: Config; function onTitleBarMaximise(a) { tb.toggleMaximise(a); } }
    function sameAddress(a, b) { return String(a).replace(/^0x/, "") === String(b).replace(/^0x/, ""); }
    function toggleMaximise(addr) {
        const c = clients.find(x => sameAddress(x.address, addr));
        if (!c || !mon || c.monitor !== mon.id) return;          // (another screen's bar does it)
        const sc = mon.scale || 1, turned = (mon.transform || 0) % 2 === 1;
        const W = (turned ? mon.height : mon.width) / sc, H = (turned ? mon.width : mon.height) / sc;
        const res = mon.reserved || [0, 0, 0, 0];                 // left, top, right, bottom
        const x = mon.x + res[0], y = mon.y + res[1] + barH;
        const w = W - res[0] - res[2], h = H - res[1] - res[3] - barH;
        const key = String(c.address);
        const saved = Config.titleBarRestore[key];
        const near = (a, b) => Math.abs(a - b) <= 3;
        const isMax = near(c.at[0], x) && near(c.at[1], y) && near(c.size[0], w) && near(c.size[1], h);
        const r = Object.assign({}, Config.titleBarRestore);
        let to, flatNow;
        if (isMax && saved) { to = saved; delete r[key]; flatNow = false; }
        else { if (!saved) r[key] = [c.at[0], c.at[1], c.size[0], c.size[1]]; to = [x, y, w, h]; flatNow = true; }
        Config.titleBarRestore = r;
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
