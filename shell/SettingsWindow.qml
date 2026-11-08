// Slate settings window for the bar, dock, launcher, switchers, notifications and
// Bluetooth, styled like the rest of the shell. Values live in Config (settings.json).
// Open with:  slate ipc call settings toggle   (also Super+Z and the control centre gear)

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import QtQuick.Dialogs as Dialogs

FloatingWindow {
    id: win
    required property var bar
    property var notifs: null

    title: "Slate Settings"
    // 880×620, or less on a small screen (Hyprland centres it at the size it asks for)
    readonly property var fitScreen: Config.focusedScreen
    implicitWidth: Math.round(Math.min(880, fitScreen ? fitScreen.width * 0.9 : 880))
    implicitHeight: Math.round(Math.min(620, fitScreen ? (fitScreen.height - 60) * 0.9 : 620))
    minimumSize: Qt.size(Math.min(520, implicitWidth), Math.min(380, implicitHeight))
    // The screen it's on changing size (its scale or resolution changed, or the interface
    // size): fit and centre it again, or it can be left off to one side or past the edge
    readonly property string screenSize: screen ? screen.width + "x" + screen.height : ""
    onScreenSizeChanged: if (visible) recentre.restart()
    Timer {
        id: recentre
        interval: 400        // let Hyprland finish changing the monitor first
        onTriggered: {
            if (!win.visible || !win.screen) return;
            // Hyprland's units: Slate's times the interface size
            const w = Math.round(Math.min(880, win.screen.width * 0.9) * Config.uiScale);
            const h = Math.round(Math.min(620, (win.screen.height - 60) * 0.9) * Config.uiScale);
            const sel = "title:^(Slate Settings)$";
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() hl.dispatch(hl.dsp.window.resize({ x = ${w}, y = ${h}, window = "${sel}" })); hl.dispatch(hl.dsp.window.center({ window = "${sel}" })) end`]);
        }
    }
    // Narrow window (a small screen): the sidebar shows just its icons
    readonly property bool compact: width < 760
    visible: false
    color: bar.barColor
    onVisibleChanged: {
        const a = Bluetooth.defaultAdapter;
        if (!visible && a && a.discovering) a.discovering = false;
        if (visible && !keepSection) section = "overview";
        // Cleared a moment later, not now: showing the window can report "visible" twice,
        // and the second would otherwise send a requested page back to the Overview
        if (visible) keepClear.restart(); else keepSection = false;
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { win.visible = !win.visible; }
        function open(): void { win.visible = true; }
        function close(): void { win.visible = false; }
        // Old page names still work: switchers → windows, wallpaper → appearance (at the wallpapers)
        function page(name: string): void {
            if (name === "wallpaper") win.scrollTo = "wallpaper";
            win.keepSection = !win.visible;
            win.section = ({ switchers: "windows", wallpaper: "appearance" })[name] ?? name;
            win.visible = true;
        }
        // Open a page scrolled to one setting (or heading), lit up for a moment, e.g.
        //   slate ipc call settings find appearance "Interface size"
        function find(page: string, label: string): void { win.goTo(page, label); }
        // Open General with the account picture chooser showing (the control centre's avatar)
        function avatar(): void { win.keepSection = !win.visible; win.section = "general"; win.avatarPicking = true; win.visible = true; }
    }

    // ---- Look --------------------------------------------------------------
    readonly property color card: bar.capsuleColor
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    readonly property string font: bar.fontFamily
    function glyph(code) { return String.fromCodePoint(code); }

    property string section: "overview"
    // Opening Settings starts on the Overview, unless it was asked for a page (keepSection)
    property bool keepSection: false
    Timer { id: keepClear; interval: 600; onTriggered: win.keepSection = false }
    // A setting to scroll to and light up once its page has loaded (goTo)
    property string findLabel: ""
    function goTo(page, label) {
        keepSection = !visible;           // (only matters while opening: see onVisibleChanged)
        findLabel = label || "";
        if (section === page && pageLoader.item) Qt.callLater(showFound);
        section = page;
        visible = true;
    }
    function showFound() {
        const label = findLabel;
        findLabel = "";
        if (!label || !pageLoader.item) return;
        // The setting (anything with that label), or a heading with that text
        const match = it => it.visible && (it.label === label || (it.text === label && it.label === undefined && it.font !== undefined && it.font.pixelSize <= 13));
        const look = it => {
            if (!it) return null;
            if (match(it) && it !== pageLoader.item) return it;
            for (const c of it.children) { const r = look(c); if (r) return r; }
            return null;
        };
        const hit = look(pageLoader.item);
        if (!hit) return;
        const p = hit.mapToItem(pageLoader.item, 0, 0);
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, p.y - 40));
        Qt.callLater(() => {
            const q = hit.mapToItem(contentPane, 0, 0);
            foundFlash.x = q.x - 6; foundFlash.y = q.y - 4;
            foundFlash.width = Math.min(hit.width + 12, contentPane.width - foundFlash.x - 8); foundFlash.height = hit.height + 8;
            foundFade.restart();
        });
    }
    property bool avatarPicking: false     // General: the account picture chooser is open
    property string scrollTo: ""           // a part of the next page to scroll to ("wallpaper")
    // The settings each page can restore to their defaults. Left out on purpose: your
    // location and night light on/off (General), and the chosen wallpaper (Appearance)
    readonly property var pageKeys: ({
        general: ["clipboardHistory", "nightLightTemperature", "nightLightSchedule", "nightLightFrom", "nightLightTo"],
        appearance: ["themeMode", "lightMode", "accentFromWallpaper", "accent", "toneFromWallpaper", "roundedScreenCorners",
            "animations", "glass", "glassOpacity", "glassBlur", "glassShine", "glassGloss", "fastBlur", "blurPasses", "iconShape", "iconFill", "tintIcons", "iconTintStrength", "folderColour", "fontFamily", "codeFontFamily", "uiScale",
            "wallpaperFolder", "wallpaperChange", "wallpaperHideSmall", "wallpaperMinSize"],
        bar: ["barPosition", "barAutoHide", "barHoverDescriptions", "barShowApps", "barShowWorkspaces", "barShowTitle", "barShowTitleIcon",
            "barShowTray", "barShowNotifications", "barShowClipboard", "barShowScreenshot", "barShowWifi", "barShowKeyboard", "barShowBluetooth", "barShowVolume", "barShowBattery", "barValueClipboard", "barValueWifi", "barValueKeyboard", "barValueBluetooth", "barValueVolume", "barValueBattery", "barTrayCollapsed",
            "barShowPower", "barClockFormat", "barClockSeconds", "barClockDate"],
        dock: ["dockPosition", "dockAutoHide", "dockIconSize", "dockMagnification", "dockSpread"],
        launcher: ["launcherLayout", "launcherColumns", "launcherRows", "launcherDescriptions", "launcherSortByUsage"],
        displays: ["mainDisplay"],
        input: ["kbLayouts", "kbVariants", "kbSwitch", "capsLock", "keyRepeatDelay", "keyRepeatRate", "mouseSpeed", "mouseAccel",
            "mouseNaturalScroll", "cursorSize", "touchpadSpeed", "touchpadScrollSpeed", "touchpadNaturalScroll", "touchpadTapToClick",
            "touchpadIgnoreWhileTyping"],
        sound: ["volumeSound", "soundEffectsVolume"],
        power: ["lidAction", "powerKeyAction", "profileOnBattery", "profileOnAC"],
        apps: ["defaultTerminal", "defaultBrowser", "defaultFileManager", "defaultEditor", "defaultCalculator"],
        startup: ["startupApps"],
        screenshots: ["screenshotAfter", "screenshotFolder", "screenshotName"],
        windows: ["windowMode", "focusFollowsMouse", "titleButtons", "windowBorderSize", "windowGap", "soloWindowGap", "inactiveDim", "switcherPreviews", "switcherAppIcons"],
        workspaces: ["workspaceAnimation", "wrapWorkspaces", "keepEmptyWorkspace", "workspaceShape", "overviewCardWidth", "overviewAppIcons"],
        spaces: ["barShowSpaces", "spaceBarTint", "spaceBorders", "spaceBadges", "spaceSwitcherBadges"],
        hotcorners: ["hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight", "hotCornerDelay"],
        notifications: ["notificationPosition", "notificationSeconds", "notificationMaxToasts"],
        screensaver: ["screensaverMinutes", "screensaverStyle", "screensaverClock", "screensaverSlideSeconds", "screensaverLock"],
        shortcuts: ["keyset"],
        updates: ["updateCheck"],
        lock: ["lockBeforeSleep", "lockScreenPowerMenu", "idleLockMinutes", "idleScreenOffMinutes", "idleSuspendMinutes",
            "idleRespectInhibitors"]
    })
    readonly property var currentKeys: pageKeys[section] || []
    // Settings on this page that differ from their defaults (re-read whenever settings change)
    property int changedHere: 0
    function countChanged() { changedHere = Config.changedCount(currentKeys); }
    onCurrentKeysChanged: countChanged()
    Connections { target: Config; function onSaved() { win.countChanged(); } }
    property bool confirmReset: false
    onSectionChanged: { if (section !== "general") avatarPicking = false; confirmReset = false; }
    property string pageTitle: ""
    // Descriptions wrap at a comfortable reading length (~70 characters of the UI font)
    FontMetrics { id: detailMetrics; font.family: win.font; font.pixelSize: 12 }
    FontMetrics { id: introMetrics; font.family: win.font; font.pixelSize: 13 }
    readonly property real detailMeasure: detailMetrics.averageCharacterWidth * 70
    readonly property real introMeasure: introMetrics.averageCharacterWidth * 70
    // Every page. The ones used most are down the sidebar; the rest (more: true) are tiles on
    // the Overview, the first page
    readonly property var sections: [
        { id: "general", label: "General", icon: 0xEB20 },
        { id: "appearance", label: "Appearance", icon: 0xEB01 },
        { id: "displays", label: "Displays", icon: 0xEA89 },
        { id: "input", label: "Keyboard & mouse", icon: 0xEBD6 },
        { id: "sound", label: "Sound", icon: 0xEB51 },
        { id: "power", label: "Power", icon: 0xEA38 },
        { id: "windows", label: "Windows", icon: 0xEFE6 },
        { id: "workspaces", label: "Workspaces", icon: 0xEDBA },
        { id: "notifications", label: "Notifications", icon: 0xEA35 },
        { id: "wifi", label: "Wi-Fi", icon: 0xEB52 },
        { id: "bluetooth", label: "Bluetooth", icon: 0xEA37 },
        { id: "bar", label: "Menu bar", icon: 0xEAD7, more: true, about: "Position, auto-hide, and what it shows" },
        { id: "dock", label: "Dock", icon: 0xEAD3, more: true, about: "Position, auto-hide, icon size and magnification" },
        { id: "launcher", label: "Launcher", icon: 0xEB1C, more: true, about: "App descriptions and ordering by use" },
        { id: "spaces", label: "Spaces", icon: 0xEEF6, more: true, about: "Saved sets of workspaces, and how their windows are marked" },
        { id: "hotcorners", label: "Hot corners", icon: 0xF7A0, more: true, about: "Actions for the corners of the screen" },
        { id: "lock", label: "Lock & idle", icon: 0xEAE2, more: true, about: "Locking, screen off and sleep when idle; the login screen" },
        { id: "screensaver", label: "Screensaver", icon: 0xEAF8, more: true, about: "A clock, your wallpaper or a slideshow while you're away" },
        { id: "shortcuts", label: "Shortcuts", icon: 0xEA78, more: true, about: "Every keyboard shortcut, searchable" },
        { id: "apps", label: "Default apps", icon: 0xEBB6, more: true, about: "Terminal, browser, files, editor and calculator" },
        { id: "startup", label: "Startup apps", icon: 0xEC45, more: true, about: "Apps that open when you log in" },
        { id: "datetime", label: "Date & time", icon: 0xEA70, more: true, about: "Time zone and setting the time automatically" },
        { id: "apptheming", label: "App theming", icon: 0xEB01, more: true, about: "Other apps following Slate's colours: terminals, editors, GTK, Qt…" },
        { id: "screenshots", label: "Screenshots", icon: 0xF201, more: true, about: "Where they're saved, their names, and marking up" },
        { id: "updates", label: "Updates", icon: 0xEA96, more: true, about: "New versions of Slate: what's new, updating and going back" },
        { id: "about", label: "About", icon: 0xEAC5, more: true, about: "Slate's files, and restarting it" }
    ]
    readonly property var sidebarSections: [{ id: "overview", label: "Overview", icon: 0xEDBA }].concat(sections.filter(x => !x.more))
    readonly property var moreSections: sections.filter(x => x.more)
    // A page opened from the Overview: the sidebar keeps Overview lit, and the title gets a back arrow
    readonly property bool onMorePage: moreSections.some(x => x.id === section)

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { if (win.confirmReset) win.confirmReset = false; else if (dropLayer.owner) dropLayer.owner = null; else win.visible = false; }

        // ---- Sidebar -------------------------------------------------------
        Rectangle {
            id: sidebar
            width: win.compact ? 66 : 210
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            color: win.bar.barColor
            // Scrolls when the pages don't all fit (a short screen)
            Flickable {
                id: sideScroll
                anchors { fill: parent; margins: 14 }
                contentHeight: sideCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                SmoothWheel { flick: sideScroll }
            Column {
                id: sideCol
                width: parent.width
                spacing: 2
                // Slate's mark (as on the About page) beside the title
                Row {
                    leftPadding: 4; topPadding: 4; bottomPadding: 14
                    spacing: 8
                    SlateLogo { size: win.compact ? 30 : 40; showText: false; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        visible: !win.compact
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Slate"; color: win.text; font.family: win.font; font.pixelSize: 18; font.weight: Font.Medium }
                        Text { text: "Settings"; color: win.dim; font.family: win.font; font.pixelSize: 12 }
                    }
                }
                Repeater {
                    model: win.sidebarSections
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: win.section === modelData.id || (modelData.id === "overview" && win.onMorePage)
                        width: parent.width; height: 38; radius: 9
                        color: current ? win.card : navHover.hovered ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (current || navHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            id: navIcon
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: win.glyph(parent.modelData.icon)
                            color: parent.current ? win.accent : win.dim
                            font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                        Text {
                            visible: !win.compact
                            anchors { left: navIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: parent.modelData.label
                            color: parent.current ? win.text : win.dim
                            font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        HoverHandler { id: navHover }
                        TapHandler { onTapped: win.section = parent.modelData.id }
                    }
                }
            }
            }
        }

        // ---- Content -------------------------------------------------------
        Rectangle {
            // Fills the rest of the window, edge to edge (the window's own corners round it)
            anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right; right: parent.right }
            radius: 0
            color: Config.tint("#151920")

            id: contentPane
            // Header: the page's title and the close button; the page scrolls beneath it
            Item {
                id: header
                z: 2
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 66
                // Back to the Overview, from a page opened there
                Rectangle {
                    id: backBtn
                    visible: win.onMorePage
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                    width: 34; height: 34; radius: 17
                    color: backHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (backHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: win.glyph(0xEA19)
                        color: backHover.hovered ? win.text : win.dim
                        font.family: win.bar.iconFont; font.pixelSize: 18
                    }
                    HoverHandler { id: backHover }
                    TapHandler { onTapped: win.section = "overview" }
                }
                Text {
                    anchors { left: backBtn.visible ? backBtn.right : parent.left; leftMargin: backBtn.visible ? 6 : 22; right: resetBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                    text: win.pageTitle
                    color: win.text
                    font.family: win.font; font.pixelSize: 22; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                // Restore defaults: only on pages with settings, and only when something's changed
                Button {
                    id: resetBtn
                    compactLabel: win.compact
                    anchors { right: parent.right; rightMargin: 58; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }   // clear of the close button
                    visible: win.currentKeys.length > 0
                    opacity: win.changedHere > 0 ? 1 : 0.45
                    icon: 0xEB77
                    label: "Restore defaults"
                    onClicked: if (win.changedHere > 0) win.confirmReset = true
                }
            }
            Rectangle {
                id: closeBtn
                z: 3
                anchors { right: parent.right; rightMargin: 14; verticalCenter: header.verticalCenter }
                width: 34; height: 34; radius: 17
                color: closeHover.hovered ? Config.hover : "transparent"
                Gloss { radius: parent.radius; opacity: (closeHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: win.glyph(0xEB55)
                    color: closeHover.hovered ? win.text : win.dim
                    font.family: win.bar.iconFont; font.pixelSize: 18
                }
                HoverHandler { id: closeHover }
                TapHandler { onTapped: win.visible = false }
            }

            // Lights up a setting found by search (showFound), then fades
            Rectangle {
                id: foundFlash
                z: 4
                opacity: 0
                radius: 10
                color: "transparent"
                border.width: 2; border.color: win.accent
                Rectangle { anchors.fill: parent; radius: parent.radius; color: win.accent; opacity: 0.12 }
                SequentialAnimation {
                    id: foundFade
                    NumberAnimation { target: foundFlash; property: "opacity"; to: 1; duration: 150 }
                    PauseAnimation { duration: 900 }
                    NumberAnimation { target: foundFlash; property: "opacity"; to: 0; duration: 600 }
                }
            }
            Flickable {
                id: scroller
                anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 22; rightMargin: 22 }
                contentHeight: pageLoader.item ? pageLoader.item.implicitHeight + 22 : 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: scroller }
                onContentYChanged: dropLayer.owner = null      // an open dropdown would drift away
                Loader {
                    id: pageLoader
                    width: scroller.width
                    sourceComponent: ({ overview: overviewPage, general: generalPage, appearance: appearancePage, bar: barPage, dock: dockPage, launcher: launcherPage, spaces: spacesPage,
                        displays: displaysPage, input: inputPage, sound: soundPage, power: powerPage, shortcuts: shortcutsPage,
                        apps: appsPage, startup: startupPage, datetime: timePage, screenshots: shotsPage, windows: windowsPage, notifications: notificationsPage, bluetooth: bluetoothPage, about: aboutPage, wifi: wifiPage, hotcorners: hotCornersPage, lock: lockPage, screensaver: screensaverPage, updates: updatesPage, workspaces: workspacesPage, apptheming: appThemingPage })[win.section]
                    onLoaded: { scroller.contentY = 0; dropLayer.owner = null; if (win.findLabel) Qt.callLater(() => Qt.callLater(win.showFound)); }
                }
            }

            // Scrollbar (ThinScrollbar, as everywhere), in the right-hand margin
            ThinScrollbar {
                id: scrollbar
                z: 2
                flick: scroller
                color: win.text
                anchors { top: header.bottom; bottom: parent.bottom; right: parent.right; topMargin: 4; bottomMargin: 14; rightMargin: 6 }
            }

            // Scroll shadows: under the header once scrolled down, and at the bottom while
            // there's more below
            Rectangle {
                z: 1
                anchors { top: header.bottom; left: parent.left; right: parent.right }
                height: 18
                topLeftRadius: contentPane.radius; topRightRadius: contentPane.radius
                // Fades with the distance from the edge, gone just as you reach it
                opacity: Math.max(0, Math.min(1, (scroller.contentY - scroller.originY) / 24))
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Config.s.lightMode ? 0.12 : 0.32) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                z: 1
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 24
                bottomLeftRadius: contentPane.radius; bottomRightRadius: contentPane.radius
                opacity: Math.max(0, Math.min(1, (scroller.originY + scroller.contentHeight - scroller.height - scroller.contentY) / 24))
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, Config.s.lightMode ? 0.14 : 0.38) }
                }
            }
        }
    }

    // ---- Dropdown menus ----------------------------------------------------
    // ---- Restore defaults: confirmation ---------------------------------------------
    Rectangle {
        id: resetConfirm
        anchors.fill: parent
        z: 120
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: opacity > 0
        opacity: win.confirmReset ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        onVisibleChanged: if (visible) resetConfirmCard.forceActiveFocus()
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: win.confirmReset = false }
        Rectangle {
            id: resetConfirmCard
            anchors.centerIn: parent
            width: 380; height: confirmCol.implicitHeight + 40
            radius: 16
            color: win.bar.barColor
            border.width: 1; border.color: Config.tint("#2a313c")
            scale: win.confirmReset ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }    // clicks on the card don't close it
            Keys.onEscapePressed: win.confirmReset = false
            Keys.onReturnPressed: confirmYes.clicked()
            Keys.onEnterPressed: confirmYes.clicked()
            Column {
                id: confirmCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 8
                Text {
                    text: "Restore " + win.pageTitle + " defaults?"
                    color: win.text; font.family: win.font; font.pixelSize: 16; font.weight: Font.Medium
                    width: parent.width; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: win.changedHere + (win.changedHere === 1 ? " setting on this page goes" : " settings on this page go")
                        + " back to how Slate starts out. Other pages aren't touched."
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
                Item { width: 1; height: 8 }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Button { label: "Cancel"; onClicked: win.confirmReset = false }
                    Button {
                        id: confirmYes
                        label: "Restore defaults"; primary: true
                        onClicked: { Config.resetKeys(win.currentKeys); win.confirmReset = false; win.countChanged(); }
                    }
                }
            }
        }
    }

    // One shared layer over the whole window, so a menu isn't clipped by the scrolling
    // page. A DropdownSetting sets itself as the owner to open its menu here.
    Item {
        id: dropLayer
        anchors.fill: parent
        z: 100
        property var owner: null
        visible: owner !== null
        onVisibleChanged: if (visible) place()
        property real menuX: 0
        property real menuY: 0
        property real menuH: 0
        readonly property real rowH: 34
        function place() {
            const b = owner.button;
            const p = b.mapToItem(dropLayer, 0, 0);
            const full = (owner.options ? owner.options.length : 0) * rowH + 12;
            menuX = Math.max(8, Math.min(width - menu.width - 8, p.x + b.width - menu.width));
            // Below the button, or above it if there's no room; a long list goes on the
            // roomier side, as tall as fits, and scrolls
            const below = height - 8 - (p.y + b.height + 6), above = p.y - 6 - 8;
            const downwards = full <= below || (full > above && below >= above);
            menuH = Math.max(Math.min(full, 3 * rowH + 12), Math.min(full, downwards ? below : above));
            menuY = downwards ? Math.min(p.y + b.height + 6, height - 8 - menuH) : Math.max(8, p.y - 6 - menuH);
            // Open on the current choice
            const i = owner.options ? owner.options.findIndex(o => o.value === owner.value) : -1;
            Qt.callLater(() => menuList.positionViewAtIndex(Math.max(0, i), ListView.Contain));
        }
        // Click anywhere else to close
        MouseArea { anchors.fill: parent; onPressed: dropLayer.owner = null }
        Rectangle {
            id: menu
            x: dropLayer.menuX; y: dropLayer.menuY
            width: Math.max(200, dropLayer.owner ? dropLayer.owner.button.width : 0)
            height: dropLayer.menuH
            radius: 12
            color: Config.tint("#1d222a")
            border.width: 1; border.color: Config.tint("#2a313c")
            opacity: dropLayer.visible ? 1 : 0
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.4; shadowBlur: 0.8; shadowVerticalOffset: 4; blurMax: 24 }
            MouseArea { anchors.fill: parent }     // clicks between rows stay in the menu
            ListView {
                id: menuList
                anchors { fill: parent; margins: 6 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: menuList }
                model: dropLayer.owner ? dropLayer.owner.options : []
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool current: dropLayer.owner && modelData.value === dropLayer.owner.value
                    width: menuList.width; height: dropLayer.rowH; radius: 8
                    color: rowHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (rowHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                    FolderSwatch {
                        id: rowFolder
                        visible: !!parent.modelData.folder
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        colour: parent.modelData.folder || "transparent"
                    }
                    Text {
                        anchors { left: rowFolder.visible ? rowFolder.right : parent.left; leftMargin: rowFolder.visible ? 10 : 12; right: tick.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.label
                        color: parent.current ? win.accent : win.text
                        font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        id: tick
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: parent.current
                        text: win.glyph(0xEA5E)
                        color: win.accent
                        font.family: win.bar.iconFont; font.pixelSize: 16
                    }
                    HoverHandler { id: rowHover }
                    // A MouseArea (not a TapHandler): the menu's own MouseArea underneath would otherwise
                    // take the click first and the pick would never happen
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            const o = dropLayer.owner;
                            const v = parent.modelData.value;
                            dropLayer.owner = null;
                            o.picked(v);
                        }
                    }
                }
            }
        }
    }

    // ---- Building blocks ---------------------------------------------------
    // A page names itself; the title is drawn in the fixed header above the scrolling page
    component PageTitle: Item {
        property string text
        width: 1; height: 0
        visible: false
        onTextChanged: win.pageTitle = text
        Component.onCompleted: win.pageTitle = text
    }
    component GroupLabel: Text {
        color: win.dim
        font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
        topPadding: 14; bottomPadding: 6; leftPadding: 4
    }
    // Rounded card holding a few rows
    component Group: Rectangle {
        default property alias rows: groupCol.data
        width: parent ? parent.width : 0
        height: groupCol.implicitHeight + 8
        radius: 12
        color: win.card
        Column { id: groupCol; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 } }
    }
    // One setting: label + description on the left, a control on the right
    component SettingRow: Item {
        property string label
        property string detail: ""
        default property alias control: controlSlot.data
        width: parent ? parent.width : 0
        height: Math.max(56, labels.implicitHeight + 24, controlSlot.height + 24)
        Column {
            id: labels
            anchors { left: parent.left; leftMargin: 16; right: controlSlot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text { width: parent.width; text: label; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
            Text { width: Math.min(parent.width, win.detailMeasure); visible: detail !== ""; text: detail; color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap }
        }
        Item {
            id: controlSlot
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
    }
    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled(bool value)
        width: 42; height: 24; radius: 12
        color: checked ? (tgHover.hovered ? Qt.lighter(win.accent, 1.08) : win.accent)
            : (tgHover.hovered ? Config.tint("#38414e") : Config.tint("#2a313c"))
        Behavior on color { ColorAnimation { duration: 120 } }
        // Hover: a soft accent ring around the switch
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: height / 2
            color: "transparent"
            border.width: 2; border.color: win.accent
            opacity: tgHover.hovered ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        HoverHandler { id: tgHover }
        Gloss { radius: parent.radius }   // glass: a sheen
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: tg.checked ? parent.width - width - 3 : 3
            color: tg.checked ? win.accentText : win.text
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        TapHandler { onTapped: tg.toggled(!tg.checked) }
    }
    // Slider with its value shown alongside
    component ValueSlider: Row {
        id: vs
        property real from: 0
        property real to: 1
        property real stepSize: 0.1
        property real value: 0
        property string suffix: ""
        property int decimals: 0
        signal moved(real value)
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            horizontalAlignment: Text.AlignRight
            text: vs.value.toFixed(vs.decimals) + vs.suffix
            color: win.dim
            font.family: win.font; font.pixelSize: 12
        }
        Item {
            width: 200; height: 24
            readonly property real frac: (vs.value - vs.from) / (vs.to - vs.from)
            id: sliderBox
            readonly property bool hot: sliderMouse.containsMouse || sliderMouse.pressed
            Rectangle {
                id: trk
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: sliderBox.hot ? Config.tint("#38414e") : Config.tint("#2a313c")
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle { width: Math.max(6, trk.width * parent.parent.frac); height: parent.height; radius: 3; color: win.accent }
            }
            // Hover: an accent halo behind the knob, which grows a little
            Rectangle {
                width: 28; height: 28; radius: 14
                anchors.verticalCenter: parent.verticalCenter
                x: parent.frac * (parent.width - 16) + 8 - width / 2
                color: win.accent
                opacity: sliderBox.hot ? 0.22 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: parent.frac * (parent.width - 16)
                color: win.text
                Gloss { radius: parent.radius; strength: 0.6 }   // glass: a sheen
                scale: sliderBox.hot ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: sliderMouse
                anchors.fill: parent
                hoverEnabled: true
                function set(mx) {
                    const raw = vs.from + Math.max(0, Math.min(1, mx / width)) * (vs.to - vs.from);
                    vs.moved(Math.round(raw / vs.stepSize) * vs.stepSize);
                }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x); }
            }
        }
    }
    component Button: Rectangle {
        id: btn
        property string label
        property bool primary: false
        property bool destructive: false
        property int icon: 0          // optional Tabler glyph before the label
        property bool compactLabel: false   // with an icon: show just the icon (narrow window)
        signal clicked()
        width: btnRow.implicitWidth + 28; height: 32; radius: 8
        color: primary ? (btnHover.hovered ? Qt.lighter(win.accent, 1.1) : win.accent)
            : btnHover.hovered ? Config.tint("#323a46") : Config.tint("#2a313c")
        Behavior on color { ColorAnimation { duration: 100 } }
        readonly property color fg: primary ? win.accentText : destructive ? win.danger : win.text
        Gloss { radius: parent.radius }   // glass: a sheen
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: btn.icon !== 0
                anchors.verticalCenter: parent.verticalCenter
                text: btn.icon ? win.glyph(btn.icon) : ""
                color: btn.fg
                font.family: win.bar.iconFont; font.pixelSize: 15
            }
            Text {
                visible: !(btn.compactLabel && btn.icon !== 0)
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.fg
                font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
        HoverHandler { id: btnHover }
        TapHandler { onTapped: btn.clicked() }
    }
    // A font choice: shows the current font, and opens a searchable list of
    // installed fonts (each shown in its own typeface). key = Config.s property.
    component FontSetting: Column {
        id: fs
        property string label
        property string detail
        property string key
        property string defaultFont
        property bool monoOnly: false
        property bool open: false
        readonly property string value: Config.s[key]
        function choose(f) { Config.s[key] = f; }
        width: parent ? parent.width : 0

        // Monospaced fonts, from fontconfig, plus anything named like one
        property var monoFonts: []
        Process {
            running: fs.monoOnly
            command: ["fc-list", ":spacing=mono", "family"]
            stdout: StdioCollector {
                onStreamFinished: fs.monoFonts = text.split("\n").map(l => l.split(",")[0].trim()).filter(f => f)
            }
        }
        readonly property var all: Qt.fontFamilies().filter(f => f && !f.startsWith(".")
            && !/icon|emoji|symbol|tabler|awesome|powerline|signwriting|\.pcf$/i.test(f)
            && (!monoOnly || monoFonts.includes(f) || /mono|code|console|courier|terminal|fixed/i.test(f)))
        readonly property var shown: {
            const q = fontSearch.text.trim().toLowerCase();
            return q ? all.filter(f => f.toLowerCase().includes(q)) : all;
        }
        onOpenChanged: if (open) {
            fontSearch.text = "";
            fontSearch.forceActiveFocus();
            revealTimer.restart();
        }
        // Once the list has been laid out, scroll the page so it's all on screen
        Timer {
            id: revealTimer; interval: 30
            onTriggered: { fontList.positionViewAtIndex(Math.max(0, fs.shown.indexOf(fs.value)), ListView.Center); fs.revealList(); }
        }
        function revealList() {
            const bottom = fs.mapToItem(scroller.contentItem, 0, fs.height).y;
            const top = fs.mapToItem(scroller.contentItem, 0, 0).y;
            if (bottom > scroller.contentY + scroller.height)
                scroller.contentY = Math.min(top, bottom - scroller.height);
        }

        SettingRow {
            label: fs.label
            detail: fs.detail
            Row {
                spacing: 8
                Button { visible: fs.value !== fs.defaultFont; label: "Default"; onClicked: fs.choose(fs.defaultFont) }
                Button {
                    label: fs.value + (fs.open ? "  ▴" : "  ▾")
                    primary: fs.open
                    onClicked: fs.open = !fs.open
                }
            }
        }
        Item {
            visible: fs.open
            width: parent.width
            height: fs.open ? 300 : 0
            Rectangle {
                id: fontSearchBox
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                height: 34; radius: 8
                color: Config.tint("#2a313c")
                // Hover: a faint accent outline (solid while typing)
                HoverHandler { id: fontSearchHover; cursorShape: Qt.IBeamCursor }
                border.width: fontSearch.activeFocus || fontSearchHover.hovered ? 1 : 0; border.color: fontSearch.activeFocus ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.5)
                TextInput {
                    id: fontSearch
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: win.text; selectionColor: win.accent
                    font.family: win.font; font.pixelSize: 13
                    Keys.onEscapePressed: fs.open = false
                    Keys.onReturnPressed: if (fs.shown.length) { fs.choose(fs.shown[0]); fs.open = false; }
                }
                Text {
                    visible: fontSearch.text === ""
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Search " + fs.all.length + " fonts"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
            }
            ListView {
                id: fontList
                anchors { left: parent.left; right: parent.right; top: fontSearchBox.bottom; bottom: parent.bottom; margins: 8; leftMargin: 12; rightMargin: 12 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: fs.shown
                SmoothWheel { flick: fontList; notch: 108 }
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool current: fs.value === modelData
                    width: ListView.view.width; height: 36; radius: 8
                    color: current ? win.accent : fontHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (current || fontHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                    Text {
                        anchors { left: parent.left; leftMargin: 12; right: sample.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: parent.modelData
                        color: parent.current ? win.accentText : win.text
                        font.family: parent.modelData; font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                    Text {
                        id: sample
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: fs.monoOnly ? "{ x => 0 }" : "Aa 123"
                        color: parent.current ? win.accentText : win.dim
                        font.family: parent.modelData; font.pixelSize: 13
                    }
                    HoverHandler { id: fontHover }
                    TapHandler { onTapped: fs.choose(parent.modelData) }
                }
            }
        }
    }
    // A setting with a few named options: shows the current one; click to pick.
    // options: [{ value, label }]
    component ChoiceSetting: Column {
        id: ch
        property string label
        property string detail: ""
        property var options: []
        property var value
        property bool open: false
        signal picked(var value)
        width: parent ? parent.width : 0
        readonly property var current: options.find(o => o.value === value) ?? null
        SettingRow {
            label: ch.label
            detail: ch.detail
            Button {
                label: (ch.current ? ch.current.label : String(ch.value)) + (ch.open ? "  ▴" : "  ▾")
                primary: ch.open
                onClicked: ch.open = !ch.open
            }
        }
        Flow {
            visible: ch.open
            width: parent.width - 32; x: 16
            spacing: 6
            bottomPadding: 14
            Repeater {
                model: ch.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.value === ch.value
                    width: optText.implicitWidth + 26; height: 32; radius: 8
                    color: on ? win.accent : optHover.hovered ? Config.hoverOn(Config.tint("#2a313c")) : Config.tint("#2a313c")
                    Gloss { radius: parent.radius; opacity: (on || optHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                    Text { id: optText; anchors.centerIn: parent; text: parent.modelData.label; color: parent.on ? win.accentText : win.text; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                    HoverHandler { id: optHover }
                    TapHandler { onTapped: { ch.picked(parent.modelData.value); ch.open = false; } }
                }
            }
        }
    }
    // A setting with a dropdown menu of choices (opens over the page; see dropLayer)
    component DropdownSetting: Item {
        id: dd
        property string label
        property string detail: ""
        width: parent ? parent.width : 0
        height: ddRow.height
        property var options: []
        property var value
        signal picked(var value)
        readonly property var current: options.find(o => o.value === value) ?? null
        property alias button: ddButton
        SettingRow {
          id: ddRow
          label: dd.label
          detail: dd.detail
          Rectangle {
            id: ddButton
            readonly property bool open: dropLayer.owner === dd
            width: Math.max(150, ddText.implicitWidth + 44 + (ddFolder.visible ? ddFolder.width + 8 : 0)); height: 32; radius: 8
            color: open || ddHover.hovered ? Config.hoverOn(Config.tint("#2a313c")) : Config.tint("#2a313c")
            Gloss { radius: parent.radius }   // glass: a sheen
            border.width: open ? 1 : 0; border.color: win.accent
            Behavior on color { ColorAnimation { duration: 100 } }
            // Options can carry a folder colour (folder: "#hex"): a little folder in it before the label
            FolderSwatch {
                id: ddFolder
                visible: !!dd.current && !!dd.current.folder
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                colour: dd.current && dd.current.folder ? dd.current.folder : "transparent"
            }
            Text {
                id: ddText
                anchors { left: ddFolder.visible ? ddFolder.right : parent.left; leftMargin: ddFolder.visible ? 8 : 12; verticalCenter: parent.verticalCenter }
                text: dd.current ? dd.current.label : String(dd.value)
                color: win.text; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
            }
            Text {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: win.glyph(0xEA5F)                      // chevron down
                rotation: ddButton.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 120 } }
                color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
            }
            HoverHandler { id: ddHover }
            TapHandler { onTapped: dropLayer.owner = ddButton.open ? null : dd }
          }
        }
    }
    component Separator: Rectangle { width: parent ? parent.width - 32 : 0; x: 16; height: 1; color: Config.tint("#262c35") }
    // A choice from a long list (keyboard layouts, time zones, apps): a button that opens a
    // search box and list under the row. options: [{ value, label, detail? }]
    component SearchPicker: Column {
        id: sp
        property string label
        property string detail: ""
        property string buttonLabel: "Choose…"
        property int buttonIcon: 0
        property var options: []
        property bool open: false
        signal picked(var value)
        width: parent ? parent.width : 0
        readonly property var shown: {
            const q = findBox.text.toLowerCase().trim();
            const list = q === "" ? options : options.filter(o => (o.label + " " + (o.detail || "") + " " + o.value).toLowerCase().includes(q));
            return list.slice(0, 400);
        }
        SettingRow {
            label: sp.label
            detail: sp.detail
            Button {
                icon: sp.open ? 0 : sp.buttonIcon
                label: sp.open ? "Cancel" : sp.buttonLabel
                onClicked: {
                    sp.open = !sp.open;
                    findBox.text = "";
                    if (sp.open) Qt.callLater(() => findBox.forceActiveFocus());
                }
            }
        }
        Column {
            visible: sp.open
            width: parent.width - 32; x: 16
            spacing: 6
            bottomPadding: 14
            Rectangle {
                width: parent.width; height: 34; radius: 8
                color: Config.tint("#151920")
                border.width: findBox.activeFocus ? 1 : 0; border.color: win.accent
                Text {
                    id: findGlass
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: win.glyph(0xEB1C); color: win.dim
                    font.family: win.bar.iconFont; font.pixelSize: 15
                }
                TextInput {
                    id: findBox
                    anchors { left: findGlass.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: win.text; font.family: win.font; font.pixelSize: 13
                    selectionColor: win.accent; selectedTextColor: win.accentText
                    clip: true
                    Keys.onReturnPressed: if (sp.shown.length > 0) { sp.picked(sp.shown[0].value); sp.open = false; }
                    Keys.onEscapePressed: event => { sp.open = false; event.accepted = true; }
                    Text { visible: findBox.text === ""; text: "Search"; color: win.dim; font: findBox.font; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Rectangle {
                width: parent.width; height: Math.min(220, Math.max(40, pickList.contentHeight + 8)); radius: 8
                color: Config.tint("#151920")
                ListView {
                    id: pickList
                    anchors { fill: parent; margins: 4 }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: pickList }
                    model: sp.shown
                    delegate: Rectangle {
                        required property var modelData
                        width: pickList.width; height: pickDetail.visible ? 42 : 32; radius: 6
                        color: pickHover.hovered ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (pickHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Column {
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; text: parent.parent.modelData.label; color: win.text; font.family: win.font; font.pixelSize: 13; elide: Text.ElideRight }
                            Text { id: pickDetail; width: parent.width; visible: !!parent.parent.modelData.detail; text: parent.parent.modelData.detail || ""; color: win.dim; font.family: win.font; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        HoverHandler { id: pickHover }
                        TapHandler { onTapped: { sp.picked(parent.modelData.value); sp.open = false; } }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: pickList.count === 0
                        text: "Nothing matches"
                        color: win.dim; font.family: win.font; font.pixelSize: 12
                    }
                }
            }
        }
    }
    // An item in a list setting (a keyboard layout, a startup app), with a way to remove it
    component ListItemRow: SettingRow {
        id: lir
        property bool removable: true
        signal removed()
        Button {
            visible: lir.removable
            icon: 0xEB41
            label: "Remove"
            compactLabel: true
            onClicked: lir.removed()
        }
    }

    // ---- Pages -------------------------------------------------------------
    // Overview: tiles for the pages that aren't in the sidebar
    Component {
        id: overviewPage
        Column {
            id: ovPage
            spacing: 4
            PageTitle { text: "Overview" }
            // ---- Search every setting (SettingsIndex) ----------------------------------
            readonly property var found: SettingsIndex.search(findField.text, 30)
            property int pick: 0
            onFoundChanged: pick = 0
            function open(e) { if (e) win.goTo(e.page, e.label); }
            Rectangle {
                width: parent.width; height: 44
                radius: 12
                color: win.card
                border.width: findField.activeFocus ? 1 : 0; border.color: win.accent
                Text {
                    id: findIcon
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: win.glyph(0xEB1C)
                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 18
                }
                TextInput {
                    id: findField
                    anchors { left: findIcon.right; leftMargin: 10; right: clearFind.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    color: win.text; font.family: win.font; font.pixelSize: 14
                    selectionColor: win.accent; selectedTextColor: win.accentText
                    clip: true
                    // Ready to type whenever the Overview shows: when the page loads and each time
                    // the window opens (after the window's own focus has settled), starting afresh
                    function ready() { Qt.callLater(() => Qt.callLater(() => { if (win.visible && win.section === "overview") findField.forceActiveFocus(); })); }
                    Component.onCompleted: ready()
                    Connections {
                        target: win
                        function onVisibleChanged() { if (win.visible) { findField.text = ""; findField.ready(); } }
                    }
                    // ...and when the window gets the keyboard (Hyprland focuses it a moment after it shows)
                    readonly property bool windowActive: Window.active
                    onWindowActiveChanged: if (windowActive && text === "") ready()
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Down) { ovPage.pick = Math.min(ovPage.found.length - 1, ovPage.pick + 1); e.accepted = true; }
                        else if (e.key === Qt.Key_Up) { ovPage.pick = Math.max(0, ovPage.pick - 1); e.accepted = true; }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ovPage.open(ovPage.found[ovPage.pick]); e.accepted = true; }
                        else if (e.key === Qt.Key_Escape && text !== "") { text = ""; e.accepted = true; }
                    }
                    Text {
                        visible: findField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search settings"
                        color: win.dim; font: findField.font
                    }
                }
                Text {
                    id: clearFind
                    visible: findField.text !== ""
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: win.glyph(0xEB55)
                    color: clearHover.hovered ? win.text : win.dim
                    font.family: win.bar.iconFont; font.pixelSize: 16
                    HoverHandler { id: clearHover }
                    TapHandler { onTapped: { findField.text = ""; findField.forceActiveFocus(); } }
                }
            }
            Item { width: 1; height: 6 }
            // Results, while searching
            Text {
                visible: findField.text.trim().length >= 2 && ovPage.found.length === 0
                topPadding: 8; leftPadding: 4
                text: "No settings match “" + findField.text.trim() + "”"
                color: win.dim; font.family: win.font; font.pixelSize: 13
            }
            Group {
                visible: ovPage.found.length > 0
                Repeater {
                    model: ovPage.found
                    delegate: Rectangle {
                        id: hitRow
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === ovPage.pick
                        width: parent.width; height: hitCol.implicitHeight + 18
                        radius: 9
                        color: chosen ? Config.tint("#262c35") : hitHover.hovered ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (chosen || hitHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                        Text {
                            id: hitIcon
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            text: win.glyph(SettingsIndex.pageIcons[hitRow.modelData.page] || 0xEB20)
                            color: hitRow.chosen ? win.accent : win.dim
                            font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                        Column {
                            id: hitCol
                            anchors { left: hitIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width
                                text: hitRow.modelData.label
                                color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: (SettingsIndex.pageNames[hitRow.modelData.page] || "")
                                    + (hitRow.modelData.group && hitRow.modelData.group !== hitRow.modelData.label ? " → " + hitRow.modelData.group : "")
                                    + (hitRow.modelData.detail ? " · " + hitRow.modelData.detail : "")
                                color: win.dim; font.family: win.font; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        HoverHandler { id: hitHover; onHoveredChanged: if (hovered) ovPage.pick = hitRow.index }
                        TapHandler { onTapped: ovPage.open(hitRow.modelData) }
                    }
                }
            }
            GroupLabel { visible: findField.text.trim().length < 2; text: "More settings" }
            Flow {
                id: tiles
                visible: findField.text.trim().length < 2
                width: parent.width
                spacing: 10
                // Two or three across, filling the width
                readonly property int across: width >= 560 ? 3 : width >= 340 ? 2 : 1
                readonly property real tileW: (width - spacing * (across - 1)) / across
                Repeater {
                    model: win.moreSections
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        width: tiles.tileW
                        height: 112
                        radius: 12
                        color: tileHover.hovered ? Config.hoverOn(win.card) : win.card
                        Gloss { radius: parent.radius; opacity: (tileHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Rectangle {
                            x: 14; y: 14
                            width: 34; height: 34; radius: 10
                            color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
                            Text {
                                anchors.centerIn: parent
                                text: win.glyph(tile.modelData.icon)
                                color: win.accent
                                font.family: win.bar.iconFont; font.pixelSize: 18
                            }
                        }
                        Column {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 58 }
                            spacing: 2
                            Text {
                                width: parent.width
                                text: tile.modelData.label
                                color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: tile.modelData.about
                                color: win.dim; font.family: win.font; font.pixelSize: 11
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            }
                        }
                        HoverHandler { id: tileHover }
                        TapHandler { onTapped: win.section = tile.modelData.id }
                    }
                }
            }
        }
    }
    Component {
        id: generalPage
        Column {
            id: generalCol
            spacing: 4
            PageTitle { text: "General" }
            // ---- Account: your picture (AccountsService) and name
            property string fullName: Quickshell.env("USER")
            Process {
                running: true
                command: ["getent", "passwd", Quickshell.env("USER")]
                stdout: StdioCollector { onStreamFinished: { const n = (text.split(":")[4] || "").split(",")[0]; if (n) generalCol.fullName = n; } }
            }
            Group {
                Item {
                    width: parent.width; height: 88
                    // Picture: hover greys it with a pencil; click to choose another
                    Item {
                        id: acctPic
                        x: 16; width: 60; height: 60
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: Config.tint("#2a313c")
                            visible: acctImg.status !== Image.Ready
                            Text { anchors.centerIn: parent; text: win.glyph(0xEF68); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 34 }
                        }
                        RoundImage {
                            id: acctImg
                            anchors.fill: parent; radius: width / 2
                            source: Config.avatarUrl
                            saturation: acctHover.hovered || Config.avatarBusy ? -1 : 0
                            brightness: acctHover.hovered || Config.avatarBusy ? -0.45 : 0
                            Behavior on saturation { NumberAnimation { duration: 150 } }
                            Behavior on brightness { NumberAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: win.glyph(0xEB04)
                            color: "white"
                            font.family: win.bar.iconFont; font.pixelSize: 20
                            opacity: acctHover.hovered && !Config.avatarBusy ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }
                        HoverHandler { id: acctHover }
                        TapHandler { onTapped: win.avatarPicking = !win.avatarPicking }
                    }
                    Column {
                        anchors { left: acctPic.right; leftMargin: 14; right: acctButtons.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text { width: parent.width; text: generalCol.fullName; color: win.text; font.family: win.font; font.pixelSize: 15; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text {
                            width: Math.min(parent.width, win.detailMeasure)
                            text: Config.avatarBusy ? "Changing your picture…"
                                : Config.avatarError !== "" ? Config.avatarError
                                : "Your picture on the control centre, lock screen and login screen"
                            color: Config.avatarError !== "" && !Config.avatarBusy ? win.danger : win.dim
                            font.family: win.font; font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                    }
                    Row {
                        id: acctButtons
                        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        Button { icon: 0xEB0A; label: win.avatarPicking ? "Done" : "Change picture"; onClicked: win.avatarPicking = !win.avatarPicking }
                    }
                }
            }
            // The chooser: pictures in ~/Pictures, or browse for any image
            Column {
                id: picker
                visible: win.avatarPicking
                width: parent.width
                spacing: 0
                readonly property string folder: Quickshell.env("HOME") + "/Pictures"
                Item {
                    width: parent.width; height: pickLabel.implicitHeight
                    GroupLabel { id: pickLabel; text: avatarFiles.count > 0 ? "Pick a picture from Pictures" : "No pictures in ~/Pictures" }
                    Button {
                        anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
                        icon: 0xFAF7; label: "Browse…"
                        onClicked: avatarDialog.open()
                    }
                }
                Item { width: 1; height: 6 }
                FolderListModel {
                    id: avatarFiles
                    folder: "file://" + picker.folder
                    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG"]
                    showDirs: false
                    sortField: FolderListModel.Time
                }
                Grid {
                    id: avatarGrid
                    width: parent.width
                    spacing: 12
                    leftPadding: 4
                    columns: Math.max(1, Math.floor((width - 4 + spacing) / (72 + spacing)))
                    Repeater {
                        model: avatarFiles
                        delegate: Item {
                            required property string filePath
                            width: 72; height: 72
                            Rectangle {
                                anchors.fill: parent; radius: width / 2
                                color: win.card
                                border.width: pickHover.hovered ? 2 : 0
                                border.color: win.accent
                            }
                            Item {
                                anchors { fill: parent; margins: pickHover.hovered ? 4 : 0 }
                                Behavior on anchors.margins { NumberAnimation { duration: 100 } }
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: pickMask }
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + filePath
                                    sourceSize.width: 160
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                Item {
                                    id: pickMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    Rectangle { anchors.fill: parent; radius: width / 2 }
                                }
                            }
                            HoverHandler { id: pickHover }
                            TapHandler { onTapped: { Config.setAvatar(filePath); win.avatarPicking = false; } }
                        }
                    }
                }
                Item { width: 1; height: 10 }
                Dialogs.FileDialog {
                    id: avatarDialog
                    title: "Choose a picture"
                    currentFolder: "file://" + picker.folder
                    nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.PNG *.JPG *.JPEG)"]
                    onAccepted: { Config.setAvatar(selectedFile.toString()); win.avatarPicking = false; }
                }
            }
            GroupLabel { text: "Clipboard" }
            Group {
                SettingRow {
                    label: "Clipboard history"
                    detail: Config.s.clipboardHistory
                        ? "Keep the last 100 things you copy, text and images (Super+V, or the bar's clipboard). Passwords copied from password managers are never kept"
                        : "Off: nothing you copy is kept. Anything kept before stays until you clear it"
                    Toggle { checked: Config.s.clipboardHistory; onToggled: v => Config.s.clipboardHistory = v }
                }
                Separator {}
                SettingRow {
                    label: "Clear clipboard history"
                    detail: Config.clipCount === 0 ? "It's empty"
                        : Config.clipCount === 1 ? "Forget the 1 item it holds" : "Forget the " + Config.clipCount + " items it holds"
                    Button {
                        icon: 0xEB41; label: "Clear"; destructive: true
                        enabled: Config.clipCount > 0
                        opacity: enabled ? 1 : 0.5
                        onClicked: Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/clipstore.py"), "clear"])
                    }
                }
            }
            GroupLabel { text: "Location" }
            Group {
                // Search a place by name (Open-Meteo's free geocoding), then pick a result
                Column {
                    id: loc
                    width: parent.width
                    property var results: []
                    property string status: ""
                    function search(q) {
                        if (q.trim().length < 2) return;
                        status = "Searching…"; results = [];
                        geo.command = ["curl", "-sf", "--max-time", "10", "https://geocoding-api.open-meteo.com/v1/search?count=6&format=json&name=" + encodeURIComponent(q.trim())];
                        geo.running = true;
                    }
                    Process {
                        id: geo
                        stdout: StdioCollector {
                            onStreamFinished: {
                                try { loc.results = JSON.parse(text).results || []; } catch (e) { loc.results = []; }
                                loc.status = loc.results.length ? "" : "No places found";
                            }
                        }
                        onExited: code => { if (code !== 0) loc.status = "Couldn't search (offline?)"; }
                    }
                    SettingRow {
                        label: "Location"
                        detail: Config.s.locationName !== "" ? "Weather and night light's sunset/sunrise use " + Config.s.locationName
                            : "Not set: weather is hidden. Search for your town or city"
                        Rectangle {
                            width: 200; height: 30; radius: 8
                            color: Config.tint("#2a313c")
                            // Hover: a faint accent outline (solid while typing)
                            HoverHandler { id: placeInputHover; cursorShape: Qt.IBeamCursor }
                            border.width: placeInput.activeFocus || placeInputHover.hovered ? 1 : 0
                            border.color: placeInput.activeFocus ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.5)
                            TextInput {
                                id: placeInput
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: win.text; selectionColor: win.accent
                                font.family: win.font; font.pixelSize: 12
                                onAccepted: loc.search(text)
                                Keys.onEscapePressed: { text = ""; loc.results = []; loc.status = ""; focus = false; }
                            }
                            Text {
                                visible: placeInput.text === ""
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "Search, then Enter"
                                color: win.dim; font.family: win.font; font.pixelSize: 12
                            }
                        }
                    }
                    Text {
                        visible: loc.status !== ""
                        x: 16; bottomPadding: 12
                        text: loc.status
                        color: win.dim; font.family: win.font; font.pixelSize: 12
                    }
                    Flow {
                        visible: loc.results.length > 0
                        width: parent.width - 32; x: 16
                        spacing: 6
                        bottomPadding: 14
                        Repeater {
                            model: loc.results
                            delegate: Rectangle {
                                required property var modelData
                                readonly property string place: [modelData.name, modelData.admin1, modelData.country].filter(x => x).join(", ")
                                width: placeText.implicitWidth + 26; height: 32; radius: 8
                                color: placeHover.hovered ? Config.hoverOn(Config.tint("#2a313c")) : Config.tint("#2a313c")
                                Gloss { radius: parent.radius; opacity: (placeHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                Text { id: placeText; anchors.centerIn: parent; text: parent.place; color: win.text; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                HoverHandler { id: placeHover }
                                TapHandler {
                                    onTapped: {
                                        Config.s.latitude = parent.modelData.latitude;
                                        Config.s.longitude = parent.modelData.longitude;
                                        Config.s.locationName = parent.modelData.name;
                                        loc.results = []; placeInput.text = ""; placeInput.focus = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            GroupLabel { text: "Night light" }
            Group {
                SettingRow {
                    label: "Night light"
                    detail: "Warmer screen colours, easier on the eyes at night. Also in the control centre"
                    Toggle { checked: Config.s.nightLight; onToggled: v => Config.s.nightLight = v }
                }
                Separator {}
                SettingRow {
                    label: "Warmth"
                    detail: "Colour temperature: lower is warmer"
                    ValueSlider { from: 2500; to: 6000; stepSize: 100; suffix: " K"; value: Config.s.nightLightTemperature; onMoved: v => Config.s.nightLightTemperature = v }
                }
                Separator {}
                ChoiceSetting {
                    label: "Schedule"
                    detail: {
                        if (Config.s.nightLightSchedule === "sun") {
                            if (Config.s.locationName === "") return "Set your location above first";
                            const st = Config.sunTimes(new Date());
                            return "Today: on at " + Config.clockText(st.set) + ", off at " + Config.clockText(st.rise) + ". Switching by hand lasts until the next change";
                        }
                        if (Config.s.nightLightSchedule === "custom") return "Switching by hand lasts until the next change";
                        return "Only when you switch it";
                    }
                    value: Config.s.nightLightSchedule
                    options: [{ value: "manual", label: "Manual" }, { value: "sun", label: "Sunset to sunrise" }, { value: "custom", label: "Custom times" }]
                    onPicked: v => Config.s.nightLightSchedule = v
                }
                Separator { visible: Config.s.nightLightSchedule === "custom" }
                ChoiceSetting {
                    visible: Config.s.nightLightSchedule === "custom"
                    label: "Turn on at"
                    value: Config.s.nightLightFrom
                    options: [{ value: "16:00", label: "16:00" }, { value: "16:30", label: "16:30" }, { value: "17:00", label: "17:00" }, { value: "17:30", label: "17:30" }, { value: "18:00", label: "18:00" }, { value: "18:30", label: "18:30" }, { value: "19:00", label: "19:00" }, { value: "19:30", label: "19:30" }, { value: "20:00", label: "20:00" }, { value: "20:30", label: "20:30" }, { value: "21:00", label: "21:00" }, { value: "21:30", label: "21:30" }, { value: "22:00", label: "22:00" }, { value: "22:30", label: "22:30" }, { value: "23:00", label: "23:00" }, { value: "23:30", label: "23:30" }]
                    onPicked: v => Config.s.nightLightFrom = v
                }
                Separator { visible: Config.s.nightLightSchedule === "custom" }
                ChoiceSetting {
                    visible: Config.s.nightLightSchedule === "custom"
                    label: "Turn off at"
                    value: Config.s.nightLightTo
                    options: [{ value: "04:00", label: "04:00" }, { value: "04:30", label: "04:30" }, { value: "05:00", label: "05:00" }, { value: "05:30", label: "05:30" }, { value: "06:00", label: "06:00" }, { value: "06:30", label: "06:30" }, { value: "07:00", label: "07:00" }, { value: "07:30", label: "07:30" }, { value: "08:00", label: "08:00" }, { value: "08:30", label: "08:30" }, { value: "09:00", label: "09:00" }, { value: "09:30", label: "09:30" }, { value: "10:00", label: "10:00" }, { value: "10:30", label: "10:30" }]
                    onPicked: v => Config.s.nightLightTo = v
                }
            }
        }
    }

    Component {
        id: barPage
        Column {
            spacing: 4
            PageTitle { text: "Menu bar" }
            Group {
                SettingRow {
                    label: "Position"
                    detail: "Click an edge. The dock is at the " + Config.s.dockPosition + "; if you pick its edge, it moves to the opposite one. On the left or right, the status icons drop their text and the window title turns to run along the bar"
                    EdgePicker { accent: win.accent; bar: true; edge: Config.s.barPosition; onPicked: e => Config.moveBar(e) }
                }
                Separator {}
                SettingRow {
                    label: "Auto-hide"
                    detail: "Slide the bar away when a single window fills the screen; it comes back on workspace switches and at the top edge"
                    Toggle { checked: Config.s.barAutoHide; onToggled: v => Config.s.barAutoHide = v }
                }
                Separator {}
                SettingRow {
                    label: "Hover descriptions"
                    detail: "Show what you're pointing at on the bar in place of the window title"
                    Toggle { checked: Config.s.barHoverDescriptions; onToggled: v => Config.s.barHoverDescriptions = v }
                }
            }
            GroupLabel { text: "Left side" }
            Group {
                SettingRow {
                    label: "Apps button"
                    detail: "Opens the app launcher (also Super or Super+Space)"
                    Toggle { checked: Config.s.barShowApps; onToggled: v => Config.s.barShowApps = v }
                }
                Separator {}
                SettingRow {
                    label: "Workspaces"
                    detail: "A dot for each workspace; the highlighted one is where you are"
                    Toggle { checked: Config.s.barShowWorkspaces; onToggled: v => Config.s.barShowWorkspaces = v }
                }
                Separator {}
                SettingRow {
                    label: "Window title"
                    detail: "The focused app's icon and title"
                    Toggle { checked: Config.s.barShowTitle; onToggled: v => Config.s.barShowTitle = v }
                }
                Separator { visible: Config.s.barShowTitle }
                SettingRow {
                    visible: Config.s.barShowTitle
                    label: "App icon"
                    detail: "The focused app's icon before its title"
                    Toggle { checked: Config.s.barShowTitleIcon; onToggled: v => Config.s.barShowTitleIcon = v }
                }
            }
            GroupLabel { text: "Right side" }
            Group {
                SettingRow {
                    label: "App icons (tray)"
                    detail: "Icons that background apps put in the bar"
                    Toggle { checked: Config.s.barShowTray; onToggled: v => Config.s.barShowTray = v }
                }
                Separator { visible: Config.s.barShowTray }
                SettingRow {
                    visible: Config.s.barShowTray
                    label: "Tuck the tray away"
                    detail: "Show one button that opens to reveal the tray icons, and closes again after a few seconds"
                    Toggle { checked: Config.s.barTrayCollapsed; onToggled: v => Config.s.barTrayCollapsed = v }
                }
                Separator {}
                SettingRow {
                    label: "Notifications"
                    detail: "Bell with the number of unread notifications"
                    Toggle { checked: Config.s.barShowNotifications; onToggled: v => Config.s.barShowNotifications = v }
                }
                Separator {}
                SettingRow {
                    label: "Clipboard"
                    detail: "What you've copied recently; click to copy something again"
                    Toggle { checked: Config.s.barShowClipboard; onToggled: v => Config.s.barShowClipboard = v }
                }
                Separator {}
                SettingRow {
                    label: "Screenshot"
                    detail: "Click to take one of an area, a window or the screen"
                    Toggle { checked: Config.s.barShowScreenshot; onToggled: v => Config.s.barShowScreenshot = v }
                }
                Separator {}
                SettingRow {
                    label: "Wi-Fi"
                    detail: "Signal strength; click for networks"
                    Toggle { checked: Config.s.barShowWifi; onToggled: v => Config.s.barShowWifi = v }
                }
                Separator {}
                SettingRow {
                    label: "Keyboard layout"
                    detail: Config.kbLayoutList.length > 1 ? "The layout in use; click to switch, scroll to cycle"
                        : "Shows once you have more than one layout (Keyboard & mouse settings)"
                    Toggle { checked: Config.s.barShowKeyboard; onToggled: v => Config.s.barShowKeyboard = v }
                }
                Separator {}
                SettingRow {
                    label: "Bluetooth"
                    detail: "Turn it on or off and connect devices; click for the panel"
                    Toggle { checked: Config.s.barShowBluetooth; onToggled: v => Config.s.barShowBluetooth = v }
                }
                Separator {}
                SettingRow {
                    label: "Volume"
                    detail: "Click for output and input devices; scroll to change"
                    Toggle { checked: Config.s.barShowVolume; onToggled: v => Config.s.barShowVolume = v }
                }
                Separator {}
                SettingRow {
                    label: "Battery"
                    detail: "Charge level; click for power profiles. Hidden on computers without a battery"
                    Toggle { checked: Config.s.barShowBattery; onToggled: v => Config.s.barShowBattery = v }
                }
                Separator {}
                SettingRow {
                    label: "Clipboard items"
                    detail: "How many items the clipboard history holds, beside its icon"
                    Toggle { checked: Config.s.barValueClipboard; onToggled: v => Config.s.barValueClipboard = v }
                }
                Separator {}
                SettingRow {
                    label: "Wi-Fi network name"
                    detail: "Beside the Wi-Fi icon"
                    Toggle { checked: Config.s.barValueWifi; onToggled: v => Config.s.barValueWifi = v }
                }
                Separator {}
                SettingRow {
                    label: "Keyboard layout code"
                    detail: "The layout in use (GB, FR…) beside the keyboard icon"
                    Toggle { checked: Config.s.barValueKeyboard; onToggled: v => Config.s.barValueKeyboard = v }
                }
                Separator {}
                SettingRow {
                    label: "Connected Bluetooth devices"
                    detail: "How many, beside the Bluetooth icon"
                    Toggle { checked: Config.s.barValueBluetooth; onToggled: v => Config.s.barValueBluetooth = v }
                }
                Separator {}
                SettingRow {
                    label: "Volume percentage"
                    detail: "Beside the volume icon"
                    Toggle { checked: Config.s.barValueVolume; onToggled: v => Config.s.barValueVolume = v }
                }
                Separator {}
                SettingRow {
                    label: "Battery percentage"
                    detail: "Beside the battery icon"
                    Toggle { checked: Config.s.barValueBattery; onToggled: v => Config.s.barValueBattery = v }
                }
                Separator {}
                SettingRow {
                    label: "Power button"
                    detail: "Lock, suspend, log out, restart and shut down"
                    Toggle { checked: Config.s.barShowPower; onToggled: v => Config.s.barShowPower = v }
                }
            }
            GroupLabel { text: "Clock" }
            Group {
                DropdownSetting {
                    label: "Time format"
                    options: [{ value: "12h", label: "12-hour (6:30 PM)" }, { value: "24h", label: "24-hour (18:30)" }]
                    value: Config.s.barClockFormat
                    onPicked: v => Config.s.barClockFormat = v
                }
                Separator {}
                SettingRow {
                    label: "Show seconds"
                    detail: ""
                    Toggle { checked: Config.s.barClockSeconds; onToggled: v => Config.s.barClockSeconds = v }
                }
                Separator {}
                SettingRow {
                    label: "Show the date"
                    detail: "Day and date before the time, e.g. Sat 7 Nov. Click the clock for a calendar"
                    Toggle { checked: Config.s.barClockDate; onToggled: v => Config.s.barClockDate = v }
                }
            }
        }
    }

    Component {
        id: dockPage
        Column {
            spacing: 4
            PageTitle { text: "Dock" }
            Group {
                SettingRow {
                    label: "Position"
                    detail: "Click an edge. The menu bar is at the " + Config.s.barPosition + "; if you pick its edge, it moves to the opposite one"
                    EdgePicker { accent: win.accent; bar: false; edge: Config.s.dockPosition; onPicked: e => Config.moveDock(e) }
                }
                Separator {}
                SettingRow {
                    label: "Auto-hide"
                    detail: "Hide the dock while the workspace has windows; push the pointer to the bottom edge to show it"
                    Toggle { checked: Config.s.dockAutoHide; onToggled: v => Config.s.dockAutoHide = v }
                }
            }
            GroupLabel { text: "Icons" }
            Group {
                SettingRow {
                    label: "Icon size"
                    ValueSlider { from: 28; to: 64; stepSize: 1; suffix: " px"; value: Config.s.dockIconSize; onMoved: v => Config.s.dockIconSize = v }
                }
                Separator {}
                SettingRow {
                    label: "Magnification"
                    detail: "How large the icon under the pointer grows"
                    ValueSlider { from: 1; to: 2.5; stepSize: 0.05; decimals: 2; suffix: "×"; value: Config.s.dockMagnification; onMoved: v => Config.s.dockMagnification = v }
                }
                Separator {}
                SettingRow {
                    label: "Magnification spread"
                    detail: "How many neighbouring icons rise in the arc"
                    ValueSlider { from: 1; to: 5; stepSize: 0.5; decimals: 1; value: Config.s.dockSpread; onMoved: v => Config.s.dockSpread = v }
                }
            }
        }
    }

    Component {
        id: spacesPage
        Column {
            spacing: 4
            PageTitle { text: "Spaces" }
            Text {
                width: Math.min(parent.width, win.introMeasure)
                text: "Save the apps on some workspaces, and where their windows sit, as a space; then bring them all back on new workspaces in one click from the Spaces button on the menu bar."
                color: win.dim; font.family: win.font; font.pixelSize: 13
                wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
            }
            GroupLabel { text: "Menu bar" }
            Group {
                SettingRow {
                    label: "Spaces button"
                    detail: "Between Apps and the workspaces: your spaces, and New Space"
                    Toggle { checked: Config.s.barShowSpaces; onToggled: v => Config.s.barShowSpaces = v }
                }
                Separator {}
                SettingRow {
                    label: "Colour the window's icon"
                    detail: "When the focused window came from a space, its icon on the menu bar sits on the space's colour"
                    Toggle { checked: Config.s.spaceBarTint; onToggled: v => Config.s.spaceBarTint = v }
                }
            }
            GroupLabel { text: "Windows from a space" }
            Group {
                SettingRow {
                    label: "Top border"
                    detail: "A thin line in the space's colour along the top of each window"
                    Toggle { checked: Config.s.spaceBorders; onToggled: v => Config.s.spaceBorders = v }
                }
                Separator {}
                SettingRow {
                    label: "Corner badge"
                    detail: "The space's icon in the window's top left corner; it moves to the other corner when the pointer comes near"
                    Toggle { checked: Config.s.spaceBadges; onToggled: v => Config.s.spaceBadges = v }
                }
                Separator {}
                SettingRow {
                    label: "Badges in the switchers"
                    detail: "The space's icon on its windows in the window switcher (Super+Tab) and the workspace overview (Super+Down)"
                    Toggle { checked: Config.s.spaceSwitcherBadges; onToggled: v => Config.s.spaceSwitcherBadges = v }
                }
            }
        }
    }

    Component {
        id: screensaverPage
        Column {
            id: ssCol
            spacing: 4
            readonly property var minutes: [0, 1, 2, 3, 5, 10, 15, 20, 30].map(m => ({ value: m, label: m === 0 ? "Never" : m + (m === 1 ? " minute" : " minutes") }))
            PageTitle { text: "Screensaver" }
            Text {
                width: Math.min(parent.width, win.introMeasure)
                text: "Covers the screen while you're away, before the lock and screen-off times in Lock & idle. Any key, click or move of the pointer puts it away."
                color: win.dim; font.family: win.font; font.pixelSize: 13
                wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
            }
            Group {
                DropdownSetting {
                    label: "Start after"
                    detail: Config.s.idleLockMinutes > 0 && Config.s.screensaverMinutes >= Config.s.idleLockMinutes
                        ? "The screen locks at " + Config.s.idleLockMinutes + " minutes (Lock & idle), so it won't show"
                        : "Of no input. Video and apps that keep the screen awake hold it off"
                    options: ssCol.minutes
                    value: Config.s.screensaverMinutes
                    onPicked: v => Config.s.screensaverMinutes = v
                }
                Separator {}
                DropdownSetting {
                    label: "Style"
                    options: [{ value: "drift", label: "Clock on your wallpaper" },
                              { value: "slideshow", label: "Wallpaper slideshow" },
                              { value: "black", label: "Clock on black" }]
                    value: Config.s.screensaverStyle
                    onPicked: v => Config.s.screensaverStyle = v
                    detail: Config.s.screensaverStyle === "drift" ? "Your wallpaper, dimmed and slowly drifting"
                        : Config.s.screensaverStyle === "slideshow" ? "The pictures in your wallpaper folder, fading from one to the next"
                        : "Moves now and then so nothing burns in; best for OLED screens"
                }
                Separator { visible: Config.s.screensaverStyle !== "black" }
                SettingRow {
                    visible: Config.s.screensaverStyle !== "black"
                    label: "Show the clock"
                    detail: "The time and date in the middle"
                    Toggle { checked: Config.s.screensaverClock; onToggled: v => Config.s.screensaverClock = v }
                }
                Separator { visible: Config.s.screensaverStyle === "slideshow" }
                DropdownSetting {
                    visible: Config.s.screensaverStyle === "slideshow"
                    label: "Change picture every"
                    options: [10, 20, 30, 60, 120, 300].map(s => ({ value: s, label: s < 60 ? s + " seconds" : (s / 60) + (s === 60 ? " minute" : " minutes") }))
                    value: Config.s.screensaverSlideSeconds
                    onPicked: v => Config.s.screensaverSlideSeconds = v
                }
                Separator {}
                SettingRow {
                    label: "Lock on wake"
                    detail: "Waking it shows the lock screen, so you need your password to get back in"
                    Toggle { checked: Config.s.screensaverLock; onToggled: v => Config.s.screensaverLock = v }
                }
                Separator {}
                SettingRow {
                    label: "Preview"
                    detail: "Shows it now; any key, click or pointer move puts it away (it doesn't lock)"
                    Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "screensaver", "start"]); } }
                }
            }
        }
    }

    Component {
        id: launcherPage
        Column {
            spacing: 4
            PageTitle { text: "Launcher" }
            Group {
                SettingRow {
                    label: "Layout"
                    detail: Config.s.launcherLayout === "grid"
                        ? "Apps as a grid of icons, with the selected one's name along the bottom. Arrow keys move around it; Ctrl+Left/Right opens an app on a new workspace beside this one"
                        : "Apps in a list, with descriptions. Left/Right opens an app on a new workspace beside this one"
                    // Two-way switch: List | Grid
                    Rectangle {
                        readonly property var modes: ["list", "grid"]
                        width: 184; height: 34; radius: 9
                        color: Config.tint("#151920")
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.s.launcherLayout)) * 92
                            color: win.accent
                            Gloss { radius: parent.radius }   // glass: a sheen on the chosen side
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: [{ mode: "list", label: "List", icon: 0xEC14 }, { mode: "grid", label: "Grid", icon: 0xEDBA }]
                                delegate: Item {
                                    id: layoutOpt
                                    required property var modelData
                                    readonly property bool on: Config.s.launcherLayout === modelData.mode
                                    width: 92; height: 34
                                    Rectangle {
                                        anchors { fill: parent; margins: 3 }
                                        radius: 7
                                        color: win.accent
                                        opacity: !layoutOpt.on && layoutHover.hovered ? Config.hoverStrength : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    HoverHandler { id: layoutHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.glyph(layoutOpt.modelData.icon); color: layoutOpt.on ? win.accentText : win.dim; font.family: win.bar.iconFont; font.pixelSize: 15 }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: layoutOpt.modelData.label; color: layoutOpt.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    TapHandler { onTapped: Config.s.launcherLayout = layoutOpt.modelData.mode }
                                }
                            }
                        }
                    }
                }
                Separator { visible: Config.s.launcherLayout === "grid" }
                SettingRow {
                    visible: Config.s.launcherLayout === "grid"
                    label: "Columns"
                    detail: "Apps across the grid; the icons get smaller the more there are"
                    ValueSlider { from: 3; to: 10; stepSize: 1; value: Config.s.launcherColumns; onMoved: v => Config.s.launcherColumns = Math.round(v) }
                }
                Separator { visible: Config.s.launcherLayout === "grid" }
                SettingRow {
                    visible: Config.s.launcherLayout === "grid"
                    label: "Rows"
                    detail: "Rows shown at once, which sets the launcher's height (scroll for more)"
                    ValueSlider { from: 2; to: 8; stepSize: 1; value: Config.s.launcherRows; onMoved: v => Config.s.launcherRows = Math.round(v) }
                }
                Separator {}
                SettingRow {
                    label: "Show descriptions"
                    detail: Config.s.launcherLayout === "grid" ? "What the selected app is, under its name at the bottom" : "A short line under each app's name"
                    Toggle { checked: Config.s.launcherDescriptions; onToggled: v => Config.s.launcherDescriptions = v }
                }
                Separator {}
                SettingRow {
                    label: "Most used first"
                    detail: "Order apps by how often you open them (after how well they match your search)"
                    Toggle { checked: Config.s.launcherSortByUsage; onToggled: v => Config.s.launcherSortByUsage = v }
                }
            }
        }
    }

    Component {
        id: displaysPage
        Column {
            id: dp
            spacing: 4
            PageTitle { text: "Displays" }
            Displays { id: disp }
            // The monitor being set up below the arrangement (Hyprland's name, e.g. DP-1)
            property string selected: ""
            readonly property var mon: disp.monitors.find(m => m.name === selected) || disp.monitors[0] || null
            readonly property var cfg: mon ? disp.configOf(mon) : null
            readonly property int enabledCount: disp.monitors.filter(m => !m.disabled).length

            // Change one thing about the selected monitor, and apply it
            function change(field, value) {
                if (!mon) return;
                const all = disp.currentConfigs();
                const old = Object.assign({}, all[mon.name]);
                const c = all[mon.name];
                c[field] = value;
                // A new resolution may not suit the scale: take the nearest one that does
                if (field === "mode") {
                    const ok = disp.scaleOptions(c.mode, -1);
                    if (!ok.some(o => Math.abs(o.value - c.scale) < 0.001))
                        c.scale = ok.reduce((a, b) => Math.abs(b.value - c.scale) < Math.abs(a.value - c.scale) ? b : a, ok[0]).value;
                }
                disp.apply(disp.reflow(all, mon.name, old));
            }

            // Keep or go back (changes revert by themselves if not kept)
            Rectangle {
                visible: disp.pending
                width: parent.width
                height: keepRow.implicitHeight + 24
                radius: 12
                color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
                border.width: 1; border.color: win.accent
                Row {
                    id: keepRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                    spacing: 12
                    Text {
                        width: parent.width - revertBtn.width - keepBtn.width - 24
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Keep these display settings? Going back in " + disp.secondsLeft + " s"
                        color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                        wrapMode: Text.Wrap
                    }
                    Button { id: revertBtn; label: "Go back"; anchors.verticalCenter: parent.verticalCenter; onClicked: disp.revert() }
                    Button { id: keepBtn; label: "Keep"; primary: true; anchors.verticalCenter: parent.verticalCenter; onClicked: disp.keep() }
                }
            }

            // ---- Arrangement: the monitors to scale; drag one beside another --------------
            GroupLabel { text: disp.monitors.length > 1 ? "Arrangement (drag to move, click to choose)" : "Display" }
            Group {
                Item {
                    id: arrange
                    width: parent.width; height: 200
                    readonly property var live: disp.monitors.filter(m => !m.disabled)
                    // Fit the layout into the box
                    readonly property var box: {
                        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                        for (const m of live) {
                            const c = disp.configOf(m), sz = disp.logicalSize(c);
                            x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y);
                            x1 = Math.max(x1, c.x + sz.w); y1 = Math.max(y1, c.y + sz.h);
                        }
                        if (!isFinite(x0)) return { x0: 0, y0: 0, k: 1, ox: 0, oy: 0 };
                        const k = Math.min((width - 48) / (x1 - x0), (height - 40) / (y1 - y0));
                        return { x0: x0, y0: y0, k: k, ox: (width - (x1 - x0) * k) / 2, oy: (height - (y1 - y0) * k) / 2 };
                    }
                    Repeater {
                        model: arrange.live
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            readonly property var c: disp.configOf(modelData)
                            readonly property var sz: disp.logicalSize(c)
                            readonly property bool chosen: dp.mon && dp.mon.name === modelData.name
                            readonly property real homeX: arrange.box.ox + (c.x - arrange.box.x0) * arrange.box.k
                            readonly property real homeY: arrange.box.oy + (c.y - arrange.box.y0) * arrange.box.k
                            x: homeX; y: homeY
                            width: Math.max(24, sz.w * arrange.box.k - 4); height: Math.max(18, sz.h * arrange.box.k - 4)
                            radius: 6
                            color: chosen ? win.accent : Config.tint("#2a313c")
                            border.width: 1; border.color: chosen ? win.accent : Config.tint("#3a424e")
                            z: drag.active ? 2 : 1
                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.name
                                    color: tile.chosen ? win.accentText : win.text
                                    font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: Config.primaryScreen && Config.primaryScreen.name === tile.modelData.name && disp.monitors.length > 1
                                    text: "Main"
                                    color: tile.chosen ? win.accentText : win.dim
                                    font.family: win.font; font.pixelSize: 11
                                }
                            }
                            HoverHandler { cursorShape: arrange.live.length > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor }
                            TapHandler { onTapped: dp.selected = tile.modelData.name }
                            DragHandler {
                                id: drag
                                enabled: arrange.live.length > 1
                                onActiveChanged: {
                                    if (active) { dp.selected = tile.modelData.name; return; }
                                    // Dropped: from the box back to the layout, then snap beside the nearest
                                    const lx = (tile.x - arrange.box.ox) / arrange.box.k + arrange.box.x0;
                                    const ly = (tile.y - arrange.box.oy) / arrange.box.k + arrange.box.y0;
                                    tile.x = Qt.binding(() => tile.homeX);
                                    tile.y = Qt.binding(() => tile.homeY);
                                    const all = disp.currentConfigs();
                                    const before = JSON.stringify(all);
                                    const placed = disp.placeBeside(all, tile.modelData.name, lx, ly);
                                    if (JSON.stringify(placed) !== before) disp.apply(placed);
                                }
                            }
                        }
                    }
                }
            }

            // ---- The chosen monitor -----------------------------------------------------
            GroupLabel { visible: !!dp.mon; text: dp.mon ? disp.displayName(dp.mon) + " (" + dp.mon.name + ")" : "" }
            Group {
                visible: !!dp.mon
                SettingRow {
                    visible: disp.monitors.length > 1
                    label: "Use this display"
                    detail: dp.cfg && !dp.cfg.disabled && dp.enabledCount <= 1 ? "The only display in use can't be turned off" : "Turn it off to leave it dark and unused"
                    Toggle {
                        checked: dp.cfg ? !dp.cfg.disabled : true
                        opacity: dp.cfg && !dp.cfg.disabled && dp.enabledCount <= 1 ? 0.4 : 1
                        onToggled: v => { if (v || dp.enabledCount > 1) dp.change("disabled", !v); }
                    }
                }
                Separator { visible: disp.monitors.length > 1 }
                DropdownSetting {
                    visible: dp.cfg && !dp.cfg.disabled
                    label: "Resolution"
                    detail: "Size and refresh rate"
                    options: dp.mon ? disp.modeOptions(dp.mon) : []
                    value: dp.cfg ? dp.cfg.mode : ""
                    onPicked: v => dp.change("mode", v)
                }
                Separator { visible: dp.cfg && !dp.cfg.disabled }
                DropdownSetting {
                    visible: dp.cfg && !dp.cfg.disabled
                    label: "Scale"
                    detail: "How large everything on this display looks, apps included. Only scales that suit the resolution are offered"
                    options: dp.cfg ? disp.scaleOptions(dp.cfg.mode, dp.cfg.scale) : []
                    value: dp.cfg ? dp.cfg.scale : 1
                    onPicked: v => dp.change("scale", v)
                }
                Separator { visible: dp.cfg && !dp.cfg.disabled }
                DropdownSetting {
                    visible: dp.cfg && !dp.cfg.disabled
                    label: "Rotation"
                    options: disp.transformOptions
                    value: dp.cfg ? dp.cfg.transform : 0
                    onPicked: v => dp.change("transform", v)
                }
                Separator { visible: disp.monitors.length > 1 }
                DropdownSetting {
                    visible: disp.monitors.length > 1
                    label: "Main display"
                    detail: "Where the main menu bar lives (every display has a bar; the launcher and other panels open on the display you're using)"
                    options: disp.monitors.filter(m => !m.disabled).map(m => ({ value: m.description || m.name, label: m.name + " · " + disp.displayName(m) }))
                    value: {
                        const p = Config.primaryScreen;
                        const m = p ? disp.monitors.find(x => x.name === p.name) : null;
                        return m ? (m.description || m.name) : "";
                    }
                    onPicked: v => Config.s.mainDisplay = v
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "Slate's own size (bar, panels, this window) is under Appearance → Interface size, on top of each display's scale. Monitor rules in ~/.config/slate/hypr/hyprland.lua override these."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    // ---- Keyboard & mouse ----------------------------------------------------
    // Only what's changed here is set (Config.hyprSettings); the rest shows what Hyprland's
    // config (and your own hyprland.lua) has, read when the page opens
    Component {
        id: inputPage
        Column {
            id: ip
            spacing: 4
            PageTitle { text: "Keyboard & mouse" }
            property var cur: ({})
            property var layoutOptions: []
            property bool hasTouchpad: false
            Process {
                running: true
                command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:kb_layout", "input:kb_variant", "input:kb_options",
                    "input:repeat_rate", "input:repeat_delay", "input:sensitivity", "input:accel_profile", "input:natural_scroll",
                    "input:touchpad:natural_scroll", "input:touchpad:tap-to-click", "input:touchpad:disable_while_typing",
                    "input:touchpad:scroll_factor"]
                stdout: StdioCollector { onStreamFinished: { try { ip.cur = JSON.parse(text); } catch (e) {} } }
            }
            Process {
                running: true
                command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
                stdout: StdioCollector { onStreamFinished: { try { ip.layoutOptions = JSON.parse(text); } catch (e) {} } }
            }
            Process {
                running: true
                command: ["hyprctl", "devices", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { ip.hasTouchpad = JSON.parse(text).mice.some(m => m.name.toLowerCase().includes("touchpad")); } catch (e) {} } }
            }

            // Keyboard layouts in use, in order: [{ layout, variant }]
            readonly property var layouts: {
                const set = Config.s.kbLayouts !== "";
                const ls = (set ? Config.s.kbLayouts : (cur["input:kb_layout"] || "us")).split(",");
                const vs = (set ? Config.s.kbVariants : (cur["input:kb_variant"] || "")).split(",");
                return ls.map(l => l.trim()).filter(l => l !== "").map((l, i) => ({ layout: l, variant: (vs[i] || "").trim() }));
            }
            function setLayouts(list) {
                Config.s.kbVariants = list.map(x => x.variant).join(",");
                Config.s.kbLayouts = list.map(x => x.layout).join(",");
            }
            function layoutName(x) {
                const key = x.variant ? x.layout + ":" + x.variant : x.layout;
                const o = layoutOptions.find(o => o.value === key);
                return o ? o.label : key;
            }
            readonly property string curOptions: cur["input:kb_options"] || ""
            readonly property string capsValue: Config.s.capsLock !== "" ? Config.s.capsLock
                : curOptions.includes("caps:ctrl_modifier") ? "ctrl" : curOptions.includes("caps:escape") ? "escape"
                : curOptions.includes("caps:none") ? "off" : "default"
            readonly property string switchValue: Config.s.kbSwitch !== "" ? Config.s.kbSwitch
                : curOptions.includes("grp:alt_shift_toggle") ? "alt_shift" : curOptions.includes("grp:ctrl_space_toggle") ? "ctrl_space"
                : curOptions.includes("grp:caps_toggle") ? "caps" : "none"

            GroupLabel { text: "Keyboard" }
            Group {
                Repeater {
                    model: ip.layouts
                    delegate: Column {
                        id: layoutRow
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        Separator { visible: layoutRow.index > 0 }
                        ListItemRow {
                            label: ip.layoutName(layoutRow.modelData)
                            detail: ip.layouts.length > 1 && layoutRow.index === 0 ? "Used first" : ""
                            removable: ip.layouts.length > 1
                            onRemoved: { const l = ip.layouts.slice(); l.splice(layoutRow.index, 1); ip.setLayouts(l); }
                        }
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Add a layout"
                    detail: "Search by language or name, e.g. French or Dvorak"
                    buttonLabel: "Add…"
                    buttonIcon: 0xEB0B
                    options: ip.layoutOptions
                    onPicked: v => {
                        const parts = String(v).split(":");
                        const l = ip.layouts.slice();
                        if (!l.some(x => x.layout === parts[0] && x.variant === (parts[1] || "")))
                            l.push({ layout: parts[0], variant: parts[1] || "" });
                        ip.setLayouts(l);
                    }
                }
                Separator { visible: ip.layouts.length > 1 }
                DropdownSetting {
                    visible: ip.layouts.length > 1
                    label: "Switch layouts with"
                    options: [{ value: "alt_shift", label: "Alt+Shift" }, { value: "ctrl_space", label: "Ctrl+Space" },
                              { value: "caps", label: "Caps Lock" }, { value: "none", label: "No shortcut" }]
                    value: ip.switchValue
                    onPicked: v => Config.s.kbSwitch = v
                }
                Separator {}
                DropdownSetting {
                    label: "Caps Lock key"
                    detail: ip.switchValue === "caps" && ip.layouts.length > 1 ? "It switches layouts (above)" : "What the Caps Lock key does"
                    options: [{ value: "default", label: "Caps Lock" }, { value: "ctrl", label: "Another Ctrl" },
                              { value: "escape", label: "Escape" }, { value: "off", label: "Nothing" }]
                    value: ip.capsValue
                    onPicked: v => Config.s.capsLock = v
                }
                Separator {}
                SettingRow {
                    label: "Repeat delay"
                    detail: "How long a held key waits before it repeats"
                    ValueSlider {
                        from: 150; to: 1000; stepSize: 25; suffix: " ms"
                        value: Config.s.keyRepeatDelay > 0 ? Config.s.keyRepeatDelay : (ip.cur["input:repeat_delay"] || 600)
                        onMoved: v => Config.s.keyRepeatDelay = Math.round(v)
                    }
                }
                Separator {}
                SettingRow {
                    label: "Repeat speed"
                    detail: "How fast a held key repeats"
                    ValueSlider {
                        from: 10; to: 80; stepSize: 1; suffix: " /s"
                        value: Config.s.keyRepeatRate > 0 ? Config.s.keyRepeatRate : (ip.cur["input:repeat_rate"] || 25)
                        onMoved: v => Config.s.keyRepeatRate = Math.round(v)
                    }
                }
            }

            GroupLabel { text: "Mouse" }
            Group {
                SettingRow {
                    label: "Pointer speed"
                    detail: "Slower to faster; 0 is the mouse's own speed"
                    ValueSlider {
                        from: -100; to: 100; stepSize: 5
                        value: Math.round((Config.s.mouseSpeed >= -1 ? Config.s.mouseSpeed : (ip.cur["input:sensitivity"] || 0)) * 100)
                        onMoved: v => Config.s.mouseSpeed = v / 100
                    }
                }
                Separator {}
                SettingRow {
                    label: "Acceleration"
                    detail: "Quick movements carry the pointer further. Off: the same distance however fast you move"
                    Toggle {
                        checked: (Config.s.mouseAccel !== "" ? Config.s.mouseAccel : (ip.cur["input:accel_profile"] || "adaptive")) !== "flat"
                        onToggled: v => Config.s.mouseAccel = v ? "adaptive" : "flat"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Natural scrolling"
                    detail: "Content moves the way the wheel turns, like a touch screen"
                    Toggle {
                        checked: Config.s.mouseNaturalScroll !== "" ? Config.s.mouseNaturalScroll === "on" : !!ip.cur["input:natural_scroll"]
                        onToggled: v => Config.s.mouseNaturalScroll = v ? "on" : "off"
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Pointer size"
                    detail: "Apps opened from now on use it too"
                    options: [16, 20, 24, 32, 40, 48, 64].map(n => ({ value: n, label: n + " px" }))
                    value: Config.s.cursorSize > 0 ? Config.s.cursorSize : 20
                    onPicked: v => Config.s.cursorSize = v
                }
            }

            GroupLabel { visible: ip.hasTouchpad; text: "Touchpad" }
            Group {
                visible: ip.hasTouchpad
                SettingRow {
                    label: "Speed"
                    detail: Config.s.touchpadSpeed >= -1 ? "Slower to faster" : "Slower to faster (your own config may set the touchpad separately until it's changed here)"
                    ValueSlider {
                        from: -100; to: 100; stepSize: 5
                        value: Math.round((Config.s.touchpadSpeed >= -1 ? Config.s.touchpadSpeed : (ip.cur["input:sensitivity"] || 0)) * 100)
                        onMoved: v => Config.s.touchpadSpeed = v / 100
                    }
                }
                Separator {}
                SettingRow {
                    label: "Scroll speed"
                    ValueSlider {
                        from: 10; to: 200; stepSize: 10; suffix: "%"
                        value: Math.round((Config.s.touchpadScrollSpeed > 0 ? Config.s.touchpadScrollSpeed : (ip.cur["input:touchpad:scroll_factor"] || 1)) * 100)
                        onMoved: v => Config.s.touchpadScrollSpeed = v / 100
                    }
                }
                Separator {}
                SettingRow {
                    label: "Natural scrolling"
                    detail: "Content follows your fingers, like a phone"
                    Toggle {
                        checked: Config.s.touchpadNaturalScroll !== "" ? Config.s.touchpadNaturalScroll === "on" : !!ip.cur["input:touchpad:natural_scroll"]
                        onToggled: v => Config.s.touchpadNaturalScroll = v ? "on" : "off"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Tap to click"
                    Toggle {
                        checked: Config.s.touchpadTapToClick !== "" ? Config.s.touchpadTapToClick === "on" : ip.cur["input:touchpad:tap-to-click"] !== false
                        onToggled: v => Config.s.touchpadTapToClick = v ? "on" : "off"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Ignore while typing"
                    detail: "Stops a palm on the touchpad moving the pointer as you type"
                    Toggle {
                        checked: Config.s.touchpadIgnoreWhileTyping !== "" ? Config.s.touchpadIgnoreWhileTyping === "on" : ip.cur["input:touchpad:disable_while_typing"] !== false
                        onToggled: v => Config.s.touchpadIgnoreWhileTyping = v ? "on" : "off"
                    }
                }
            }
        }
    }

    // ---- Sound ------------------------------------------------------------------
    Component {
        id: soundPage
        Column {
            id: sndp
            spacing: 4
            PageTitle { text: "Sound" }
            readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
            readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property var source: Pipewire.defaultAudioSource
            PwObjectTracker { objects: [sndp.sink, sndp.source] }
            function nodeName(n) { return n ? (n.description || n.nickname || n.name) : ""; }

            GroupLabel { text: "Output" }
            Group {
                DropdownSetting {
                    label: "Play sound through"
                    options: sndp.sinks.map(n => ({ value: n.id, label: sndp.nodeName(n) }))
                    value: sndp.sink ? sndp.sink.id : -1
                    onPicked: v => { const n = sndp.sinks.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSink = n; }
                }
                Separator {}
                SettingRow {
                    label: "Volume"
                    ValueSlider {
                        from: 0; to: 100; stepSize: 1; suffix: "%"
                        value: sndp.sink && sndp.sink.audio ? Math.round(sndp.sink.audio.volume * 100) : 0
                        onMoved: v => { if (sndp.sink && sndp.sink.audio) sndp.sink.audio.volume = v / 100; }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Mute"
                    Toggle {
                        checked: !!(sndp.sink && sndp.sink.audio && sndp.sink.audio.muted)
                        onToggled: v => { if (sndp.sink && sndp.sink.audio) sndp.sink.audio.muted = v; }
                    }
                }
            }
            GroupLabel { text: "Input" }
            Group {
                DropdownSetting {
                    label: "Microphone"
                    options: sndp.sources.map(n => ({ value: n.id, label: sndp.nodeName(n) }))
                    value: sndp.source ? sndp.source.id : -1
                    onPicked: v => { const n = sndp.sources.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSource = n; }
                }
                Separator {}
                SettingRow {
                    label: "Input level"
                    ValueSlider {
                        from: 0; to: 100; stepSize: 1; suffix: "%"
                        value: sndp.source && sndp.source.audio ? Math.round(sndp.source.audio.volume * 100) : 0
                        onMoved: v => { if (sndp.source && sndp.source.audio) sndp.source.audio.volume = v / 100; }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Mute the microphone"
                    Toggle {
                        checked: !!(sndp.source && sndp.source.audio && sndp.source.audio.muted)
                        onToggled: v => { if (sndp.source && sndp.source.audio) sndp.source.audio.muted = v; }
                    }
                }
            }
            GroupLabel { text: "Sound effects" }
            Group {
                SettingRow {
                    label: "Volume key sound"
                    detail: "A short tick at the new volume when you press the volume keys"
                    Toggle { checked: Config.s.volumeSound; onToggled: v => Config.s.volumeSound = v }
                }
                Separator {}
                SettingRow {
                    label: "Sound effects volume"
                    detail: "How loud Slate's own sounds are"
                    ValueSlider { from: 0; to: 100; stepSize: 5; suffix: "%"; value: Config.s.soundEffectsVolume; onMoved: v => Config.s.soundEffectsVolume = Math.round(v) }
                }
            }
        }
    }

    // ---- Power ------------------------------------------------------------------
    Component {
        id: powerPage
        Column {
            id: pwp
            spacing: 4
            PageTitle { text: "Power" }
            property bool hasLid: false
            Process {
                running: true
                command: ["hyprctl", "devices", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { pwp.hasLid = (JSON.parse(text).switches || []).some(x => /lid/i.test(x.name)); } catch (e) {} } }
            }
            readonly property var profileOptions: [{ value: "", label: "Leave it as it is" }, { value: "power-saver", label: "Power saver" },
                { value: "balanced", label: "Balanced" }].concat(PowerProfiles.hasPerformanceProfile ? [{ value: "performance", label: "Performance" }] : [])

            GroupLabel { text: "Lid and power button" }
            Group {
                DropdownSetting {
                    visible: pwp.hasLid
                    label: "Closing the lid"
                    detail: Config.s.lidAction === "" ? "Left to the system (usually suspends)"
                        : "With another screen connected, only the laptop's own screen turns off"
                    options: [{ value: "", label: "System default" }, { value: "suspend", label: "Suspend" }, { value: "lock", label: "Lock the screen" },
                              { value: "screenoff", label: "Turn the screen off" }, { value: "nothing", label: "Do nothing" }]
                    value: Config.s.lidAction
                    onPicked: v => Config.s.lidAction = v
                }
                Separator { visible: pwp.hasLid }
                DropdownSetting {
                    label: "Power button"
                    detail: Config.s.powerKeyAction === "" ? "Left to the system (usually shuts down)" : ""
                    options: [{ value: "", label: "System default" }, { value: "menu", label: "Show the power menu" }, { value: "suspend", label: "Suspend" },
                              { value: "poweroff", label: "Shut down (asks first)" }, { value: "lock", label: "Lock the screen" }, { value: "nothing", label: "Do nothing" }]
                    value: Config.s.powerKeyAction
                    onPicked: v => Config.s.powerKeyAction = v
                }
            }
            GroupLabel { text: "Power mode" }
            Group {
                DropdownSetting {
                    label: "On battery"
                    detail: "Switched to when you unplug; the control centre can still change it any time"
                    options: pwp.profileOptions
                    value: Config.s.profileOnBattery
                    onPicked: v => { Config.s.profileOnBattery = v; Config.applyPowerProfile(); }
                }
                Separator {}
                DropdownSetting {
                    label: "Plugged in"
                    detail: "Switched to when you plug in"
                    options: pwp.profileOptions
                    value: Config.s.profileOnAC
                    onPicked: v => { Config.s.profileOnAC = v; Config.applyPowerProfile(); }
                }
            }
        }
    }

    // ---- Shortcuts: Slate's keyboard shortcuts, as Hyprland has them (with descriptions) ----
    Component {
        id: shortcutsPage
        Column {
            id: scp
            spacing: 4
            PageTitle { text: "Shortcuts" }
            property var binds: []
            Process {
                id: bindsProc
                running: true
                command: ["hyprctl", "binds", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { scp.binds = JSON.parse(text).filter(b => b.has_description && b.description && b.submap === ""); } catch (e) {} } }
            }
            // The keys, as caps: modifiers then the key
            function keysOf(b) {
                if (b.key === "SUPER_L") return ["Super"];
                const m = b.modmask, keys = [];
                if (m & 64) keys.push("Super");
                if (m & 4) keys.push("Ctrl");
                if (m & 8) keys.push("Alt");
                if (m & 1) keys.push("Shift");
                const names = { Return: "Enter", period: ".", Minus: "−", Plus: "+", Print: "Print Screen", Escape: "Esc",
                                Space: "Space", Tab: "Tab", Left: "←", Right: "→", Up: "↑", Down: "↓",
                                "mouse:272": "Drag", "mouse:273": "Right-drag", mouse_up: "Scroll up", mouse_down: "Scroll down" };
                let k = b.key || (b.keycode ? "code:" + b.keycode : "");
                const code = /^code:(\d+)$/.exec(k);
                if (code) k = String(+code[1] === 19 ? 0 : +code[1] - 9);
                else k = names[k] !== undefined ? names[k] : (k.length === 1 ? k.toUpperCase() : k);
                if (k) keys.push(k);
                return keys;
            }
            // A different set: read the shortcuts again once Hyprland has reloaded with it
            Connections {
                target: Config
                function onKeysetApplied() { bindsAgain.restart(); }
            }
            Timer { id: bindsAgain; interval: 500; onTriggered: { bindsProc.running = false; bindsProc.running = true; } }
            readonly property var order: ["Apps", "Slate", "Windows", "Workspaces", "Monitors"]
            readonly property var groups: {
                const q = findKeys.text.toLowerCase().trim();
                const g = {};
                for (const b of binds) {
                    const i = b.description.indexOf(": ");
                    const group = i > 0 ? b.description.slice(0, i) : "Other";
                    const text = i > 0 ? b.description.slice(i + 2) : b.description;
                    const keys = keysOf(b);
                    if (q && !(text + " " + keys.join(" ")).toLowerCase().includes(q)) continue;
                    if (!g[group]) g[group] = [];
                    if (!g[group].some(r => r.text === text && r.keys.join() === keys.join())) g[group].push({ text: text, keys: keys });
                }
                return Object.keys(g).sort((a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99)).map(k => ({ name: k, rows: g[k] }));
            }

            // Which set of shortcuts (binds.lua); changing it reloads Hyprland's config
            Group {
                DropdownSetting {
                    label: "Shortcut set"
                    options: [{ value: "slate", label: "Slate" },
                              { value: "hyprland", label: "Hyprland Defaults" },
                              { value: "hyprland-extras", label: "Hyprland + Slate Extras" }]
                    value: Config.s.keyset
                    onPicked: v => Config.setKeyset(v)
                    detail: Config.s.keyset === "hyprland" ? "Hyprland's own default shortcuts (Super+Q terminal, Super+C close, Super+R launcher, Super+1–0 workspaces)"
                        : Config.s.keyset === "hyprland-extras" ? "Hyprland's defaults, plus Slate's shortcuts where the keys are free (clipboard on Super+Shift+V, colour picker on Super+Shift+P, overview on Super+Ctrl+Down)"
                        : "Slate's own shortcuts (Super+Q close, Super+Space or tap Super for the launcher, Super+Tab to switch windows)"
                }
            }
            Item { width: 1; height: 6 }

            Rectangle {
                width: parent.width; height: 40; radius: 10
                color: win.card
                border.width: findKeys.activeFocus ? 1 : 0; border.color: win.accent
                Text {
                    id: keysGlass
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: win.glyph(0xEB1C); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
                }
                TextInput {
                    id: findKeys
                    anchors { left: keysGlass.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: win.text; font.family: win.font; font.pixelSize: 13; clip: true
                    selectionColor: win.accent; selectedTextColor: win.accentText
                    Text { visible: findKeys.text === ""; text: "Search shortcuts"; color: win.dim; font: findKeys.font; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Repeater {
                model: scp.groups
                delegate: Column {
                    id: keyGroup
                    required property var modelData
                    width: parent ? parent.width : 0
                    spacing: 4
                    GroupLabel { text: keyGroup.modelData.name }
                    Group {
                        Repeater {
                            model: keyGroup.modelData.rows
                            delegate: Column {
                                id: keyRow
                                required property var modelData
                                required property int index
                                width: parent ? parent.width : 0
                                Separator { visible: keyRow.index > 0 }
                                SettingRow {
                                    label: keyRow.modelData.text
                                    Row {
                                        spacing: 4
                                        Repeater {
                                            model: keyRow.modelData.keys
                                            delegate: Rectangle {
                                                required property string modelData
                                                width: Math.max(26, capText.implicitWidth + 14); height: 24; radius: 6
                                                color: Config.tint("#262c35")
                                                border.width: 1; border.color: Config.tint("#323a46")
                                                Text { id: capText; anchors.centerIn: parent; text: parent.modelData; color: win.text; font.family: win.font; font.pixelSize: 11; font.weight: Font.Medium }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "Add or change shortcuts in ~/.config/slate/hypr/hyprland.lua (with a description = \"Group: what it does\" to list them here)."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    // ---- Default apps: what Slate's shortcuts open (and links and folders, for the browser
    // and file manager) ----------------------------------------------------------------
    Component {
        id: appsPage
        Column {
            id: dap
            spacing: 4
            PageTitle { text: "Default apps" }
            readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
                .slice().sort((a, b) => a.name.localeCompare(b.name))
            // Apps of a kind (by their categories), or every app if none say so
            function optionsFor(cats) {
                const fit = all.filter(e => (e.categories || []).some(c => cats.includes(c)));
                return (fit.length > 0 ? fit : all).map(e => ({ value: e.id, label: e.name, detail: e.genericName || e.comment || "" }));
            }
            function nameOf(id) { const e = id ? DesktopEntries.byId(id) : null; return e ? e.name : ""; }
            Group {
                SearchPicker {
                    label: "Terminal"
                    detail: "Super+Enter"
                    buttonLabel: dap.nameOf(Config.s.defaultTerminal) || "Choose…"
                    options: dap.optionsFor(["TerminalEmulator"])
                    onPicked: v => Config.s.defaultTerminal = v
                }
                Separator {}
                SearchPicker {
                    label: "Web browser"
                    detail: "Links open in it"
                    buttonLabel: dap.nameOf(Config.s.defaultBrowser) || "Choose…"
                    options: dap.optionsFor(["WebBrowser"])
                    onPicked: v => {
                        Config.s.defaultBrowser = v;
                        Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", v + ".desktop"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Files"
                    detail: "Super+E, and folders open in it"
                    buttonLabel: dap.nameOf(Config.s.defaultFileManager) || "Choose…"
                    options: dap.optionsFor(["FileManager"])
                    onPicked: v => {
                        Config.s.defaultFileManager = v;
                        Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "inode/directory"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Text editor"
                    detail: "Super+T, and text files open in it"
                    buttonLabel: dap.nameOf(Config.s.defaultEditor) || "Choose…"
                    options: dap.optionsFor(["TextEditor"])
                    onPicked: v => {
                        Config.s.defaultEditor = v;
                        Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "text/plain"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Calculator"
                    detail: "Super+C and the calculator key"
                    buttonLabel: dap.nameOf(Config.s.defaultCalculator) || "Choose…"
                    options: dap.optionsFor(["Calculator"])
                    onPicked: v => Config.s.defaultCalculator = v
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "Ones not chosen here use those in ~/.config/slate/hypr/variables.lua (or Slate's own defaults)."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    // ---- Startup apps: opened at each login (Config.atLogin) ---------------------------------
    Component {
        id: startupPage
        Column {
            id: stp
            spacing: 4
            PageTitle { text: "Startup apps" }
            readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
                .slice().sort((a, b) => a.name.localeCompare(b.name))
            Group {
                SettingRow {
                    visible: (Config.s.startupApps || []).length === 0
                    label: "Nothing opens at login yet"
                    detail: "Add apps below and they'll open each time you log in"
                }
                Repeater {
                    model: Config.s.startupApps || []
                    delegate: Column {
                        id: startRow
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        Separator { visible: startRow.index > 0 }
                        ListItemRow {
                            readonly property var entry: DesktopEntries.byId(startRow.modelData)
                            label: entry ? entry.name : startRow.modelData
                            detail: entry ? (entry.genericName || entry.comment || "") : "Not installed"
                            onRemoved: { const l = (Config.s.startupApps || []).slice(); l.splice(startRow.index, 1); Config.s.startupApps = l; }
                        }
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Add an app"
                    detail: "It opens each time you log in"
                    buttonLabel: "Add…"
                    buttonIcon: 0xEB0B
                    options: stp.all.filter(e => !(Config.s.startupApps || []).includes(e.id))
                        .map(e => ({ value: e.id, label: e.name, detail: e.genericName || e.comment || "" }))
                    onPicked: v => Config.s.startupApps = (Config.s.startupApps || []).concat([v])
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "Apps started in ~/.config/slate/hypr/hyprland.lua still open too."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    // ---- Date & time (timedatectl; changing them may ask for your password) -----------------
    Component {
        id: timePage
        Column {
            id: dtp
            spacing: 4
            PageTitle { text: "Date & time" }
            property string zone: ""
            property bool ntp: false
            property bool canNtp: true
            property var zones: []
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: dtp.now = new Date() }
            function refresh() { stateProc.running = false; stateProc.running = true; }
            Timer { id: reread; interval: 1500; onTriggered: dtp.refresh() }
            Process {
                id: stateProc
                running: true
                command: ["timedatectl", "show", "-p", "Timezone", "-p", "NTP", "-p", "CanNTP"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        for (const line of text.split("\n")) {
                            const i = line.indexOf("="), k = line.slice(0, i), v = line.slice(i + 1);
                            if (k === "Timezone") dtp.zone = v;
                            else if (k === "NTP") dtp.ntp = v === "yes";
                            else if (k === "CanNTP") dtp.canNtp = v === "yes";
                        }
                    }
                }
            }
            Process {
                running: true
                command: ["timedatectl", "list-timezones"]
                stdout: StdioCollector { onStreamFinished: dtp.zones = text.trim().split("\n").filter(z => z !== "").map(z => ({ value: z, label: z.replace(/_/g, " ") })) }
            }
            Group {
                SettingRow {
                    label: Qt.formatDateTime(dtp.now, "dddd d MMMM yyyy")
                    detail: Qt.formatTime(dtp.now, "HH:mm:ss")
                }
                Separator {}
                SearchPicker {
                    label: "Time zone"
                    detail: dtp.zone.replace(/_/g, " ")
                    buttonLabel: "Change…"
                    options: dtp.zones
                    onPicked: v => { Quickshell.execDetached(["timedatectl", "set-timezone", v]); reread.restart(); }
                }
                Separator { visible: dtp.canNtp }
                SettingRow {
                    visible: dtp.canNtp
                    label: "Set the time automatically"
                    detail: "Keeps the clock right using a time server on the internet"
                    Toggle {
                        checked: dtp.ntp
                        onToggled: v => { dtp.ntp = v; Quickshell.execDetached(["timedatectl", "set-ntp", v ? "true" : "false"]); reread.restart(); }
                    }
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "How the clock looks is under Menu bar. Changing these may ask for your password."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    // ---- Screenshots (scripts/screenshot.sh reads these) ----------------------------------
    Component {
        id: shotsPage
        Column {
            id: shp
            spacing: 4
            PageTitle { text: "Screenshots" }
            property bool hasSwash: false
            Process { running: true; command: ["sh", "-c", "command -v swash"]; onExited: code => shp.hasSwash = code === 0 }
            readonly property string home: Quickshell.env("HOME")
            readonly property string folder: Config.s.screenshotFolder || (home + "/Pictures/Screenshots")
            readonly property date example: new Date()
            Group {
                DropdownSetting {
                    label: "After taking one"
                    detail: shp.hasSwash ? "Every screenshot is saved to the folder below and copied. Marking one up and saving updates that file"
                        : "Every screenshot is saved to the folder below and copied (swash, for marking up, isn't installed)"
                    options: [{ value: "edit", label: "Open it to mark up" }, { value: "save", label: "Just show a notification" }]
                    value: Config.s.screenshotAfter
                    onPicked: v => Config.s.screenshotAfter = v
                }
                Separator {}
                DropdownSetting {
                    label: "Save to"
                    detail: shp.folder.replace(shp.home, "~")
                    options: [{ value: "", label: "Pictures/Screenshots" }, { value: shp.home + "/Pictures", label: "Pictures" },
                              { value: shp.home + "/Desktop", label: "Desktop" }, { value: shp.home + "/Downloads", label: "Downloads" }]
                    value: Config.s.screenshotFolder
                    onPicked: v => Config.s.screenshotFolder = v
                }
                Separator {}
                DropdownSetting {
                    label: "File names"
                    options: [{ value: "default", label: "Screenshot " + Qt.formatDateTime(shp.example, "yyyy-MM-dd HH.mm.ss") },
                              { value: "compact", label: Qt.formatDateTime(shp.example, "yyyy-MM-dd_HH-mm-ss") },
                              { value: "gnome", label: "Screenshot from " + Qt.formatDateTime(shp.example, "yyyy-MM-dd HH-mm-ss") }]
                    value: Config.s.screenshotName
                    onPicked: v => Config.s.screenshotName = v
                }
                Separator {}
                SettingRow {
                    label: "Screenshot folder"
                    Button {
                        icon: 0xFAF7; label: "Open"
                        onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && xdg-open \"$0\"", shp.folder])
                    }
                }
            }
            Text {
                width: parent.width
                topPadding: 10
                text: "Print Screen takes an area (drag it out), Super+Print Screen the whole screen."
                color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: windowsPage
        Column {
            spacing: 4
            PageTitle { text: "Windows" }
            Group {
                // Floating mode and its title bars need hyprbars (Config.titleBarsAvailable)
                SettingRow {
                    visible: Config.titleBarsAvailable
                    label: "Window mode"
                    detail: Config.s.windowMode === "floating"
                        ? "Windows open floating and centred, like a traditional desktop. Move them by their title bar or with Super+drag; Super+Alt+Space tiles one"
                        : "Windows tile side by side. Super+drag moves one, Super+Alt+Space floats it"
                    // Two-way switch: Tiling | Floating, each with a small picture of the layout
                    Rectangle {
                        readonly property var modes: ["tiling", "floating"]
                        width: 200; height: 34; radius: 9
                        color: Config.tint("#151920")
                        Rectangle {
                            width: 100 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.s.windowMode)) * 100
                            color: win.accent
                            Gloss { radius: parent.radius }   // glass: a sheen on the chosen side
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: [{ mode: "tiling", label: "Tiling" }, { mode: "floating", label: "Floating" }]
                                delegate: Item {
                                    id: modeOpt
                                    required property var modelData
                                    readonly property bool on: Config.s.windowMode === modelData.mode
                                    readonly property color ink: on ? win.accentText : win.dim
                                    width: 100; height: 34
                                    Rectangle {
                                        anchors { fill: parent; margins: 3 }
                                        radius: 7
                                        color: win.accent
                                        opacity: !modeOpt.on && modeHover.hovered ? Config.hoverStrength : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    HoverHandler { id: modeHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 7
                                        // The picture: two windows side by side, or two overlapping
                                        Item {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 16; height: 12
                                            Rectangle {
                                                visible: modeOpt.modelData.mode === "tiling"
                                                width: 7; height: 12; radius: 2
                                                color: modeOpt.ink
                                            }
                                            Rectangle {
                                                visible: modeOpt.modelData.mode === "tiling"
                                                x: 9; width: 7; height: 12; radius: 2
                                                color: modeOpt.ink
                                            }
                                            Rectangle {
                                                visible: modeOpt.modelData.mode === "floating"
                                                width: 11; height: 8; radius: 2
                                                color: "transparent"
                                                border.width: 1.5; border.color: modeOpt.ink
                                            }
                                            Rectangle {
                                                visible: modeOpt.modelData.mode === "floating"
                                                x: 5; y: 4; width: 11; height: 8; radius: 2
                                                color: modeOpt.ink
                                            }
                                        }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modeOpt.modelData.label; color: modeOpt.ink; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    TapHandler { onTapped: Config.s.windowMode = modeOpt.modelData.mode }
                                }
                            }
                        }
                    }
                }
                Separator { visible: Config.titleBarsAvailable }
                DropdownSetting {
                    visible: Config.titleBarsAvailable
                    label: "Title bar buttons"
                    detail: "Which side of a floating window's title bar the close and maximise buttons sit on"
                    options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }]
                    value: Config.s.titleButtons
                    onPicked: v => Config.s.titleButtons = v
                }
                Separator { visible: Config.titleBarsAvailable }
                SettingRow {
                    id: focusRow
                    label: "Focus follows the pointer"
                    detail: "Windows take the keyboard as the pointer moves over them. Off: click a window to use it (scrolling still reaches the one under the pointer)"
                    property int current: 1
                    Process {
                        running: true
                        command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:follow_mouse"]
                        stdout: StdioCollector { onStreamFinished: { try { focusRow.current = JSON.parse(text)["input:follow_mouse"]; } catch (e) {} } }
                    }
                    Toggle {
                        checked: Config.s.focusFollowsMouse !== "" ? Config.s.focusFollowsMouse === "on" : focusRow.current === 1
                        onToggled: v => Config.s.focusFollowsMouse = v ? "on" : "off"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Window borders"
                    detail: "Around each window when a workspace has more than one (a lone window has none). 0 turns them off"
                    ValueSlider { from: 0; to: 12; stepSize: 1; suffix: " px"; value: Config.s.windowBorderSize; onMoved: v => Config.s.windowBorderSize = v }
                }
                Separator {}
                SettingRow {
                    label: "Window spacing"
                    detail: "The gap between windows on a workspace with more than one (the screen edges get a little more). 0 puts them edge to edge"
                    ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.windowGap; onMoved: v => Config.s.windowGap = v }
                }
                Separator {}
                SettingRow {
                    label: "Space around a lone window"
                    detail: "Padding around a window that's alone on its workspace, which then keeps its rounded corners. 0 lets it fill the screen up to the bar. Maximised and full-screen apps always fill it"
                    ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.soloWindowGap; onMoved: v => Config.s.soloWindowGap = v }
                }
                Separator {}
                SettingRow {
                    label: "Dim inactive windows"
                    detail: "Darken the windows you're not using, so the focused one stands out. 0 turns it off"
                    ValueSlider { from: 0; to: 80; stepSize: 5; suffix: "%"; value: Config.s.inactiveDim; onMoved: v => Config.s.inactiveDim = v }
                }
            }
            GroupLabel { text: "Window switcher (Super+Tab)" }
            Group {
                SettingRow {
                    label: "Live previews"
                    detail: "Show each window's contents; turn off to show app icons only"
                    Toggle { checked: Config.s.switcherPreviews; onToggled: v => Config.s.switcherPreviews = v }
                }
                Separator {}
                SettingRow {
                    label: "App icons on previews"
                    detail: "A small app icon on the corner of each window's preview"
                    Toggle { checked: Config.s.switcherAppIcons; onToggled: v => Config.s.switcherAppIcons = v }
                }

            }
        }
    }

    Component {
        id: workspacesPage
        Column {
            spacing: 4
            PageTitle { text: "Workspaces" }
            Group {
                DropdownSetting {
                    label: "Workspace switching"
                    detail: Config.s.animations === "off" ? "Animations are off, so workspaces switch straight away"
                        : ({ slidefade: "The new workspace slides in over the old one, which fades away underneath",
                             slidefadevert: "The new workspace slides in from above or below over the old one, which fades away",
                             slide: "Both slide along together, like turning pages",
                             slidevert: "Both slide up or down together",
                             crossfade: "The new workspace fades in over the old one",
                             none: "Straight to the new workspace, with no animation" })[Config.s.workspaceAnimation] || ""
                    options: [{ value: "slidefade", label: "Slide Fade" }, { value: "slide", label: "Slide" },
                              { value: "crossfade", label: "Crossfade" }, { value: "slidefadevert", label: "Vertical Slide Fade" },
                              { value: "slidevert", label: "Vertical Slide" }, { value: "none", label: "None" }]
                    value: Config.s.workspaceAnimation || "slidefade"
                    onPicked: v => Config.s.workspaceAnimation = v
                }
                Separator {}
                SettingRow {
                    label: "Workspaces wrap around"
                    detail: "Super+Left/Right and the overview go from the last workspace back to the first (and the other way); off, they stop at the ends, and the overview's row ends there too"
                    Toggle { checked: Config.s.wrapWorkspaces; onToggled: v => Config.s.wrapWorkspaces = v }
                }
                Separator {}
                SettingRow {
                    label: "Keep an empty workspace"
                    detail: "Always have an empty workspace after the last one in use, ready for a new window"
                    Toggle { checked: Config.s.keepEmptyWorkspace; onToggled: v => Config.s.keepEmptyWorkspace = v }
                }
            }
            GroupLabel { text: "Look" }
            Group {
                SettingRow {
                    label: "Workspace indicators"
                    detail: "The shape of the workspace dots on the bar, the window switcher, the overview and the on-screen display"
                    // Two-way switch: Circles | Squares, each with a small preview
                    Rectangle {
                        readonly property var shapes: ["circle", "square"]
                        width: 184; height: 34; radius: 9
                        color: Config.tint("#151920")
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.shapes.indexOf(Config.s.workspaceShape)) * 92
                            color: win.accent
                            Gloss { radius: parent.radius }   // glass: a sheen on the chosen side
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: [{ shape: "circle", label: "Circles" }, { shape: "square", label: "Squares" }]
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool on: Config.s.workspaceShape === modelData.shape
                                    width: 92; height: 34
                                    Rectangle {
                                        anchors { fill: parent; margins: 3 }
                                        radius: 7
                                        color: win.accent
                                        opacity: !parent.on && shapeHover.hovered ? Config.hoverStrength : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    HoverHandler { id: shapeHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 10; height: 10
                                            radius: parent.parent.modelData.shape === "square" ? 10 * 0.28 : 5
                                            color: parent.parent.on ? win.accentText : win.dim
                                        }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; color: parent.parent.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    TapHandler { onTapped: Config.s.workspaceShape = parent.modelData.shape }
                                }
                            }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "On the menu bar"
                    detail: "The workspace dots on the bar (also in Menu bar)"
                    Toggle { checked: Config.s.barShowWorkspaces; onToggled: v => Config.s.barShowWorkspaces = v }
                }
            }
            GroupLabel { text: "Workspace overview (Super+Down)" }
            Group {
                SettingRow {
                    label: "Card size"
                    ValueSlider { from: 480; to: 1000; stepSize: 8; suffix: " px"; value: Config.s.overviewCardWidth; onMoved: v => Config.s.overviewCardWidth = v }
                }
                Separator {}
                SettingRow {
                    label: "App icons on windows"
                    detail: "Each window's app icon in the middle of it on the cards"
                    Toggle { checked: Config.s.overviewAppIcons; onToggled: v => Config.s.overviewAppIcons = v }
                }
            }
            GroupLabel { text: "Spaces" }
            Group {
                SettingRow {
                    label: "Spaces"
                    detail: "Save sets of workspaces with their apps and layout, and bring them back in one click"
                    Button { label: "Open"; onClicked: win.goTo("spaces", "") }
                }
            }
        }
    }

    Component {
        id: notificationsPage
        Column {
            spacing: 4
            PageTitle { text: "Notifications" }
            Group {
                SettingRow {
                    label: "Do not disturb"
                    detail: "Silence pop-ups (critical ones still show); everything still goes to history"
                    Toggle { checked: win.notifs ? win.notifs.dnd : false; onToggled: v => { if (win.notifs) win.notifs.dnd = v; } }
                }
            }
            GroupLabel { text: "Pop-ups" }
            Group {
                SettingRow {
                    label: "Position"
                    detail: "Where new notifications appear on screen"
                    // A small screen: click a spot to put notifications there
                    Rectangle {
                        width: 168; height: 104; radius: 10
                        color: Config.tint("#151920")
                        border.width: 1; border.color: Config.tint("#323a46")
                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 } height: 9; topLeftRadius: 9; topRightRadius: 9; color: Config.tint("#2a313c") }
                        Repeater {
                            model: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool current: Config.s.notificationPosition === modelData
                                width: 44; height: 22; radius: 6
                                x: [8, (168 - 44) / 2, 168 - 44 - 8][index % 3]
                                y: index < 3 ? 16 : 104 - 22 - 8
                                color: current ? win.accent : spotHover.hovered ? Config.hoverOn(Config.tint("#262c35")) : Config.tint("#262c35")
                                Gloss { radius: parent.radius; opacity: (current || spotHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                                Behavior on color { ColorAnimation { duration: 100 } }
                                HoverHandler { id: spotHover }
                                TapHandler { onTapped: Config.s.notificationPosition = parent.modelData }
                            }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Stay on screen for"
                    detail: "When the app doesn't choose its own time"
                    ValueSlider { from: 2; to: 15; stepSize: 1; suffix: " s"; value: Config.s.notificationSeconds; onMoved: v => Config.s.notificationSeconds = v }
                }
                Separator {}
                SettingRow {
                    label: "Most at once"
                    ValueSlider { from: 1; to: 8; stepSize: 1; value: Config.s.notificationMaxToasts; onMoved: v => Config.s.notificationMaxToasts = v }
                }
            }
            GroupLabel { text: "History" }
            Group {
                SettingRow {
                    label: "Clear notification history"
                    detail: win.notifs ? win.notifs.history.length + " saved" : ""
                    Button { label: "Clear"; destructive: true; onClicked: if (win.notifs) win.notifs.clearAll() }
                }
            }
        }
    }

    Component {
        id: appearancePage
        Column {
            id: wp
            spacing: 4
            readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
            function setWallpaper(path) { Config.s.wallpaper = path; }
            // Choosing another wallpaper folder (a small folder browser under the Folder row)
            property bool choosingFolder: false
            property string browseDir: ""
            function chooseFolder() { browseDir = folder; choosingFolder = true; }

            PageTitle { text: "Appearance" }
            GroupLabel { text: "Theme & colour" }
            Group {
                SettingRow {
                    label: "Theme"
                    detail: {
                        if (Config.themeMode !== "auto") return "Dark is the default; light flips the bar, panels and windows to light backgrounds with dark text";
                        const h = Config.lightHours(new Date());
                        return "Auto: light from " + Config.clockText(h.from) + " to " + Config.clockText(h.to)
                            + (Config.s.locationName !== "" ? " (sunrise to sunset in " + Config.s.locationName + ")" : " (set a location below to follow sunrise and sunset)");
                    }
                    // Three-way switch: Dark | Light | Auto
                    Rectangle {
                        readonly property var modes: ["dark", "light", "auto"]
                        width: 276; height: 34; radius: 9
                        color: Config.tint("#151920")
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.themeMode)) * 92
                            color: win.accent
                            Gloss { radius: parent.radius }   // glass: a sheen on the chosen side
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.fill: parent
                            Repeater {
                                model: [{ mode: "dark", label: "Dark", icon: 0xEAF8 }, { mode: "light", label: "Light", icon: 0xEB30 }, { mode: "auto", label: "Auto", icon: 0xF4A3 }]
                                delegate: Item {
                                    required property var modelData
                                    readonly property bool on: Config.themeMode === modelData.mode
                                    width: 92; height: 34
                                    Rectangle {
                                        anchors { fill: parent; margins: 3 }
                                        radius: 7
                                        color: win.accent
                                        opacity: !parent.on && themeHover.hovered ? Config.hoverStrength : 0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                    HoverHandler { id: themeHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.glyph(parent.parent.modelData.icon); color: parent.parent.on ? win.accentText : win.dim; font.family: win.bar.iconFont; font.pixelSize: 14 }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; color: parent.parent.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    TapHandler {
                                        onTapped: {
                                            const m = parent.modelData.mode;
                                            Config.s.themeMode = m;
                                            if (m !== "auto") Config.s.lightMode = m === "light";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Accent colour from wallpaper"
                    detail: "Highlights (switches, sliders, selected items, the active workspace dot) use a bright colour picked from the wallpaper. Off: the colour chosen below"
                    Row {
                        spacing: 12
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: Config.wallpaperAccent || "transparent"
                            border.width: 1; border.color: Config.tint("#3a424e")
                        }
                        Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.accentFromWallpaper; onToggled: v => Config.s.accentFromWallpaper = v }
                    }
                }
                Separator {}
                Column {
                    width: parent.width
                    opacity: Config.s.accentFromWallpaper ? 0.4 : 1
                    enabled: !Config.s.accentFromWallpaper
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    SettingRow {
                        label: "Accent colour"
                        detail: "Used for highlights across the bar, dock, launcher and panels"
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["#8fb3e8", "#7fc4c0", "#9ad3a6", "#e8c48f", "#e8a6b5", "#b9a6e8", "#eef1f5"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 24; height: 24; radius: 12
                                    color: modelData
                                    border.width: Config.s.accent.toLowerCase() === modelData ? 2 : 0
                                    border.color: win.text
                                    scale: swHover.hovered ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: 100 } }
                                    HoverHandler { id: swHover }
                                    TapHandler { onTapped: Config.s.accent = parent.modelData }
                                }
                            }
                        }
                    }
                    Separator {}
                    SettingRow {
                        id: customRow
                        label: "Custom colour"
                        detail: "Slide to pick a shade, or type a hex code"
                        readonly property color current: Config.s.accent
                        Row {
                            spacing: 12
                            // Hue slider: keeps the theme's soft lightness, changes the hue
                            Item {
                                id: hue
                                anchors.verticalCenter: parent.verticalCenter
                                width: 200; height: 24
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 10; radius: 5
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0/6; color: Qt.hsla(0/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 1/6; color: Qt.hsla(1/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 2/6; color: Qt.hsla(2/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 3/6; color: Qt.hsla(3/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 4/6; color: Qt.hsla(4/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 5/6; color: Qt.hsla(5/6, 0.65, 0.74, 1) }
                                        GradientStop { position: 6/6; color: Qt.hsla(0.999, 0.65, 0.74, 1) }
                                    }
                                }
                                Rectangle {
                                    width: 16; height: 16; radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, customRow.current.hslHue) * (parent.width - width)
                                    color: customRow.current
                                    border.width: 2; border.color: win.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    function set(mx) {
                                        const h = Math.max(0, Math.min(0.999, mx / width));
                                        const c = Qt.hsla(h, 0.65, 0.74, 1);
                                        const hex = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
                                        Config.s.accent = "#" + hex(c.r) + hex(c.g) + hex(c.b);
                                    }
                                    onPressed: m => set(m.x)
                                    onPositionChanged: m => { if (pressed) set(m.x); }
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92; height: 30; radius: 8
                                color: Config.tint("#2a313c")
                                // Hover: a faint accent outline (solid while typing)
                                HoverHandler { id: hexInputHover; cursorShape: Qt.IBeamCursor }
                                border.width: hexInput.activeFocus || hexInputHover.hovered ? 1 : 0
                                border.color: hexInput.activeFocus ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.5)
                                TextInput {
                                    id: hexInput
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: Config.s.accent
                                    color: win.text
                                    selectionColor: win.accent
                                    font.family: win.font; font.pixelSize: 12
                                    maximumLength: 7
                                    validator: RegularExpressionValidator { regularExpression: /#?[0-9A-Fa-f]{0,6}/ }
                                    function apply() {
                                        let t = text.trim();
                                        if (!t.startsWith("#")) t = "#" + t;
                                        if (/^#[0-9A-Fa-f]{6}$/.test(t)) Config.s.accent = t.toLowerCase();
                                        else text = Config.s.accent;
                                    }
                                    onAccepted: { apply(); focus = false; }
                                    onEditingFinished: apply()
                                }
                            }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Background tint from wallpaper"
                    detail: "The bar, panels and window backgrounds keep their brightness but take on the wallpaper's overall hue. Off: neutral slate"
                    Row {
                        spacing: 12
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: Config.wallpaperTone ? Qt.hsla(Qt.lighter(Config.wallpaperTone, 1).hslHue, 0.3, 0.2, 1) : "transparent"
                            border.width: 1; border.color: Config.tint("#3a424e")
                        }
                        Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.toneFromWallpaper; onToggled: v => Config.s.toneFromWallpaper = v }
                    }
                }
            }
            GroupLabel { text: "Glass" }
            Group {
                SettingRow {
                    label: "Glass"
                    detail: "The bar, dock, panels, menus, the launcher and Settings turn see-through, with what's behind them blurred"
                    Toggle { checked: Config.s.glass; onToggled: v => Config.s.glass = v }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Opacity"
                    detail: "How much of their colour the surfaces keep: lower is clearer glass"
                    ValueSlider { from: 30; to: 95; stepSize: 5; suffix: "%"; value: Math.round(Config.s.glassOpacity * 100); onMoved: v => Config.s.glassOpacity = v / 100 }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Blur"
                    detail: Config.s.glassBlur > 0 ? "How strongly what's behind is blurred (Hyprland's blur, so see-through windows use it too)"
                        : "Hyprland's own blur (size " + Config.hyprBlur.size + "); drag to make it stronger or softer"
                    ValueSlider { from: 0; to: 20; stepSize: 1; value: Config.s.glassBlur; onMoved: v => Config.s.glassBlur = v }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Shine"
                    detail: "A thin light rim around the glass, like the edge of a pane"
                    Toggle { checked: Config.s.glassShine; onToggled: v => Config.s.glassShine = v }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Gloss"
                    detail: "A glossy sheen on the bar's containers, hover highlights and tooltips. 0% for none"
                    ValueSlider { from: 0; to: 200; stepSize: 10; suffix: "%"; value: Math.round(Config.glossAmount * 100); onMoved: v => Config.s.glassGloss = v / 100 }
                }
            }
            GroupLabel { text: "Blur" }
            Group {
                SettingRow {
                    label: "Fast blur"
                    detail: Config.s.fastBlur ? "See-through windows and glass blur just the wallpaper, not the windows under them: far less work, so everything stays smooth"
                        : "See-through windows and glass blur whatever's under them, windows included. Heavier: animations and the pointer can slow down"
                    Toggle { checked: Config.s.fastBlur; onToggled: v => Config.s.fastBlur = v }
                }
                Separator {}
                DropdownSetting {
                    label: "Blur quality"
                    detail: "Smoother blur takes more passes, and more work"
                    options: [{ value: 0, label: "Hyprland's own" }, { value: 1, label: "Low (1 pass)" }, { value: 2, label: "Medium (2 passes)" },
                              { value: 3, label: "High (3 passes)" }, { value: 4, label: "Highest (4 passes)" }]
                    value: Config.s.blurPasses
                    onPicked: v => Config.s.blurPasses = v
                }
            }
            GroupLabel { text: "Style" }
            Group {
                SettingRow {
                    label: "Rounded screen corners"
                    detail: "Round off the corners of the screen and curve the bar into the screen edges"
                    Toggle { checked: Config.s.roundedScreenCorners; onToggled: v => Config.s.roundedScreenCorners = v }
                }
                Separator {}
                // Folder colour for file managers: Papirus's coloured folders (scripts/folder-colour.py)
                Column {
                    id: folderSet
                    width: parent.width
                    property var info: ({ supported: true, base: "", colours: [] })
                    Process {
                        running: true
                        command: [Quickshell.shellPath("scripts/folder-colour.py"), "--list"]
                        stdout: StdioCollector { onStreamFinished: { try { folderSet.info = JSON.parse(text); } catch (e) {} } }
                    }
                    readonly property var names: ({ adwaita: "Adwaita blue", bluegrey: "Blue grey", breeze: "Breeze blue",
                        darkcyan: "Dark cyan", deeporange: "Deep orange", palebrown: "Pale brown", paleorange: "Pale orange" })
                    function nice(n) { return names[n] || (n.charAt(0).toUpperCase() + n.slice(1)); }
                    readonly property var colours: folderSet.info.colours || []
                    function hexOf(name) { const c = colours.find(x => x.name === name); return c ? c.hex : ""; }
                    // Auto: the Papirus colour closest to the wallpaper's, picked as folder-colour.py
                    // does (nearest()): by hue for colourful ones, else a grey
                    readonly property string autoHex: {
                        const a = Config.wallpaperAccent ? Qt.color(Config.wallpaperAccent) : null;
                        if (!a || colours.length === 0) return hexOf("blue") || "#5294e2";
                        const greys = ["black", "grey", "white", "bluegrey"];
                        const hue = c => Math.max(0, c.hslHue);
                        const grey = a.hslSaturation < 0.18;
                        let best = "", d = 1e9;
                        for (const c of colours) {
                            if (c.name === "yaru" || greys.includes(c.name) !== grey) continue;
                            const k = Qt.color(c.hex);
                            const dh0 = Math.abs(hue(k) - hue(a)), dh = Math.min(dh0, 1 - dh0);
                            const e = dh * 4 + Math.abs(k.hslLightness - a.hslLightness) + Math.abs(k.hslSaturation - a.hslSaturation) * 0.5;
                            if (e < d) { d = e; best = c.hex; }
                        }
                        return best || hexOf("blue") || "#5294e2";
                    }
                    SettingRow {
                        visible: !folderSet.info.supported
                        label: "Folder colour"
                        detail: "Folders in Nautilus, Dolphin and other file managers. Needs the Papirus icon theme (this system uses " + folderSet.info.base + ")"
                    }
                    DropdownSetting {
                        visible: folderSet.info.supported
                        label: "Folder colour"
                        detail: Config.s.folderColour === "auto" ? "Folders in Nautilus, Dolphin and other file managers, in the Papirus colour closest to the wallpaper's"
                            : "Folders in Nautilus, Dolphin and other file managers"
                        options: [{ value: "auto", label: "From the wallpaper", folder: folderSet.autoHex },
                                  { value: "default", label: "Theme's own", folder: folderSet.hexOf("blue") || "#5294e2" }]
                            .concat(folderSet.colours.map(c => ({ value: c.name, label: folderSet.nice(c.name), folder: c.hex })))
                        value: Config.s.folderColour === "" ? "default" : Config.s.folderColour
                        onPicked: v => Config.s.folderColour = v
                    }
                }
            }
            GroupLabel { text: "App icons" }
            Group {
                id: iconGroup
                // One of your apps drawn in each shape, filled and whole (scripts/appicon.py --preview)
                readonly property string previewDir: Quickshell.env("HOME") + "/.cache/slate/tiles/preview"
                property int previewVersion: 0
                Process {
                    running: true
                    command: [Config.tileScript, "--preview", iconGroup.previewDir, "96"]
                    onExited: iconGroup.previewVersion++
                }
                SettingRow {
                    label: "Shape"
                    detail: "For app icons in the dock, launcher, switcher, bar and notifications"
                }
                Flow {
                    width: parent.width - 32; x: 16
                    spacing: 8
                    bottomPadding: 14
                    Repeater {
                        model: [{ value: "tile", label: "Tile" }, { value: "squircle", label: "Squircle" }, { value: "circle", label: "Circle" },
                                { value: "square", label: "Square" }, { value: "original", label: "Original" }]
                        delegate: Rectangle {
                            id: shapeCard
                            required property var modelData
                            readonly property bool on: Config.s.iconShape === modelData.value
                            width: 92; height: 96; radius: 12
                            color: on ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16) : shapeHover.hovered ? Config.hoverOn(Config.tint("#151920")) : Config.tint("#151920")
                            Gloss { radius: parent.radius; opacity: (on || shapeHover.hovered) ? 1 : 0 }   // glass: a sheen while selected or hovered
                            border.width: on ? 2 : 0; border.color: win.accent
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Image {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                                width: 48; height: 48
                                sourceSize: Qt.size(96, 96)
                                cache: false
                                source: iconGroup.previewVersion > 0
                                    ? "file://" + iconGroup.previewDir + "/" + shapeCard.modelData.value + (Config.s.iconFill ? "-fill" : "-whole") + ".png?v=" + iconGroup.previewVersion
                                    : ""
                                IconPlate { anchors.fill: parent; z: -1; shape: shapeCard.modelData.value }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                                text: shapeCard.modelData.label
                                color: shapeCard.on ? win.text : win.dim
                                font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            HoverHandler { id: shapeHover }
                            TapHandler { onTapped: Config.s.iconShape = shapeCard.modelData.value }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Fill the shape"
                    detail: Config.s.iconShape === "original"
                        ? "Trim icons' empty margins and theme shadows so they're all the same size. Off: exactly as the apps ship them"
                        : "Crop each icon's own border and shadow and grow it to fill the shape, on its main colour. Off: the whole icon, smaller, on a plain tile"
                    Toggle { checked: Config.s.iconFill; onToggled: v => Config.s.iconFill = v }
                }
                Separator {}
                SettingRow {
                    label: "Tint app icons"
                    detail: "Colour app icons in the dock, launcher, switcher, bar and notifications with the accent colour"
                    Toggle { checked: Config.s.tintIcons; onToggled: v => Config.s.tintIcons = v }
                }
                Separator { visible: Config.s.tintIcons }
                SettingRow {
                    visible: Config.s.tintIcons
                    label: "Tint strength"
                    detail: "A light wash of colour, up to icons drawn entirely in the accent"
                    ValueSlider { from: 20; to: 100; stepSize: 5; suffix: "%"; value: Config.s.iconTintStrength; onMoved: v => Config.s.iconTintStrength = v }
                }
            }
            GroupLabel { text: "Fonts" }
            Group {
                FontSetting {
                    label: "Interface font"
                    detail: "Used across the bar, panels, launcher, switchers, notifications and this window"
                    key: "fontFamily"
                    defaultFont: "Geist"
                }
                Separator {}
                FontSetting {
                    label: "Code font"
                    detail: "Monospaced font for terminals and code; used when apps are themed"
                    key: "codeFontFamily"
                    defaultFont: "Noto Sans Mono"
                    monoOnly: true
                }
            }
            GroupLabel { text: "Size" }
            Group {
                SettingRow {
                    label: "Interface size"
                    detail: Math.abs(Config.s.uiScale - Config.uiScale) < 0.001
                        ? "Scales all of Slate: the bar, dock, panels, launcher, title bars and this window"
                        : "Slate restarts to apply this (Settings opens again)"
                    ValueSlider {
                        from: 75; to: 150; stepSize: 5; suffix: "%"
                        value: Math.round(Config.s.uiScale * 100)
                        onMoved: v => { Config.s.uiScale = v / 100; Config.uiScaleEdited(); }
                    }
                }
            }
            GroupLabel { text: "Motion" }
            Group {
                DropdownSetting {
                    label: "Animations"
                    detail: "Windows opening, closing and moving, and switching workspaces"
                    options: [{ value: "normal", label: "Normal" }, { value: "fast", label: "Faster" }, { value: "off", label: "Off" }]
                    value: Config.s.animations !== "" ? Config.s.animations : "normal"
                    onPicked: v => Config.s.animations = v
                }
            }
            GroupLabel { text: "Other apps" }
            Group {
                SettingRow {
                    label: "App theming"
                    readonly property int count: (Config.s.themedApps || []).length
                    detail: "Terminals, editors, GTK, Qt and more following Slate's colours and accent · "
                        + (count === 0 ? "none switched on" : count + (count === 1 ? " app" : " apps") + " themed")
                    Button { label: "Open"; onClicked: win.goTo("apptheming", "") }
                }
            }
            GroupLabel { id: wallLabel; text: "Wallpaper" }
            Group {
                SettingRow {
                    label: "Folder"
                    detail: wp.folder.replace(Quickshell.env("HOME"), "~")
                    Row {
                        spacing: 8
                        Button { icon: 0xFAF7; label: "Open"; onClicked: Quickshell.execDetached(["xdg-open", wp.folder]) }
                        Button { icon: 0xEAAD; label: "Change…"; onClicked: wp.choosingFolder ? wp.choosingFolder = false : wp.chooseFolder() }
                        Button { icon: 0xF000; label: "Random"; primary: true; onClicked: if (wp.shown.length > 0) wp.setWallpaper(wp.shown[Math.floor(Math.random() * wp.shown.length)]) }
                    }
                }
                // Folder browser: go into a folder, then use it
                Column {
                    visible: wp.choosingFolder
                    width: parent.width - 32; x: 16
                    spacing: 8
                    bottomPadding: 14
                    Row {
                        width: parent.width
                        spacing: 6
                        Button {
                            id: upBtn
                            icon: 0xEA25; label: "Up"
                            opacity: wp.browseDir === "/" ? 0.45 : 1
                            onClicked: if (wp.browseDir !== "/") wp.browseDir = wp.browseDir.replace(/\/[^\/]*$/, "") || "/"
                        }
                        Button { id: homeBtn; icon: 0xEAC1; label: "Home"; onClicked: wp.browseDir = Quickshell.env("HOME") }
                        Text {
                            width: parent.width - upBtn.width - homeBtn.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: wp.browseDir.replace(Quickshell.env("HOME"), "~")
                            color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 220
                        radius: 8
                        color: Config.tint("#151920")
                        ListView {
                            id: dirList
                            anchors { fill: parent; margins: 4 }
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            SmoothWheel { flick: dirList }
                            model: FolderListModel {
                                id: dirModel
                                folder: wp.choosingFolder ? "file://" + wp.browseDir : ""
                                showFiles: false
                                showDirs: true
                                showDotAndDotDot: false
                                showHidden: false
                                sortField: FolderListModel.Name
                            }
                            delegate: Rectangle {
                                required property string fileName
                                required property string filePath
                                width: dirList.width; height: 32; radius: 6
                                color: dirHover.hovered ? Config.hover : "transparent"
                                Gloss { radius: parent.radius; opacity: (dirHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                                Text {
                                    id: dirIcon
                                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: win.glyph(0xEAAD)
                                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
                                }
                                Text {
                                    anchors { left: dirIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: parent.fileName
                                    color: win.text; font.family: win.font; font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                HoverHandler { id: dirHover }
                                TapHandler { onTapped: wp.browseDir = parent.filePath }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: dirList.count === 0
                            text: "No folders in here"
                            color: win.dim; font.family: win.font; font.pixelSize: 12
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { label: "Cancel"; onClicked: wp.choosingFolder = false }
                        Button {
                            label: "Use this folder"; primary: true
                            onClicked: {
                                const home = Quickshell.env("HOME") + "/Pictures";
                                Config.s.wallpaperFolder = wp.browseDir === home ? "" : wp.browseDir;
                                wp.choosingFolder = false;
                            }
                        }
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Change wallpaper"
                    detail: (Config.s.wallpaperChange === "off"
                            ? "Keep the one you pick"
                            : "Switch to another image from this folder, in a shuffled order")
                        + (Config.s.wallpaperChange !== "off" && !Config.s.accentFromWallpaper && !Config.s.toneFromWallpaper
                            ? ". Turn on the accent or tint from the wallpaper (above) for the theme to change with it" : "")
                    options: [
                        { value: "off", label: "Never" },
                        { value: "login", label: "At each login" },
                        { value: "15", label: "Every 15 minutes" },
                        { value: "30", label: "Every 30 minutes" },
                        { value: "60", label: "Every hour" },
                        { value: "180", label: "Every 3 hours" },
                        { value: "1440", label: "Every day" }
                    ]
                    value: Config.s.wallpaperChange
                    onPicked: v => Config.s.wallpaperChange = v
                }
                Separator {}
                SettingRow {
                    label: "Hide small images"
                    detail: "Leave out pictures too small to be wallpapers, like icons, avatars and small screenshots"
                    Toggle { checked: Config.s.wallpaperHideSmall; onToggled: v => Config.s.wallpaperHideSmall = v }
                }
                Separator { visible: Config.s.wallpaperHideSmall }
                DropdownSetting {
                    visible: Config.s.wallpaperHideSmall
                    label: "Smallest size"
                    detail: "Images narrower or shorter than this are hidden"
                    options: [{ value: "320x240", label: "320 × 240" }, { value: "640x480", label: "640 × 480" }, { value: "800x600", label: "800 × 600" }, { value: "1024x768", label: "1024 × 768" }, { value: "1280x720", label: "1280 × 720" }, { value: "1920x1080", label: "1920 × 1080" }, { value: "2560x1440", label: "2560 × 1440" }]
                    value: Config.s.wallpaperMinSize
                    onPicked: v => Config.s.wallpaperMinSize = v
                }
            }
            // ---- Hiding small images: each image's size, read from its file (scripts/image-sizes.py)
            property var sizes: ({})
            readonly property var minSize: Config.s.wallpaperMinSize.split("x").map(Number)
            function tooSmall(name) {
                const sz = sizes[name];
                return Config.s.wallpaperHideSmall && !!sz && (sz[0] < minSize[0] || sz[1] < minSize[1]);
            }
            Process {
                id: sizeReader
                command: [Quickshell.shellPath("scripts/image-sizes.py"), wp.folder]
                stdout: StdioCollector { onStreamFinished: { try { wp.sizes = JSON.parse(text); } catch (e) {} } }
            }
            // Read the sizes when the page opens and when the folder's contents change
            Connections { target: wallFiles; function onCountChanged() { sizeReader.running = false; sizeReader.running = true; } }
            Component.onCompleted: {
                sizeReader.running = true;
                // Opened for the wallpapers (Super+Shift+W): scroll down to them
                if (win.scrollTo === "wallpaper") Qt.callLater(() => Qt.callLater(() => {
                    win.scrollTo = "";
                    scroller.contentY = Math.max(0, Math.min(wallLabel.y - 8, scroller.contentHeight - scroller.height));
                }));
            }
            readonly property var shown: {
                const out = [];
                for (let i = 0; i < wallFiles.count; i++) {
                    const n = wallFiles.get(i, "fileName");
                    if (!tooSmall(n)) out.push(wallFiles.get(i, "filePath"));
                }
                return out;
            }
            readonly property int hidden: wallFiles.count - shown.length

            GroupLabel {
                text: wp.shown.length + (wp.shown.length === 1 ? " image" : " images")
                    + (wp.hidden > 0 ? " · " + wp.hidden + " small " + (wp.hidden === 1 ? "one" : "ones") + " hidden" : "")
            }
            FolderListModel {
                id: wallFiles
                folder: "file://" + wp.folder
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG"]
                showDirs: false
                sortField: FolderListModel.Name
            }
            Text {
                visible: wallFiles.count === 0
                text: "No images in this folder"
                color: win.dim; font.family: win.font; font.pixelSize: 13
                leftPadding: 4
            }
            // Thumbnails; click one to use it
            Grid {
                id: wallGrid
                width: parent.width
                columns: 3
                spacing: 12
                readonly property real tileW: (width - spacing * (columns - 1)) / columns
                Repeater {
                    model: wallFiles
                    delegate: Item {
                        required property string filePath
                        required property string fileName
                        readonly property bool current: Config.wallpaper === filePath
                        visible: !wp.tooSmall(fileName)
                        width: wallGrid.tileW
                        height: width * 10 / 16 + 26
                        Rectangle {
                            id: thumbFrame
                            width: parent.width; height: parent.width * 10 / 16
                            radius: 10
                            color: win.card
                            border.width: parent.current ? 3 : wallHover.hovered ? 1 : 0
                            border.color: parent.current ? win.accent : Config.tint("#4a5360")
                            Item {
                                anchors { fill: parent; margins: parent.parent.current ? 3 : 0 }
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: thumbMask }
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + filePath
                                    sourceSize.width: 360
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                Item {
                                    id: thumbMask
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: true
                                    Rectangle { anchors.fill: parent; radius: 8 }
                                }
                            }
                            // Tick on the wallpaper in use
                            Rectangle {
                                visible: parent.parent.current
                                anchors { right: parent.right; top: parent.top; margins: 8 }
                                width: 24; height: 24; radius: 12
                                color: win.accent
                                Text { anchors.centerIn: parent; text: win.glyph(0xEA5E); color: win.accentText; font.family: win.bar.iconFont; font.pixelSize: 15 }
                            }
                        }
                        Text {
                            anchors { top: thumbFrame.bottom; topMargin: 6; left: parent.left; right: parent.right }
                            text: fileName
                            color: parent.current ? win.text : win.dim
                            font.family: win.font; font.pixelSize: 11
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                        }
                        HoverHandler { id: wallHover }
                        TapHandler { onTapped: wp.setWallpaper(filePath) }
                    }
                }
            }
        }
    }

    Component {
        id: appThemingPage
        Column {
            spacing: 4
            PageTitle { text: "App theming" }
            Group {
                id: appTheming
                // What scripts/apply-theme.py can theme, and which are installed: [{id, label, detail, installed}]
                property var apps: []
                Process {
                    running: true
                    command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--apps"]
                    stdout: StdioCollector { onStreamFinished: { try { appTheming.apps = JSON.parse(text); } catch (e) {} } }
                }
                function isOn(id) { return (Config.s.themedApps || []).indexOf(id) >= 0; }
                function setOn(id, on) {
                    const list = (Config.s.themedApps || []).filter(x => x !== id);
                    if (on) list.push(id);
                    Config.s.themedApps = list;
                }
                SettingRow {
                    label: "Theme other apps"
                    detail: "Apps you switch on follow Slate's colours, light or dark, and the accent (even one picked from the wallpaper). Slate backs up a config before changing it, and switching an app off puts it back"
                }
                Repeater {
                    model: appTheming.apps
                    delegate: Column {
                        id: appRow
                        required property var modelData
                        width: parent ? parent.width : 0
                        Separator {}
                        SettingRow {
                            label: appRow.modelData.label
                            detail: appRow.modelData.installed || appTheming.isOn(appRow.modelData.id)
                                ? appRow.modelData.detail : "Not installed"
                            opacity: appRow.modelData.installed || appTheming.isOn(appRow.modelData.id) ? 1 : 0.5
                            Toggle {
                                visible: appRow.modelData.installed || checked
                                checked: appTheming.isOn(appRow.modelData.id)
                                onToggled: v => appTheming.setOn(appRow.modelData.id, v)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wifiPage
        Column {
            id: wf
            spacing: 4
            readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
            readonly property var nets: {
                if (!dev) return [];
                const seen = new Set();
                return dev.networks.values
                    .filter(n => n.name && !seen.has(n.name) && seen.add(n.name))
                    .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
            }
            readonly property var current: nets.find(n => n.connected) ?? null
            property string askingFor: ""
            // Look for networks while this page is open
            Binding { target: wf.dev; property: "scannerEnabled"; value: true; when: wf.dev !== null && win.visible }

            PageTitle { text: "Wi-Fi" }
            Group {
                SettingRow {
                    label: "Wi-Fi"
                    detail: !wf.dev ? "No Wi-Fi adapter found"
                        : !Networking.wifiEnabled ? "Off"
                        : wf.current ? "Connected to " + wf.current.name : "Not connected"
                    Toggle { visible: !!wf.dev; checked: Networking.wifiEnabled; onToggled: v => Networking.wifiEnabled = v }
                }
            }
            GroupLabel { visible: Networking.wifiEnabled && !!wf.dev; text: wf.nets.length ? "Networks" : "Searching for networks…" }
            Group {
                visible: Networking.wifiEnabled && wf.nets.length > 0
                Repeater {
                    model: wf.nets
                    delegate: Column {
                        id: netRow
                        required property var modelData
                        required property int index
                        readonly property var n: modelData
                        readonly property bool secure: n.security !== undefined && n.security !== WifiSecurityType.Open
                        width: parent.width
                        Rectangle { visible: netRow.index > 0; width: parent.width - 32; x: 16; height: 1; color: Config.tint("#262c35") }
                        Item {
                            width: parent.width; height: 60
                            Rectangle {
                                id: netIcon
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                width: 34; height: 34; radius: 9
                                color: netRow.n.connected ? win.accent : Config.tint("#2a313c")
                                Text {
                                    anchors.centerIn: parent
                                    readonly property real s: netRow.n.signalStrength
                                    text: win.glyph(s > 0.66 ? 0xEB52 : s > 0.33 ? 0xEBA5 : 0xEBA4)
                                    color: netRow.n.connected ? win.accentText : win.text
                                    font.family: win.bar.iconFont; font.pixelSize: 17
                                }
                            }
                            Column {
                                anchors { left: netIcon.right; leftMargin: 12; right: netButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Row {
                                    spacing: 6
                                    Text { text: netRow.n.name; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium }
                                    Text { visible: netRow.secure; anchors.verticalCenter: parent.verticalCenter; text: win.glyph(0xEAE2); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 12 }
                                }
                                Text {
                                    text: (netRow.n.connected ? "Connected" : netRow.n.stateChanging ? "Connecting…" : netRow.n.known ? "Saved" : netRow.secure ? "Secured" : "Open")
                                        + " · " + Math.round(netRow.n.signalStrength * 100) + "% signal"
                                    color: netRow.n.connected ? win.accent : win.dim
                                    font.family: win.font; font.pixelSize: 12
                                }
                            }
                            Row {
                                id: netButtons
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Button {
                                    label: netRow.n.connected ? "Disconnect" : "Connect"
                                    primary: !netRow.n.connected
                                    onClicked: {
                                        const n = netRow.n;
                                        if (n.connected) n.disconnect();
                                        else if (n.known || !netRow.secure) { n.connect(); wf.askingFor = ""; }
                                        else wf.askingFor = (wf.askingFor === n.name ? "" : n.name);
                                    }
                                }
                                Button {
                                    visible: netRow.n.known
                                    label: "Forget"
                                    destructive: true
                                    onClicked: netRow.n.forget()
                                }
                            }
                        }
                        // Password for a new secured network
                        Item {
                            visible: wf.askingFor === netRow.n.name
                            width: parent.width; height: 48
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; leftMargin: 60; rightMargin: 14; top: parent.top }
                                height: 36; radius: 8
                                color: Config.tint("#2a313c")
                                border.width: 1; border.color: win.accent
                                TextInput {
                                    id: psk
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: win.text
                                    font.family: win.font; font.pixelSize: 13
                                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                    onAccepted: { netRow.n.connectWithPsk(text); wf.askingFor = ""; }
                                    Keys.onEscapePressed: wf.askingFor = ""
                                }
                                Text {
                                    visible: psk.text === ""
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: "Password for " + netRow.n.name + ", then Enter"
                                    color: win.dim; font.family: win.font; font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: lockPage
        Column {
            id: lockCol
            spacing: 4
            readonly property var minutes: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60].map(m => ({ value: m, label: m === 0 ? "Never" : m + (m === 1 ? " minute" : " minutes") }))
            PageTitle { text: "Lock & idle" }
            Group {
                SettingRow {
                    label: "Lock screen"
                    detail: "Super+L, the power menu, or a hot corner"
                    Row {
                        spacing: 8
                        Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "preview", "lock"]); } }
                        Button { icon: 0xEAE2; label: "Lock now"; primary: true; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "lock"]); } }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Power menu on the lock screen"
                    detail: "Lets anyone at the keyboard suspend, restart, shut down or log you out without your password"
                    Toggle { checked: Config.s.lockScreenPowerMenu; onToggled: v => Config.s.lockScreenPowerMenu = v }
                }
                Separator {}
                SettingRow {
                    label: "Lock before sleep"
                    detail: "Lock the screen whenever the computer suspends or hibernates"
                    Toggle { checked: Config.s.lockBeforeSleep; onToggled: v => Config.s.lockBeforeSleep = v }
                }
            }
            GroupLabel { text: "Login screen" }
            Group {
                SettingRow {
                    id: greeterRow
                    property string state: ""          // not-installed, outdated, current
                    property string status: ""
                    readonly property bool installed: state === "outdated" || state === "current"
                    label: "Slate login screen"
                    detail: status !== "" ? status
                        : state === "current" ? "Set up; follows your wallpaper and theme automatically"
                        : state === "outdated" ? "Its design has changed since it was installed. Update asks for your password"
                        : state === "not-installed" ? "Not set up yet. In a terminal run:  sudo ~/.config/slate/bin/slate-greeter-install"
                        : ""
                    Process {
                        id: greeterCheck
                        running: true
                        command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--check"]
                        stdout: StdioCollector { onStreamFinished: greeterRow.state = text.trim() }
                    }
                    Process {
                        id: greeterUpdate
                        command: ["pkexec", Quickshell.shellPath("bin/slate-greeter-install"), "--code-only"]
                        onExited: code => { greeterRow.status = code === 0 ? "Updated; shows at your next logout or restart" : "Not updated"; greeterCheck.running = true; }
                    }
                    Process {
                        id: greeterSyncNow
                        command: [Quickshell.shellPath("bin/slate-greeter-sync")]
                        onExited: code => greeterRow.status = code === 0 ? "Appearance updated just now" : "Couldn't update; is it set up?"
                    }
                    Row {
                        spacing: 8
                        Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "preview", "login"]); } }
                        Button { visible: greeterRow.state === "outdated"; label: "Update"; onClicked: { greeterRow.status = "Updating…"; greeterUpdate.running = true; } }
                        Button { visible: greeterRow.installed; label: "Sync now"; onClicked: { greeterRow.status = "Updating…"; greeterSyncNow.running = true; } }
                    }
                }
            }
            GroupLabel { text: "When you're away" }
            Group {
                ChoiceSetting {
                    label: "Lock after"
                    options: lockCol.minutes
                    value: Config.s.idleLockMinutes
                    onPicked: v => Config.s.idleLockMinutes = v
                }
                Separator {}
                ChoiceSetting {
                    label: "Turn the screen off after"
                    detail: "Moving the mouse or pressing a key turns it back on"
                    options: lockCol.minutes
                    value: Config.s.idleScreenOffMinutes
                    onPicked: v => Config.s.idleScreenOffMinutes = v
                }
                Separator {}
                ChoiceSetting {
                    label: "Suspend after"
                    options: lockCol.minutes
                    value: Config.s.idleSuspendMinutes
                    onPicked: v => Config.s.idleSuspendMinutes = v
                }
                Separator {}
                SettingRow {
                    label: "Wait while media plays"
                    detail: "Don't count as away while a video or app is keeping the screen awake"
                    Toggle { checked: Config.s.idleRespectInhibitors; onToggled: v => Config.s.idleRespectInhibitors = v }
                }
            }
        }
    }

    Component {
        id: hotCornersPage
        Column {
            id: hcCol
            spacing: 4
            readonly property var actions: [
                { value: "none", label: "Nothing" },
                { value: "lock", label: "Lock screen" },
                { value: "launcher", label: "App launcher" },
                { value: "overview", label: "Workspace overview" },
                { value: "control", label: "Control centre" },
                { value: "notifications", label: "Notifications" },
                { value: "screenoff", label: "Turn screen off" }
            ]
            PageTitle { text: "Hot corners" }
            Text {
                width: Math.min(parent.width, win.introMeasure)
                text: "Rest the pointer in a corner of the screen to run an action."
                color: win.dim; font.family: win.font; font.pixelSize: 13
                wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
            }
            // The screen, with each corner's action; click one to set it below
            property string corner: "TopLeft"
            readonly property string cornerName: ({ TopLeft: "Top left", TopRight: "Top right", BottomLeft: "Bottom left", BottomRight: "Bottom right" })[corner]
            Group {
                Item {
                    width: parent.width
                    height: cornerPicker.height + 24
                    HotCornerPicker {
                        id: cornerPicker
                        anchors.centerIn: parent
                        width: Math.min(420, parent.width - 24)
                        selected: hcCol.corner
                        actions: hcCol.actions
                        accent: win.accent; textColor: win.text; dimColor: win.dim
                        fontFamily: win.font; iconFont: win.bar.iconFont
                        onPicked: c => hcCol.corner = c
                    }
                }
                Separator {}
                DropdownSetting {
                    label: hcCol.cornerName
                    detail: "What resting the pointer in this corner does"
                    options: hcCol.actions
                    value: Config.s["hotCorner" + hcCol.corner]
                    onPicked: v => Config.s["hotCorner" + hcCol.corner] = v
                }
            }
            GroupLabel { text: "Timing" }
            Group {
                SettingRow {
                    label: "Delay"
                    detail: "How long to rest in the corner before it triggers"
                    ValueSlider { from: 0; to: 1500; stepSize: 50; suffix: " ms"; value: Config.s.hotCornerDelay; onMoved: v => Config.s.hotCornerDelay = v }
                }
            }
        }
    }

    Component {
        id: bluetoothPage
        Column {
            id: bt
            spacing: 4
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) =>
                (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || "")) : []
            function deviceIcon(d) {
                const i = (d.icon || "").toLowerCase();
                if (i.includes("headset") || i.includes("headphone") || i.includes("audio")) return 0xEABD;
                if (i.includes("gam") || i.includes("joystick")) return 0xF1D2;
                if (i.includes("mouse")) return 0xEAF9;
                if (i.includes("keyboard")) return 0xEBD6;
                if (i.includes("phone")) return 0xEA8A;
                return 0xEA37;
            }

            PageTitle { text: "Bluetooth" }
            Group {
                SettingRow {
                    label: "Bluetooth"
                    detail: bt.adapter ? (bt.adapter.enabled ? "On" : "Off") : "No Bluetooth adapter found"
                    Toggle { visible: !!bt.adapter; checked: bt.adapter ? bt.adapter.enabled : false; onToggled: v => { if (bt.adapter) bt.adapter.enabled = v; } }
                }
                Separator { visible: bt.adapter && bt.adapter.enabled }
                SettingRow {
                    visible: bt.adapter && bt.adapter.enabled
                    label: "New devices"
                    detail: bt.adapter && bt.adapter.discovering ? "Searching… put your device in pairing mode" : "Find nearby devices to pair"
                    Row {
                        spacing: 10
                        Text {
                            visible: bt.adapter && bt.adapter.discovering
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.glyph(0xF226)
                            color: win.accent
                            font.family: win.bar.iconFont; font.pixelSize: 16
                            RotationAnimation on rotation { running: parent.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                        Button {
                            icon: 0xEA37
                            label: bt.adapter && bt.adapter.discovering ? "Stop" : "Search"
                            primary: !(bt.adapter && bt.adapter.discovering)
                            onClicked: if (bt.adapter) bt.adapter.discovering = !bt.adapter.discovering
                        }
                    }
                }
            }
            GroupLabel { visible: bt.adapter && bt.adapter.enabled; text: "Devices" }
            Group {
                visible: bt.adapter && bt.adapter.enabled
                Text {
                    visible: bt.devices.length === 0
                    x: 16; height: 48; verticalAlignment: Text.AlignVCenter
                    text: "No devices yet"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
                Repeater {
                    model: bt.devices
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property var d: modelData
                        width: parent.width
                        height: 60
                        Rectangle { visible: index > 0; width: parent.width - 32; x: 16; height: 1; color: Config.tint("#262c35") }
                        Rectangle {
                            id: devIcon
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: 9
                            color: d.connected ? win.accent : Config.tint("#2a313c")
                            Text {
                                anchors.centerIn: parent
                                text: win.glyph(bt.deviceIcon(d))
                                color: d.connected ? win.accentText : win.text
                                font.family: win.bar.iconFont; font.pixelSize: 17
                            }
                        }
                        Column {
                            anchors { left: devIcon.right; leftMargin: 12; right: devButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; text: d.name || d.deviceName || d.address; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                            Text {
                                width: parent.width
                                text: d.pairing ? "Pairing…"
                                    : d.connected ? "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "% battery" : "")
                                    : d.paired ? "Paired" : "Not paired"
                                color: d.connected ? win.accent : win.dim
                                font.family: win.font; font.pixelSize: 12
                            }
                        }
                        Row {
                            id: devButtons
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Button {
                                visible: d.paired || d.bonded
                                label: d.connected ? "Disconnect" : "Connect"
                                primary: !d.connected
                                onClicked: d.connected ? d.disconnect() : d.connect()
                            }
                            Button {
                                visible: !(d.paired || d.bonded)
                                label: d.pairing ? "Cancel" : "Pair"
                                primary: !d.pairing
                                onClicked: d.pairing ? d.cancelPair() : d.pair()
                            }
                            Button {
                                visible: d.paired || d.bonded
                                label: "Forget"
                                destructive: true
                                onClicked: d.forget()
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: updatesPage
        Column {
            id: upd
            spacing: 4
            // A second click confirms (updating over files you've changed; going back)
            property bool confirmUpdate: false
            property bool confirmRevert: false
            readonly property var mod: Updates.modified
            readonly property var touched: mod && mod.known ? mod.changed.concat(mod.added) : []
            readonly property string latest: Updates.latest
            function when(iso) { return iso ? Qt.formatDate(new Date(iso), "d MMMM yyyy") : ""; }
            function ago(ms) {
                const m = Math.max(0, Math.round((Date.now() - ms) / 60000));
                return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Qt.formatDate(new Date(ms), "d MMM");
            }
            // "v0.4.2-15-gabc123" (a copy of the code past a release) reads as "v0.4.2 + 15 changes"
            function nice(v) {
                const m = /^(v[\d.]+)-(\d+)-g/.exec(v || "");
                return m ? m[1] + " + " + m[2] + " changes" : v;
            }
            Component.onCompleted: { Updates.check(false); Updates.findModified(); }

            PageTitle { text: "Updates" }
            Text {
                width: Math.min(parent.width, win.introMeasure)
                text: "Slate looks for a new version once a day and lets you know with a notification. Updating keeps your settings and your own tweaks (settings.json, hypr/ and user/ in ~/.config/slate), and keeps the version you had, so you can go back to it."
                color: win.dim; font.family: win.font; font.pixelSize: 13
                wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
            }
            Group {
                SettingRow {
                    label: "Installed version"
                    detail: Updates.installed === "" ? "Unknown: this copy of Slate wasn't installed with a version"
                        : upd.nice(Updates.installed)
                }
                Separator {}
                SettingRow {
                    label: Updates.available ? "Slate " + upd.latest + " is available" : "Latest version"
                    detail: Updates.checking ? "Checking…"
                        : Updates.error !== "" && Updates.status !== "failed" ? Updates.error
                        : upd.latest === "" ? "Not checked yet"
                        : (Updates.available ? "Released " + upd.when(Updates.state.published) : upd.latest + ": you're up to date")
                          + (Updates.checkedAt > 0 ? " · checked " + upd.ago(Updates.checkedAt) : "")
                    Button { label: Updates.checking ? "Checking…" : "Check now"; icon: 0xEB13; onClicked: Updates.check(true) }
                }
                Separator {}
                SettingRow {
                    label: "Check for updates"
                    detail: "Once a day, with a notification when there's a new version"
                    Toggle { checked: Config.s.updateCheck; onToggled: v => Config.s.updateCheck = v }
                }
            }

            // ---- A new version: what's new, and updating ----
            GroupLabel {
                visible: Updates.available || Updates.busy || Updates.status === "failed"
                text: "What's new in " + upd.latest
            }
            Group {
                visible: Updates.available || Updates.busy || Updates.status === "failed"
                Text {
                    x: 16; width: parent.width - 32
                    visible: Updates.notes !== ""
                    topPadding: 12; bottomPadding: 8
                    text: Updates.notes
                    textFormat: Text.MarkdownText
                    color: win.text; linkColor: win.accent
                    font.family: win.font; font.pixelSize: 13
                    wrapMode: Text.Wrap
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }
                Separator { visible: Updates.notes !== "" }
                // Slate's own files changed by hand: an update replaces them (the old copy is kept)
                Text {
                    x: 16; width: parent.width - 32
                    visible: upd.touched.length > 0 && !Updates.busy
                    topPadding: 12; bottomPadding: 4
                    text: "You've changed some of Slate's own files, outside settings.json, hypr/ and user/. Updating replaces them; your versions stay in ~/.config/slate.previous:\n"
                        + upd.touched.slice(0, 8).map(f => "  · " + f).join("\n")
                        + (upd.touched.length > 8 ? "\n  · and " + (upd.touched.length - 8) + " more" : "")
                    color: win.danger; font.family: win.font; font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                SettingRow {
                    label: Updates.status === "downloading" ? "Downloading " + upd.latest + "…"
                        : Updates.status === "installing" ? "Installing " + upd.latest + "…"
                        : Updates.status === "failed" ? "The update didn't finish"
                        : "Update to " + upd.latest
                    detail: Updates.status === "installing" ? "Slate restarts on the new version when it's done"
                        : Updates.status === "failed" ? Updates.error
                        : upd.confirmUpdate ? "Your changed files above will be replaced. Click again to update"
                        : "Takes a moment; Slate restarts on the new version"
                    Row {
                        spacing: 8
                        Button { visible: Updates.url !== ""; label: "Release page"; icon: 0xEA99; onClicked: Qt.openUrlExternally(Updates.url) }
                        Button {
                            visible: Updates.status === "failed" && Updates.state.log !== undefined
                            label: "Show log"
                            onClicked: Quickshell.execDetached(["xdg-open", Updates.state.log])
                        }
                        Button {
                            visible: !Updates.busy
                            primary: true
                            icon: 0xEA96
                            label: Updates.status === "failed" ? "Try again" : upd.confirmUpdate ? "Update anyway" : "Update now"
                            onClicked: {
                                if (upd.touched.length > 0 && !upd.confirmUpdate) { upd.confirmUpdate = true; return; }
                                upd.confirmUpdate = false;
                                Updates.install();
                            }
                        }
                    }
                }
            }

            // ---- Just updated, or went back ----
            Group {
                visible: Updates.status === "done" || Updates.status === "reverted"
                SettingRow {
                    label: Updates.status === "done" ? "Updated to " + upd.nice(Updates.installed) : "Back on " + upd.nice(Updates.installed)
                    detail: Updates.status === "done" ? (Updates.note !== "" ? Updates.note : "Your settings and tweaks came along. The version before is kept, below")
                        : "Your settings and tweaks stayed as they were. The version you left is kept, below"
                    Button { visible: Updates.status === "done" && Updates.url !== ""; label: "What's new"; icon: 0xEA99; onClicked: Qt.openUrlExternally(Updates.url) }
                }
            }

            // ---- The version kept as a backup ----
            GroupLabel { visible: Updates.previous !== ""; text: "Previous version" }
            Group {
                visible: Updates.previous !== ""
                SettingRow {
                    label: "Go back to " + (Updates.previous === "unknown" ? "the previous version" : upd.nice(Updates.previous))
                    detail: upd.confirmRevert ? "Click again to switch. Your settings and tweaks stay as they are now"
                        : "Kept in ~/.config/slate.previous. Your settings and tweaks stay as they are now, and the version you leave is kept instead, so you can switch back"
                    Button {
                        enabled: !Updates.busy
                        label: upd.confirmRevert ? "Go back now" : "Go back"
                        onClicked: {
                            if (!upd.confirmRevert) { upd.confirmRevert = true; return; }
                            upd.confirmRevert = false;
                            Updates.revert();
                        }
                    }
                }
            }
        }
    }

    Component {
        id: aboutPage
        Column {
            spacing: 4
            PageTitle { text: "About Slate" }
            SlateLogo { size: 64; x: 4; textColor: win.text }
            Item { width: 1; height: 10 }
            Text {
                width: Math.min(parent.width, win.introMeasure)
                text: "Slate is this desktop's shell: the bar, dock, launcher, window and workspace switchers, panels, notifications and these settings. It runs on Quickshell and Hyprland, from ~/.config/slate."
                color: win.dim; font.family: win.font; font.pixelSize: 13
                wrapMode: Text.Wrap
                leftPadding: 4; bottomPadding: 10
            }
            Group {
                SettingRow {
                    label: "Welcome"
                    detail: "The introduction from Slate's first start, with its recommended choices"
                    Button {
                        label: "Show the welcome"
                        onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "welcome", "open"]); }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Settings file"
                    detail: "settings.json in ~/.config/slate"
                    Button { label: "Open file"; onClicked: Quickshell.execDetached(["xdg-open", Qt.resolvedUrl("settings.json").toString()]) }
                }
                Separator {}
                SettingRow {
                    label: "Restart the shell"
                    detail: "Reloads the bar, dock, launcher, switchers and notifications"
                    Button { label: "Restart"; onClicked: Quickshell.reload(true) }
                }
            }
        }
    }
}
