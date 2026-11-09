// Slate's menu bar: workspaces, the focused window's title, tray, status, clock and power.
//
// Auto-hide (Settings → Menu bar): while hidden the bar reserves no space, so windows use
// the whole screen; pushing the pointer against the bar's screen edge slides it in and moves
// the windows aside to make room, and it slides away again shortly after the pointer leaves
// (it stays while one of its panels is open). `slate ipc call bar reveal` shows it for a few
// seconds.

import QtQuick
import QtQuick.Effects
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
    // Rounded screen corners: a squircle (superellipse) shape
    readonly property real screenCornerRadius: 17
    readonly property real screenCornerShape: 3.0
    // Outside the rounded screen corners: always black, in both themes
    readonly property color screenCornerColor: "#000000"
    // (See-through with glass: Settings → Appearance → Glass)
    readonly property color barColor: Config.surface(Config.tint("#0f1216"))
    // In light mode a shade deeper than other fields, to stand out from the tinted bar
    readonly property color capsuleColor: Config.raised(Config.tint(Config.s.lightMode ? "#262c35" : "#1d222a"))
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimColor: Config.tint("#c5ccd6")
    readonly property color accent: Config.accent
    readonly property color errorColor: Config.tint("#f28b8b")
    readonly property color separatorColor: Config.tint("#444c58")
    readonly property color emptyDot: Config.tint("#5f6876")
    readonly property string fontFamily: Config.s.fontFamily   // Settings → Appearance → Fonts
    readonly property real fontSize: 13              // Settings → Interface size scales it with everything else
    readonly property string iconFont: tabler.name
    readonly property int holdMs: 4000
    readonly property int slideMs: 500
    readonly property string tileScript: Config.tileScript
    readonly property string tileDir: Config.tileDir

    // Drop-down panels (Popouts.qml), set from shell.qml
    property var popouts: null
    property var notifs: null
    // Each screen has a bar; the primary one answers `slate ipc call bar …` and passes it
    // to the bar on the focused screen
    property bool primary: true
    Component.onCompleted: Config.bars = Config.bars.concat([bar])
    Component.onDestruction: Config.bars = Config.bars.filter(b => b !== bar)
    // A panel is open from this bar (the panels go to whichever screen opened them)
    // (from the start of opening, so the bar is done changing before the panel slides)
    readonly property bool popoutHere: !!popouts && popouts.engaged && popouts.screen === bar.screen
    function openPopout(name, item) {
        if (!popouts) return;
        const p = item.mapToItem(content, item.width / 2, item.height / 2);   // from the screen edge
        popouts.toggle(name, p.x, p.y, bar.screen);
    }
    // With more than one screen, the bars on screens without focus are dimmed
    readonly property bool dimmed: Quickshell.screens.length > 1 && !!screen
        && !(Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === screen.name)

    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    function glyph(code) { return String.fromCodePoint(code); }

    // ---- Window ------------------------------------------------------------
    // Which screen edge (Settings → Menu bar → Position). Laid out for the top; at the bottom
    // the curves and corners flip, and on a side the groups stack top to bottom, the status
    // icons drop their text, the clock stacks and the window title is turned to run along it.
    readonly property string side: Config.barEdge
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
    Behavior on shadow { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    // Text along a side bar is turned to read top to bottom on the right, bottom to top on the left
    readonly property real textRotation: vert ? (atRight ? 90 : -90) : 0
    anchors { top: side !== "bottom"; bottom: side !== "top"; left: side !== "right"; right: side !== "left" }
    implicitHeight: vert ? 0 : thickness + shadowPad
    implicitWidth: vert ? thickness + shadowPad : 0
    color: "transparent"
    WlrLayershell.namespace: "slate-bar"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Math.round(barHeight * zoneReveal)
    mask: Region { item: hitArea }

    // ---- Auto-hide state ---------------------------------------------------
    property bool filled: false          // one window fills the workspace (from Hyprland)
    readonly property bool hovered: hover.hovered
    Timer { id: holdTimer; interval: bar.holdMs }        // shown after fill / workspace switch
    Timer { id: hoverTimer; interval: 700 }              // lingers a moment after the pointer leaves
    onHoveredChanged: if (!hovered) hoverTimer.restart()

    // Reserved space follows the "held" state; hover only slides the bar over the window
    // Auto-hide only applies when it's switched on in Settings
    readonly property bool autoHiding: Config.s.barAutoHide
    // Reserved space follows the bar: while auto-hiding, windows get the whole screen, and when
    // the bar slides in they're pushed aside to make room (and grow back when it leaves)
    property real zoneReveal: reveal
    property real reveal: !autoHiding || holdTimer.running || hovered || hoverTimer.running || popoutHere || trayMenuWin.visible ? 1 : 0
    Behavior on zoneReveal { NumberAnimation { duration: bar.slideMs; easing.type: Easing.InOutCubic } }
    Behavior on reveal { NumberAnimation { duration: bar.slideMs; easing.type: Easing.InOutCubic } }

    function setFilled(value) {
        if (value && !filled) holdTimer.restart();
        filled = value;
    }
    function revealNow() { if (autoHiding) holdTimer.restart(); }
    function openPanel(name) {
        const button = ({ control: flameBtn, spaces: spacesBtn, notifications: bellBtn, session: powerBtn,
                          volume: volSeg, wifi: wifiSeg, clipboard: clipSeg, screenshot: shotSeg, keyboard: kbSeg, bluetooth: btSeg, battery: batSeg, calendar: clockCap })[name];
        if (button) openPopout(name, button);
    }
    // Tray apps with no "activate" of their own: Ayatana app indicators (Steam and others)
    // only have a menu, so clicking them shows it, as KDE does. Found by their D-Bus paths,
    // whose last part is the item's id
    property var indicatorIds: []
    Process {
        id: indicatorQuery
        command: ["busctl", "--user", "--json=short", "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                  "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    bar.indicatorIds = JSON.parse(text).data.filter(x => x.includes("/org/ayatana/NotificationItem/"))
                        .map(x => x.split("/").pop());
                } catch (e) {}
            }
        }
    }
    Timer { id: indicatorLater; interval: 800; running: true; onTriggered: { indicatorQuery.running = false; indicatorQuery.running = true; } }
    Connections { target: SystemTray.items; function onValuesChanged() { indicatorLater.restart(); } }

    // App tray menus (TrayMenu.qml), opened from a tray icon at its centre on the bar's inner edge
    TrayMenu { id: trayMenuWin; bar: bar }
    function openTrayMenu(menu, item) {
        // The icon's centre in the bar's window, then on the screen (the bar's window sits
        // against its edge of the screen)
        const p = item.mapToItem(bar.contentItem, item.width / 2, item.height / 2);
        const sw = bar.screen ? bar.screen.width : 0, sh = bar.screen ? bar.screen.height : 0;
        let x = p.x + (bar.side === "right" ? sw - bar.width : 0);
        let y = p.y + (bar.side === "bottom" ? sh - bar.height : 0);
        // To the bar's inner edge, where the menu's pointer meets it
        if (bar.side === "top") y = bar.barHeight;
        else if (bar.side === "bottom") y = sh - bar.barHeight;
        else if (bar.side === "left") x = bar.barHeight;
        else x = sw - bar.barHeight;
        trayMenuWin.openFor(menu, x, y);
    }
    // The Slate button's right-click menu: quick access to useful things
    function openSlateMenu(item) {
        if (bar.popouts) bar.popouts.close();
        const slate = args => () => Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call"].concat(args));
        const notifs = bar.popouts ? bar.popouts.notifs : null;
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
            { text: "Restart Slate", glyph: 0xEB13, action: () => Quickshell.reload(true) },
            { text: "Show the welcome", glyph: 0xEDBA, action: slate(["welcome", "open"]) },
            { separator: true },
            { text: "Lock screen", glyph: 0xEAE2, action: slate(["lock", "lock"]) },
            { text: "Log out…", glyph: 0xEBA8, action: slate(["power", "confirm", "logout"]) },
            { text: "About Slate", glyph: 0xEAC5, action: slate(["settings", "page", "about"]) }
        ];
        const p = item.mapToItem(bar.contentItem, item.width / 2, item.height / 2);
        const sw = bar.screen ? bar.screen.width : 0, sh = bar.screen ? bar.screen.height : 0;
        let x = p.x + (bar.side === "right" ? sw - bar.width : 0);
        let y = p.y + (bar.side === "bottom" ? sh - bar.height : 0);
        if (bar.side === "top") y = bar.barHeight;
        else if (bar.side === "bottom") y = sh - bar.barHeight;
        else if (bar.side === "left") x = bar.barHeight;
        else x = sw - bar.barHeight;
        trayMenuWin.openList(list, x, y);
    }
    function focusedBar() { return Config.barFor(Config.focusedScreen) || bar; }
    IpcHandler {
        target: "bar"
        enabled: bar.primary
        // Hyprland's notes and requests are for the focused screen's bar
        function setFilled(value: bool): void { bar.focusedBar().setFilled(value); }
        function reveal(): void { bar.focusedBar().revealNow(); }
        // Open (or close) one of the bar's panels under its button, e.g.
        //   slate ipc call bar panel control
        // names: control, spaces, notifications, session, volume, wifi, keyboard, bluetooth, battery, calendar
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
    }

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
        NumberAnimation { target: titleArea; property: "opacity"; to: 0; duration: 90; easing.type: Easing.InQuad }
        ScriptAction { script: bar.shownItem = bar.hoverItem }
        NumberAnimation { target: titleArea; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutQuad }
    }

    // Uptime, for the power button's hover text (refreshed each minute)
    FileView { id: uptimeFile; path: "/proc/uptime" }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: uptimeFile.reload() }
    function uptimeText() {
        const sec = parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return "Up " + (d > 0 ? d + (d === 1 ? " day " : " days ") : "") + (h > 0 || d > 0 ? h + " h " : "") + m + " min";
    }

    // ---- Helpers -----------------------------------------------------------
    function run(cmd) { runner.command = cmd; runner.running = true; }
    Process { id: runner }

    function lookup(appId) {
        if (!appId) return null;
        const e = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        if (e) return e;
        const parts = appId.toLowerCase().split(".");
        if (parts.length < 3) return null;
        const prefix = parts.slice(0, 2).join(".") + ".";
        return DesktopEntries.applications.values.find(a => a.id.toLowerCase().startsWith(prefix)) ?? null;
    }

    // ---- Drawing -----------------------------------------------------------
    Item {
        id: content
        width: bar.vert ? bar.thickness : parent.width
        height: bar.vert ? parent.height : bar.thickness
        // Against the screen edge (the window's extra room, for the shadow, is on the inside)
        x: bar.vert && bar.atRight ? bar.shadowPad : 0
        y: !bar.vert && bar.atBottom ? bar.shadowPad : 0
        // Hides by sliding off its screen edge
        transform: Translate {
            x: bar.vert ? (bar.atRight ? 1 : -1) * bar.thickness * (1 - bar.reveal) : 0
            y: bar.vert ? 0 : (bar.atBottom ? 1 : -1) * bar.thickness * (1 - bar.reveal)
        }

        // The bar's shape (band and curved corners), casting a drop shadow on hover or while
        // a panel is open
        Item {
            anchors.fill: parent
            // On the whole time a panel from this bar is shown (from before it slides), so the
            // shadow's blur is set up once, not as it slides (that held the slide up)
            // Never with glass, which has no shadow: switching the layer on (on hover) changed how
            // the see-through bar was drawn, and it lit up
            layer.enabled: !Config.glass && (bar.shadow > 0.01 || (!!bar.popouts && bar.popouts.active && bar.popouts.screen === bar.screen))
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "black"
                shadowOpacity: Config.glass ? 0 : (Config.s.lightMode ? 0.22 : 0.5) * bar.shadow
                shadowBlur: 0.9
                blurMax: 24
                shadowHorizontalOffset: bar.vert ? (bar.atRight ? -4 : 4) : 0
                shadowVerticalOffset: bar.vert ? 0 : (bar.atBottom ? -4 : 4)
            }
            Rectangle {
                id: bg
                width: bar.vert ? bar.barHeight : parent.width
                height: bar.vert ? parent.height : bar.barHeight
                x: bar.vert ? bar.bgX : 0
                y: bar.vert ? 0 : bar.bgY
                color: bar.barColor

                // Clicking an empty part of the bar closes any open panel
                MouseArea {
                    anchors.fill: parent
                    onClicked: m => {
                        const onItem = row => {
                            const p = mapToItem(row, m.x, m.y);
                            return row.contains(p) && row.childAt(p.x, p.y) !== null;
                        };
                        if (!onItem(left) && !onItem(right) && bar.popouts) bar.popouts.close();
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
                    readonly property color fill: bar.barColor
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
        // Rounded screen corners at the top (black outside the curve), to match
        // the rounded corners at the bottom of the screen
        Repeater {
            model: 2
            Canvas {
                required property int index
                readonly property real r: bar.screenCornerRadius
                z: 10
                // Make sure it paints after loading / reloading
                onAvailableChanged: if (available) requestPaint()
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()
                width: r; height: r
                // The two screen corners at the bar's edge
                x: bar.vert ? (bar.atRight ? parent.width - r : 0) : (index === 0 ? 0 : parent.width - width)
                y: bar.vert ? (index === 0 ? 0 : parent.height - r) : (bar.atBottom ? parent.height - r : 0)
                transform: Scale {
                    xScale: bar.vert ? (bar.atRight ? -1 : 1) : (index === 0 ? 1 : -1)
                    yScale: bar.vert ? (index === 0 ? 1 : -1) : (bar.atBottom ? -1 : 1)
                    origin.x: r / 2; origin.y: r / 2
                }
                visible: Config.s.roundedScreenCorners
                onVisibleChanged: if (visible) requestPaint()
                readonly property color fill: bar.screenCornerColor
                onFillChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d"), n = bar.screenCornerShape;
                    ctx.reset();
                    ctx.fillStyle = fill;
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(r, 0);
                    // Squircle edge from the top (r, 0) round to the side (0, r)
                    for (let i = 0; i <= 48; i++) {
                        const t = Math.PI / 2 * (1 - i / 48);
                        ctx.lineTo(r - r * Math.pow(Math.cos(t), 2 / n), r - r * Math.pow(Math.sin(t), 2 / n));
                    }
                    ctx.closePath();
                    ctx.fill();
                }
            }
        }

        // ---- Left side ---------------------------------------------------
        Grid {
            id: left
            opacity: bar.dimmed ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            spacing: bar.gap
            // One row across the bar, or one column down a side bar, sized to what it holds
            // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
            // for every column it's told to have, even empty ones)
            columns: bar.vert ? 1 : -1
            rows: bar.vert ? -1 : 1
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            x: bar.vert ? bar.bgX + (bar.barHeight - bar.capsuleHeight) / 2 : bar.sidePadding
            y: bar.vert ? bar.sidePadding : bar.bgY + (bar.barHeight - bar.capsuleHeight) / 2

            // Control centre: Slate's mark (a slab of slate, accent along its top edge)
            Capsule {
                id: flameBtn
                length: bar.capsuleHeight + 8
                hoverText: "Control centre"
                hoverImage: "file://" + Quickshell.shellPath("assets/icon/icon-64.png")
                onClicked: bar.openPopout("control", flameBtn)
                onRightClicked: bar.openSlateMenu(flameBtn)
                // Turns white (the text colour) while the control centre is open
                SlateMark {
                    anchors.centerIn: parent
                    accent: bar.accent
                    body: bar.popoutHere && bar.popouts.current === "control" ? bar.textColor : Config.tint("#566173")
                    Behavior on body { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }
            // Apps: three soft rounded bars
            Capsule {
                visible: Config.s.barShowApps
                length: bar.capsuleHeight + 8
                hoverText: "Apps"
                hoverCode: 0xEC42
                onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "launcher", "toggle"])
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: 3
                        // Colourful look: each bar its own pastel
                        Rectangle {
                            required property int index
                            width: 14; height: 2.4; radius: height / 2
                            color: Config.partColour(Config.appsPastels, index, bar.textColor)
                        }
                    }
                }
            }

            // Spaces: four small squares (Spaces.qml). While a space is coming back they take
            // its colour and light up in turn
            Capsule {
                id: spacesBtn
                visible: Config.s.barShowSpaces
                length: bar.capsuleHeight + 8
                hoverText: Spaces.restoringSpace ? "Opening " + Spaces.restoringSpace.name + "…" : "Spaces"
                hoverCode: 0xEDBA
                onClicked: bar.openPopout("spaces", spacesBtn)
                property int beat: 0
                Timer { interval: 220; repeat: true; running: Spaces.restoring !== ""; onTriggered: spacesBtn.beat = (spacesBtn.beat + 1) % 4 }
                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    spacing: 2.4
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            readonly property bool busy: Spaces.restoring !== ""
                            width: 5.8; height: 5.8; radius: 1.6
                            // Clockwise: top left, top right, bottom right, bottom left
                            readonly property bool lit: busy && [0, 1, 3, 2][spacesBtn.beat] === index
                            // (Colourful look: each square its own pastel)
                            color: busy && Spaces.restoringSpace ? Spaces.restoringSpace.colour : Config.partColour(Config.spacesPastels, index, bar.textColor)
                            opacity: !busy || lit ? 1 : 0.35
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                }
            }

            // Workspaces: grey/white dots, plus an accent marker that glides between them
            // (WorkspaceMarker).
            Capsule {
                id: wsCap
                visible: Config.s.barShowWorkspaces
                readonly property real dot: 14
                readonly property real dotGap: 5
                readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
                readonly property int activeIndex: Math.max(0, spaces.findIndex(w => Hyprland.focusedWorkspace && w.id === Hyprland.focusedWorkspace.id))
                length: (bar.vert ? wsRow.height : wsRow.width) + 16

                Grid {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: wsCap.dotGap
                    // One row across the bar, or one column down a side bar, sized to what it holds
                    // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
                    // for every column it's told to have, even empty ones)
                    columns: bar.vert ? 1 : -1
                    rows: bar.vert ? -1 : 1
                    Repeater {
                        model: wsCap.spaces
                        delegate: Rectangle {
                            id: wsDot
                            required property var modelData
                            readonly property int winCount: modelData.toplevels?.values?.length ?? 0
                            readonly property bool occupied: winCount > 0
                            readonly property var firstApp: occupied && modelData.toplevels.values[0].wayland ? bar.lookup(modelData.toplevels.values[0].wayland.appId) : null
                            readonly property string hoverText: "Workspace " + modelData.id + " · " + (winCount === 0 ? "empty" : winCount + (winCount === 1 ? " window" : " windows"))
                            readonly property int hoverCode: 0
                            readonly property string hoverTile: firstApp ? firstApp.id : ""
                            readonly property url hoverImage: ""
                            HoverHandler { id: wsDotHover; onHoveredChanged: bar.setHover(wsDot, hovered) }
                            width: wsCap.dot; height: wsCap.dot; radius: Config.dotRadius(wsCap.dot)
                            // Inactive workspaces are dimmed a little; the accent marker shows the active
                            // one. Brighter under the pointer
                            color: wsDotHover.hovered ? (occupied ? Config.tint("#eef1f5") : Config.tint("#8b94a3"))
                                : occupied ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                            Behavior on color { ColorAnimation { duration: 150 } }
                            MouseArea { anchors.fill: parent; onClicked: modelData.activate() }
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

            // Title area: the focused window's tile and title, or, while the pointer is
            // over something on the bar, a description of that (cross-faded)
            // Placeholder for the title area (it moves to the bottom group on a left bar)
            Item {
                id: titleSlotTop
                visible: titleArea.parent === titleSlotTop && Config.s.barShowTitle
                width: childrenRect.width; height: childrenRect.height
            }
            Grid {
                id: titleArea
                // On a left bar the title reads upwards, so it sits at the bottom, just above
                // the tray, and grows up from there
                parent: bar.vert && !bar.atRight ? titleSlotBottom : titleSlotTop
                visible: Config.s.barShowTitle
                spacing: bar.gap
                // One row across the bar, or one column down a side bar, sized to what it holds
                // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
                // for every column it's told to have, even empty ones)
                columns: bar.vert ? 1 : -1
                rows: bar.vert ? -1 : 1
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter
                readonly property var s: bar.shownItem

                Item { id: tileSlotStart; visible: appTile.parent === tileSlotStart && appTile.visible; width: childrenRect.width; height: childrenRect.height }
                Capsule {
                    id: appTile
                    // Before the title, except on a left bar, where the title reads upwards and
                    // starts at the bottom: the icon goes there
                    parent: bar.vert && !bar.atRight ? tileSlotEnd : tileSlotStart
                    readonly property var focusedTop: ToplevelManager.activeToplevel
                    readonly property var entry: bar.lookup(focusedTop ? focusedTop.appId : "")
                    readonly property string winKey: entry ? entry.id : (focusedTop ? focusedTop.appId : "")
                    readonly property string key: titleArea.s ? (titleArea.s.hoverTile || "") : winKey
                    readonly property string path: bar.tileDir + "/" + key.replace(/[^A-Za-z0-9._-]/g, "_") + ".png"
                    readonly property bool showGlyph: !!titleArea.s && key === "" && titleArea.s.hoverCode !== 0
                    readonly property bool showImage: !!titleArea.s && key === "" && !showGlyph && String(titleArea.s.hoverImage) !== ""
                    // The focused window came from a space: its tile takes the space's colour
                    // (the whole button, for icon styles with no tile behind the icon)
                    readonly property var space: titleArea.s || !Config.s.spaceBarTint ? null
                        : Spaces.spaceById(Hyprland.activeToplevel ? Spaces.spaceOfAddress[Hyprland.activeToplevel.address] : "")
                    color: space && !tilePlate.visible ? space.colour : bar.capsuleColor
                    Behavior on color { ColorAnimation { duration: 200 } }
                    property int version: 0
                    property string tried: ""      // drawn once per icon file
                    // Hover descriptions are text only; the app's icon can be turned off (Settings → Menu bar)
                    visible: !titleArea.s && !!focusedTop && Config.s.barShowTitleIcon
                    length: bar.capsuleHeight
                    hoverTint: false
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
                            color: appTile.space ? appTile.space.colour : Config.iconPlateColor
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                    }
                    Process {
                        id: tileGen
                        command: Config.tileCommand(appTile.key, appTile.path)
                        onExited: appTile.version++
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appTile.showGlyph
                        text: appTile.showGlyph ? bar.glyph(titleArea.s.hoverCode) : ""
                        color: bar.textColor
                        font.family: bar.iconFont
                        font.pixelSize: 16
                    }
                    Image {
                        id: hoverImg
                        anchors.centerIn: parent
                        width: 16; height: 16
                        source: appTile.showImage ? titleArea.s.hoverImage : ""
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

                // The title (turned to run down a side bar)
                Item {
                    width: bar.vert ? titleText.height : titleText.width
                    height: bar.vert ? titleText.width : titleText.height
                    Text {
                        id: titleText
                        anchors.centerIn: parent
                        rotation: bar.textRotation
                        width: Math.min(implicitWidth, bar.vert ? 320 : 560)
                        elide: Text.ElideRight
                        text: titleArea.s ? titleArea.s.hoverText
                            : ToplevelManager.activeToplevel ? ToplevelManager.activeToplevel.title : ""
                        leftPadding: titleArea.s || !Config.s.barShowTitleIcon ? 8 : 0      // a little space for a hover description, or with no app icon
                        color: bar.textColor
                        font.family: bar.fontFamily
                        font.pixelSize: bar.fontSize
                        font.weight: Font.Medium
                    }
                }
                Item { id: tileSlotEnd; visible: appTile.parent === tileSlotEnd && appTile.visible; width: childrenRect.width; height: childrenRect.height }
            }
        }

        // ---- Right side --------------------------------------------------
        Grid {
            id: right
            opacity: bar.dimmed ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            spacing: bar.gap
            // One row across the bar, or one column down a side bar, sized to what it holds
            // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
            // for every column it's told to have, even empty ones)
            columns: bar.vert ? 1 : -1
            rows: bar.vert ? -1 : 1
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            // Placed by the edge of what's actually shown: the grid's own size can include spacing
            // for hidden items, which would leave a wider gap at this end of the bar
            x: bar.vert ? bar.bgX + (bar.barHeight - bar.capsuleHeight) / 2 : parent.width - (childrenRect.x + childrenRect.width) - bar.sidePadding
            y: bar.vert ? parent.height - (childrenRect.y + childrenRect.height) - bar.sidePadding : bar.bgY + (bar.barHeight - bar.capsuleHeight) / 2

            // The title area on a left bar (see titleSlotTop)
            Item {
                id: titleSlotBottom
                visible: titleArea.parent === titleSlotBottom && Config.s.barShowTitle
                width: childrenRect.width; height: childrenRect.height
            }

            // Tray. Collapsed (Settings → Menu bar): one button that opens to show the icons, and
            // closes again a few seconds after the pointer leaves (or when clicked)
            Capsule {
                id: trayCapsule
                visible: Config.s.barShowTray && SystemTray.items.values.length > 0
                length: (bar.vert ? trayRow.height : trayRow.width) + 10     // 5 px each side
                hoverTint: false
                readonly property bool collapsible: Config.s.barTrayCollapsed
                property bool expanded: false
                readonly property bool showIcons: !collapsible || expanded
                onCollapsibleChanged: expanded = false
                HoverHandler { id: trayAreaHover; onHoveredChanged: if (hovered) trayClose.stop(); else if (trayCapsule.expanded) trayClose.restart() }
                Timer { id: trayClose; interval: 4000; onTriggered: trayCapsule.expanded = false }
                Grid {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: 2
                    // One row across the bar, or one column down a side bar, sized to what it holds
                    // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
                    // for every column it's told to have, even empty ones)
                    columns: bar.vert ? 1 : -1
                    rows: bar.vert ? -1 : 1
                    Repeater {
                        model: trayCapsule.showIcons ? SystemTray.items.values : []
                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            width: bar.vert ? 22 : 26; height: bar.vert ? 26 : 22
                            readonly property string hoverText: modelData.tooltipTitle || modelData.title || modelData.id || ""
                            readonly property int hoverCode: 0
                            readonly property string hoverTile: ""
                            readonly property url hoverImage: modelData.icon
                            // Hover highlight
                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: bar.hoverFill
                                opacity: trayHover.hovered ? bar.hoverStrength : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            HoverHandler { id: trayHover; onHoveredChanged: bar.setHover(trayItem, hovered) }
                            // Icon drawn in high-contrast black and white (light parts white,
                            // dark/coloured parts black) to match the rest of the bar; in the
                            // Colourful look, in its own colours
                            Image {
                                id: trayIcon
                                anchors.centerIn: parent
                                width: 18; height: 18
                                source: trayItem.modelData.icon
                                sourceSize: Qt.size(36, 36)
                                smooth: true
                                visible: Config.colourful
                            }
                            ShaderEffect {
                                visible: !Config.colourful
                                anchors.fill: trayIcon
                                property variant source: trayIcon
                                property real threshold: 0.45      // brighter than this takes the text colour
                                property color tint: bar.textColor
                                fragmentShader: Qt.resolvedUrl("shaders/mono.frag.qsb")
                            }
                            // Right-click (or any click, for apps that only have a menu): the app's
                            // menu, drawn by Slate (TrayMenu.qml). Left-click: the app's own action;
                            // middle-click: its other one
                            MouseArea {
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
                        width: bar.vert ? 22 : 22; height: 22
                        readonly property string hoverText: trayCapsule.expanded ? "Hide the tray" : SystemTray.items.values.length + " tray " + (SystemTray.items.values.length === 1 ? "app" : "apps")
                        readonly property int hoverCode: 0
                        readonly property string hoverTile: ""
                        readonly property url hoverImage: ""
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: bar.hoverFill
                            opacity: toggleHover.hovered ? bar.hoverStrength : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                        HoverHandler { id: toggleHover; onHoveredChanged: bar.setHover(trayToggle, hovered) }
                        Text {
                            anchors.centerIn: parent
                            // Points the way the icons open (away from the rest of the bar), or back when open
                            text: bar.glyph(bar.vert ? (trayCapsule.expanded ? 0xEA5F : 0xEA62) : (trayCapsule.expanded ? 0xEA61 : 0xEA60))
                            color: bar.textColor
                            font.family: bar.iconFont; font.pixelSize: 16
                        }
                        TapHandler { onTapped: { trayCapsule.expanded = !trayCapsule.expanded; trayClose.stop(); } }
                    }
                }
            }

            // Notifications | Wi-Fi | keyboard | Bluetooth | volume | battery: one container, hover fills each section to the separator
            Capsule {
                id: status
                hoverTint: false
                // Which sections are shown (Settings → Menu bar); the rounded hover ends and
                // separators follow whichever are visible
                readonly property bool hasBell: Config.s.barShowNotifications
                readonly property bool hasClip: Config.s.barShowClipboard
                readonly property bool hasShot: Config.s.barShowScreenshot
                readonly property bool hasWifi: Config.s.barShowWifi
                readonly property bool hasKb: Config.s.barShowKeyboard && Config.kbLayoutList.length > 1
                readonly property bool hasBt: Config.s.barShowBluetooth && !!Bluetooth.defaultAdapter
                readonly property bool hasVol: Config.s.barShowVolume
                readonly property bool hasBat: Config.s.barShowBattery && UPower.displayDevice && UPower.displayDevice.isPresent
                // In order along the bar; first/last/separators follow whichever are shown
                readonly property var shown: [hasBell, hasClip, hasShot, hasWifi, hasKb, hasBt, hasVol, hasBat]
                function isFirst(i) { return !shown.slice(0, i).some(x => x); }
                function isLast(i) { return !shown.slice(i + 1).some(x => x); }
                function sepBefore(i) { return shown[i] && !isFirst(i); }
                visible: shown.some(x => x)
                length: bar.vert ? statusRow.height : statusRow.width
                Grid {
                    id: statusRow
                    // One row across the bar, or one column down a side bar, sized to what it holds
                    // (one row or column, left open: a grid counts what it shows itself, and leaves a gap
                    // for every column it's told to have, even empty ones)
                    columns: bar.vert ? 1 : -1
                    rows: bar.vert ? -1 : 1

                    // Notifications: crossed-out bell during Do Not Disturb, unread count beside it
                    Segment {
                        id: bellBtn
                        pastel: "notifications"            // its colour when the look is Colourful
                        visible: status.hasBell
                        first: true
                        last: status.isLast(0)
                        iconCode: bar.notifs && bar.notifs.dnd ? 0xECE9 : 0xEA35
                        hoverText: !bar.notifs ? "Notifications"
                            : bar.notifs.dnd ? "Do not disturb is on"
                            : bar.notifs.unread > 0 ? bar.notifs.unread + (bar.notifs.unread === 1 ? " unread notification" : " unread notifications")
                            : "Notifications"
                        // Unread count beside the bell (hidden during Do Not Disturb)
                        label: bar.notifs && bar.notifs.unread > 0 && !bar.notifs.dnd
                            ? (bar.notifs.unread > 99 ? "99+" : String(bar.notifs.unread)) : ""
                        onClicked: bar.openPopout("notifications", bellBtn)
                    }
                    Separator { visible: status.sepBefore(1) }
                    // Clipboard history: how many items it holds; click for the list
                    Segment {
                        id: clipSeg
                        pastel: "clipboard"            // its colour when the look is Colourful
                        visible: status.hasClip
                        first: status.isFirst(1)
                        last: status.isLast(1)
                        iconCode: Config.s.clipboardHistory ? 0xEA6F : 0xF0CE
                        label: Config.s.barValueClipboard && Config.s.clipboardHistory && Config.clipCount > 0 ? String(Config.clipCount) : ""
                        hoverText: !Config.s.clipboardHistory ? "Clipboard history is off"
                            : Config.clipCount === 0 ? "Clipboard · empty"
                            : "Clipboard · " + Config.clipCount + (Config.clipCount === 1 ? " item" : " items")
                        onClicked: bar.openPopout("clipboard", clipSeg)
                    }
                    Separator { visible: status.sepBefore(2) }
                    // Screenshots: click for area / window / screen
                    Segment {
                        id: shotSeg
                        pastel: "screenshot"            // its colour when the look is Colourful
                        visible: status.hasShot
                        first: status.isFirst(2)
                        last: status.isLast(2)
                        iconCode: 0xF201
                        hoverText: "Screenshot"
                        onClicked: bar.openPopout("screenshot", shotSeg)
                    }
                    Separator { visible: status.sepBefore(3) }
                    Segment {
                        id: wifiSeg
                        pastel: "wifi"            // its colour when the look is Colourful
                        visible: status.hasWifi
                        first: status.isFirst(3)
                        last: status.isLast(3)
                        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
                        readonly property var net: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null
                        readonly property real signal: net ? net.signalStrength : 0
                        iconCode: !net ? 0xECFA : signal > 0.66 ? 0xEB52 : signal > 0.33 ? 0xEBA5 : 0xEBA4
                        label: Config.s.barValueWifi ? (net ? net.name : "Offline") : ""
                        hoverText: net ? "Wi-Fi · " + net.name + " · " + Math.round(signal * 100) + "% signal"
                            : Networking.wifiEnabled ? "Wi-Fi · not connected" : "Wi-Fi is off"
                        onClicked: bar.openPopout("wifi", wifiSeg)
                    }
                    Separator { visible: status.sepBefore(4) }
                    // Keyboard layout: its short code (GB, FR…); click to pick one, scroll to cycle
                    Segment {
                        id: kbSeg
                        pastel: "keyboard"            // its colour when the look is Colourful
                        visible: status.hasKb
                        first: status.isFirst(4)
                        last: status.isLast(4)
                        readonly property var current: Config.kbLayoutList[Config.kbActive] ?? Config.kbLayoutList[0] ?? null
                        iconCode: 0xEBD6
                        label: Config.s.barValueKeyboard && current ? current.code : ""
                        hoverText: current ? "Keyboard · " + current.name : "Keyboard"
                        onClicked: bar.openPopout("keyboard", kbSeg)
                        onWheel: delta => Config.switchLayout(Config.kbActive + (delta > 0 ? -1 : 1))
                    }
                    Separator { visible: status.sepBefore(5) }
                    // Bluetooth: off / on / something connected; beside it, how many are connected
                    Segment {
                        id: btSeg
                        pastel: "bluetooth"            // its colour when the look is Colourful
                        visible: status.hasBt
                        first: status.isFirst(5)
                        last: status.isLast(5)
                        readonly property var adapter: Bluetooth.defaultAdapter
                        readonly property bool on: !!adapter && adapter.enabled
                        readonly property var connected: on ? adapter.devices.values.filter(d => d.connected) : []
                        iconCode: !on ? 0xECEB : connected.length > 0 ? 0xECEA : 0xEA37
                        label: Config.s.barValueBluetooth && connected.length > 0 ? String(connected.length) : ""
                        hoverText: !on ? "Bluetooth is off"
                            : connected.length === 0 ? "Bluetooth · nothing connected"
                            : "Bluetooth · " + connected.map(d => d.name || d.deviceName || d.address).join(", ")
                        onClicked: bar.openPopout("bluetooth", btSeg)
                    }
                    Separator { visible: status.sepBefore(6) }
                    Segment {
                        id: volSeg
                        pastel: "volume"            // its colour when the look is Colourful
                        visible: status.hasVol
                        first: status.isFirst(6)
                        last: status.isLast(6)
                        readonly property var sink: Pipewire.defaultAudioSink
                        readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
                        readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
                        tint: muted ? bar.errorColor : bar.textColor
                        iconCode: muted || vol === 0 ? 0xF1C3 : vol > 0.5 ? 0xEB51 : 0xEB4F
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
                    Separator { visible: status.sepBefore(7) }
                    Segment {
                        id: batSeg
                        pastel: "battery"            // its colour when the look is Colourful
                        first: status.isFirst(7)
                        last: true
                        readonly property var dev: UPower.displayDevice
                        readonly property real pct: dev && dev.ready ? dev.percentage : 0
                        readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged || dev.state === UPowerDeviceState.PendingCharge)
                        visible: status.hasBat
                        iconCode: charging || !UPower.onBattery ? 0xEBD9 : pct > 0.8 ? 0xEA32 : pct > 0.55 ? 0xEA31 : pct > 0.3 ? 0xEA30 : 0xEA2F
                        label: Config.s.barValueBattery ? Math.round(pct * 100) + "%" : ""
                        hoverText: "Battery " + Math.round(pct * 100) + "% · " + (charging ? "charging" : UPower.onBattery ? "on battery" : "plugged in")
                        onClicked: bar.openPopout("battery", batSeg)
                    }
                }
            }

            // Clock
            Capsule {
                id: clockCap
                length: clock.implicitWidth + 20
                hoverText: Qt.formatDate(sysClock.date, "dddd, d MMMM yyyy")
                hoverCode: 0xEA53
                SystemClock { id: sysClock; precision: Config.s.barClockSeconds ? SystemClock.Seconds : SystemClock.Minutes }
                Text {
                    id: clock
                    anchors.centerIn: parent
                    // Turned to run along a side bar, like the window title
                    rotation: bar.textRotation
                    text: (Config.s.barClockDate ? Qt.formatDate(sysClock.date, "ddd d MMM") + "  " : "")
                        + Qt.formatTime(sysClock.date, Config.s.barClockFormat === "24h"
                            ? (Config.s.barClockSeconds ? "HH:mm:ss" : "HH:mm")
                            : (Config.s.barClockSeconds ? "h:mm:ss AP" : "h:mm AP"))
                    color: bar.textColor
                    font.family: bar.fontFamily
                    font.pixelSize: bar.fontSize
                    font.weight: Font.Medium
                }
                onClicked: bar.openPopout("calendar", clockCap)
            }

            GlyphButton { id: powerBtn; visible: Config.s.barShowPower; code: 0xEB0D; tint: bar.errorColor; hoverText: bar.uptimeText(); onClicked: bar.openPopout("session", powerBtn) }   // power
        }
    }

    // ---- Building blocks ---------------------------------------------------

    // Hover highlight behind bar items: the accent colour, lightly (as everywhere: Config.hover)
    readonly property color hoverFill: bar.accent
    readonly property real hoverStrength: Config.hoverStrength

    // Rounded container with a soft hover tint and click handling
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
        color: bar.capsuleColor
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: bar.hoverFill
            opacity: cap.hoverTint && capHover.hovered ? bar.hoverStrength : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Gloss { radius: cap.radius }          // glass: a sheen
        HoverHandler { id: capHover; onHoveredChanged: if (cap.hoverText !== "") bar.setHover(cap, hovered) }
        TapHandler { onTapped: cap.clicked() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: cap.rightClicked() }
    }

    // Capsule holding one icon glyph
    component GlyphButton: Capsule {
        property int code: 0
        hoverCode: code
        property color tint: bar.textColor
        length: bar.capsuleHeight + 8
        Text {
            anchors.centerIn: parent
            text: bar.glyph(parent.code)
            color: parent.tint
            font.family: bar.iconFont
            font.pixelSize: 17
        }
    }

    // One section of the notifications/Wi-Fi/volume/battery group. Its hover tint reaches the
    // separators (square there) and follows the container's rounding at the ends.
    component Segment: Item {
        id: seg
        property bool first: false
        property bool last: false
        property int iconCode: 0
        property string label: ""
        property color tint: bar.textColor
        // Colourful look: the icon in this pastel (Config.statusPastels), unless it's showing a
        // warning colour (tint other than the text colour)
        property string pastel: ""
        property string hoverText: ""
        property int hoverCode: iconCode
        property string hoverTile: ""
        property url hoverImage
        signal clicked()
        signal wheel(real delta)
        // Icon and value across a top/bottom bar; just the icon, stacked, on a side bar
        width: bar.vert ? bar.capsuleHeight : segRow.width + 20
        height: bar.vert ? segRow.height + 14 : bar.capsuleHeight

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
            opacity: segHover.hovered ? bar.hoverStrength : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Row {
            id: segRow
            anchors.centerIn: parent
            // No gap when there's no label, so a lone icon sits in the middle
            spacing: seg.label !== "" && !bar.vert ? 6 : 0
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: bar.glyph(seg.iconCode)
                color: seg.pastel !== "" && Qt.colorEqual(seg.tint, bar.textColor) ? Config.statusColour(seg.pastel, seg.tint) : seg.tint
                font.family: bar.iconFont
                font.pixelSize: 16
            }
            Text {
                visible: seg.label !== "" && !bar.vert
                anchors.verticalCenter: parent.verticalCenter
                text: seg.label
                color: seg.tint
                font.family: bar.fontFamily
                font.pixelSize: bar.fontSize
                font.weight: Font.Medium
            }
        }
        HoverHandler { id: segHover; onHoveredChanged: if (seg.hoverText !== "") bar.setHover(seg, hovered) }
        TapHandler { onTapped: seg.clicked() }
        WheelHandler { onWheel: e => seg.wheel(e.angleDelta.y) }
    }

    component Separator: Item {
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
