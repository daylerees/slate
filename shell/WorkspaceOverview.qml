// Workspace overview (Super+Down on a normal workspace): large live previews of each
// workspace in a circular strip with the selected one centred, and a row of workspace
// dots underneath. Left/Right choose, Enter goes there, Escape / Super+Up close.
//
// Driven from Hyprland (config/binds.lua):  slate ipc call overview open | close

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: ov
    required property var bar

    // ---- Look --------------------------------------------------------------
    // The width set in Settings, made smaller when the screen can't fit it: a card (the
    // screen's shape) plus the dots and title below must fit the height, and neighbours
    // should still peek in at the sides
    readonly property real cardW: Math.max(160, Math.min(Config.s.overviewCardWidth, width * 0.72,
        (height - 260) * width / Math.max(1, height)))
    readonly property real gap: 28
    readonly property real slotW: cardW + gap
    readonly property real dot: 14
    readonly property real dotGap: 6
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color selectColor: Config.tint("#262c35")

    // Current wallpaper (Slate setting)
    readonly property string wallpaper: Config.wallpaper ? "file://" + Config.wallpaper : ""

    // ---- State -------------------------------------------------------------
    property bool shown: false
    property var spaces: []           // normal workspaces, snapshot when opened
    property int index: 0             // position on the (repeated) strip
    property bool animate: false

    // What each card shows: workspace id -> window addresses. Kept by us (not looked
    // up live) so cards don't flicker while windows are being moved between workspaces.
    property var contents: ({})
    readonly property var byAddr: {
        const m = {};
        for (const t of Hyprland.toplevels.values) m[t.address] = t;
        return m;
    }
    function snapshotContents() {
        const c = {}, g = {}, all = [];
        for (const w of spaces) c[w.id] = [];
        for (const t of Hyprland.toplevels.values) {
            if (!t.workspace || c[t.workspace.id] === undefined) continue;
            c[t.workspace.id].push(t.address);
            all.push(t.address);
            const o = t.lastIpcObject;
            if (o && o.at && o.size) g[t.address] = { at: o.at, size: o.size };
        }
        contents = c;
        geo = g;
        shotAddrs = all;
    }
    // The part of a workspace's monitor that windows can use (without the space the bar and
    // other edges reserve), in Hyprland's units: window positions are in these; Slate's own
    // units differ by the interface size. Cards show just this part.
    function monitorBox(wsId) {
        const w = Hyprland.workspaces.values.find(x => x.id === wsId);
        const m = w ? w.monitor : null;
        const a = m ? areas[m.name] : null;
        if (a) return a;
        if (m && m.width > 0) {
            const mw = m.width / (m.scale || 1), mh = m.height / (m.scale || 1);
            return { x: m.x, y: m.y, w: mw, h: mh, mx: m.x, my: m.y, fw: mw, fh: mh, rl: 0, rt: 0 };
        }
        const sw = ov.width * Config.uiScale, sh = ov.height * Config.uiScale;
        return { x: 0, y: 0, w: sw, h: sh, mx: 0, my: 0, fw: sw, fh: sh, rl: 0, rt: 0 };
    }
    // Each monitor's usable area by name, from hyprctl (read at start and on each open, as
    // the bar's reserved space changes with its position and auto-hide)
    property var areas: ({})
    Process {
        id: areaProc
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = {};
                    for (const m of JSON.parse(text)) {
                        const sc = m.scale || 1;
                        let w = m.width / sc, h = m.height / sc;
                        if ((m.transform || 0) % 2) { const t = w; w = h; h = t; }
                        const r = m.reserved || [0, 0, 0, 0];      // left, top, right, bottom
                        // The usable area (x, y, w, h), and the whole screen it's part of (mx, my,
                        // fw, fh; rl, rt = the reserved space on its left and top)
                        o[m.name] = { x: m.x + r[0], y: m.y + r[1], w: w - r[0] - r[2], h: h - r[1] - r[3],
                                      mx: m.x, my: m.y, fw: w, fh: h, rl: r[0], rt: r[1] };
                    }
                    ov.areas = o;
                } catch (e) {}
            }
        }
    }
    // The cards' shape: the usable area of the screen the overview is on
    readonly property real areaAspect: {
        const a = areas[screen ? screen.name : ""];
        return a && a.w > 0 ? a.h / a.w : ov.height / Math.max(1, ov.width);
    }
    // Last known position/size of each window (Hyprland's data briefly drops out
    // while windows move between workspaces)
    property var geo: ({})
    function geoFor(addr) {
        const t = byAddr[addr], o = t ? t.lastIpcObject : null;
        return (o && o.at && o.size) ? { at: o.at, size: o.size } : geo[addr];
    }
    // One live capture per window, kept for as long as the overview is open; cards
    // show copies of these, so moving windows between cards never blanks a preview
    property var shotAddrs: []
    function shotFor(addr) {
        for (let i = 0; i < shotRepeater.count; i++) {
            const it = shotRepeater.itemAt(i);
            if (it && it.addr === addr) return it;
        }
        return null;
    }

    // Holding Shift "lifts" the selected card; arrows then swap it along the row
    property bool shiftHeld: false
    property int swapA: -1            // id of the lifted workspace while swapping
    property int swapB: -1            // id of the neighbour it's trading places with
    property int swapStep: 0
    property real swapProg: 0
    readonly property bool swapping: swapA >= 0
    // True for a moment when a swap finishes: the selection passes from the card that
    // was carried to the one now centred (same picture), so that switch must be instant
    property bool handover: false

    // Repeat the workspaces round the loop so the strip always feels endless
    readonly property int reps: spaces.length < 2 ? 1
        : Math.max(1, Math.ceil((width + 2 * slotW) / (spaces.length * slotW)))
    readonly property var strip: {
        const out = [];
        for (let r = 0; r < reps; r++) for (const w of spaces) out.push(w);
        return out;
    }
    readonly property int selected: spaces.length ? index % spaces.length : 0

    function open() {
        screen = Config.focusedScreen;     // open on the focused screen
        areaProc.running = false; areaProc.running = true;
        Config.readBlur();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        // Normal workspaces only (the secret / special workspace has a negative id)
        // Plain copies (number + name): Hyprland deletes workspace objects that go empty
        // (e.g. while windows move), which would leave cards reading "undefined"
        spaces = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
            .map(w => ({ id: w.id, name: String(w.name || w.id) }));
        if (spaces.length === 0) return;
        cardsOut = false;
        releasing = false;
        zooming = false;
        snapshotContents();
        geoRefresh.restart();          // refreshToplevels() answers later: read positions again then
        shiftHeld = false;
        animate = false;
        const cur = spaces.findIndex(w => Hyprland.focusedWorkspace && w.id === Hyprland.focusedWorkspace.id);
        index = Math.max(0, cur);
        // The strip resets to its first card when its contents load, so set the
        // position after that, then animate from there
        Qt.callLater(() => { list.currentIndex = ov.index; list.positionViewAtIndex(ov.index, PathView.Center); ov.animate = true; });
        shown = true;
    }
    function close() { shown = false; shiftHeld = false; }
    function move(step) {
        const n = strip.length;
        if (!n) return;
        // Round from the last workspace to the first, unless that's turned off (Settings →
        // Windows): then it stops at the first and last
        if (!Config.s.wrapWorkspaces && (selected + step < 0 || selected + step >= spaces.length)) return;
        if (spaces.length > 1) Config.swish(step);         // one workspace: nothing moves
        index = (index + step + n) % n;
        list.currentIndex = index;
    }
    // Shift+Left/Right: move the selected workspace along by swapping its windows
    // with the neighbouring workspace's (Hyprland workspaces are numbered, so
    // "moving" one means trading contents). On screen the lifted card stays centred
    // while the row slides under it and the neighbour slides across into its place.
    function reorder(step) {
        const n = spaces.length;
        if (n < 2 || swapping) return;
        if (!Config.s.wrapWorkspaces && (selected + step < 0 || selected + step >= n)) return;
        const a = spaces[selected], b = spaces[(selected + step + n) % n];
        swapA = a.id; swapB = b.id; swapStep = step;
        swapProg = 0;
        move(step);                       // row slides one place under the lifted card
        swapAnim.restart();               // the two cards' offsets, in step with the row
    }
    NumberAnimation {
        id: swapAnim
        target: ov; property: "swapProg"
        from: 0; to: 1
        duration: Config.ms(260)
        easing.type: Easing.InOutQuad
        onFinished: ov.finishSwap()
    }
    function finishSwap() {
        const a = swapA, b = swapB;
        // Trade what the two cards show (seamless: it matches where they ended up)
        const c = Object.assign({}, contents);
        const t = c[a]; c[a] = c[b]; c[b] = t;
        handover = true;
        contents = c;
        swapA = -1; swapB = -1; swapProg = 0;
        Qt.callLater(() => ov.handover = false);
        // Now actually move the windows in Hyprland
        const mv = (addr, ws) => {
            const ad = addr.startsWith("0x") ? addr : "0x" + addr;
            return `hl.dispatch(hl.dsp.window.move({ workspace = ${ws}, window = "address:${ad}", follow = false }))`;
        };
        const cmds = (c[b] || []).map(x => mv(x, b)).concat((c[a] || []).map(x => mv(x, a)));
        if (cmds.length) Quickshell.execDetached(["hyprctl", "dispatch", "function() " + cmds.join("; ") + " end"]);
        refreshTimer.restart();
    }
    // Hyprland answers refreshToplevels() a moment later; keep the fresh positions
    Timer {
        id: geoRefresh
        interval: 120
        onTriggered: {
            const g = Object.assign({}, ov.geo);
            for (const t of Hyprland.toplevels.values) {
                const o = t.lastIpcObject;
                if (o && o.at && o.size) g[t.address] = { at: o.at, size: o.size };
            }
            ov.geo = g;
        }
    }
    // Pick up the windows' new positions for the previews
    Timer { id: refreshTimer; interval: 200; onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); } }

    // Go to the chosen workspace once we've let go of the keyboard (Hyprland won't
    // switch while we hold it)
    property int pendingId: -1
    function choose() {
        if (!shown || releasing) return;
        const w = spaces[selected];
        if (!w) { close(); return; }
        pendingId = w.id;
        // Let go of the keyboard and switch underneath while the overview still covers the
        // screen. The chosen card then grows from its place to exactly the size and place of
        // the workspace (its wallpaper and windows landing on the real ones) while everything
        // else fades away, and once it's there the overview goes, with nothing changing on
        // screen. (Fading the cards first left a dark screen for a moment; growing the card
        // only part of the way showed two wallpapers at different sizes.)
        releasing = true;
        goTimer.restart();
    }
    // The zoom: 0 → 1, from the card (zoomFrom) to the workspace's area (zoomTo), in the
    // overview's own coordinates
    property real zoomP: 0
    property rect zoomFrom: Qt.rect(0, 0, 1, 1)
    property rect zoomTo: Qt.rect(0, 0, 1, 1)
    readonly property real zoomK: 1 + (zoomTo.width / Math.max(1, zoomFrom.width) - 1) * zoomP
    NumberAnimation {
        id: zoomAnim
        target: ov; property: "zoomP"; from: 0; to: 1
        duration: Config.ms(300); easing.type: Easing.OutCubic
        // Once it's there (and Hyprland is on that workspace), the real workspace is exactly
        // underneath: fade quickly
        onFinished: if (ov.arrived) ov.shown = false
    }
    // Hyprland has switched to the chosen workspace. Until then the backdrop stays solid,
    // so the old workspace never shows through
    property bool arrived: false
    // The backdrop thins with the zoom, but only after arriving (smoothed, in case that's
    // part-way through)
    property real backdropGone: zooming && arrived ? zoomP : 0
    Behavior on backdropGone { NumberAnimation { duration: Config.ms(90) } }
    function goNow() {
        Quickshell.execDetached(["hyprctl", "dispatch", `function() instantTo(hl.dsp.focus({ workspace = ${ov.pendingId} })) end`]);
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (!ov.zooming) return;
            const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
            if (id === ov.pendingId) {
                ov.arrived = true;
                if (!zoomAnim.running) ov.shown = false;      // the zoom's already done
            } else if (ov.arrived) {
                // Hyprland went back (giving focus back to the window from before, after we let
                // go of the keyboard): go again, while it's still covered
                ov.arrived = false;
                ov.goNow();
            }
        }
    }
    // In case the switch was lost (or undone without a change being reported): try again
    Timer {
        id: arriveCheck
        interval: 250
        onTriggered: {
            if (!ov.zooming) return;
            const id = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
            if (id === ov.pendingId) { ov.arrived = true; if (!zoomAnim.running) ov.shown = false; }
            else { ov.goNow(); restart(); }
        }
    }
    function startZoom() {
        const card = list.currentItem;
        const box = monitorBox(pendingId);
        const s = Config.uiScale || 1;
        if (!card || !card.previewItem) { shown = false; return; }
        const p = card.previewItem.mapToItem(content, 0, 0, card.previewItem.width, card.previewItem.height);
        zoomFrom = Qt.rect(p.x, p.y, p.width, p.height);
        zoomTo = Qt.rect((box.x - box.mx) / s, (box.y - box.my) / s, box.w / s, box.h / s);
        zooming = true;
        zoomAnim.restart();
    }
    property bool releasing: false
    property bool cardsOut: false
    property real cardsFade: cardsOut ? 0 : 1
    Behavior on cardsFade { NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutQuad } }
    // Leaving into a chosen workspace (zooms in as it fades), rather than closing
    property bool zooming: false
    Timer {
        id: goTimer
        interval: 40               // Hyprland won't switch while we still hold the keyboard
        onTriggered: {
            ov.arrived = Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === ov.pendingId;
            ov.goNow();
            ov.releasing = false;
            ov.startZoom();
            arriveCheck.restart();
        }
    }


    IpcHandler {
        target: "overview"
        function open(): void { ov.open(); }
        function close(): void { ov.close(); }
        function toggle(): void { if (ov.shown) ov.close(); else ov.open(); }
        function next(): void { ov.move(1); }
        function prev(): void { ov.move(-1); }
        function go(): void { ov.choose(); }
        function moveRight(): void { ov.reorder(1); }
        function moveLeft(): void { ov.reorder(-1); }
        function hold(on: bool): void { ov.shiftHeld = on; }      // same as holding Shift
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
    // After zooming into a workspace the overview matches it, so it just goes, quickly
    Behavior on fade { NumberAnimation { duration: Config.ms(ov.zooming ? 120 : 360); easing.type: Easing.InOutCubic } }
    onFadeChanged: if (fade === 0) { zooming = false; zoomP = 0; arrived = false; arriveCheck.stop(); }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0.04, 0.05, 0.06, 0.94 * fade * (1 - backdropGone))
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown && !releasing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; enabled: ov.shown; onClicked: ov.close() }

    // Live captures of every window (see shotFor); drawn off-screen, shown via copies
    Item {
        x: -10000
        Repeater {
            id: shotRepeater
            model: ov.shotAddrs
            delegate: ScreencopyView {
                required property string modelData
                readonly property string addr: modelData
                // Drawn at twice its size on a card (capped at the window's own size), then
                // scaled down smoothly by the cards: sharp on HiDPI screens and when lifted
                readonly property var g: ov.geoFor(modelData)
                readonly property var ws: ov.byAddr[modelData] ? ov.byAddr[modelData].workspace : null
                readonly property real k: Math.min(1, 2 * ov.cardW / Math.max(1, ov.monitorBox(ws ? ws.id : -1).w))
                width: g ? Math.max(1, g.size[0] * k) : 200
                height: g ? Math.max(1, g.size[1] * k) : 120
                // Kept until the overview has completely gone (not just closing): dropped as it
                // started fading, the window vanished from its card and came back as the real one
                captureSource: ov.visible && ov.byAddr[modelData] && ov.byAddr[modelData].wayland ? ov.byAddr[modelData].wayland : null
                live: ov.shown && !ov.releasing     // stop updating once chosen: less work during the fade
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: ov.fade * ov.cardsFade
        // Opening and closing: a slight grow. Leaving into a workspace: the chosen card
        // carried onto the workspace's area (scaled about the top left, then moved)
        transform: [
            Scale {
                origin.x: content.width / 2; origin.y: content.height / 2
                xScale: ov.zooming ? 1 : 0.97 + 0.03 * ov.fade
                yScale: xScale
            },
            Scale { xScale: ov.zoomK; yScale: ov.zoomK },
            Translate {
                x: ov.zooming ? ov.zoomFrom.x + (ov.zoomTo.x - ov.zoomFrom.x) * ov.zoomP - ov.zoomFrom.x * ov.zoomK : 0
                y: ov.zooming ? ov.zoomFrom.y + (ov.zoomTo.y - ov.zoomFrom.y) * ov.zoomP - ov.zoomFrom.y * ov.zoomK : 0
            }
        ]

        Item {
            focus: ov.shown
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Shift) { ov.shiftHeld = true; return; }
                switch (e.key) {
                case Qt.Key_Escape: ov.close(); break;
                case Qt.Key_Return: case Qt.Key_Enter: ov.choose(); break;
                case Qt.Key_Right: case Qt.Key_Tab:
                    if (e.modifiers & Qt.ShiftModifier) ov.reorder(1); else ov.move(1);
                    break;
                case Qt.Key_Left: case Qt.Key_Backtab:
                    if (e.modifiers & Qt.ShiftModifier) ov.reorder(-1); else ov.move(-1);
                    break;
                default: return;
                }
                e.accepted = true;
            }
            Keys.onReleased: e => { if (e.key === Qt.Key_Shift) ov.shiftHeld = false; }
        }

        // ---- Workspace previews --------------------------------------------
        PathView {
            id: list
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -30 }
            height: cardH + 60
            readonly property real cardH: ov.cardW * ov.areaAspect
            interactive: false
            model: ov.strip
            currentIndex: ov.index
            readonly property real len: Math.max(1, ov.strip.length) * ov.slotW
            path: Path {
                startX: list.width / 2 - list.len / 2; startY: list.height / 2
                PathLine { x: list.width / 2 + list.len / 2; y: list.height / 2 }
            }
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: ov.animate ? 260 : 0
            // It resets to the first card when it fills in (after the window shows), so
            // put it back on the chosen workspace then
            onCountChanged: { currentIndex = ov.index; positionViewAtIndex(ov.index, PathView.Center); }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                // While swapping, the lifted card stays the selected one
                readonly property bool isSelected: ov.swapping ? modelData.id === ov.swapA : PathView.isCurrentItem
                readonly property bool lifted: isSelected && (ov.shiftHeld || ov.swapping)
                readonly property var wins: (ov.contents[modelData.id] || []).map(a => ov.byAddr[a])
                    .filter(t => t && ov.geoFor(t.address))
                // Swap motion: lifted card keeps pace with the row, neighbour crosses over
                transform: Translate {
                    x: card.modelData.id === ov.swapA ? ov.swapStep * ov.slotW * ov.swapProg
                     : card.modelData.id === ov.swapB ? -ov.swapStep * ov.slotW * ov.swapProg : 0
                    y: card.lifted ? -26 : 0
                    Behavior on y { enabled: !ov.handover; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
                }
                z: lifted ? 10 : (modelData.id === ov.swapB ? 5 : 0)
                // Hyprland units to card units, for this workspace's monitor
                readonly property var mon: ov.monitorBox(modelData.id)
                readonly property real sx: ov.cardW / Math.max(1, mon.w)
                width: ov.cardW
                height: list.cardH + 40
                scale: lifted ? 1.04 : isSelected ? 1 : 0.86
                // Without wrapping round (Settings → Workspaces), the row ends at the first and last
                // workspace: the repeats past either end (the other end's cards) fade away
                readonly property int offset: {
                    const n = ov.strip.length;
                    let d = ((index - ov.index) % n + n) % n;
                    if (d > n / 2) d -= n;
                    return d;
                }
                readonly property bool pastEnd: !Config.s.wrapWorkspaces
                    && (ov.selected + offset < 0 || ov.selected + offset >= ov.spaces.length)
                readonly property Item previewItem: preview
                opacity: pastEnd ? 0 : isSelected ? 1 : 0.6 * (1 - ov.zoomP)
                Behavior on scale { enabled: !ov.handover; NumberAnimation { duration: Config.ms(220); easing.type: Easing.OutCubic } }
                Behavior on opacity { enabled: !ov.handover && !ov.zooming; NumberAnimation { duration: Config.ms(220) } }

                // Shadow under the lifted card
                RectangularShadow {
                    anchors.fill: preview
                    radius: 12
                    blur: 36
                    offset.y: 18
                    color: Qt.rgba(0, 0, 0, 0.7)
                    opacity: card.lifted ? 1 : 0
                    Behavior on opacity { enabled: !ov.handover; NumberAnimation { duration: Config.ms(180) } }
                }

                // Selection ring
                Rectangle {
                    anchors { fill: preview; margins: -5 }
                    radius: 17
                    color: "transparent"
                    // Blue when selected; bright white while lifted (holding Shift)
                    border.width: card.lifted ? 4 : 3
                    border.color: card.lifted ? ov.bar.textColor : ov.bar.accent
                    Behavior on border.color { enabled: !ov.handover; ColorAnimation { duration: Config.ms(150) } }
                    opacity: card.isSelected ? 1 - ov.zoomP : 0
                    Behavior on opacity { enabled: !ov.handover && !ov.zooming; NumberAnimation { duration: Config.ms(180) } }
                    Gloss { radius: parent.radius; strength: 0.7 }   // glass: a sheen over the selected card
                }

                // Miniature of the workspace: wallpaper, then each window in place
                Item {
                    id: preview
                    width: ov.cardW
                    height: list.cardH
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: previewMask }

                    // The wallpaper blurred as Hyprland blurs it behind see-through windows (its
                    // size and passes, scaled to the card). Under the sharp one, so it's drawn
                    // for the windows to show through, but never seen itself
                    MultiEffect {
                        id: wallBlur
                        visible: Config.hyprBlur.enabled
                        x: wallImg.x; y: wallImg.y; width: wallImg.width; height: wallImg.height
                        source: wallImg
                        blurEnabled: true
                        blur: 1
                        blurMax: Math.max(4, Math.min(64, Math.round(Config.hyprBlur.size * Math.pow(2, Config.hyprBlur.passes) * card.sx)))
                        contrast: Config.hyprBlur.contrast - 1
                        saturation: Config.hyprBlur.vibrancy
                    }
                    // The wallpaper as the screen shows it: across the whole screen (behind the
                    // bar too), so the card shows the part in the usable area, just like the
                    // workspace itself
                    Image {
                        id: wallImg
                        x: -(card.mon.rl || 0) * card.sx
                        y: -(card.mon.rt || 0) * card.sx
                        width: (card.mon.fw || card.mon.w) * card.sx
                        height: (card.mon.fh || card.mon.h) * card.sx
                        source: ov.wallpaper
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(width * 2, height * 2)
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        visible: ov.wallpaper === ""
                    }

                    Repeater {
                        model: card.wins
                        delegate: Item {
                            id: ovWin
                            required property var modelData
                            readonly property var g: modelData ? ov.geoFor(modelData.address) : null
                            visible: !!g          // position not known yet: leave it out rather than misplace it
                            x: g ? (g.at[0] - card.mon.x) * card.sx : 0
                            y: g ? (g.at[1] - card.mon.y) * card.sx : 0
                            width: g ? g.size[0] * card.sx : 0
                            height: g ? g.size[1] * card.sx : 0
                            // The window's own rounding, scaled to the card (but enough to see;
                            // a square window stays square)
                            readonly property real rounding: Config.windowRadius(modelData ? modelData.lastIpcObject : null,
                                card.wins.filter(t => t.lastIpcObject && !t.lastIpcObject.floating).length)
                            readonly property real radius: rounding > 0 ? Math.max(2.5, rounding * card.sx) : 0
                            // What a see-through window shows behind it on screen: the blurred
                            // wallpaper (opaque windows simply cover it)
                            ShaderEffectSource {
                                anchors.fill: parent
                                visible: Config.hyprBlur.enabled
                                sourceItem: wallBlur
                                sourceRect: Qt.rect(ovWin.x - wallImg.x, ovWin.y - wallImg.y, ovWin.width, ovWin.height)
                                layer.enabled: ovWin.radius > 0
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: ovWinMask }
                            }
                            ShaderEffectSource {
                                anchors.fill: parent
                                sourceItem: ov.shotFor(parent.modelData.address)
                                live: true
                                smooth: true
                                mipmap: true
                                layer.enabled: ovWin.radius > 0
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: ovWinMask }
                            }
                            Item {
                                id: ovWinMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: ovWin.radius }
                            }
                            // Its app's icon in the middle (Settings → Workspaces), with a soft shadow
                            // so it reads over the window
                            Item {
                                visible: Config.s.overviewAppIcons
                                opacity: 1 - ov.zoomP
                                anchors.centerIn: parent
                                width: Math.round(Math.max(16, Math.min(44, parent.width * 0.28, parent.height * 0.4))); height: width
                                layer.enabled: visible
                                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowOpacity: 0.55; shadowBlur: 0.6; shadowVerticalOffset: 1 }
                                AppTile {
                                    anchors.fill: parent
                                    readonly property var entry: parent.parent.modelData && parent.parent.modelData.wayland ? ov.lookup(parent.parent.modelData.wayland.appId) : null
                                    app: entry ? entry.id : (parent.parent.modelData && parent.parent.modelData.wayland ? parent.parent.modelData.wayland.appId : "")
                                }
                            }
                            // The window came from a space: its badge in the top left corner
                            SpaceBadge {
                                x: Math.round(size * 0.3); y: x
                                size: Math.round(Math.max(14, Math.min(24, parent.width * 0.12, parent.height * 0.2)))
                                space: Config.s.spaceSwitcherBadges ? Spaces.spaceById(Spaces.spaceOfAddress[parent.modelData.address]) : null
                            }
                        }
                    }
                }
                Item {
                    id: previewMask
                    anchors.fill: preview
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: 12 * (1 - ov.zoomP) }   // square once it's the workspace
                }

                // Label
                Text {
                    anchors { top: preview.bottom; topMargin: 14; horizontalCenter: parent.horizontalCenter }
                    opacity: 1 - ov.zoomP
                    readonly property var first: card.wins.length ? ov.lookup(card.wins[0].wayland ? card.wins[0].wayland.appId : "") : null
                    text: "Workspace " + card.modelData.name
                        + (card.wins.length === 0 ? " · empty"
                           : " · " + (first ? first.name : card.wins[0].title)
                             + (card.wins.length > 1 ? " +" + (card.wins.length - 1) : ""))
                    color: ov.bar.textColor
                    font.family: ov.bar.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                }

                ClickArea {
                    anchors.fill: preview
                    onClicked: { ov.index = card.index; list.currentIndex = card.index; ov.choose(); }
                }
            }
        }

        // ---- Workspace dots, like the bar's, with a gliding marker -----------
        Rectangle {
            id: dotsCap
            anchors { horizontalCenter: parent.horizontalCenter; top: list.bottom; topMargin: 24 }
            opacity: 1 - ov.zoomP
            width: dotsRow.width + 20
            height: 30
            radius: ov.bar.capsuleRadius
            color: ov.bar.capsuleColor


            Row {
                id: dotsRow
                anchors.centerIn: parent
                spacing: ov.dotGap
                Repeater {
                    model: ov.spaces
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool occupied: (ov.contents[modelData.id] || []).length > 0
                        width: ov.dot; height: ov.dot; radius: Config.dotRadius(ov.dot)
                        color: occupied ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                    }
                }
            }
            WorkspaceMarker {
                x: dotsRow.x; y: dotsRow.y
                width: dotsRow.width; height: dotsRow.height
                dot: ov.dot; step: ov.dot + ov.dotGap
                index: ov.selected
                animate: ov.animate
                color: ov.bar.accent
            }
        }

    }
}
