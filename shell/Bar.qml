// Slate's menu bar: workspaces, the focused window's title, tray, status, clock and power.
//
// Auto-hide (Settings → Menu Bar): while hidden the bar reserves no space, so windows use
// the whole screen; pushing the pointer against the bar's screen edge slides it in and moves
// the windows aside to make room, and it slides away again shortly after the pointer leaves
// (it stays while one of its panels is open). `slate ipc call bar reveal` shows it for a few
// seconds.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: bar

    // ---- Look --------------------------------------------------------------
    readonly property real barHeight: 40
    readonly property real capsuleHeight: 27
    readonly property real capsuleRadius: 6
    readonly property real sidePadding: (barHeight - capsuleHeight) / 2   // space at the bar's ends: the same as above and below the buttons
    readonly property real gap: 6
    readonly property real cornerRadius: 12            // concave corners under the bar
    // Rounded screen corners (drawn by ScreenCorners.qml): a squircle (superellipse) shape
    readonly property real screenCornerRadius: 17
    readonly property real screenCornerShape: 3.0
    // (See-through with glass: Settings → Appearance → Glass)
    readonly property color barColor: Config.surface(Config.tint("#0f1216"))
    // The menu bar's own background: with glass in dark mode, darker and less see-through
    // than other glass (a quarter of the way from Glass → Opacity to solid), so the bar reads as a steady
    // band whatever the wallpaper does behind it
    // (and clearer still by Settings → Menu Bar → Background opacity: Config.barGlassOpacity)
    readonly property color barBackground: !Config.glass ? barColor
        : (c => Qt.rgba(c.r, c.g, c.b, Config.barGlassOpacity))(Config.tint(Config.s.lightMode ? "#0f1216" : "#0c0e12"))
    // In light mode a shade deeper than other fields, to stand out from the tinted bar
    readonly property color capsuleColor: Config.raised(Config.tint(Config.s.lightMode ? "#262c35" : "#1d222a"))
    // On the bar itself, a container with an opacity chosen (Settings → Menu Bar → Glass) is
    // drawn solid, and the whole of it faded to that (Capsule, below; Settings' cards and the arranging panel's chips keep
    // capsuleColor as it is)
    readonly property color capsuleSolid: Config.frostedTile(Config.tint(Config.s.lightMode ? "#262c35" : "#1d222a"))
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color dimColor: Config.tint("#c5ccd6")
    readonly property color accent: Config.accent
    readonly property color errorColor: Config.tint("#f28b8b")
    // With glass: a translucent line in the dim text colour (light in dark mode, dark in light
    // mode, tinted toward the wallpaper), which stays visible whatever's behind the bar
    readonly property color separatorColor: Config.glass ? withAlpha(dimColor, 0.35)
                                                           : Config.tint("#444c58")
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    readonly property string fontFamily: Config.s.fontFamily   // Settings → Appearance → Fonts
    readonly property real fontSize: 13              // Settings → Interface size scales it with everything else
    readonly property string iconFont: tabler.name
    readonly property int holdMs: 4000
    readonly property int slideMs: 500

    // Drop-down panels (Popouts.qml), set from shell.qml
    property var popouts: null
    property var notifs: null
    // Each screen has a bar; the primary one answers `slate ipc call bar …` and passes it
    // to the bar on the focused screen
    property bool primary: true
    Component.onCompleted: { Config.bars = Config.bars.concat([bar]); settledSide = side; }
    Component.onDestruction: Config.bars = Config.bars.filter(b => b !== bar)
    // A panel is open from this bar (the panels go to whichever screen opened them)
    // (from the start of opening, so the bar is done changing before the panel slides)
    readonly property bool popoutHere: !!popouts && popouts.engaged && popouts.screen === bar.screen
    // Is this the very first or very last thing on the bar ("start" / "end"; "" if neither)?
    // Its panel then sits flush against that end of the screen, as the control centre's and
    // the power menu's always have: now whichever buttons are there, wherever they've been put
    // What a thing would say on the bar with its text on (for the arranging panel's pool: a chip
    // carried from there is drawn as the thing will be when it lands)
    function exampleOf(id) { const t = left.things[id]; return id === "windowtitle" ? "Window" : t && !bar.vert ? (t.exampleLabel || "") : ""; }
    // (tests) A drag on the bar while it's being arranged, in the bar window's own coordinates:
    // press at one place, move to the next in steps, let go
    function testDrag(x0, y0, x1, y1) {
        const at = (x, y) => arranger.mapFromItem(null, x, y);
        let p = at(x0, y0);
        arranger.press(p.x, p.y);
        for (let i = 1; i <= 6; i++) { p = at(x0 + (x1 - x0) * i / 6, y0 + (y1 - y0) * i / 6); arranger.move(p.x, p.y); }
        arranger.release();
    }
    readonly property string clockText: clock.text
    readonly property var scrollState: ({ at: Math.round(scroll), max: Math.round(scrollMax), handle: scrollGrip.visible })
    // What's in More, for its panel (Popouts.qml): a row each, in the order they left. The
    // tray is a row for each of its icons; the window's icon goes with its title
    function moreRows() {
        const rows = [];
        for (const id of overflowed) {
            const it = Config.barItem(id), t = left.things[id];
            if (!it || !t || id === "windowicon") continue;
            if (id === "tray") {
                for (const tr of SystemTray.items.values)
                    rows.push({ id: id, tray: tr, label: tr.tooltipTitle || tr.title || tr.id || "App", icon: 0, image: String(tr.icon), value: "" });
                continue;
            }
            rows.push({ id: id, tray: null, label: id === "windowtitle" ? "Window" : it.label, icon: it.icon, image: "",
                        value: id === "windowtitle" ? titleText.text : id === "workspaces" ? Config.workspaceLabel(Config.focusedWorkspaceId) : (t.plain ? t.label : "") });
        }
        return rows;
    }
    // A row in More pressed, right-clicked or scrolled over: what the thing itself does on the bar
    function moreClick(row, right) {
        if (row.tray) {
            const it = row.tray;
            if ((right || it.onlyMenu || indicatorIds.includes(it.id)) && it.hasMenu) { if (popouts) popouts.close(); openTrayMenu(it.menu, moreBtn); }
            else { if (popouts) popouts.close(); it.activate(); }
            return;
        }
        const t = left.things[row.id];
        if (!t) return;
        if (row.id === "workspaces") { if (popouts) popouts.close(); Config.slateCall("overview", "toggle"); }
        else if (right) t.rightClicked();
        else t.clicked();
    }
    function moreWheel(row, delta) { const t = left.things[row.id]; if (t && !row.tray) t.wheel(delta); }
    // (tests) Each thing on the line: where it is in the bar's window and whether it shows
    function lineState() {
        const out = {};
        for (const name in left.things) {
            const t = left.things[name], p = t.mapToItem(null, 0, 0);
            out[name] = { visible: t.visible, text: t.plain ? (t.slimText ? "" : t.drawnLabel) : "", opacity: t.opacity, x: Math.round(p.x), y: Math.round(p.y), w: Math.round(t.width), h: Math.round(t.height),
                          box: t.shell ? t.shell.index : -1, boxOpen: t.shell ? t.shell.openness : -1, parentVisible: t.parent ? t.parent.visible : false };
        }
        return out;
    }
    function outermost(item) {
        const box = item ? item.shell : null;
        if (!box) return "";
        const shown = [];
        for (const c of left.children) if (c.visible && (bar.vert ? c.height : c.width) > 0.5) shown.push(c);
        if (shown.length === 0) return "";
        if (shown[0] === box && item.first) return "start";
        if (shown[shown.length - 1] === box && item.last) return "end";
        return "";
    }
    function openPopout(name, item) {
        if (!popouts) return;
        if (item.overflowed) item = moreBtn;        // (asked for from the More panel: it opens from More's place)
        const p = item.mapToItem(content, item.width / 2, item.height / 2);   // from the screen edge
        // (a button that isn't showing has no place to go by: the panel opens as it always did)
        popouts.toggle(name, p.x, p.y, bar.screen, item.visible ? outermost(item) : undefined);
    }
    // With more than one screen, the bars on screens without focus are dimmed
    readonly property bool dimmed: Quickshell.screens.length > 1 && !!screen
        && !(Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === screen.name)

    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    function glyph(code) { return String.fromCodePoint(code); }

    // ---- Window ------------------------------------------------------------
    // Which screen edge (Settings → Menu Bar → Position). Laid out for the top; at the bottom
    // the curves and corners flip, and on a side the groups stack top to bottom, the status
    // icons drop their text, the clock stacks and the window title is turned to run along it.
    // The edge it's on: the setting's, once it's slid out of sight at the old one (then it slides
    // in at the new), rather than Hyprland sliding the window across the screen
    // (bound to start with, so it starts on the right edge; on a change, put straight back,
    // before anything's drawn, until it's slid out: settledSide is where it was)
    property string side: Config.barEdge
    property string settledSide: ""
    property bool movingOut: false
    Connections {
        target: Config
        function onBarEdgeChanged() {
            if (bar.settledSide === "" || Config.barEdge === bar.settledSide) return;
            bar.side = bar.settledSide;
            bar.movingOut = true;
            barMove.restart();
        }
    }
    Timer {
        id: barMove
        interval: Config.ms(300) + 20
        // (in at the new edge, and shown there a moment even with auto-hide)
        onTriggered: { bar.side = Config.barEdge; bar.settledSide = bar.side; bar.movingOut = false; holdTimer.restart(); }
    }
    readonly property bool vert: side === "left" || side === "right"
    readonly property bool atBottom: side === "bottom"
    readonly property bool atRight: side === "right"
    readonly property real bgY: atBottom ? cornerRadius : 0      // where the bar's band starts
    readonly property real bgX: atRight ? cornerRadius : 0
    readonly property real thickness: barHeight + cornerRadius
    // Room for the drop shadow beyond the bar (the window is this much bigger; it takes no input)
    readonly property real shadowPad: 18
    // Drop shadow while the pointer is on the bar or one of its panels is open
    property real shadow: hovered || popoutHere ? 1 : 0
    Behavior on shadow { NumberAnimation { duration: Config.ms(220); easing.type: Easing.OutCubic } }
    // Text along a side bar is turned to read top to bottom on the right, bottom to top on the left
    readonly property real textRotation: vert ? (atRight ? 90 : -90) : 0
    anchors { top: side !== "bottom"; bottom: side !== "top"; left: side !== "right"; right: side !== "left" }
    implicitHeight: vert ? 0 : thickness + shadowPad
    implicitWidth: vert ? thickness + shadowPad : 0
    color: "transparent"
    WlrLayershell.namespace: "slate-bar"
    // (above the dimming laid over the windows while the bar's being arranged: BarEditor.qml)
    WlrLayershell.layer: Config.barArranging ? WlrLayer.Overlay : WlrLayer.Top
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Math.round(barHeight * zoneReveal)
    mask: Region { item: hitArea; Region { item: scrollGrip } }

    // ---- Auto-hide state ---------------------------------------------------
    property bool filled: false          // one window fills the workspace (from Hyprland)
    // The pointer is on the bar: on an empty part of it (hitArea, which also catches the thin
    // strip while the bar's hidden) or on anything in it. (hitArea alone went false over the
    // bar's own buttons, which take the hover themselves, and the bar's shadow vanished there)
    readonly property bool hovered: hover.hovered || overItems.hovered
    Timer { id: holdTimer; interval: bar.holdMs }        // shown after fill / workspace switch
    Timer { id: hoverTimer; interval: 700 }              // lingers a moment after the pointer leaves
    onHoveredChanged: if (!hovered) hoverTimer.restart()

    // Reserved space follows the "held" state; hover only slides the bar over the window
    // Auto-hide only applies when it's switched on in Settings
    readonly property bool autoHiding: Config.s.barAutoHide
    // Reserved space follows the bar: while auto-hiding, windows get the whole screen, and when
    // the bar slides in they're pushed aside to make room (and grow back when it leaves)
    property real zoneReveal: reveal
    property real reveal: !movingOut && (!autoHiding || holdTimer.running || hovered || hoverTimer.running || popoutHere || trayMenuWin.visible || Config.barArranging) ? 1 : 0
    Behavior on zoneReveal { NumberAnimation { duration: Config.ms(bar.slideMs); easing.type: Easing.InOutCubic } }
    // (quicker out when it's moving to another edge)
    Behavior on reveal { NumberAnimation { duration: Config.ms(bar.movingOut ? 300 : bar.slideMs); easing.type: Easing.InOutCubic } }

    function setFilled(value) {
        if (value && !filled) holdTimer.restart();
        filled = value;
    }
    function revealNow() { if (autoHiding) holdTimer.restart(); }
    function openPanel(name) {
        const button = ({ control: flameBtn, spaces: spacesBtn, notifications: bellBtn, session: powerBtn, windowmode: wsMode,
                          volume: volSeg, wifi: wifiSeg, clipboard: clipSeg, screenshot: shotSeg, keyboard: kbSeg, bluetooth: btSeg, battery: batSeg, gamemode: gameSeg, calendar: clockCap, more: moreBtn })[name];
        if (name === "more" && popouts) popouts.moreBar = bar;
        if (button) openPopout(name, button);
    }
    // Tray apps with no "activate" of their own: Ayatana app indicators (Steam and others)
    // only have a menu, so clicking them shows it, as KDE does. Found by their D-Bus paths,
    // whose last part is the item's id. Only the main bar asks (every bar would get the same
    // answer); they all read it from Config
    readonly property var indicatorIds: Config.trayIndicatorIds
    Process {
        id: indicatorQuery
        // (gdbus, from glib, rather than busctl, which only systemd has. It answers
        // (<['name/path', …]>,))
        command: ["gdbus", "call", "--session", "--dest", "org.kde.StatusNotifierWatcher", "--object-path", "/StatusNotifierWatcher",
                  "--method", "org.freedesktop.DBus.Properties.Get", "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"]
        stdout: StdioCollector {
            onStreamFinished: {
                Config.trayIndicatorIds = (text.match(/'[^']*'/g) || []).map(x => x.slice(1, -1))
                    .filter(x => x.includes("/org/ayatana/NotificationItem/")).map(x => x.split("/").pop());
            }
        }
    }
    Timer { id: indicatorLater; interval: 800; running: bar.primary; onTriggered: { indicatorQuery.running = false; indicatorQuery.running = true; } }
    Connections { target: SystemTray.items; enabled: bar.primary; function onValuesChanged() { indicatorLater.restart(); } }

    // App tray menus (TrayMenu.qml), opened from a tray icon at its centre on the bar's inner edge
    TrayMenu { id: trayMenuWin; bar: bar }
    // Where a menu opened from one of the bar's items points from: the item's centre on the
    // screen, moved out to the bar's inner edge, where the menu's pointer meets it
    function menuAnchor(item) {
        // The item's centre in the bar's window, then on the screen (the bar's window sits
        // against its edge of the screen)
        const p = item.mapToItem(bar.contentItem, item.width / 2, item.height / 2);
        const sw = bar.screen ? bar.screen.width : 0, sh = bar.screen ? bar.screen.height : 0;
        let x = p.x + (bar.side === "right" ? sw - bar.width : 0);
        let y = p.y + (bar.side === "bottom" ? sh - bar.height : 0);
        if (bar.side === "top") y = bar.barHeight;
        else if (bar.side === "bottom") y = sh - bar.barHeight;
        else if (bar.side === "left") x = bar.barHeight;
        else x = sw - bar.barHeight;
        return Qt.point(x, y);
    }
    function openTrayMenu(menu, item) {
        const at = menuAnchor(item);
        trayMenuWin.openFor(menu, at.x, at.y);
    }
    // The Slate button's right-click menu: quick access to useful things
    function openSlateMenu(item) {
        if (bar.popouts) bar.popouts.close();
        const slate = args => () => Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call"].concat(args));
        const notifs = bar.notifs;
        const list = [
            { text: "Settings", glyph: 0xEB20, action: slate(["settings", "open"]) },
            { text: "Appearance", glyph: 0xEB01, action: slate(["settings", "page", "appearance"]) },
            { text: "Next wallpaper", glyph: 0xEB0A, action: slate(["wallpaper", "next"]) },
            { separator: true },
            { text: "Do Not Disturb", glyph: 0xECE9, checked: !!(notifs && notifs.dnd), action: () => { if (notifs) notifs.dnd = !notifs.dnd; } },
            { text: "Night Light", glyph: 0xEAF8, checked: Config.s.nightLight, action: slate(["nightlight", "toggle"]) },
            { text: "Glass", glyph: 0xEB01, checked: Config.s.glass, action: () => { Config.s.glass = !Config.s.glass; } },
            { separator: true },
            { text: Updates.available ? "Update to " + Updates.latest : "Check for updates", glyph: 0xEA96, action: slate(["settings", "page", "updates"]) },
            { text: "Restart Slate", glyph: 0xEB13, action: () => Config.restartSlate() },
            { text: "Show the welcome", glyph: 0xEDBA, action: slate(["welcome", "open"]) },
            { separator: true },
            { text: "Lock screen", glyph: 0xEAE2, action: slate(["lock", "lock"]) },
            { text: "Log out…", glyph: 0xEBA8, action: slate(["power", "confirm", "logout"]) },
            { text: "About Slate", glyph: 0xEAC5, action: slate(["settings", "page", "about"]) }
        ];
        const at = menuAnchor(item);
        trayMenuWin.openList(list, at.x, at.y);
    }
    function focusedBar() { return Config.barFor(Config.focusedScreen) || bar; }
    IpcHandler {
        target: "bar"
        enabled: bar.primary
        // Hyprland's notes and requests are for the focused screen's bar
        function setFilled(value: bool): void { bar.focusedBar().setFilled(value); }
        function reveal(): void { bar.focusedBar().revealNow(); }
        // Arranging the bar (Settings → Menu Bar → Edit layout):  slate ipc call bar edit start | done
        // (done, with menu item priority up: back to the arranging, as its Back does. It's what
        // Escape runs while the bar's arranged)
        function edit(what: string): void {
            if (what !== "start" && Config.barPrioritising) Config.barPrioritising = false;
            else Config.barArranging = what === "start";
        }
        // Open (or close) one of the bar's panels under its button, e.g.
        //   slate ipc call bar panel control
        // names: control, spaces, notifications, session, volume, wifi, clipboard, screenshot,
        // keyboard, bluetooth, battery, gamemode, calendar, windowmode
        function panel(name: string): void { bar.focusedBar().openPanel(name); }
    }

    // Takes pointer input: the bar while shown, a thin strip at the top edge while hidden
    Item {
        id: hitArea
        readonly property real depth: bar.reveal > 0.01 ? bar.barHeight : 2    // a thin strip at the edge while hidden
        width: bar.vert ? depth : parent.width
        height: bar.vert ? parent.height : depth
        x: bar.vert && bar.atRight ? parent.width - width : 0
        y: !bar.vert && bar.atBottom ? parent.height - height : 0
        HoverHandler { id: hover }
        // Right-click an empty part of the bar, a flexible space or the active window: the
        // bar's own menu. (Things on the bar keep their own right-clicks)
        ClickTap {
            id: barRightClick
            acceptedButtons: Qt.RightButton
            enabled: !Config.barArranging
            onTapped: at => {
                const w = hitArea.mapToItem(null, at.position.x, at.position.y);
                const p = left.mapFromItem(null, w.x, w.y);
                const under = left.childAt(p.x, p.y);
                if (under && under.isBox) {
                    const q = under.row.mapFromItem(null, w.x, w.y), cell = under.row.childAt(q.x, q.y);
                    if (cell !== winTitle && cell !== winIcon) return;
                }
                barMenu.openAt(w.x + bar.windowX, w.y + bar.windowY);
            }
        }
    }
    // (this window's corner within its screen: it sits against its edge)
    readonly property real windowX: bar.screen && bar.side === "right" ? bar.screen.width - bar.width : 0
    readonly property real windowY: bar.screen && bar.side === "bottom" ? bar.screen.height - bar.height : 0
    DesktopMenu {
        id: barMenu
        screen: bar.screen
        items: [
            { label: "Auto-hide", icon: Config.s.barAutoHide ? 0xEA5E : 0, run: () => Config.s.barAutoHide = !Config.s.barAutoHide },
            { label: "Edit layout", icon: 0xEB04, run: () => Config.barArranging = true }
        ]
    }
    property alias menu: barMenu

    // ---- What's under the pointer, shown in the title area ------------------
    property Item hoverItem: null      // bar item under the pointer (has hoverText etc.)
    property Item shownItem: null      // what the title area shows (null = focused window)
    Timer { id: hoverClear; interval: 140; onTriggered: bar.hoverItem = null }
    function setHover(item, on) {
        if (!Config.s.barHoverDescriptions) { hoverItem = null; return; }
        if (on) { hoverClear.stop(); hoverItem = item; }
        else if (hoverItem === item) hoverClear.restart();
    }
    onHoverItemChanged: titleSwap.restart()
    SequentialAnimation {
        id: titleSwap
        NumberAnimation { target: bar; property: "titleFade"; to: 0; duration: Config.ms(90); easing.type: Easing.InQuad }
        ScriptAction { script: { bar.shownItem = bar.hoverItem; bar.shownTop = ToplevelManager.activeToplevel; } }
        NumberAnimation { target: bar; property: "titleFade"; to: 1; duration: Config.ms(140); easing.type: Easing.OutQuad }
    }
    // The window whose icon and title the bar shows: the focused one, taken up at the middle of
    // the same cross-fade, so going from one window to another fades the old out and the new
    // in. (A window changing its own title just changes: some do every second)
    property var shownTop: null
    Connections {
        target: ToplevelManager
        Component.onCompleted: bar.shownTop = ToplevelManager.activeToplevel
        function onActiveToplevelChanged() { if (ToplevelManager.activeToplevel !== bar.shownTop) titleSwap.restart(); }
    }

    // Uptime, for the power button's hover text: read again as the pointer comes onto the button
    // (rather than every minute, on every bar, whether anyone looked or not)
    FileView { id: uptimeFile; path: "/proc/uptime" }
    function uptimeText() {
        const sec = parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return "Up " + (d > 0 ? d + (d === 1 ? " day " : " days ") : "") + (h > 0 || d > 0 ? h + " h " : "") + m + " min";
    }

    // ---- Room along the line (the flexible spaces, and how long a title may be) ------------
    readonly property real lineFull: Math.max(0, (vert ? content.height : content.width) - 2 * sidePadding)
    readonly property real lineLength: Math.max(0, lineFull - squeeze - lineFull * Config.barPreview)
    // (tests, and the arranging panel's narrow preview: the line made this much shorter)
    property real squeeze: 0

    // ---- Arranged, and too long to show whole: it scrolls ----------------------------------------
    // While the bar's arranged nothing is slimmed or tucked, everything has its text and every
    // container its gripper, so what's on it can be longer than the bar. The line then slides
    // along inside the bar: by the thick handle under it (only there when it's needed), by the
    // wheel over the bar, and by itself as something's carried to either end. From the
    // beginning each time arranging starts.
    readonly property real lineNatural: vert ? left.height : left.width
    readonly property real scrollMax: Config.barShowAll ? Math.max(0, Math.ceil(lineNatural - lineLength)) : 0
    property real scroll: 0
    onScrollMaxChanged: scroll = Math.max(0, Math.min(scrollMax, scroll))
    function scrollBy(d) { scroll = Math.max(0, Math.min(scrollMax, scroll + d)); }
    Connections { target: Config; function onBarShowAllChanged() { bar.scroll = 0; } }

    // ---- When it doesn't all fit: slimming (plans/menubar-length.md) --------------------------
    // The line gives up the cheapest things first, each only if it still doesn't fit after the
    // one before: the window's title goes (its icon stays; before that it has already
    // shortened, and the flexible spaces have closed up), then the text beside icons, longest
    // first, then the clock's date, then its seconds. Nothing's lost that a hover or a click
    // doesn't bring back. `gives` is what's been given up, in that order.
    //
    // Worked out by trying: with nothing given up, then one thing, then two…, laying the line
    // out afresh each time (all in one go, so none of it is drawn) until it fits. Something
    // given up comes back only when there'd be `slimMargin` to spare with it back, so a line
    // that only just fits doesn't have things coming and going. Not while the bar's being
    // arranged: everything's there then, to be picked up.
    property var gives: []
    // ...and when slimming isn't enough, things leave the bar for More, one at a time, in the
    // order they're least minded (Config.barOverflowDefault; some stay whatever happens), and
    // come back in the reverse order. What's in More now, in that order:
    property var overflowed: []
    property bool fitting: false
    property bool slimTitle: false
    property int slimClock: 0                 // 1: no date; 2: no seconds either
    readonly property real slimMargin: 28
    readonly property real titleLeast: 44     // a title shorter than this isn't worth its room
    function slimPlan() {
        const plan = [];
        if (Config.barShowAll) return plan;
        if (Config.s.barShowTitle && winTitle.shell && titleText.text !== "") plan.push("title");
        if (!vert) {
            const texts = [];
            for (const id in left.things) {
                const t = left.things[id];
                if (t.shell && t.wanted && t.plain && t.label !== "") texts.push({ id: id, w: t.labelLength });
            }
            texts.sort((a, b) => b.w - a.w || (a.id < b.id ? -1 : 1));
            for (const t of texts) plan.push("text:" + t.id);
        }
        if (clockCap.shell && clockCap.wanted) {
            if (Config.s.barClockDate) plan.push("clock:date");
            if (Config.s.barClockSeconds) plan.push("clock:seconds");
        }
        // ...then the containers set to collapse when needed tuck away, one at a time: the one
        // holding what's minded least first (Config.barOverflowRank)
        const boxes = [];
        for (const c of left.children) {
            if (!c.isBox || c.collapse !== "needed" || c.cells.indexOf(moreBtn) >= 0) continue;     // (More is never tucked away)
            const shown = c.cells.filter(x => x.wanted);
            if (shown.length >= 2) boxes.push({ at: c.index, rank: Math.min(...shown.map(x => Config.barOverflowRank(x.name))) });
        }
        boxes.sort((a, b) => a.rank - b.rank || a.at - b.at);
        for (const b of boxes) plan.push("tuck:" + b.at);
        // ...and then things leave for More
        for (const id of Config.barOverflowOrder) {
            const t = left.things[id];
            if (!t || !t.shell || Config.barStays(id)) continue;
            if (id === "windowtitle" ? (Config.s.barShowTitle && titleText.text !== "") : t.wanted) plan.push("over:" + id);
        }
        return plan;
    }
    function slimApply(given) {
        slimTitle = given.indexOf("title") >= 0;
        slimClock = given.indexOf("clock:seconds") >= 0 ? 2 : given.indexOf("clock:date") >= 0 ? 1 : 0;
        overflowed = given.filter(g => g.indexOf("over:") === 0).map(g => g.slice(5));
        for (const id in left.things) {
            left.things[id].slimText = given.indexOf("text:" + id) >= 0;
            left.things[id].overflowed = given.indexOf("over:" + id) >= 0;
        }
        for (const c of left.children) if (c.isBox) c.needTuck = given.indexOf("tuck:" + c.index) >= 0;
        // (laid out now, not when the next frame is drawn: its length is about to be read)
        for (const c of left.children) if (c.isBox) c.relayout();
        left.forceLayout();
    }
    // How much too long the line is as it stands (below 0: that much to spare), allowing the
    // title, where it shows, the least room worth having
    // (by the lengths things will have once settled: a container opening or closing is eased)
    function slimOver() {
        let sum = 0, n = 0;
        for (const c of left.children) {
            if (!c.visible) continue;
            if (c.isSpace) { n++; continue; }
            const len = c.isBox ? c.settledLength : (vert ? c.height : c.width);
            if (c.isBox || len > 0) { n++; sum += len; }
        }
        const title = winTitle.wanted && winTitle.shell && !winTitle.shell.tuck;
        return sum + gap * Math.max(0, n - 1) + (title ? titleLeast : 0) - lineLength;
    }
    function fit() {
        if (fitting) return;
        fitting = true;
        const plan = slimPlan();
        let fits = -1, roomy = -1;
        for (let k = 0; k <= plan.length && roomy < 0; k++) {
            slimApply(plan.slice(0, k));
            const over = slimOver();
            if (fits < 0 && over <= 0) fits = k;
            if (over <= -slimMargin) roomy = k;
        }
        if (fits < 0) fits = plan.length;
        if (roomy < 0) roomy = plan.length;
        // (as few as fit; one already given up stays so unless there's room to spare without it)
        const k = Math.max(fits, Math.min(roomy, gives.length));
        slimApply(plan.slice(0, k));
        gives = plan.slice(0, k);
        fitting = false;
    }
    Timer { id: fitLater; interval: 40; onTriggered: bar.fit() }
    onLineLengthChanged: fitLater.restart()
    onLineFixedChanged: if (!fitting) fitLater.restart()
    Connections {
        target: Config
        function onBarArrangingChanged() { fitLater.restart(); }
        function onBarPreviewChanged() { fitLater.restart(); }
        function onBarOverflowOrderChanged() { fitLater.restart(); }
        function onBarStayChanged() { fitLater.restart(); }
    }

    // What's on the line besides the window's title: how much room the fixed things take
    // (the title's own container counted without the title), and how many things there are
    // (flexible spaces included). The line (a Grid) leaves a gap between every two things it
    // shows and passes over anything with no size; a flexible space always keeps a sliver of
    // size, so it always has its two. (The title's size isn't read here: how long it may be
    // depends on this)
    readonly property real lineOthers: {
        let sum = 0;
        for (const c of left.children)
            if (c.visible && !c.isSpace) sum += c.isBox && c.stretchyCell ? c.fixedLength : (vert ? c.height : c.width);
        return sum;
    }
    readonly property int lineOthersCount: {
        let n = 0;
        for (const c of left.children)
            if (c.visible && (c.isSpace || c.isBox || (vert ? c.height : c.width) > 0)) n++;
        return n;
    }
    readonly property int lineSpaces: { let n = 0; for (const c of left.children) if (c.isSpace && c.visible) n++; return n; }
    // What the title could have: everything the others don't need, a gap between each two
    readonly property real lineFixed: lineOthers + gap * Math.max(0, lineOthersCount - 1)
    // What each flexible space gets: an equal share of what's left once the title has its own
    readonly property real flex: {
        if (lineSpaces === 0) return 0;
        const title = winTitle.visible ? (vert ? titleBody.height : titleBody.width) : 0;
        return Math.max(0, (lineLength - lineFixed - title) / lineSpaces);
    }
    // The cross-fade between the window's title and a description of what the pointer's over
    property real titleFade: 1

    // The scroll handle: thicker than Slate's usual scrollbar (sideways scrolling is harder to
    // do), in the accent, with no track. Just off the bar, on its inner side
    Item {
        id: scrollGrip
        visible: bar.scrollMax > 0
        readonly property real thick: 14                    // (its hit area: the handle's drawn slimmer within it)
        readonly property real travel: Math.max(1, bar.lineLength - handle.length)
        x: bar.vert ? (bar.atRight ? bar.width - bar.barHeight - thick - 2 : bar.barHeight + 2) : bar.sidePadding
        y: bar.vert ? bar.sidePadding : (bar.atBottom ? bar.height - bar.barHeight - thick - 2 : bar.barHeight + 2)
        width: bar.vert ? thick : bar.lineLength
        height: bar.vert ? bar.lineLength : thick
        Rectangle {
            id: handle
            readonly property real length: Math.max(64, bar.lineLength * bar.lineLength / Math.max(1, bar.lineNatural))
            readonly property real at: scrollGrip.travel * (bar.scrollMax > 0 ? bar.scroll / bar.scrollMax : 0)
            readonly property real across: gripHover.hovered || gripDrag.pressed ? 10 : 8
            x: bar.vert ? (scrollGrip.thick - across) / 2 : at
            y: bar.vert ? at : (scrollGrip.thick - across) / 2
            width: bar.vert ? across : length
            height: bar.vert ? length : across
            radius: across / 2
            color: Config.accent
            opacity: gripHover.hovered || gripDrag.pressed ? 1 : 0.75
            Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
        }
        HoverHandler { id: gripHover }
        MouseArea {
            id: gripDrag
            anchors.fill: parent
            preventStealing: true
            property real grab: 0
            function to(m) {
                const a = (bar.vert ? m.y : m.x) - grab;
                bar.scroll = Math.max(0, Math.min(bar.scrollMax, a / scrollGrip.travel * bar.scrollMax));
            }
            onPressed: m => {
                const a = bar.vert ? m.y : m.x;
                // On the handle: keep the grab point; beside it: bring its middle here
                grab = a >= handle.at && a <= handle.at + handle.length ? a - handle.at : handle.length / 2;
                to(m);
            }
            onPositionChanged: m => { if (pressed) to(m); }
        }
    }

    // ---- Drawing -----------------------------------------------------------
    Item {
        id: content
        width: bar.vert ? bar.thickness : parent.width
        height: bar.vert ? parent.height : bar.thickness
        // Against the screen edge (the window's extra room, for the shadow, is on the inside)
        x: bar.vert && bar.atRight ? bar.shadowPad : 0
        y: !bar.vert && bar.atBottom ? bar.shadowPad : 0
        HoverHandler { id: overItems }
        // Hides by sliding off its screen edge
        transform: Translate {
            x: bar.vert ? (bar.atRight ? 1 : -1) * bar.thickness * (1 - bar.reveal) : 0
            y: bar.vert ? 0 : (bar.atBottom ? 1 : -1) * bar.thickness * (1 - bar.reveal)
        }

        // The bar's shape (band and curved corners), casting a shadow on hover or while a panel
        // is open: Slate's own (Shadow.qml), following the band and its flared corners, with
        // the bar's shape cut out of it so nothing shows through with glass. The shape is the
        // whole strip (band and the corners' depth) less the desktop's rounded rectangle
        Item {
            anchors.fill: parent
            Shadow {
                readonly property real far: 8000
                readonly property real r: Config.s.roundedScreenCorners ? bar.cornerRadius : 0
                visible: !Config.gameMode && opacity > 0.01
                opacity: bar.shadow
                // (kept fainter than where Hyprland starts blurring behind the bar, which is
                // lower when the bar's background is made clearer)
                // (only with the bar's blur on: without it there's nothing to keep under)
                strength: Config.barShadowShare
                radius: 0
                blur: 15
                dropX: bar.vert ? (bar.atRight ? -3 : 3) : 0
                dropY: bar.vert ? 0 : (bar.atBottom ? -3 : 3)
                holeRadius: r
                hole: bar.vert
                    ? (bar.atRight ? Qt.rect(-far, 0, far + bar.cornerRadius, height) : Qt.rect(bar.barHeight, 0, far, height))
                    : (bar.atBottom ? Qt.rect(0, -far, width, far + bar.cornerRadius) : Qt.rect(0, bar.barHeight, width, far))
            }
            Rectangle {
                id: bg
                width: bar.vert ? bar.barHeight : parent.width
                height: bar.vert ? parent.height : bar.barHeight
                x: bar.vert ? bar.bgX : 0
                y: bar.vert ? 0 : bar.bgY
                color: bar.barBackground
                // Clicking an empty part of the bar closes any open panel
                MouseArea {
                    anchors.fill: parent
                    onClicked: m => {
                        const onItem = row => {
                            const p = mapToItem(row, m.x, m.y);
                            const c = row.childAt(p.x, p.y);
                            return row.contains(p) && c !== null && !c.isSpace;       // (a flexible space is empty bar)
                        };
                        if (!onItem(left) && bar.popouts) bar.popouts.close();
                    }
                }
            }

            // Concave corners that flare from the bar into the screen edges
            Repeater {
                model: 2
                Canvas {
                    required property int index
                    width: bar.cornerRadius; height: bar.cornerRadius
                    // At the bar's two ends, on its inner side; the shape is drawn for the top
                    // bar's left end and mirrored for the others
                    x: bar.vert ? (bar.atRight ? 0 : bar.barHeight) : (index === 0 ? 0 : parent.width - width)
                    y: bar.vert ? (index === 0 ? 0 : parent.height - height) : (bar.atBottom ? 0 : bar.barHeight)
                    transform: Scale {
                        xScale: bar.vert ? (bar.atRight ? -1 : 1) : (index === 0 ? 1 : -1)
                        yScale: bar.vert ? (index === 0 ? 1 : -1) : (bar.atBottom ? -1 : 1)
                        origin.x: bar.cornerRadius / 2; origin.y: bar.cornerRadius / 2
                    }
                    visible: Config.s.roundedScreenCorners
                    onVisibleChanged: if (visible) requestPaint()
                    // Repaint when the theme colour changes
                    readonly property color fill: bar.barBackground
                    onFillChanged: requestPaint()
                    onAvailableChanged: if (available) requestPaint()
                    onPaint: {
                        const r = bar.cornerRadius, ctx = getContext("2d");
                        ctx.reset();
                        ctx.fillStyle = fill;
                        ctx.beginPath();
                        ctx.moveTo(0, 0);
                        ctx.lineTo(r, 0);
                        ctx.arc(r, r, r, -Math.PI / 2, Math.PI, true);
                        ctx.closePath();
                        ctx.fill();
                    }
                }
            }
        }
        // (Rounded screen corners: ScreenCorners.qml draws all four, over the bar)

        // ---- The line of things along the bar ------------------------------
        // One line, in the order Config.barLayout gives (Settings → Menu Bar): containers, the
        // window's title and flexible spaces, which share whatever room is left.
        // Everything on the bar is written out once below, as it always was; arrange() only
        // decides which of them are on the line and in what order, by handing each to the line
        // in turn (anything not in the arrangement waits, unseen, in `parked`). So the bar
        // looks exactly as it did: Slate's own arrangement is the old left group, the title,
        // one flexible space, and the old right group.
        Component { id: boxComp; Container {} }
        // Where something being dragged would land: one of these sits before each thing on the
        // line and in each container while the bar's being arranged, with no size (the line
        // passes over it) until it's the place aimed at, when it opens to the size of what's
        // carried and the rest part for it
        Component {
            id: slotComp
            Item {
                readonly property bool isSlot: true
                property int to: -1             // the thing on the line it's before (or the container it's in)
                property int slot: -1           // in a container: the item it's before; -1: on the line
                readonly property bool open: !!arranger.gap && arranger.gap.to === to && arranger.gap.slot === slot
                property real len: open ? arranger.gap.len : 0
                Behavior on len { NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutCubic } }
                width: bar.vert ? (len > 0.5 ? bar.capsuleHeight : 0) : len
                height: bar.vert ? len : (len > 0.5 ? bar.capsuleHeight : 0)
                Rectangle {
                    anchors { fill: parent; margins: 2 }
                    visible: parent.len > 6
                    radius: Math.max(0, bar.capsuleRadius - 2)
                    color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.14)
                    Dashes { colour: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.6) }
                }
            }
        }
        Component { id: sepComp; Separator {} }
        // A flexible space: nothing but room on the ordinary bar. While arranging, an outlined
        // gap wide enough to pick up, with arrows in it
        Component {
            id: flexSpace
            Item {
                id: sp
                readonly property bool isSpace: true
                property int index: -1
                property bool carried: false    // being dragged: off the line till it lands
                visible: !carried
                readonly property real len: Math.max(Config.barArranging ? 26 : 0.01, bar.flex)
                width: bar.vert ? (Config.barArranging ? bar.capsuleHeight : 1) : len
                height: bar.vert ? len : (Config.barArranging ? bar.capsuleHeight : 1)
                Rectangle {
                    visible: Config.barArranging
                    anchors.fill: parent
                    radius: bar.capsuleRadius
                    readonly property bool picked: Config.barSelected === sp.index
                    color: picked ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.18) : "transparent"
                    Dashes { picked: parent.picked }
                    Text {
                        anchors.centerIn: parent
                        text: bar.glyph(bar.vert ? 0xEB5B : 0xEB59)
                        color: bar.dimTextColor
                        font.family: bar.iconFont; font.pixelSize: 14
                    }
                }
            }
        }
        BarLine {
            id: left
            opacity: bar.dimmed ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
            spacing: bar.gap
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            // (slid along by bar.scroll while the bar's arranged and too long to show whole)
            x: bar.vert ? bar.bgX + (bar.barHeight - bar.capsuleHeight) / 2 : bar.sidePadding - bar.scroll
            y: bar.vert ? bar.sidePadding - bar.scroll : bar.bgY + (bar.barHeight - bar.capsuleHeight) / 2

            // Everything that can go in a container, by its name in the arrangement
            readonly property var things: ({
                control: flameBtn, apps: appsBtn, spaces: spacesBtn, chalk: chalkBtn, windowmode: wsMode, workspaces: wsCap,
                tray: trayCapsule, notifications: bellBtn, clipboard: clipSeg, screenshot: shotSeg, gamemode: gameSeg,
                keyboard: kbSeg, bluetooth: btSeg, volume: volSeg, wifi: wifiSeg, battery: batSeg, clock: clockCap, power: powerBtn,
                windowicon: winIcon, windowtitle: winTitle, more: moreBtn })
            property var made: []              // the containers and flexible spaces made for this arrangement
            // Put the line in the order the arrangement gives: a container made for each of its
            // containers and handed its things, the title, a flexible space for each "space".
            // Things join the end of a line as they're handed over, so: everything off first
            // (anything the arrangement leaves out stays off, unseen), then each on in its turn
            // A moment after the change that asked for it, not in the same instant: something
            // that has just been switched back on (from the pool, by Defaults) and is moved to
            // another container before it has been drawn once keeps its room there and is never
            // drawn again
            function arrange() { placing.restart(); }
            property bool afresh: false
            Timer { id: placing; interval: 34; onTriggered: left.place() }
            Timer { id: showing; interval: 34; onTriggered: { for (const name in left.things) left.things[name].held = false; } }
            function place() {
                // Each thing goes straight from the container it was in to its new one, never by way
                // of somewhere unseen: one that went out of sight and came back in the same
                // instant was sometimes never drawn again. The old containers go once they're empty
                // And one that wasn't showing where it was (tucked away, say) and will show where
                // it's going stays unseen through the move, and shows a moment after it: shown and
                // moved in the same instant, it was never drawn either
                const old = made;
                // (so does one that was being carried, which is back on the line from here. And
                // all of them when the bar goes into or out of being arranged, or back to Slate's
                // own: should one ever have been left undrawn, that draws it again)
                for (const name in things) { const t = things[name]; t.name = name; t.held = afresh || t.carried || !t.visible || t.opacity < 1; t.carried = false; }
                afresh = false;
                showing.restart();
                // (each with its place in the arrangement, which is what a change is made by)
                let order = Config.barLayout.map((entry, at) => ({ entry: entry, at: at }));
                // A left bar's title reads upwards, growing up from where it sits: where it's
                // followed by a flexible space (Slate's own arrangement), it goes after the
                // space instead, down by what comes next
                if (bar.vert && !bar.atRight) {
                    const t = order.findIndex(o => typeof o.entry !== "string" && o.entry.items.indexOf("windowtitle") >= 0);
                    if (t >= 0 && order[t + 1] && order[t + 1].entry === "space") { const o = order[t]; order[t] = order[t + 1]; order[t + 1] = o; }
                }
                const fresh = [];
                for (const o of order) {
                    const entry = o.entry;
                    if (Config.barArranging) fresh.push(slotComp.createObject(left, { to: o.at }));
                    if (entry === "space") fresh.push(flexSpace.createObject(left, { index: o.at }));
                    else {
                        const box = boxComp.createObject(left, { index: o.at, collapse: entry.collapse || "needed", tuckFrom: entry.tuckFrom || "end" });
                        if (entry.tuckIcon) box.tuckIcon = parseInt(entry.tuckIcon, 16) || 0xEC38;
                        box.fill(entry.items.map(id => things[id]).filter(t => !!t));
                        fresh.push(box);
                    }
                }
                if (Config.barArranging) fresh.push(slotComp.createObject(left, { to: Config.barLayout.length }));
                made = fresh;
                for (const m of old) m.destroy();
                fitLater.restart();
            }
            Component.onCompleted: place()
            Connections { target: Config; function onBarLayoutChanged() { left.arrange(); } function onBarArrangingChanged() { left.afresh = true; left.arrange(); } function onBarRedraw() { left.afresh = true; left.arrange(); } }
            Connections { target: bar; function onVertChanged() { left.arrange(); } function onAtRightChanged() { left.arrange(); } }

        }

        // ---- Arranging: dragging things about on the bar itself --------------------------
        // While the bar's being arranged (Config.barArranging: Settings → Menu Bar → Edit layout), one area lies over the whole
        // line, so nothing under it does its usual thing: a press picks something up. An item
        // inside a container is picked up by itself; a container by its gripper, and a
        // flexible space or the title anywhere, as a whole. Dropped on a container (not at its
        // very ends) an item joins it there; dropped anywhere else, whatever it is goes into the
        // gap, an item in a container of its own. A press without a drag picks the container,
        // for its options in the panel. It works by where things are along the line, and tells
        // Config what moved (barMoveItem, barMoveEntry), which redraws the line. Silent while
        // dragging, a click on the drop, as everywhere.
        MouseArea {
            id: arranger
            anchors.fill: parent
            visible: Config.barArranging
            z: 5
            preventStealing: true
            property var held: null            // { kind: "item" | "entry", name, index, obj, box }
            property bool moved: false
            property real from: 0
            property real at: 0                // where the pointer is, along the line
            property var target: null          // { join, to, slot, at }
            // The gap that's open for what's carried (from here, or from the panel's pool): the
            // slot it is (slotComp), and how long
            property real gapLen: 0
            readonly property var gap: {
                const t = target || carryTarget;
                return t ? { to: t.to, slot: t.join ? t.slot : -1, len: gapLen } : null;
            }
            // The open slot's own place along the line, or null
            function openSlot() {
                const g = gap;
                if (!g) return null;
                let it = null;
                for (const c of left.children) {
                    if (g.slot < 0 && c.isSlot && c.to === g.to) it = c;
                    else if (g.slot >= 0 && c.isBox && c.index === g.to)
                        for (const d of c.row.children) if (d.isSlot && d.slot === g.slot) it = d;
                }
                if (!it || it.len < 2) return null;
                const p = it.mapToItem(left, 0, 0), a = bar.vert ? p.y : p.x;
                return { a0: a, a1: a + (bar.vert ? it.height : it.width) };
            }
            // What's drawn under the pointer for the thing picked up (BarEditor.qml draws it, over
            // everything): its icons, as they are on the bar
            function floatOf(h) {
                const e = Config.barLayout[h.index];
                const icon = id => { const it = Config.barItem(id), t = left.things[id]; return { code: it ? it.icon : 0, item: id, text: id === "windowtitle" ? "Window" : t && !bar.vert ? (t.shownLabel || "") : "" }; };
                if (h.kind === "item" && h.name === "tuck") return { kind: "tuck", icons: [{ code: h.obj.iconCode, item: "" }], label: "" };
                if (h.kind === "item") return { kind: "item", icons: [icon(h.name)], label: "" };
                if (e === "space") return { kind: "space", icons: [{ code: bar.vert ? 0xEB5B : 0xEB59, item: "" }], label: "" };
                return { kind: "box", icons: e.items.filter(id => id !== "tuck" && Config.barShown(id)).map(icon), label: "" };
            }
            function carry(h, on) {
                if (!h) return;
                if (h.obj) h.obj.carried = on;
            }
            function drop() {
                held = null; target = null; moved = false; leaving = false; edge = -1;
                Config.barLeaving = false; Config.barFloat = null;
            }
            function along(p) { return bar.vert ? p.y : p.x; }
            // What's showing on the line, in order, with where each starts and ends along it
            function onLine() {
                const out = [];
                for (const c of left.children) {
                    if (!c.visible) continue;
                    const a = bar.vert ? c.y : c.x, b = a + (bar.vert ? c.height : c.width);
                    if (c.isSpace) out.push({ kind: "space", obj: c, index: c.index, a0: a, a1: b });
                    else if (c.isBox) out.push({ kind: "box", obj: c, index: c.index, a0: a, a1: b });
                }
                return out;
            }
            // A container's showing items, the same way
            function cellsOf(box) {
                const out = [];
                for (const c of box.row.children) {
                    if (!c.visible || !c.name) continue;
                    const p = c.mapToItem(left, 0, 0), a = bar.vert ? p.y : p.x;
                    out.push({ cell: c, a0: a, a1: a + (bar.vert ? c.height : c.width) });
                }
                return out;
            }
            function pick(a) {
                for (const e of onLine()) {
                    if (a < e.a0 || a > e.a1) continue;
                    if (e.kind !== "box") return { kind: "entry", index: e.index, obj: e.obj, box: false };
                    if (a - e.a0 > e.obj.grip + 1)
                        for (const c of cellsOf(e.obj))
                            if (a >= c.a0 && a <= c.a1) return { kind: "item", name: c.cell.name, index: e.index, obj: c.cell, box: true };
                    return { kind: "entry", index: e.index, obj: e.obj, box: true };
                }
                return null;
            }
            // Where something would land at `a` along the line: `joins` for what can go inside a
            // container (an item, a collapse button), which lands there when it's over one
            function aim(a, joins) {
                // (over the gap that's already open: there it stays. The rest have moved to make
                // it, and going by where they are now would send it back and forth)
                const now = openSlot();
                if (now && a >= now.a0 - 2 && a <= now.a1 + 2) return target || carryTarget;
                const line = onLine();
                if (joins) {
                    for (const e of line) {
                        if (e.kind !== "box" || a < e.a0 + 7 || a > e.a1 - 7) continue;
                        const cells = cellsOf(e.obj), items = Config.barLayout[e.index].items;
                        const k = cells.findIndex(c => (c.a0 + c.a1) / 2 > a);
                        const last = cells.length > 0 ? cells[cells.length - 1] : null;
                        return k >= 0 ? { join: true, to: e.index, slot: items.indexOf(cells[k].cell.name), at: cells[k].a0 }
                            : { join: true, to: e.index, slot: last ? items.indexOf(last.cell.name) + 1 : items.length, at: last ? last.a1 : e.a1 };
                    }
                }
                const k = line.findIndex(e => (e.a0 + e.a1) / 2 > a);
                if (k >= 0) return { join: false, to: line[k].index, slot: -1, at: line[k].a0 - bar.gap / 2 };
                const end = line.length > 0 ? line[line.length - 1] : null;
                return { join: false, to: Config.barLayout.length, slot: -1, at: end ? end.a1 + bar.gap / 2 : 0 };
            }
            // (press, move and let go as functions of their own, so a test can drag without a pointer)
            onPressed: m => press(m.x, m.y)
            onPositionChanged: m => { last = Qt.point(m.x, m.y); move(m.x, m.y); }
            onReleased: release()
            // The wheel slides a line that's too long to show whole (either way of scrolling)
            onWheel: w => { const d = Math.abs(w.angleDelta.x) > Math.abs(w.angleDelta.y) ? w.angleDelta.x : w.angleDelta.y; bar.scrollBy(-d * 0.6); }
            // ...and so does carrying something to either end, faster the nearer the edge: `edge`
            // is where what's carried is along the bar itself (below 0: nothing's carried here)
            property point last
            property real edge: -1
            Timer {
                running: arranger.edge >= 0 && bar.scrollMax > 0
                interval: 16; repeat: true
                onTriggered: {
                    const zone = 70, far = bar.lineLength + 2 * bar.sidePadding, a = arranger.edge;
                    const push = a < zone ? -(zone - a) : a > far - zone ? a - (far - zone) : 0;
                    if (push === 0) return;
                    const was = bar.scroll;
                    bar.scrollBy(push * 0.22);
                    if (bar.scroll === was) return;
                    // (the line has moved under what's carried: where it would land is worked out again)
                    if (arranger.held && arranger.moved) arranger.move(arranger.last.x, arranger.last.y);
                    else arranger.carried();
                }
            }
            function press(x, y) {
                const m = Qt.point(x, y);
                const a = along(mapToItem(left, m.x, m.y));
                held = pick(a); from = a; at = a; moved = false; target = null;
            }
            function move(x, y) {
                const m = Qt.point(x, y);
                if (!held) return;
                at = along(mapToItem(left, m.x, m.y));
                if (!moved && Math.abs(at - from) > 5) {
                    // Picked up: it leaves the line (the rest close up, then part where it would
                    // land) and comes with the pointer
                    moved = true;
                    gapLen = bar.vert ? held.obj.height : held.obj.width;
                    Config.barFloat = floatOf(held);
                    carry(held, true);
                }
                if (!moved) return;
                edge = along(mapToItem(content, m.x, m.y));
                const w = mapToItem(null, m.x, m.y), sc = bar.screen;
                Config.barFloatAt = Qt.point((sc ? sc.x : 0) + bar.windowX + w.x, (sc ? sc.y : 0) + bar.windowY + w.y);
                // Well off the bar: let go there and it's back in the pool
                const p = mapToItem(left, m.x, m.y), across = bar.vert ? p.x : p.y;
                leaving = across < -40 || across > bar.capsuleHeight + 40;
                Config.barLeaving = leaving;
                target = leaving ? null : aim(at, held.kind === "item");
            }
            function release() {
                const h = held, t = target, dragged = moved, off = leaving;
                drop();
                // (it stays off the line until the line's laid again with it in its new place; if
                // nothing came of the drag, it goes back where it was)
                if (dragged && !(off || t)) carry(h, false);
                else if (dragged) back.restart();
                if (!h) { Config.barSelected = -1; return; }
                if (!dragged) {              // a press, not a drag: pick it (or let go of it), for its options in the panel
                    Config.barPick(h.index, h.kind === "item" ? h.name : "");
                    Config.click();
                    return;
                }
                if (off) {
                    if (h.kind === "item" && h.name === "tuck") Config.barMoveTuck(h.index, -1, 0);
                    else if (h.kind === "item") Config.barSetShown(h.name, false);
                    else Config.barRemoveEntry(h.index);
                    Config.click();
                    return;
                }
                if (!t) return;
                if (h.kind === "item" && h.name === "tuck") Config.barMoveTuck(h.index, t.join ? t.to : -1, t.slot);
                else if (h.kind === "item") Config.barMoveItem(h.name, t.to, t.join ? t.slot : -1);
                else Config.barMoveEntry(h.index, t.to);
                Config.click();
            }
            onCanceled: { carry(held, false); drop(); }
            // (should a drop change nothing, so the line isn't laid again: back on it)
            Timer { id: back; interval: 300; onTriggered: { for (const n in left.things) left.things[n].carried = false; for (const c of left.children) { if (c.isBox) c.settle(); else if (c.carried) c.carried = false; } } }

            // Something carried here from the pool in the panel beside the bar (BarEditor.qml; Config.barCarry): the
            // page says where the pointer is on the desktop; when that's on or near this bar,
            // this bar says where it would land (and shows the line there). The page drops it
            property bool leaving: false
            property var carryTarget: null
            function carried() {
                const c = Config.barCarry, sc = bar.screen;
                let t = null;
                if (c && sc && Config.barArranging) {
                    // (this bar's window on the desktop: against its edge of its screen)
                    const ox = sc.x + bar.windowX, oy = sc.y + bar.windowY;
                    const g = Config.barCarryAt;
                    const here = g.x >= sc.x && g.x < sc.x + sc.width && g.y >= sc.y && g.y < sc.y + sc.height;
                    const p = left.mapFromItem(null, g.x - ox, g.y - oy);
                    const across = bar.vert ? p.x : p.y;
                    if (here && across > -30 && across < bar.capsuleHeight + 30) {
                        if (!held) edge = along(content.mapFromItem(null, g.x - ox, g.y - oy));
                        const joins = c.kind === "item" || c.kind === "tuck";
                        t = aim(along(p), joins);
                        if (c.kind === "tuck" && !t.join) t = null;      // (a collapse button only goes in a container)
                    }
                }
                if (t && !held) gapLen = c.kind === "space" ? 30 : c.kind === "box" ? 44 : bar.capsuleHeight + 8;
                if (!t && !held) edge = -1;
                carryTarget = t;
                if (t) Config.barCarryTarget = { join: t.join, to: t.to, slot: t.slot, bar: bar };
                else if (Config.barCarryTarget && Config.barCarryTarget.bar === bar) Config.barCarryTarget = null;
            }
            Connections {
                target: Config
                function onBarCarryAtChanged() { arranger.carried(); }
                function onBarCarryChanged() { arranger.carried(); }
            }
        }
        // ---- Everything that can go in a container ---------------------------------
        // Written out here, once each; arrange() hands each to its container on the line above
        // in its turn. Whatever isn't in the arrangement stays here, unseen. (All of them here, none
        // written straight onto the line: a thing taken off a showing line and put back in the
        // same breath kept its place and size but was never drawn again.)
        Item {
            id: parked
            visible: false
            // The focused window, as two things: its icon and its title. Each sits in a container
            // like the rest (together, in Slate's own arrangement). While the pointer's over
            // something on the bar, the title gives a description of that instead (cross-faded:
            // bar.titleFade) and the icon steps out
            Segment {
                id: winIcon
                hover: false
                readonly property var desc: bar.shownItem
                wanted: Config.s.barShowTitleIcon && (Config.barArranging || (!desc && !!appTile.focusedTop))
                length: bar.capsuleHeight + 4
                Item {
                    id: appTile
                    anchors.centerIn: parent
                    width: bar.capsuleHeight; height: bar.capsuleHeight
                    opacity: bar.titleFade
                    readonly property var focusedTop: bar.shownTop
                    readonly property var entry: Config.appEntry(focusedTop ? focusedTop.appId : "")
                    readonly property string winKey: entry ? entry.id : (focusedTop ? focusedTop.appId : "")
                    // (while the bar's being arranged: Slate Settings' own icon, as a stand-in)
                    readonly property string key: Config.barArranging ? "slate-settings" : winIcon.desc ? (winIcon.desc.hoverTile || "") : winKey
                    readonly property string path: Config.tilePath(key)
                    readonly property bool showGlyph: !!winIcon.desc && key === "" && winIcon.desc.hoverCode !== 0
                    readonly property bool showImage: !!winIcon.desc && key === "" && !showGlyph && String(winIcon.desc.hoverImage) !== ""
                    // The focused window came from a space: its tile takes the space's colour
                    // (the whole button, for icon styles with no tile behind the icon)
                    readonly property var space: winIcon.desc || Config.barArranging || !Config.s.spaceBarTint ? null
                        : Spaces.spaceById(Hyprland.activeToplevel ? Spaces.spaceOfAddress[Hyprland.activeToplevel.address] : "")
                    Rectangle {
                        anchors { fill: parent; margins: 2 }
                        radius: Math.max(0, bar.capsuleRadius - 2)
                        visible: !!appTile.space && !tilePlate.visible
                        color: appTile.space ? appTile.space.colour : "transparent"
                    }
                    property int version: 0
                    property string tried: ""      // drawn once per icon file
                    Image {
                        anchors { fill: parent; margins: 3 }
                        visible: appTile.key !== ""
                        source: appTile.key ? "file://" + appTile.path + "?v=" + appTile.version + "." + Config.tileVersion : ""
                        sourceSize: Qt.size(96, 96)
                        smooth: true
                        mipmap: true
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        onStatusChanged: if (status === Image.Error && !tileGen.running && appTile.tried !== appTile.path) { appTile.tried = appTile.path; tileGen.running = true; }
                        // The tile behind, in the theme's colour (or the space's)
                        IconPlate {
                            id: tilePlate
                            anchors.fill: parent; z: -1
                            // (app: IconPlate's own, worked out from the tile image it sits behind)
                            color: appTile.space ? appTile.space.colour : Config.iconTileFor(app, Config.iconPlateColor)
                            shaded: !appTile.space && Config.iconTileShade(app) !== null
                            Behavior on color { ColorAnimation { duration: Config.ms(200) } }
                        }
                        IconGloss {}            // glass: a sheen on the tile, as on the dock's icons
                    }
                    Process {
                        id: tileGen
                        command: Config.tileCommand(appTile.key, appTile.path)
                        onExited: appTile.version++
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appTile.showGlyph
                        text: appTile.showGlyph ? bar.glyph(winIcon.desc.hoverCode) : ""
                        color: bar.textColor
                        font.family: bar.iconFont
                        font.pixelSize: 16
                    }
                    Image {
                        id: hoverImg
                        anchors.centerIn: parent
                        width: 16; height: 16
                        source: appTile.showImage ? winIcon.desc.hoverImage : ""
                        sourceSize: Qt.size(32, 32)
                        visible: appTile.showImage && Config.colourful     // Colourful: its own colours
                    }
                    ShaderEffect {
                        anchors.fill: hoverImg
                        visible: appTile.showImage && !Config.colourful
                        property variant source: hoverImg
                        property real threshold: 0.45
                        property color tint: bar.textColor
                        fragmentShader: Qt.resolvedUrl("shaders/mono.frag.qsb")
                    }
                }
            }
            Segment {
                id: winTitle
                hover: false
                stretchy: true              // (it takes the room the rest of the line doesn't need)
                pad: 18
                readonly property var desc: bar.shownItem
                wanted: Config.s.barShowTitle && (Config.barShowAll || (titleText.text !== "" && !bar.slimTitle))
                // Room for the title: what the line has left once everything else on it has what
                // it needs (the gaps between them included). A long title stops there and fades
                // out rather than running under whatever comes next
                // (all it likes while the bar's arranged: the line scrolls then, if it has to)
                readonly property real room: Config.barShowAll ? 100000 : Math.max(0, bar.lineLength - bar.lineFixed)
                length: (bar.vert ? titleBody.height : titleBody.width) + pad
                // The title (turned to run down a side bar)
                Item {
                    id: titleBody
                    anchors.centerIn: parent
                    opacity: bar.titleFade
                    width: bar.vert ? titleText.height : titleText.width
                    height: bar.vert ? titleText.width : titleText.height
                    Text {
                        id: titleText
                        anchors.centerIn: parent
                        rotation: bar.textRotation
                        width: Math.min(implicitWidth, bar.vert ? 320 : 560, winTitle.room)
                        // Too long for its room: the end fades away (drawn through fadeMask)
                        readonly property bool cut: implicitWidth > width + 0.5
                        layer.enabled: cut
                        // (thresholds set so the mask's soft edge fades the text, rather than
                        // cutting it off wherever the mask isn't fully clear)
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: titleFade; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                        // (while the bar's being arranged it just says what it is, to leave room)
                        text: Config.barArranging ? "Window" : winTitle.desc ? winTitle.desc.hoverText
                            : bar.shownTop ? bar.shownTop.title : ""
                        color: bar.textColor
                        font.family: bar.fontFamily
                        font.pixelSize: bar.fontSize
                        font.weight: Font.Medium
                    }
                    // The title's fade: solid, then clear over its last 32 px (in the text's own
                    // direction, so it works turned down a side bar too)
                    Item {
                        id: titleFade
                        width: titleText.width; height: titleText.height
                        visible: false
                        layer.enabled: titleText.cut
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "white" }
                                GradientStop { position: Math.max(0, 1 - 32 / Math.max(1, titleFade.width)); color: "white" }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                    }
                }
            }

            // Control centre: Slate's mark (a slab of slate, accent along its top edge)
            Segment {
                id: flameBtn
                wanted: Config.s.barShowControl
                length: bar.capsuleHeight + 8
                hoverText: "Control centre"
                hoverImage: "file://" + Quickshell.shellPath("assets/icon/icon-64.png")
                onClicked: bar.openPopout("control", flameBtn)
                onRightClicked: bar.openSlateMenu(flameBtn)
                // Turns white (the text colour) while the control centre is open
                // (the Slate mark, Apps, Spaces and the window mode icon are all drawn 13 px tall,
                // from their top drawn pixel to their bottom one, so they line up)
                SlateMark {
                    anchors.centerIn: parent
                    size: 19.5              // (its drawn part, accent line to slab, 13 px tall)
                    flat: true              // (straight on here; tilted elsewhere)
                    accent: bar.accent
                    body: bar.popoutHere && bar.popouts.current === "control" ? bar.textColor : Config.tint("#566173")
                    Behavior on body { ColorAnimation { duration: Config.ms(220); easing.type: Easing.OutCubic } }
                }
            }
            // Apps: three soft rounded bars
            Segment {
                id: appsBtn
                wanted: Config.s.barShowApps
                length: bar.capsuleHeight + 8
                hoverText: "Apps"
                hoverCode: 0xEC42
                onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "launcher", "toggle"])
                // (in a 16 px slot, as every icon on the bar, but drawn about 13 px, the bars a
                // little thinner: optically matched to the line icons round it)
                Column {
                    anchors.centerIn: parent
                    spacing: 3.5
                    Repeater {
                        model: 3
                        // Colourful look: each bar its own pastel
                        Rectangle {
                            required property int index
                            width: 13; height: 2; radius: height / 2
                            color: Config.partColour(Config.appsPastels, 0, bar.textColor)      // (one pastel for the whole icon)
                        }
                    }
                }
            }

            // Spaces: four small squares (Spaces.qml). While a space is coming back they take
            // its colour and light up in turn
            Segment {
                id: spacesBtn
                wanted: Config.s.barShowSpaces
                length: bar.capsuleHeight + 8
                hoverText: Spaces.restoringSpace ? "Opening " + Spaces.restoringSpace.name + "…" : "Spaces"
                hoverCode: 0xEDBA
                onClicked: bar.openPopout("spaces", spacesBtn)
                property int beat: 0
                Timer { interval: 220; repeat: true; running: Spaces.restoring !== ""; onTriggered: spacesBtn.beat = (spacesBtn.beat + 1) % 4 }
                // Four squares in outline, in the weight of the line icons round them (the window
                // mode's beside it most of all: a frame with lines in it). Drawn here, not from
                // the icon font, so each can light up in turn while a space opens: filled then
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 1.5       // (13 px in all, the drawn height of the icons beside it)
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            readonly property bool busy: Spaces.restoring !== ""
                            width: 5.75; height: 5.75; radius: 1.6
                            // Clockwise: top left, top right, bottom right, bottom left
                            readonly property bool lit: busy && [0, 1, 3, 2][spacesBtn.beat] === index
                            // (Colourful look: one pastel; a space's own colour while it opens)
                            readonly property color ink: busy && Spaces.restoringSpace ? Spaces.restoringSpace.colour : Config.partColour(Config.spacesPastels, 0, bar.textColor)
                            color: lit ? ink : "transparent"
                            border.width: 1.3; border.color: ink
                            antialiasing: true
                            opacity: !busy || lit ? 1 : 0.45
                            Behavior on opacity { NumberAnimation { duration: Config.ms(160) } }
                            Behavior on color { ColorAnimation { duration: Config.ms(200) } }
                            Behavior on border.color { ColorAnimation { duration: Config.ms(200) } }
                        }
                    }
                }
            }

            // Chalk, the assistant (Assistant.qml), while it's switched on: opens its prompt
            // window, and shows a spinner while a prompt is out
            Segment {
                id: chalkBtn
                wanted: Config.s.barShowAssistant && Config.assistantOn
                length: bar.capsuleHeight + 8
                hoverCode: 0xF38A
                hoverText: Config.assistantWorking ? "Chalk is working…" : "Ask Chalk"
                onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "assistant", "toggle"])
                // One pastel in the Colourful look, as Apps and Spaces have (the Assistant page's
                // colour); the text colour otherwise.
                // While Chalk is thinking, Slate's loading spinner takes its place, turning (the
                // spinner Settings and the login screen use; still, with animations off or in
                // game mode)
                // (two items, so the icon is never the one that was turned: as one, it came back at
                // whatever angle the spinner had stopped at)
                Text {
                    anchors.centerIn: parent
                    visible: !Config.assistantWorking
                    text: bar.glyph(0xF38A)
                    color: Config.colourful ? Config.pageColour("assistant") : bar.textColor
                    font.family: bar.iconFont
                    font.pixelSize: 17
                }
                Text {
                    anchors.centerIn: parent
                    visible: Config.assistantWorking
                    text: bar.glyph(0xF226)
                    color: Config.colourful ? Config.pageColour("assistant") : bar.textColor
                    font.family: bar.iconFont
                    font.pixelSize: 17
                    RotationAnimation on rotation {
                        running: Config.assistantWorking && Config.animate && !Config.gameMode
                        loops: Animation.Infinite; from: 0; to: 360; duration: 900
                    }
                }
            }

            // Workspaces: grey/white dots, plus an accent marker that glides between them
            // (WorkspaceMarker).
            // (two things on the bar: the window mode's icon, and the dots)
                  Segment {
                    id: wsMode
                    // (with the dots, as it always was: no dots, no icon)
                    wanted: Config.s.barShowWindowMode && Config.s.barShowWorkspaces
                    readonly property var mode: Config.windowModes.find(m => m.value === Config.focusedMode) ?? Config.windowModes[0]
                    readonly property bool own: !!Config.workspaceModes[String(Config.focusedWorkspaceId)]
                    iconCode: mode.icon
                    // (its drawn part 13 px tall, as the Slate mark, Apps and Spaces beside it:
                    // each mode's icon fills a different share of its height)
                    iconSize: 13 / (mode.ink || 0.75)
                    // Closer in than a status icon: its glyph is drawn larger to match its
                    // neighbours' height, so it carries blank space of its own at the sides
                    pad: 12
                    // A green pastel in the Colourful look, the accent otherwise; its own mode or
                    // the default alike (the panel and the description say which)
                    tint: Config.statusColour("windowmode", bar.accent)
                    hoverText: Config.workspaceLabel(Config.focusedWorkspaceId) + " · " + mode.label
                        + (own ? "" : " (the default)") + " · click to change"
                    onClicked: bar.openPopout("windowmode", wsMode)
                  }
                  // The dots (each with its own hover highlight, behind it)
                  Segment {
                    id: wsCap
                    wanted: Config.s.barShowWorkspaces
                    hover: false
                    readonly property real dot: 14
                    readonly property real dotGap: 5
                    readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
                    readonly property int activeIndex: Math.max(0, spaces.findIndex(w => Hyprland.focusedWorkspace && w.id === Hyprland.focusedWorkspace.id))
                    length: (bar.vert ? wsRow.height : wsRow.width) + 16
                BarLine {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: wsCap.dotGap
                    Repeater {
                        model: wsCap.spaces
                        delegate: Rectangle {
                            id: wsDot
                            required property var modelData
                            readonly property int winCount: modelData.toplevels?.values?.length ?? 0
                            readonly property bool occupied: winCount > 0
                            // Its first window's app, for the hover description's icon: only looked up
                            // while this dot is being described (the lookup can scan every installed
                            // app, and ran for every dot on every window change)
                            readonly property bool described: bar.hoverItem === wsDot || bar.shownItem === wsDot
                            readonly property var firstApp: described && occupied && modelData.toplevels.values[0].wayland ? Config.appEntry(modelData.toplevels.values[0].wayland.appId) : null
                            readonly property string hoverText: Config.workspaceLabel(modelData.id) + " · " + (winCount === 0 ? "empty" : winCount + (winCount === 1 ? " window" : " windows"))
                            readonly property int hoverCode: 0
                            readonly property string hoverTile: firstApp ? firstApp.id : ""
                            readonly property url hoverImage: ""
                            HoverHandler { id: wsDotHover; onHoveredChanged: bar.setHover(wsDot, hovered) }
                            width: wsCap.dot; height: wsCap.dot; radius: Config.dotRadius(wsCap.dot)
                            // Hover: the status icons' highlight, in the dot's shape, behind it
                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                readonly property real size: wsCap.dot + 10
                                width: size; height: size
                                radius: Config.dotRadius(size)
                                color: bar.hoverFill
                                opacity: wsDotHover.hovered ? bar.hoverStrength : 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                            }
                            // Inactive workspaces are dimmed a little; the accent marker shows the active
                            // one. Brighter under the pointer
                            color: wsDotHover.hovered ? (occupied ? Config.tint("#eef1f5") : Config.tint("#8b94a3"))
                                : occupied ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                            Behavior on color { ColorAnimation { duration: Config.ms(150) } }
                            ClickArea { anchors.fill: parent; onClicked: modelData.activate() }
                        }
                    }
                }
                // The accent marker, gliding between dots
                WorkspaceMarker {
                    x: wsRow.x; y: wsRow.y
                    width: wsRow.width; height: wsRow.height
                    dot: wsCap.dot; step: wsCap.dot + wsCap.dotGap
                    index: wsCap.activeIndex
                    vertical: bar.vert
                    color: bar.accent
                }
            }

            // Tray. Collapsed (Settings → Menu Bar): one button that slides open to show the icons,
            // and closes again a few seconds after the pointer leaves (or when clicked)
            Segment {
                id: trayCapsule
                wanted: Config.s.barShowTray && SystemTray.items.values.length > 0
                hover: false
                readonly property bool collapsible: Config.s.barTrayCollapsed
                property bool expanded: false
                onCollapsibleChanged: expanded = false
                // 0 closed … 1 open, eased; the icons stay laid out until it has finished closing
                property real openness: !collapsible || expanded ? 1 : 0
                Behavior on openness { NumberAnimation { duration: Config.ms(280); easing.type: Easing.OutCubic } }
                readonly property bool showIcons: !collapsible || openness > 0
                readonly property real fullLength: (bar.vert ? trayRow.height : trayRow.width) + 10     // 5 px each side
                readonly property real closedLength: 22 + 10
                length: collapsible ? closedLength + (fullLength - closedLength) * openness : fullLength
                clip: collapsible
                HoverHandler { id: trayAreaHover; onHoveredChanged: if (hovered) trayClose.stop(); else if (trayCapsule.expanded) trayClose.restart() }
                // Stays open while one of its apps' menus is open
                Timer { id: trayClose; interval: 4000; onTriggered: if (trayMenuWin.visible) restart(); else trayCapsule.expanded = false }
                BarLine {
                    id: trayRow
                    // Held at the end with the button, so the icons slide out from it
                    x: bar.vert ? (parent.width - width) / 2 : parent.width - width - 5
                    y: bar.vert ? parent.height - height - 5 : (parent.height - height) / 2
                    spacing: 2
                    Repeater {
                        model: trayCapsule.showIcons ? SystemTray.items.values : []
                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            opacity: trayCapsule.openness
                            width: bar.vert ? 22 : 26; height: bar.vert ? 26 : 22
                            readonly property string hoverText: modelData.tooltipTitle || modelData.title || modelData.id || ""
                            readonly property int hoverCode: 0
                            readonly property string hoverTile: ""
                            readonly property url hoverImage: modelData.icon
                            required property int index
                            // Hover highlight: the whole of its part of the container, as the status icons'
                            TrayFill {
                                lit: trayHover.hovered
                                atStart: trayItem.index === 0
                                atEnd: !trayCapsule.collapsible && trayItem.index === SystemTray.items.values.length - 1
                            }
                            HoverHandler { id: trayHover; onHoveredChanged: bar.setHover(trayItem, hovered) }
                            // Icon drawn in high-contrast black and white (light parts white,
                            // dark/coloured parts black) to match the rest of the bar; in the
                            // Colourful look, in its own colours, unless Settings → Menu Bar →
                            // Monochrome tray icons asks for one colour there too
                            readonly property bool mono: !Config.colourful || Config.s.barTrayMono
                            Image {
                                id: trayIcon
                                anchors.centerIn: parent
                                width: 18; height: 18
                                source: trayItem.modelData.icon
                                sourceSize: Qt.size(36, 36)
                                smooth: true
                                visible: !trayItem.mono
                            }
                            ShaderEffect {
                                visible: trayItem.mono
                                anchors.fill: trayIcon
                                property variant source: trayIcon
                                property real threshold: 0.45      // brighter than this takes the text colour
                                property color tint: bar.textColor
                                fragmentShader: Qt.resolvedUrl("shaders/mono.frag.qsb")
                            }
                            // Right-click (or any click, for apps that only have a menu): the app's
                            // menu, drawn by Slate (TrayMenu.qml). Left-click: the app's own action;
                            // middle-click: its other one
                            ClickArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: m => {
                                    const it = trayItem.modelData;
                                    const menuOnly = it.onlyMenu || bar.indicatorIds.includes(it.id);
                                    if (m.button === Qt.RightButton || (m.button === Qt.LeftButton && menuOnly)) {
                                        if (it.hasMenu) bar.openTrayMenu(it.menu, trayItem);
                                        else it.activate();
                                    } else if (m.button === Qt.MiddleButton) it.secondaryActivate();
                                    else it.activate();
                                }
                            }
                        }
                    }
                    // The button that opens and closes it (collapsed tray only). It sits at the
                    // end nearest the rest of the bar, so the icons open out away from it
                    Item {
                        id: trayToggle
                        visible: trayCapsule.collapsible
                        width: 22; height: 22
                        readonly property string hoverText: trayCapsule.expanded ? "Hide the tray" : SystemTray.items.values.length + " tray " + (SystemTray.items.values.length === 1 ? "app" : "apps")
                        readonly property int hoverCode: 0
                        readonly property string hoverTile: ""
                        readonly property url hoverImage: ""
                        TrayFill { lit: toggleHover.hovered; atStart: SystemTray.items.values.length === 0 || !trayCapsule.showIcons; atEnd: true }
                        HoverHandler { id: toggleHover; onHoveredChanged: bar.setHover(trayToggle, hovered) }
                        Text {
                            anchors.centerIn: parent
                            // Points the way the icons open (away from the rest of the bar), turning
                            // round to point back as it opens
                            text: bar.glyph(bar.vert ? 0xEA62 : 0xEA60)
                            rotation: 180 * trayCapsule.openness
                            color: bar.textColor
                            font.family: bar.iconFont; font.pixelSize: 16
                        }
                        ClickTap { onTapped: { trayCapsule.expanded = !trayCapsule.expanded; trayClose.stop(); } }
                    }
                }
            }

            // The status icons: notifications, clipboard, screenshot, game mode, keyboard,
            // Bluetooth, volume, Wi-Fi, battery. Each a thing of its own on the bar; in Slate's
            // own arrangement they share one container
                    // Notifications: crossed-out bell during Do Not Disturb, unread count beside it
                    Segment {
                        id: bellBtn
                        wanted: Config.s.barShowNotifications
                        pastel: "notifications"            // its colour when the look is Colourful
                        iconCode: bar.notifs && bar.notifs.dnd ? 0xECE9 : 0xEA35
                        hoverText: !bar.notifs ? "Notifications"
                            : bar.notifs.dnd ? "Do not disturb is on"
                            : bar.notifs.unread > 0 ? bar.notifs.unread + (bar.notifs.unread === 1 ? " unread notification" : " unread notifications")
                            : "Notifications"
                        // Unread count beside the bell (hidden during Do Not Disturb)
                        sample: "50"
                        label: bar.notifs && bar.notifs.unread > 0 && !bar.notifs.dnd
                            ? (bar.notifs.unread > 99 ? "99+" : String(bar.notifs.unread)) : ""
                        onClicked: bar.openPopout("notifications", bellBtn)
                    }
                    // Clipboard history: how many items it holds; click for the list
                    Segment {
                        id: clipSeg
                        wanted: Config.s.barShowClipboard
                        pastel: "clipboard"            // its colour when the look is Colourful
                        iconCode: Config.s.clipboardHistory ? 0xEA6F : 0xF0CE
                        sample: "12"; textOn: Config.s.barValueClipboard
                        label: Config.s.barValueClipboard && Config.s.clipboardHistory && Config.clipCount > 0 ? String(Config.clipCount) : ""
                        hoverText: !Config.s.clipboardHistory ? "Clipboard history is off"
                            : Config.clipCount === 0 ? "Clipboard · empty"
                            : "Clipboard · " + Config.clipCount + (Config.clipCount === 1 ? " item" : " items")
                        onClicked: bar.openPopout("clipboard", clipSeg)
                    }
                    // Screenshots: click for area / window / screen
                    Segment {
                        id: shotSeg
                        wanted: Config.s.barShowScreenshot
                        pastel: "screenshot"            // its colour when the look is Colourful
                        iconCode: 0xF201
                        hoverText: "Screenshot"
                        onClicked: bar.openPopout("screenshot", shotSeg)
                    }
                    // Game mode: On or Off beside it, lit while it's on; click for the panel to turn it on or off
                    Segment {
                        id: gameSeg
                        wanted: Config.s.barShowGameMode
                        pastel: "gamemode"            // its colour when the look is Colourful
                        iconCode: 0xF1D2
                        sample: "Off"; textOn: Config.s.barValueGameMode
                        label: Config.s.barValueGameMode ? (Config.gameMode ? "On" : "Off") : ""
                        tint: Config.gameMode ? bar.accent : bar.textColor
                        hoverText: Config.gameMode ? "Game mode is on" : "Game mode"
                        onClicked: bar.openPopout("gamemode", gameSeg)
                    }
                    // Keyboard layout: its short code (GB, FR…); click to pick one, scroll to cycle
                    Segment {
                        id: kbSeg
                        wanted: Config.s.barShowKeyboard && Config.kbLayoutList.length > 1
                        pastel: "keyboard"            // its colour when the look is Colourful
                        readonly property var current: Config.kbLayoutList[Config.kbActive] ?? Config.kbLayoutList[0] ?? null
                        iconCode: 0xEBD6
                        sample: "GB"; textOn: Config.s.barValueKeyboard
                        label: Config.s.barValueKeyboard && current ? current.code : ""
                        hoverText: current ? "Keyboard · " + current.name : "Keyboard"
                        onClicked: bar.openPopout("keyboard", kbSeg)
                        onWheel: delta => Config.switchLayout(Config.kbActive + (delta > 0 ? -1 : 1))
                    }
                    // Bluetooth: off / on / something connected; beside it, how many are connected
                    Segment {
                        id: btSeg
                        wanted: Config.s.barShowBluetooth && !!Bluetooth.defaultAdapter
                        pastel: "bluetooth"            // its colour when the look is Colourful
                        readonly property var adapter: Bluetooth.defaultAdapter
                        readonly property bool on: !!adapter && adapter.enabled
                        readonly property var connected: on ? adapter.devices.values.filter(d => d.connected) : []
                        iconCode: !on ? 0xECEB : connected.length > 0 ? 0xECEA : 0xEA37
                        sample: "5"; textOn: Config.s.barValueBluetooth
                        label: Config.s.barValueBluetooth && connected.length > 0 ? String(connected.length) : ""
                        hoverText: !on ? "Bluetooth is off"
                            : connected.length === 0 ? "Bluetooth · nothing connected"
                            : "Bluetooth · " + connected.map(d => d.name || d.deviceName || d.address).join(", ")
                        onClicked: bar.openPopout("bluetooth", btSeg)
                    }
                    Segment {
                        id: volSeg
                        wanted: Config.s.barShowVolume
                        pastel: "volume"            // its colour when the look is Colourful
                        readonly property var sink: Pipewire.defaultAudioSink
                        readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
                        readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
                        tint: muted ? bar.errorColor : bar.textColor
                        iconCode: muted || vol === 0 ? 0xF1C3 : vol > 0.5 ? 0xEB51 : 0xEB4F
                        sample: "50%"; textOn: Config.s.barValueVolume
                        label: Config.s.barValueVolume ? Math.round(vol * 100) + "%" : ""
                        hoverText: "Volume " + Math.round(vol * 100) + "%" + (muted ? " · muted" : "")
                            + (sink && sink.properties && sink.properties["device.profile.description"] ? " · " + sink.properties["device.profile.description"] : "")
                        onClicked: bar.openPopout("volume", volSeg)
                        onWheel: delta => {
                            if (!sink || !sink.audio) return;
                            sink.audio.muted = false;
                            sink.audio.volume = Math.max(0, Math.min(1, vol + (delta > 0 ? 0.05 : -0.05)));
                        }
                        PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
                    }
                    // Wi-Fi: just before the battery
                    Segment {
                        id: wifiSeg
                        wanted: Config.s.barShowWifi
                        pastel: "wifi"            // its colour when the look is Colourful
                        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
                        readonly property var net: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null
                        readonly property real signal: net ? net.signalStrength : 0
                        iconCode: !net ? 0xECFA : signal > 0.66 ? 0xEB52 : signal > 0.33 ? 0xEBA5 : 0xEBA4
                        sample: "Wi-Fi"; textOn: Config.s.barValueWifi
                        label: Config.s.barValueWifi ? (net ? net.name : "Offline") : ""
                        hoverText: net ? "Wi-Fi · " + net.name + " · " + Math.round(signal * 100) + "% signal"
                            : Networking.wifiEnabled ? "Wi-Fi · not connected" : "Wi-Fi is off"
                        onClicked: bar.openPopout("wifi", wifiSeg)
                    }
                    Segment {
                        id: batSeg
                        wanted: Config.s.barShowBattery && !!UPower.displayDevice && UPower.displayDevice.isPresent
                        pastel: "battery"            // its colour when the look is Colourful
                        readonly property var dev: UPower.displayDevice
                        readonly property real pct: dev && dev.ready ? dev.percentage : 0
                        readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge)
                        iconCode: charging || !UPower.onBattery ? 0xEBD9 : pct > 0.8 ? 0xEA32 : pct > 0.55 ? 0xEA31 : pct > 0.3 ? 0xEA30 : 0xEA2F
                        sample: "80%"; textOn: Config.s.barValueBattery
                        label: Config.s.barValueBattery ? Math.round(pct * 100) + "%" : ""
                        hoverText: "Battery " + Math.round(pct * 100) + "% · " + (charging ? "charging" : UPower.onBattery ? "on battery" : "plugged in")
                        onClicked: bar.openPopout("battery", batSeg)
                    }

            // Clock
            Segment {
                id: clockCap
                wanted: Config.s.barShowClock
                length: clock.implicitWidth + 20
                hoverText: Qt.formatDate(Config.clockDate(sysClock.date), "dddd, d MMMM yyyy")
                hoverCode: 0xEA53
                SystemClock { id: sysClock; precision: Config.s.barClockSeconds ? SystemClock.Seconds : SystemClock.Minutes }
                Text {
                    id: clock
                    anchors.centerIn: parent
                    // Turned to run along a side bar, like the window title
                    rotation: bar.textRotation
                    // What it says now, and what's drawn: taken up at the middle of a cross-fade as the
                    // minute (or the format) changes. Counting seconds, it just changes
                    // (short of room, it sheds its date, then its seconds: bar.slimClock)
                    readonly property bool date: Config.s.barClockDate && bar.slimClock < 1
                    readonly property bool seconds: Config.s.barClockSeconds && bar.slimClock < 2
                    readonly property string now: (date ? Qt.formatDate(Config.clockDate(sysClock.date), "ddd d MMM") + "  " : "")
                        + Qt.formatTime(Config.clockDate(sysClock.date), Config.s.barClockFormat === "24h"
                            ? (seconds ? "HH:mm:ss" : "HH:mm")
                            : (seconds ? "h:mm:ss AP" : "h:mm AP"))
                    property string drawn: ""
                    Component.onCompleted: drawn = now
                    text: Config.s.barClockSeconds ? now : drawn
                    // (straight away while the line's being fitted: its length is read as it's tried)
                    onNowChanged: if (Config.s.barClockSeconds || bar.fitting) drawn = now; else if (!clockSwap.running) clockSwap.start()
                    SequentialAnimation {
                        id: clockSwap
                        NumberAnimation { target: clock; property: "opacity"; to: 0; duration: Config.ms(90); easing.type: Easing.InQuad }
                        ScriptAction { script: clock.drawn = clock.now }
                        NumberAnimation { target: clock; property: "opacity"; to: 1; duration: Config.ms(140); easing.type: Easing.OutQuad }
                        onFinished: if (clock.drawn !== clock.now) start()
                    }
                    color: bar.textColor
                    font.family: bar.fontFamily
                    font.pixelSize: bar.fontSize
                    font.weight: Font.Medium
                }
                onClicked: bar.openPopout("calendar", clockCap)
            }

            // More: what holds whatever there isn't room for (bar.overflowed). Only there when
            // something is, or while the bar's arranged, so it can be put where it's wanted
            Segment {
                id: moreBtn
                wanted: bar.overflowed.length > 0 || Config.barShowAll
                iconCode: 0xEA95
                length: bar.capsuleHeight + 8
                hoverText: bar.overflowed.length === 1 ? "1 more thing" : bar.overflowed.length + " more things"
                onClicked: { if (bar.popouts) bar.popouts.moreBar = bar; bar.openPopout("more", moreBtn); }
            }
            Segment {       // power
                id: powerBtn
                wanted: Config.s.barShowPower; iconCode: 0xEB0D; iconSize: 17; tint: bar.errorColor
                length: bar.capsuleHeight + 8
                hoverText: bar.uptimeText()
                onClicked: bar.openPopout("session", powerBtn)
                HoverHandler { onHoveredChanged: if (hovered) uptimeFile.reload() }
            }
        }
    }

    // ---- Building blocks ---------------------------------------------------

    // Hover highlight behind bar items: the accent colour, lightly (as everywhere: Config.hover)
    readonly property color hoverFill: bar.accent
    readonly property real hoverStrength: Config.hoverStrength

    // Rounded container with a soft hover tint and click handling
    // One row across the bar, or one column down a side bar, sized to what it holds (one row
    // or column, left open: a grid counts what it shows itself, and leaves a gap for every
    // column it's told to have, even empty ones)
    component BarLine: Grid {
        columns: bar.vert ? 1 : -1
        rows: bar.vert ? -1 : 1
    }


    component Capsule: Rectangle {
        id: cap
        property bool hoverTint: true
        // Description shown in the title area while hovered ("" = none)
        property string hoverText: ""
        property int hoverCode: 0
        property string hoverTile: ""
        property url hoverImage
        property real length: bar.capsuleHeight      // size along the bar
        signal clicked()
        signal rightClicked()
        width: bar.vert ? bar.capsuleHeight : length
        height: bar.vert ? length : bar.capsuleHeight
        radius: bar.capsuleRadius
        // With a Contents opacity chosen (Settings → Menu Bar → Glass), or a Hover opacity and
        // the pointer over it: drawn solid, and the whole container at that opacity, its fill
        // and everything in it (icons, text, the highlight, the lines between things), faded as
        // one. While the bar's being arranged: solid and at full strength, there to be picked up
        // (`over`: the pointer's on it, or on what it goes with; `fades` false: what it's part of
        // does the fading. Both for the active window's icon, which goes with its title)
        property bool over: capHover.hovered
        property bool fades: true
        readonly property bool lifted: over && Config.barItemHoverSet
        readonly property bool own: !Config.barArranging && (lifted || Config.barItemSet)
        color: own || (Config.barArranging && Config.glass) ? bar.capsuleSolid : bar.capsuleColor
        opacity: !own || !fades ? 1 : lifted ? Config.barItemHoverOpacity : Config.barItemOpacity
        // (each part fades by itself rather than the container as one picture: drawn that way,
        // through a layer, a container showed nothing at all)
        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: bar.hoverFill
            opacity: cap.hoverTint && capHover.hovered ? bar.hoverStrength : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        }
        Gloss { radius: cap.radius; }          // glass: a sheen
        HoverHandler { id: capHover; onHoveredChanged: if (cap.hoverText !== "") bar.setHover(cap, hovered) }
        ClickTap { onTapped: cap.clicked() }
        ClickTap { acceptedButtons: Qt.RightButton; onTapped: cap.rightClicked() }
    }

    // One thing on the bar: a button, an icon with a value, the tray, the dots… It sits in a
    // container (its `shell`, a Container below) alone or with others, and draws the same
    // either way: the container is the rounded shape, and this is its hover fill (rounded where
    // it's at the container's end, fading out where it meets a separator), its icon and value,
    // or whatever is put inside it instead. `wanted`: whether it has anything to show (its
    // switch in Settings, and whether this computer has the thing at all); `length`: its size
    // along the bar, when that isn't just its icon and value.
    component Segment: Item {
        id: seg
        property Item shell: null
        property string name: ""                // what it's called in the arrangement (set as it's placed)
        property bool wanted: true
        property bool isToggle: false           // a container's open/close button (it doesn't fade with the rest)
        property bool hover: true               // false: its parts have hover fills of their own
        property real length: -1
        default property alias inside: custom.data
        readonly property bool plain: custom.children.length === 0
        readonly property bool first: shell ? shell.isFirst(seg) : true
        readonly property bool last: shell ? shell.isLast(seg) : true
        property bool held: false               // (kept unseen for a moment as it's moved: see place())
        property bool carried: false            // being dragged (arranging): off the line till it lands
        property bool stretchy: false           // the window's title: as long as the line has room for
        visible: shell && !held ? shell.shows(seg) : false
        opacity: shell && !isToggle ? shell.openness : 1
        property int iconCode: 0
        property real iconSize: 16
        property string label: ""
        // While the bar's being arranged, a thing with its text on always has some to show, so
        // it's seen as it will be: its own, or an example (`sample`) when there's none just now
        // (nothing unread, no devices connected). `textOn`: its text isn't switched off
        property string sample: ""
        property bool textOn: true
        readonly property string exampleLabel: label !== "" ? label : sample
        readonly property string shownLabel: !Config.barArranging ? label : textOn ? exampleLabel : ""
        // What's drawn: the same, taken up at the middle of a cross-fade, so a change of text
        // (the volume, a network's name) fades from the old to the new. Changes that come
        // while one's under way are picked up by it, or by another straight after
        property string drawnLabel: ""
        property bool slimText: false           // short of room: its text is put away (bar.fit)
        property bool overflowed: false         // ...or it has left the bar for More
        readonly property real labelLength: segLabel.implicitWidth + 6
        function relayout() { segRow.forceLayout(); }
        Component.onCompleted: drawnLabel = shownLabel
        onShownLabelChanged: if (!labelSwap.running) labelSwap.start()
        SequentialAnimation {
            id: labelSwap
            NumberAnimation { target: segLabel; property: "opacity"; to: 0; duration: Config.ms(90); easing.type: Easing.InQuad }
            ScriptAction { script: seg.drawnLabel = seg.shownLabel }
            NumberAnimation { target: segLabel; property: "opacity"; to: 1; duration: Config.ms(140); easing.type: Easing.OutQuad }
            onFinished: if (seg.drawnLabel !== seg.shownLabel) start()
        }
        property color tint: bar.textColor
        // Colourful look: the icon in this pastel (Config.statusPastels), unless it's showing a
        // warning colour (tint other than the text colour)
        property string pastel: ""
        property string hoverText: ""
        property int hoverCode: iconCode
        property string hoverTile: ""
        property url hoverImage
        signal clicked()
        signal rightClicked()
        signal wheel(real delta)
        // Icon and value across a top/bottom bar; just the icon, stacked, on a side bar. pad: the
        // space beside the icon, both sides together
        property real pad: 20
        width: bar.vert ? bar.capsuleHeight : length >= 0 ? length : segRow.width + pad
        height: bar.vert ? (length >= 0 ? length : segRow.height + 14) : bar.capsuleHeight

        // Hover fill: solid at the group's rounded ends, fading out at the
        // square sides that meet a separator
        Rectangle {
            id: segFill
            anchors.fill: parent
            readonly property real fade: Math.min(0.45, 12 / Math.max(1, width))   // ~12px soft edge
            gradient: Gradient {
                orientation: bar.vert ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: seg.first ? bar.hoverFill : "transparent" }
                GradientStop { position: segFill.fade; color: bar.hoverFill }
                GradientStop { position: 1 - segFill.fade; color: bar.hoverFill }
                GradientStop { position: 1.0; color: seg.last ? bar.hoverFill : "transparent" }
            }
            topLeftRadius: seg.first ? bar.capsuleRadius : 0
            bottomLeftRadius: (bar.vert ? seg.last : seg.first) ? bar.capsuleRadius : 0
            topRightRadius: (bar.vert ? seg.first : seg.last) ? bar.capsuleRadius : 0
            bottomRightRadius: seg.last ? bar.capsuleRadius : 0
            opacity: seg.hover && segHover.hovered ? bar.hoverStrength : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        }
        // Picked, while the bar's being arranged: lit in the accent colour, with an outline
        Rectangle {
            visible: Config.barArranging && !!seg.shell && Config.barSelected === seg.shell.index && Config.barSelectedItem === seg.name && seg.name !== ""
            anchors { fill: parent; margins: 2 }
            radius: Math.max(0, bar.capsuleRadius - 2)
            color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.18)
            border.width: 2; border.color: bar.accent
        }
        // What's put inside it, in place of the icon and value
        Item { id: custom; anchors.fill: parent }
        Row {
            id: segRow
            visible: seg.plain
            anchors.centerIn: parent
            // No gap when there's no label, so a lone icon sits in the middle
            spacing: seg.drawnLabel !== "" && !bar.vert && !seg.slimText ? 6 : 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: bar.glyph(seg.iconCode)
                color: seg.pastel !== "" && Qt.colorEqual(seg.tint, bar.textColor) ? Config.statusColour(seg.pastel, seg.tint) : seg.tint
                font.family: bar.iconFont
                font.pixelSize: seg.iconSize
            }
            Text {
                id: segLabel
                visible: seg.drawnLabel !== "" && !bar.vert && !seg.slimText
                anchors.verticalCenter: parent.verticalCenter
                text: seg.drawnLabel
                color: seg.tint
                font.family: bar.fontFamily
                font.pixelSize: bar.fontSize
                font.weight: Font.Medium
            }
        }
        HoverHandler { id: segHover; onHoveredChanged: if (seg.hoverText !== "") bar.setHover(seg, hovered) }
        ClickTap { onTapped: seg.clicked() }
        ClickTap { acceptedButtons: Qt.RightButton; onTapped: seg.rightClicked() }
        WheelHandler { onWheel: e => seg.wheel(e.angleDelta.y) }
    }

    // A container on the bar: the rounded shape, holding one thing or several in a row with a
    // line between each. Made by the line for each container in the arrangement (arrange()),
    // which hands it its things in order. It can tuck them away behind one button that slides
    // them open, closing again a few seconds after the pointer leaves (or when clicked).
    component Container: Capsule {
        id: box
        readonly property bool isBox: true
        property int index: -1                  // its place in the arrangement
        property var cells: []                  // its things, in order
        // Being arranged (Config.barArranging): outlined, brighter when it's the one
        // picked, with a gripper at its start to move it whole by. Only then: the ordinary bar
        // has neither
        readonly property real grip: Config.barArranging ? 14 : 0
        // (an outline of its own, not the shape's border: giving the shape a border, even of
        // no width, changed how its edge was drawn by a few pixels)
        Rectangle {
            visible: Config.barArranging
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            Dashes { picked: box.picked }
        }
        // (picked as a whole, by its gripper: one of its things picked lights that instead)
        readonly property bool picked: Config.barSelected === box.index && Config.barSelectedItem === ""
        Text {
            visible: Config.barArranging
            x: bar.vert ? (parent.width - width) / 2 : (box.grip - width) / 2 + 1
            y: bar.vert ? (box.grip - height) / 2 + 1 : (parent.height - height) / 2
            text: bar.glyph(bar.vert ? 0xEC00 : 0xEC01)
            color: box.picked ? bar.accent : bar.dimTextColor
            font.family: bar.iconFont; font.pixelSize: 13
        }
        // How it collapses (Config.barBox): "always" tucked behind its button until that's clicked;
        // "needed", only when the bar's short of room and has asked it to (needTuck, from bar.fit),
        // and only with two things or more to tuck; "never"
        property string collapse: "needed"
        property bool needTuck: false
        readonly property bool always: collapse === "always"
        readonly property bool tuck: always || (collapse === "needed" && needTuck && !Config.barShowAll)
        property string tuckFrom: "end"         // "start": the button first, the things after it; else last
        property int tuckIcon: 0xEC38
        hoverTint: false                        // (each thing has its own hover fill)
        property bool expanded: false
        onTuckChanged: expanded = false
        // 0 closed … 1 open, eased; the things stay laid out until it has finished closing
        // (open while the bar's being arranged, so what's in it can be got at)
        // (...unless it's being tried shorter, when it closes as it would)
        property real openness: !tuck || expanded || Config.barShowAll ? 1 : 0
        Behavior on openness { NumberAnimation { duration: Config.ms(280); easing.type: Easing.OutCubic } }
        readonly property bool showThings: !tuck || openness > 0
        // Along the container: its things, and the button at one end while it tucks
        // (the button's always among them, unseen unless it tucks: a container can start to at any time)
        readonly property var order: tuckFrom === "start" ? [toggle].concat(cells) : cells.concat([toggle])
        // As long as it will be once it's settled (opening and closing are eased): what the line
        // is fitted by
        readonly property real settledLength: (tuck ? closedLength : stretchyCell ? fixedLength - grip : fullLength) + grip
        function shows(c) { return !c.carried && !c.overflowed && (c === toggle ? tuck : (c.wanted && showThings)); }
        property bool carried: false            // being dragged (arranging): off the line till it lands
        function isFirst(c) { const i = order.indexOf(c); for (let k = 0; k < i; k++) if (shows(order[k])) return false; return true; }
        function isLast(c) { const i = order.indexOf(c); for (let k = i + 1; k < order.length; k++) if (shows(order[k])) return false; return true; }
        function sepBefore(c) { return shows(c) && !isFirst(c); }
        // (one fresh from the pool, with nothing in it yet, shows while the bar's being arranged)
        readonly property bool hollow: Config.barArranging && cells.length === 0
        visible: !carried && (cells.some(c => c.wanted && !c.carried && !c.overflowed) || hollow)
        function settle() { carried = false; toggle.carried = false; }
        function relayout() { for (const c of cells) c.relayout(); toggle.relayout(); row.forceLayout(); }
        // Holding the window's title: how long it is without the title's own text (the things
        // beside it, the title's padding, a line between each two, the gripper), which is what
        // the line counts when it works out the title's room
        readonly property var stretchyCell: cells.find(c => c.stretchy && shows(c)) || null
        readonly property real fixedLength: {
            let sum = grip, n = 0;
            for (const c of order) {
                if (!shows(c)) continue;
                n++;
                sum += c.stretchy ? c.pad : (bar.vert ? c.height : c.width);
            }
            return sum + Math.max(0, n - 1);
        }
        readonly property real fullLength: hollow ? Math.max(30, bar.vert ? row.height : row.width) : bar.vert ? row.height : row.width
        readonly property real closedLength: bar.vert ? toggle.height : toggle.width
        length: (tuck ? closedLength + (fullLength - closedLength) * openness : fullLength) + grip
        clip: tuck
        HoverHandler { onHoveredChanged: if (hovered) closing.stop(); else if (box.expanded) closing.restart() }
        // Stays open while one of its panels is open
        Timer { id: closing; interval: 4000; onTriggered: if (bar.popoutHere) restart(); else box.expanded = false }
        BarLine {
            id: row
            // Held at the end with the button, so the things slide out from it
            x: bar.vert ? 0 : box.tuckFrom === "start" ? box.grip : parent.width - width
            y: !bar.vert ? 0 : box.tuckFrom === "start" ? box.grip : parent.height - height
        }
        property alias row: row
        // The button that opens and closes it (while it tucks)
        Segment {
            id: toggle
            shell: box
            // (no name in the arrangement: it isn't picked up by itself. It's its container's, set
            // up in the container's options)
            isToggle: true
            iconCode: box.tuckIcon
            hoverText: box.expanded ? "Hide these" : box.cells.filter(c => c.wanted).map(c => c.hoverText.split(" · ")[0]).filter(t => t).slice(0, 3).join(", ") + (box.cells.length > 3 ? " and more" : "")
            onClicked: { box.expanded = !box.expanded; closing.stop(); }
        }
        // Take its things, in order, with a line before each but the first
        function fill(things) {
            cells = things;
            const seq = order;
            // (a place to land before each thing, numbered as the arrangement's items are: the
            // button is one of them only in a container that always tucks)
            let n = 0;
            for (let i = 0; i < seq.length; i++) {
                const counted = seq[i] !== toggle || box.always;
                if (Config.barArranging && counted) slotComp.createObject(row, { to: box.index, slot: n });
                if (i > 0) sepComp.createObject(row, { shell: box, cell: seq[i] });
                seq[i].shell = box;
                seq[i].parent = row;
                if (counted) n++;
            }
            if (Config.barArranging) slotComp.createObject(row, { to: box.index, slot: n });
        }
    }

    // The highlight under the pointer for one of the tray's icons (or its open/close button):
    // the full height of the container over that icon's share of it, as a status icon's is.
    // Rounded where it's at the container's own end, fading out where it meets its neighbour
    component TrayFill: Rectangle {
        id: tf
        property bool lit: false
        property bool atStart: false        // the first thing in the tray (5 px in from its edge)
        property bool atEnd: false
        readonly property bool endFirst: atStart && trayCapsule.first
        readonly property bool endLast: atEnd && trayCapsule.last
        readonly property real before: atStart ? 5 : 1      // (to the tray's edge, or half the gap between icons)
        readonly property real after: atEnd ? 5 : 1
        readonly property real across: bar.capsuleHeight
        x: bar.vert ? (parent.width - across) / 2 : -before
        y: bar.vert ? -before : (parent.height - across) / 2
        width: bar.vert ? across : parent.width + before + after
        height: bar.vert ? parent.height + before + after : across
        readonly property real fade: Math.min(0.45, 10 / Math.max(1, bar.vert ? height : width))
        gradient: Gradient {
            orientation: bar.vert ? Gradient.Vertical : Gradient.Horizontal
            GradientStop { position: 0.0; color: tf.endFirst ? bar.hoverFill : "transparent" }
            GradientStop { position: tf.fade; color: bar.hoverFill }
            GradientStop { position: 1 - tf.fade; color: bar.hoverFill }
            GradientStop { position: 1.0; color: tf.endLast ? bar.hoverFill : "transparent" }
        }
        topLeftRadius: endFirst ? bar.capsuleRadius : 0
        bottomLeftRadius: (bar.vert ? endLast : endFirst) ? bar.capsuleRadius : 0
        topRightRadius: (bar.vert ? endFirst : endLast) ? bar.capsuleRadius : 0
        bottomRightRadius: endLast ? bar.capsuleRadius : 0
        opacity: lit ? bar.hoverStrength : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
    }

    // A dashed outline round its parent (a Rectangle: it takes its rounding), for the things
    // marked out while the bar's being arranged: containers, flexible spaces, the active
    // window, the place something would land. Heavier, in the full accent, round the one picked
    component Dashes: Shape {
        id: dashes
        property bool picked: false
        property color colour: picked ? bar.accent : Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.55)
        readonly property real line: picked ? 2 : 1
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: dashes.colour
            strokeWidth: dashes.line
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 2.5]
            fillColor: "transparent"
            PathRectangle {
                x: dashes.line / 2; y: dashes.line / 2
                width: Math.max(0, dashes.width - dashes.line); height: Math.max(0, dashes.height - dashes.line)
                radius: Math.max(0, (dashes.parent && dashes.parent.radius !== undefined ? dashes.parent.radius : 0) - dashes.line / 2)
            }
        }
    }

    // The line between two things in a container: shown when the thing after it shows and
    // isn't the first
    component Separator: Item {
        property var shell: null
        property var cell: null
        visible: shell && cell ? shell.sepBefore(cell) : true
        width: bar.vert ? bar.capsuleHeight : 1
        height: bar.vert ? 1 : bar.capsuleHeight
        Rectangle {
            anchors.centerIn: parent
            width: bar.vert ? parent.width * 0.5 : 1
            height: bar.vert ? 1 : parent.height * 0.5
            color: bar.separatorColor
        }
    }
}
