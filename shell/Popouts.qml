// Drop-down panels attached to the top bar: spaces, volume, Wi-Fi, battery & power,
// calendar and session. Each opens under the button that was clicked, joins the
// bar with curved corners, and slides out of it.
//
// Open from the bar with bar.openPopout("<name>", item). Close by clicking outside,
// pressing Escape, or clicking the same button again.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects

PanelWindow {
    id: pop
    required property var bar
    property var notifs: null
    property var powerConfirm: null      // centred "Shut down?" dialog (PowerConfirm.qml)

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
    function toggle(name, x, y, scr) {
        const target = scr || Config.focusedScreen;
        if (target && screen !== target) { current = ""; pending = ""; revealed = false; screen = target; }
        else if (current === name) { close(); return; }
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
    }
    function close() { current = ""; pending = ""; revealed = false; revealWaiting = false; }
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
    // held up the slide
    visible: true
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
    mask: Region { item: pop.engaged ? catcher : pop.active ? panelArea : null }

    Item { id: catcher; anchors.fill: parent }

    // Click outside the panel to close
    MouseArea {
        anchors.fill: parent
        enabled: pop.engaged
        onClicked: pop.close()
    }

    // ---- Look --------------------------------------------------------------
    readonly property color bg: bar.barColor
    readonly property color card: bar.capsuleColor
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    readonly property real radius: 14
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
        color: pop.bg
        topLeftRadius: body.topLeftRadius; topRightRadius: body.topRightRadius
        bottomLeftRadius: body.bottomLeftRadius; bottomRightRadius: body.bottomRightRadius
        // Never quite 0 while shown: at 0 Qt drops it from the scene and rebuilds it on the
        // first frame of the slide, which held the slide up
        opacity: pop.active ? Math.max(0.01, pop.fade) : 0      // prepared with the panel (see pending)
        // No shadow with glass: it would show through the panel (and get blurred behind it)
        visible: width > 0 && height > 0 && !Config.glass
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: Config.s.lightMode ? 0.22 : 0.5
            shadowBlur: 0.9
            blurMax: 24
            shadowHorizontalOffset: pop.sideways ? (pop.side === "left" ? 4 : -4) : 0
            shadowVerticalOffset: pop.sideways ? 4 : (pop.fromBottom ? -4 : 4)
        }
    }

    // ---- Panel body --------------------------------------------------------
    // The control centre opens from the bar's first button and the power menu (session) from
    // its last, so they sit flush against the start / end of the screen, rounded only on
    // their one corner out in the screen
    readonly property bool atScreenStart: displayed === "control"
    readonly property bool atScreenEnd: displayed === "session"
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
            topLeftRadius: (pop.side === "bottom" && !pop.atScreenStart) || (pop.side === "right" && !pop.atScreenStart) ? pop.radius : 0
            topRightRadius: (pop.side === "bottom" && !pop.atScreenEnd) || (pop.side === "left" && !pop.atScreenStart) ? pop.radius : 0
            bottomLeftRadius: (pop.side === "top" && !pop.atScreenStart) || (pop.side === "right" && !pop.atScreenEnd) ? pop.radius : 0
            bottomRightRadius: (pop.side === "top" && !pop.atScreenEnd) || (pop.side === "left" && !pop.atScreenEnd) ? pop.radius : 0
            // Fades with its movement: in as it slides out, out as it slides back
            opacity: pop.active ? Math.max(0.01, pop.fade) : 0

            FocusScope {
                anchors.fill: parent
                anchors.margins: pop.pad
                focus: pop.shown
                Keys.onEscapePressed: pop.close()
                Loader {
                    id: content
                    focus: true
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
                        : pop.displayed === "calendar" ? calendarPanel
                        : pop.displayed === "session" ? sessionPanel
                        : pop.displayed === "control" ? controlPanel
                        : pop.displayed === "spaces" ? spacesPanel
                        : pop.displayed === "notifications" ? notificationsPanel : null
                }
            }
        }
    }

    // Curved joins between the bar and the panel's sides
    Repeater {
        model: 2
        Canvas {
            required property int index
            width: bar.cornerRadius; height: bar.cornerRadius
            // None at the screen's edge, for a panel flush against it
            visible: !(pop.atScreenEnd && index === 1) && !(pop.atScreenStart && index === 0)
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
            readonly property color fill: pop.bg
            onFillChanged: requestPaint()
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                const r = bar.cornerRadius, ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = fill;
                ctx.beginPath();
                ctx.moveTo(0, 0);
                ctx.lineTo(r, 0);
                ctx.lineTo(r, r);
                ctx.arc(0, r, r, 0, -Math.PI / 2, true);
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    // ---- Control centre state ----------------------------------------------
    // Caffeine: keeps the session awake (Slate's idle lock and other idle watchers respect it)
    property bool caffeine: false
    IdleInhibitor { window: pop.bar; enabled: pop.caffeine }
    readonly property bool nightLight: Config.s.nightLight   // NightLight.qml applies it
    onCurrentChanged: {
        if (current === "control") uptimeFile.reload();
        if (current === "notifications" && notifs) notifs.markRead();
    }

    // Weather from Open-Meteo for Settings' location (Config.s.latitude/longitude), every 30 min
    property var weather: null
    property var forecast: null       // daily: time[], weather_code[], temperature_2m_max[], temperature_2m_min[]
    Process {
        id: weatherFetch
        command: ["curl", "-sf", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + Config.s.latitude + "&longitude=" + Config.s.longitude + "&current=temperature_2m,apparent_temperature,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=5&timezone=auto"]
        stdout: StdioCollector {
            onStreamFinished: { try { const j = JSON.parse(text); pop.weather = j.current; pop.forecast = j.daily; } catch (e) {} }
        }
    }
    // Only once a location is set (Settings → General → Location); again when it changes
    readonly property string weatherPlace: Config.s.locationName === "" ? "" : Config.s.latitude + "," + Config.s.longitude
    onWeatherPlaceChanged: { weather = null; forecast = null; if (weatherPlace !== "") weatherFetch.running = true; }
    Timer { interval: 30 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (pop.weatherPlace !== "") weatherFetch.running = true }
    function weatherInfo(code) {
        if (code === 0) return { text: "Clear", icon: 0xEB30 };
        if (code <= 2) return { text: "Partly cloudy", icon: 0xEC6D };
        if (code === 3) return { text: "Overcast", icon: 0xEA76 };
        if (code <= 48) return { text: "Fog", icon: 0xECD9 };
        if (code <= 67 || (code >= 80 && code <= 82)) return { text: "Rain", icon: 0xEA72 };
        if (code <= 77 || code === 85 || code === 86) return { text: "Snow", icon: 0xEC0B };
        return { text: "Thunderstorm", icon: 0xEA74 };
    }

    FileView { id: uptimeFile; path: "/proc/uptime" }
    // Your name from the account (as on the lock screen), else the user name
    property string fullName: Quickshell.env("USER")
    Process {
        running: true
        command: ["getent", "passwd", Quickshell.env("USER")]
        stdout: StdioCollector { onStreamFinished: { const n = (text.split(":")[4] || "").split(",")[0]; if (n) pop.fullName = n; } }
    }
    FileView { id: hostFile; path: "/etc/hostname" }
    property string hyprVersion: ""
    Process {
        running: true
        command: ["hyprctl", "version", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { pop.hyprVersion = JSON.parse(text).tag.replace(/^v/, ""); } catch (e) {} } }
    }
    function uptimeText() {
        const sec = parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return "Up " + (d > 0 ? d + (d === 1 ? " day " : " days ") : "") + h + " h " + m + " min";
    }

    // ---- Shared pieces -----------------------------------------------------
    function glyph(code) { return String.fromCodePoint(code); }

    component Label: Text {
        color: pop.text
        font.family: bar.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        elide: Text.ElideRight
    }
    component Icon: Text {
        property int code: 0
        text: pop.glyph(code)
        color: pop.text
        font.family: bar.iconFont
        font.pixelSize: 18
    }
    component Divider: Rectangle { width: parent ? parent.width : 0; height: 1; color: pop.card }

    // Horizontal slider, 0..1
    component Slider: Item {
        id: sl
        property real value: 0
        property bool muted: false
        signal moved(real v)
        implicitHeight: 22
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: pop.card
            Rectangle {
                width: Math.max(6, track.width * Math.min(1, sl.value)); height: parent.height; radius: 3
                color: sl.muted ? pop.dim : pop.accent
                Gloss { radius: parent.radius }   // glass: a sheen
            }
        }
        Rectangle {
            width: 16; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(1, sl.value) * (sl.width - width)
            color: pop.text
            Gloss { radius: parent.radius; strength: 0.6 }   // glass: a sheen
        }
        MouseArea {
            preventStealing: true      // keep the drag once started, even if the pointer drifts off
            anchors.fill: parent
            function set(mx) { sl.moved(Math.max(0, Math.min(1, mx / width))); }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x); }
            onWheel: w => sl.moved(Math.max(0, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    // A row you can click, highlighted on hover (or blue when selected)
    component RowButton: Rectangle {
        id: rb
        property bool selected: false
        property bool danger: false
        signal clicked()
        height: 36
        radius: 8
        color: selected ? pop.accent : rbHover.hovered ? Config.hover : "transparent"
        Gloss { radius: parent.radius; opacity: (selected || rbHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        HoverHandler { id: rbHover }
        ClickTap { onTapped: rb.clicked() }
    }

    // ---- Volume ------------------------------------------------------------
    Component {
        id: volumePanel
        Column {
            id: vol
            width: 300
            spacing: 12
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property var source: Pipewire.defaultAudioSource
            readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
            PwObjectTracker { objects: [vol.sink, vol.source].concat(vol.sinks) }

            Repeater {
                model: [
                    { node: vol.sink, title: "Output", on: 0xEB51, off: 0xF1C3 },
                    { node: vol.source, title: "Input", on: 0xEAF0, off: 0xED16 }
                ]
                delegate: Column {
                    required property var modelData
                    readonly property var a: modelData.node && modelData.node.audio ? modelData.node.audio : null
                    visible: a !== null
                    width: vol.width
                    spacing: 6
                    Item {
                        width: parent.width; height: 22
                        Icon {
                            id: muteIcon
                            code: parent.parent.a && parent.parent.a.muted ? parent.parent.modelData.off : parent.parent.modelData.on
                            color: parent.parent.a && parent.parent.a.muted ? pop.danger : pop.text
                            anchors.verticalCenter: parent.verticalCenter
                            ClickTap { onTapped: { const a = muteIcon.parent.parent.a; if (a) a.muted = !a.muted; } }
                        }
                        Label {
                            anchors { left: muteIcon.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: parent.parent.modelData.title
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: parent.parent.a ? Math.round(parent.parent.a.volume * 100) + "%" : ""
                            color: pop.dim
                        }
                    }
                    Slider {
                        width: parent.width
                        value: parent.a ? parent.a.volume : 0
                        muted: parent.a ? parent.a.muted : false
                        onMoved: v => { const a = parent.a; if (a) { a.muted = false; a.volume = v; } }
                    }
                }
            }

            Divider { visible: vol.sinks.length > 1 }
            Label { visible: vol.sinks.length > 1; text: "Output device"; color: pop.dim; font.pixelSize: 12 }
            Column {
                visible: vol.sinks.length > 1
                width: parent.width
                spacing: 6
                Repeater {
                    model: vol.sinks
                    delegate: RowButton {
                        required property var modelData
                        width: parent.width
                        selected: vol.sink && vol.sink.id === modelData.id
                        // Short name ("Speaker", "Headphones") rather than the sound card's long one
                        readonly property string shortName: (modelData.properties && modelData.properties["device.profile.description"])
                            || modelData.nickname || modelData.description || modelData.name
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                        Icon {
                            id: devIcon
                            code: parent.shortName.toLowerCase().includes("head") ? 0xEABD : 0xEA8B
                            color: parent.selected ? pop.accentText : pop.text
                            font.pixelSize: 16
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        }
                        Label {
                            anchors { left: devIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: parent.shortName
                            color: parent.selected ? pop.accentText : pop.text
                        }
                    }
                }
            }
        }
    }

    // ---- Wi-Fi -------------------------------------------------------------
    Component {
        id: wifiPanel
        Column {
            id: wf
            width: 320
            spacing: 10
            readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
            readonly property var nets: {
                if (!dev) return [];
                const seen = new Set();
                return dev.networks.values
                    .filter(n => n.name && !seen.has(n.name) && seen.add(n.name))
                    .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
            }
            property string askingFor: ""      // network waiting for a password
            // Scan while the panel is open
            Binding { target: wf.dev; property: "scannerEnabled"; value: true; when: wf.dev !== null && pop.shown }

            Item {
                width: parent.width; height: 26
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi"; font.pixelSize: 15 }
                // On/off switch
                Rectangle {
                    id: sw
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 40; height: 22; radius: 11
                    color: Networking.wifiEnabled ? pop.accent : pop.card
                    Gloss { radius: parent.radius }   // glass: a sheen
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                        color: Networking.wifiEnabled ? pop.accentText : pop.text
                        Behavior on x { NumberAnimation { duration: Config.ms(120) } }
                    }
                    ClickTap { onTapped: Networking.wifiEnabled = !Networking.wifiEnabled }
                }
            }

            // ---- Connection details (scripts/netinfo.sh), refreshed while the panel is open
            property var info: ({})
            readonly property var connected: nets.find(n => n.connected) ?? null
            Process {
                id: netInfo
                command: [Quickshell.shellPath("scripts/netinfo.sh")]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const o = {};
                        for (const line of text.split("\n")) {
                            const i = line.indexOf("=");
                            if (i > 0) o[line.slice(0, i)] = line.slice(i + 1);
                        }
                        wf.info = o;
                    }
                }
            }
            Timer {
                interval: 5000; repeat: true; triggeredOnStart: true
                running: pop.shown && pop.displayed === "wifi"
                onTriggered: if (!netInfo.running) netInfo.running = true
            }
            function band(freq) {
                const mhz = parseInt(freq);
                return isNaN(mhz) ? "" : mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz";
            }

            Label {
                visible: !Networking.wifiEnabled || wf.nets.length === 0
                text: Networking.wifiEnabled ? "Searching…" : "Wi-Fi is off"
                color: pop.dim
            }

            ListView {
                id: netList
                visible: Networking.wifiEnabled && wf.nets.length > 0
                width: parent.width
                height: Math.min(contentHeight, 320)
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: wf.nets
                SmoothWheel { flick: netList }
                delegate: Column {
                    id: netRow
                    required property var modelData
                    readonly property bool secure: modelData.security !== undefined && modelData.security !== WifiSecurityType.Open
                    width: netList.width
                    spacing: 4
                    RowButton {
                        width: parent.width
                        selected: netRow.modelData.connected
                        onClicked: {
                            const n = netRow.modelData;
                            if (n.connected) return;
                            if (n.known || !netRow.secure) { n.connect(); wf.askingFor = ""; }
                            else wf.askingFor = (wf.askingFor === n.name ? "" : n.name);
                        }
                        Icon {
                            id: sig
                            readonly property real s: netRow.modelData.signalStrength
                            code: s > 0.66 ? 0xEB52 : s > 0.33 ? 0xEBA5 : 0xEBA4
                            color: parent.selected ? pop.accentText : pop.text
                            font.pixelSize: 16
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        }
                        Label {
                            anchors { left: sig.right; leftMargin: 10; right: status.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: netRow.modelData.name
                            color: parent.selected ? pop.accentText : pop.text
                        }
                        Row {
                            id: status
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: netRow.modelData.connected ? "Connected"
                                    : netRow.modelData.stateChanging ? "Connecting…"
                                    : netRow.modelData.known ? "Saved" : ""
                                color: netRow.modelData.connected ? pop.accentText : pop.dim
                                font.pixelSize: 12
                            }
                            Icon {
                                visible: netRow.secure
                                code: 0xEAE2
                                font.pixelSize: 13
                                color: netRow.modelData.connected ? pop.accentText : pop.dim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    // Password entry for a new secured network
                    Rectangle {
                        visible: wf.askingFor === netRow.modelData.name
                        width: parent.width; height: 34; radius: 8
                        color: pop.card
                        TextInput {
                            id: psk
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: pop.text
                            font.family: bar.fontFamily
                            font.pixelSize: 13
                            focus: parent.visible
                            onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                            onAccepted: { netRow.modelData.connectWithPsk(text); wf.askingFor = ""; }
                            Keys.onEscapePressed: wf.askingFor = ""
                        }
                        Label {
                            visible: psk.text === ""
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: "Password, then Enter"
                            color: pop.dim
                        }
                    }
                }
            }

            // ---- Connection: signal, then details as small tiles (click to copy) ----
            readonly property bool showInfo: Networking.wifiEnabled && wf.connected !== null && wf.info.ip !== undefined
            Divider { visible: wf.showInfo }
            Label { visible: wf.showInfo; text: "Connection"; color: pop.dim; font.pixelSize: 12 }
            // Signal strength, as a meter like the battery panel's
            Column {
                visible: wf.showInfo
                width: parent.width
                spacing: 5
                // Glides between readings (the bar and the number together)
                property real sig: wf.connected ? wf.connected.signalStrength : 0
                Behavior on sig { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
                Item {
                    width: parent.width; height: sigLabel.height
                    Label { id: sigLabel; text: "Signal"; font.pixelSize: 12 }
                    Label {
                        anchors.right: parent.right
                        text: Math.round(parent.parent.sig * 100) + "%" + (wf.info.security ? " · " + wf.info.security : "")
                        color: pop.dim; font.pixelSize: 12
                    }
                }
                Rectangle {
                    width: parent.width; height: 6; radius: 3
                    color: pop.card
                    Rectangle {
                        width: Math.max(height, parent.width * parent.parent.sig)
                        height: parent.height; radius: 3
                        color: parent.parent.sig < 0.2 ? pop.danger : pop.accent   // red below 20%
                        Behavior on color { ColorAnimation { duration: Config.ms(300) } }
                    }
                }
            }
            // Details: two columns of tiles
            Grid {
                visible: wf.showInfo
                width: parent.width
                columns: 2
                spacing: 6
                Repeater {
                    model: {
                        const ip = (wf.info.ip || "").split("/")[0];
                        const t = [
                            { k: "Band", v: [wf.band(wf.info.freq), wf.info.channel ? "ch " + wf.info.channel : ""].filter(x => x).join(" · "), copy: false },
                            { k: "Link speed", v: wf.info.rate || "", copy: false },
                            { k: "IP address", v: ip, copy: true },
                            { k: "Gateway", v: wf.info.gateway || "", copy: true }
                        ];
                        if (wf.info.dns && wf.info.dns !== wf.info.gateway) t.push({ k: "DNS", v: wf.info.dns, copy: true });
                        return t.filter(x => x.v);
                    }
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        width: (wf.width - 6) / 2
                        height: 46
                        radius: 9
                        color: tileHover.hovered && modelData.copy ? Config.hoverOn(pop.card) : pop.card
                        Gloss { radius: parent.radius; opacity: (tileHover.hovered && modelData.copy) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        property bool copied: false
                        Timer { id: copiedTimer; interval: 1200; onTriggered: tile.copied = false }
                        Column {
                            anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Label { text: tile.modelData.k; color: pop.dim; font.pixelSize: 11 }
                            Label {
                                width: parent.width
                                text: tile.copied ? "Copied" : tile.modelData.v
                                color: tile.copied ? pop.accent : pop.text
                                font.pixelSize: 13
                            }
                        }
                        HoverHandler { id: tileHover }
                        ClickTap {
                            enabled: tile.modelData.copy
                            onTapped: { Quickshell.execDetached(["wl-copy", tile.modelData.v]); tile.copied = true; copiedTimer.restart(); }
                        }
                    }
                }
            }
            // VPN, when one is active
            Rectangle {
                visible: wf.showInfo && !!wf.info.vpn
                width: parent.width; height: 36; radius: 9
                color: Qt.rgba(pop.accent.r, pop.accent.g, pop.accent.b, 0.14)
                Row {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; code: 0xED58; color: pop.accent; font.pixelSize: 16 }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "VPN"; color: pop.accent; font.pixelSize: 12 }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: wf.info.vpn || ""; font.pixelSize: 12 }
                }
            }

            // Disconnect from the current network
            RowButton {
                readonly property var cur: wf.nets.find(n => n.connected) ?? null
                visible: cur !== null
                width: parent.width
                onClicked: if (cur) cur.disconnect()
                Label {
                    anchors.centerIn: parent
                    text: "Disconnect"
                    color: pop.dim
                }
            }
        }
    }

    // ---- Clipboard history ------------------------------------------------
    // The latest things copied (scripts/clipstore.py); click one to copy it again. Super+V
    // (Show all) has the full, searchable list.
    Component {
        id: clipboardPanel
        Column {
            id: clp
            width: 320
            spacing: 10
            readonly property string script: Quickshell.shellPath("scripts/clipstore.py")
            readonly property string dir: Config.clipIndex.replace(/\/index\.json$/, "")
            property var entries: []
            FileView {
                path: Config.clipIndex
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: { try { clp.entries = JSON.parse(text()).entries || []; } catch (e) { clp.entries = []; } }
                onLoadFailed: clp.entries = []
            }
            function slate(args) { Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call"].concat(args)); }

            Item {
                width: parent.width; height: 22
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Clipboard"; font.pixelSize: 15 }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: Config.s.clipboardHistory
                    text: clp.entries.length === 1 ? "1 item" : clp.entries.length + " items"
                    color: pop.dim; font.weight: Font.Normal
                }
            }
            Label {
                width: parent.width
                visible: !Config.s.clipboardHistory || clp.entries.length === 0
                text: !Config.s.clipboardHistory ? "Clipboard history is off, so nothing you copy is kept."
                    : "Nothing copied yet."
                color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
            }
            Column {
                width: parent.width
                spacing: 6
                visible: Config.s.clipboardHistory && clp.entries.length > 0
                Repeater {
                    model: clp.entries.slice(0, 8)
                    delegate: RowButton {
                        id: clipRow
                        required property var modelData
                        width: parent.width
                        height: modelData.kind === "image" ? 52 : 36
                        onClicked: { Quickshell.execDetached(["python3", clp.script, "copy", modelData.id]); pop.close(); }
                        Image {
                            id: clipThumb
                            visible: clipRow.modelData.kind === "image"
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: visible ? 56 : 0; height: 40
                            source: visible ? "file://" + clp.dir + "/" + clipRow.modelData.file : ""
                            sourceSize: Qt.size(112, 80)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Icon {
                            id: clipIcon
                            visible: clipRow.modelData.kind !== "image"
                            code: 0xF089; font.pixelSize: 16; color: pop.dim
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        }
                        Label {
                            anchors {
                                left: clipRow.modelData.kind === "image" ? clipThumb.right : clipIcon.right; leftMargin: 10
                                right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter
                            }
                            text: clipRow.modelData.kind === "image"
                                ? "Image" + (clipRow.modelData.w ? " · " + clipRow.modelData.w + " × " + clipRow.modelData.h : "")
                                : (clipRow.modelData.text || "").replace(/\s+/g, " ").trim()
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                        }
                    }
                }
            }
            Divider {}
            RowButton {
                width: parent.width
                visible: Config.s.clipboardHistory
                onClicked: { pop.close(); clp.slate(["picker", "clipboard"]); }
                Icon { id: clpAllIcon; code: 0xEA6D; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: clpAllIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Show all and search (Super+V)"; font.weight: Font.Normal }
            }
            RowButton {
                width: parent.width
                visible: Config.s.clipboardHistory && clp.entries.length > 0
                danger: true
                onClicked: { clp.entries = []; Quickshell.execDetached(["python3", clp.script, "clear"]); }
                Icon { id: clpClearIcon; code: 0xEB41; font.pixelSize: 16; color: pop.danger; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: clpClearIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Clear history"; color: pop.danger; font.weight: Font.Normal }
            }
            RowButton {
                width: parent.width
                onClicked: { pop.close(); clp.slate(["settings", "find", "general", "Clipboard history"]); }
                Icon { id: clpSetIcon; code: 0xEB20; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: clpSetIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Clipboard settings"; font.weight: Font.Normal }
            }
        }
    }

    // ---- Spaces -----------------------------------------------------------
    // Saved sets of workspaces (Spaces.qml, scripts/spaces.py): click one to bring it back on
    // new workspaces, or save the workspaces you have now as a new one
    Component {
        id: spacesPanel
        Column {
            id: spp
            width: 440
            spacing: 10
            property string mode: "list"          // list, or new (saving the workspaces now)
            // New Space
            property var picked: []               // workspace ids
            property string name: ""
            property int icon: Spaces.icons[0]
            property color colour: Spaces.colours[0]
            property bool custom: false           // a colour of your own (hue strip and hex)
            readonly property var sameName: Spaces.list.find(s => s.name.toLowerCase() === name.trim().toLowerCase()) ?? null
            readonly property bool canSave: name.trim() !== "" && picked.length > 0
            readonly property color inkColour: "#1b1f26"      // icons on a pastel

            // The workspace you're on starts picked, once the list of workspaces with apps is in,
            // and only if it's on it (an empty one has nothing to save)
            property int autoPick: -1
            Connections {
                target: Spaces
                function onLiveChanged() {
                    if (spp.autoPick < 0) return;
                    spp.picked = Spaces.live.some(w => w.id === spp.autoPick) ? [spp.autoPick] : [];
                    spp.autoPick = -1;
                }
            }
            function startNew() {
                const ws = Hyprland.focusedWorkspace;
                picked = [];
                autoPick = ws ? ws.id : -1;
                Spaces.refreshLive();
                name = "";
                custom = false;
                // A colour and icon no saved space uses yet
                const used = Spaces.list.map(s => String(s.colour).toLowerCase());
                colour = Spaces.colours.find(c => !used.includes(c)) ?? Spaces.colours[0];
                const usedIcons = Spaces.list.map(s => Spaces.iconOf(s));
                icon = Spaces.icons.find(i => !usedIcons.includes(i)) ?? Spaces.icons[0];
                mode = "new";
            }
            function toggle(id) { picked = picked.includes(id) ? picked.filter(x => x !== id) : picked.concat([id]).sort((a, b) => a - b); }
            function save() {
                if (!canSave) return;
                Spaces.save(name.trim(), colour.toString(), icon, picked);
                mode = "list";
            }
            Connections {
                target: pop
                function onCurrentChanged() { if (pop.current === "spaces") { spp.mode = "list"; } }
            }

            // ---- The saved spaces ----
            Item {
                visible: spp.mode === "list"
                width: parent.width; height: 22
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Spaces"; font.pixelSize: 15 }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: Spaces.list.length > 0
                    text: Spaces.list.length === 1 ? "1 space" : Spaces.list.length + " spaces"
                    color: pop.dim; font.weight: Font.Normal
                }
            }
            Label {
                visible: spp.mode === "list" && Spaces.list.length === 0
                width: parent.width
                text: "Set up your apps across workspaces the way you like them, then save them as a space to bring them all back in one click."
                color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
            }
            // The saved spaces. Past five they scroll (about four and a half show, to say
            // there's more), with a soft shadow at an edge that has more beyond it
            Item {
                id: spListBox
                visible: spp.mode === "list" && Spaces.list.length > 0
                width: parent.width
                readonly property real rowH: 52
                readonly property bool overflow: Spaces.list.length > 5
                height: overflow ? Math.round(rowH * 4.5 + 6 * 4) : spListCol.height
                Flickable {
                    id: spListFlick
                    anchors.fill: parent
                    contentHeight: spListCol.height
                    clip: true
                    interactive: spListBox.overflow
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: spListFlick; enabled: spListBox.overflow }
                    Column {
                        id: spListCol
                        width: spListBox.width - (spListBox.overflow ? 18 : 0)
                        spacing: 6
                        Repeater {
                            model: Spaces.list
                            delegate: RowButton {
                                id: spRow
                                required property var modelData
                                readonly property bool busy: Spaces.restoring === modelData.id
                                readonly property var appIds: Spaces.apps(modelData)
                                width: parent.width
                                height: 52
                                onClicked: { if (Spaces.restoring !== "") return; Spaces.restore(modelData.id); pop.close(); }
                                HoverHandler { id: spRowHover }
                                Rectangle {
                                    id: spBadge
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: 34; height: 34; radius: 9
                                    color: spRow.modelData.colour
                                    Icon { anchors.centerIn: parent; code: Spaces.iconOf(spRow.modelData); color: spp.inkColour; font.pixelSize: 19 }
                                }
                                Column {
                                    anchors { left: spBadge.right; leftMargin: 10; right: spSide.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 2
                                    Label { width: parent.width; text: spRow.modelData.name }
                                    Label {
                                        width: parent.width
                                        readonly property int nWs: (spRow.modelData.workspaces || []).length
                                        readonly property int nApps: Spaces.appCount(spRow.modelData)
                                        text: spRow.busy ? "Opening…"
                                            : (nWs === 1 ? "1 workspace" : nWs + " workspaces") + " · " + (nApps === 1 ? "1 app" : nApps + " apps")
                                        color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12
                                    }
                                }
                                // Its apps, or, under the pointer, a delete button (asks first, in
                                // the middle of the screen)
                                Item {
                                    id: spSide
                                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: spRowHover.hovered ? spDel.width : spApps.width
                                    height: 28
                                    Row {
                                        id: spApps
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        visible: !spRowHover.hovered
                                        spacing: -5
                                        Repeater {
                                            model: spRow.appIds.slice(0, 4)
                                            AppTile { required property string modelData; app: modelData; width: 22; height: 22 }
                                        }
                                        Label {
                                            visible: spRow.appIds.length > 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            leftPadding: 8
                                            text: "+" + (spRow.appIds.length - 4)
                                            color: pop.dim; font.pixelSize: 11
                                        }
                                    }
                                    Rectangle {
                                        id: spDel
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        visible: !spApps.visible
                                        width: 28; height: 28; radius: 7
                                        color: spDelHover.hovered ? Config.hover : "transparent"
                                        Gloss { radius: parent.radius; opacity: (spDelHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                        Icon { anchors.centerIn: parent; code: 0xEB41; font.pixelSize: 16; color: pop.danger }
                                        HoverHandler { id: spDelHover }
                                        // A MouseArea, so the click stops here rather than also opening the space
                                        ClickArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                const sp = spRow.modelData;
                                                pop.close();
                                                if (!pop.powerConfirm) return;
                                                pop.powerConfirm.confirmWith({
                                                    title: "Delete \u201c" + sp.name + "\u201d?",
                                                    body: "The space is forgotten. Its apps and windows that are open now stay as they are.",
                                                    button: "Delete", code: 0xEB41, danger: true
                                                }, () => Spaces.remove(sp.id));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // Scroll shadows, as in Settings: at the top once scrolled down, and at the
                // bottom while there's more below
                Rectangle {
                    anchors { left: parent.left; right: parent.right; rightMargin: spListBox.overflow ? 18 : 0; top: parent.top }
                    height: 18
                    // Fades with the distance from the edge, gone just as you reach it
                    opacity: Math.max(0, Math.min(1, (spListFlick.contentY - spListFlick.originY) / 24))
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Config.s.lightMode ? 0.12 : 0.32) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; rightMargin: spListBox.overflow ? 18 : 0; bottom: parent.bottom }
                    height: 24
                    opacity: Math.max(0, Math.min(1, (spListFlick.originY + spListFlick.contentHeight - spListFlick.height - spListFlick.contentY) / 24))
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, Config.s.lightMode ? 0.14 : 0.38) }
                    }
                }
                ThinScrollbar {
                    flick: spListFlick
                    color: pop.text
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                }
            }
            Divider { visible: spp.mode === "list" }
            RowButton {
                visible: spp.mode === "list"
                width: parent.width
                onClicked: spp.startNew()
                Icon { id: spNewIcon; code: 0xEB0B; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: spNewIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "New Space"; font.weight: Font.Normal }
            }
            RowButton {
                visible: spp.mode === "list"
                width: parent.width
                onClicked: { pop.close(); Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "page", "spaces"]); }
                Icon { id: spSetIcon; code: 0xEB20; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: spSetIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Spaces settings"; font.weight: Font.Normal }
            }

            // ---- New Space ----
            Item {
                visible: spp.mode === "new"
                width: parent.width; height: 26
                Rectangle {
                    id: spBack
                    width: 26; height: 26; radius: 7
                    color: spBackHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (spBackHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                    Icon { anchors.centerIn: parent; code: 0xEA60; font.pixelSize: 16; color: pop.dim }
                    HoverHandler { id: spBackHover }
                    ClickTap { onTapped: spp.mode = "list" }
                }
                Label { anchors { left: spBack.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                    text: "New Space"; font.pixelSize: 15 }
            }
            Label {
                visible: spp.mode === "new"
                text: spp.picked.length === 0 ? "Pick the workspaces to save" : spp.picked.length === 1 ? "1 workspace" : spp.picked.length + " workspaces"
                color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12
            }
            Label {
                visible: spp.mode === "new" && Spaces.live.length === 0
                width: parent.width
                text: "No workspace has apps open yet: open the apps you want, arranged how you like, then come back here."
                color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
            }
            // Each workspace with apps, drawn small over the wallpaper; click to pick it.
            // Three to a row; past two rows the rest scroll (a little of the third shows,
            // to say there's more)
            Item {
                id: wsBox
                visible: spp.mode === "new" && Spaces.live.length > 0
                width: parent.width
                readonly property bool overflow: Math.ceil(Spaces.live.length / 3) > 2
                readonly property real cardW: Math.floor((width - 16 - (overflow ? 18 : 0)) / 3)
                readonly property real rowH: Math.round(cardW / Math.max(1, (Spaces.live[0] || {}).aspect || 1.6)) + 5 + 17 + 8
                height: overflow ? Math.round(rowH * 2.4) : wsFlow.height
                Flickable {
                    id: wsFlick
                    anchors.fill: parent
                    contentHeight: wsFlow.height
                    clip: true
                    interactive: wsBox.overflow
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: wsFlick; enabled: wsBox.overflow }
                    Flow {
                        id: wsFlow
                        width: wsBox.width - (wsBox.overflow ? 18 : 0)
                        spacing: 8
                        Repeater {
                            model: Spaces.live
                            delegate: Column {
                                id: wsCard
                                required property var modelData
                                readonly property bool on: spp.picked.includes(modelData.id)
                                width: wsBox.cardW
                                spacing: 5
                                Rectangle {
                                    id: wsShot
                                    width: parent.width
                                    height: Math.round(width / Math.max(1, wsCard.modelData.aspect || 1.6))
                                    radius: 8
                                    color: Config.tint("#0b0d10")
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: Config.wallpaper ? "file://" + Config.wallpaper : ""
                                        sourceSize: Qt.size(320, 200)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        opacity: wsCard.on ? 0.75 : 0.4
                                        Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                                    }
                                    Repeater {
                                        // Tiled first, floating ones on top
                                        model: wsCard.modelData.windows.slice().sort((a, b) => a.floating - b.floating)
                                        delegate: Rectangle {
                                            id: wsWin
                                            required property var modelData
                                            x: wsShot.width * modelData.x; y: wsShot.height * modelData.y
                                            width: Math.max(6, wsShot.width * modelData.w - 1); height: Math.max(6, wsShot.height * modelData.h - 1)
                                            // The window's own rounding, scaled to the preview (but
                                            // enough to see; a square window stays square)
                                            radius: (modelData.rounding ?? 10) > 0
                                                ? Math.max(2.5, (modelData.rounding ?? 10) * wsShot.width / Math.max(1, wsCard.modelData.width || 1440)) : 0
                                            color: Qt.rgba(pop.card.r, pop.card.g, pop.card.b, 0.92)
                                            border.width: 1
                                            border.color: Qt.rgba(pop.text.r, pop.text.g, pop.text.b, 0.12)
                                            // The window itself, live while New Space is open
                                            // (as in the workspace overview)
                                            readonly property var toplevel: Hyprland.toplevels.values.find(t => "0x" + t.address === modelData.address || t.address === modelData.address) ?? null
                                            // Behind a see-through window: the wallpaper blurred as on
                                            // screen, from where the window sits on this card
                                            WallBlur {
                                                anchors.fill: wsLive
                                                win: Qt.rect(wsWin.modelData.x * wsShot.width, wsWin.modelData.y * wsShot.height,
                                                             wsWin.modelData.w * wsShot.width, wsWin.modelData.h * wsShot.height)
                                                screen: Qt.size(wsShot.width, wsShot.height)
                                                pixelScale: wsShot.width / Math.max(1, wsCard.modelData.width || 1440)
                                                radius: Math.max(0, wsWin.radius - 1)
                                                opacity: wsCard.on ? 1 : 0.6
                                            }
                                            ScreencopyView {
                                                id: wsLive
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                captureSource: pop.shown && spp.mode === "new" && wsWin.toplevel && wsWin.toplevel.wayland ? wsWin.toplevel.wayland : null
                                                live: pop.shown && spp.mode === "new"
                                                smooth: true
                                                // Clipped to the window's rounded corners
                                                layer.enabled: wsWin.radius > 0
                                                layer.effect: MultiEffect { maskEnabled: true; maskSource: wsLiveMask }
                                            }
                                            Item {
                                                id: wsLiveMask
                                                anchors.fill: wsLive
                                                visible: false
                                                layer.enabled: true
                                                Rectangle { anchors.fill: parent; radius: Math.max(0, wsWin.radius - 1) }
                                            }
                                            // Its app's icon on top, with a soft shadow so it
                                            // reads over whatever the window shows
                                            Item {
                                                anchors.centerIn: parent
                                                width: Math.min(22, wsWin.width * 0.6, wsWin.height * 0.6); height: width
                                                layer.enabled: wsLive.hasContent
                                                layer.effect: MultiEffect {
                                                    shadowEnabled: true
                                                    shadowColor: "black"
                                                    shadowOpacity: 0.55
                                                    shadowBlur: 0.6
                                                    shadowVerticalOffset: 1
                                                }
                                                AppTile {
                                                    anchors.fill: parent
                                                    app: wsWin.modelData.desktopId || wsWin.modelData["class"]
                                                }
                                            }
                                        }
                                    }
                                    // Picked: an accent ring and a tick
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: "transparent"
                                        border.width: wsCard.on ? 2 : 1
                                        border.color: wsCard.on ? pop.accent : wsShotHover.hovered ? pop.dim : Qt.rgba(pop.text.r, pop.text.g, pop.text.b, 0.1)
                                        Behavior on border.color { ColorAnimation { duration: Config.ms(120) } }
                                    }
                                    Rectangle {
                                        anchors { top: parent.top; right: parent.right; margins: 5 }
                                        width: 18; height: 18; radius: 9
                                        color: wsCard.on ? pop.accent : Qt.rgba(0, 0, 0, 0.45)
                                        border.width: wsCard.on ? 0 : 1.5
                                        border.color: Qt.rgba(1, 1, 1, 0.7)
                                        Icon { anchors.centerIn: parent; visible: wsCard.on; code: 0xEA5E; font.pixelSize: 12; color: pop.accentText }
                                    }
                                    HoverHandler { id: wsShotHover }
                                    ClickTap { onTapped: spp.toggle(wsCard.modelData.id) }
                                }
                                Label {
                                    width: parent.width
                                    readonly property int n: wsCard.modelData.windows.length
                                    text: "Workspace " + wsCard.modelData.id + " · " + (n === 1 ? "1 app" : n + " apps")
                                    color: wsCard.on ? pop.text : pop.dim
                                    font.weight: Font.Normal; font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
                ThinScrollbar { flick: wsFlick; color: pop.text; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }

            Label { visible: spp.mode === "new"; text: "Name"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
            Rectangle {
                visible: spp.mode === "new"
                width: parent.width; height: 34; radius: 8
                color: pop.card
                border.width: spName.activeFocus ? 1 : 0
                border.color: pop.accent
                TextInput {
                    id: spName
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: pop.text
                    font.family: bar.fontFamily
                    font.pixelSize: 13
                    maximumLength: 40
                    selectByMouse: true
                    text: spp.name
                    onTextEdited: spp.name = text
                    onVisibleChanged: if (visible) { text = spp.name; forceActiveFocus(); }
                    onAccepted: spp.save()
                    Keys.onEscapePressed: spp.mode = "list"
                }
                Label {
                    visible: spName.text === ""
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "e.g. Coding, Writing, Gaming"
                    color: pop.dim; font.weight: Font.Normal
                }
            }
            Label {
                visible: spp.mode === "new" && spp.sameName !== null
                width: parent.width
                text: "Saving replaces the space already called " + (spp.sameName ? spp.sameName.name : "")
                color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12; wrapMode: Text.Wrap
            }

            Label { visible: spp.mode === "new"; text: "Icon"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
            Grid {
                visible: spp.mode === "new"
                columns: 15
                spacing: 2
                Repeater {
                    model: Spaces.icons
                    delegate: Rectangle {
                        id: icCell
                        required property int modelData
                        readonly property bool on: spp.icon === modelData
                        width: (spp.width - 28) / 15; height: width; radius: 7
                        color: on ? spp.colour : icHover.hovered ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (on || icHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        Icon { anchors.centerIn: parent; code: icCell.modelData; font.pixelSize: 17; color: icCell.on ? spp.inkColour : icHover.hovered ? pop.text : pop.dim }
                        HoverHandler { id: icHover }
                        ClickTap { onTapped: spp.icon = icCell.modelData }
                    }
                }
            }

            Label { visible: spp.mode === "new"; text: "Colour"; color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12 }
            Grid {
                visible: spp.mode === "new"
                columns: 9
                readonly property real cell: 28
                columnSpacing: (spp.width - cell * 9) / 8
                rowSpacing: 10
                Repeater {
                    // The pastels, then your own colour
                    model: Spaces.colours.concat(["custom"])
                    delegate: Item {
                        id: swatch
                        required property string modelData
                        readonly property bool isCustom: modelData === "custom"
                        readonly property bool on: isCustom ? spp.custom : !spp.custom && Qt.colorEqual(spp.colour, modelData)
                        width: 28; height: 28
                        // A ring around the picked one
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: swatch.on ? pop.text : "transparent"
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: swatch.on ? 20 : swHover.hovered ? 24 : 22; height: width; radius: width / 2
                            color: swatch.isCustom ? (spp.custom ? spp.colour : "transparent") : swatch.modelData
                            Behavior on width { NumberAnimation { duration: Config.ms(100) } }
                            // Your own colour: a colour wheel until one is chosen
                            Canvas {
                                anchors.fill: parent
                                visible: swatch.isCustom && !spp.custom
                                onPaint: {
                                    const ctx = getContext("2d"), r = width / 2;
                                    ctx.reset();
                                    for (let i = 0; i < 36; i++) {
                                        ctx.beginPath();
                                        ctx.moveTo(r, r);
                                        ctx.arc(r, r, r, i / 36 * Math.PI * 2, (i + 1.2) / 36 * Math.PI * 2);
                                        ctx.closePath();
                                        ctx.fillStyle = Qt.hsla(i / 36, 0.65, 0.78, 1);
                                        ctx.fill();
                                    }
                                }
                                onWidthChanged: requestPaint()
                            }
                            Icon { anchors.centerIn: parent; visible: swatch.isCustom; code: 0xEBE6; font.pixelSize: 12; color: spp.inkColour }
                        }
                        HoverHandler { id: swHover }
                        ClickTap {
                            onTapped: {
                                if (swatch.isCustom) {
                                    if (!spp.custom) { spp.custom = true; spHex.text = spp.colour.toString().slice(0, 7); }
                                } else { spp.custom = false; spp.colour = swatch.modelData; }
                            }
                        }
                    }
                }
            }
            // Your own colour: drag along the hues, or type a hex value
            Row {
                visible: spp.mode === "new" && spp.custom
                width: parent.width
                spacing: 10
                Item {
                    id: hueStrip
                    width: parent.width - spHexBox.width - 10; height: 30
                    Canvas {
                        id: hueCanvas
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: 14
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const g = ctx.createLinearGradient(0, 0, width, 0);
                            for (let i = 0; i <= 12; i++) g.addColorStop(i / 12, Qt.hsla(i / 12, 0.65, 0.78, 1));
                            ctx.fillStyle = g;
                            ctx.beginPath();
                            ctx.roundedRect(0, 0, width, height, height / 2, height / 2);
                            ctx.fill();
                        }
                        onWidthChanged: requestPaint()
                    }
                    Rectangle {
                        readonly property real hue: Math.max(0, spp.colour.hslHue)
                        x: hue * (hueStrip.width - width)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: spp.colour
                        border.width: 2; border.color: pop.text
                    }
                    MouseArea {
                        anchors.fill: parent
                        function set(mx) {
                            const h = Math.max(0, Math.min(0.999, mx / width));
                            spp.colour = Qt.hsla(h, 0.65, 0.78, 1);
                            spHex.text = spp.colour.toString().slice(0, 7);
                        }
                        onPressed: m => set(m.x)
                        onPositionChanged: m => { if (pressed) set(m.x); }
                    }
                }
                Rectangle {
                    id: spHexBox
                    width: 92; height: 30; radius: 8
                    color: pop.card
                    border.width: spHex.activeFocus ? 1 : 0
                    border.color: pop.accent
                    TextInput {
                        id: spHex
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: pop.text
                        font.family: bar.fontFamily
                        font.pixelSize: 13
                        maximumLength: 7
                        selectByMouse: true
                        onTextEdited: {
                            const t = text.startsWith("#") ? text : "#" + text;
                            if (/^#[0-9a-fA-F]{6}$/.test(t)) spp.colour = t;
                        }
                        Keys.onEscapePressed: spp.mode = "list"
                    }
                }
            }

            Divider { visible: spp.mode === "new" }
            Row {
                visible: spp.mode === "new"
                anchors.right: parent.right
                spacing: 8
                Rectangle {
                    width: spCancel.implicitWidth + 28; height: 32; radius: 8
                    color: spCancelHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (spCancelHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                    Label { id: spCancel; anchors.centerIn: parent; text: "Cancel"; font.weight: Font.Normal }
                    HoverHandler { id: spCancelHover }
                    ClickTap { onTapped: spp.mode = "list" }
                }
                Rectangle {
                    width: spSave.implicitWidth + 28; height: 32; radius: 8
                    color: spp.canSave ? (spSaveHover.hovered ? Qt.lighter(pop.accent, 1.08) : pop.accent) : pop.card
                    Label { id: spSave; anchors.centerIn: parent; text: spp.sameName ? "Replace" : "Save"; color: spp.canSave ? pop.accentText : pop.dim }
                    HoverHandler { id: spSaveHover }
                    ClickTap { onTapped: spp.save() }
                }
            }
        }
    }

    // ---- Screenshots ------------------------------------------------------
    // Take one of an area, a window or the screen (scripts/screenshot.sh); the panel closes
    // first so it isn't in the picture
    Component {
        id: screenshotPanel
        Column {
            id: shp
            width: 300
            spacing: 10
            readonly property string folder: Config.s.screenshotFolder !== "" ? Config.s.screenshotFolder
                : Quickshell.env("HOME") + "/Pictures/Screenshots"
            function take(mode) {
                pop.close();
                Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$0\" \"$1\"", Quickshell.shellPath("scripts/screenshot.sh"), mode]);
            }
            Label { text: "Screenshot"; font.pixelSize: 15 }
            Row {
                width: parent.width
                spacing: 8
                Repeater {
                    model: [{ mode: "region", label: "Area", code: 0xEEAE },
                            { mode: "window", label: "Window", code: 0xEFE6 },
                            { mode: "screen", label: "Screen", code: 0xEA89 }]
                    delegate: Rectangle {
                        id: shotTile
                        required property var modelData
                        width: (shp.width - 16) / 3; height: 76
                        radius: 10
                        color: shotHover.hovered ? Config.hoverOn(pop.card) : pop.card
                        Gloss { radius: parent.radius; opacity: (shotHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; code: shotTile.modelData.code; font.pixelSize: 22; color: pop.text }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: shotTile.modelData.label; font.weight: Font.Normal }
                        }
                        HoverHandler { id: shotHover }
                        ClickTap { onTapped: shp.take(shotTile.modelData.mode) }
                    }
                }
            }
            Label {
                width: parent.width
                text: "Saved to " + shp.folder.replace(Quickshell.env("HOME"), "~") + " and copied"
                color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12; elide: Text.ElideMiddle
            }
            Divider {}
            RowButton {
                width: parent.width
                onClicked: { pop.close(); Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && exec xdg-open \"$0\"", shp.folder]); }
                Icon { id: shpFolderIcon; code: 0xEAAD; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: shpFolderIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Open screenshots folder"; font.weight: Font.Normal }
            }
            RowButton {
                width: parent.width
                onClicked: { pop.close(); Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "page", "screenshots"]); }
                Icon { id: shpSetIcon; code: 0xEB20; font.pixelSize: 16; color: pop.dim; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } }
                Label { anchors { left: shpSetIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Screenshot settings"; font.weight: Font.Normal }
            }
        }
    }

    // ---- Keyboard layout --------------------------------------------------
    // The layouts from Settings → Keyboard & Mouse; click one to switch to it
    Component {
        id: keyboardPanel
        Column {
            id: kbp
            width: 280
            spacing: 10
            Label { text: "Keyboard layout"; font.pixelSize: 15 }
            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: Config.kbLayoutList
                    delegate: RowButton {
                        id: layoutBtn
                        required property var modelData
                        required property int index
                        width: parent.width
                        selected: index === Config.kbActive
                        onClicked: Config.switchLayout(index)
                        // The short code in a little key cap, then the full name
                        Rectangle {
                            id: codeCap
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            width: Math.max(28, codeText.implicitWidth + 10); height: 22; radius: 5
                            color: layoutBtn.selected ? Qt.rgba(0, 0, 0, 0.15) : pop.card
                            Text {
                                id: codeText
                                anchors.centerIn: parent
                                text: layoutBtn.modelData.code
                                color: layoutBtn.selected ? pop.accentText : pop.text
                                font.family: bar.fontFamily; font.pixelSize: 11; font.weight: Font.Bold
                            }
                        }
                        Label {
                            anchors { left: codeCap.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: layoutBtn.modelData.name
                            color: layoutBtn.selected ? pop.accentText : pop.text
                        }
                    }
                }
            }
            Divider {}
            RowButton {
                width: parent.width
                onClicked: {
                    pop.close();
                    Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "page", "input"]);
                }
                Icon {
                    id: kbSettingsIcon
                    code: 0xEB20; font.pixelSize: 16; color: pop.dim
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors { left: kbSettingsIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Keyboard settings"
                    font.weight: Font.Normal
                }
            }
        }
    }

    // ---- Bluetooth --------------------------------------------------------
    // On/off, then paired devices (click one to connect or disconnect), then Settings for
    // finding and pairing new ones
    Component {
        id: bluetoothPanel
        Column {
            id: btp
            width: 300
            spacing: 10
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property bool on: !!adapter && adapter.enabled
            readonly property var devices: on ? adapter.devices.values.filter(d => d.paired || d.bonded || d.connected).slice()
                .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || "")) : []
            function iconFor(d) {
                const i = (d.icon || "").toLowerCase();
                if (i.includes("headset") || i.includes("headphone") || i.includes("audio")) return 0xEABD;
                if (i.includes("gam") || i.includes("joystick")) return 0xF1D2;
                if (i.includes("mouse")) return 0xEAF9;
                if (i.includes("keyboard")) return 0xEBD6;
                if (i.includes("phone")) return 0xEA8A;
                return 0xEA37;
            }

            Item {
                width: parent.width; height: 26
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; font.pixelSize: 15 }
                // On/off switch
                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: !!btp.adapter
                    width: 40; height: 22; radius: 11
                    color: btp.on ? pop.accent : pop.card
                    Gloss { radius: parent.radius }   // glass: a sheen
                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: btp.on ? parent.width - width - 3 : 3
                        color: btp.on ? pop.accentText : pop.text
                        Behavior on x { NumberAnimation { duration: Config.ms(120) } }
                    }
                    ClickTap { onTapped: if (btp.adapter) btp.adapter.enabled = !btp.adapter.enabled }
                }
            }

            Label {
                visible: !btp.on || btp.devices.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                color: pop.dim
                font.pixelSize: 12
                font.weight: Font.Normal
                text: !btp.adapter ? "No Bluetooth adapter found" : !btp.on ? "Bluetooth is off"
                    : "No paired devices yet. Pair one in Bluetooth settings"
            }
            Column {
                visible: btp.on && btp.devices.length > 0
                width: parent.width
                spacing: 6
                Repeater {
                    model: btp.devices
                    delegate: RowButton {
                        id: devRow
                        required property var modelData
                        readonly property var d: modelData
                        readonly property bool busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
                        width: parent.width
                        height: 44
                        selected: d.connected
                        onClicked: d.connected ? d.disconnect() : d.connect()
                        Icon {
                            id: devIcon
                            code: btp.iconFor(devRow.d)
                            color: devRow.selected ? pop.accentText : pop.text
                            font.pixelSize: 17
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        }
                        Column {
                            anchors { left: devIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Label {
                                width: parent.width
                                text: devRow.d.name || devRow.d.deviceName || devRow.d.address
                                color: devRow.selected ? pop.accentText : pop.text
                            }
                            Label {
                                width: parent.width
                                font.pixelSize: 11; font.weight: Font.Normal
                                color: devRow.selected ? pop.accentText : pop.dim
                                opacity: devRow.selected ? 0.8 : 1
                                text: devRow.busy ? (devRow.d.connected ? "Disconnecting…" : "Connecting…")
                                    : devRow.d.connected ? "Connected" + (devRow.d.batteryAvailable ? " · " + Math.round(devRow.d.battery * 100) + "% battery" : "")
                                    : "Not connected"
                            }
                        }
                    }
                }
            }

            Divider {}
            RowButton {
                width: parent.width
                onClicked: {
                    pop.close();
                    Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "page", "bluetooth"]);
                }
                Icon {
                    id: btSettingsIcon
                    code: 0xEB20; font.pixelSize: 16; color: pop.dim
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors { left: btSettingsIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: "Bluetooth settings"
                    font.weight: Font.Normal
                }
            }
        }
    }

    // ---- Battery & power ---------------------------------------------------
    Component {
        id: batteryPanel
        Column {
            id: bat
            width: 300
            spacing: 12
            readonly property var dev: UPower.displayDevice
            readonly property real pct: dev && dev.ready ? dev.percentage : 0
            readonly property int st: dev ? dev.state : 0
            function duration(sec) {
                if (!sec || sec <= 0) return "";
                const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
                return h > 0 ? `${h} h ${m} min` : `${m} min`;
            }
            readonly property string stateText:
                st === UPowerDeviceState.Charging ? "Charging" + (duration(dev.timeToFull) ? " · full in " + duration(dev.timeToFull) : "")
                : st === UPowerDeviceState.FullyCharged ? "Fully charged"
                : st === UPowerDeviceState.Discharging ? "On battery" + (duration(dev.timeToEmpty) ? " · " + duration(dev.timeToEmpty) + " left" : "")
                : UPower.onBattery ? "On battery" : "Plugged in"

            Row {
                spacing: 10
                Icon {
                    code: UPower.onBattery ? 0xEA34 : 0xEA33
                    font.pixelSize: 24
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: Math.round(bat.pct * 100) + "%"; font.pixelSize: 20 }
                    Label { text: bat.stateText; color: pop.dim; font.pixelSize: 12 }
                }
            }
            // Charge bar
            Rectangle {
                width: parent.width; height: 6; radius: 3
                color: pop.card
                Rectangle {
                    width: parent.width * bat.pct; height: parent.height; radius: 3
                    color: bat.pct < 0.15 && UPower.onBattery ? pop.danger : pop.accent
                    Gloss { radius: parent.radius }   // glass: a sheen
                }
            }

            Divider {}
            Label { text: "Power mode"; color: pop.dim; font.pixelSize: 12 }
            Row {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { p: PowerProfile.PowerSaver, label: "Saver", code: 0xED4F },
                        { p: PowerProfile.Balanced, label: "Balanced", code: 0xEBC2 },
                        { p: PowerProfile.Performance, label: "Performance", code: 0xEC45 }
                    ].filter(x => x.p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
                    delegate: RowButton {
                        required property var modelData
                        width: (bat.width - 12) / 3
                        height: 56
                        selected: PowerProfiles.profile === modelData.p
                        onClicked: PowerProfiles.profile = modelData.p
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                code: parent.parent.modelData.code
                                font.pixelSize: 18
                                color: parent.parent.selected ? pop.accentText : pop.text
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.parent.modelData.label
                                font.pixelSize: 12
                                color: parent.parent.selected ? pop.accentText : pop.text
                            }
                        }
                    }
                }
            }

            // ---- System: CPU, memory and the main drive, refreshed while the panel is open
            Divider {}
            Label { text: "System"; color: pop.dim; font.pixelSize: 12 }
            property real cpu: 0                 // 0..1
            property var lastCpu: null           // [busy, total] from the previous reading
            property real memUsed: 0
            property real memTotal: 0
            property real diskUsed: 0
            property real diskTotal: 0
            FileView { id: statFile; path: "/proc/stat" }
            FileView { id: memFile; path: "/proc/meminfo" }
            Process {
                id: diskInfo
                command: ["df", "-B1", "--output=size,used", "/"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const f = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                        if (f.length === 2 && !isNaN(f[0])) { bat.diskTotal = f[0]; bat.diskUsed = f[1]; }
                    }
                }
            }
            function sample() {
                statFile.reload(); memFile.reload();
                const c = (statFile.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number);
                if (c.length >= 4) {
                    const idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
                    if (lastCpu) {
                        const dt = total - lastCpu[1], dbusy = (total - idle) - lastCpu[0];
                        if (dt > 0) cpu = Math.max(0, Math.min(1, dbusy / dt));
                    }
                    lastCpu = [total - idle, total];
                }
                const mem = {};
                for (const line of memFile.text().split("\n")) {
                    const mm = /^(\w+):\s+(\d+)/.exec(line);
                    if (mm) mem[mm[1]] = Number(mm[2]) * 1024;
                }
                if (mem.MemTotal) { memTotal = mem.MemTotal; memUsed = mem.MemTotal - (mem.MemAvailable || mem.MemFree || 0); }
                if (!diskInfo.running) diskInfo.running = true;
            }
            Timer {
                interval: 2000; repeat: true; triggeredOnStart: true
                running: pop.shown && pop.displayed === "battery"
                onTriggered: bat.sample()
            }
            // Shown values glide from one reading to the next (readings come every 2s)
            property real cpuShown: cpu
            property real memShown: memTotal ? memUsed / memTotal : 0
            property real diskShown: diskTotal ? diskUsed / diskTotal : 0
            Behavior on cpuShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
            Behavior on memShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
            Behavior on diskShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
            function gb(bytes) {
                const g = bytes / 1e9;
                return g >= 1000 ? (g / 1000).toFixed(1) + " TB" : g >= 100 ? Math.round(g) + " GB" : g.toFixed(1) + " GB";
            }
            // A fixed list, so the meters stay put (and animate) as the readings change
            Repeater {
                model: ["CPU", "Memory", "Disk"]
                delegate: Column {
                    required property string modelData
                    readonly property real frac: modelData === "CPU" ? bat.cpuShown : modelData === "Memory" ? bat.memShown : bat.diskShown
                    readonly property string value: modelData === "CPU" ? Math.round(bat.cpuShown * 100) + "%"
                        : modelData === "Memory" ? (bat.memTotal ? (bat.memShown * bat.memTotal / 1e9).toFixed(1) + " / " + (bat.memTotal / 1e9).toFixed(1) + " GB" : "")
                        : (bat.diskTotal ? bat.gb(bat.diskShown * bat.diskTotal) + " / " + bat.gb(bat.diskTotal) : "")
                    width: bat.width
                    spacing: 5
                    Item {
                        width: parent.width; height: meterLabel.height
                        Label { id: meterLabel; text: parent.parent.modelData; font.pixelSize: 12 }
                        Label {
                            anchors.right: parent.right
                            text: parent.parent.value
                            color: pop.dim; font.pixelSize: 12
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 6; radius: 3
                        color: pop.card
                        Rectangle {
                            width: Math.max(height, parent.width * Math.min(1, parent.parent.frac))
                            height: parent.height; radius: 3
                            // Red when above 80%
                            color: parent.parent.frac > 0.8 ? pop.danger : pop.accent
                            Gloss { radius: parent.radius }   // glass: a sheen
                            Behavior on color { ColorAnimation { duration: Config.ms(300) } }
                        }
                    }
                }
            }
        }
    }

    // ---- Calendar ----------------------------------------------------------
    Component {
        id: calendarPanel
        Column {
            id: cal
            width: 280
            spacing: 10
            SystemClock { id: calClock; precision: SystemClock.Minutes }
            readonly property date today: calClock.date
            property int monthOffset: 0
            readonly property date shownMonth: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)

            // Weather, when a location is set (Settings → General → Location) and it has loaded
            readonly property bool hasWeather: Config.s.locationName !== "" && pop.weather !== null

            Item {
                width: parent.width
                height: Math.max(timeCol.height, nowWeather.height)
                Column {
                    id: timeCol
                    spacing: 2
                    Label { text: Qt.formatTime(cal.today, "h:mm AP"); font.pixelSize: 22 }
                    Label { text: Qt.formatDate(cal.today, "dddd, d MMMM yyyy"); color: pop.dim; font.pixelSize: 12 }
                }
                // Now: icon and temperature, conditions and place underneath
                Column {
                    id: nowWeather
                    visible: cal.hasWeather
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Row {
                        anchors.right: parent.right
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            code: pop.weather ? pop.weatherInfo(pop.weather.weather_code).icon : 0
                            color: pop.accent
                            font.pixelSize: 20
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pop.weather ? Math.round(pop.weather.temperature_2m) + "°" : ""
                            font.pixelSize: 20
                        }
                    }
                    Label {
                        anchors.right: parent.right
                        text: pop.weather ? pop.weatherInfo(pop.weather.weather_code).text + " · " + Config.s.locationName : ""
                        color: pop.dim; font.pixelSize: 11
                        width: Math.min(implicitWidth, 130)
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
            Divider {}
            Item {
                width: parent.width; height: 26
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(cal.shownMonth, "MMMM yyyy")
                    font.pixelSize: 14
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Repeater {
                        model: [{ code: 0xEA60, d: -1 }, { code: 0xEA61, d: 1 }]
                        delegate: RowButton {
                            required property var modelData
                            width: 28; height: 26
                            onClicked: cal.monthOffset += modelData.d
                            Icon { anchors.centerIn: parent; code: parent.modelData.code; font.pixelSize: 15 }
                        }
                    }
                }
            }
            Grid {
                id: grid
                columns: 7
                readonly property real cell: cal.width / 7
                // Weekday initials, Monday first
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Label {
                        required property string modelData
                        width: grid.cell; height: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: pop.dim
                        font.pixelSize: 11
                    }
                }
                Repeater {
                    model: 42
                    delegate: Item {
                        required property int index
                        readonly property int lead: (cal.shownMonth.getDay() + 6) % 7
                        readonly property date day: new Date(cal.shownMonth.getFullYear(), cal.shownMonth.getMonth(), index - lead + 1)
                        readonly property bool inMonth: day.getMonth() === cal.shownMonth.getMonth()
                        readonly property bool isToday: day.toDateString() === cal.today.toDateString()
                        width: grid.cell; height: 32
                        Rectangle {
                            anchors.centerIn: parent
                            width: 28; height: 28; radius: 14
                            color: parent.isToday ? pop.accent : "transparent"
                        }
                        Label {
                            anchors.centerIn: parent
                            text: parent.day.getDate()
                            color: parent.isToday ? pop.accentText : parent.inMonth ? pop.text : Config.tint("#4f5866")
                            font.pixelSize: 12
                        }
                    }
                }
            }
            // The next few days
            Divider { visible: cal.hasWeather && pop.forecast !== null }
            Row {
                visible: cal.hasWeather && pop.forecast !== null
                width: parent.width
                spacing: 6
                Repeater {
                    model: pop.forecast ? Math.min(4, pop.forecast.time.length - 1) : 0
                    delegate: Rectangle {
                        required property int index
                        readonly property int day: index + 1
                        width: (cal.width - 18) / 4; height: 64; radius: 9
                        color: pop.card
                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDate(new Date(pop.forecast.time[parent.parent.day] + "T12:00"), "ddd")
                                color: pop.dim; font.pixelSize: 11
                            }
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                code: pop.weatherInfo(pop.forecast.weather_code[parent.parent.day]).icon
                                font.pixelSize: 16
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(pop.forecast.temperature_2m_max[parent.parent.day]) + "° "
                                    + "<font color='" + pop.dim + "'>" + Math.round(pop.forecast.temperature_2m_min[parent.parent.day]) + "°</font>"
                                textFormat: Text.StyledText
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
            // Reset to the current month each time the panel opens
            Connections { target: pop; function onCurrentChanged() { if (pop.current === "calendar") cal.monthOffset = 0; } }
        }
    }

    // ---- Session -----------------------------------------------------------
    Component {
        id: sessionPanel
        Column {
            id: ses
            width: 220
            spacing: 6
            Repeater {
                model: [
                    { id: "lock", label: "Lock", code: 0xEAE2, confirm: false },
                    { id: "lock_and_suspend", label: "Suspend", code: 0xF228, confirm: false },
                    { id: "logout", label: "Log out", code: 0xEBA8, confirm: true },
                    { id: "reboot", label: "Restart", code: 0xEB13, confirm: true },
                    { id: "shutdown", label: "Shut down", code: 0xEB0D, confirm: true }
                ]
                delegate: RowButton {
                    required property var modelData
                    width: ses.width
                    height: 40
                    onClicked: {
                        pop.close();
                        if (modelData.confirm && pop.powerConfirm) pop.powerConfirm.ask(modelData.id);
                        else if (modelData.id === "lock") Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "lock"]);
                        else if (modelData.id === "lock_and_suspend")   // lock first, then sleep
                            Quickshell.execDetached(["sh", "-c", "\"$0\" ipc call lock lock; sleep 0.6; systemctl suspend", Quickshell.shellPath("bin/slate")]);
                        else Config.sessionAction(modelData.id);
                    }
                    Icon {
                        id: sIcon
                        code: parent.modelData.code
                        color: parent.modelData.id === "shutdown" ? pop.danger : pop.text
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    }
                    Label {
                        anchors { left: sIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.label
                    }
                }
            }
        }
    }

    // ---- Control centre ----------------------------------------------------
    Component {
        id: controlPanel
        Column {
            id: cc
            width: 470
            spacing: 12
            readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

            // Profile
            Rectangle {
                id: profileCard
                width: parent.width; height: 80; radius: 12
                color: pop.card
                // Wallpaper behind the card, fading into it from the left
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    // (maskSpreadAtMin: the mask's see-through parts blend rather than cut off,
                    // so glass's fading mask works)
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: profileMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                    Image {
                        anchors.fill: parent
                        // Loaded ahead of time (profileWallpaper), so loading it here is instant
                        // from the cache: there as the panel opens. (Loaded in the background
                        // instead, it wasn't ready for a frame and faded in.)
                        source: pop.profileWallpaper
                        sourceSize.width: pop.profileWallpaperWidth
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                    }
                    // (With glass the card is see-through, so a fade in its colour wouldn't
                    // show: the picture itself fades in instead, through the mask below)
                    Rectangle {
                        visible: !Config.glass
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: pop.card }
                            GradientStop { position: 0.35; color: Qt.rgba(pop.card.r, pop.card.g, pop.card.b, 0.92) }
                            GradientStop { position: 1.0; color: Qt.rgba(pop.card.r, pop.card.g, pop.card.b, 0.35) }
                        }
                    }
                }
                Item {
                    id: profileMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent; radius: profileCard.radius
                        // Glass: the wallpaper fades in from the left, over the frosted card
                        gradient: Config.glass ? glassFade : null
                        color: "white"
                        Gradient {
                            id: glassFade
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.08) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.65) }
                        }
                    }
                }
                RoundImage {
                    id: avatar
                    width: 56; height: 56; radius: 28
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    source: Config.avatarUrl
                    // Hover: greyed and dimmed with a pencil; click to change the picture
                    saturation: avatarHover.hovered ? -1 : 0
                    brightness: avatarHover.hovered ? -0.45 : 0
                    Behavior on saturation { NumberAnimation { duration: Config.ms(150) } }
                    Behavior on brightness { NumberAnimation { duration: Config.ms(150) } }
                    Icon {
                        anchors.centerIn: parent
                        code: 0xEB04
                        color: "white"
                        opacity: avatarHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                    }
                    HoverHandler { id: avatarHover }
                    ClickTap {
                        onTapped: {
                            pop.close();
                            Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "avatar"]);
                        }
                    }
                }
                Column {
                    anchors { left: avatar.right; leftMargin: 14; verticalCenter: parent.verticalCenter; right: ccButtons.left; rightMargin: 8 }
                    spacing: 2
                    Label { width: parent.width; text: pop.fullName; font.pixelSize: 16 }
                    Label { width: parent.width; text: Quickshell.env("USER") + "@" + hostFile.text().trim(); color: pop.dim; font.pixelSize: 12 }
                    Label { width: parent.width; text: pop.uptimeText() + (pop.hyprVersion ? " · Hyprland " + pop.hyprVersion : ""); color: pop.dim; font.pixelSize: 12 }
                }
                Row {
                    id: ccButtons
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: [{ code: 0xEB20, act: "settings" }, { code: 0xEB0D, act: "session" }]
                        delegate: RowButton {
                            required property var modelData
                            width: 34; height: 34
                            // Over the wallpaper, so they need to stand out from whatever it is: the
                            // solid card colour, mostly opaque (not the glass card colour, which is
                            // already see-through white), a faint light edge and the sheen
                            readonly property color base: Config.tint("#1d222a")
                            color: hovered2.hovered ? Config.hoverOn(base) : Qt.rgba(base.r, base.g, base.b, 0.82)
                            border.width: 1
                            border.color: Qt.rgba(pop.text.r, pop.text.g, pop.text.b, hovered2.hovered ? 0.22 : 0.14)
                            // glass: a sheen (RowButton's own takes over while hovered)
                            Gloss { radius: parent.radius; opacity: hovered2.hovered ? 0 : 1 }
                            HoverHandler { id: hovered2 }
                            onClicked: {
                                if (modelData.act === "settings") { pop.close(); Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "settings", "open"]); }
                                else { pop.anchorX = pop.width - 40; pop.displayed = "session"; pop.current = "session"; }
                            }
                            Icon { anchors.centerIn: parent; code: parent.modelData.code; color: parent.modelData.act === "session" ? pop.danger : pop.text }
                        }
                    }
                }
            }

            Row {
                spacing: 12
                // Left: media, then clock & weather
                Column {
                    id: ccLeft
                    width: 262
                    spacing: 12

                    Rectangle {
                        visible: cc.player !== null
                        width: parent.width; height: 104; radius: 12
                        color: pop.card
                        Item {
                            visible: cc.player !== null
                            anchors { fill: parent; margins: 12 }
                            RoundImage {
                                id: art
                                width: 80; height: 80; radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                source: cc.player ? cc.player.trackArtUrl : ""
                                visible: cc.player && cc.player.trackArtUrl !== ""
                            }
                            Column {
                                anchors { left: art.visible ? art.right : parent.left; leftMargin: art.visible ? 12 : 0; right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Label { width: parent.width; text: cc.player ? (cc.player.trackTitle || cc.player.identity) : "" }
                                Label { width: parent.width; text: cc.player ? (cc.player.trackArtist || "") : ""; color: pop.dim; font.pixelSize: 12 }
                                Row {
                                    spacing: 4
                                    topPadding: 6
                                    Repeater {
                                        model: [
                                            { code: 0xF693, act: "prev" },
                                            { code: cc.player && cc.player.isPlaying ? 0xF690 : 0xF691, act: "play" },
                                            { code: 0xF694, act: "next" }
                                        ]
                                        delegate: RowButton {
                                            required property var modelData
                                            width: 32; height: 30
                                            onClicked: {
                                                const p = cc.player; if (!p) return;
                                                if (modelData.act === "prev") p.previous();
                                                else if (modelData.act === "next") p.next();
                                                else p.togglePlaying();
                                            }
                                            Icon { anchors.centerIn: parent; code: parent.modelData.code; font.pixelSize: 16 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: clockCard
                        // Nothing playing: take the media card's space too
                        readonly property bool roomy: cc.player === null
                        width: parent.width; height: roomy ? 104 + 12 + 92 : 92; radius: 12
                        color: pop.card
                        SystemClock { id: ccClock; precision: SystemClock.Minutes }
                        Column {
                            anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14 }
                            anchors.verticalCenter: clockCard.roomy ? undefined : parent.verticalCenter
                            anchors.top: clockCard.roomy ? parent.top : undefined
                            anchors.topMargin: 14
                            spacing: 2
                            Label { text: Qt.formatTime(ccClock.date, "h:mm AP"); font.pixelSize: clockCard.roomy ? 32 : 24 }
                            Label { text: Qt.formatDate(ccClock.date, "dddd, d MMMM"); color: pop.dim; font.pixelSize: 12 }
                            Row {
                                visible: pop.weather !== null
                                spacing: 6
                                topPadding: 2
                                Icon {
                                    code: pop.weather ? pop.weatherInfo(pop.weather.weather_code).icon : 0
                                    font.pixelSize: 14; color: pop.dim
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Label {
                                    text: !pop.weather ? ""
                                        : Math.round(pop.weather.temperature_2m) + "°C · " + pop.weatherInfo(pop.weather.weather_code).text
                                          + (clockCard.roomy && pop.weather.apparent_temperature !== undefined
                                             ? " · feels " + Math.round(pop.weather.apparent_temperature) + "°" : "")
                                    color: pop.dim; font.pixelSize: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Label {
                                visible: clockCard.roomy && pop.forecast !== null
                                text: pop.forecast ? "High " + Math.round(pop.forecast.temperature_2m_max[0]) + "° · Low " + Math.round(pop.forecast.temperature_2m_min[0]) + "°" : ""
                                color: pop.dim; font.pixelSize: 12
                            }
                        }
                        // Next few days
                        Row {
                            visible: clockCard.roomy && pop.forecast !== null
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                            spacing: 6
                            Repeater {
                                model: pop.forecast ? Math.min(4, pop.forecast.time.length - 1) : 0
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int day: index + 1
                                    width: (parent.width - 18) / 4; height: 76; radius: 9
                                    // A faint wash over the card: white on dark; on light, where white
                                    // vanished, a shade darker
                                    color: Config.s.lightMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                                    border.width: 0
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatDate(new Date(pop.forecast.time[parent.parent.day] + "T12:00"), "ddd")
                                            color: pop.dim; font.pixelSize: 11
                                        }
                                        Icon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            code: pop.weatherInfo(pop.forecast.weather_code[parent.parent.day]).icon
                                            font.pixelSize: 18
                                        }
                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(pop.forecast.temperature_2m_max[parent.parent.day]) + "° "
                                                + "<font color='" + pop.dim + "'>" + Math.round(pop.forecast.temperature_2m_min[parent.parent.day]) + "°</font>"
                                            textFormat: Text.StyledText
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right: quick toggles, as tall as the column beside them
                Grid {
                    id: ccTiles
                    columns: 2
                    spacing: 8
                    readonly property real tileW: (cc.width - 262 - 12 - 8) / 2
                    readonly property int rowCount: Math.ceil(6 / columns)
                    readonly property real tileH: (ccLeft.height - spacing * (rowCount - 1)) / rowCount
                    Repeater {
                        model: [
                            { id: "wifi", label: Networking.wifiEnabled ? "Wi-Fi" : "Wi-Fi off", on: Networking.wifiEnabled, code: Networking.wifiEnabled ? 0xEB52 : 0xECFA },
                            { id: "bt", label: "Bluetooth", on: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false, code: 0xEA37 },
                            { id: "caffeine", label: "Caffeine", on: pop.caffeine, code: 0xEF0E },
                            { id: "night", label: "Night Light", on: pop.nightLight, code: 0xEAF8 },
                            { id: "dnd", label: "Do Not Disturb", on: pop.notifs ? pop.notifs.dnd : false, code: 0xECE9 },
                            { id: "perf", label: "Performance", on: PowerProfiles.profile === PowerProfile.Performance, code: 0xEC45 }
                        ]
                        delegate: RowButton {
                            required property var modelData
                            width: ccTiles.tileW
                            height: ccTiles.tileH
                            radius: 12
                            selected: modelData.on
                            // On ones light up too when pointed at (a lighter accent), as they can be turned off
                            color: selected ? (tileHover.hovered ? Qt.lighter(pop.accent, 1.12) : pop.accent)
                                : tileHover.hovered ? Config.hoverOn(pop.card) : pop.card
                            Gloss { radius: parent.radius; opacity: (selected || tileHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                            HoverHandler { id: tileHover }
                            onClicked: {
                                switch (modelData.id) {
                                case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break;
                                case "bt": if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; break;
                                case "caffeine": pop.caffeine = !pop.caffeine; break;
                                case "night": Config.s.nightLight = !Config.s.nightLight; break;
                                case "dnd": if (pop.notifs) pop.notifs.dnd = !pop.notifs.dnd; break;
                                case "perf": PowerProfiles.profile = modelData.on ? PowerProfile.Balanced : PowerProfile.Performance; break;
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                spacing: 3
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    code: parent.parent.modelData.code
                                    color: parent.parent.selected ? pop.accentText : pop.text
                                }
                                Label {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: parent.parent.modelData.label
                                    font.pixelSize: 11
                                    color: parent.parent.selected ? pop.accentText : pop.text
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Notifications -----------------------------------------------------
    Component {
        id: notificationsPanel
        Column {
            id: np
            width: 380
            spacing: 10
            readonly property var list: pop.notifs ? pop.notifs.history : []

            Item {
                width: parent.width; height: 28
                Label { anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; font.pixelSize: 15 }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "Do not disturb"; color: pop.dim; font.pixelSize: 12 }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 22; radius: 11
                        readonly property bool on: pop.notifs ? pop.notifs.dnd : false
                        color: on ? pop.accent : pop.card
                        Gloss { radius: parent.radius }   // glass: a sheen
                        Rectangle {
                            width: 16; height: 16; radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.on ? parent.width - width - 3 : 3
                            color: parent.on ? pop.accentText : pop.text
                            Behavior on x { NumberAnimation { duration: Config.ms(120) } }
                        }
                        ClickTap { onTapped: if (pop.notifs) pop.notifs.dnd = !pop.notifs.dnd }
                    }
                    RowButton {
                        visible: np.list.length > 0
                        width: 30; height: 28
                        onClicked: if (pop.notifs) pop.notifs.clearAll()
                        Icon { anchors.centerIn: parent; code: 0xEB41; font.pixelSize: 16; color: pop.dim }
                    }
                }
            }

            Item {
                visible: np.list.length === 0
                width: parent.width; height: 120
                Column {
                    anchors.centerIn: parent
                    spacing: 8
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; code: 0xEA35; font.pixelSize: 26; color: pop.dim }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: "No notifications"; color: pop.dim }
                }
            }

            ListView {
                id: nList
                visible: np.list.length > 0
                width: parent.width
                height: Math.min(contentHeight, 480)
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: np.list
                readonly property bool overflowing: contentHeight > height
                SmoothWheel { flick: nList }
                delegate: NotificationCard {
                    required property var modelData
                    width: nList.width - (nList.overflowing ? 18 : 0)   // room for the scrollbar and a gap before it
                    bar: pop.bar
                    inPanel: true
                    entry: modelData
                    notif: pop.notifs ? (pop.notifs.live[modelData.key] ?? null) : null
                    onActivated: { pop.notifs.activate(modelData.key); pop.close(); }
                    onClosed: pop.notifs.remove(modelData.key)
                    onAction: id => { pop.notifs.invokeAction(modelData.key, id); pop.close(); }
                }
                remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Config.ms(150) } }
                displaced: Transition { NumberAnimation { property: "y"; duration: Config.ms(180); easing.type: Easing.OutCubic } }

                // Scrollbar (ThinScrollbar, as everywhere), only when the list overflows
                ThinScrollbar {
                    parent: nList
                    flick: nList
                    color: pop.text
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                }

                // Shadow at the top once scrolled down. Parented to the list itself (not its
                // scrolling content) so it stays put.
                Rectangle {
                    parent: nList
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 36
                    // Fades with the distance from the edge, gone just as you reach it
                    opacity: Math.max(0, Math.min(1, (nList.contentY - nList.originY) / 24))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: pop.bg }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                // …and at the bottom while there's more to scroll to
                Rectangle {
                    parent: nList
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 36
                    opacity: Math.max(0, Math.min(1, (nList.originY + nList.contentHeight - nList.height - nList.contentY) / 24))
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: pop.bg }
                    }
                }
            }
        }
    }
}
