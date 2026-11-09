// The welcome: shown the first time Slate starts (and from Settings → About), it introduces
// Slate and walks through a few big choices, each with a recommendation: tiling or floating
// windows, colours (from the wallpaper), where the bar and dock go, and the shortcuts.
// Everything it sets is in Settings too. Skip (or Escape) at any point.
//
//   slate ipc call welcome open

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: w
    required property var bar

    // ---- Showing ---------------------------------------------------------------
    property bool shown: false
    property int page: 0
    readonly property int pages: 6
    function open() {
        screen = Config.focusedScreen;
        page = 0;
        shown = true;
    }
    // Done or skipped: it won't show by itself again
    function finish() {
        Config.s.welcomeShown = true;
        shown = false;
    }
    // The first time Slate starts (a moment after, once the desktop is up)
    Timer {
        interval: 2500
        running: true
        onTriggered: if (!Config.s.welcomeShown) w.open()
    }
    IpcHandler {
        target: "welcome"
        function open(): void { w.open(); }
    }

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(260); easing.type: Easing.OutCubic } }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: Qt.rgba(0.02, 0.03, 0.04, 0.82 * fade)        // the desktop well dimmed behind it
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-welcome"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---- Look ------------------------------------------------------------------
    readonly property color bg: Config.surface(Config.tint("#0f1216"))
    readonly property color card: Config.raised(Config.tint("#1d222a"))
    readonly property color line: Config.tint("#2a313c")
    readonly property color text: Config.tint("#eef1f5")
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property string font: bar.fontFamily
    readonly property string iconFont: bar.iconFont
    function glyph(c) { return String.fromCodePoint(c); }

    // ---- Asking before light mode (still being polished), as Settings does -----
    property string askMode: ""                 // the mode waiting for an answer
    property var askText: ({ title: "", body: "", button: "" })
    function pickThemeMode(m) {
        if (m === Config.themeMode) return;
        if (m === "dark" || Config.themeMode !== "dark" || !Config.lightModeAsks) { Config.setThemeMode(m); return; }
        askText = Config.lightModeQuestion(m);
        askMode = m;
        Config.attention();
    }
    function answer(yes) {
        if (yes && askMode !== "") Config.setThemeMode(askMode);
        askMode = "";
        panel.forceActiveFocus();
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(780, w.width - 48)
        height: Math.min(600, w.height - 48)
        radius: 18
        color: w.bg
        border.width: 1; border.color: w.line
        opacity: w.fade
        scale: 0.96 + 0.04 * w.fade
        layer.enabled: !Config.glass     // only for the shadow, which glass goes without
        layer.effect: MultiEffect { shadowEnabled: !Config.glass; shadowColor: "black"; shadowOpacity: 0.5; shadowBlur: 1; shadowVerticalOffset: 10; blurMax: 48 }

        focus: w.shown
        Keys.onEscapePressed: w.finish()
        Keys.onLeftPressed: if (w.page > 0) w.page--
        Keys.onRightPressed: if (w.page < w.pages - 1) w.page++
        Keys.onReturnPressed: { if (w.page < w.pages - 1) w.page++; else w.finish(); }

        // Skip, top right (not on the last page, which has its own buttons)
        Text {
            visible: w.page < w.pages - 1
            anchors { top: parent.top; right: parent.right; topMargin: 18; rightMargin: 22 }
            text: "Skip"
            color: skipHover.hovered ? w.text : w.dim
            font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium
            HoverHandler { id: skipHover }
            ClickTap { onTapped: w.finish() }
        }

        // The pages: one shows at a time, sliding a little as it fades in
        Item {
            id: pagesBox
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; margins: 40; topMargin: 48; bottomMargin: 8 }

            // ---- 0. Welcome ------------------------------------------------
            Item {
                anchors.fill: parent
                opacity: w.page === 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 18
                    SlateLogo { size: 96; showText: false; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Welcome to Slate"
                        color: w.text; font.family: w.font; font.pixelSize: 30; font.weight: Font.DemiBold
                    }
                    Text {
                        width: Math.min(parent.width, 520)
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        lineHeight: 1.25
                        text: "A calm, aesthetically pleasing desktop for Linux: a bar, a dock, a launcher, switchers, panels and notifications that all fit together.\n\nLet's make a few choices to get you started. Each has a recommendation, and you can change any of them later in Settings (Super+Z)."
                        color: w.dim; font.family: w.font; font.pixelSize: 14
                    }
                }
            }

            // ---- 1. Windows ------------------------------------------------
            Item {
                anchors.fill: parent
                opacity: w.page === 1 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "How should windows behave?"; color: w.text; font.family: w.font; font.pixelSize: 22; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 14
                        text: "Slate can arrange your windows for you, or leave them where you put them."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                    Row {
                        width: parent.width
                        spacing: 16
                        Repeater {
                            model: [
                                { key: "tiling", title: "Tiling", rec: true, detail: "Windows sit side by side and share the screen, never overlapping. Quick to use from the keyboard." },
                                { key: "floating", title: "Floating", rec: false, detail: "Windows open where you put them and can overlap, with title bars, like a traditional desktop." }
                            ]
                            delegate: Rectangle {
                                id: modeCard
                                required property var modelData
                                readonly property bool usable: modelData.key === "tiling" || Config.titleBarsAvailable
                                readonly property bool on: Config.s.windowMode === modelData.key
                                width: (parent.width - 16) / 2; height: 290
                                radius: 14
                                color: modeHover.hovered && usable ? Config.hoverOn(w.card) : w.card
                                Gloss { radius: parent.radius; opacity: (modeHover.hovered && usable) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                border.width: on ? 2 : 1
                                border.color: on ? w.accent : w.line
                                opacity: usable ? 1 : 0.5
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                // A small screen showing the idea
                                Rectangle {
                                    id: modeArt
                                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                                    height: 130; radius: 9
                                    color: Config.tint("#151920")
                                    Item {
                                        anchors { fill: parent; margins: 10 }
                                        visible: modeCard.modelData.key === "tiling"
                                        Rectangle { x: 0; y: 0; width: parent.width * 0.55 - 4; height: parent.height; radius: 6; color: modeCard.on ? w.accent : w.line; opacity: 0.9 }
                                        Rectangle { x: parent.width * 0.55 + 4; y: 0; width: parent.width * 0.45 - 4; height: parent.height / 2 - 4; radius: 6; color: w.line }
                                        Rectangle { x: parent.width * 0.55 + 4; y: parent.height / 2 + 4; width: parent.width * 0.45 - 4; height: parent.height / 2 - 4; radius: 6; color: w.line }
                                    }
                                    Item {
                                        anchors { fill: parent; margins: 10 }
                                        visible: modeCard.modelData.key === "floating"
                                        Rectangle { x: 6; y: 8; width: parent.width * 0.55; height: parent.height * 0.62; radius: 6; color: w.line
                                            Rectangle { width: parent.width; height: 9; radius: 6; color: Qt.lighter(w.line, 1.3) } }
                                        Rectangle { x: parent.width * 0.38; y: parent.height * 0.3; width: parent.width * 0.58; height: parent.height * 0.66; radius: 6; color: modeCard.on ? w.accent : Qt.lighter(w.line, 1.15)
                                            Rectangle { width: parent.width; height: 9; radius: 6; color: Qt.lighter(parent.color, 1.15) } }
                                    }
                                }
                                Column {
                                    anchors { top: modeArt.bottom; left: parent.left; right: parent.right; margins: 16; topMargin: 14 }
                                    spacing: 6
                                    Row {
                                        spacing: 8
                                        Text { text: modeCard.modelData.title; color: w.text; font.family: w.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Rectangle {
                                            visible: modeCard.modelData.rec
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: recText.implicitWidth + 14; height: 20; radius: 10
                                            color: Qt.rgba(w.accent.r, w.accent.g, w.accent.b, 0.18)
                                            Text { id: recText; anchors.centerIn: parent; text: "Recommended"; color: w.accent; font.family: w.font; font.pixelSize: 11; font.weight: Font.Medium }
                                        }
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.Wrap
                                        text: modeCard.usable ? modeCard.modelData.detail
                                            : "Needs the title bar plugin (hyprbars), which isn't built yet: run slate build-hyprbars, then come back"
                                        color: w.dim; font.family: w.font; font.pixelSize: 12; lineHeight: 1.2
                                    }
                                }
                                HoverHandler { id: modeHover }
                                ClickTap { onTapped: if (modeCard.usable) Config.s.windowMode = modeCard.modelData.key }
                            }
                        }
                    }
                }
            }

            // ---- 2. Colours ------------------------------------------------
            Item {
                anchors.fill: parent
                opacity: w.page === 2 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Colours"; color: w.text; font.family: w.font; font.pixelSize: 22; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 12
                        text: "Slate can take its colours from your wallpaper, so everything matches it, and change with it."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                    // Theme
                    Text { text: "Theme"; color: w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium; bottomPadding: 4 }
                    Row {
                        spacing: 10
                        Repeater {
                            model: [{ mode: "dark", label: "Dark", icon: 0xEAF8 }, { mode: "light", label: "Light", icon: 0xEB30 },
                                    { mode: "auto", label: "Auto (light by day)", icon: 0xEA70 }]
                            delegate: Rectangle {
                                id: themeOpt
                                required property var modelData
                                readonly property bool on: (Config.s.themeMode || (Config.s.lightMode ? "light" : "dark")) === modelData.mode
                                width: themeRow.implicitWidth + 28; height: 38; radius: 10
                                color: on ? w.accent : themeHover.hovered ? Config.hoverOn(w.card) : w.card
                                Gloss { radius: parent.radius; opacity: (on || themeHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                Row {
                                    id: themeRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: w.glyph(themeOpt.modelData.icon); color: themeOpt.on ? w.accentText : w.dim; font.family: w.iconFont; font.pixelSize: 16 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: themeOpt.modelData.label; color: themeOpt.on ? w.accentText : w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium }
                                }
                                HoverHandler { id: themeHover }
                                ClickTap { onTapped: w.pickThemeMode(themeOpt.modelData.mode) }
                            }
                        }
                    }
                    Item { width: 1; height: 14 }
                    // Accent
                    Text { text: "Accent colour"; color: w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium; bottomPadding: 4 }
                    Row {
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: [{ wall: true, title: "From your wallpaper", rec: true, detail: "A bright colour picked from the wallpaper, changing with it" },
                                    { wall: false, title: "Choose one", rec: false, detail: "Pick a colour that stays the same" }]
                            delegate: Rectangle {
                                id: accOpt
                                required property var modelData
                                readonly property bool on: Config.s.accentFromWallpaper === modelData.wall
                                width: (parent.width - 12) / 2; height: 112; radius: 12
                                color: accHover.hovered ? Config.hoverOn(w.card) : w.card
                                Gloss { radius: parent.radius; opacity: (accHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                border.width: on ? 2 : 1; border.color: on ? w.accent : w.line
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                Column {
                                    anchors { fill: parent; margins: 14 }
                                    spacing: 6
                                    Row {
                                        spacing: 8
                                        Text { text: accOpt.modelData.title; color: w.text; font.family: w.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Rectangle {
                                            visible: accOpt.modelData.rec
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: accRec.implicitWidth + 14; height: 20; radius: 10
                                            color: Qt.rgba(w.accent.r, w.accent.g, w.accent.b, 0.18)
                                            Text { id: accRec; anchors.centerIn: parent; text: "Recommended"; color: w.accent; font.family: w.font; font.pixelSize: 11; font.weight: Font.Medium }
                                        }
                                    }
                                    Text { width: parent.width; wrapMode: Text.Wrap; text: accOpt.modelData.detail; color: w.dim; font.family: w.font; font.pixelSize: 12 }
                                    Row {
                                        spacing: 7
                                        topPadding: 4
                                        // The wallpaper's colour, or the colours to choose from
                                        Repeater {
                                            model: accOpt.modelData.wall ? [Config.wallpaperAccent || Config.accent]
                                                : ["#8fb3e8", "#7fc4c0", "#9ad3a6", "#e8c48f", "#e8a6b5", "#b9a6e8", "#eef1f5"]
                                            delegate: Rectangle {
                                                id: sw
                                                required property string modelData
                                                width: 22; height: 22; radius: 11
                                                // As it'll look: deeper in light mode, and the wallpaper's as bold as set
                                                color: accOpt.modelData.wall && Config.wallpaperAccent ? Config.fromWallpaper(modelData) : Config.accentShade(modelData)
                                                border.width: !accOpt.modelData.wall && !Config.s.accentFromWallpaper && Config.s.accent.toLowerCase() === modelData ? 2 : 0
                                                border.color: w.text
                                                ClickTap {
                                                    enabled: !accOpt.modelData.wall
                                                    onTapped: { Config.s.accentFromWallpaper = false; Config.s.accent = sw.modelData; }
                                                }
                                            }
                                        }
                                    }
                                }
                                HoverHandler { id: accHover }
                                ClickTap { onTapped: Config.s.accentFromWallpaper = accOpt.modelData.wall }
                            }
                        }
                    }
                    Item { width: 1; height: 14 }
                    // Other apps: every supported one that's installed, in one go
                    Rectangle {
                        id: appsRow
                        width: parent.width; height: appsText.implicitHeight + 28; radius: 12
                        color: w.card
                        Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                        // Installed apps Slate can theme: the list Settings' search already reads at
                        // start (SettingsIndex.themeApps, from scripts/apply-theme.py --apps), rather
                        // than running the script again for a page that's seldom seen
                        readonly property var installed: SettingsIndex.themeApps.filter(a => a.installed).map(a => a.id)
                        readonly property var themed: Config.s.themedApps || []
                        readonly property bool on: installed.length > 0 && installed.every(a => themed.includes(a))
                        Column {
                            id: appsText
                            anchors { left: parent.left; right: appsSwitch.left; leftMargin: 14; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 4
                            Text {
                                text: "Theme your other apps too" + (appsRow.installed.length ? " (" + appsRow.installed.length + " found)" : "")
                                color: w.text; font.family: w.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: "Every app Slate can theme that you have installed (GTK and Qt apps, terminals, editors and more) follows these colours."
                                color: w.dim; font.family: w.font; font.pixelSize: 12
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: "\u26A0 This changes those apps' own settings (their colour or theme files). Each one is backed up first, and switching an app off in Settings \u2192 App theming puts its original back."
                                color: Config.tint("#e8c48f"); font.family: w.font; font.pixelSize: 12
                            }
                        }
                        Rectangle {
                            id: appsSwitch
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 42; height: 24; radius: 12
                            color: appsRow.on ? w.accent : w.line
                            Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: appsRow.on ? parent.width - width - 3 : 3
                                color: appsRow.on ? w.accentText : w.text
                                Behavior on x { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
                            }
                        }
                        // On: all installed ones; off: none of them (their configs are put back)
                        ClickTap {
                            onTapped: {
                                const others = appsRow.themed.filter(x => !appsRow.installed.includes(x));
                                Config.s.themedApps = appsRow.on ? others : others.concat(appsRow.installed);
                            }
                        }
                    }
                }
            }

            // ---- 3. Bar and dock ------------------------------------------
            Item {
                anchors.fill: parent
                opacity: w.page === 3 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "The menu bar and dock"; color: w.text; font.family: w.font; font.pixelSize: 22; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 18
                        text: "Put them on any edge of the screen. Most people like the bar along the top and the dock at the bottom."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                    Row {
                        width: parent.width
                        spacing: 16
                        Repeater {
                            model: [{ bar: true, title: "Menu Bar", detail: "Apps, workspaces, the window title, status icons and the clock" },
                                    { bar: false, title: "Dock", detail: "Your favourite and open apps" }]
                            delegate: Rectangle {
                                id: edgeCard
                                required property var modelData
                                width: (parent.width - 16) / 2; height: 250; radius: 14
                                color: w.card
                                Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                                Column {
                                    anchors { fill: parent; margins: 16 }
                                    spacing: 6
                                    Text { text: edgeCard.modelData.title; color: w.text; font.family: w.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Text { width: parent.width; wrapMode: Text.Wrap; text: edgeCard.modelData.detail; color: w.dim; font.family: w.font; font.pixelSize: 12; bottomPadding: 8 }
                                    EdgePicker {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        accent: w.accent
                                        bar: edgeCard.modelData.bar
                                        edge: edgeCard.modelData.bar ? Config.s.barPosition : Config.s.dockPosition
                                        onPicked: e => edgeCard.modelData.bar ? Config.moveBar(e) : Config.moveDock(e)
                                    }
                                    Text {
                                        width: parent.width; horizontalAlignment: Text.AlignHCenter; topPadding: 6
                                        text: "Click an edge"
                                        color: w.dim; font.family: w.font; font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 8 }
                    Rectangle {
                        id: hideRow
                        width: parent.width; height: 56; radius: 12
                        color: w.card
                        Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                        readonly property bool on: Config.s.dockAutoHide
                        Column {
                            anchors { left: parent.left; right: hideSwitch.left; leftMargin: 14; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 3
                            Text { text: "Hide the dock when windows are open"; color: w.text; font.family: w.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: "Push the pointer to its edge to bring it back. Gives your windows more room"; color: w.dim; font.family: w.font; font.pixelSize: 12 }
                        }
                        Rectangle {
                            id: hideSwitch
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 42; height: 24; radius: 12
                            color: hideRow.on ? w.accent : w.line
                            Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: hideRow.on ? parent.width - width - 3 : 3
                                color: hideRow.on ? w.accentText : w.text
                                Behavior on x { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
                            }
                        }
                        ClickTap { onTapped: Config.s.dockAutoHide = !Config.s.dockAutoHide }
                    }
                }
            }

            // ---- 4. Shortcuts ---------------------------------------------
            Item {
                anchors.fill: parent
                opacity: w.page === 4 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Keyboard shortcuts"; color: w.text; font.family: w.font; font.pixelSize: 22; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; bottomPadding: 14
                        text: "Coming from Hyprland? You can keep the keys you know."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                    Repeater {
                        model: [
                            { key: "slate", title: "Slate's", rec: true, detail: "Built around the Super key: tap it for apps, Super+Tab to switch windows, Super+Arrows for workspaces" },
                            { key: "hyprland", title: "Hyprland's defaults", rec: false, detail: "Hyprland's own: Super+Q terminal, Super+C close, Super+R launcher, Super+1–0 workspaces" },
                            { key: "hyprland-extras", title: "Hyprland's, plus Slate's extras", rec: false, detail: "Hyprland's defaults, with Slate's shortcuts added where the keys are free" }
                        ]
                        delegate: Rectangle {
                            id: keyOpt
                            required property var modelData
                            readonly property bool on: Config.s.keyset === modelData.key
                            width: parent.width; height: 70; radius: 12
                            color: keyHover.hovered ? Config.hoverOn(w.card) : w.card
                            Gloss { radius: parent.radius; opacity: (keyHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                            border.width: on ? 2 : 1; border.color: on ? w.accent : w.line
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            Column {
                                anchors { left: parent.left; right: keyTick.left; leftMargin: 16; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 4
                                Row {
                                    spacing: 8
                                    Text { text: keyOpt.modelData.title; color: w.text; font.family: w.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                    Rectangle {
                                        visible: keyOpt.modelData.rec
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: keyRec.implicitWidth + 14; height: 20; radius: 10
                                        color: Qt.rgba(w.accent.r, w.accent.g, w.accent.b, 0.18)
                                        Text { id: keyRec; anchors.centerIn: parent; text: "Recommended"; color: w.accent; font.family: w.font; font.pixelSize: 11; font.weight: Font.Medium }
                                    }
                                }
                                Text { width: parent.width; elide: Text.ElideRight; text: keyOpt.modelData.detail; color: w.dim; font.family: w.font; font.pixelSize: 12 }
                            }
                            Text {
                                id: keyTick
                                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                visible: keyOpt.on
                                text: w.glyph(0xEA5E)
                                color: w.accent; font.family: w.iconFont; font.pixelSize: 20
                            }
                            HoverHandler { id: keyHover }
                            ClickTap { onTapped: Config.setKeyset(keyOpt.modelData.key) }
                        }
                    }
                }
            }

            // ---- 5. All set ------------------------------------------------
            // The logo and a line on top, the keys worth knowing as cards (icon, what it
            // does, the keys as keycaps), and a thank-you to close
            Item {
                id: donePage
                anchors.fill: parent
                opacity: w.page === 5 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
                readonly property var tips: Config.s.keyset === "slate" ? [
                        { keys: "Super", what: "Open apps", icon: 0xEB1C },
                        { keys: "Super+Tab", what: "Switch windows", icon: 0xEFE6 },
                        { keys: "Super+Right", what: "Next workspace", icon: 0xEA1F },
                        { keys: "Super+Down", what: "All your workspaces", icon: 0xEDBA },
                        { keys: "Super+V", what: "Clipboard history", icon: 0xEA6F },
                        { keys: "Super+Z", what: "Settings", icon: 0xEB20 }
                    ] : Config.s.keyset === "hyprland" ? [
                        { keys: "Super+R", what: "Open apps", icon: 0xEB1C },
                        { keys: "Super+Q", what: "Terminal", icon: 0xEBEF },
                        { keys: "Super+C", what: "Close a window", icon: 0xEB55 },
                        { keys: "Super+1", what: "Go to a workspace", icon: 0xEA1F },
                        { keys: "Super+Tab", what: "Switch windows", icon: 0xEFE6 },
                        { keys: "Super+Z", what: "Settings", icon: 0xEB20 }
                    ] : [
                        { keys: "Super+R", what: "Open apps", icon: 0xEB1C },
                        { keys: "Super+Q", what: "Terminal", icon: 0xEBEF },
                        { keys: "Super+Tab", what: "Switch windows", icon: 0xEFE6 },
                        { keys: "Super+Ctrl+Down", what: "All your workspaces", icon: 0xEDBA },
                        { keys: "Super+Shift+V", what: "Clipboard history", icon: 0xEA6F },
                        { keys: "Super+Z", what: "Settings", icon: 0xEB20 }
                    ]
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 0
                    SlateLogo { size: 56; showText: false; anchors.horizontalCenter: parent.horizontalCenter }
                    Item { width: 1; height: 14 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "You're all set"
                        color: w.text; font.family: w.font; font.pixelSize: 26; font.weight: Font.DemiBold
                    }
                    Item { width: 1; height: 6 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "A few keys to get around. Settings has the full list (Super+Z → Shortcuts)."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                    Item { width: 1; height: 22 }
                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 3
                        columnSpacing: 12; rowSpacing: 12
                        readonly property real cardW: Math.floor((donePage.width - 2 * columnSpacing) / 3)
                        Repeater {
                            model: donePage.tips
                            delegate: Rectangle {
                                id: tip
                                required property var modelData
                                width: parent.cardW; height: 84; radius: 12
                                color: w.card
                                Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                                border.width: 1; border.color: w.line
                                // Icon, in an accent-tinted square
                                Rectangle {
                                    id: tipIcon
                                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                    width: 38; height: 38; radius: 10
                                    color: Qt.rgba(w.accent.r, w.accent.g, w.accent.b, 0.16)
                                    Text { anchors.centerIn: parent; text: w.glyph(tip.modelData.icon); color: w.accent; font.family: w.iconFont; font.pixelSize: 19 }
                                }
                                Column {
                                    anchors { left: tipIcon.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Text { width: parent.width; text: tip.modelData.what; color: w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                                    // The keys, each as a keycap
                                    Row {
                                        spacing: 4
                                        Repeater {
                                            model: tip.modelData.keys.split("+")
                                            delegate: Row {
                                                required property string modelData
                                                required property int index
                                                spacing: 4
                                                Text {
                                                    visible: index > 0
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "+"; color: w.dim; font.family: w.font; font.pixelSize: 11
                                                }
                                                Rectangle {
                                                    width: Math.max(22, capText.implicitWidth + 14); height: 22; radius: 6
                                                    color: w.line
                                                    // A slightly darker lower edge, like a key
                                                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; radius: 6; color: Qt.darker(w.line, 1.35) }
                                                    Text { id: capText; anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: parent.parent.modelData; color: w.text; font.family: w.font; font.pixelSize: 11; font.weight: Font.Medium }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 28 }
                    // The thank-you, between two short lines
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 40; height: 1; color: w.line }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Thank you for using Slate"
                            color: w.text; font.family: w.font; font.pixelSize: 15; font.weight: Font.Medium
                        }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 40; height: 1; color: w.line }
                    }
                    Item { width: 1; height: 6 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "We hope you enjoy it."
                        color: w.dim; font.family: w.font; font.pixelSize: 13
                    }
                }
            }
        }

        // ---- Footer: page dots, Back and Next ----------------------------------
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
            height: 40
            Row {
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: w.pages
                    delegate: Rectangle {
                        required property int index
                        width: index === w.page ? 22 : 8; height: 8; radius: 4
                        color: index === w.page ? w.accent : w.line
                        Behavior on width { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: Config.ms(180) } }
                        ClickTap { onTapped: w.page = parent.index }
                    }
                }
            }
            // Back
            Rectangle {
                visible: w.page > 0
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: backText.implicitWidth + 32; height: 38; radius: 10
                color: backHover.hovered ? Config.hoverOn(w.card) : w.card
                Gloss { radius: parent.radius; opacity: (backHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                Text { id: backText; anchors.centerIn: parent; text: "Back"; color: w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium }
                HoverHandler { id: backHover }
                ClickTap { onTapped: w.page-- }
            }
            // Next / Get started / Open Settings + Start using Slate
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                Rectangle {
                    visible: w.page === w.pages - 1
                    width: setText.implicitWidth + 32; height: 38; radius: 10
                    color: setHover.hovered ? Config.hoverOn(w.card) : w.card
                    Gloss { radius: parent.radius; opacity: (setHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                    Text { id: setText; anchors.centerIn: parent; text: "Open Settings"; color: w.text; font.family: w.font; font.pixelSize: 13; font.weight: Font.Medium }
                    HoverHandler { id: setHover }
                    ClickTap {
                        onTapped: {
                            w.finish();
                            Config.slateCall("settings", "open");
                        }
                    }
                }
                Rectangle {
                    width: nextText.implicitWidth + 36; height: 38; radius: 10
                    color: nextHover.hovered ? Qt.lighter(w.accent, 1.08) : w.accent
                    Text {
                        id: nextText
                        anchors.centerIn: parent
                        text: w.page === 0 ? "Get started" : w.page === w.pages - 1 ? "Start using Slate" : "Next"
                        color: w.accentText; font.family: w.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    HoverHandler { id: nextHover }
                    ClickTap { onTapped: { if (w.page < w.pages - 1) w.page++; else w.finish(); } }
                }
            }
        }
    }

    // The question: the welcome dimmed behind a card, like Settings' confirmations
    Rectangle {
        anchors.fill: parent
        z: 10
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: opacity > 0
        opacity: w.askMode !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(140) } }
        onVisibleChanged: if (visible) askCard.forceActiveFocus()
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: w.answer(false) }
        Rectangle {
            id: askCard
            anchors.centerIn: parent
            width: 380; height: askCol.implicitHeight + 40
            radius: 16
            color: Config.tint("#0f1216")
            border.width: 1; border.color: w.line
            scale: w.askMode !== "" ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }    // clicks on the card don't close it
            Keys.onEscapePressed: w.answer(false)
            Keys.onReturnPressed: w.answer(true)
            Keys.onEnterPressed: w.answer(true)
            Column {
                id: askCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 8
                Text {
                    width: parent.width
                    text: w.askText.title
                    color: w.text; font.family: w.font; font.pixelSize: 16; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: w.askText.body
                    color: w.dim; font.family: w.font; font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
                Item { width: 1; height: 8 }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Rectangle {
                        width: askNo.implicitWidth + 28; height: 32; radius: 8
                        color: askNoHover.hovered ? Config.hoverOn(w.card) : w.card
                        Gloss { radius: parent.radius; opacity: askNoHover.hovered ? 1 : 0 }
                        Text { id: askNo; anchors.centerIn: parent; text: "Cancel"; color: w.text; font.family: w.font; font.pixelSize: 12; font.weight: Font.Medium }
                        HoverHandler { id: askNoHover }
                        ClickTap { onTapped: w.answer(false) }
                    }
                    Rectangle {
                        width: askYes.implicitWidth + 28; height: 32; radius: 8
                        color: askYesHover.hovered ? Qt.lighter(w.accent, 1.08) : w.accent
                        Gloss { radius: parent.radius }
                        Text { id: askYes; anchors.centerIn: parent; text: w.askText.button; color: w.accentText; font.family: w.font; font.pixelSize: 12; font.weight: Font.Medium }
                        HoverHandler { id: askYesHover }
                        ClickTap { onTapped: w.answer(true) }
                    }
                }
            }
        }
    }
}
