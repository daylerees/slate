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
import qs

// ---- Control centre ----------------------------------------------------
Column {
    required property var pop
    id: controlView
    width: 470
    spacing: 12
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property bool testAvatarFallback: avatar.showingFallback   // (the test state's avatarFallback)

    // Profile
    Rectangle {
        id: profileCard
        width: parent.width; height: 80; radius: Config.corner(12)
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
            width: 56; height: 56; radius: Config.corner(28)
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            source: Config.avatarUrl
        fallback: true      // no account picture: the themed person icon
            // Hover (or the keyboard on it): greyed and dimmed with a pencil; click to change the picture
            readonly property bool pointed: avatarHover.hovered || activeFocus
            saturation: pointed ? -1 : 0
            brightness: pointed ? -0.45 : 0
            Behavior on saturation { NumberAnimation { duration: Config.ms(150) } }
            Behavior on brightness { NumberAnimation { duration: Config.ms(150) } }
            Icon {
                anchors.centerIn: parent
                code: 0xEB04
                color: "white"
                opacity: avatar.pointed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
            }
            HoverHandler { id: avatarHover }
            function change() { pop.close(); pop.slate(["settings", "avatar"]); }
            ClickTap { onTapped: avatar.change() }
            // (the keyboard and a screen reader: a button)
            Accessible.role: Accessible.Button
            Accessible.name: "Change your picture"
            Accessible.onPressAction: avatar.change()
            activeFocusOnTab: visible
            Keys.onPressed: e => {
                if (e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter && e.key !== Qt.Key_Space) return;
                avatar.change();
                e.accepted = true;
            }
            FocusRing { round: 30 }
        }
        Column {
            anchors { left: avatar.right; leftMargin: 14; verticalCenter: parent.verticalCenter; right: ccButtons.left; rightMargin: 8 }
            spacing: 2
            Label { width: parent.width; text: pop.fullName; font.pixelSize: Config.text(16) }
            Label { width: parent.width; text: Quickshell.env("USER") + "@" + hostFile.text().trim(); color: pop.dim; font.pixelSize: Config.text(12) }
            Label { width: parent.width; text: pop.uptimeText() + (pop.hyprVersion ? " · Hyprland " + pop.hyprVersion : ""); color: pop.dim; font.pixelSize: Config.text(12) }
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
                    // Flat and solid, with glass too: the card's own solid colour, no edge and
                    // nothing showing through; under the pointer, the muted hover over it
                    readonly property color base: Config.tint("#1d222a")
                    color: controlButtonHover.hovered ? Qt.tint(base, Config.hover) : base
                    HoverHandler { id: controlButtonHover }
                    onClicked: {
                        if (modelData.act === "settings") { pop.close(); pop.slate(["settings", "open"]); }
                        else { pop.anchorX = pop.width - 40; pop.displayed = "session"; pop.current = "session"; }
                    }
                    Icon { anchors.centerIn: parent; code: parent.modelData.code; color: parent.modelData.act === "session" ? pop.danger : pop.text }
                }
            }
        }
    }

    // Under your name: the clock and what's playing on the left, the quick toggles on the
    // right, the two sides the same height
    Item {
        id: ccBody
        width: parent.width
        readonly property int count: ccTiles.toggles.length
        readonly property bool playing: controlView.player !== null
        readonly property real rightW: count > 0 ? 208 : 0
        readonly property real leftW: count > 0 ? width - rightW - 12 : width      // (no toggles chosen: the whole width)
        height: 248

        Column {
            id: ccLeft
            width: ccBody.leftW
            spacing: 12

            // The time, and the weather as it is now; with room (nothing playing), the days to come
            Rectangle {
                id: clockCard
                width: parent.width
                height: ccBody.height - (ccBody.playing ? 104 + 12 : 0)
                radius: Config.corner(12)
                color: pop.card
                readonly property bool days: height >= 200 && pop.forecast !== null
                SystemClock { id: ccClock; precision: SystemClock.Minutes }
                Column {
                    id: ccNowText
                    x: 14; width: parent.width - 28
                    // (no weather to show: the time sits in the middle)
                    y: pop.weather ? 12 : (parent.height - height) / 2
                    spacing: 1
                    Label {
                        text: Qt.formatTime(Config.clockDate(ccClock.date), pop.timeFormat)
                        font.pixelSize: Config.text(34); font.weight: Font.DemiBold
                    }
                    Label { width: parent.width; text: Config.dateText(Config.clockDate(ccClock.date), "longDay"); color: pop.dim; font.pixelSize: Config.text(12) }
                    Item { width: 1; height: 8; visible: pop.weather !== null }
                    Label {
                        visible: pop.weather !== null
                        width: parent.width
                        text: !pop.weather ? "" : pop.weatherInfo(pop.weather.weather_code).text
                            + (pop.weather.apparent_temperature !== undefined ? " · feels " + Math.round(pop.weather.apparent_temperature) + "°" : "")
                        font.pixelSize: Config.text(12)
                    }
                    Label {
                        visible: pop.weather !== null && pop.forecast !== null
                        width: parent.width
                        text: pop.forecast ? "High " + Math.round(pop.forecast.temperature_2m_max[0]) + "° · Low " + Math.round(pop.forecast.temperature_2m_min[0]) + "°" : ""
                        color: pop.dim; font.pixelSize: Config.text(12)
                    }
                }
                // Now: the weather's icon over the temperature, in the corner
                Column {
                    visible: pop.weather !== null
                    anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
                    spacing: 2
                    Icon {
                        anchors.right: parent.right
                        code: pop.weather ? pop.weatherInfo(pop.weather.weather_code).icon : 0
                        font.pixelSize: 26
                    }
                    Label {
                        anchors.right: parent.right
                        text: pop.weather ? Math.round(pop.weather.temperature_2m) + "°" + (Config.fahrenheit ? "F" : "C") : ""
                        font.pixelSize: Config.text(14)
                    }
                }
                // Next few days
                Row {
                    visible: clockCard.days
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                    spacing: 6
                    Repeater {
                        model: pop.forecast ? Math.min(4, pop.forecast.time.length - 1) : 0
                        delegate: ForecastDay {
                            required property int index
                            day: index + 1
                            width: (parent.width - 18) / 4; height: 76
                            // A faint wash over the card: white on dark; on light, where white
                            // vanished, a shade darker
                            color: Config.s.lightMode ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                            gap: 4; iconSize: 18; tempSize: 11
                        }
                    }
                }
            }

            Rectangle {
                visible: controlView.player !== null
                width: parent.width; height: 104; radius: Config.corner(12)
                color: pop.card
                Item {
                    visible: controlView.player !== null
                    anchors { fill: parent; margins: 12 }
                    RoundImage {
                        id: art
                        width: 80; height: 80; radius: Config.corner(10)
                        anchors.verticalCenter: parent.verticalCenter
                        source: controlView.player ? controlView.player.trackArtUrl : ""
                        visible: controlView.player && controlView.player.trackArtUrl !== ""
                    }
                    Column {
                        anchors { left: art.visible ? art.right : parent.left; leftMargin: art.visible ? 12 : 0; right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Label { width: parent.width; text: controlView.player ? (controlView.player.trackTitle || controlView.player.identity) : "" }
                        Label { width: parent.width; text: controlView.player ? (controlView.player.trackArtist || "") : ""; color: pop.dim; font.pixelSize: Config.text(12) }
                        Row {
                            spacing: 4
                            topPadding: 6
                            Repeater {
                                model: [
                                    { code: 0xF693, act: "prev" },
                                    { code: controlView.player && controlView.player.isPlaying ? 0xF690 : 0xF691, act: "play" },
                                    { code: 0xF694, act: "next" }
                                ]
                                delegate: RowButton {
                                    required property var modelData
                                    width: 32; height: 30
                                    onClicked: {
                                        const p = controlView.player; if (!p) return;
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
        }

        // Quick toggles: eight, two to a row, all the same size. Which ones, and in what
        // order, is yours to choose (Settings → Control Centre: Config.controlSwitches;
        // Config.controlSwitchRects lays them out, for Settings' picture of this too)
        Item {
            id: ccTiles
            x: ccBody.leftW + 12
            width: ccBody.rightW; height: parent.height
            visible: ccBody.count > 0
            // Every toggle there is, each lit while it's on (the same ids as Config.controlSwitchList)
            readonly property var every: ({
                wifi: { label: Networking.wifiEnabled ? "Wi-Fi" : "Wi-Fi off", on: Networking.wifiEnabled, code: Networking.wifiEnabled ? 0xEB52 : 0xECFA },
                bt: { label: "Bluetooth", on: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false, code: 0xEA37 },
                caffeine: { label: "Caffeine", on: Config.caffeine, code: 0xEF0E },
                night: { label: "Night Light", on: pop.nightLight, code: 0xEAF8 },
                dnd: { label: "Do Not Disturb", on: pop.notifs ? pop.notifs.quiet : false, code: 0xECE9 },
                perf: { label: "Performance", on: PowerProfiles.profile === PowerProfile.Performance, code: 0xEC45 },
                airplane: { label: "Airplane Mode", on: Config.s.airplaneMode, code: 0xEB6F },
                gamemode: { label: "Game Mode", on: Config.s.gameMode, code: 0xF1D2 },
                light: { label: "Light Mode", on: Config.s.lightMode, code: 0xEB30 },
                mute: { label: "Mute", on: !!ccSink && !!ccSink.audio && ccSink.audio.muted, code: 0xF1C3 },
                micmute: { label: "Mute Mic", on: !!ccSource && !!ccSource.audio && ccSource.audio.muted, code: 0xED16 },
                saver: { label: "Power Saver", on: PowerProfiles.profile === PowerProfile.PowerSaver, code: 0xED4F },
                glass: { label: "Glass", on: Config.s.glass, code: 0xEF8C },
                chargelimit: { label: "Charging Limit", on: Config.chargeLimitOn, code: 0xEF3C },
                dockhide: { label: "Hide Dock", on: Config.s.dockAutoHide, code: 0xEAD3 },
                barhide: { label: "Hide Menu Bar", on: Config.s.barAutoHide, code: 0xEAD7 },
                floating: { label: "Floating", on: Config.focusedMode === "floating", code: 0xEE17 },
                clipboard: { label: "Clipboard", on: Config.s.clipboardHistory, code: 0xEA6F },
                private: { label: "Private Mode", on: Config.s.privateMode, code: 0xF227 }
            })
            // (the speakers and microphone in use, watched so their mutes can be read and set)
            readonly property var ccSink: Pipewire.defaultAudioSink
            readonly property var ccSource: Pipewire.defaultAudioSource
            PwObjectTracker { objects: [ccTiles.ccSink, ccTiles.ccSource].filter(o => !!o) }
            readonly property var toggles: Config.controlSwitches.filter(id => every[id] !== undefined)
                .map(id => Object.assign({ id: id }, every[id]))
            readonly property var rects: Config.controlSwitchRects(toggles.length, width, height)
            Connections {
                target: pop
                function onPressSwitchAsked(id) {
                    for (let i = 0; i < ccTileRep.count; i++) {
                        const t = ccTileRep.itemAt(i);
                        if (t && t.modelData === id) { t.clicked(); return; }
                    }
                }
            }
            Repeater {
                id: ccTileRep
                // A tile for each switch you chose, by its id, which only changes when
                // the choice does; what it shows is looked up as it changes (tile). Handed
                // the switches as they stand, every tile was made again when any one of
                // them was switched, so none ever faded from one colour to the other
                model: ScriptModel { values: ccTiles.toggles.map(t => t.id) }
                delegate: RowButton {
                    id: controlTile
                    required property var modelData      // its switch's id
                    readonly property var tile: ccTiles.every[modelData]
                    Component.onCompleted: pop.rowMade("tiles")
                    required property int index
                    readonly property rect at: ccTiles.rects[index] ?? Qt.rect(0, 0, 0, 0)
                    readonly property color fg: selected ? pop.accentText : pop.text
                    x: at.x; y: at.y; width: at.width; height: at.height
                    radius: Config.corner(12)
                    selected: tile.on
                    // On ones light up too when pointed at (a lighter accent), as they can be turned off
                    color: selected ? (tileHover.hovered ? Config.accentLit : pop.accent) : "transparent"
                    HoverFill { base: pop.card; hovered: tileHover.hovered; gone: controlTile.selected; radius: controlTile.radius }
                    HoverHandler { id: tileHover }
                    onClicked: {
                        switch (modelData) {
                        case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break;
                        case "bt": if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; break;
                        case "caffeine": Config.caffeine = !Config.caffeine; break;
                        case "night": Config.s.nightLight = !Config.s.nightLight; break;
                        case "dnd": if (pop.notifs) pop.notifs.setQuiet(!pop.notifs.quiet); break;
                        case "perf": PowerProfiles.profile = tile.on ? PowerProfile.Balanced : PowerProfile.Performance; break;
                        case "airplane": Config.s.airplaneMode = !Config.s.airplaneMode; break;
                        case "gamemode": Config.setGameMode(!Config.s.gameMode); break;
                        case "light": Config.setThemeMode(tile.on ? "dark" : "light"); break;
                        case "mute": if (ccTiles.ccSink && ccTiles.ccSink.audio) ccTiles.ccSink.audio.muted = !tile.on; break;
                        case "micmute": if (ccTiles.ccSource && ccTiles.ccSource.audio) ccTiles.ccSource.audio.muted = !tile.on; break;
                        case "saver": PowerProfiles.profile = tile.on ? PowerProfile.Balanced : PowerProfile.PowerSaver; break;
                        case "glass": Config.s.glass = !Config.s.glass; break;
                        case "chargelimit":
                            // (charging to full is asked about first, in the usual window: the panel makes way for it)
                            if (tile.on) pop.close();
                            Config.askChargeLimit(!tile.on, pop.powerConfirm);
                            break;
                        case "dockhide": Config.s.dockAutoHide = !Config.s.dockAutoHide; break;
                        case "barhide": Config.s.barAutoHide = !Config.s.barAutoHide; break;
                        // (this workspace: floating, or back to how it was. Where floating's the
                        // default, off means tiled)
                        case "floating":
                            Config.setWorkspaceMode(Config.focusedWorkspaceId, tile.on ? (Config.windowMode === "floating" ? "tiling" : "") : "floating");
                            break;
                        case "clipboard": Config.s.clipboardHistory = !Config.s.clipboardHistory; break;
                        // (the first time, Slate asks before turning it on: the panel makes way)
                        case "private":
                            if (!tile.on) pop.close();
                            Config.setPrivateMode(!tile.on);
                            break;
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        spacing: 3
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            code: controlTile.tile.code
                            color: controlTile.fg
                            Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        }
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: controlTile.tile.label
                            font.pixelSize: Config.text(11)
                            color: controlTile.fg
                            Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        }
                    }
                }
            }
        }
    }
}
