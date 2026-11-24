// Drop-down panels attached to the bar (on whichever edge it's on): the control center, Spaces,
// notifications, clipboard, screenshot, volume, Wi-Fi, keyboard layout, Bluetooth, game mode,
// battery & power, calendar, session, the window mode, More, and the drink and focus timers.
// Each is a file in panels/ (WifiPanel.qml…); it opens beside the button that was clicked,
// joins the bar with curved corners, and slides out of it.
//
// Open from the bar with bar.openPopout("<name>", item). Close by clicking outside,
// pressing Escape, or clicking the same button again.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "panels"

PanelWindow {
    id: pop
    required property var bar
    // The shared pieces in panels/ read their colours from here (PanelHost.qml)
    Component.onCompleted: PanelHost.pop = pop
    property var notifs: null
    // (the test hook: press a control centre switch by its id, as a click on it does; the
    // panel has to be open)
    signal pressSwitchAsked(string id)
    // (the test hook: Spaces → New Space, as clicking it does; the Spaces panel has to be open)
    signal newSpaceAsked()
    // (the test hooks for the panels' lists. rowsMade: how many rows each list has made, by
    // name, so a test can tell a row that was kept from one made again. pretendNets: networks
    // for the Wi-Fi panel to list where there's no Wi-Fi, and askForPassword opens one's
    // password field, as a click on it does. listState: the open panel's password field
    // and how far its list has scrolled)
    property var rowsMade: ({})
    function rowMade(list) { if (Config.testMode) rowsMade[list] = (rowsMade[list] || 0) + 1; }
    property var pretendNets: null
    signal askForPassword(string name)
    Component {
        id: pretendNet
        QtObject {
            property string name
            property real signalStrength
            property bool connected: false
            property bool known: false
            property bool stateChanging: false
            property int security: -1
            function connect() {}
            function connectWithPsk(psk) {}
        }
    }
    // names and signals (0 … 1) as JSON, {"Home": 0.9, …}: made the first time, then each
    // network's signal changed as it would be by a scan ("": back to none)
    function pretendWifi(json) {
        if (json === "") { pretendNets = null; return; }
        const want = JSON.parse(json), nets = (pretendNets || []).slice();
        let added = pretendNets === null;
        for (const name in want) {
            const old = nets.find(n => n.name === name);
            if (old) old.signalStrength = want[name];
            else { nets.push(pretendNet.createObject(pop, { name: name, signalStrength: want[name] })); added = true; }
        }
        if (added) pretendNets = nets;
    }
    function scrollList(y) { const list = content.item ? content.item.testList : null; if (list) list.contentY = list.originY + y; }
    function listState() {
        const panel = content.item, list = panel && panel.testList ? panel.testList : null;
        const f = panel && panel.testField ? panel.testField() : null;
        return { rows: rowsMade, typing: !!f && f.focus, typed: f ? f.text : "", cursor: f ? f.cursorPosition : -1,
                 order: panel && panel.testOrder ? panel.testOrder() : [],
                 avatarFallback: panel && panel.testAvatarFallback !== undefined ? panel.testAvatarFallback : null,
                 scroll: list ? Math.round(list.contentY - list.originY) : 0, count: list ? list.count : 0,
                 // rows still fading in (or out): none once everything has settled
                 fading: list ? Array.from(list.contentItem.children).filter(c => c.visible && c.opacity < 1).length : 0 };
    }
    property var powerConfirm: null      // centred "Shut down?" dialog (PowerConfirm.qml)
    property var dock: null              // the dock's window (shell.qml), left usable while a panel's open

    // ---- State -------------------------------------------------------------
    property string current: ""          // panel being shown ("" = closed)
    property string displayed: ""        // panel drawn (kept while fading out)
    property real anchorX: 0             // centre of the button that opened it
    property real anchorY: 0
    readonly property bool shown: current !== ""

    // Opening from closed, a panel is made and drawn for two frames out of sight (slid away,
    // cut off by its edge) before it slides in, so everything in it (rounded pictures,
    // shadows, effects) is prepared first. Made as the slide started, the first frames were
    // late: the slide showed, held, then went
    property string pending: ""
    property int pendingFrames: 0
    // scr: the screen of the bar that opened it (the panel moves there)
    // edge: "start" / "end" when the button that opens it is the first / last thing on the bar
    // (the panel sits flush against that end of the screen), "" when it's anywhere else. Left
    // out (opened by name, with no button to go by): as these two always were
    property string edge: ""
    function toggle(name, x, y, scr, at) {
        const target = scr || Config.focusedScreen;
        if (target && screen !== target) { current = ""; pending = ""; revealed = false; screen = target; }
        else if (current === name) { close(); return; }
        edge = at !== undefined ? at : name === "control" ? "start" : name === "session" ? "end" : "";
        anchorX = x;
        anchorY = y === undefined ? 0 : y;
        displayed = name;
        if (current !== "") { current = name; return; }      // one already open: switch at once
        pending = name;
        pendingFrames = 0;
        openFallback.restart();
    }
    // Then it's moved out of sight, and slides in only once that frame is drawn (started
    // straight away, the slide had already run part-way when it first appeared)
    property bool revealed: false
    property bool revealWaiting: false
    // The panel's first (or last) control the keyboard can stop on, given the keyboard: for a
    // panel opened from the bar by keyboard (Bar.qml: popouts.fromKeys), as it opens
    property bool fromKeys: false
    // (the tests: the words on the control that has the keyboard in the panel, "" for none)
    readonly property string keyFocusText: { if (!Config.testMode) return ""; const f = panelKeys.Window.activeFocusItem; return f && f !== panelKeys && f !== content ? keyStops().indexOf(f) + ":" + (Config.textOf(f) || "?") : ""; }
    property var keyFocusPath: []
    // (the window given the keyboard, opened from the keyboard, nothing chosen yet: the first)
    readonly property bool windowActive: contentItem.Window.active
    onWindowActiveChanged: if (windowActive && fromKeys && current !== "" && keyStops().indexOf(panelKeys.Window.activeFocusItem) < 0) focusFirst(true)
    onKeyFocusTextChanged: keyFocusPath = keyFocusPath.concat([keyFocusText]).slice(-12)
    // The panel's controls the keyboard stops on, in the order they're laid out
    function keyStops() {
        const stops = [];
        const walk = it => {
            for (const c of it.children) {
                if (!c.visible || !c.enabled) continue;
                if (c.activeFocusOnTab) stops.push(c);
                walk(c);
            }
        };
        if (content.item) walk(content.item);
        // (in the order they're seen, top to bottom, then left to right: the order they were
        // made isn't it, a list's rows above all, which are made and reused out of order)
        const at = c => c.mapToItem(content, 0, 0);
        const places = stops.map(c => ({ c: c, p: at(c) }));
        places.sort((a, b) => Math.abs(a.p.y - b.p.y) > 4 ? a.p.y - b.p.y : a.p.x - b.p.x);
        return places.map(o => o.c);
    }
    // (the tests: everything in the open panel that takes a click but can't take the keyboard,
    // a line each saying what it is and where. A click is a tap handler (ClickTap) or a mouse
    // area (ClickArea), found anywhere in the panel; it can be reached when it, or something
    // it's inside, is a stop for Tab and the arrow keys. Right-click-only ones are what a
    // row's own menu key does, so they're left to the row they're in)
    function unreachable() {
        const out = [];
        const kind = o => {
            const s = String(o);
            return /^(ClickTap|QQuickTapHandler)/.test(s) ? "click" : /^(ClickArea|QQuickMouseArea)/.test(s) ? "area" : "";
        };
        const reached = it => {
            for (let a = it; a && a !== content; a = a.parent)
                if (a.activeFocusOnTab) return true;
            return false;
        };
        const walk = it => {
            for (const o of it.data || []) {
                const k = kind(o);
                if (k === "" || !o.enabled) continue;
                if (k === "click" && o.acceptedButtons === Qt.RightButton) continue;
                const owner = o.parent;
                if (owner && !reached(k === "area" ? o : owner)) {
                    const p = owner.mapToItem(content, 0, 0);
                    out.push((Config.textOf(owner) || String(owner).split("(")[0]) + " @" + Math.round(p.x) + "," + Math.round(p.y));
                }
            }
            for (const c of it.children) if (c.visible) walk(c);
        };
        if (content.item) walk(content.item);
        return out;
    }
    function keyStep(on) {
        const stops = keyStops(), i = stops.indexOf(panelKeys.Window.activeFocusItem);
        if (i < 0) { focusFirst(on); return; }
        const next = stops[Math.max(0, Math.min(stops.length - 1, i + (on ? 1 : -1)))];
        if (next) { next.forceActiveFocus(on ? Qt.TabFocusReason : Qt.BacktabFocusReason); intoView(next); }
    }
    function focusFirst(first) {
        const stops = keyStops();
        const pick = first ? stops[0] : stops[stops.length - 1];
        if (!pick) return false;
        pick.forceActiveFocus(first ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        intoView(pick);
        return true;
    }
    // A control the keyboard has moved to, scrolled into sight in every list it's in (a long
    // Wi-Fi list, the spaces, the notifications), with a little room above or below it
    function intoView(item) {
        for (let f = item.parent; f && f !== content; f = f.parent) {
            if (f.contentY === undefined || f.contentHeight === undefined || !(f.contentHeight > f.height)) continue;
            const top = item.mapToItem(f.contentItem, 0, 0).y, bottom = top + item.height, room = 8;
            const lo = f.originY, hi = f.originY + f.contentHeight - f.height;
            if (top - room < f.contentY) f.contentY = Math.max(lo, top - room);
            else if (bottom + room > f.contentY + f.height) f.contentY = Math.min(hi, bottom + room - f.height);
        }
    }
    function startOpening() {
        if (pending === "") return;
        const name = pending;
        pending = "";
        current = name;
        revealWaiting = true;
        revealFallback.restart();
    }
    function reveal() {
        if (!revealWaiting) return;
        revealWaiting = false;
        if (current !== "") revealed = true;
        if (current !== "" && fromKeys && keyStops().indexOf(panelKeys.Window.activeFocusItem) < 0) Qt.callLater(() => focusFirst(true));
    }
    function close() { current = ""; pending = ""; revealed = false; revealWaiting = false; }
    // Going to another workspace (a shortcut, the wheel, a dot on the bar) closes it, as opening
    // the launcher, a switcher or Nova does (shell.qml)
    Connections {
        target: Config
        function onFocusedWorkspaceIdChanged() { if (pop.engaged) pop.close(); }
    }
    // Name a workspace (the pencil on the window mode panel): the panel closes and Slate's
    // confirmation window asks, with a field for the name
    function renameWorkspace(ws) {
        if (!(ws > 0) || !powerConfirm) return;
        const name = Config.workspaceName(ws);
        close();
        powerConfirm.confirmWith({
            title: name !== "" ? "Rename \u201c" + name + "\u201d" : "Name this workspace",
            body: "Pick a short name for workspace " + ws + ". It stays for as long as the workspace is around, and "
                + "is saved with a Space. Leave it empty to go back to the number.",
            button: "Rename", code: 0xEA98, danger: false,
            input: { text: name, placeholder: Config.workspaceNumber(ws), maxLength: Config.workspaceNameLimit }
        }, (option, typed) => Config.setWorkspaceName(ws, typed));
    }
    // Its first frame is drawn (still slid away): now slide it in
    Connections {
        target: panelArea.Window.window
        function onFrameSwapped() {
            if (pop.pending !== "") { if (++pop.pendingFrames >= 2) Qt.callLater(pop.startOpening); }
            else if (pop.revealWaiting) Qt.callLater(pop.reveal);
        }
    }
    Timer { id: openFallback; interval: 200; onTriggered: pop.startOpening() }
    Timer { id: revealFallback; interval: 120; onTriggered: pop.reveal() }

    // e.g.  slate ipc call popout toggle volume 1250
    IpcHandler {
        target: "popout"
        function toggle(name: string, x: real): void { pop.toggle(name, x, 0); }
        function close(): void { pop.close(); }
    }

    // The control centre's profile card shows the wallpaper behind it. Loaded here, ahead of
    // time and at the same size, so it's already in the image cache when the card is made and
    // is there as the panel opens (otherwise it loaded, and faded in, after the first opening)
    readonly property string profileWallpaper: Config.wallpaper ? "file://" + Config.wallpaper : ""
    readonly property int profileWallpaperWidth: 940
    Image {
        visible: false
        source: pop.profileWallpaper
        sourceSize.width: pop.profileWallpaperWidth
        asynchronous: true
    }

    property real fade: revealed ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }

    // ---- Window ------------------------------------------------------------
    // Opening, open or closing (when closed it's empty: no panel, no clicks, no keyboard)
    readonly property bool active: fade > 0 || pending !== "" || revealWaiting
    // The window itself stays on screen, empty, between panels: a window made as a panel
    // opened drew its first several frames slowly (its screen buffers being set up), which
    // held up the slide. (And made again once a screen comes back after there was none: it
    // places itself, so it's given the main display to go back to: ScreenKeeper.qml)
    visible: popKeeper.ready
    ScreenKeeper { id: popKeeper; window: pop; home: () => Config.primaryScreen }
    anchors { top: true; bottom: true; left: true; right: true }
    // Panels come out of the bar: down from a top bar, up from a bottom one, sideways from a
    // side bar, next to the button that opened them
    readonly property string side: Config.barEdge
    readonly property bool sideways: side === "left" || side === "right"
    readonly property bool fromBottom: side === "bottom"
    margins.top: side === "top" ? bar.barHeight : 0
    margins.bottom: side === "bottom" ? bar.barHeight : 0
    margins.left: side === "left" ? bar.barHeight : 0
    margins.right: side === "right" ? bar.barHeight : 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-popout"
    // Above the bar's layer, not beside it: under it, the bar's glass blur picked up the top of
    // an open panel and smeared it up into the bar
    WlrLayershell.layer: WlrLayer.Overlay
    // Takes the keyboard and the clicks from the start of opening, while it's still being
    // prepared: Hyprland's side of that took a frame or two, and done as the slide began it
    // held the slide up
    readonly property bool engaged: shown || pending !== ""
    WlrLayershell.keyboardFocus: engaged ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // While closing, let clicks through so the desktop is usable straight away
    // (less the dock, which stays in use: pressing on it closes the panel, from the dock's side)
    mask: Region {
        item: pop.engaged ? catcher : pop.active ? panelArea : null
        Region { item: dockHole; intersection: Intersection.Subtract }
    }

    Item { id: catcher; anchors.fill: parent }
    // Where the dock takes the pointer, in this window (both windows reach the screen's edges,
    // this one less the bar)
    Item {
        id: dockHole
        readonly property var d: pop.dock
        readonly property bool here: !!d && d.visible && d.screen === pop.screen
        readonly property real screenW: pop.width + pop.margins.left + pop.margins.right
        readonly property real screenH: pop.height + pop.margins.top + pop.margins.bottom
        x: !here ? 0 : (d.edge === "right" ? screenW - d.width : 0) + d.inputRect.x - pop.margins.left
        y: !here ? 0 : (d.edge === "bottom" ? screenH - d.height : 0) + d.inputRect.y - pop.margins.top
        width: here ? d.inputRect.width : 0
        height: here ? d.inputRect.height : 0
    }

    // Click outside the panel to close
    MouseArea {
        anchors.fill: parent
        enabled: pop.engaged
        onClicked: pop.close()
    }

    // ---- Look --------------------------------------------------------------
    // The bar's own colour, so a panel is of a piece with the bar it comes out of, at an opacity
    // and with a blur of its own (Settings → Menu Bar → Glass → Panel opacity, Panel blur)
    readonly property color bg: !Config.glass ? bar.barColor
        : (c => Qt.rgba(c.r, c.g, c.b, Config.panelGlassOpacity))(Config.tint(Config.s.lightMode ? "#0f1216" : "#0c0e12"))
    readonly property color card: bar.capsuleColor
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    readonly property color warn: Config.tint("#f2cf8b")       // getting full or busy: before the red
    // The panels' clocks, in the clock style set for the bar (Settings → Menu Bar → Clock),
    // without seconds: they're big and don't tick every second
    readonly property real radius: Config.corner(14)
    readonly property real pad: 14

    // ---- Drop shadow under the panel: a copy of the panel's shape (the panel clips itself, so
    // it can't cast one), cast away from the bar. It moves with the panel at its full size: the
    // part not slid out yet is past the window's edge, so isn't drawn. (Sized to the part slid
    // out instead, its blur was redone on every frame of the slide.)
    Rectangle {
        x: panelArea.x + body.x
        y: panelArea.y + body.y
        width: panelArea.width
        height: panelArea.height
        topLeftRadius: body.topLeftRadius; topRightRadius: body.topRightRadius
        bottomLeftRadius: body.bottomLeftRadius; bottomRightRadius: body.bottomRightRadius
        // Never quite 0 while shown: at 0 Qt drops it from the scene and rebuilds it on the
        // first frame of the slide, which held the slide up
        opacity: pop.active ? Math.max(0.01, pop.fade) : 0      // prepared with the panel (see pending)
        // (the shape itself isn't drawn: only Slate's shadow round it, which has the panel's
        // shape cut out, so with glass nothing shows through the panel)
        color: "transparent"
        visible: width > 0 && height > 0
        Shadow {
            z: 0
            topLeftRadius: body.topLeftRadius; topRightRadius: body.topRightRadius
            bottomLeftRadius: body.bottomLeftRadius; bottomRightRadius: body.bottomRightRadius
            // Moved by the distance like every other shadow (grown all round by it instead, it
            // spread out at the sides too), its shape carried on into the bar, so it still meets
            // the bar with no gap or curl at the joins' ends
            attachEdge: pop.sideways ? pop.side : pop.fromBottom ? "bottom" : "top"
            // (fainter than where the blur behind the panel starts, as the bar's own is under its)
            strength: Config.panelShadowShare
            // The curved joins either side of it, where it leaves the bar, as part of its shape:
            // the shadow follows them out to the bar (and, kept from under them, nothing shows
            // through them on glass). None where the panel's flush with the screen's edge, nor
            // with Rounded UI elements off (Canvas joins below: the same shapes)
            readonly property real jr: Config.s.roundedElements ? bar.cornerRadius : 0
            readonly property bool joinStart: jr > 0 && !pop.atScreenStart
            readonly property bool joinEnd: jr > 0 && !pop.atScreenEnd
            joinRadius: jr
            joinA: !joinStart ? Qt.rect(0, 0, 0, 0)
                : pop.sideways ? Qt.rect(pop.side === "left" ? 0 : width - jr, -jr, jr, jr)
                : Qt.rect(-jr, pop.fromBottom ? height - jr : 0, jr, jr)
            joinB: !joinEnd ? Qt.rect(0, 0, 0, 0)
                : pop.sideways ? Qt.rect(pop.side === "left" ? 0 : width - jr, height, jr, jr)
                : Qt.rect(width, pop.fromBottom ? height - jr : 0, jr, jr)
            joinCentreA: pop.sideways ? Qt.point(pop.side === "left" ? jr : width - jr, -jr)
                : Qt.point(-jr, pop.fromBottom ? height - jr : jr)
            joinCentreB: pop.sideways ? Qt.point(pop.side === "left" ? jr : width - jr, height + jr)
                : Qt.point(width + jr, pop.fromBottom ? height - jr : jr)
            // The bar's own shadow is under this one, beside the panel (Bar.qml: cast from its
            // inner edge, which is this window's edge against the bar): only what the panel adds
            // over it is drawn, or beside the joins the two came out darker than either
            underNormal: pop.sideways ? Qt.point(pop.side === "left" ? 1 : -1, 0) : Qt.point(0, pop.fromBottom ? -1 : 1)
            underLine: pop.sideways ? (pop.side === "left" ? -parent.x : pop.width - parent.x)
                : (pop.fromBottom ? pop.height - parent.y : -parent.y)
            underStrength: Config.shadowsOn ? Config.shadowStrength * Config.barShadowShare * bar.shadow : 0
        }
    }

    // ---- Panel body --------------------------------------------------------
    // A panel opened from the bar's first or last button (in Slate's own arrangement the
    // control centre and the power menu; whichever buttons you've put there) sits flush
    // against the start / end of the screen, rounded only on its one corner out in the screen
    // Where the open panel is on its screen (Slate's px), for the tests: its shadow's place
    // (worked out when a test asks: shell.qml's state)
    function panelBox() { return ({ x: Math.round(margins.left + panelArea.x + body.x), y: Math.round(margins.top + panelArea.y + body.y),
                                       width: Math.round(panelArea.width), height: Math.round(panelArea.height) }); }
    readonly property bool atScreenStart: edge === "start"
    readonly property bool atScreenEnd: edge === "end"
    Item {
        id: panelArea
        readonly property real bodyW: (content.item ? content.item.implicitWidth : 280) + pop.pad * 2
        readonly property real bodyH: (content.item ? content.item.implicitHeight : 100) + pop.pad * 2
        width: bodyW
        height: bodyH
        x: pop.sideways ? (pop.side === "left" ? 0 : pop.width - width)
            : pop.atScreenStart ? 0 : pop.atScreenEnd ? pop.width - width
            : Math.max(bar.cornerRadius + 2, Math.min(pop.width - width - bar.cornerRadius - 2, pop.anchorX - width / 2))
        y: pop.sideways ? (pop.atScreenStart ? 0 : pop.atScreenEnd ? pop.height - height
                : Math.max(bar.cornerRadius + 2, Math.min(pop.height - height - bar.cornerRadius - 2, pop.anchorY - height / 2)))
            : (pop.fromBottom ? pop.height - height : 0)
        clip: true

        // Swallow clicks inside the panel
        MouseArea { anchors.fill: parent }

        Rectangle {
            id: body
            width: parent.width
            height: parent.height
            // Slides out of the bar; rounded on the corners away from it
            // (While it's being prepared it's drawn here too, still slid away and cut off by the
            // panel's edge, so it's ready without showing: see `pending`)
            x: pop.sideways ? (pop.side === "left" ? -1 : 1) * width * (1 - pop.fade) : 0
            y: pop.sideways ? 0 : (pop.fromBottom ? 1 : -1) * height * (1 - pop.fade)
            color: pop.bg
            // Flush with the start or end of the screen: not on the corner against it
            topLeftRadius: Config.corner((pop.side === "bottom" && !pop.atScreenStart) || (pop.side === "right" && !pop.atScreenStart) ? pop.radius : 0)
            topRightRadius: Config.corner((pop.side === "bottom" && !pop.atScreenEnd) || (pop.side === "left" && !pop.atScreenStart) ? pop.radius : 0)
            bottomLeftRadius: Config.corner((pop.side === "top" && !pop.atScreenStart) || (pop.side === "right" && !pop.atScreenEnd) ? pop.radius : 0)
            bottomRightRadius: Config.corner((pop.side === "top" && !pop.atScreenEnd) || (pop.side === "left" && !pop.atScreenEnd) ? pop.radius : 0)
            // Fades with its movement: in as it slides out, out as it slides back
            opacity: pop.active ? Math.max(0.01, pop.fade) : 0

            FocusScope {
                id: panelKeys
                anchors.fill: parent
                anchors.margins: pop.pad
                focus: pop.shown
                Keys.onEscapePressed: pop.close()
                // Down / Tab and Up / Shift+Tab move between the panel's controls in the order
                // they're laid out (keyStops), from wherever the keyboard is: none chosen yet
                // goes to the first or the last. Qt's own Tab order follows how the panel was
                // built, not how it looks: it skipped controls and wandered onto the panel itself
                Keys.onPressed: e => {
                    const on = e.key === Qt.Key_Down || e.key === Qt.Key_Tab;
                    const back = e.key === Qt.Key_Up || e.key === Qt.Key_Backtab;
                    if (!on && !back) return;
                    e.accepted = true;
                    pop.keyStep(on);
                }
                Loader {
                    id: content
                    focus: true
                    // (opened from the keyboard: its first control chosen once it's made)
                    onLoaded: if (pop.fromKeys) Qt.callLater(() => pop.focusFirst(true))
                    // Made fresh for each opening (in the prep stage), and gone when closed so
                    // nothing in it (meters, clocks…) makes the idle window redraw
                    active: pop.active
                    sourceComponent: pop.displayed === "volume" ? volumePanel
                        : pop.displayed === "wifi" ? wifiPanel
                        : pop.displayed === "keyboard" ? keyboardPanel
                        : pop.displayed === "clipboard" ? clipboardPanel
                        : pop.displayed === "screenshot" ? screenshotPanel
                        : pop.displayed === "bluetooth" ? bluetoothPanel
                        : pop.displayed === "battery" ? batteryPanel
                        : pop.displayed === "gamemode" ? gameModePanel
                        : pop.displayed === "drink" ? drinkPanel
                        : pop.displayed === "focus" ? focusPanel
                        : pop.displayed === "more" ? morePanel
                        : pop.displayed === "windowmode" ? windowModePanel
                        : pop.displayed === "calendar" ? calendarPanel
                        : pop.displayed === "session" ? sessionPanel
                        : pop.displayed === "control" ? controlPanel
                        : pop.displayed === "spaces" ? spacesPanel
                        : pop.displayed === "notifications" ? notificationsPanel : null
                }
            }
        }
        // A little shadow from the bar along the edge the panel comes out of it by, so the bar
        // sits over its panel (the curved joins have theirs, below). With glass only (a flat panel
        // is one piece with its bar), and not in game mode, as no shadow is
        Rectangle {
            visible: pop.barShadeOn
            opacity: pop.active ? pop.fade : 0
            readonly property real reach: pop.barShade
            x: pop.side === "right" ? parent.width - reach : 0
            y: pop.side === "bottom" ? parent.height - reach : 0
            width: pop.sideways ? reach : parent.width
            height: pop.sideways ? parent.height : reach
            gradient: Gradient {
                orientation: pop.sideways ? Gradient.Horizontal : Gradient.Vertical
                GradientStop { position: 0; color: pop.side === "bottom" || pop.side === "right" ? "transparent" : pop.barShadeColour }
                GradientStop { position: 1; color: pop.side === "bottom" || pop.side === "right" ? pop.barShadeColour : "transparent" }
            }
        }
    }
    // (how far that shadow reaches, and how dark it is against the bar)
    readonly property bool barShadeOn: Config.glass && !Config.gameMode
    readonly property real barShade: 9
    readonly property color barShadeColour: Config.shade(Math.min(0.42, Config.shadowStrength * 0.8))

    // Curved joins between the bar and the panel's sides
    Repeater {
        model: 2
        // (a Shape, as TitleBar's are: drawn by the GPU, recoloured without being painted again
        // in software on every frame of a colour change)
        Shape {
            id: join
            required property int index
            width: bar.cornerRadius; height: bar.cornerRadius
            // None at the screen's edge, for a panel flush against it; and none at all with
            // Rounded UI elements off, when a panel meets the bar square
            visible: Config.s.roundedElements && !(pop.atScreenEnd && index === 1) && !(pop.atScreenStart && index === 0)
            // Either side of the panel where it meets the bar (above and below it on a side bar).
            // The shape is drawn for a top bar's left join and mirrored for the others.
            x: pop.sideways ? (pop.side === "left" ? 0 : pop.width - width)
                : (index === 0 ? panelArea.x - width : panelArea.x + panelArea.width)
            y: pop.sideways ? (index === 0 ? panelArea.y - height : panelArea.y + panelArea.height)
                : (pop.fromBottom ? pop.height - height : 0)
            opacity: pop.active ? Math.max(0.01, pop.fade) : 0
            transform: Scale {
                xScale: pop.sideways ? (pop.side === "left" ? -1 : 1) : (index === 0 ? 1 : -1)
                yScale: pop.sideways ? (index === 0 ? -1 : 1) : (pop.fromBottom ? -1 : 1)
                origin.x: bar.cornerRadius / 2; origin.y: bar.cornerRadius / 2
            }
            readonly property real r: bar.cornerRadius
            readonly property color shade: pop.barShadeOn ? pop.barShadeColour : "transparent"
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: pop.bg; strokeColor: "transparent"; strokeWidth: -1
                startX: 0; startY: 0
                PathLine { x: join.r; y: 0 }
                PathLine { x: join.r; y: join.r }
                PathArc { x: 0; y: 0; radiusX: join.r; radiusY: join.r; direction: PathArc.Counterclockwise }
            }
            // ...and the bar's shadow on it, as on the panel: darkest at the bar, gone a little way
            // off (the shape's drawn for a top bar and mirrored, so on a side bar the bar's edge
            // is its right-hand one)
            ShapePath {
                strokeColor: "transparent"; strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: pop.sideways ? join.r : 0; y1: 0
                    x2: pop.sideways ? join.r - pop.barShade : 0; y2: pop.sideways ? 0 : pop.barShade
                    GradientStop { position: 0; color: join.shade }
                    GradientStop { position: 1; color: Qt.rgba(join.shade.r, join.shade.g, join.shade.b, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: join.r; y: 0 }
                PathLine { x: join.r; y: join.r }
                PathArc { x: 0; y: 0; radiusX: join.r; radiusY: join.r; direction: PathArc.Counterclockwise }
            }
        }
    }

    // ---- Control centre state ----------------------------------------------
    // Caffeine (Config.caffeine) keeps the session awake: Slate's idle lock and other idle watchers
    // respect it, and it's asked of the compositor too, for apps and tools that listen
    IdleInhibitor { window: pop.bar; enabled: Config.caffeine }
    onCurrentChanged: {
        if (current === "") fromKeys = false;       // (a panel opened from the keyboard: done)
        if (current === "control") uptimeFile.reload();
        if (current === "notifications" && notifs) notifs.markRead();
    }

    // Which speakers and microphones are in use just now: sound playing through one, or
    // something listening to one ({ node's name: true }). PipeWire knows (a node that's
    // "running"); asked every three seconds (pw-dump lists everything PipeWire knows, so it's
    // not cheap), and only while the volume panel's open. Without
    // pw-dump nothing's marked, and the sliders are as they always were
    property var audioBusy: ({})
    Process {
        id: audioBusyAsk
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                const busy = {};
                try {
                    for (const o of JSON.parse(text)) {
                        const i = o.info, p = i && i.props;
                        if (i && p && i.state === "running" && (p["media.class"] === "Audio/Sink" || p["media.class"] === "Audio/Source"))
                            busy[p["node.name"]] = true;
                    }
                } catch (e) {}
                if (JSON.stringify(busy) !== JSON.stringify(pop.audioBusy)) pop.audioBusy = busy;
            }
        }
    }
    Timer {
        interval: 3000; repeat: true; triggeredOnStart: true
        running: pop.current === "volume" && !Config.testMode
        onTriggered: if (!audioBusyAsk.running) audioBusyAsk.running = true
    }

    // The weather (Weather.qml): held there, and reached from the panels and the tests through
    // these, as it always was
    Weather { id: weatherSrc }
    property alias weather: weatherSrc.weather
    property alias forecast: weatherSrc.forecast
    function takeWeather(text: string): bool { return weatherSrc.take(text); }
    function weatherInfo(code) { return weatherSrc.info(code); }

    FileView { id: uptimeFile; path: "/proc/uptime" }
    readonly property string fullName: Config.fullName
    FileView { id: hostFileView; path: "/etc/hostname" }
    property alias hostFile: hostFileView     // (the control center's "you@this-computer")
    property string hyprVersion: ""
    Process {
        running: true
        command: ["hyprctl", "version", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { pop.hyprVersion = JSON.parse(text).tag.replace(/^v/, ""); } catch (e) {} } }
    }
    function uptimeText() {
        // (the same every time under the test suite, so its screenshots don't change with the
        // test machine's uptime)
        const sec = Config.testMode ? 121320 : parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return "Up " + (d > 0 ? d + (d === 1 ? " day " : " days ") : "") + h + " h " + m + " min";
    }

    // ---- Shared pieces -----------------------------------------------------
    // Run one of Slate's IPC calls (bin/slate ipc call …)
    function slate(args) { Config.slateCall(...args); }
    // Close the panel and open Settings on one of its pages
    function openSettingsPage(page) { close(); slate(["settings", "page", page]); }

    // What there isn't room for on the bar just now (Bar.qml: overflowed), a row each: its
    // icon, its name and what it says. A row does what the thing does on the bar: pressed (most
    // open their own panel, from More's place), right-clicked, scrolled over
    property var moreBar: null             // the bar whose More was pressed

    // ---- The panels, one file each in panels/ (the Loader above makes one when it opens) ----
    Component { id: volumePanel; VolumePanel { pop: PanelHost.pop } }
    Component { id: wifiPanel; WifiPanel { pop: PanelHost.pop } }
    Component { id: clipboardPanel; ClipboardPanel { pop: PanelHost.pop } }
    Component { id: spacesPanel; SpacesPanel { pop: PanelHost.pop } }
    Component { id: screenshotPanel; ScreenshotPanel { pop: PanelHost.pop } }
    Component { id: keyboardPanel; KeyboardPanel { pop: PanelHost.pop } }
    Component { id: morePanel; MorePanel { pop: PanelHost.pop } }
    Component { id: bluetoothPanel; BluetoothPanel { pop: PanelHost.pop } }
    Component { id: windowModePanel; WindowModePanel { pop: PanelHost.pop } }
    Component { id: gameModePanel; GameModePanel { pop: PanelHost.pop } }
    Component { id: drinkPanel; DrinkPanel { pop: PanelHost.pop } }
    Component { id: focusPanel; FocusPanel { pop: PanelHost.pop } }
    Component { id: batteryPanel; BatteryPanel { pop: PanelHost.pop } }
    Component { id: calendarPanel; CalendarPanel { pop: PanelHost.pop } }
    Component { id: sessionPanel; SessionPanel { pop: PanelHost.pop } }
    Component { id: controlPanel; ControlPanel { pop: PanelHost.pop } }
    Component { id: notificationsPanel; NotificationsPanel { pop: PanelHost.pop } }
}
