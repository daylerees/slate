// Slate's Settings app: every page of settings (SettingsIndex.pages), styled like the rest of
// the shell. Values live in Config (settings.json).
// Open with:  slate ipc call settings toggle   (also Super+Z and the control centre gear)

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel

FloatingWindow {
    id: win
    required property var bar
    property var notifs: null
    // Slate's confirmation window (PowerConfirm: confirmWith), for questions asked as the rest
    // of Slate asks them (installing an app)
    property var confirmer: null

    title: "Slate Settings"
    // 880×620, or less on a small screen (Hyprland centres it at the size it asks for)
    readonly property var fitScreen: Config.focusedScreen
    // The window's size on a screen, in Slate's units (before rounding)
    function fitSize(scr) { return Qt.size(Math.min(880, scr.width * 0.9), Math.min(620, (scr.height - 60) * 0.9)); }
    implicitWidth: Math.round(fitScreen ? fitSize(fitScreen).width : 880)
    implicitHeight: Math.round(fitScreen ? fitSize(fitScreen).height : 620)
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
            const size = win.fitSize(win.screen);
            const w = Math.round(size.width * Config.uiScale);
            const h = Math.round(size.height * Config.uiScale);
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
        if (!visible) cancelConfirm();        // closing Settings answers an open question with Cancel
        if (!visible) dropLayer.owner = null; // and closes an open dropdown (its page is let go)
        if (visible && !keepSection) section = "overview";
        // Cleared a moment later, not now: showing the window can report "visible" twice,
        // and the second would otherwise send a requested page back to All Settings
        if (visible) keepClear.restart(); else keepSection = false;
        placeSave.restart();                  // open: where it is; closed: forgotten
    }

    IpcHandler {
        target: "settings"
        // (open on another workspace, toggle brings it here rather than closing it out of sight)
        function toggle(): void { if (win.visible && !win.isHere()) win.show(); else win.visible = !win.visible; }
        function open(): void { win.show(); }
        function close(): void { win.visible = false; }
        // Old page names still work: switchers → windows, wallpaper → appearance (at the wallpapers)
        function page(name: string): void {
            if (name === "wallpaper") win.scrollTo = "wallpaper";
            win.keepSection = !win.visible;
            win.section = ({ switchers: "windows", wallpaper: "appearance" })[name] ?? name;
            win.show();
        }
        // Open a page scrolled to one setting (or heading), lit up for a moment, e.g.
        //   slate ipc call settings find appearance "Interface size"
        function find(page: string, label: string): void { win.goTo(page, label); }
        // Open General with the account picture chooser showing (the control centre's avatar)
        function avatar(): void { win.keepSection = !win.visible; win.section = "general"; win.avatarPicking = true; win.show(); }
    }

    // ---- Look --------------------------------------------------------------
    readonly property color card: bar.capsuleColor
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: bar.errorColor
    // Buttons, switches, fields and other controls: solid grey, or with glass the frosted fill the
    // bar's containers have (a hint of the wallpaper's colour), so their sheen picks it up too
    readonly property color control: Config.raised(Config.tint("#2a313c"))
    // (a button or a field under the pointer: the muted hover, as everywhere, with glass or without)
    function controlHover(solid) { return Config.hover; }
    // The theme's greys, named for what they're used for (each worked out once, not per item)
    readonly property color well: Config.tint("#151920")           // sunken areas: the content pane, search wells, segmented tracks
    readonly property color divider: Config.tint("#262c35")        // separators, chosen rows, meter tracks
    readonly property color outline: Config.tint("#2a313c")        // borders, idle icon tiles
    readonly property color popupFill: Config.tint("#1d222a")      // dropdown menus and other pop-ups
    readonly property color controlHoverSolid: Config.tint("#323a46")  // a button under the pointer (without glass)
    readonly property color knobHover: Config.tint("#38414e")      // a switch or slider track under the pointer (without glass)
    readonly property color ring: Config.tint("#3a424e")           // the outline round a swatch or picture
    readonly property color faint: Qt.rgba(text.r, text.g, text.b, 0.06)   // a whisper of the text colour, for flat fills
    // A text field or dropdown under the pointer
    function fieldHover() { return controlHover(Config.hoverOn(outline)); }
    readonly property string font: bar.fontFamily
    function glyph(code) { return String.fromCodePoint(code); }
    // Dropdown choices every half hour, from one hour to another (halfHours(16, 23.5): 16:00,
    // 16:30 … 23:30), for night light's schedule
    function halfHours(from, to) {
        const out = [];
        for (let t = from; t <= to; t += 0.5) {
            const v = String(Math.floor(t)).padStart(2, "0") + (t % 1 ? ":30" : ":00");
            out.push({ value: v, label: v });
        }
        return out;
    }
    // Dropdown choices for a number of minutes (0 is "Never")
    function minuteOptions(list) { return list.map(m => ({ value: m, label: m === 0 ? "Never" : m + (m === 1 ? " minute" : " minutes") })); }

    property string section: "overview"
    // While the menu bar's being arranged (Edit layout on its page), Settings steps out of the
    // way, and comes back, on the page it was on, when that's done
    property bool awayForBar: false
    Connections {
        target: Config
        function onBarArrangingChanged() {
            if (Config.barArranging) { if (win.visible) { win.awayForBar = true; win.visible = false; } }
            else if (win.awayForBar) { win.awayForBar = false; win.keepSection = true; win.show(); }
        }
    }
    readonly property int scrolledTo: Math.round(scroller.contentY)   // (tests: the "test" IPC)

    // ---- Back where it was after Slate reloads or restarts ----------------
    // While Settings is open, its page and how far down it's scrolled are kept in the runtime
    // folder, named for this Hyprland session (so logging in again never opens it); closing it
    // forgets them. When Slate starts again with them there, Settings reopens just as it was.
    readonly property string placeFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate/settings-open-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none") + ".json"
    // (restored once it has loaded: read straight away as Settings was made, it could still be
    // loading, so Settings came back on All Settings)
    FileView {
        id: placeView
        path: win.placeFile
        blockLoading: true
        printErrors: false
        onLoaded: win.restoreFromFile()
        onLoadFailed: win.placeReady = true     // nothing saved (Settings wasn't open)
    }
    property real restoreY: -1           // scroll back to this once the page has loaded
    property bool placeReady: false      // not saving until any earlier place has been read
    function savePlace() {
        if (!placeReady) return;
        placeView.setText(JSON.stringify(visible ? { section: section, y: Math.round(scroller.contentY) } : {}));
    }
    // Saved a moment after a change, which also means a window that's closing only because Slate
    // is reloading (and going away with it) doesn't forget the place first
    Timer { id: placeSave; interval: 400; onTriggered: win.savePlace() }
    // Scrolls back to restoreY once the page is laid out (from the page loading, or straight away
    // when it's the page already showing)
    function restorePlace() {
        if (restoreY <= 0) { restoreY = -1; return; }
        const y = restoreY;
        restoreY = -1;
        Qt.callLater(() => Qt.callLater(() => { scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, y)); }));
    }
    Component.onCompleted: if (placeView.loaded) restoreFromFile()
    function restoreFromFile() {
        if (placeReady) return;                 // (once, at start)
        let p = null;
        try { p = JSON.parse(placeView.text() || "{}"); } catch (e) {}
        placeReady = true;
        if (p && p.section) {
            keepSection = true;
            restoreY = Number(p.y) || 0;       // before the page changes: it loads straight away
            if (section === p.section) restorePlace(); else section = p.section;
            visible = true;
        }
    }

    // Opening Settings starts on All Settings, unless it was asked for a page (keepSection)
    property bool keepSection: false
    Timer { id: keepClear; interval: 600; onTriggered: win.keepSection = false }
    // A setting to scroll to and light up once its page has loaded (goTo)
    property string findLabel: ""
    function goTo(page, label) {
        keepSection = !visible;           // (only matters while opening: see onVisibleChanged)
        findLabel = label || "";
        if (section === page && pageLoader.item) Qt.callLater(showFound);
        section = page;
        show();
    }
    // Show Settings. Already open on another workspace: it moves to the one you're on (and
    // takes the focus), rather than staying out of sight there
    function show() {
        if (!visible) { visible = true; return; }
        const ws = Hyprland.focusedWorkspace;
        if (!ws || ws.id < 1 || isHere()) return;        // (not to the secret workspace)
        const window = "title:^(Slate Settings)$";
        Quickshell.execDetached(["hyprctl", "dispatch", `function() hl.dispatch(hl.dsp.window.move({ workspace = ${ws.id}, window = "${window}", follow = false })); hl.dispatch(hl.dsp.focus({ window = "${window}" })) end`]);
    }
    // Whether Settings is on the workspace you're looking at
    function isHere() {
        const mine = Hyprland.toplevels.values.find(t => t.title === "Slate Settings");
        return !mine || !mine.workspace || !Hyprland.focusedWorkspace || mine.workspace.id === Hyprland.focusedWorkspace.id;
    }
    function showFound() {
        const label = findLabel || foundRetryLabel;
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
        // Not there yet (rows a page makes once it's loaded something, like App theming's
        // apps): look again for a moment
        if (!hit) {
            if (foundRetryLabel !== label) { foundRetryLabel = label; foundTries = 0; }
            if (++foundTries <= 10) foundRetry.restart(); else foundRetryLabel = "";
            return;
        }
        foundRetryLabel = "";
        foundItem = hit;
        foundAt = Date.now();
        placeFound();
        Qt.callLater(() => { placeFound(); foundFade.restart(); });
    }
    // The found setting, kept in view and lit up while the highlight shows. Things above it on
    // the page can finish loading after the jump (pictures, lists) and push it down, so this
    // follows it, rather than staying where it first was (which left it lit too high)
    property string foundRetryLabel: ""
    property int foundTries: 0
    Timer { id: foundRetry; interval: 100; onTriggered: win.showFound() }
    property Item foundItem: null
    property real foundAt: 0
    function placeFound() {
        const hit = foundItem;
        if (!hit || !pageLoader.item) return;
        // Scrolled to it for the first moment only, so it doesn't fight you scrolling away
        if (Date.now() - foundAt < 1000) {
            const p = hit.mapToItem(pageLoader.item, 0, 0);
            scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, p.y - 40));
        }
        const q = hit.mapToItem(contentPane, 0, 0);
        foundFlash.x = q.x - 6; foundFlash.y = q.y - 4;
        foundFlash.width = Math.min(hit.width + 12, contentPane.width - foundFlash.x - 8); foundFlash.height = hit.height + 8;
    }
    Timer { interval: 40; repeat: true; running: foundFade.running; onTriggered: win.placeFound() }
    // Choosing your account picture: its own window (AvatarPicker.qml), opened from General or
    // the control centre's picture
    property bool avatarPicking: false
    onAvatarPickingChanged: if (avatarPicking) avatarPicker.open()
    AvatarPicker {
        id: avatarPicker
        bar: win.bar
        onVisibleChanged: if (!visible) win.avatarPicking = false
    }
    property string scrollTo: ""           // a part of the next page to scroll to ("wallpaper")
    // The settings each page can restore to their defaults. Left out on purpose: your
    // location and night light on/off (General), and the chosen wallpaper (Appearance)
    readonly property var pageKeys: ({
        datetime: ["dateFormat", "weekStart", "temperatureUnit"],
        general: ["clipboardHistory", "nightLightTemperature", "nightLightSchedule", "nightLightFrom", "nightLightTo"],
        appearance: ["themeMode", "lightMode", "colourStyle", "accentFromWallpaper", "accentBoldness", "accent", "toneFromWallpaper", "toneBoldness", "roundedScreenCorners",
            "animations", "glass", "glassOpacity", "glassBlur", "glassGloss", "glassGlossTint", "fastBlur", "blurPasses", "iconShape", "iconFill", "iconTileColour", "tintIcons", "iconTintStrength", "folderColour", "fontFamily", "codeFontFamily", "uiScale",
            "wallpaperFolder", "wallpaperChange", "wallpaperHideSmall", "wallpaperMinSize", "wallpaperShowSlate"],
        bar: ["barPosition", "barLayout", "barOverflow", "barStay", "barBlur", "barOpacity", "barPanelBlur", "barPanelOpacity", "barItemOpacity", "barItemHoverOpacity", "barAutoHide", "barHoverDescriptions", "barShowControl", "barShowClock", "barShowApps", "barShowSpaces", "barShowAssistant", "barShowWorkspaces", "barShowWindowMode", "barShowTitle", "barShowTitleIcon",
            "barShowTray", "barTrayMono", "barShowNotifications", "barShowClipboard", "barShowScreenshot", "barShowGameMode", "barShowWifi", "barShowKeyboard", "barShowBluetooth", "barShowVolume", "barShowBattery", "barValueClipboard", "barValueGameMode", "barValueWifi", "barValueKeyboard", "barValueBluetooth", "barValueVolume", "barValueBattery", "barTrayCollapsed", "barStatusCollapsed",
            "barShowPower", "barClockFormat", "barClockSeconds", "barClockDate"],
        dock: ["dockPosition", "dockAutoHide", "dockShowLauncher", "dockPreviews", "dockPreviewDelay", "dockBadges", "dockDivider", "dockShowMedia", "dockMediaArt", "dockShowDownloads", "dockShowTrash", "dockIconSize", "dockHoverEffect", "dockMagnification", "dockSpread", "dockBlur", "dockOpacity", "dockTileOpacity", "dockIconOpacity"],
        launcher: ["launcherLayout", "launcherColumns", "launcherRows", "launcherDescriptions", "launcherSortByUsage",
            "launcherWrap", "launcherRecent", "launcherFuzzy", "launcherWindows", "launcherActions", "launcherToggles", "launcherFiles",
            "launcherConvert", "launcherCommands", "launcherEmoji", "launcherWeb", "launcherSearchEngine"],
        debug: ["logLevel"],
        displays: ["mainDisplay"],
        input: ["kbLayouts", "kbVariants", "kbSwitch", "capsLock", "keyRepeatDelay", "keyRepeatRate", "mouseSpeed", "mouseAccel",
            "mouseNaturalScroll", "cursorSize", "touchpadScrollSpeed", "touchpadNaturalScroll", "touchpadTapToClick",
            "touchpadIgnoreWhileTyping"],
        sound: ["tickVolume", "notificationVolume", "clickVolume", "swishVolume", "welcomeVolume", "goodbyeVolume", "attentionVolume",
            "volumeSound", "notificationSound", "clickSound", "swishSound", "welcomeSound", "goodbyeSound", "soundEffectsVolume"],
        power: ["lidAction", "powerKeyAction", "profileOnBattery", "profileOnAC", "reopenAppsAfterRestart"],
        apps: ["defaultTerminal", "defaultBrowser", "defaultFileManager", "defaultEditor", "defaultCalculator"],
        startup: ["startupApps"],
        screenshots: ["screenshotAfter", "screenshotFolder", "screenshotName"],
        windows: ["windowMode", "focusFollowsMouse", "titleBarStyle", "titleButtons", "windowBorderSize", "windowGap", "soloWindowGap", "inactiveDim", "switcherPreviews", "switcherAppIcons",
                  "switcherMoveAnimation", "switcherPickAnimation"],
        workspaces: ["workspaceAnimation", "workspaceSwitchName", "wrapWorkspaces", "keepEmptyWorkspace", "workspaceShape", "overviewCardWidth", "overviewPreviews", "overviewAppIcons",
                     "overviewMoveAnimation", "overviewPickAnimation", "overviewGridSize"],
        spaces: ["barShowSpaces", "spaceBarTint", "spaceBorders", "spaceBadges", "spaceSwitcherBadges"],
        hotcorners: ["hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight", "hotCornerDelay"],
        notifications: ["notificationPosition", "notificationSeconds", "notificationMaxToasts"],
        screensaver: ["screensaverMinutes", "screensaverStyle", "screensaverClock", "screensaverSlideSeconds", "screensaverLock"],
        shortcuts: ["keyset"],
        updates: ["updateCheck"],
        assistant: ["assistantEnabled", "assistantRisksAccepted", "assistantAgent", "assistantModel", "assistantCommand", "assistantCommandBare", "assistantAgentsAccepted", "assistantKeepChat", "assistantAskChanges", "assistantSeeTitles", "assistantSeeNotifications"],
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
    // A page whose settings aren't Slate's own (Webcam: the camera's) hooks its reset into the
    // title's Restore defaults: whether anything's changed, and what puts it back
    property bool pageResetChanged: false
    property var pageResetRun: null
    // Any other question for the confirmation card: { title, body, button, run, cancel (optional),
    // cancelLabel (optional: the other button's label, when it's a choice rather than backing out),
    // destructive (optional: a red button Enter doesn't press), option (optional: { label, detail },
    // a switch on the card, off to start; run gets whether it's on) }.
    // Esc, Cancel, clicking outside or changing page all count as cancelling. The card keeps
    // showing the last one while it fades out
    property var ask: null
    property var lastAsk: null
    property bool askOption: false
    onAskChanged: {
        if (!ask) return;
        // Asked in Slate's confirmation window, like the rest of Slate; this window's own card
        // only when that isn't there
        if (confirmer) { const q = ask; ask = null; askInConfirmer(q); return; }
        lastAsk = ask; askOption = false;
    }
    // A question { title, body, button, destructive?, code?, option?, run(optionOn), cancel? }
    function askInConfirmer(q) {
        confirmer.confirmWith({ title: q.title, body: q.body, button: q.button,
                                code: q.code || (q.destructive ? 0xEB41 : 0xEB13), danger: !!q.destructive, option: q.option || null,
                                cancelLabel: q.cancelLabel || "" },
                              v => { if (q.run) q.run(v); }, q.cancel || null);
    }
    // Settings → Lock & Idle → Slate login screen. It's optional (nothing installs it unless you
    // ask), so installing says plainly what can go wrong and what keeping it working takes
    readonly property var loginScreenInstallQuestion: ({
        title: "Install Slate's login screen?",
        body: "This replaces your computer's login screen, which lives outside Slate, so it needs your password. "
            + "If it breaks, it can stop you logging in: Slate tests every copy before installing it and keeps a basic "
            + "fallback, and you can always press Ctrl+Alt+F3, log in as text and run "
            + "sudo ~/.config/slate/bin/slate-greeter-install --revert. "
            + "Changes to Slate and updates to Hyprland, Quickshell or greetd can need it updated; Slate asks when, "
            + "and each update needs your password.",
        button: "Install", code: 0xEAE2
    })
    readonly property var loginScreenUpdateQuestion: ({
        title: "Update the login screen?",
        body: "Slate will copy its latest login screen into place, which needs your password. It's tested first, "
            + "so if anything's wrong, nothing changes. You'll see it at your next logout or restart.",
        button: "Update", code: 0xEAE2
    })
    // Settings → Assistant → Let assistants use Slate. Switching on doesn't switch it on: it
    // shows the risks first, in plain words, and only "Switch on" does it, recording which
    // version of them was accepted (Config.assistantOn needs both). Best efforts, said as such
    readonly property string assistantDocs: "https://github.com/daylerees/slate/blob/master/docs/ASSISTANT.md#before-you-switch-it-on"
    readonly property string assistantRisks: (Config.assistantRisksChanged ? "Something's changed about the assistant since you switched it on, so here it is again.<br><br>" : "Before you do, here's what it means.<br><br>")
        + "<b>What leaves your computer.</b> What you type, and what Slate tells the assistant about your desktop "
        + "(your settings, your open windows and their titles), goes to the service behind the agent you choose, under your own account with them.<br><br>"
        + "<b>What it can do.</b> It can change settings and move windows without asking. Slate asks you before anything that can't be undone.<br><br>"
        + "<b>What can go wrong.</b> Assistants make mistakes, and can be misled by text they read, like the title of a web page. "
        + "Slate does its best to limit the harm, but it can't promise what an assistant will do, least of all one that keeps tools of its own.<br><br>"
        + "Using the assistant is your choice, and what it does on your behalf is your responsibility. You can switch it off at any time. "
        + "<a href=\"" + assistantDocs + "\">Read more</a>"
    function assistantAccept() {
        Config.s.assistantRisksAccepted = Config.assistantRisksVersion;
        Config.s.assistantEnabled = true;
    }
    function assistantSwitch(on) {
        if (!on) { Config.s.assistantEnabled = false; return; }
        if (!confirmer) return;
        confirmer.confirmWith({ title: "Switch on the assistant?", body: assistantRisks, long: true,
                                button: "Switch on", code: 0xF38A, danger: false }, () => assistantAccept());
    }
    // Choosing which agent answers the prompt window. One Slate can't confine (it keeps tools
    // of its own: a command of your own always does) asks once, per agent
    function assistantChoose(id, label, confined) {
        const accepted = Config.s.assistantAgentsAccepted || [];
        if (confined || accepted.indexOf(id) >= 0 || !confirmer) { Config.s.assistantAgent = id; return; }
        const own = id === "custom";
        confirmer.confirmWith({
            title: own ? "Use your own command?" : "Use " + label + "?",
            body: (own ? "Slate runs your command as you typed it and can't limit what it does, so it can do more than Slate's tools allow: "
                       : "Slate can't switch off " + label + "'s own tools, so it can do more than Slate's tools allow: ")
                + "run commands, read your files, see your screen. Slate's questions and limits only cover Slate's own tools. "
                + "If you use it, that's yours to answer for.",
            button: "Use it", code: 0xF38A, danger: false
        }, () => { Config.s.assistantAgentsAccepted = accepted.concat([id]); Config.s.assistantAgent = id; });
    }
    // Read the risks again, while it's on: the same words, and the chance to think again
    function assistantReadRisks() {
        if (!confirmer) return;
        confirmer.confirmWith({ title: "What using the assistant means", body: assistantRisks.replace("Before you do, here's what it means.<br><br>", ""), long: true,
                                button: "Keep it on", cancelLabel: "Switch off", code: 0xF38A, danger: false },
                              () => {}, () => { Config.s.assistantEnabled = false; });
    }
    // Restore defaults (the title button): asks first
    function askRestoreDefaults() {
        if (!confirmer) { confirmReset = true; return; }
        confirmer.confirmWith({
            title: "Restore " + pageTitle + " defaults?",
            body: changedHere + (changedHere === 1 ? " setting on this page goes" : " settings on this page go")
                + " back to how Slate starts out. Your other pages are left just as they are."
                + (resetRestarts ? " Slate restarts to apply them; your apps and windows stay open." : ""),
            button: "Restore defaults", code: 0xEB13, danger: false
        }, () => { restoreDefaults(); countChanged(); });
    }
    // A follow-up question (asking again, more seriously): shown once the card has faded out, so
    // it's clearly a new one, with its own attention sound
    property var nextAsk: null
    function askAfter(q) { nextAsk = q; nextAskTimer.restart(); }
    Timer { id: nextAskTimer; interval: 260; onTriggered: { win.ask = win.nextAsk; win.nextAsk = null; } }
    readonly property bool confirming: !confirmer && (confirmReset || ask !== null)
    onConfirmingChanged: if (confirming) Config.attention()
    function closeConfirm() { confirmReset = false; ask = null; }
    function cancelConfirm() { const c = ask && ask.cancel; closeConfirm(); if (c) c(); }
    // Restoring defaults that restarts Slate to apply them (Interface size, Log detail)
    readonly property bool resetRestarts: (currentKeys.includes("uiScale") && Math.abs(Config.s.uiScale - 1) > 0.001)
        || (currentKeys.includes("logLevel") && (Config.s.logLevel || "normal") !== "normal")
    onSectionChanged: {
        if (section !== "general") avatarPicking = false;
        cancelConfirm();
        if (visible) placeSave.restart();     // remember the page (see savePlace)
    }
    property string pageTitle: ""
    // Descriptions wrap at a comfortable reading length (~70 characters of the UI font)
    FontMetrics { id: detailMetrics; font.family: win.font; font.pixelSize: 12 }
    FontMetrics { id: introMetrics; font.family: win.font; font.pixelSize: 13 }
    readonly property real detailMeasure: detailMetrics.averageCharacterWidth * 70
    readonly property real introMeasure: introMetrics.averageCharacterWidth * 70
    // Every page (SettingsIndex.pages: id, label, icon, about, more)
    readonly property var sections: SettingsIndex.pages
    // Theme presets (Settings → Appearance → Presets): a named set of the Theme & colour and Glass
    // settings, applied together. Only those keys; lightMode follows themeMode
    // Slate Default: the same settings the other presets set (and light or dark), at Slate's
    // defaults, read from Config.defaultOf so it never falls out of step with them
    readonly property var presetKeys: ["themeMode", "lightMode", "colourStyle", "accentFromWallpaper", "accentBoldness", "accent",
        "toneFromWallpaper", "toneBoldness", "glass", "glassOpacity", "glassBlur", "glassGloss", "glassGlossTint", "folderColour"]
    readonly property var themePresets: [
        { name: "Slate Default", settings: presetKeys.reduce((o, k) => { const d = Config.defaultOf(k); if (d !== undefined) o[k] = d; return o; }, {}) },
        { name: "Liquid Glass", settings: Config.lookPresets["Liquid Glass"] },
        { name: "Metro Flat", settings: Config.lookPresets["Metro Flat"] }
    ]
    function presetActive(p) {
        for (const k in p.settings) {
            const a = Config.s[k], b = p.settings[k];
            if (typeof b === "number" ? Math.abs(Number(a) - b) > 0.001 : a !== b) return false;
        }
        return true;
    }
    // Restore defaults on the page showing. On Appearance that's Slate Default too, set by name
    // and checked again a moment later, so the preset reads Slate Default afterwards
    function restoreDefaults() {
        if (pageResetRun) pageResetRun();
        Config.resetKeys(currentKeys);
        if (section !== "appearance") return;
        const d = themePresets.find(p => p.name === "Slate Default");
        applyPreset(d);
        Qt.callLater(() => { if (!presetActive(d)) { console.warn("Slate Default didn't stick after Restore defaults; applying it again"); applyPreset(d); } });
    }
    // Dark | Light | Auto. Moving off Dark asks first, while light mode is still being polished
    function pickThemeMode(m) {
        if (m === Config.themeMode) return;
        if (m === "dark" || Config.themeMode !== "dark" || !Config.lightModeAsks) { Config.setThemeMode(m); return; }
        ask = Object.assign(Config.lightModeQuestion(m), { run: () => Config.setThemeMode(m) });
    }
    function applyPreset(p) {
        for (const k in p.settings) Config.s[k] = p.settings[k];
        if (p.settings.themeMode && p.settings.themeMode !== "auto") Config.s.lightMode = p.settings.themeMode === "light";
    }
    readonly property var sidebarSections: [{ id: "overview", label: "All Settings", icon: 0xEA03 }].concat(sections.filter(x => !x.more))
    readonly property var moreSections: sections.filter(x => x.more)
    // A page opened from All Settings: the sidebar keeps All Settings lit, and the title gets a back arrow
    readonly property bool onMorePage: moreSections.some(x => x.id === section)

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { if (win.confirming) win.cancelConfirm(); else if (dropLayer.owner) dropLayer.owner = null; else win.visible = false; }

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
                    spacing: 4                  // room between the pills for the page you're on and the one pointed at
                    // Slate's mark (as on the About page) beside the title; drag it to move the window
                    Item {
                        width: parent.width
                        height: logoRow.implicitHeight
                        Row {
                            id: logoRow
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
                        MouseArea { anchors.fill: parent; onPressed: win.startSystemMove() }
                    }
                    Repeater {
                        model: win.sidebarSections
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool current: win.section === modelData.id || (modelData.id === "overview" && win.onMorePage)
                            width: parent.width; height: 38; radius: 9
                            color: current ? win.accent : navHover.hovered ? Config.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            Text {
                                id: navIcon
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: win.glyph(parent.modelData.icon)
                                // Colourful: each page its own colour; monotone: the accent when current
                                // (on the page you're on, dark like its name: it sits on the active colour)
                                color: parent.current ? win.accentText : Config.colourful ? Config.pageColour(parent.modelData.id) : win.dim
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                font.family: win.bar.iconFont; font.pixelSize: 17
                            }
                            Text {
                                visible: !win.compact
                                anchors { left: navIcon.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: parent.modelData.label
                                color: parent.current ? win.accentText : win.dim
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                            }
                            HoverHandler { id: navHover }
                            ClickTap { onTapped: win.section = parent.modelData.id }
                        }
                    }
                }
            }
        }

        // ---- Content -------------------------------------------------------
        Rectangle {
            // Fills the rest of the window, edge to edge (the window's own corners round it)
            anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right; right: parent.right }
            color: win.well

            id: contentPane
            // Header: a search across every setting (on each page but All Settings, which has its
            // own), then the page's title with Restore defaults opposite; the close button sits top
            // right. The page scrolls beneath
            Item {
                id: header
                z: 2
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: titleRow.height + (pageSearch.visible ? pageSearch.height + 14 : 0)
                // The header's empty space moves the window, as a title bar would (under its search,
                // title and buttons, which take their own clicks)
                MouseArea { anchors.fill: parent; z: -1; onPressed: win.startSystemMove() }

                // ---- Search every setting (SettingsIndex), from any page -------------------
                Rectangle {
                    id: pageSearch
                    // Above the rest of the header (the title row and Restore defaults come after it,
                    // so they'd otherwise draw over its results)
                    z: 2
                    visible: win.section !== "overview"
                    // Level with the close button (top right), and clear of it
                    anchors { top: parent.top; topMargin: 15; left: parent.left; leftMargin: 22; right: parent.right; rightMargin: 58 }
                    height: 36; radius: 10
                    // Flat: a faint fill and no sheen, so it stays quiet above the page
                    color: win.faint
                    border.width: pageFind.activeFocus ? 1 : 0; border.color: win.accent
                    readonly property var found: pageFind.text.trim() === "" ? [] : SettingsIndex.search(pageFind.text, 8)
                    property int pick: 0
                    onFoundChanged: pick = 0
                    function open(e) {
                        if (!e) return;
                        pageFind.text = "";
                        pageFind.focus = false;
                        win.goTo(e.page, e.label);
                    }
                    // A fresh search on each page, and each time Settings opens
                    Connections {
                        target: win
                        function onSectionChanged() { pageFind.text = ""; }
                        function onVisibleChanged() { pageFind.text = ""; }
                    }
                    Text {
                        id: pageFindIcon
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        text: win.glyph(0xEB1C)
                        color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
                    }
                    TextInput {
                        id: pageFind
                        anchors { left: pageFindIcon.right; leftMargin: 8; right: pageFindClear.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        color: win.text; font.family: win.font; font.pixelSize: 13
                        selectionColor: win.accent; selectedTextColor: win.accentText
                        clip: true
                        Keys.onPressed: e => {
                            const f = pageSearch.found;
                            if (e.key === Qt.Key_Down) { pageSearch.pick = Math.min(f.length - 1, pageSearch.pick + 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Up) { pageSearch.pick = Math.max(0, pageSearch.pick - 1); e.accepted = true; }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { pageSearch.open(f[pageSearch.pick]); e.accepted = true; }
                            else if (e.key === Qt.Key_Escape) { if (text !== "") text = ""; else focus = false; e.accepted = true; }
                        }
                        Text {
                            visible: pageFind.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search settings"
                            color: win.dim; font: pageFind.font
                        }
                    }
                    HoverHandler { cursorShape: Qt.IBeamCursor }
                    TapHandler { onTapped: pageFind.forceActiveFocus() }
                    Text {
                        id: pageFindClear
                        visible: pageFind.text !== ""
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: win.glyph(0xEB55)
                        color: pageFindClearHover.hovered ? win.text : win.dim
                        // (with the fill behind it, not ahead of it)
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        font.family: win.bar.iconFont; font.pixelSize: 15
                        HoverHandler { id: pageFindClearHover }
                        ClickTap { onTapped: { pageFind.text = ""; pageFind.forceActiveFocus(); } }
                    }
                }

                Item {
                    id: titleRow
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 66
                    // Back to All Settings, from any other page (All Settings itself has nowhere to go
                    // back to)
                    IconButton {
                        id: backBtn
                        visible: win.section !== "overview"
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                        icon: 0xEA19
                        onClicked: win.section = "overview"
                    }
                    Text {
                        anchors { left: backBtn.visible ? backBtn.right : parent.left; leftMargin: backBtn.visible ? 6 : 22; right: resetBtn.visible ? resetBtn.left : parent.right; rightMargin: resetBtn.visible ? 12 : 22; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                        text: win.pageTitle
                        color: win.text
                        font.family: win.font; font.pixelSize: 22; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    // Restore defaults: opposite the title, only on pages with settings, and only
                    // clickable when something's changed
                    Button {
                        id: resetBtn
                        compactLabel: win.compact
                        anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                        visible: win.currentKeys.length > 0 || !!win.pageResetRun
                        opacity: win.changedHere > 0 || win.pageResetChanged ? 1 : 0.45
                        icon: 0xEB77
                        label: "Restore defaults"
                        onClicked: if (win.changedHere > 0 || win.pageResetChanged) win.askRestoreDefaults()
                    }
                }
            }

            // The page search's results, over the page while typing. Here in the pane rather than
            // in the search box: past the header's bottom edge, the pointer doesn't reach things
            // inside it, so the results couldn't be hovered or clicked there
            Rectangle {
                id: pageHits
                z: 6
                visible: pageFind.activeFocus && pageFind.text.trim() !== ""
                // Under the search box (the header sits at the pane's top left)
                x: header.x + pageSearch.x; y: header.y + pageSearch.y + pageSearch.height + 6
                width: pageSearch.width
                height: pageHitsCol.implicitHeight + 8
                radius: 12
                // Solid, so the page under it doesn't show through the results
                color: win.well
                border.width: 1; border.color: win.outline
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }   // the page under it stays put
                Column {
                    id: pageHitsCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                    Text {
                        visible: pageSearch.found.length === 0
                        width: parent.width
                        topPadding: 10; bottomPadding: 10; leftPadding: 12
                        text: "No settings match “" + pageFind.text.trim() + "”"
                        color: win.dim; font.family: win.font; font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    Repeater {
                        model: pageSearch.found
                        delegate: Rectangle {
                            id: pageHit
                            required property var modelData
                            required property int index
                            readonly property bool chosen: index === pageSearch.pick
                            width: parent.width; height: pageHitCol.implicitHeight + 14
                            radius: 9
                            color: chosen ? win.accent : pageHitHover.hovered ? Config.hover : "transparent"
                            Text {
                                id: pageHitIcon
                                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                text: win.glyph(SettingsIndex.pageIcons[pageHit.modelData.page] || 0xEB20)
                                color: pageHit.chosen ? win.accentText : win.dim
                                font.family: win.bar.iconFont; font.pixelSize: 16
                            }
                            Column {
                                id: pageHitCol
                                anchors { left: pageHitIcon.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: pageHit.modelData.label
                                    color: pageHit.chosen ? win.accentText : win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: (SettingsIndex.pageNames[pageHit.modelData.page] || "")
                                        + (pageHit.modelData.group && pageHit.modelData.group !== pageHit.modelData.label ? " → " + pageHit.modelData.group : "")
                                        + (pageHit.modelData.detail ? " · " + pageHit.modelData.detail : "")
                                    color: pageHit.chosen ? Qt.rgba(win.accentText.r, win.accentText.g, win.accentText.b, 0.72) : win.dim; font.family: win.font; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                            // (pointing at a row doesn't choose it: the chosen row, the one Enter opens, wears
                            // the active colour, and the row under the pointer only the muted hover. The same
                            // in every search list here: this one, All Settings', dropdowns and places)
                            HoverHandler { id: pageHitHover }
                            ClickTap { onTapped: pageSearch.open(pageHit.modelData) }
                        }
                    }
                }
            }
            IconButton {
                id: closeBtn
                z: 3
                // Top right, in the same place on every page (beside the search, or All Settings' title)
                anchors { right: parent.right; rightMargin: 14; top: header.top; topMargin: 16 }
                icon: 0xEB55
                onClicked: win.visible = false
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
                    NumberAnimation { target: foundFlash; property: "opacity"; to: 1; duration: Config.ms(150) }
                    PauseAnimation { duration: 900 }
                    NumberAnimation { target: foundFlash; property: "opacity"; to: 0; duration: Config.ms(600) }
                }
            }
            Flickable {
                id: scroller
                anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 22; rightMargin: 22 }
                contentHeight: pageLoader.item ? pageLoader.item.implicitHeight + 22 : 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: scroller }
                onContentYChanged: { dropLayer.owner = null; if (win.visible) placeSave.restart(); }      // an open dropdown would drift away
                Loader {
                    id: pageLoader
                    width: scroller.width
                    // Only while Settings shows: closed, the page (its wallpaper thumbnails, folder
                    // watching, device lists…) is let go, and built again on opening
                    active: win.visible
                    sourceComponent: ({ overview: overviewPage, general: generalPage, appearance: appearancePage, bar: barPage, dock: dockPage, launcher: launcherPage, spaces: spacesPage,
                        displays: displaysPage, input: inputPage, sound: soundPage, power: powerPage, shortcuts: shortcutsPage,
                        apps: appsPage, startup: startupPage, datetime: timePage, screenshots: shotsPage, windows: windowsPage, notifications: notificationsPage, bluetooth: bluetoothPage, printers: printersPage, about: aboutPage, wifi: wifiPage, hotcorners: hotCornersPage, debug: debugPage, webcam: webcamPage, lock: lockPage, screensaver: screensaverPage, updates: updatesPage, workspaces: workspacesPage, apptheming: appThemingPage, assistant: assistantPage })[win.section]
                    onLoaded: {
                        scroller.contentY = 0; dropLayer.owner = null;
                        if (win.findLabel) Qt.callLater(() => Qt.callLater(win.showFound));
                        else win.restorePlace();     // reopened after a reload: back to where it was scrolled
                    }
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
            ScrollShade {
                z: 1
                anchors { top: header.bottom; left: parent.left; right: parent.right }
                distance: scroller.contentY - scroller.originY
            }
            ScrollShade {
                z: 1
                atBottom: true
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 24
                distance: scroller.originY + scroller.contentHeight - scroller.height - scroller.contentY
            }
        }
    }

    // ---- Confirmation card (Restore defaults, or any win.ask question) --------------------
    Rectangle {
        id: confirmLayer
        anchors.fill: parent
        z: 120
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: opacity > 0
        opacity: win.confirming ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(140) } }
        onVisibleChanged: if (visible) confirmCard.forceActiveFocus()
        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: win.cancelConfirm() }
        // Restoring defaults, or another question (win.ask)
        readonly property var q: win.confirmReset ? null : win.lastAsk
        Rectangle {
            id: confirmCard
            anchors.centerIn: parent
            width: 380; height: confirmCol.implicitHeight + 40
            radius: 16
            color: win.bar.barColor
            border.width: 1; border.color: win.outline
            scale: win.confirming ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }    // clicks on the card don't close it
            Keys.onEscapePressed: win.cancelConfirm()
            // Enter confirms, except for something that can't be taken back (a red button)
            Keys.onReturnPressed: if (!confirmYes.destructive) confirmYes.clicked()
            Keys.onEnterPressed: if (!confirmYes.destructive) confirmYes.clicked()
            Column {
                id: confirmCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 8
                Text {
                    text: confirmLayer.q ? confirmLayer.q.title : "Restore " + win.pageTitle + " defaults?"
                    color: win.text; font.family: win.font; font.pixelSize: 16; font.weight: Font.Medium
                    width: parent.width; elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: confirmLayer.q ? confirmLayer.q.body
                        : win.changedHere + (win.changedHere === 1 ? " setting on this page goes" : " settings on this page go")
                          + " back to how Slate starts out. Your other pages are left just as they are."
                          + (win.resetRestarts ? " Slate restarts to apply them; your apps and windows stay open." : "")
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
                // The question's switch (an option to go further), when it has one
                Item {
                    readonly property var opt: confirmLayer.q ? confirmLayer.q.option : null
                    visible: !!opt
                    width: parent.width; height: visible ? Math.max(optCol.implicitHeight, optToggle.height) + 12 : 0
                    Column {
                        id: optCol
                        anchors { left: parent.left; right: optToggle.left; rightMargin: 12; bottom: parent.bottom }
                        spacing: 2
                        Text { width: parent.width; text: parent.parent.opt ? parent.parent.opt.label : ""; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: parent.parent.opt ? parent.parent.opt.detail || "" : ""; color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap }
                    }
                    Toggle {
                        id: optToggle
                        anchors { right: parent.right; verticalCenter: optCol.verticalCenter }
                        checked: win.askOption
                        onToggled: v => win.askOption = v
                    }
                }
                Item { width: 1; height: 8 }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Button { label: "Cancel"; onClicked: win.cancelConfirm() }
                    Button {
                        id: confirmYes
                        label: confirmLayer.q ? confirmLayer.q.button : "Restore defaults"
                        destructive: !!(confirmLayer.q && confirmLayer.q.destructive)
                        primary: !destructive
                        onClicked: {
                            if (win.ask) { const run = win.ask.run, opt = win.askOption; win.closeConfirm(); run(opt); }
                            else { win.restoreDefaults(); win.closeConfirm(); win.countChanged(); }
                        }
                    }
                }
            }
        }
    }

    // ---- Dropdown menus ----------------------------------------------------
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
        property real menuW: 200
        readonly property real rowH: 34
        // Searchable lists (owner.searchable): what's typed, the choices matching it, and the
        // one Up/Down/Enter would pick
        readonly property bool searching: !!owner && !!owner.searchable
        property string query: ""
        property int pick: 0
        readonly property var shown: {
            const all = owner ? owner.options || [] : [];
            const q = query.trim().toLowerCase().replace(/[_\s]+/g, " ");
            if (!searching || q === "") return all;
            return all.filter(o => (String(o.label) + " " + String(o.value)).toLowerCase().replace(/[_\s]+/g, " ").includes(q));
        }
        onQueryChanged: { pick = 0; menuList.positionViewAtBeginning(); }
        readonly property real searchH: searching ? 40 : 0
        // For the list's width: as wide as its longest choice, at least the button's, at most
        // the window less a margin (longer ones shorten in the middle)
        TextMetrics { id: rowMetrics; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium }
        function place() {
            const b = owner.button;
            const p = b.mapToItem(dropLayer, 0, 0);
            query = ""; pick = 0;
            const full = (owner.options ? owner.options.length : 0) * rowH + 12 + searchH;
            let widest = 0;
            for (const o of (owner.options || [])) {
                rowMetrics.text = String(o.label);
                widest = Math.max(widest, rowMetrics.advanceWidth + (o.folder || o.icon ? 28 : 0));
            }
            // + the row's padding, the tick and the list's own margins (and room for a scrollbar)
            menuW = Math.min(width - 16, Math.max(200, b.width, widest + 12 + 34 + 12 + 8));
            // Measured before placing: placed by its old width, a wider list ran off the window
            menuX = Math.max(8, Math.min(width - menuW - 8, p.x + b.width - menuW));
            // Below the button, or above it if there's no room; a long list goes on the
            // roomier side, as tall as fits, and scrolls
            const below = height - 8 - (p.y + b.height + 6), above = p.y - 6 - 8;
            const downwards = full <= below || (full > above && below >= above);
            menuH = Math.max(Math.min(full, 3 * rowH + 12), Math.min(full, downwards ? below : above));
            menuY = downwards ? Math.min(p.y + b.height + 6, height - 8 - menuH) : Math.max(8, p.y - 6 - menuH);
            // Open on the current choice (and, searchable, ready to type)
            const i = owner.options ? owner.options.findIndex(o => o.value === owner.value) : -1;
            if (searching) pick = Math.max(0, i);
            Qt.callLater(() => { menuList.positionViewAtIndex(Math.max(0, i), ListView.Contain); if (dropLayer.searching) dropFind.forceActiveFocus(); });
        }
        // Click anywhere else to close
        MouseArea { anchors.fill: parent; onPressed: dropLayer.owner = null }
        Rectangle {
            id: menu
            x: dropLayer.menuX; y: dropLayer.menuY
            width: dropLayer.menuW
            height: dropLayer.menuH
            radius: 12
            color: win.popupFill
            border.width: 1; border.color: win.outline
            opacity: dropLayer.visible ? 1 : 0
            layer.enabled: true
            layer.effect: PopupShadow {}
            MouseArea { anchors.fill: parent }     // clicks between rows stay in the menu
            // Searchable: type to filter; Up/Down, Enter to pick, Escape to close
            Rectangle {
                id: dropFindBox
                visible: dropLayer.searching
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6 }
                height: 32; radius: 8
                color: win.faint
                border.width: dropFind.activeFocus ? 1 : 0; border.color: win.accent
                Text {
                    id: dropFindIcon
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: win.glyph(0xEB1C)
                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 15
                }
                TextInput {
                    id: dropFind
                    anchors { left: dropFindIcon.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: win.text; font.family: win.font; font.pixelSize: 13
                    selectionColor: win.accent; selectedTextColor: win.accentText
                    clip: true
                    text: dropLayer.query
                    onTextChanged: dropLayer.query = text
                    Keys.onPressed: e => {
                        const n = dropLayer.shown.length;
                        if (e.key === Qt.Key_Down) { dropLayer.pick = Math.min(n - 1, dropLayer.pick + 1); menuList.positionViewAtIndex(dropLayer.pick, ListView.Contain); e.accepted = true; }
                        else if (e.key === Qt.Key_Up) { dropLayer.pick = Math.max(0, dropLayer.pick - 1); menuList.positionViewAtIndex(dropLayer.pick, ListView.Contain); e.accepted = true; }
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            const o = dropLayer.shown[dropLayer.pick], own = dropLayer.owner;
                            if (o && own) { dropLayer.owner = null; own.picked(o.value); }
                            e.accepted = true;
                        }
                        else if (e.key === Qt.Key_Escape) { dropLayer.owner = null; e.accepted = true; }
                    }
                    Text {
                        visible: dropFind.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Type to search"
                        color: win.dim; font: dropFind.font
                    }
                }
            }
            Text {
                visible: dropLayer.searching && dropLayer.shown.length === 0
                anchors { top: dropFindBox.bottom; topMargin: 12; left: parent.left; leftMargin: 18 }
                text: "Nothing matches “" + dropLayer.query.trim() + "”"
                color: win.dim; font.family: win.font; font.pixelSize: 12
            }
            ListView {
                id: menuList
                anchors { fill: parent; margins: 6; topMargin: 6 + dropLayer.searchH }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: menuList }
                model: dropLayer.shown
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: dropLayer.owner && modelData.value === dropLayer.owner.value
                    // Searchable: the row Enter would pick
                    readonly property bool picked: dropLayer.searching && index === dropLayer.pick
                    // Clear of the scrollbar, when there is one
                    width: menuList.width - (menuList.contentHeight > menuList.height ? 8 : 0); height: dropLayer.rowH; radius: 8
                    color: picked ? win.accent : rowHover.hovered ? Config.hover : "transparent"
                    FolderSwatch {
                        id: rowFolder
                        visible: !!parent.modelData.folder
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        colour: parent.modelData.folder || "transparent"
                    }
                    Text {
                        id: rowIcon
                        visible: !rowFolder.visible && !!parent.modelData.icon
                        anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                        text: visible ? win.glyph(parent.modelData.icon) : ""
                        color: parent.picked ? win.accentText : parent.current ? win.accent : win.dim
                        font.family: win.bar.iconFont; font.pixelSize: 17
                    }
                    Text {
                        readonly property Item lead: rowFolder.visible ? rowFolder : rowIcon.visible ? rowIcon : null
                        anchors { left: lead ? lead.right : parent.left; leftMargin: lead ? 10 : 12; right: tick.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.label
                        color: parent.picked ? win.accentText : parent.current ? win.accent : win.text
                        font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideMiddle      // device names differ at the end: keep it in view
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
                    ClickArea {
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
            // While the list scrolls: a soft shadow at the top once scrolled down and at the bottom
            // while there's more below (like Settings' pages), and a 1 px scrollbar
            ScrollShade {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
                cornerRadius: menu.radius - 1
                distance: menuList.contentY
            }
            ScrollShade {
                atBottom: true
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 1 }
                cornerRadius: menu.radius - 1
                distance: menuList.contentHeight - menuList.height - menuList.contentY
            }
            Rectangle {
                readonly property real range: menuList.contentHeight - menuList.height
                // In the gap the rows leave for it, kept in from the menu's top and bottom
                readonly property real inset: 6
                readonly property real track: menuList.height - 2 * inset
                visible: range > 0
                x: menuList.x + menuList.width - 4
                width: 1
                height: Math.max(16, track * menuList.height / Math.max(1, menuList.contentHeight))
                y: menuList.y + inset + (range > 0 ? (track - height) * Math.max(0, Math.min(1, menuList.contentY / range)) : 0)
                radius: 0.5
                color: win.text
                opacity: 0.4
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
    // A round icon button (the header's back and close): a glyph that brightens, on a fill and
    // sheen that fade in, under the pointer
    component IconButton: Rectangle {
        id: iconButton
        property int icon                  // a Tabler glyph's code point
        signal clicked()
        width: 34; height: 34; radius: 17
        color: iconButtonHover.hovered ? Config.hover : "transparent"
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        Text {
            anchors.centerIn: parent
            text: win.glyph(iconButton.icon)
            color: iconButtonHover.hovered ? win.text : win.dim
            // (with the fill behind it, not ahead of it)
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            font.family: win.bar.iconFont; font.pixelSize: 18
        }
        HoverHandler { id: iconButtonHover }
        ClickTap { onTapped: iconButton.clicked() }
    }
    // A soft shadow along the top or bottom edge of a scrolling list, saying there's more that
    // way: it fades with the distance (px) from that end, gone just as you reach it
    component ScrollShade: Rectangle {
        id: scrollShade
        property bool atBottom: false
        property real distance: 0
        property real cornerRadius: 0      // the rounding of the corners it sits in
        height: 18
        topLeftRadius: atBottom ? 0 : cornerRadius; topRightRadius: atBottom ? 0 : cornerRadius
        bottomLeftRadius: atBottom ? cornerRadius : 0; bottomRightRadius: atBottom ? cornerRadius : 0
        opacity: Math.max(0, Math.min(1, distance / 24))
        gradient: Gradient {
            GradientStop { position: 0; color: scrollShade.atBottom ? "transparent" : Config.shade(Config.s.lightMode ? 0.12 : 0.32) }
            GradientStop { position: 1; color: scrollShade.atBottom ? Config.shade(Config.s.lightMode ? 0.14 : 0.38) : "transparent" }
        }
    }
    // The shadow under a pop-up (dropdown menus, the place search's results): use it as
    // layer.effect: PopupShadow {}
    component PopupShadow: MultiEffect { shadowEnabled: true; shadowColor: Config.shadowColour; shadowOpacity: 0.4; shadowBlur: 0.8; shadowVerticalOffset: 4; blurMax: 24 }
    // The box round a text field: the control colour with a sheen, an I-beam pointer, and a faint
    // accent outline under the pointer (solid while typing). field: the TextInput inside it
    component FieldFrame: Rectangle {
        id: fieldFrame
        property Item field: null
        radius: 8
        color: win.control
        HoverHandler { id: fieldFrameHover; cursorShape: Qt.IBeamCursor }
        border.width: (fieldFrame.field && fieldFrame.field.activeFocus) || fieldFrameHover.hovered ? 1 : 0
        border.color: fieldFrame.field && fieldFrame.field.activeFocus ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.5)
    }
    // A page's opening paragraph, under its title
    component IntroText: Text {
        width: Math.min(parent.width, win.introMeasure)
        color: win.dim; font.family: win.font; font.pixelSize: 13
        wrapMode: Text.Wrap; leftPadding: 4; bottomPadding: 6
    }
    // A note at the foot of a page
    component Footnote: Text {
        width: parent.width
        topPadding: 10
        color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
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
        Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
        Column { id: groupCol; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 } }
    }
    // One setting: label + description on the left, a control on the right
    component SettingRow: Item {
        id: settingRow
        property string label
        property string detail: ""
        default property alias control: controlSlot.data
        // Optional buttons under the description (below: [Button {…}, …]); takes no room when empty
        property alias below: belowSlot.data
        // ...and something on the right edge, level with them (belowRight: [Item {…}])
        property alias belowRight: belowRightSlot.data
        // The Slate setting this row changes (its name in SettingsData), for the mark that shows
        // it's been changed from its default; defaultText says what that default is, when the
        // row can't work it out (a switch: On/Off; a slider: its value, as the slider shows it)
        property string settingKey: ""
        property string defaultText: ""
        readonly property bool changed: settingKey !== "" && Config.defaultOf(settingKey) !== undefined
            && !Config.sameValue(Config.s[settingKey], Config.defaultOf(settingKey))
        readonly property string defaultShown: {
            if (defaultText !== "") return defaultText;
            const d = settingKey !== "" ? Config.defaultOf(settingKey) : undefined;
            if (typeof d === "boolean") return d ? "On" : "Off";
            if (typeof d === "number") {
                const sl = controlSlot.children.length ? controlSlot.children[0] : null;
                if (sl && sl.suffix !== undefined) {
                    // (as the slider would show it: a 0–1 setting on a percentage slider is 80%, not 1%)
                    const v = d * (sl.per || 1);
                    if (sl.zeroText && v <= sl.from) return sl.zeroText;
                    return v.toFixed(sl.decimals || 0) + sl.suffix;
                }
                return String(d);
            }
            return d === undefined || d === "" ? "none" : String(d);
        }
        width: parent ? parent.width : 0
        height: Math.max(56, labels.implicitHeight + 24, controlSlot.height + 24)
        Column {
            id: labels
            anchors { left: parent.left; leftMargin: 16; right: controlSlot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                id: labelText
                // (room left after the name for the changed-from-default dot)
                width: Math.min(implicitWidth, parent.width - (settingRow.changed ? 20 : 0))
                text: label; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
            }
            Text { width: Math.min(parent.width, win.detailMeasure); visible: detail !== ""; text: detail; color: win.dim; font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap }
            Row {
                id: belowSlot
                spacing: 8
                topPadding: visibleChildren.length > 0 ? 8 : 0
            }
        }
        Item {
            id: belowRightSlot
            anchors { right: parent.right; rightMargin: 16 }
            y: labels.y + belowSlot.y + belowSlot.topPadding
            height: Math.max(0, belowSlot.height - belowSlot.topPadding)
            width: 0          // (what's in it is anchored to its right, the row's right edge)
        }
        // Changed from its default: a small dot after the name. Pointed at, it says what the
        // default is; clicked, it puts it back. (The row comes above its neighbours meanwhile, so
        // the bubble isn't drawn under them)
        z: dotHover.hovered ? 5 : 0
        Rectangle {
            id: changedDot
            visible: settingRow.changed
            x: labels.x + labelText.width + 8
            y: labels.y + labelText.height / 2 - height / 2
            width: 8; height: 8; radius: 4
            color: win.accent
            scale: dotHover.hovered ? 1.4 : 1
            Behavior on scale { NumberAnimation { duration: Config.ms(100) } }
            // Easier to point at than it looks: it reacts 10 px all round
            HoverHandler { id: dotHover; margin: 10; cursorShape: Qt.PointingHandCursor }
            ClickTap { margin: 10; onTapped: Config.resetKeys([settingRow.settingKey]) }
        }
        Rectangle {
            visible: changedDot.visible && dotHover.hovered
            z: 2
            x: changedDot.x + 18
            y: changedDot.y + changedDot.height / 2 - height / 2
            width: tipText.implicitWidth + 14; height: tipText.implicitHeight + 8
            radius: 6
            // The theme's own shades (Config.tint: light or dark, and the wallpaper's tint)
            color: Config.tint("#262c35")
            border.width: 1; border.color: Config.tint("#3d4553")
            Text {
                id: tipText
                anchors.centerIn: parent
                text: "Default: " + settingRow.defaultShown + "  ·  click to use it"
                color: win.text
                font.family: win.font; font.pixelSize: 11
            }
        }
        Item {
            id: controlSlot
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
    }
    // A setting that's a plain switch for one of Slate's settings: key is its name in
    // SettingsData (ToggleSetting { label: "…"; detail: "…"; key: "barShowApps" })
    component ToggleSetting: SettingRow {
        id: toggleRow
        property string key
        settingKey: key
        Toggle { checked: Config.s[toggleRow.key]; onToggled: v => Config.s[toggleRow.key] = v }
    }
    component Toggle: Rectangle {
        id: toggleSwitch
        property bool checked: false
        signal toggled(bool value)
        width: 42; height: 24; radius: 12
        color: checked ? win.accent
            : (tgHover.hovered ? win.controlHover(win.knobHover) : win.control)
        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
        // Hover: a soft accent ring around the switch
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: height / 2
            color: "transparent"
            border.width: 2; border.color: win.accent
            opacity: tgHover.hovered ? 0.35 : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        }
        HoverHandler { id: tgHover }
        Rectangle {
            width: 18; height: 18; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            x: toggleSwitch.checked ? parent.width - width - 3 : 3
            color: toggleSwitch.checked ? win.accentText : win.text
            Behavior on x { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
        }
        ClickTap { onTapped: toggleSwitch.toggled(!toggleSwitch.checked) }
    }
    // Slider with its value shown alongside
    component ValueSlider: Row {
        id: valueSlider
        property real from: 0
        property real to: 1
        property real stepSize: 0.1
        property real value: 0
        property string suffix: ""
        property string zeroText: ""   // shown instead of the value at the bottom (e.g. "Off")
        // How many of the slider's units one of the setting's is: 100 for a setting kept as 0–1 and
        // shown as a percentage. Its row uses it to say what the default is, in the slider's terms
        property real per: 1
        property int decimals: 0
        signal moved(real value)
        signal released()          // let go of the slider (after moving it, or a click)
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            horizontalAlignment: Text.AlignRight
            text: valueSlider.zeroText !== "" && valueSlider.value <= valueSlider.from ? valueSlider.zeroText : valueSlider.value.toFixed(valueSlider.decimals) + valueSlider.suffix
            color: win.dim
            font.family: win.font; font.pixelSize: 12
        }
        Item {
            width: 200; height: 24
            readonly property real frac: (valueSlider.value - valueSlider.from) / (valueSlider.to - valueSlider.from)
            id: sliderBox
            readonly property bool hot: sliderMouse.containsMouse || sliderMouse.pressed
            Rectangle {
                id: trk
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: sliderBox.hot ? win.controlHover(win.knobHover) : win.control
                Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                Rectangle {
                    width: Math.max(6, trk.width * parent.parent.frac); height: parent.height; radius: 3; color: win.accent
                }
            }
            // Hover: an accent halo behind the knob, which grows a little
            Rectangle {
                width: 28; height: 28; radius: 14
                anchors.verticalCenter: parent.verticalCenter
                x: parent.frac * (parent.width - 16) + 8 - width / 2
                color: win.accent
                opacity: sliderBox.hot ? 0.22 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
            }
            Rectangle {
                width: 16; height: 16; radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: parent.frac * (parent.width - 16)
                color: win.text
                Gloss { radius: parent.radius; strength: 0.6 }   // glass: a sheen
                scale: sliderBox.hot ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Config.ms(120) } }
            }
            MouseArea {
                id: sliderMouse
                // Keep the drag once it's started here: the scrolling page around it took over
                // when the pointer drifted up or down, and the slider stopped following it
                preventStealing: true
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Config.handCursor ? Qt.PointingHandCursor : Qt.ArrowCursor      // (a hand over it, as over what's clicked)
                function set(mx) {
                    const raw = valueSlider.from + Math.max(0, Math.min(1, mx / width)) * (valueSlider.to - valueSlider.from);
                    valueSlider.moved(Math.round(raw / valueSlider.stepSize) * valueSlider.stepSize);
                }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x); }
                onReleased: valueSlider.released()
            }
        }
    }
    // One of Slate's sounds: a play button to hear it, and a volume slider, Off at 0; letting go
    // of the slider plays it too, at that volume
    component SoundSetting: SettingRow {
        id: soundSetting
        property string which              // Config.soundSettings key
        property string sample             // sounds/<sample>.wav to play as a preview
        property bool available: true
        readonly property bool audible: available && Config.soundVolume(which) > 0
        Row {
            spacing: 6
            // Play: the sound at its volume (dimmed while it's off, with nothing to hear). A plain
            // TapHandler, not ClickTap: the sound it plays is its own feedback
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28; radius: 14
                opacity: soundSetting.audible ? 1 : 0.4
                color: playHover.hovered && soundSetting.audible ? win.controlHover(win.controlHoverSolid) : win.control
                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 1      // the triangle looks centred a touch right
                    text: win.glyph(0xED46)                // play
                    color: soundSetting.audible ? win.text : win.dim
                    font.family: win.bar.iconFont; font.pixelSize: 14
                }
                HoverHandler { id: playHover; cursorShape: soundSetting.audible ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: soundSetting.audible; onTapped: Config.playSound(soundSetting.sample, soundSetting.which) }
            }
            ValueSlider {
                anchors.verticalCenter: parent.verticalCenter
                enabled: soundSetting.available
                opacity: enabled ? 1 : 0.4
                from: 0; to: 100; stepSize: 5; suffix: "%"; zeroText: "Off"
                value: soundSetting.available ? Config.soundVolume(soundSetting.which) : 0
                onMoved: v => Config.s[Config.soundSettings[soundSetting.which][0]] = Math.round(v)
                onReleased: Config.playSound(soundSetting.sample, soundSetting.which)
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
        color: primary ? win.accent
            : btnHover.hovered ? (destructive ? Config.hoverDanger : win.controlHover(win.controlHoverSolid)) : win.control
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        readonly property color fg: primary ? win.accentText : destructive ? win.danger : win.text
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
        ClickTap { onTapped: btn.clicked() }
    }
    // A font choice: shows the current font, and opens a searchable list of
    // installed fonts (each shown in its own typeface). key = Config.s property.
    component FontSetting: Column {
        id: fontSetting
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
            running: fontSetting.monoOnly
            command: ["fc-list", ":spacing=mono", "family"]
            stdout: StdioCollector {
                onStreamFinished: fontSetting.monoFonts = text.split("\n").map(l => l.split(",")[0].trim()).filter(f => f)
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
            onTriggered: { fontList.positionViewAtIndex(Math.max(0, fontSetting.shown.indexOf(fontSetting.value)), ListView.Center); fontSetting.revealList(); }
        }
        function revealList() {
            const bottom = fontSetting.mapToItem(scroller.contentItem, 0, fontSetting.height).y;
            const top = fontSetting.mapToItem(scroller.contentItem, 0, 0).y;
            if (bottom > scroller.contentY + scroller.height)
                scroller.contentY = Math.min(top, bottom - scroller.height);
        }

        SettingRow {
            settingKey: fontSetting.key
            defaultText: fontSetting.defaultFont || "the system font"
            label: fontSetting.label
            detail: fontSetting.detail
            Row {
                spacing: 8
                Button { visible: fontSetting.value !== fontSetting.defaultFont; label: "Default"; onClicked: fontSetting.choose(fontSetting.defaultFont) }
                Button {
                    label: fontSetting.value + (fontSetting.open ? "  ▴" : "  ▾")
                    primary: fontSetting.open
                    onClicked: fontSetting.open = !fontSetting.open
                }
            }
        }
        Item {
            visible: fontSetting.open
            width: parent.width
            height: fontSetting.open ? 300 : 0
            FieldFrame {
                id: fontSearchBox
                field: fontSearch
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                height: 34
                TextInput {
                    id: fontSearch
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: win.text; selectionColor: win.accent
                    font.family: win.font; font.pixelSize: 13
                    Keys.onEscapePressed: fontSetting.open = false
                    Keys.onReturnPressed: if (fontSetting.shown.length) { fontSetting.choose(fontSetting.shown[0]); fontSetting.open = false; }
                }
                Text {
                    visible: fontSearch.text === ""
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: "Search " + fontSetting.all.length + " fonts"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
            }
            ListView {
                id: fontList
                anchors { left: parent.left; right: parent.right; top: fontSearchBox.bottom; bottom: parent.bottom; margins: 8; leftMargin: 12; rightMargin: 12 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: fontSetting.shown
                SmoothWheel { flick: fontList; notch: 108 }
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool current: fontSetting.value === modelData
                    width: ListView.view.width; height: 36; radius: 8
                    color: current ? win.accent : fontHover.hovered ? Config.hover : "transparent"
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
                        text: fontSetting.monoOnly ? "{ x => 0 }" : "Aa 123"
                        color: parent.current ? win.accentText : win.dim
                        font.family: parent.modelData; font.pixelSize: 13
                    }
                    HoverHandler { id: fontHover }
                    ClickTap { onTapped: fontSetting.choose(parent.modelData) }
                }
            }
        }
    }
    // A setting with a few named options: shows the current one; click to pick.
    // options: [{ value, label }]
    component ChoiceSetting: Column {
        id: choiceSetting
        property string label
        property string detail: ""
        property var options: []
        property var value
        property bool open: false
        signal picked(var value)
        property string settingKey: ""          // (as SettingRow's: the changed-from-default mark)
        width: parent ? parent.width : 0
        readonly property var current: options.find(o => o.value === value) ?? null
        SettingRow {
            label: choiceSetting.label
            detail: choiceSetting.detail
            settingKey: choiceSetting.settingKey
            defaultText: {
                const d = choiceSetting.settingKey !== "" ? Config.defaultOf(choiceSetting.settingKey) : undefined;
                const o = d === undefined ? null : choiceSetting.options.find(x => x.value === d);
                return o ? o.label : "";
            }
            Button {
                label: (choiceSetting.current ? choiceSetting.current.label : String(choiceSetting.value)) + (choiceSetting.open ? "  ▴" : "  ▾")
                primary: choiceSetting.open
                onClicked: choiceSetting.open = !choiceSetting.open
            }
        }
        Flow {
            visible: choiceSetting.open
            width: parent.width - 32; x: 16
            spacing: 6
            bottomPadding: 14
            Repeater {
                model: choiceSetting.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.value === choiceSetting.value
                    width: optText.implicitWidth + 26; height: 32; radius: 8
                    color: on ? win.accent : optHover.hovered ? win.fieldHover() : win.control
                    Text { id: optText; anchors.centerIn: parent; text: parent.modelData.label; color: parent.on ? win.accentText : win.text; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                    HoverHandler { id: optHover }
                    ClickTap { onTapped: { choiceSetting.picked(parent.modelData.value); choiceSetting.open = false; } }
                }
            }
        }
    }
    // A setting with a dropdown menu of choices (opens over the page; see dropLayer)
    component DropdownSetting: Item {
        id: dropdown
        property string label
        property string detail: ""
        width: parent ? parent.width : 0
        height: ddRow.height
        property var options: []
        property var value
        signal picked(var value)
        property string settingKey: ""          // (as SettingRow's: the changed-from-default mark)
        readonly property var current: options.find(o => o.value === value) ?? null
        // Shown when the value isn't one of the options (it isn't offered in the list itself)
        property string noneLabel: ""
        // A search box at the top of the open list, filtering it as you type (long lists)
        property bool searchable: false
        property alias button: ddButton
        SettingRow {
          id: ddRow
          label: dropdown.label
          detail: dropdown.detail
          settingKey: dropdown.settingKey
          defaultText: {
              const d = dropdown.settingKey !== "" ? Config.defaultOf(dropdown.settingKey) : undefined;
              const o = d === undefined ? null : dropdown.options.find(x => x.value === d);
              return o ? o.label : "";
          }
          Rectangle {
            id: ddButton
            readonly property bool open: dropLayer.owner === dropdown
            // As wide as its choice needs, up to a bit under half the row (long names shorten in the middle)
            readonly property real naturalWidth: ddText.implicitWidth + 44 + (ddFolder.visible ? ddFolder.width + 8 : 0)
                + (ddIcon.visible ? ddIcon.width + 8 : 0)
            width: Math.max(150, Math.min(naturalWidth, dropdown.width * 0.45)); height: 32; radius: 8
            color: open || ddHover.hovered ? win.fieldHover() : win.control
            border.width: open ? 1 : 0; border.color: win.accent
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            // Options can carry a folder colour (folder: "#hex"): a little folder in it before the label
            FolderSwatch {
                id: ddFolder
                visible: !!dropdown.current && !!dropdown.current.folder
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                colour: dropdown.current && dropdown.current.folder ? dropdown.current.folder : "transparent"
            }
            // ...or an icon (icon: a glyph code)
            Text {
                id: ddIcon
                visible: !ddFolder.visible && !!dropdown.current && !!dropdown.current.icon
                anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter }
                text: visible ? win.glyph(dropdown.current.icon) : ""
                color: win.text; font.family: win.bar.iconFont; font.pixelSize: 16
            }
            Text {
                id: ddText
                readonly property Item lead: ddFolder.visible ? ddFolder : ddIcon.visible ? ddIcon : null
                anchors { left: lead ? lead.right : parent.left; leftMargin: lead ? 8 : 12; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, ddButton.width - x - 32)
                text: dropdown.current ? dropdown.current.label : dropdown.noneLabel !== "" ? dropdown.noneLabel : String(dropdown.value)
                color: win.text; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
                elide: Text.ElideMiddle      // device names differ at the end: keep it in view
            }
            Text {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: win.glyph(0xEA5F)                      // chevron down
                rotation: ddButton.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Config.ms(120) } }
                color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
            }
            HoverHandler { id: ddHover }
            ClickTap { onTapped: dropLayer.owner = ddButton.open ? null : dropdown }
          }
        }
    }
    // (with glass the cards are see-through, and the solid divider grey all but vanished on them:
    // a faint line of the text colour there, still quiet)
    component Separator: Rectangle {
        width: parent ? parent.width - 32 : 0; x: 16; height: 1
        color: Config.glass ? Qt.rgba(win.text.r, win.text.g, win.text.b, 0.11) : win.divider
    }
    // A choice from a long list (keyboard layouts, time zones, apps): a button that opens a
    // search box and list under the row. options: [{ value, label, detail? }]
    component SearchPicker: Column {
        id: searchPicker
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
            label: searchPicker.label
            detail: searchPicker.detail
            Button {
                icon: searchPicker.open ? 0 : searchPicker.buttonIcon
                label: searchPicker.open ? "Cancel" : searchPicker.buttonLabel
                onClicked: {
                    searchPicker.open = !searchPicker.open;
                    findBox.text = "";
                    if (searchPicker.open) Qt.callLater(() => findBox.forceActiveFocus());
                }
            }
        }
        Column {
            visible: searchPicker.open
            width: parent.width - 32; x: 16
            spacing: 6
            bottomPadding: 14
            Rectangle {
                width: parent.width; height: 34; radius: 8
                color: win.well
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
                    Keys.onReturnPressed: if (searchPicker.shown.length > 0) { searchPicker.picked(searchPicker.shown[0].value); searchPicker.open = false; }
                    Keys.onEscapePressed: event => { searchPicker.open = false; event.accepted = true; }
                    Text { visible: findBox.text === ""; text: "Search"; color: win.dim; font: findBox.font; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Rectangle {
                width: parent.width; height: Math.min(220, Math.max(40, pickList.contentHeight + 8)); radius: 8
                color: win.well
                ListView {
                    id: pickList
                    anchors { fill: parent; margins: 4 }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: pickList }
                    model: searchPicker.shown
                    delegate: Rectangle {
                        required property var modelData
                        width: pickList.width; height: pickDetail.visible ? 42 : 32; radius: 6
                        color: pickHover.hovered ? Config.hover : "transparent"
                        Column {
                            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            Text { width: parent.width; text: parent.parent.modelData.label; color: win.text; font.family: win.font; font.pixelSize: 13; elide: Text.ElideRight }
                            Text { id: pickDetail; width: parent.width; visible: !!parent.parent.modelData.detail; text: parent.parent.modelData.detail || ""; color: win.dim; font.family: win.font; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        HoverHandler { id: pickHover }
                        ClickTap { onTapped: { searchPicker.picked(parent.modelData.value); searchPicker.open = false; } }
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
        id: listItemRow
        property bool removable: true
        signal removed()
        Button {
            visible: listItemRow.removable
            icon: 0xEB41
            label: "Remove"
            destructive: true
            compactLabel: true
            onClicked: listItemRow.removed()
        }
    }

    // ---- Pages -------------------------------------------------------------
    // Overview: tiles for the pages that aren't in the sidebar
    Component {
        id: overviewPage
        Column {
            id: ovPage
            spacing: 4
            PageTitle { text: "All Settings" }
            // ---- Search every setting (SettingsIndex) ----------------------------------
            readonly property var found: SettingsIndex.search(findField.text, 30)
            property int pick: 0
            onFoundChanged: pick = 0
            function open(e) { if (e) win.goTo(e.page, e.label); }
            Rectangle {
                width: parent.width; height: 44
                radius: 12
                color: win.card          // (flat, as Slate's other text boxes: no sheen)
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
                    // Ready to type whenever All Settings shows: when the page loads and each time
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
                    // (with the fill behind it, not ahead of it)
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    font.family: win.bar.iconFont; font.pixelSize: 16
                    HoverHandler { id: clearHover }
                    ClickTap { onTapped: { findField.text = ""; findField.forceActiveFocus(); } }
                }
            }
            Item { width: 1; height: 6 }
            // What's under the search box scrolls by itself (the results, or the tiles), so the
            // box stays where it is: the page as a whole is made to fit, and never scrolls
            Item {
                width: parent.width
                height: Math.max(160, scroller.height - 80)
                Flickable {
                    id: ovScroll
                    anchors { fill: parent; rightMargin: contentHeight > height ? 18 : 0 }
                    contentHeight: ovInner.implicitHeight + 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: ovScroll }
                    Column {
                        id: ovInner
                        width: ovScroll.width
                        spacing: 4
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
                                    color: chosen ? win.accent : hitHover.hovered ? Config.hover : "transparent"
                                    Text {
                                        id: hitIcon
                                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                        text: win.glyph(SettingsIndex.pageIcons[hitRow.modelData.page] || 0xEB20)
                                        color: hitRow.chosen ? win.accentText : win.dim
                                        font.family: win.bar.iconFont; font.pixelSize: 17
                                    }
                                    Column {
                                        id: hitCol
                                        anchors { left: hitIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: hitRow.modelData.label
                                            color: hitRow.chosen ? win.accentText : win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: parent.width
                                            text: (SettingsIndex.pageNames[hitRow.modelData.page] || "")
                                                + (hitRow.modelData.group && hitRow.modelData.group !== hitRow.modelData.label ? " → " + hitRow.modelData.group : "")
                                                + (hitRow.modelData.detail ? " · " + hitRow.modelData.detail : "")
                                            color: hitRow.chosen ? Qt.rgba(win.accentText.r, win.accentText.g, win.accentText.b, 0.72) : win.dim; font.family: win.font; font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                    HoverHandler { id: hitHover }
                                    ClickTap { onTapped: ovPage.open(hitRow.modelData) }
                                }
                            }
                        }
                        Flow {
                            id: tiles
                            visible: findField.text.trim().length < 2
                            width: parent.width
                            spacing: 10
                            // Two or three across, filling the width
                            readonly property int across: width >= 560 ? 3 : width >= 340 ? 2 : 1
                            readonly property real tileW: (width - spacing * (across - 1)) / across
                            Repeater {
                                model: win.sections
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    width: tiles.tileW
                                    height: 112
                                    radius: 12
                                    color: tileHover.hovered ? Config.hoverOn(win.card) : win.card
                                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                    Rectangle {
                                        x: 14; y: 14
                                        width: 34; height: 34; radius: 10
                                        // The page's own colour when colourful, else the accent
                                        readonly property color pc: Config.pageColour(tile.modelData.id)
                                        color: Qt.rgba(pc.r, pc.g, pc.b, 0.16)
                                        Text {
                                            anchors.centerIn: parent
                                            text: win.glyph(tile.modelData.icon)
                                            color: parent.pc
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
                                    ClickTap { onTapped: win.section = tile.modelData.id }
                                }
                            }
                        }
                    }
                }
                ThinScrollbar {
                    flick: ovScroll
                    color: win.text
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right; bottomMargin: 8 }
                }
                ScrollShade {
                    anchors { top: parent.top; left: parent.left; right: ovScroll.right }
                    distance: ovScroll.contentY
                }
                ScrollShade {
                    atBottom: true
                    anchors { bottom: parent.bottom; left: parent.left; right: ovScroll.right }
                    distance: ovScroll.contentHeight - ovScroll.height - ovScroll.contentY
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
            GroupLabel { text: "Account" }
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
                            color: win.outline
                            visible: acctImg.status !== Image.Ready
                            Text { anchors.centerIn: parent; text: win.glyph(0xEF68); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 34 }
                        }
                        RoundImage {
                            id: acctImg
                            anchors.fill: parent; radius: width / 2
                            source: Config.avatarUrl
                            saturation: acctHover.hovered || Config.avatarBusy ? -1 : 0
                            brightness: acctHover.hovered || Config.avatarBusy ? -0.45 : 0
                            Behavior on saturation { NumberAnimation { duration: Config.ms(150) } }
                            Behavior on brightness { NumberAnimation { duration: Config.ms(150) } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: win.glyph(0xEB04)
                            color: "white"
                            font.family: win.bar.iconFont; font.pixelSize: 20
                            opacity: acctHover.hovered && !Config.avatarBusy ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                        }
                        HoverHandler { id: acctHover }
                        ClickTap { onTapped: win.avatarPicking = true }
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
                        Button { icon: 0xEB0A; label: "Change picture"; onClicked: win.avatarPicking = true }
                    }
                }
            }
            GroupLabel { text: "Clipboard" }
            Group {
                SettingRow {
                    label: "Clipboard history"
                    settingKey: "clipboardHistory"
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
                // In front of the groups below while its results are showing over them
                z: locPop.visible ? 5 : 0
                // Search a place by name as you type (Open-Meteo's free geocoding), then pick a result
                Column {
                    id: loc
                    width: parent.width
                    property var results: []
                    property string status: ""
                    property int pick: 0
                    onResultsChanged: pick = 0
                    function search(q) {
                        if (q.trim().length < 2) { results = []; status = ""; return; }
                        status = "Searching…";
                        geo.running = false;         // a newer search replaces one still going
                        geo.command = ["curl", "-sf", "--max-time", "10", "https://geocoding-api.open-meteo.com/v1/search?count=6&format=json&name=" + encodeURIComponent(q.trim())];
                        geo.running = true;
                    }
                    function choose(r) {
                        if (!r) return;
                        Config.s.latitude = r.latitude;
                        Config.s.longitude = r.longitude;
                        Config.s.locationName = r.name;
                        results = []; status = ""; placeInput.text = ""; placeInput.focus = false;
                    }
                    // Searches a moment after you stop typing
                    Timer { id: geoSoon; interval: 350; onTriggered: loc.search(placeInput.text) }
                    // A search stopped for a newer one ends with nothing (and a failure code): that
                    // says nothing about the newer one, so it's ignored
                    Process {
                        id: geo
                        stdout: StdioCollector {
                            onStreamFinished: {
                                if (text.trim() === "") return;
                                try { loc.results = JSON.parse(text).results || []; } catch (e) { loc.results = []; }
                                loc.status = loc.results.length ? "" : "No places found";
                            }
                        }
                        onExited: code => { if (code !== 0 && !geo.running && !geoSoon.running) loc.status = "Slate couldn't search just now. Are you online?"; }
                    }
                    SettingRow {
                        label: "Location"
                        detail: Config.s.locationName !== "" ? "Weather and night light's sunset/sunrise use " + Config.s.locationName
                            : "Not set yet, so the weather is hidden. Search for your town or city to see it"
                        FieldFrame {
                            id: placeField
                            field: placeInput
                            width: 240; height: 30
                            TextInput {
                                id: placeInput
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: win.text; selectionColor: win.accent
                                font.family: win.font; font.pixelSize: 12
                                onTextChanged: { if (text.trim().length >= 2) geoSoon.restart(); else { geoSoon.stop(); geo.running = false; loc.results = []; loc.status = ""; } }
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_Down) { loc.pick = Math.min(loc.results.length - 1, loc.pick + 1); e.accepted = true; }
                                    else if (e.key === Qt.Key_Up) { loc.pick = Math.max(0, loc.pick - 1); e.accepted = true; }
                                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                        if (geoSoon.running) { geoSoon.stop(); loc.search(text); }      // Enter before the pause: search now
                                        else loc.choose(loc.results[loc.pick]);
                                        e.accepted = true;
                                    }
                                    else if (e.key === Qt.Key_Escape) { text = ""; focus = false; e.accepted = true; }
                                }
                            }
                            // Empty field: the place you've set (with a pin), or how to search
                            Row {
                                visible: placeInput.text === ""
                                anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                readonly property bool showsPlace: Config.s.locationName !== "" && !placeInput.activeFocus
                                Text {
                                    visible: parent.showsPlace
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: win.glyph(0xEAE8)                  // map pin
                                    color: win.accent; font.family: win.bar.iconFont; font.pixelSize: 14
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - (parent.showsPlace ? 20 : 0)
                                    text: parent.showsPlace ? Config.s.locationName
                                        : Config.s.locationName !== "" ? "Search for a new place" : "Search for your town or city"
                                    color: parent.showsPlace ? win.text : win.dim
                                    font.family: win.font; font.pixelSize: 12; font.weight: parent.showsPlace ? Font.Medium : Font.Normal
                                    elide: Text.ElideRight
                                }
                            }

                            // Results, dropping down from the field over the page
                            Rectangle {
                                id: locPop
                                visible: placeInput.activeFocus && placeInput.text.trim().length >= 2 && (loc.results.length > 0 || loc.status !== "")
                                anchors { top: parent.bottom; topMargin: 6; right: parent.right }
                                width: 300
                                height: locPopCol.implicitHeight + 8
                                radius: 12
                                // Solid, so the page under it doesn't show through
                                color: win.popupFill
                                border.width: 1; border.color: win.outline
                                layer.enabled: true
                                layer.effect: PopupShadow {}
                                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }   // the page under it stays put
                                Column {
                                    id: locPopCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                                    // Searching…, No places found, or couldn't search
                                    Text {
                                        visible: loc.results.length === 0 && loc.status !== ""
                                        width: parent.width
                                        topPadding: 10; bottomPadding: 10; leftPadding: 12
                                        text: loc.status
                                        color: win.dim; font.family: win.font; font.pixelSize: 12
                                    }
                                    Repeater {
                                        model: loc.results
                                        delegate: Rectangle {
                                            id: placeRow
                                            required property var modelData
                                            required property int index
                                            readonly property bool chosen: index === loc.pick
                                            width: parent.width; height: placeCol.implicitHeight + 14
                                            radius: 9
                                            color: chosen ? win.accent : placeHover.hovered ? Config.hover : "transparent"
                                            Column {
                                                id: placeCol
                                                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                                spacing: 1
                                                Text {
                                                    width: parent.width
                                                    text: placeRow.modelData.name
                                                    color: placeRow.chosen ? win.accentText : win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    width: parent.width
                                                    visible: text !== ""
                                                    text: [placeRow.modelData.admin1, placeRow.modelData.country].filter(x => x).join(", ")
                                                    color: placeRow.chosen ? Qt.rgba(win.accentText.r, win.accentText.g, win.accentText.b, 0.72) : win.dim; font.family: win.font; font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            HoverHandler { id: placeHover }
                                            ClickArea { anchors.fill: parent; onClicked: loc.choose(placeRow.modelData) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            GroupLabel { text: "Night light" }
            Group {
                ToggleSetting {
                    label: "Night light"
                    detail: "Warmer screen colours that are kinder to your eyes at night. Also in the control centre"
                    key: "nightLight"
                }
                Separator {}
                SettingRow {
                    label: "Warmth"
                    settingKey: "nightLightTemperature"
                    detail: "Colour temperature: lower is warmer"
                    ValueSlider { from: 2500; to: 6000; stepSize: 100; suffix: " K"; value: Config.s.nightLightTemperature; onMoved: v => Config.s.nightLightTemperature = v }
                }
                Separator {}
                DropdownSetting {
                    label: "Schedule"
                    settingKey: "nightLightSchedule"
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
                    settingKey: "nightLightFrom"
                    value: Config.s.nightLightFrom
                    options: win.halfHours(16, 23.5)
                    onPicked: v => Config.s.nightLightFrom = v
                }
                Separator { visible: Config.s.nightLightSchedule === "custom" }
                ChoiceSetting {
                    visible: Config.s.nightLightSchedule === "custom"
                    label: "Turn off at"
                    settingKey: "nightLightTo"
                    value: Config.s.nightLightTo
                    options: win.halfHours(4, 10.5)
                    onPicked: v => Config.s.nightLightTo = v
                }
            }
        }
    }

    Component {
        id: barPage
        Column {
            id: barPane
            spacing: 4
            PageTitle { text: "Menu Bar" }
            // ---- Arranging the bar: done on the bar itself, with a panel beside it (BarEditor.qml)
            GroupLabel { text: "Layout" }
            Group {
                SettingRow {
                    label: "Arrange the menu bar"
                    detail: "Drag things along the bar itself, put them together in containers, add space between them, and take off what you don't use. "
                        + "Settings steps out of the way while you do, and comes back when you press Done"
                    Button { label: "Edit layout"; onClicked: Config.barArranging = true }
                }
            }
            GroupLabel { text: "Position & behaviour" }
            Group {
                SettingRow {
                    label: "Position"
                    settingKey: "barPosition"
                    defaultText: { const d = Config.defaultOf("barPosition"); return d.charAt(0).toUpperCase() + d.slice(1); }
                    detail: "Click an edge. The dock is at the " + Config.s.dockPosition + "; if you pick its edge, it moves to the opposite one. On the left or right, the status icons drop their text and the window title turns to run along the bar"
                    EdgePicker { accent: win.accent; bar: true; edge: Config.s.barPosition; onPicked: e => Config.moveBar(e) }
                }
                Separator {}
                ToggleSetting {
                    label: "Auto-hide"
                    detail: "Slides the bar out of your way when a single window fills the screen; it comes back when you switch workspace or reach for the top edge"
                    key: "barAutoHide"
                }
                Separator {}
                ToggleSetting {
                    label: "Hover descriptions"
                    detail: "Tells you what you're pointing at on the bar, in place of the window title"
                    key: "barHoverDescriptions"
                }
                Separator {}
                ToggleSetting {
                    label: "Monochrome tray icons"
                    detail: "Draws the tray's app icons in one colour, like the rest of the bar, even with the Colourful look on"
                    key: "barTrayMono"
                }
            }
            // (only with glass on: Appearance → Glass)
            GroupLabel { visible: Config.s.glass; text: "Glass" }
            Group {
                visible: Config.s.glass
                ToggleSetting {
                    label: "Blur"
                    detail: "What's behind the bar is blurred, like frosted glass. Off, you see straight through it"
                    key: "barBlur"
                }
                Separator {}
                SettingRow {
                    label: "Background opacity"
                    settingKey: "barOpacity"
                    detail: "How solid the bar's background is: 100% can't be seen through, lower is clearer"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round((Config.s.barOpacity < 0 ? Config.barGlassOpacity : Config.s.barOpacity) * 100); onMoved: v => Config.s.barOpacity = v / 100 }
                }
                Separator {}
                SettingRow {
                    label: "Contents opacity"
                    settingKey: "barItemOpacity"
                    detail: "How solid the containers on the bar are, with everything in them: their icons, text and dividers. At 0% they're gone"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.barItemOpacity * 100); onMoved: v => Config.s.barItemOpacity = v / 100 }
                }
                Separator {}
                SettingRow {
                    label: "Hover opacity"
                    settingKey: "barItemHoverOpacity"
                    detail: "How solid a container is while the pointer's over it, with everything in it: its icons, text, highlight and dividers"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.barItemHoverOpacity * 100); onMoved: v => Config.s.barItemHoverOpacity = v / 100 }
                }
                Separator {}
                ToggleSetting {
                    label: "Panel blur"
                    detail: "What's behind the panels that open from the bar is blurred. Off, you see straight through them"
                    key: "barPanelBlur"
                }
                Separator {}
                SettingRow {
                    label: "Panel opacity"
                    settingKey: "barPanelOpacity"
                    detail: Config.s.barPanelBlur ? "How solid the panels that open from the bar are: 100% can't be seen through, lower is clearer"
                        : "How solid the panels that open from the bar are. With their blur off they stay mostly solid, so they can be read: 0% is as clear as they go"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.barPanelOpacity * 100); onMoved: v => Config.s.barPanelOpacity = v / 100 }
                }
            }
        }
    }

    Component {
        id: dockPage
        Column {
            spacing: 4
            PageTitle { text: "Dock" }
            GroupLabel { text: "Position & behaviour" }
            Group {
                SettingRow {
                    label: "Position"
                    settingKey: "dockPosition"
                    defaultText: { const d = Config.defaultOf("dockPosition"); return d.charAt(0).toUpperCase() + d.slice(1); }
                    detail: "Click an edge. The menu bar is at the " + Config.s.barPosition + "; if you pick its edge, it moves to the opposite one"
                    EdgePicker { accent: win.accent; bar: false; edge: Config.s.dockPosition; onPicked: e => Config.moveDock(e) }
                }
                Separator {}
                ToggleSetting {
                    label: "Auto-hide"
                    detail: "Hide the dock while the workspace has tiled windows (floating ones leave it open, except in floating windows mode); push the pointer to the bottom edge to show it"
                    key: "dockAutoHide"
                }
                Separator {}
                ToggleSetting {
                    label: "Window previews"
                    detail: "Rest the pointer on an app with windows open to see them; click one to go to it (titles only, in game mode)"
                    key: "dockPreviews"
                }
                Separator { visible: Config.s.dockPreviews }
                SettingRow {
                    visible: Config.s.dockPreviews
                    label: "Previews appear after"
                    settingKey: "dockPreviewDelay"
                    detail: "How long to rest on an app before its windows show. Instant shows them as soon as the pointer arrives"
                    ValueSlider { from: 0; to: 3; stepSize: 0.1; decimals: 1; suffix: " s"; zeroText: "Instant"; value: Config.s.dockPreviewDelay; onMoved: v => Config.s.dockPreviewDelay = v }
                }
                Separator {}
                ToggleSetting {
                    label: "Badges and progress"
                    detail: "An app's unread count on its icon (what it says itself, or its unread notifications), and how far a download or copy has got"
                    key: "dockBadges"
                }
                Separator {}
                ToggleSetting {
                    label: "Divider"
                    detail: "A line after the Apps button and media controls, between the pinned apps and the others running, and before the Waste Basket"
                    key: "dockDivider"
                }
                Separator {}
                ToggleSetting {
                    label: "Apps button"
                    detail: "At the start of the dock: opens the launcher; right-click for Settings"
                    key: "dockShowLauncher"
                }
                Separator {}
                ToggleSetting {
                    label: "Media controls"
                    detail: "After the Apps button while something's playing: its album art (click it to go to the app) with Previous, Play/Pause and Next beside it (over the art on a side dock); right-click for them all"
                    key: "dockShowMedia"
                }
                Separator { visible: Config.s.dockShowMedia }
                SettingRow {
                    visible: Config.s.dockShowMedia
                    label: "Album art"
                    settingKey: "dockMediaArt"
                    detail: "The track's artwork beside the controls; off, just the controls"
                    Toggle { checked: Config.s.dockMediaArt; onToggled: v => Config.s.dockMediaArt = v }
                }
                Separator {}
                ToggleSetting {
                    label: "Downloads"
                    detail: "Before the Waste Basket: click for your newest downloads, right-click to open the folder"
                    key: "dockShowDownloads"
                }
                Separator {}
                ToggleSetting {
                    label: "Waste Basket"
                    detail: "At the end of the dock, filled when there's something in it: click to open it, right-click to empty it"
                    key: "dockShowTrash"
                }
            }
            GroupLabel { text: "Icons" }
            Group {
                SettingRow {
                    label: "Icon size"
                    settingKey: "dockIconSize"
                    ValueSlider { from: 28; to: 64; stepSize: 1; suffix: " px"; value: Config.s.dockIconSize; onMoved: v => Config.s.dockIconSize = v }
                }
                Separator {}
                DropdownSetting {
                    label: "Hover effect"
                    settingKey: "dockHoverEffect"
                    detail: ({
                        tilt: "With the pointer on the dock, the icons turn in 3D towards it, and the ones near it straighten up to face you (the one under it lifts a little)",
                        both: "With the pointer on the dock, the icons turn in 3D towards it, and the ones near it straighten up and grow",
                        fade: "The icons away from the pointer fade, so the ones near it stand out; all clear again when it leaves",
                        fademagnify: "The icons near the pointer grow, and the ones away from it fade",
                        glow: "The icon under the pointer gets a ring and a soft glow round it, in its own colour",
                        glowmagnify: "The icons near the pointer grow, and the one under it gets a ring and a soft glow in its own colour",
                        raise: "The icon under the pointer lifts up a little; the others stay where they are",
                        none: "The icons stay as they are"
                    })[Config.s.dockHoverEffect] ?? "The icons near the pointer grow, the one under it most"
                    options: [{ value: "magnify", label: "Magnify" }, { value: "tilt", label: "Tilt" },
                              { value: "both", label: "Magnify and tilt" }, { value: "fade", label: "Fade" },
                              { value: "fademagnify", label: "Fade and magnify" }, { value: "glow", label: "Glow" },
                              { value: "glowmagnify", label: "Glow and magnify" }, { value: "raise", label: "Raise" },
                              { value: "none", label: "None" }]
                    value: ["tilt", "both", "fade", "fademagnify", "glow", "glowmagnify", "raise", "none"].includes(Config.s.dockHoverEffect) ? Config.s.dockHoverEffect : "magnify"
                    onPicked: v => Config.s.dockHoverEffect = v
                }
                // Under the effect they belong to: magnifying's size, and how far either reaches
                Separator { visible: !["tilt", "fade", "glow", "raise", "none"].includes(Config.s.dockHoverEffect) }
                SettingRow {
                    visible: !["tilt", "fade", "glow", "raise", "none"].includes(Config.s.dockHoverEffect)
                    label: "Magnification"
                    settingKey: "dockMagnification"
                    detail: "How large the icon under the pointer grows"
                    ValueSlider { from: 1; to: 2.5; stepSize: 0.05; decimals: 2; suffix: "×"; value: Config.s.dockMagnification; onMoved: v => Config.s.dockMagnification = v }
                }
                Separator { visible: Config.s.dockHoverEffect !== "none" && Config.s.dockHoverEffect !== "raise" }
                SettingRow {
                    visible: Config.s.dockHoverEffect !== "none" && Config.s.dockHoverEffect !== "raise"
                    label: "Magnification spread"
                    settingKey: "dockSpread"
                    detail: "How many neighbouring icons rise in the arc (or turn, with tilt, or stay clear, with fade)"
                    ValueSlider { from: 1; to: 5; stepSize: 0.5; decimals: 1; value: Config.s.dockSpread; onMoved: v => Config.s.dockSpread = v }
                }
            }
            // (only with glass on: Appearance → Glass)
            GroupLabel { visible: Config.s.glass; text: "Glass" }
            Group {
                visible: Config.s.glass
                ToggleSetting {
                    label: "Blur"
                    detail: "What's behind the dock is blurred, like frosted glass. Off, you see straight through it"
                    key: "dockBlur"
                }
                Separator {}
                SettingRow {
                    label: "Background opacity"
                    settingKey: "dockOpacity"
                    detail: "How solid the dock's background is: 100% can't be seen through, lower is clearer"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round((Config.s.dockOpacity < 0 ? Config.dockGlassOpacity : Config.s.dockOpacity) * 100); onMoved: v => Config.s.dockOpacity = v / 100 }
                }
                Separator {}
                SettingRow {
                    label: "Tile opacity"
                    settingKey: "dockTileOpacity"
                    detail: "The tiles behind the dock's icons and its buttons: 100% is solid, lower lets the dock show through them"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.dockTileOpacity * 100); onMoved: v => Config.s.dockTileOpacity = v / 100 }
                }
                Separator {}
                SettingRow {
                    label: "Icon opacity"
                    settingKey: "dockIconOpacity"
                    detail: "The icons, and what's drawn on the dock's own buttons: 100% is solid, at 0% they're gone"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.dockIconOpacity * 100); onMoved: v => Config.s.dockIconOpacity = v / 100 }
                }
            }
        }
    }

    Component {
        id: spacesPage
        Column {
            spacing: 4
            PageTitle { text: "Spaces" }
            IntroText { text: "Save the apps on some workspaces, and where their windows sit, as a space; then bring them all back on new workspaces in one click from the Spaces button on the menu bar." }
            GroupLabel { text: "Menu Bar" }
            Group {
                ToggleSetting {
                    label: "Spaces button"
                    detail: "Between Apps and the workspaces: your spaces, and New Space"
                    key: "barShowSpaces"
                }
                Separator {}
                ToggleSetting {
                    label: "Colour the window's icon"
                    detail: "When the focused window came from a space, its icon on the menu bar sits on the space's colour"
                    key: "spaceBarTint"
                }
            }
            GroupLabel { text: "Windows from a space" }
            Group {
                ToggleSetting {
                    label: "Top border"
                    detail: "A thin line in the space's colour along the top of each window"
                    key: "spaceBorders"
                }
                Separator {}
                ToggleSetting {
                    label: "Corner badge"
                    detail: "The space's icon in the window's top left corner; it moves to the other corner when the pointer comes near"
                    key: "spaceBadges"
                }
                Separator {}
                ToggleSetting {
                    label: "Badges in the switchers"
                    detail: "The space's icon on its windows in the window switcher (Super+Tab) and the workspace overview (Super+Down)"
                    key: "spaceSwitcherBadges"
                }
            }
        }
    }

    Component {
        id: screensaverPage
        Column {
            id: ssCol
            spacing: 4
            readonly property var minutes: win.minuteOptions([0, 1, 2, 3, 5, 10, 15, 20, 30])
            PageTitle { text: "Screensaver" }
            IntroText { text: "Covers the screen while you're away, before the lock and screen-off times in Lock & idle. Any key, click or move of the pointer puts it away." }
            GroupLabel { text: "Style & timing" }
            Group {
                DropdownSetting {
                    label: "Start after"
                    settingKey: "screensaverMinutes"
                    detail: Config.s.idleLockMinutes > 0 && Config.s.screensaverMinutes >= Config.s.idleLockMinutes
                        ? "The screen locks at " + Config.s.idleLockMinutes + " minutes (Lock & idle), so it won't show"
                        : "Of no input. Video and apps that keep the screen awake hold it off"
                    options: ssCol.minutes
                    value: Config.s.screensaverMinutes
                    onPicked: v => Config.s.screensaverMinutes = v
                }
                Separator {}
                DropdownSetting {
                    // The background; whether there's a clock on it is Show the clock, below
                    label: "Style"
                    settingKey: "screensaverStyle"
                    options: [{ value: "drift", label: "Your wallpaper" },
                              { value: "slideshow", label: "Wallpaper slideshow" },
                              { value: "videos", label: "Videos" },
                              { value: "black", label: "Black" }]
                    value: Config.s.screensaverStyle
                    onPicked: v => Config.s.screensaverStyle = v
                    detail: Config.s.screensaverStyle === "drift" ? "Your wallpaper, dimmed and slowly drifting"
                        : Config.s.screensaverStyle === "slideshow" ? "The pictures in your wallpaper folder, fading from one to the next"
                        : Config.s.screensaverStyle === "videos" ? (Config.multimediaAvailable ? "The videos in a folder, silent, fading from one to the next"
                            : "The videos in a folder, silent. Needs Qt Multimedia (the qt6-multimedia package), which isn't installed")
                        : "Plain black; best for OLED screens"
                }
                Separator { visible: Config.s.screensaverStyle === "videos" }
                SettingRow {
                    id: vidRow
                    visible: Config.s.screensaverStyle === "videos"
                    label: "Videos folder"
                    // Get scenery videos: twelve free clips (Earth from the ISS, an aurora, lakes,
                    // coasts, mountains, penguins…) from Wikimedia Commons (scripts/screensaver-videos.py)
                    property string status: ""
                    property real progress: 0          // the whole download, 0 to 1
                    detail: status !== "" ? status
                        : Config.screensaverVideoFolder.replace(Quickshell.env("HOME"), "~") + ": MP4, WebM, MKV or MOV, played in a shuffled order. "
                          + "Get scenery videos adds twelve free clips (credits in the folder's CREDITS.txt)"
                    Process {
                        id: sceneryRun
                        command: [Quickshell.shellPath("scripts/screensaver-videos.py"), Config.screensaverVideoFolder, Config.sceneryQuality]
                        stdout: SplitParser {
                            onRead: line => {
                                if (line.startsWith("progress ")) { vidRow.progress = Number(line.slice(9)) || 0; return; }
                                const m = line.match(/^(\d+)\/(\d+) (.*)$/);
                                if (m) vidRow.status = "Downloading " + m[1] + " of " + m[2] + ": " + m[3] + "…";
                                else if (line.startsWith("done ")) vidRow.status = line.slice(5) === "0" ? "Slate couldn't download any videos. Are you online?"
                                    : "Got " + line.slice(5) + " scenery videos, in " + Config.screensaverVideoFolder.replace(Quickshell.env("HOME"), "~");
                            }
                        }
                        onExited: code => { if (code !== 0 && !vidRow.status.startsWith("Got")) vidRow.status = "Slate couldn't download the videos this time"; }
                    }
                    // How far the download's got: a thin bar along the bottom of the row while it runs
                    Rectangle {
                        parent: vidRow
                        visible: sceneryRun.running
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 6 }
                        height: 4; radius: 2
                        color: win.control
                        Rectangle {
                            width: Math.max(height, parent.width * vidRow.progress); height: parent.height; radius: 2
                            color: win.accent
                            Behavior on width { NumberAnimation { duration: Config.ms(200) } }
                        }
                    }
                    Row {
                        spacing: 8
                        Button {
                            icon: 0xEA96; label: sceneryRun.running ? "Downloading…" : "Get scenery videos"
                            opacity: sceneryRun.running ? 0.5 : 1
                            onClicked: if (!sceneryRun.running) { vidRow.status = "Starting…"; vidRow.progress = 0; sceneryRun.running = true; }
                        }
                        Button {
                            icon: 0xEAAD; label: "Open folder"
                            onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && exec xdg-open \"$0\"", Config.screensaverVideoFolder])
                        }
                    }
                }
                Separator { visible: Config.s.screensaverStyle === "videos" }
                // The size Get scenery videos downloads in (clips without that size come in their
                // largest). Raising it later fetches again only the clips that get sharper
                DropdownSetting {
                    visible: Config.s.screensaverStyle === "videos"
                    readonly property var names: ({ "2160p": "4K", "1440p": "1440p", "1080p": "1080p" })
                    label: "Scenery quality"
                    settingKey: "screensaverVideoQuality"
                    detail: "For Get scenery videos: sharper is bigger (4K is about 1.1 GB in all, 1440p about 780 MB, 1080p about 410 MB). Choosing a higher one and getting them again replaces only the clips that get sharper"
                    options: [{ value: "auto", label: "Automatic (" + names[Config.screenSceneryQuality] + " for this screen)" },
                              { value: "2160p", label: "4K" }, { value: "1440p", label: "1440p" }, { value: "1080p", label: "1080p" }]
                    value: Config.s.screensaverVideoQuality || "auto"
                    onPicked: v => Config.s.screensaverVideoQuality = v
                }
                Separator {}
                SettingRow {
                    label: "Show the clock"
                    settingKey: "screensaverClock"
                    detail: Config.s.screensaverStyle === "black" ? "The time and date, moving now and then so nothing burns in"
                        : "The time and date in the middle"
                    Toggle { checked: Config.s.screensaverClock; onToggled: v => Config.s.screensaverClock = v }
                }
                Separator { visible: Config.s.screensaverStyle === "slideshow" }
                DropdownSetting {
                    visible: Config.s.screensaverStyle === "slideshow"
                    label: "Change picture every"
                    settingKey: "screensaverSlideSeconds"
                    options: [10, 20, 30, 60, 120, 300].map(s => ({ value: s, label: s < 60 ? s + " seconds" : (s / 60) + (s === 60 ? " minute" : " minutes") }))
                    value: Config.s.screensaverSlideSeconds
                    onPicked: v => Config.s.screensaverSlideSeconds = v
                }
                Separator {}
                ToggleSetting {
                    label: "Lock on wake"
                    detail: "Waking it shows the lock screen, so you'll need your password to get back in"
                    key: "screensaverLock"
                }
                Separator {}
                SettingRow {
                    label: "Preview"
                    detail: "Shows it now; any key, click or pointer move puts it away (it doesn't lock)"
                    // Settings stays open beneath it (the screensaver covers every window), so it's
                    // still here when the preview ends
                    Button { label: "Preview"; onClicked: Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "screensaver", "start"]) }
                }
            }
        }
    }

    Component {
        id: launcherPage
        Column {
            spacing: 4
            PageTitle { text: "Launcher" }
            GroupLabel { text: "Layout" }
            Group {
                SettingRow {
                    label: "Layout"
                    settingKey: "launcherLayout"
                    detail: Config.s.launcherLayout === "grid"
                        ? "Apps as a grid of icons, with the selected one's name along the bottom. Arrow keys move around it; Ctrl+Left/Right opens an app on a new workspace beside this one"
                        : "Apps in a list, with descriptions. Left/Right opens an app on a new workspace beside this one"
                    // Two-way switch: List | Grid
                    Rectangle {
                        readonly property var modes: ["list", "grid"]
                        width: 184; height: 34; radius: 9
                        color: win.well
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.s.launcherLayout)) * 92
                            color: win.accent
                            Behavior on x { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
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
                                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                                    }
                                    HoverHandler { id: layoutHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.glyph(layoutOpt.modelData.icon); color: layoutOpt.on ? win.accentText : win.dim; font.family: win.bar.iconFont; font.pixelSize: 15 }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: layoutOpt.modelData.label; color: layoutOpt.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    ClickTap { onTapped: Config.s.launcherLayout = layoutOpt.modelData.mode }
                                }
                            }
                        }
                    }
                }
                Separator { visible: Config.s.launcherLayout === "grid" }
                SettingRow {
                    visible: Config.s.launcherLayout === "grid"
                    label: "Columns"
                    settingKey: "launcherColumns"
                    detail: "Apps across the grid; the icons get smaller the more there are"
                    ValueSlider { from: 3; to: 10; stepSize: 1; value: Config.s.launcherColumns; onMoved: v => Config.s.launcherColumns = Math.round(v) }
                }
                Separator { visible: Config.s.launcherLayout === "grid" }
                SettingRow {
                    visible: Config.s.launcherLayout === "grid"
                    label: "Rows"
                    settingKey: "launcherRows"
                    detail: "Rows shown at once, which sets the launcher's height (scroll for more)"
                    ValueSlider { from: 2; to: 8; stepSize: 1; value: Config.s.launcherRows; onMoved: v => Config.s.launcherRows = Math.round(v) }
                }
                Separator {}
                SettingRow {
                    label: "Show descriptions"
                    settingKey: "launcherDescriptions"
                    detail: Config.s.launcherLayout === "grid" ? "What the selected app is, under its name at the bottom" : "A short line under each app's name"
                    Toggle { checked: Config.s.launcherDescriptions; onToggled: v => Config.s.launcherDescriptions = v }
                }
                Separator {}
                ToggleSetting {
                    label: "Most used first"
                    detail: "Order apps by how often you open them (after how well they match your search)"
                    key: "launcherSortByUsage"
                }
                Separator {}
                ToggleSetting {
                    label: "Wrap around"
                    detail: "The arrow keys go from the last result back to the first, and from the first to the last"
                    key: "launcherWrap"
                }
                Separator {}
                ToggleSetting {
                    label: "Recent apps first"
                    detail: "Before you type: the apps you opened most recently, at the top"
                    key: "launcherRecent"
                }
            }
            GroupLabel { text: "What it finds" }
            Group {
                ToggleSetting {
                    label: "Forgiving search"
                    detail: "Initials and little typos still find your apps: gc for GNOME Calculator, fierfox for Firefox"
                    key: "launcherFuzzy"
                }
                Separator {}
                ToggleSetting {
                    label: "Open windows"
                    detail: "Type part of a window's title to go to it, wherever it is"
                    key: "launcherWindows"
                }
                Separator {}
                ToggleSetting {
                    label: "App actions"
                    detail: "What apps offer besides opening, like Firefox's New Private Window"
                    key: "launcherActions"
                }
                Separator {}
                ToggleSetting {
                    label: "Quick toggles"
                    detail: "Wi-Fi, Bluetooth, Do Not Disturb, night light and game mode, switched from the results"
                    key: "launcherToggles"
                }
                Separator {}
                ToggleSetting {
                    label: "Files and folders"
                    detail: "Files you opened recently, and folders in your home by name"
                    key: "launcherFiles"
                }
                Separator {}
                ToggleSetting {
                    label: "Conversions"
                    detail: "Units and dates beside the calculator: 5 km in miles, 72 f to c, today + 30 days"
                    key: "launcherConvert"
                }
                Separator {}
                ToggleSetting {
                    label: "Run commands"
                    detail: "Start with > to run a command, in a terminal or on its own"
                    key: "launcherCommands"
                }
                Separator {}
                ToggleSetting {
                    label: "Emoji"
                    detail: "Start with : to find an emoji by name (:smile); Enter copies it"
                    key: "launcherEmoji"
                }
                Separator {}
                ToggleSetting {
                    label: "Search the web"
                    detail: "A last result that searches the web for what you typed"
                    key: "launcherWeb"
                }
                Separator { visible: Config.s.launcherWeb }
                DropdownSetting {
                    visible: Config.s.launcherWeb
                    label: "Search engine"
                    settingKey: "launcherSearchEngine"
                    options: [{ value: "duckduckgo", label: "DuckDuckGo" }, { value: "google", label: "Google" }, { value: "bing", label: "Bing" },
                              { value: "brave", label: "Brave Search" }, { value: "startpage", label: "Startpage" }, { value: "ecosia", label: "Ecosia" }]
                    value: Config.s.launcherSearchEngine
                    onPicked: v => Config.s.launcherSearchEngine = v
                }
            }
        }
    }

    Component {
        id: displaysPage
        Column {
            id: displaysPane
            spacing: 4
            PageTitle { text: "Displays" }
            Displays { id: disp }
            // The monitor being set up below the arrangement (Hyprland's name, e.g. DP-1)
            property string selected: ""
            // (with none chosen yet, the first one in use rather than one that's off)
            readonly property var mon: disp.monitors.find(m => m.name === selected) || disp.monitors.find(m => !m.disabled) || disp.monitors[0] || null
            readonly property var cfg: mon ? disp.configOf(mon) : null
            readonly property int enabledCount: disp.monitors.filter(m => !m.disabled).length
            readonly property bool hdrShown: !!mon && !!cfg && !cfg.disabled && disp.hdrCapable(mon)

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
                            readonly property bool chosen: displaysPane.mon && displaysPane.mon.name === modelData.name
                            readonly property real homeX: arrange.box.ox + (c.x - arrange.box.x0) * arrange.box.k
                            readonly property real homeY: arrange.box.oy + (c.y - arrange.box.y0) * arrange.box.k
                            x: homeX; y: homeY
                            width: Math.max(24, sz.w * arrange.box.k - 4); height: Math.max(18, sz.h * arrange.box.k - 4)
                            radius: 6
                            color: chosen ? win.accent : win.outline
                            border.width: 1; border.color: chosen ? win.accent : win.ring
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
                            ClickTap { onTapped: displaysPane.selected = tile.modelData.name }
                            DragHandler {
                                id: drag
                                enabled: arrange.live.length > 1
                                onActiveChanged: {
                                    if (active) { displaysPane.selected = tile.modelData.name; return; }
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
            GroupLabel { visible: !!displaysPane.mon; text: displaysPane.mon ? disp.displayName(displaysPane.mon) + " (" + displaysPane.mon.name + ")" : "" }
            Group {
                visible: !!displaysPane.mon
                SettingRow {
                    visible: disp.monitors.length > 1
                    label: "Use this display"
                    detail: displaysPane.cfg && !displaysPane.cfg.disabled && displaysPane.enabledCount <= 1 ? "The only display in use can't be turned off" : "Turn it off to leave it dark and unused"
                    Toggle {
                        checked: displaysPane.cfg ? !displaysPane.cfg.disabled : true
                        opacity: displaysPane.cfg && !displaysPane.cfg.disabled && displaysPane.enabledCount <= 1 ? 0.4 : 1
                        onToggled: v => { if (v || displaysPane.enabledCount > 1) displaysPane.change("disabled", !v); }
                    }
                }
                Separator { visible: disp.monitors.length > 1 }
                DropdownSetting {
                    visible: displaysPane.cfg && !displaysPane.cfg.disabled
                    label: "Resolution"
                    detail: "The sizes this display reports. Laptop panels often report only their own; to make things larger or smaller there, use Scale"
                    options: displaysPane.mon ? disp.resolutionOptions(displaysPane.mon) : []
                    value: displaysPane.cfg ? displaysPane.cfg.mode.split("@")[0] : ""
                    // Keeps the refresh rate if the new size has it, else its fastest
                    onPicked: v => displaysPane.change("mode", disp.modeAt(displaysPane.mon, v, displaysPane.cfg.mode.split("@")[1]))
                }
                Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
                DropdownSetting {
                    visible: displaysPane.cfg && !displaysPane.cfg.disabled
                    label: "Refresh rate"
                    detail: "How many times a second the picture updates, from the rates this resolution has. Higher is smoother"
                    options: displaysPane.mon && displaysPane.cfg ? disp.refreshOptions(displaysPane.mon, displaysPane.cfg.mode.split("@")[0]) : []
                    value: displaysPane.cfg ? displaysPane.cfg.mode.split("@")[1] : ""
                    onPicked: v => displaysPane.change("mode", displaysPane.cfg.mode.split("@")[0] + "@" + v)
                }
                Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
                DropdownSetting {
                    visible: displaysPane.cfg && !displaysPane.cfg.disabled
                    label: "Scale"
                    detail: "How large everything on this display looks, apps included. Only scales that suit the resolution are offered. "
                        + "To resize just Slate (the bar, dock and panels) on every display, use Interface size in Appearance"
                    options: displaysPane.cfg ? disp.scaleOptions(displaysPane.cfg.mode, displaysPane.cfg.scale) : []
                    value: displaysPane.cfg ? displaysPane.cfg.scale : 1
                    onPicked: v => displaysPane.change("scale", v)
                }
                Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
                DropdownSetting {
                    visible: displaysPane.cfg && !displaysPane.cfg.disabled
                    label: "Rotation"
                    options: disp.transformOptions
                    value: displaysPane.cfg ? displaysPane.cfg.transform : 0
                    onPicked: v => displaysPane.change("transform", v)
                }
                // HDR: only for displays that can show it
                Separator { visible: displaysPane.hdrShown }
                DropdownSetting {
                    visible: displaysPane.hdrShown
                    label: "HDR"
                    detail: "Auto: HDR while a game or video fills the screen with HDR content. On: always, in 10-bit colour. Off: never"
                    options: disp.hdrOptions
                    value: displaysPane.cfg ? displaysPane.cfg.hdr : "auto"
                    onPicked: v => displaysPane.change("hdr", v)
                }
                Separator { visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on" }
                SettingRow {
                    visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on"
                    label: "SDR brightness"
                    detail: "How bright everything that isn't HDR (most apps, the desktop) looks while HDR is on"
                    ValueSlider { from: 0.5; to: 2; stepSize: 0.05; decimals: 2; suffix: "×"; value: displaysPane.cfg ? displaysPane.cfg.sdrBrightness : 1; onMoved: v => displaysPane.change("sdrBrightness", v) }
                }
                Separator { visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on" }
                SettingRow {
                    visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on"
                    label: "SDR colour"
                    detail: "How colourful everything that isn't HDR looks while HDR is on"
                    ValueSlider { from: 0.5; to: 1.5; stepSize: 0.05; decimals: 2; suffix: "×"; value: displaysPane.cfg ? displaysPane.cfg.sdrSaturation : 1; onMoved: v => displaysPane.change("sdrSaturation", v) }
                }
                Separator { visible: disp.monitors.length > 1 }
                DropdownSetting {
                    visible: disp.monitors.length > 1
                    label: "Main display"
                    settingKey: "mainDisplay"
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
            Footnote { text: "Slate's own size (bar, panels, this window) is under Appearance → Interface size, on top of each display's scale. Monitor rules in ~/.config/slate/hypr/monitors.lua override these." }
        }
    }

    // ---- Keyboard & Mouse ----------------------------------------------------
    // Only what's changed here is set (Config.hyprSettings); the rest shows what Hyprland's
    // config (and your own hyprland.lua) has, read when the page opens
    Component {
        id: inputPage
        Column {
            id: inputPane
            spacing: 4
            PageTitle { text: "Keyboard & Mouse" }
            property var cur: ({})
            property var layoutOptions: []
            property bool hasTouchpad: false
            Process {
                running: true
                command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:kb_layout", "input:kb_variant", "input:kb_options",
                    "input:repeat_rate", "input:repeat_delay", "input:sensitivity", "input:accel_profile", "input:natural_scroll",
                    "input:touchpad:natural_scroll", "input:touchpad:tap-to-click", "input:touchpad:disable_while_typing",
                    "input:touchpad:scroll_factor"]
                stdout: StdioCollector { onStreamFinished: { try { inputPane.cur = JSON.parse(text); } catch (e) {} } }
            }
            Process {
                running: true
                command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
                stdout: StdioCollector { onStreamFinished: { try { inputPane.layoutOptions = JSON.parse(text); } catch (e) {} } }
            }
            Process {
                running: true
                command: ["hyprctl", "devices", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { inputPane.hasTouchpad = JSON.parse(text).mice.some(m => m.name.toLowerCase().includes("touchpad")); } catch (e) {} } }
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
                SearchPicker {
                    label: "Add a layout"
                    detail: "Search by language or name, e.g. French or Dvorak"
                    buttonLabel: "Add…"
                    buttonIcon: 0xEB0B
                    options: inputPane.layoutOptions
                    onPicked: v => {
                        const parts = String(v).split(":");
                        const l = inputPane.layouts.slice();
                        if (!l.some(x => x.layout === parts[0] && x.variant === (parts[1] || "")))
                            l.push({ layout: parts[0], variant: parts[1] || "" });
                        inputPane.setLayouts(l);
                    }
                }
            }
            GroupLabel { text: "Your layouts" }
            // The layouts in use, in their own container under Add a layout
            Group {
                Repeater {
                    model: inputPane.layouts
                    delegate: Column {
                        id: layoutRow
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        Separator { visible: layoutRow.index > 0 }
                        ListItemRow {
                            label: inputPane.layoutName(layoutRow.modelData)
                            detail: inputPane.layouts.length > 1 && layoutRow.index === 0 ? "Used first" : ""
                            removable: inputPane.layouts.length > 1
                            onRemoved: { const l = inputPane.layouts.slice(); l.splice(layoutRow.index, 1); inputPane.setLayouts(l); }
                        }
                    }
                }
            }
            GroupLabel { text: "Switching & keys" }
            Group {
                DropdownSetting {
                    visible: inputPane.layouts.length > 1
                    label: "Switch layouts with"
                    settingKey: "kbSwitch"
                    options: [{ value: "alt_shift", label: "Alt+Shift" }, { value: "ctrl_space", label: "Ctrl+Space" },
                              { value: "caps", label: "Caps Lock" }, { value: "none", label: "No shortcut" }]
                    value: inputPane.switchValue
                    onPicked: v => Config.s.kbSwitch = v
                }
                Separator { visible: inputPane.layouts.length > 1 }
                DropdownSetting {
                    label: "Caps Lock key"
                    settingKey: "capsLock"
                    detail: inputPane.switchValue === "caps" && inputPane.layouts.length > 1 ? "It switches layouts (above)" : "What the Caps Lock key does"
                    options: [{ value: "default", label: "Caps Lock" }, { value: "ctrl", label: "Another Ctrl" },
                              { value: "escape", label: "Escape" }, { value: "off", label: "Nothing" }]
                    value: inputPane.capsValue
                    onPicked: v => Config.s.capsLock = v
                }
                Separator {}
                SettingRow {
                    label: "Repeat delay"
                    settingKey: "keyRepeatDelay"
                    detail: "How long a held key waits before it repeats"
                    ValueSlider {
                        from: 150; to: 1000; stepSize: 25; suffix: " ms"
                        value: Config.s.keyRepeatDelay > 0 ? Config.s.keyRepeatDelay : (inputPane.cur["input:repeat_delay"] || 600)
                        onMoved: v => Config.s.keyRepeatDelay = Math.round(v)
                    }
                }
                Separator {}
                SettingRow {
                    label: "Repeat speed"
                    settingKey: "keyRepeatRate"
                    detail: "How fast a held key repeats"
                    ValueSlider {
                        from: 10; to: 80; stepSize: 1; suffix: " /s"
                        value: Config.s.keyRepeatRate > 0 ? Config.s.keyRepeatRate : (inputPane.cur["input:repeat_rate"] || 25)
                        onMoved: v => Config.s.keyRepeatRate = Math.round(v)
                    }
                }
            }

            GroupLabel { text: "Mouse" }
            Group {
                SettingRow {
                    label: "Pointer speed"
                    settingKey: "mouseSpeed"
                    defaultText: "Hyprland's own"       // (not set here until you move it)
                    detail: inputPane.hasTouchpad ? "Mice and touchpads. Slower to faster; 0 is the device's own speed" : "Slower to faster; 0 is the mouse's own speed"
                    ValueSlider {
                        per: 100
                        from: -100; to: 100; stepSize: 5
                        value: Math.round((Config.s.mouseSpeed >= -1 ? Config.s.mouseSpeed : (inputPane.cur["input:sensitivity"] || 0)) * 100)
                        onMoved: v => Config.s.mouseSpeed = v / 100
                    }
                }
                Separator {}
                SettingRow {
                    label: "Acceleration"
                    settingKey: "mouseAccel"
                    detail: "Quick movements carry the pointer further. Off: the same distance however fast you move"
                    Toggle {
                        checked: (Config.s.mouseAccel !== "" ? Config.s.mouseAccel : (inputPane.cur["input:accel_profile"] || "adaptive")) !== "flat"
                        onToggled: v => Config.s.mouseAccel = v ? "adaptive" : "flat"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Natural scrolling"
                    settingKey: "mouseNaturalScroll"
                    detail: "Content moves the way the wheel turns, like a touch screen"
                    Toggle {
                        checked: Config.s.mouseNaturalScroll !== "" ? Config.s.mouseNaturalScroll === "on" : !!inputPane.cur["input:natural_scroll"]
                        onToggled: v => Config.s.mouseNaturalScroll = v ? "on" : "off"
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Pointer size"
                    settingKey: "cursorSize"
                    detail: "Apps opened from now on use it too"
                    options: [16, 20, 24, 32, 40, 48, 64].map(n => ({ value: n, label: n + " px" }))
                    value: Config.s.cursorSize > 0 ? Config.s.cursorSize : 20
                    onPicked: v => Config.s.cursorSize = v
                }
            }

            GroupLabel { visible: inputPane.hasTouchpad; text: "Touchpad" }
            Group {
                visible: inputPane.hasTouchpad
                SettingRow {
                    label: "Scroll speed"
                    settingKey: "touchpadScrollSpeed"
                    defaultText: "Hyprland's own"       // (not set here until you move it)
                    ValueSlider {
                        per: 100
                        from: 10; to: 200; stepSize: 10; suffix: "%"
                        value: Math.round((Config.s.touchpadScrollSpeed > 0 ? Config.s.touchpadScrollSpeed : (inputPane.cur["input:touchpad:scroll_factor"] || 1)) * 100)
                        onMoved: v => Config.s.touchpadScrollSpeed = v / 100
                    }
                }
                Separator {}
                SettingRow {
                    label: "Natural scrolling"
                    settingKey: "touchpadNaturalScroll"
                    detail: "Content follows your fingers, like a phone"
                    Toggle {
                        checked: Config.s.touchpadNaturalScroll !== "" ? Config.s.touchpadNaturalScroll === "on" : !!inputPane.cur["input:touchpad:natural_scroll"]
                        onToggled: v => Config.s.touchpadNaturalScroll = v ? "on" : "off"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Tap to click"
                    settingKey: "touchpadTapToClick"
                    Toggle {
                        checked: Config.s.touchpadTapToClick !== "" ? Config.s.touchpadTapToClick === "on" : inputPane.cur["input:touchpad:tap-to-click"] !== false
                        onToggled: v => Config.s.touchpadTapToClick = v ? "on" : "off"
                    }
                }
                Separator {}
                SettingRow {
                    label: "Ignore while typing"
                    settingKey: "touchpadIgnoreWhileTyping"
                    detail: "Stops a palm on the touchpad moving the pointer as you type"
                    Toggle {
                        checked: Config.s.touchpadIgnoreWhileTyping !== "" ? Config.s.touchpadIgnoreWhileTyping === "on" : inputPane.cur["input:touchpad:disable_while_typing"] !== false
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
            id: soundPane
            spacing: 4
            PageTitle { text: "Sound" }
            readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
            readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property var source: Pipewire.defaultAudioSource
            PwObjectTracker { objects: [soundPane.sink, soundPane.source] }
            function nodeName(n) { return n ? (n.description || n.nickname || n.name) : ""; }

            GroupLabel { text: "Output" }
            Group {
                DropdownSetting {
                    label: "Play sound through"
                    options: soundPane.sinks.map(n => ({ value: n.id, label: soundPane.nodeName(n) }))
                    value: soundPane.sink ? soundPane.sink.id : -1
                    onPicked: v => { const n = soundPane.sinks.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSink = n; }
                }
                Separator {}
                SettingRow {
                    label: "Volume"
                    ValueSlider {
                        from: 0; to: 100; stepSize: 1; suffix: "%"
                        value: soundPane.sink && soundPane.sink.audio ? Math.round(soundPane.sink.audio.volume * 100) : 0
                        onMoved: v => { if (soundPane.sink && soundPane.sink.audio) soundPane.sink.audio.volume = v / 100; }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Mute"
                    Toggle {
                        checked: !!(soundPane.sink && soundPane.sink.audio && soundPane.sink.audio.muted)
                        onToggled: v => { if (soundPane.sink && soundPane.sink.audio) soundPane.sink.audio.muted = v; }
                    }
                }
            }
            GroupLabel { text: "Input" }
            Group {
                DropdownSetting {
                    label: "Microphone"
                    options: soundPane.sources.map(n => ({ value: n.id, label: soundPane.nodeName(n) }))
                    value: soundPane.source ? soundPane.source.id : -1
                    onPicked: v => { const n = soundPane.sources.find(x => x.id === v); if (n) Pipewire.preferredDefaultAudioSource = n; }
                }
                Separator {}
                SettingRow {
                    label: "Input level"
                    ValueSlider {
                        from: 0; to: 100; stepSize: 1; suffix: "%"
                        value: soundPane.source && soundPane.source.audio ? Math.round(soundPane.source.audio.volume * 100) : 0
                        onMoved: v => { if (soundPane.source && soundPane.source.audio) soundPane.source.audio.volume = v / 100; }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Mute the microphone"
                    Toggle {
                        checked: !!(soundPane.source && soundPane.source.audio && soundPane.source.audio.muted)
                        onToggled: v => { if (soundPane.source && soundPane.source.audio) soundPane.source.audio.muted = v; }
                    }
                }
            }
            GroupLabel { text: "Sound effects" }
            Group {
                SoundSetting {
                    label: "Volume keys"
                    detail: "A short tick at the new volume when you press the volume keys"
                    which: "tick"; sample: "volume-tick"
                }
                Separator {}
                SoundSetting {
                    label: "Notifications"
                    detail: "A soft chime when a notification pops up (silent during Do Not Disturb)"
                    which: "notification"; sample: "notification"
                }
                Separator {}
                SoundSetting {
                    label: "Questions and warnings"
                    detail: "A soft, questioning sound when Slate asks you to confirm something, an app asks for your password, or a notification is urgent"
                    which: "attention"; sample: "attention"
                }
                Separator {}
                SoundSetting {
                    label: "Clicks"
                    detail: Config.clickAvailable ? "A barely-there tap when you press Slate's buttons, menus and switches"
                                                  : "Needs Qt Multimedia (qt6-multimedia), so the click is on time"
                    which: "click"; sample: "click"; available: Config.clickAvailable
                }
                Separator {}
                SoundSetting {
                    label: "Switching"
                    detail: "A soft swish when you change workspace or move through the window switcher and overview, drifting the way you're going"
                    which: "swish"; sample: "swish-right"
                }
                Separator {}
                SoundSetting {
                    label: "Welcome"
                    detail: "A gentle, warm swell when you log in (not when Slate reloads)"
                    which: "welcome"; sample: "welcome"
                }
                Separator {}
                SoundSetting {
                    label: "Goodbye"
                    detail: "A gentle closing sound when you log out, restart or shut down (it plays first, so they take a moment longer)"
                    which: "goodbye"; sample: "goodbye"
                }
            }
        }
    }

    // ---- Power ------------------------------------------------------------------
    Component {
        id: powerPage
        Column {
            id: powerPane
            spacing: 4
            PageTitle { text: "Power" }
            property bool hasLid: false
            Process {
                running: true
                command: ["hyprctl", "devices", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { powerPane.hasLid = (JSON.parse(text).switches || []).some(x => /lid/i.test(x.name)); } catch (e) {} } }
            }
            readonly property var profileOptions: [{ value: "", label: "Leave it as it is" }, { value: "power-saver", label: "Power saver" },
                { value: "balanced", label: "Balanced" }].concat(PowerProfiles.hasPerformanceProfile ? [{ value: "performance", label: "Performance" }] : [])

            GroupLabel { text: "Lid and power button" }
            Group {
                DropdownSetting {
                    visible: powerPane.hasLid
                    label: "Closing the lid"
                    settingKey: "lidAction"
                    detail: !Config.canInhibit ? Config.noLogindNote
                        : Config.s.lidAction === "" ? "Left to the system (usually suspends)"
                        : "With another screen connected, only the laptop's own screen turns off"
                    // (holding the system's own handling back needs systemd or elogind: Config.system)
                    enabled: Config.canInhibit
                    opacity: enabled ? 1 : 0.5
                    options: [{ value: "", label: "System default" }, { value: "suspend", label: "Suspend" }, { value: "lock", label: "Lock the screen" },
                              { value: "screenoff", label: "Turn the screen off" }, { value: "nothing", label: "Do nothing" }]
                        .filter(o => o.value !== "suspend" || Config.canSuspend)
                    value: Config.s.lidAction
                    onPicked: v => Config.s.lidAction = v
                }
                Separator { visible: powerPane.hasLid }
                DropdownSetting {
                    label: "Power button"
                    settingKey: "powerKeyAction"
                    enabled: Config.canInhibit
                    opacity: enabled ? 1 : 0.5
                    detail: !Config.canInhibit ? Config.noLogindNote
                        : Config.s.powerKeyAction === "" ? "Left to the system (usually shuts down)" : ""
                    options: [{ value: "", label: "System default" }, { value: "menu", label: "Show the power menu" }, { value: "suspend", label: "Suspend" },
                              { value: "poweroff", label: "Shut down (asks first)" }, { value: "lock", label: "Lock the screen" }, { value: "nothing", label: "Do nothing" }]
                        .filter(o => (o.value !== "suspend" || Config.canSuspend) && (o.value !== "poweroff" || Config.canPowerOff))
                    value: Config.s.powerKeyAction
                    onPicked: v => Config.s.powerKeyAction = v
                }
            }
            // The charging limit: where the laptop can stop charging short of full, which is
            // kinder to a battery that's mostly plugged in. The system's power service (UPower)
            // keeps it, with the level the laptop's maker set, and lets whoever's at the laptop
            // switch it on and off. The row only shows where it's there to switch
            property var battery: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
            readonly property string batteryPath: battery && battery.nativePath
                ? "/org/freedesktop/UPower/devices/battery_" + String(battery.nativePath).split("/").pop().replace(/[^A-Za-z0-9]/g, "_") : ""
            property bool limitSupported: false
            property bool limitOn: false
            property int limitAt: 80
            onBatteryPathChanged: if (batteryPath !== "") limitAsk.running = true
            Component.onCompleted: if (batteryPath !== "") limitAsk.running = true
            Process {
                id: limitAsk
                command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.UPower", "--object-path", powerPane.batteryPath,
                          "--method", "org.freedesktop.DBus.Properties.GetAll", "org.freedesktop.UPower.Device"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const end = /'ChargeEndThreshold': <uint32 (\d+)>/.exec(text);
                        powerPane.limitSupported = /'ChargeThresholdSupported': <true>/.test(text) && !!end && Number(end[1]) > 0 && Number(end[1]) < 100;
                        powerPane.limitOn = /'ChargeThresholdEnabled': <true>/.test(text);
                        if (end) powerPane.limitAt = Number(end[1]);
                    }
                }
            }
            Process {
                id: limitSet
                property bool to: true
                command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.UPower", "--object-path", powerPane.batteryPath,
                          "--method", "org.freedesktop.UPower.Device.EnableChargeThreshold", to ? "true" : "false"]
                onExited: limitAsk.running = true
            }
            function setLimit(on) { limitOn = on; limitSet.to = on; limitSet.running = true; }
            // (charging past the limit is asked about first: it's the battery's life at stake)
            function askLimit(on) {
                if (on || !win.confirmer) { setLimit(on); return; }
                win.confirmer.confirmWith({
                    title: "Charge all the way to full?",
                    body: "Keeping a battery full wears it out sooner, most of all when your laptop spends its days plugged in. "
                        + "Stopping at " + limitAt + "% helps it hold its charge for years longer. Charging to full is worth it when "
                        + "you need every hour away from a socket. You can switch the limit back on at any time.",
                    button: "Charge to full", code: 0xEA33, danger: false
                }, () => powerPane.setLimit(false));
            }
            GroupLabel { text: "Power mode" }
            Group {
                DropdownSetting {
                    label: "On battery"
                    settingKey: "profileOnBattery"
                    detail: "Switched to when you unplug; the control centre can still change it any time"
                    options: powerPane.profileOptions
                    value: Config.s.profileOnBattery
                    onPicked: v => { Config.s.profileOnBattery = v; Config.applyPowerProfile(); }
                }
                Separator {}
                DropdownSetting {
                    label: "Plugged in"
                    settingKey: "profileOnAC"
                    detail: "Switched to when you plug in"
                    options: powerPane.profileOptions
                    value: Config.s.profileOnAC
                    onPicked: v => { Config.s.profileOnAC = v; Config.applyPowerProfile(); }
                }
            }
            GroupLabel { visible: powerPane.limitSupported; text: "Battery" }
            Group {
                visible: powerPane.limitSupported
                SettingRow {
                    label: "Charging limit"
                    detail: powerPane.limitOn ? "Charging stops at " + powerPane.limitAt + "%, which keeps your battery healthy for longer"
                        : "Your battery charges to full. Stopping at " + powerPane.limitAt + "% is kinder to it"
                    Toggle { checked: powerPane.limitOn; onToggled: v => powerPane.askLimit(v) }
                }
            }
            GroupLabel { text: "Restarting" }
            Group {
                ToggleSetting {
                    label: "Reopen apps after restarting"
                    detail: "Your apps open again on the same workspaces, right where you left them. Also on the restart dialog"
                    key: "reopenAppsAfterRestart"
                }
            }
        }
    }

    // ---- Shortcuts: Slate's keyboard shortcuts, as Hyprland has them (with descriptions) ----
    Component {
        id: shortcutsPage
        Column {
            id: shortcutsPane
            spacing: 4
            PageTitle { text: "Shortcuts" }
            property var binds: []
            Process {
                id: bindsProc
                running: true
                command: ["hyprctl", "binds", "-j"]
                stdout: StdioCollector { onStreamFinished: { try { shortcutsPane.binds = JSON.parse(text).filter(b => b.has_description && b.description && b.submap === ""); } catch (e) {} } }
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

            GroupLabel { text: "Shortcut set" }
            // Which set of shortcuts (binds.lua); changing it reloads Hyprland's config
            Group {
                DropdownSetting {
                    label: "Shortcut set"
                    settingKey: "keyset"
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
                Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
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
                model: shortcutsPane.groups
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
                                                color: win.divider
                                                border.width: 1; border.color: win.controlHoverSolid
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
            Footnote { text: "Add or change shortcuts in ~/.config/slate/hypr/binds.lua (with a description = \"Group: what it does\" to list them here)." }
        }
    }

    // ---- Default apps: what Slate's shortcuts open (and links and folders, for the browser
    // and file manager) ----------------------------------------------------------------
    Component {
        id: appsPage
        Column {
            id: defaultAppsPane
            spacing: 4
            PageTitle { text: "Default Apps" }
            readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
                .slice().sort((a, b) => a.name.localeCompare(b.name))
            // Apps of a kind (by their categories), or every app if none say so
            function optionsFor(cats) {
                const fit = all.filter(e => (e.categories || []).some(c => cats.includes(c)));
                return (fit.length > 0 ? fit : all).map(e => ({ value: e.id, label: e.name, detail: e.genericName || e.comment || "" }));
            }
            function nameOf(id) { const e = id ? DesktopEntries.byId(id) : null; return e ? e.name : ""; }
            GroupLabel { text: "Apps" }
            Group {
                SearchPicker {
                    label: "Terminal"
                    detail: "Super+Enter"
                    buttonLabel: defaultAppsPane.nameOf(Config.s.defaultTerminal) || "Choose…"
                    options: defaultAppsPane.optionsFor(["TerminalEmulator"])
                    onPicked: v => Config.s.defaultTerminal = v
                }
                Separator {}
                SearchPicker {
                    label: "Web browser"
                    detail: "Links open in it"
                    buttonLabel: defaultAppsPane.nameOf(Config.s.defaultBrowser) || "Choose…"
                    options: defaultAppsPane.optionsFor(["WebBrowser"])
                    onPicked: v => {
                        Config.s.defaultBrowser = v;
                        Quickshell.execDetached(["xdg-settings", "set", "default-web-browser", v + ".desktop"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Files"
                    detail: "Super+E, and folders open in it"
                    buttonLabel: defaultAppsPane.nameOf(Config.s.defaultFileManager) || "Choose…"
                    options: defaultAppsPane.optionsFor(["FileManager"])
                    onPicked: v => {
                        Config.s.defaultFileManager = v;
                        Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "inode/directory"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Text editor"
                    detail: "Super+T, and text files open in it"
                    buttonLabel: defaultAppsPane.nameOf(Config.s.defaultEditor) || "Choose…"
                    options: defaultAppsPane.optionsFor(["TextEditor"])
                    onPicked: v => {
                        Config.s.defaultEditor = v;
                        Quickshell.execDetached(["xdg-mime", "default", v + ".desktop", "text/plain"]);
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Calculator"
                    detail: "Super+C and the calculator key"
                    buttonLabel: defaultAppsPane.nameOf(Config.s.defaultCalculator) || "Choose…"
                    options: defaultAppsPane.optionsFor(["Calculator"])
                    onPicked: v => Config.s.defaultCalculator = v
                }
            }
            Footnote { text: "Ones not chosen here use those in ~/.config/slate/hypr/variables.lua (or Slate's own defaults)." }
        }
    }

    // ---- Startup apps: opened at each login (Config.atLogin) ---------------------------------
    Component {
        id: startupPage
        Column {
            id: startupPane
            spacing: 4
            PageTitle { text: "Startup Apps" }
            readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay)
                .slice().sort((a, b) => a.name.localeCompare(b.name))
            GroupLabel { text: "At login" }
            Group {
                SettingRow {
                    visible: (Config.s.startupApps || []).length === 0
                    label: "Nothing opens at login just yet"
                    detail: "Add your favourites below, and they'll be ready and waiting each time you log in"
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
                            // Asks first, in Slate's confirmation window (by its id, not its
                            // place: the list may have changed by the time it's answered)
                            onRemoved: {
                                const id = startRow.modelData, name = entry ? entry.name : id;
                                win.ask = {
                                    title: "Remove " + name + " from startup?",
                                    body: name + " won't open by itself when you log in any more. The app itself stays installed, "
                                        + "and you're welcome to add it back here at any time.",
                                    button: "Remove", destructive: true,
                                    run: () => Config.s.startupApps = (Config.s.startupApps || []).filter(a => a !== id)
                                };
                            }
                        }
                    }
                }
                Separator {}
                SearchPicker {
                    label: "Add an app"
                    detail: "It opens each time you log in"
                    buttonLabel: "Add…"
                    buttonIcon: 0xEB0B
                    options: startupPane.all.filter(e => !(Config.s.startupApps || []).includes(e.id))
                        .map(e => ({ value: e.id, label: e.name, detail: e.genericName || e.comment || "" }))
                    onPicked: v => Config.s.startupApps = (Config.s.startupApps || []).concat([v])
                }
            }
            Footnote { text: "Apps started in ~/.config/slate/hypr/autostart.lua still open too." }
        }
    }

    // ---- Date & Time (bin/slate-init timedate: timedatectl with systemd, the same D-Bus service
    // without it where something provides it; changing them may ask for your password) --------
    Component {
        id: timePage
        Column {
            id: dateTimePane
            spacing: 4
            PageTitle { text: "Date & Time" }
            property string zone: ""
            property bool ntp: false
            property bool canNtp: true
            property bool canSet: true            // something here can change the zone
            property var zones: []
            property date now: new Date()
            // The clock on this page; only ticks while Settings is showing (and catches up at once)
            Timer { interval: 1000; running: win.visible; repeat: true; triggeredOnStart: true; onTriggered: dateTimePane.now = Config.clockDate(new Date()) }
            function refresh() { stateProc.running = false; stateProc.running = true; }
            Timer { id: reread; interval: 1500; onTriggered: dateTimePane.refresh() }
            Process {
                id: stateProc
                running: true
                command: [Quickshell.shellPath("bin/slate-init"), "timedate", "show"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        for (const line of text.split("\n")) {
                            const i = line.indexOf("="), k = line.slice(0, i), v = line.slice(i + 1);
                            if (k === "Timezone") dateTimePane.zone = v;
                            else if (k === "NTP") dateTimePane.ntp = v === "yes";
                            else if (k === "CanNTP") dateTimePane.canNtp = v === "yes";
                            else if (k === "CanSet") dateTimePane.canSet = v === "yes";
                        }
                    }
                }
            }
            Process {
                running: true
                command: [Quickshell.shellPath("bin/slate-init"), "timedate", "zones"]
                stdout: StdioCollector { onStreamFinished: dateTimePane.zones = text.trim().split("\n").filter(z => z !== "").map(z => ({ value: z, label: z.replace(/_/g, " ") })) }
            }
            GroupLabel { text: "Clock" }
            Group {
                SettingRow {
                    label: Config.dateText(dateTimePane.now, "long")
                    detail: Qt.formatTime(dateTimePane.now, "HH:mm:ss")
                }
                Separator {}
                // Every zone in one dropdown, opening at the current one, with a search box to filter it
                DropdownSetting {
                    label: "Time zone"
                    // Without systemd, changing it needs a service that provides the same thing
                    // (openrc-settingsd does). Without one it's shown, greyed, with why
                    enabled: dateTimePane.canSet
                    opacity: enabled ? 1 : 0.5
                    detail: dateTimePane.canSet ? "Where you are, for the clock; type to search"
                        : "Slate can't change this here, as this computer has no time service to ask (openrc-settingsd provides one). Your clock follows the system's own setting"
                    searchable: true
                    options: dateTimePane.zones
                    value: dateTimePane.zone
                    onPicked: v => { if (v !== dateTimePane.zone) { Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "timedate", "set-zone", v]); reread.restart(); } }
                }
                Separator { visible: dateTimePane.canNtp }
                SettingRow {
                    visible: dateTimePane.canNtp
                    label: "Set the time automatically"
                    detail: "Keeps your clock right, using a time server on the internet"
                    Toggle {
                        checked: dateTimePane.ntp
                        onToggled: v => { dateTimePane.ntp = v; Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "timedate", "set-ntp", v ? "true" : "false"]); reread.restart(); }
                    }
                }
            }
            Footnote { text: "How the clock looks is under Menu bar. Changing these may ask for your password." }
            // How dates, the week and temperatures are written, everywhere Slate shows them
            GroupLabel { text: "Formats" }
            Group {
                DropdownSetting {
                    label: "Date format"
                    settingKey: "dateFormat"
                    detail: "On the menu bar's clock, the calendar, notifications and everywhere else Slate shows a date"
                    options: [{ value: "dmy", label: Qt.formatDate(dateTimePane.now, "ddd d MMM") },
                              { value: "mdy", label: Qt.formatDate(dateTimePane.now, "ddd, MMM d") },
                              { value: "ymd", label: Qt.formatDate(dateTimePane.now, "yyyy-MM-dd") }]
                    value: Config.s.dateFormat
                    onPicked: v => Config.s.dateFormat = v
                }
                Separator {}
                DropdownSetting {
                    label: "Week starts on"
                    settingKey: "weekStart"
                    detail: "The first day of the week in the clock's calendar"
                    options: [{ value: "monday", label: "Monday" }, { value: "sunday", label: "Sunday" }, { value: "saturday", label: "Saturday" }]
                    value: Config.s.weekStart
                    onPicked: v => Config.s.weekStart = v
                }
                Separator {}
                DropdownSetting {
                    label: "Temperature"
                    settingKey: "temperatureUnit"
                    detail: "For the weather in the clock's panel and the control centre"
                    options: [{ value: "celsius", label: "Celsius (°C)" }, { value: "fahrenheit", label: "Fahrenheit (°F)" }]
                    value: Config.s.temperatureUnit
                    onPicked: v => Config.s.temperatureUnit = v
                }
            }
        }
    }

    // ---- Screenshots (scripts/screenshot.sh reads these) ----------------------------------
    Component {
        id: shotsPage
        Column {
            id: screenshotsPane
            spacing: 4
            PageTitle { text: "Screenshots" }
            property bool hasSwash: false
            Process { running: true; command: ["sh", "-c", "command -v swash"]; onExited: code => screenshotsPane.hasSwash = code === 0 }
            readonly property string home: Quickshell.env("HOME")
            readonly property string folder: Config.s.screenshotFolder || (home + "/Pictures/Screenshots")
            readonly property date example: Config.clockDate(new Date())
            GroupLabel { text: "Saving" }
            Group {
                DropdownSetting {
                    label: "After taking one"
                    settingKey: "screenshotAfter"
                    detail: screenshotsPane.hasSwash ? "Every screenshot is saved to the folder below and copied. Marking one up and saving updates that file"
                        : "Every screenshot is saved to the folder below and copied (swash, for marking up, isn't installed)"
                    options: [{ value: "edit", label: "Open it to mark up" }, { value: "save", label: "Just show a notification" }]
                    value: Config.s.screenshotAfter
                    onPicked: v => Config.s.screenshotAfter = v
                }
                Separator {}
                DropdownSetting {
                    label: "Save to"
                    settingKey: "screenshotFolder"
                    detail: screenshotsPane.folder.replace(screenshotsPane.home, "~")
                    options: [{ value: "", label: "Pictures/Screenshots" }, { value: screenshotsPane.home + "/Pictures", label: "Pictures" },
                              { value: screenshotsPane.home + "/Desktop", label: "Desktop" }, { value: screenshotsPane.home + "/Downloads", label: "Downloads" }]
                    value: Config.s.screenshotFolder
                    onPicked: v => Config.s.screenshotFolder = v
                }
                Separator {}
                DropdownSetting {
                    label: "File names"
                    settingKey: "screenshotName"
                    options: [{ value: "default", label: "Screenshot " + Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd HH.mm.ss") },
                              { value: "compact", label: Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd_HH-mm-ss") },
                              { value: "gnome", label: "Screenshot from " + Qt.formatDateTime(screenshotsPane.example, "yyyy-MM-dd HH-mm-ss") }]
                    value: Config.s.screenshotName
                    onPicked: v => Config.s.screenshotName = v
                }
                Separator {}
                SettingRow {
                    label: "Screenshot folder"
                    Button {
                        icon: 0xFAF7; label: "Open"
                        onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && xdg-open \"$0\"", screenshotsPane.folder])
                    }
                }
            }
            Footnote { text: "Print Screen takes an area (drag it out), Super+Print Screen the whole screen." }
        }
    }

    // ---- Assistant (docs/ASSISTANT.md): AI agents using Slate's MCP server (slate mcp) -----
    Component {
        id: assistantPage
        Column {
            id: assistantPane
            spacing: 4
            PageTitle { text: "Assistant" }
            readonly property string server: Config.slateCommand.replace(Quickshell.env("HOME"), "~") + " mcp"
            // What the tools are, from the server's own table, so these lists can't go stale
            property var tools: []
            Process {
                running: true
                command: ["python3", Quickshell.shellPath("scripts/slate-mcp.py"), "--tools"]
                stdout: StdioCollector { onStreamFinished: { try { assistantPane.tools = JSON.parse(text); } catch (e) {} } }
            }
            function titles(tier) { return tools.filter(t => t.tier === tier).map(t => t.title).join(" · "); }
            function toolTitle(name) { const t = tools.find(x => x.name === name); return t ? t.title : name; }
            // What assistants did (the server's activity log), newest first
            readonly property string logPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/assistant/activity.jsonl"
            property bool showAll: false
            FileView { id: activityFile; path: assistantPane.logPath; watchChanges: true; printErrors: false; onFileChanged: reload() }
            readonly property var activity: {
                const out = [];
                const lines = (activityFile.text() || "").split("\n");
                for (let i = lines.length - 1; i >= 0 && out.length < 50; i--) {
                    if (!lines[i]) continue;
                    try { out.push(JSON.parse(lines[i])); } catch (e) {}
                }
                return out;
            }
            readonly property var outcomes: ({ done: "Done", declined: "You said no", "no answer": "No answer", refused: "Slate said no", failed: "Didn't work" })
            function when(iso) {
                const d = new Date(iso);
                return isNaN(d) ? "" : Config.dateText(d, "day") + ", " + Qt.formatTime(d, Config.s.barClockFormat === "24h" ? "HH:mm" : "h:mm ap");
            }
            // The agents there are (scripts/assistant.py detect), and the one a prompt would go to
            property var agents: []
            Process {
                running: true
                command: ["python3", Quickshell.shellPath("scripts/assistant.py"), "detect"]
                stdout: StdioCollector { onStreamFinished: { try { assistantPane.agents = JSON.parse(text); } catch (e) {} } }
            }
            // The one chosen ("" none, which is how it starts: Chalk asks for one to be chosen), and,
            // for an agent Slate knows, what's known about it
            readonly property string inUse: Config.s.assistantAgent
            readonly property var chosen: inUse === "" || inUse === "custom" ? null : (agents.find(a => a.id === inUse) || null)
            function signIn(cmd) {
                Quickshell.execDetached(["hyprctl", "dispatch",
                    `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. TERMINAL .. " -e ${String(cmd).replace(/[^\w.-]/g, "")}") end`]);
            }
            // What Slate adds to a prompt (scripts/assistant.py briefing), read when asked for
            property bool showAdds: false
            property string adds: ""
            Process {
                id: addsProc
                command: ["python3", Quickshell.shellPath("scripts/assistant.py"), "briefing"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const b = JSON.parse(text);
                            assistantPane.adds = b.briefing + "\n\n" + (b.context || "(Right now: a few lines on the time and the focused window, added while the assistant is switched on.)");
                        } catch (e) {}
                    }
                }
            }
            property string copied: ""
            Timer { id: copiedReset; interval: 1600; onTriggered: assistantPane.copied = "" }
            function copy(what, text) { Quickshell.execDetached(["wl-copy", text]); copied = what; copiedReset.restart(); }

            IntroText {
                text: "Ask an AI agent you already use, like Claude Code or Codex, to change a setting, move a window or tell you what's where. "
                    + "It works through Slate's own tools, and Slate asks you before anything that can't be undone. "
                    + "Chalk is Slate's own way to ask: press Super+K, type what you want, and your agent does it."
            }
            GroupLabel { text: "Assistant" }
            Group {
                SettingRow {
                    label: "Let assistants use Slate"
                    settingKey: "assistantEnabled"
                    detail: Config.assistantRisksChanged
                        ? "Something's changed about the assistant, so it's paused. Switch it on again to read what's new."
                        : "What Slate tells an assistant about your desktop (your settings, your open windows and their titles) is sent to the service behind the agent you use, "
                        + "under your own account with them. Slate itself sends nothing anywhere. Slate does its best to keep an assistant within these limits, "
                        + "but it can't promise what one will do, so using it is your choice and your responsibility."
                    Toggle { checked: Config.assistantOn; onToggled: v => win.assistantSwitch(v) }
                    below: [Button { visible: Config.assistantOn; label: "Read the risks again"; onClicked: win.assistantReadRisks() }]
                }
            }
            GroupLabel { text: "Agent" }
            Group {
                // Which agent answers Chalk: none to start with. What the chosen one needs shows beneath
                DropdownSetting {
                    label: "Agent"
                    settingKey: "assistantAgent"
                    detail: assistantPane.inUse === "" ? "Chalk needs an agent to ask. Choose the one you use, and what it needs shows here"
                        : assistantPane.inUse === "custom" ? "Slate runs your command as you typed it, with what you ask on its input. What it can see and do beyond Slate's tools is up to the command"
                        : assistantPane.chosen ? (assistantPane.chosen.confined ? "Recommended: " : "Keeps its own tools: ") + assistantPane.chosen.note
                        : "Slate couldn't find this one. It may have been removed"
                    value: assistantPane.inUse
                    options: [{ value: "", label: "None" }]
                        .concat(assistantPane.agents.filter(a => a.id !== "custom").map(a => ({ value: a.id, label: a.label })))
                        .concat([{ value: "custom", label: "A command of your own" }])
                    onPicked: v => {
                        const a = assistantPane.agents.find(x => x.id === v);
                        if (v === "") Config.s.assistantAgent = "";
                        else if (v === "custom") win.assistantChoose("custom", "your own command", false);
                        else if (a) win.assistantChoose(a.id, a.label, a.confined);
                    }
                }
                // An agent Slate knows: whether it's ready, and its model
                Separator { visible: !!assistantPane.chosen }
                SettingRow {
                    visible: !!assistantPane.chosen
                    readonly property var a: assistantPane.chosen
                    label: a ? a.label : ""
                    detail: !a ? "" : a.installed && a.signedIn ? "Ready" : a.installed ? "Not signed in. Open a terminal and run " + a.signIn + " once" : "Not installed yet"
                    Button {
                        visible: !!parent.a && !(parent.a.installed && parent.a.signedIn)
                        primary: true
                        label: parent.a && !parent.a.installed ? "Get it" : "Sign in"
                        onClicked: { if (!parent.a.installed) Qt.openUrlExternally(parent.a.url); else assistantPane.signIn(parent.a.signIn); }
                    }
                }
                Separator { visible: !!assistantPane.chosen }
                SettingRow {
                    visible: !!assistantPane.chosen
                    label: "Model"
                    settingKey: "assistantModel"
                    detail: "For agents that let you pick one. Empty: the agent's own choice"
                    FieldFrame {
                        field: modelInput
                        width: 160; height: 30
                        TextInput {
                            id: modelInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: win.text; selectionColor: win.accent
                            font.family: win.font; font.pixelSize: 12
                            text: Config.s.assistantModel
                            onEditingFinished: Config.s.assistantModel = text.trim().replace(/[^\w.:\-\[\]]/g, "")
                        }
                    }
                }
                // A command of your own: the command, and whether Slate adds anything to what you type
                Separator { visible: assistantPane.inUse === "custom" }
                SettingRow {
                    visible: assistantPane.inUse === "custom"
                    label: "Command"
                    settingKey: "assistantCommand"
                    detail: Config.s.assistantCommand === "" ? "Nothing to run yet. Type the command Chalk should hand what you ask to" : "Run as you typed it"
                    FieldFrame {
                        field: commandInput
                        width: 260; height: 30
                        TextInput {
                            id: commandInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: win.text; selectionColor: win.accent
                            font.family: win.font; font.pixelSize: 12
                            text: Config.s.assistantCommand
                            onEditingFinished: Config.s.assistantCommand = text.trim()
                        }
                    }
                }
                Separator { visible: assistantPane.inUse === "custom" }
                ToggleSetting {
                    visible: assistantPane.inUse === "custom"
                    label: "Just what you type"
                    key: "assistantCommandBare"
                    detail: "Your command gets your words alone, without what Slate adds: for a command that sets its own scene"
                }
            }
            GroupLabel { text: "What it can do" }
            Group {
                SettingRow {
                    label: "Without asking"
                    detail: "Looking: " + assistantPane.titles("look")
                }
                Separator {}
                SettingRow {
                    label: "Changes"
                    detail: "These can be undone: " + assistantPane.titles("change")
                }
                Separator {}
                ToggleSetting {
                    label: "Ask before changing anything"
                    key: "assistantAskChanges"
                    detail: "Slate asks you about every change, not only the ones that can't be undone"
                }
                Separator {}
                SettingRow {
                    label: "Always asks first"
                    detail: "These can't be undone, so Slate asks every time: " + assistantPane.titles("ask")
                }
            }
            GroupLabel { text: "What it can see" }
            Group {
                ToggleSetting {
                    label: "Window titles"
                    key: "assistantSeeTitles"
                    detail: "Titles carry document names and web page titles. Off: assistants get app names only"
                }
                Separator {}
                ToggleSetting {
                    label: "Notifications"
                    key: "assistantSeeNotifications"
                    detail: "Assistants can read your recent notifications"
                }
            }
            Footnote { text: "Slate's tools never show an assistant your screen, your files or your clipboard. An agent with tools of its own can do more than Slate's tools allow, and Slate can't limit those." }
            GroupLabel { text: "Chalk" }
            Group {
                ToggleSetting {
                    label: "Show on the menu bar"
                    key: "barShowAssistant"
                    detail: "Chalk's button, after Spaces, while the assistant is switched on"
                }
                Separator {}
                SettingRow {
                    label: "Ask Chalk"
                    detail: "Super+K, or your keyboard's Copilot or assistant key if it has one. You can change them in Shortcuts"
                    Button { label: "Shortcuts"; onClicked: win.goTo("shortcuts", "") }
                }
                Separator {}
                ToggleSetting {
                    label: "Keep chat history"
                    key: "assistantKeepChat"
                    detail: "What you asked Chalk and what it answered are still in its window after Slate restarts: the last 100 messages, kept on this computer only. Off: it's forgotten when Slate restarts, and what was kept is deleted"
                }
                Separator {}
                SettingRow {
                    label: "Clear chat history"
                    detail: "Empties Chalk's window, and what's kept of it. Nothing Chalk did is undone"
                    Button { label: "Clear"; destructive: true; onClicked: Config.slateCall("assistant", "clear") }
                }
            }
            GroupLabel { text: "Activity" }
            Group {
                SettingRow {
                    label: assistantPane.activity.length === 0 ? "Nothing here yet" : "What assistants did"
                    detail: assistantPane.activity.length === 0 ? "What assistants do with Slate's tools will show up here"
                        : "The latest " + assistantPane.activity.length + (assistantPane.activity.length === 1 ? " thing" : " things") + ", newest first. This list holds what was done, never what you typed"
                    Button {
                        visible: assistantPane.activity.length > 0
                        label: "Clear"; destructive: true
                        onClicked: Quickshell.execDetached(["sh", "-c", ': > "$0"', assistantPane.logPath])
                    }
                }
                Repeater {
                    model: assistantPane.showAll ? assistantPane.activity : assistantPane.activity.slice(0, 8)
                    Column {
                        id: activityRow
                        required property var modelData
                        width: parent ? parent.width : 0
                        Separator {}
                        SettingRow {
                            label: assistantPane.toolTitle(activityRow.modelData.tool)
                                + (activityRow.modelData.args && activityRow.modelData.args.key ? ": " + activityRow.modelData.args.key : "")
                            detail: [assistantPane.when(activityRow.modelData.time), activityRow.modelData.who,
                                     activityRow.modelData.before !== undefined ? "was " + activityRow.modelData.before : ""].filter(x => x).join(" · ")
                            Text {
                                text: assistantPane.outcomes[activityRow.modelData.outcome] || ""
                                textFormat: Text.PlainText
                                color: activityRow.modelData.outcome === "done" ? win.dim : win.text
                                font.family: win.font; font.pixelSize: 13
                            }
                        }
                    }
                }
                Separator { visible: assistantPane.activity.length > 8 }
                SettingRow {
                    visible: assistantPane.activity.length > 8
                    label: assistantPane.showAll ? "Showing all " + assistantPane.activity.length : "Showing the latest 8"
                    Button { label: assistantPane.showAll ? "Show fewer" : "Show more"; onClicked: assistantPane.showAll = !assistantPane.showAll }
                }
            }
            GroupLabel { text: "What Slate adds" }
            Group {
                SettingRow {
                    label: "See what Slate adds"
                    detail: "Alongside what you type, Slate tells the agent who it is here and a few lines about the moment. Nothing else is sent with your words"
                    Button {
                        label: assistantPane.showAdds ? "Hide" : "Show"
                        onClicked: { assistantPane.showAdds = !assistantPane.showAdds; if (assistantPane.showAdds) { addsProc.running = false; addsProc.running = true; } }
                    }
                }
                Text {
                    visible: assistantPane.showAdds
                    x: 16; width: parent.width - 32
                    bottomPadding: 12
                    text: assistantPane.adds
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: win.dim; font.family: win.font; font.pixelSize: 12
                }
            }
            GroupLabel { text: "Use Slate from other apps" }
            Group {
                SettingRow {
                    label: "Claude Code"
                    detail: "claude mcp add slate -- " + assistantPane.server
                    Button { label: assistantPane.copied === "claude" ? "Copied" : "Copy"; onClicked: assistantPane.copy("claude", "claude mcp add slate -- " + assistantPane.server) }
                }
                Separator {}
                SettingRow {
                    label: "Codex"
                    detail: "codex mcp add slate -- " + assistantPane.server
                    Button { label: assistantPane.copied === "codex" ? "Copied" : "Copy"; onClicked: assistantPane.copy("codex", "codex mcp add slate -- " + assistantPane.server) }
                }
                Separator {}
                SettingRow {
                    label: "Other agents"
                    detail: "Most take an “mcpServers” block in their settings, naming Slate's MCP server"
                    Button {
                        label: assistantPane.copied === "json" ? "Copied" : "Copy"
                        onClicked: assistantPane.copy("json", JSON.stringify({ mcpServers: { slate: { command: Config.slateCommand, args: ["mcp"] } } }, null, 2))
                    }
                }
            }
            Footnote { text: "Run the line for your agent in a terminal once. Slate's tools stay off for every agent until the switch at the top is on." }
        }
    }

    Component {
        id: windowsPage
        Column {
            spacing: 4
            PageTitle { text: "Windows" }
            GroupLabel { text: "Layout & borders" }
            Group {
                // Hyprland's layouts, and floating
                // The default: a workspace can have its own from the menu bar's workspace indicator
                DropdownSetting {
                    label: "Default window mode"
                    settingKey: "windowMode"
                    detail: ({
                        floating: "Windows open floating and centred, like a traditional desktop. Move them by their title bar or with Super+drag; Super+Alt+Space tiles one",
                        master: "One main window on the left, the rest stacked beside it. Super+J makes the focused window the main one; Super+Alt+Space floats one",
                        scrolling: "Windows sit in columns on a strip that scrolls sideways as you move between them. Super+J changes a column's width; Super+Alt+Space floats one",
                        monocle: "One window at a time, filling the screen; the others wait behind it. Super+J or Super+Alt+Left/Right switch between them",
                        solo: "Every window fills a workspace of its own: a new one opens on the next free workspace. Move between them as between workspaces"
                    })[Config.windowMode] ?? "Windows tile side by side. Super+J splits the other way, Super+drag moves one, Super+Alt+Space floats it"
                    // (and that it's only the default)
                    + ". For new workspaces: each can have its own, from the button beside the workspace dots on the menu bar"
                    options: Config.windowModes
                    value: Config.windowMode
                    // With windows open in another mode (the old default, or a workspace's own):
                    // shift every workspace to the new one, or leave those in use as they are?
                    // (asked in Slate's confirmation window; closing it leaves them)
                    onPicked: v => {
                        if (v === Config.windowMode) return;
                        const n = Config.workspacesNotIn(v).length;
                        if (n === 0) { Config.setDefaultMode(v, true); return; }
                        const to = Config.windowModes.find(m => m.value === v);
                        win.ask = {
                            title: "Tidy up open windows?",
                            body: "New workspaces will use " + to.label + ". " + (n === 1 ? "One workspace has" : n + " workspaces have")
                                + " windows open in another mode: tidy up, moving every workspace to " + to.label
                                + " now, or leave " + (n === 1 ? "it as it is" : "them as they are") + "? Left alone, "
                                + (n === 1 ? "it keeps its" : "each keeps its") + " current mode until you change it from the menu bar.",
                            button: "Tidy up", cancelLabel: "Leave " + (n === 1 ? "it" : "them"), code: to.icon,
                            run: () => Config.setDefaultMode(v, true),
                            cancel: () => Config.setDefaultMode(v, false)
                        };
                    }
                }
                // Floating windows' title bars: Slate's own (the default: nothing to build), or
                // Hyprbars, the optional plugin (Config.hyprbars…, HyprbarsWatch.qml). Always shown:
                // any workspace can be floating (the menu bar's workspace indicator), whatever the default
                Separator {}
                DropdownSetting {
                    label: "Title bars"
                    settingKey: "titleBarStyle"
                    detail: Config.slateTitleBars
                        ? "Slate Bars: Slate draws a title bar on the floating window in front, with nothing to install or rebuild. It fades out while a window moves, resizes or maximises. Drag it to move the window; double-click to maximise"
                        : "From the Hyprbars plugin, on every floating window and moving with it. It has to be rebuilt after every Hyprland update; until then Slate Bars are used"
                    options: [{ value: "slate", label: "Slate Bars" },
                              { value: "hyprbars", label: Config.hyprbarsState === "stale" ? "Hyprbars (needs rebuilding)" : "Hyprbars (optional)" }]
                    value: Config.slateTitleBars ? "slate" : "hyprbars"
                    // Hyprbars has risks, and may need building: Slate asks first, and switches once
                    // it's loaded. While it's being built or waiting for a reload, it can't be picked
                    onPicked: v => {
                        if (v === "slate") { Config.s.titleBarStyle = "slate"; return; }
                        if (Config.hyprbarsState === "building") return;
                        Config.hyprbarsChoose();
                    }
                }
                Separator {}
                SettingRow {
                    id: hyprbarsRow
                    readonly property string state: Config.hyprbarsState
                    readonly property string forNew: Config.hyprbars.installed || "the new Hyprland"
                    label: "Hyprbars"
                    detail: state === "building" ? "Being built for Hyprland " + (Config.hyprbars.stateFor || forNew) + "…"
                        : state === "loaded" ? (
                            !Config.hyprlandUpdated ? (Config.slateTitleBars ? "Built and loaded. Choose it above to use it" : "In use")
                            : Config.hyprbars.next === "yes" ? "Hyprland was updated: rebuilt for it, and ready after your next restart"
                            : Config.hyprbars.state === "failed" ? "Hyprland was updated, and Hyprbars couldn't be rebuilt for it: " + (Config.hyprbars.error || "the build failed")
                            : "Hyprland was updated. Rebuild now, and it's ready after your next restart")
                        : state === "ready" ? "Built. Reload Hyprland to load it; your windows stay open"
                        : state === "stale" ? "Needs rebuilding: it was built for another version of Hyprland, so it can't load. Slate Bars are used until it's rebuilt"
                        : state === "failed" ? "Couldn't be built: " + (Config.hyprbars.error || "the build failed")
                        : state === "removed" ? "Removed. Fully gone after your next restart"
                        : state === "system" ? "The one from your system's package doesn't match this Hyprland. Update that package, or build Slate's own"
                        : "Optional title bars from a Hyprland plugin, on every floating window. Slate builds it on this computer, and it needs rebuilding after every Hyprland update"
                    Row {
                        spacing: 8
                        Button {
                            visible: hyprbarsRow.state === "ready"
                            label: "Reload"; icon: 0xEB13
                            onClicked: Config.hyprbarsReload()
                        }
                        Button {
                            visible: hyprbarsRow.state === "stale" || hyprbarsRow.state === "failed" || hyprbarsRow.state === "system"
                                || (hyprbarsRow.state === "loaded" && Config.hyprlandUpdated && Config.hyprbars.next !== "yes")
                            label: hyprbarsRow.state === "failed" ? "Retry" : hyprbarsRow.state === "system" ? "Build" : "Rebuild"
                            onClicked: Config.hyprbarsRebuild()
                        }
                        Button {
                            visible: hyprbarsRow.state === "none" || hyprbarsRow.state === "removed"
                            label: "Build"
                            onClicked: Config.hyprbarsChoose()
                        }
                        Button {
                            visible: Config.hyprbars.any === "yes" && hyprbarsRow.state !== "building"
                            label: "Remove"
                            destructive: true
                            onClicked: Config.hyprbarsRemove()
                        }
                    }
                }
                // (always too: for whichever workspaces float)
                Separator {}
                DropdownSetting {
                    label: "Title bar buttons"
                    settingKey: "titleButtons"
                    detail: "Which side of a floating window's title bar the close and maximise buttons sit on"
                    options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }]
                    value: Config.s.titleButtons
                    onPicked: v => Config.s.titleButtons = v
                }
                // (hidden with Slate's title bars, which always use a click: Config.clickToFocus)
                Separator { visible: !Config.clickToFocus }
                SettingRow {
                    id: focusRow
                    visible: !Config.clickToFocus
                    label: "Focus follows the pointer"
                    settingKey: "focusFollowsMouse"
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
                    settingKey: "windowBorderSize"
                    detail: "Around each window when a workspace has more than one (a lone window has none). 0 turns them off"
                    ValueSlider { from: 0; to: 12; stepSize: 1; suffix: " px"; value: Config.s.windowBorderSize; onMoved: v => Config.s.windowBorderSize = v }
                }
                Separator {}
                SettingRow {
                    label: "Window spacing"
                    settingKey: "windowGap"
                    detail: "The gap between windows on a workspace with more than one (the screen edges get a little more). 0 puts them edge to edge"
                    ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.windowGap; onMoved: v => Config.s.windowGap = v }
                }
                Separator {}
                SettingRow {
                    label: "Space around a lone window"
                    settingKey: "soloWindowGap"
                    detail: "Padding around a window that's alone on its workspace, which then keeps its rounded corners. 0 lets it fill the screen up to the bar. Maximised and full-screen apps always fill it"
                    ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.soloWindowGap; onMoved: v => Config.s.soloWindowGap = v }
                }
                Separator {}
                SettingRow {
                    label: "Dim inactive windows"
                    settingKey: "inactiveDim"
                    detail: "Darken the windows you're not using, so the focused one stands out (Settings itself never dims). 0 turns it off"
                    ValueSlider { from: 0; to: 80; stepSize: 5; suffix: "%"; value: Config.s.inactiveDim; onMoved: v => Config.s.inactiveDim = v }
                }
            }
            GroupLabel { text: "Window switcher (Super+Tab)" }
            Group {
                // What each window's card shows (switcherPreviews and switcherAppIcons), as the
                // overview's Windows show
                DropdownSetting {
                    label: "Windows show"
                    detail: !Config.s.switcherPreviews ? "Each window's outline with its app icon; nothing is captured, which is lighter"
                        : Config.s.switcherAppIcons ? "Each window's contents, with a small app icon on the corner"
                        : "Each window's contents, live"
                    options: [{ value: "previews", label: "Live previews" }, { value: "icons", label: "App icons" }, { value: "both", label: "Both" }]
                    value: !Config.s.switcherPreviews ? "icons" : Config.s.switcherAppIcons ? "both" : "previews"
                    onPicked: v => {
                        Config.s.switcherPreviews = v !== "icons";
                        if (v !== "icons") Config.s.switcherAppIcons = v === "both";
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Moving between windows"
                    settingKey: "switcherMoveAnimation"
                    detail: ({
                        hop: "The windows hop along to the next one",
                        wheel: "The windows sit round the outside of a wheel that turns to bring the next one to the top",
                        tilt: "The chosen window faces you and the others are turned away in 3D on either side",
                        orbit: "The windows ride round a ring in 3D, the chosen one at the front and the rest smaller towards the back",
                        deck: "The windows sit in a pile with the chosen one on top; moving on deals it away and the next one rises",
                        fan: "The windows spread like a hand of cards, the chosen one lifted out of it",
                        instant: "The selection jumps straight to the next window"
                    })[Config.s.switcherMoveAnimation] ?? "The row of windows slides along, keeping the chosen one in the middle"
                    options: [{ value: "slide", label: "Slide" }, { value: "hop", label: "Hop" }, { value: "wheel", label: "Wheel" },
                              { value: "tilt", label: "Tilt" }, { value: "orbit", label: "Orbit" }, { value: "deck", label: "Deck" },
                              { value: "fan", label: "Fan" }, { value: "instant", label: "Instant" }]
                    value: ["hop", "wheel", "tilt", "orbit", "deck", "fan", "instant"].includes(Config.s.switcherMoveAnimation) ? Config.s.switcherMoveAnimation : "slide"
                    onPicked: v => Config.s.switcherMoveAnimation = v
                }
                Separator {}
                DropdownSetting {
                    label: "Going to the window"
                    settingKey: "switcherPickAnimation"
                    detail: ({
                        workspace: "A window on another workspace is switched to with your workspace animation (Workspaces → Workspace switching)",
                        instant: "Straight to the window, and the switcher goes at once"
                    })[Config.s.switcherPickAnimation] ?? "A window on another workspace fades in over the one you're on"
                    options: [{ value: "crossfade", label: "Crossfade" }, { value: "workspace", label: "Workspace animation" }, { value: "instant", label: "Instant" }]
                    value: Config.s.switcherPickAnimation
                    onPicked: v => Config.s.switcherPickAnimation = v
                }

            }
        }
    }

    Component {
        id: workspacesPage
        Column {
            spacing: 4
            PageTitle { text: "Workspaces" }
            GroupLabel { text: "Switching" }
            Group {
                DropdownSetting {
                    label: "Workspace switching"
                    settingKey: "workspaceAnimation"
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
                ToggleSetting {
                    label: "Name when switching"
                    detail: "The indicator that shows as you go to the next or previous workspace (Super+Left / Right) names the one you land on, under its dots"
                    key: "workspaceSwitchName"
                }
                Separator {}
                ToggleSetting {
                    label: "Workspaces wrap around"
                    detail: "Super+Left/Right and the overview go from the last workspace back to the first (and the other way); off, they stop at the ends, and the overview's row ends there too"
                    key: "wrapWorkspaces"
                }
                Separator {}
                ToggleSetting {
                    label: "Keep an empty workspace"
                    detail: "Keeps an empty workspace after the last one in use, ready and waiting for a new window"
                    key: "keepEmptyWorkspace"
                }
            }
            GroupLabel { text: "Look" }
            Group {
                SettingRow {
                    label: "Workspace indicators"
                    settingKey: "workspaceShape"
                    detail: "The shape of the workspace dots on the bar, the window switcher, the overview and the on-screen display"
                    // Two-way switch: Circles | Squares, each with a small preview
                    Rectangle {
                        readonly property var shapes: ["circle", "square"]
                        width: 184; height: 34; radius: 9
                        color: win.well
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.shapes.indexOf(Config.s.workspaceShape)) * 92
                            color: win.accent
                            Behavior on x { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
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
                                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
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
                                    ClickTap { onTapped: Config.s.workspaceShape = parent.modelData.shape }
                                }
                            }
                        }
                    }
                }
                Separator {}
                ToggleSetting {
                    label: "On the menu bar"
                    detail: "The workspace dots on the bar (also in Menu bar)"
                    key: "barShowWorkspaces"
                }
            }
            GroupLabel { text: "Workspace overview (Super+Down)" }
            Group {
                // What each window on the cards shows (overviewPreviews and overviewAppIcons): its
                // live picture, its outline with its app icon (nothing captured), or the picture
                // with the icon on it
                DropdownSetting {
                    label: "Windows show"
                    detail: !Config.s.overviewPreviews ? "Each window's outline with its app icon; nothing is captured, which is lighter"
                        : Config.s.overviewAppIcons ? "Each window's contents, with its app icon in the middle"
                        : "Each window's contents, live"
                    options: [{ value: "previews", label: "Live previews" }, { value: "icons", label: "App icons" }, { value: "both", label: "Both" }]
                    value: !Config.s.overviewPreviews ? "icons" : Config.s.overviewAppIcons ? "both" : "previews"
                    onPicked: v => {
                        Config.s.overviewPreviews = v !== "icons";
                        if (v !== "icons") Config.s.overviewAppIcons = v === "both";
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Moving between workspaces"
                    settingKey: "overviewMoveAnimation"
                    detail: ({
                        hop: "The cards hop along to the next one",
                        wheel: "The cards sit round the outside of a wheel that turns to bring the next one to the top",
                        tilt: "The chosen card faces you and the others are turned away in 3D on either side",
                        orbit: "The cards ride round a ring in 3D, the chosen one at the front and the rest smaller towards the back",
                        deck: "The cards sit in a pile with the chosen one on top; moving on deals it away and the next one rises",
                        fan: "The cards spread like a hand of cards, the chosen one lifted out of it",
                        grid: "Every workspace in a grid; the arrow keys move round it, and more rows than fit scroll",
                        instant: "The selection jumps straight to the next workspace"
                    })[Config.s.overviewMoveAnimation] ?? "The row of cards slides along, keeping the chosen one in the middle"
                    options: [{ value: "slide", label: "Slide" }, { value: "hop", label: "Hop" }, { value: "wheel", label: "Wheel" },
                              { value: "tilt", label: "Tilt" }, { value: "orbit", label: "Orbit" }, { value: "deck", label: "Deck" },
                              { value: "fan", label: "Fan" }, { value: "grid", label: "Grid" }, { value: "instant", label: "Instant" }]
                    value: ["hop", "wheel", "tilt", "orbit", "deck", "fan", "grid", "instant"].includes(Config.s.overviewMoveAnimation) ? Config.s.overviewMoveAnimation : "slide"
                    onPicked: v => Config.s.overviewMoveAnimation = v
                }
                Separator {}
                // Under the movement it goes with: the cards' size, or for the grid how many go across
                SettingRow {
                    visible: Config.s.overviewMoveAnimation !== "grid"
                    label: "Card size"
                    settingKey: "overviewCardWidth"
                    ValueSlider { from: 480; to: 1000; stepSize: 8; suffix: " px"; value: Config.s.overviewCardWidth; onMoved: v => Config.s.overviewCardWidth = v }
                }
                SettingRow {
                    visible: Config.s.overviewMoveAnimation === "grid"
                    label: "Grid size"
                    settingKey: "overviewGridSize"
                    defaultText: { const d = Config.defaultOf("overviewGridSize"); return d + " × " + d; }
                    detail: "How many workspaces go across, and down before it scrolls (fewer down on a small screen)"
                    ValueSlider {
                        from: 2; to: 9; stepSize: 1
                        value: Config.s.overviewGridSize
                        // (shown as 3 × 3 and so on)
                        suffix: " × " + Math.round(value)
                        onMoved: v => Config.s.overviewGridSize = Math.round(v)
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Going to the workspace"
                    settingKey: "overviewPickAnimation"
                    detail: ({
                        fade: "The overview fades away to show the workspace",
                        workspace: "The overview goes quickly and the workspace switches with your workspace animation (Workspace switching, above)",
                        instant: "Straight to the workspace, and the overview goes at once"
                    })[Config.s.overviewPickAnimation] ?? "The chosen card grows until it fills the screen and becomes the workspace"
                    options: [{ value: "zoom", label: "Zoom" }, { value: "fade", label: "Fade" }, { value: "workspace", label: "Workspace animation" }, { value: "instant", label: "Instant" }]
                    value: Config.s.overviewPickAnimation
                    onPicked: v => Config.s.overviewPickAnimation = v
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
            GroupLabel { text: "Do not disturb & sound" }
            Group {
                SettingRow {
                    label: "Do not disturb"
                    detail: "Quietens pop-ups so you can focus (critical ones still show). Nothing's lost: everything still goes to history"
                    Toggle { checked: win.notifs ? win.notifs.dnd : false; onToggled: v => { if (win.notifs) win.notifs.dnd = v; } }
                }
                Separator {}
                SoundSetting {
                    label: "Sound"
                    detail: "A soft chime when a notification pops up (also in Sound settings)"
                    which: "notification"; sample: "notification"
                }
            }
            GroupLabel { text: "Pop-ups" }
            Group {
                SettingRow {
                    label: "Position"
                    settingKey: "notificationPosition"
                    detail: "Where new notifications appear on screen"
                    // A small screen: click a spot to put notifications there
                    Rectangle {
                        width: 168; height: 104; radius: 10
                        color: win.well
                        border.width: 1; border.color: win.controlHoverSolid
                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 } height: 9; topLeftRadius: 9; topRightRadius: 9; color: win.outline }
                        Repeater {
                            model: ["top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right"]
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                readonly property bool current: Config.s.notificationPosition === modelData
                                width: 44; height: 22; radius: 6
                                x: [8, (168 - 44) / 2, 168 - 44 - 8][index % 3]
                                y: index < 3 ? 16 : 104 - 22 - 8
                                color: current ? win.accent : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                HoverFill { base: win.divider; hovered: spotHover.hovered; gone: parent.current; radius: parent.radius }
                                HoverHandler { id: spotHover }
                                ClickTap { onTapped: Config.s.notificationPosition = parent.modelData }
                            }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Stay on screen for"
                    settingKey: "notificationSeconds"
                    detail: "When the app doesn't choose its own time"
                    ValueSlider { from: 2; to: 15; stepSize: 1; suffix: " s"; value: Config.s.notificationSeconds; onMoved: v => Config.s.notificationSeconds = v }
                }
                Separator {}
                SettingRow {
                    label: "Most at once"
                    settingKey: "notificationMaxToasts"
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

    // A wallpaper in Settings → Appearance: its thumbnail and name; click to use it. For the
    // images in your folder and the ones that come with Slate
    component WallTile: Item {
        id: tile
        property real tileW: 200
        property bool small: false           // too small to be a wallpaper: hidden
        property string title: ""            // under it, in place of the file's name
        signal picked()
        required property string filePath
        required property string fileName
        readonly property bool current: Config.wallpaper === filePath
        visible: !tile.small
        width: tile.tileW
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
                    Behavior on opacity { NumberAnimation { duration: Config.ms(200) } }
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
            text: tile.title || fileName
            color: parent.current ? win.text : win.dim
            font.family: win.font; font.pixelSize: 11
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }
        HoverHandler { id: wallHover }
        ClickTap { onTapped: tile.picked() }
    }

    Component {
        id: appearancePage
        Column {
            id: appearancePane
            spacing: 4
            readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
            function setWallpaper(path) { Config.s.wallpaper = path; }
            // Choosing another wallpaper folder (a small folder browser under the Folder row)
            property bool choosingFolder: false
            property string browseDir: ""
            function chooseFolder() { browseDir = folder; choosingFolder = true; }

            PageTitle { text: "Appearance" }
            GroupLabel { text: "Preset" }
            // ---- Presets: theme, colour and glass in one go (asks first) --------------------
            Group {
                DropdownSetting {
                    label: "Preset"
                    detail: "A quick way to a finished look, if you'd rather not fine-tune every setting: sets the theme, colours, glass and folder colours below in one go. Your wallpaper and other settings stay as they are"
                    // Reads "Custom" while the settings don't match a preset; that's not something to
                    // pick, so it isn't in the list
                    readonly property var match: win.themePresets.find(p => win.presetActive(p)) ?? null
                    options: win.themePresets.map(p => ({ value: p.name, label: p.name }))
                    noneLabel: "Custom"
                    value: match ? match.name : ""
                    onPicked: v => {
                        const p = win.themePresets.find(x => x.name === v);
                        if (!p || win.presetActive(p)) return;
                        win.ask = {
                            title: "Apply " + p.name + "?",
                            body: "This gives you a fresh look: it changes the theme, colours, glass and folder colours. "
                                + "Your wallpaper stays as it is, and so does everything else.",
                            button: "Apply", code: 0xEB01,
                            run: () => win.applyPreset(p)
                        };
                    }
                }
            }
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
                        color: win.well
                        Rectangle {
                            width: 92 - 6; height: parent.height - 6; radius: 7
                            y: 3; x: 3 + Math.max(0, parent.modes.indexOf(Config.themeMode)) * 92
                            color: win.accent
                            Behavior on x { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
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
                                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                                    }
                                    HoverHandler { id: themeHover }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.glyph(parent.parent.modelData.icon); color: parent.parent.on ? win.accentText : win.dim; font.family: win.bar.iconFont; font.pixelSize: 14 }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; color: parent.parent.on ? win.accentText : win.dim; font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium }
                                    }
                                    ClickTap { onTapped: win.pickThemeMode(parent.modelData.mode) }
                                }
                            }
                        }
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Colour"
                    settingKey: "colourStyle"
                    detail: Config.colourful ? "More variety of colour: soft pastels, like each Settings page in its own colour"
                        : "The accent colour and greys throughout"
                    options: [{ value: "monotone", label: "Monotone" }, { value: "colourful", label: "Colourful" }]
                    value: Config.s.colourStyle || "colourful"
                    onPicked: v => Config.s.colourStyle = v
                }
                Separator {}
                SettingRow {
                    label: "Accent colour from wallpaper"
                    settingKey: "accentFromWallpaper"
                    detail: "Highlights (switches, sliders, selected items, the active workspace dot) use a bright colour picked from the wallpaper. Off: the colour chosen below"
                    Row {
                        spacing: 12
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: Config.wallpaperAccent ? Config.fromWallpaper(Config.wallpaperAccent) : "transparent"
                            border.width: 1; border.color: win.ring
                        }
                        Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.accentFromWallpaper; onToggled: v => Config.s.accentFromWallpaper = v }
                    }
                }
                Separator {}
                SettingRow {
                    // Only for the wallpaper's colour
                    readonly property bool applies: Config.s.accentFromWallpaper
                    opacity: applies ? 1 : 0.4
                    enabled: applies
                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                    label: "Accent boldness"
                    settingKey: "accentBoldness"
                    detail: "How vivid the wallpaper's colour is: from soft, as picked, to bold. Text on it stays readable"
                    ValueSlider {
                        per: 100
                        from: 0; to: 100; stepSize: 5; suffix: "%"
                        value: Math.round((Config.s.accentBoldness || 0) * 100)
                        onMoved: v => Config.s.accentBoldness = v / 100
                    }
                }
                Separator {}
                Column {
                    width: parent.width
                    opacity: Config.s.accentFromWallpaper ? 0.4 : 1
                    enabled: !Config.s.accentFromWallpaper
                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                    SettingRow {
                        label: "Accent colour"
                        settingKey: "accent"
                        detail: "Used for highlights across the bar, dock, launcher and panels"
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["#8fb3e8", "#7fc4c0", "#9ad3a6", "#e8c48f", "#e8a6b5", "#b9a6e8", "#eef1f5"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: 24; height: 24; radius: 12
                                    color: Config.accentShade(modelData)      // as it'll look (deeper in light mode)
                                    border.width: Config.s.accent.toLowerCase() === modelData ? 2 : 0
                                    border.color: win.text
                                    scale: swHover.hovered ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: Config.ms(100) } }
                                    HoverHandler { id: swHover }
                                    ClickTap { onTapped: Config.s.accent = parent.modelData }
                                }
                            }
                        }
                    }
                    Separator {}
                    SettingRow {
                        id: customRow
                        label: "Custom colour"
                        settingKey: "accent"
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
                                        GradientStop { position: 0/6; color: Config.accentShade(Qt.hsla(0/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 1/6; color: Config.accentShade(Qt.hsla(1/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 2/6; color: Config.accentShade(Qt.hsla(2/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 3/6; color: Config.accentShade(Qt.hsla(3/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 4/6; color: Config.accentShade(Qt.hsla(4/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 5/6; color: Config.accentShade(Qt.hsla(5/6, 0.65, 0.74, 1)) }
                                        GradientStop { position: 6/6; color: Config.accentShade(Qt.hsla(0.999, 0.65, 0.74, 1)) }
                                    }
                                }
                                Rectangle {
                                    width: 16; height: 16; radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, customRow.current.hslHue) * (parent.width - width)
                                    color: Config.accentShade(customRow.current)
                                    border.width: 2; border.color: win.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Config.handCursor ? Qt.PointingHandCursor : Qt.ArrowCursor      // (a hand over it, as over what's clicked)
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
                            FieldFrame {
                                field: hexInput
                                anchors.verticalCenter: parent.verticalCenter
                                width: 92; height: 30
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
                    settingKey: "toneFromWallpaper"
                    detail: "The bar, panels and window backgrounds keep their brightness but take on the wallpaper's overall hue. Off: neutral slate"
                    Row {
                        spacing: 12
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: Config.wallpaperTone ? Qt.hsla(Qt.lighter(Config.wallpaperTone, 1).hslHue, 0.3, 0.2, 1) : "transparent"
                            border.width: 1; border.color: win.ring
                        }
                        Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.toneFromWallpaper; onToggled: v => Config.s.toneFromWallpaper = v }
                    }
                }
                Separator {}
                SettingRow {
                    opacity: Config.s.toneFromWallpaper ? 1 : 0.4
                    enabled: Config.s.toneFromWallpaper
                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                    label: "Tint boldness"
                    settingKey: "toneBoldness"
                    detail: "How much of the wallpaper's colour the backgrounds take, in light and dark mode. 50% is the standard amount"
                    ValueSlider {
                        per: 100
                        from: 0; to: 100; stepSize: 5; suffix: "%"
                        value: Math.round((Config.s.toneBoldness ?? 0.5) * 100)
                        onMoved: v => Config.s.toneBoldness = v / 100
                    }
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
                        settingKey: "folderColour"
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
            GroupLabel { text: "Glass" }
            Group {
                ToggleSetting {
                    label: "Glass"
                    detail: "The bar, dock, panels, menus, the launcher and Settings turn see-through, with what's behind them blurred"
                    key: "glass"
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Opacity"
                    settingKey: "glassOpacity"
                    detail: "How much of their colour the surfaces keep: lower is clearer glass"
                    ValueSlider { per: 100; from: 30; to: 95; stepSize: 5; suffix: "%"; value: Math.round(Config.s.glassOpacity * 100); onMoved: v => Config.s.glassOpacity = v / 100 }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Blur"
                    settingKey: "glassBlur"
                    detail: Config.s.glassBlur > 0 ? "How strongly what's behind is blurred (Hyprland's blur, so see-through windows use it too)"
                        : "Hyprland's own blur (size " + Config.hyprBlur.size + "); drag to make it stronger or softer"
                    ValueSlider { from: 0; to: 20; stepSize: 1; value: Config.s.glassBlur; onMoved: v => Config.s.glassBlur = v }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Gloss"
                    settingKey: "glassGloss"
                    detail: "A glossy sheen on the bar's containers, hover highlights and tooltips. 0% for none"
                    // (the setting runs 0 to 2; the slider shows that as 0–100%, so 50% is the sheen as
                    // Slate first had it at full, and 100% twice that)
                    ValueSlider { per: 50; from: 0; to: 100; stepSize: 5; suffix: "%"; value: Math.round(Config.glossAmount * 50); onMoved: v => Config.s.glassGloss = v / 50 }
                }
                Separator { visible: Config.s.glass }
                SettingRow {
                    visible: Config.s.glass
                    label: "Gloss colour"
                    settingKey: "glassGlossTint"
                    detail: "How much colour the sheen takes from what it's on: the wallpaper's colour on glass, a selection's own. 0% for plain white"
                    ValueSlider { per: 100; from: 0; to: 100; stepSize: 5; suffix: "%"; value: Math.round(Config.glossTint * 100); onMoved: v => Config.s.glassGlossTint = v / 100 }
                }
            }
            GroupLabel { text: "Blur" }
            Group {
                SettingRow {
                    label: "Fast blur"
                    settingKey: "fastBlur"
                    detail: Config.s.fastBlur ? "See-through windows and glass blur just the wallpaper, not the windows under them: far less work, so everything stays smooth"
                        : "See-through windows and glass blur whatever's under them, windows included. Heavier: animations and the pointer can slow down"
                    Toggle { checked: Config.s.fastBlur; onToggled: v => Config.s.fastBlur = v }
                }
                Separator {}
                DropdownSetting {
                    label: "Blur quality"
                    settingKey: "blurPasses"
                    detail: "Smoother blur takes more passes, and asks a little more of your computer"
                    options: [{ value: 0, label: "Hyprland's own" }, { value: 1, label: "Low (1 pass)" }, { value: 2, label: "Medium (2 passes)" },
                              { value: 3, label: "High (3 passes)" }, { value: 4, label: "Highest (4 passes)" }]
                    value: Config.s.blurPasses
                    onPicked: v => Config.s.blurPasses = v
                }
            }
            GroupLabel { text: "Style" }
            Group {
                ToggleSetting {
                    label: "Rounded screen corners"
                    detail: "Round off the corners of the screen and curve the bar into the screen edges"
                    key: "roundedScreenCorners"
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
                    onExited: { iconGroup.previewVersion++; previewColourFile.reload(); }
                }
                // The previewed icon's main colour, so its tile shows Tiles in the icon's colour too
                FileView { id: previewColourFile; path: iconGroup.previewDir + "/colour.txt"; printErrors: false }
                readonly property var previewShade: Config.iconTileShadeOf(previewColourFile.text().trim())
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
                            color: on ? win.accent : shapeHover.hovered ? Config.hover : win.well
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            // Shown as every App icons setting has it: the shape, Fill the shape, Tiles
                            // in the icon's colour, and Tint app icons (and its strength); with glass,
                            // see-through tiles and the sheen, as in the dock
                            Image {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                                width: 48; height: 48
                                sourceSize: Qt.size(96, 96)
                                cache: false
                                source: iconGroup.previewVersion > 0
                                    ? "file://" + iconGroup.previewDir + "/" + shapeCard.modelData.value + (Config.s.iconFill ? "-fill" : "-whole") + ".png?v=" + iconGroup.previewVersion
                                    : ""
                                layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                                IconPlate {
                                    anchors.fill: parent; z: -1; shape: shapeCard.modelData.value
                                    color: iconGroup.previewShade ?? Config.iconPlateColor
                                    shaded: iconGroup.previewShade !== null
                                }
                                // Glass: the sheen the dock puts on its icons, rounded to this shape
                                Gloss {
                                    glassHint: true
                                    visible: Config.glassGloss && shapeCard.modelData.value !== "original"
                                    radius: { const v = shapeCard.modelData.value, w = parent.width;
                                              return v === "circle" ? w / 2 : v === "square" ? 0 : v === "squircle" ? w * 0.3 : w * 0.225; }
                                }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                                text: shapeCard.modelData.label
                                color: shapeCard.on ? win.accentText : win.dim
                                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                font.family: win.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            HoverHandler { id: shapeHover }
                            ClickTap { onTapped: Config.s.iconShape = shapeCard.modelData.value }
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Fill the shape"
                    settingKey: "iconFill"
                    detail: Config.s.iconShape === "original"
                        ? "Trim icons' empty margins and theme shadows so they're all the same size. Off: exactly as the apps ship them"
                        : "Crop each icon's own border and shadow and grow it to fill the shape, on its main colour. Off: the whole icon, smaller, on a plain tile"
                    Toggle { checked: Config.s.iconFill; onToggled: v => Config.s.iconFill = v }
                }
                Separator {}
                SettingRow {
                    // Only for icons on a tile: filled icons and original ones have none
                    readonly property bool applies: !Config.s.iconFill && Config.s.iconShape !== "original"
                    opacity: applies ? 1 : 0.4
                    enabled: applies
                    Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                    label: "Tiles in the icon's colour"
                    settingKey: "iconTileColour"
                    detail: applies ? "The tile behind each icon takes a deep shade of the icon's own main colour, rather than the theme's. Grey icons keep the theme's tile"
                        : "For icons on a tile: turn off Fill the shape (and pick a shape other than Original) to use it"
                    Toggle { checked: Config.s.iconTileColour; onToggled: v => Config.s.iconTileColour = v }
                }
                Separator {}
                ToggleSetting {
                    label: "Tint app icons"
                    detail: "Colour app icons in the dock, launcher, switcher, bar and notifications with the accent colour"
                    key: "tintIcons"
                }
                Separator { visible: Config.s.tintIcons }
                SettingRow {
                    visible: Config.s.tintIcons
                    label: "Tint strength"
                    settingKey: "iconTintStrength"
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
                    defaultFont: "Geist Mono"
                    monoOnly: true
                }
            }
            GroupLabel { text: "Size" }
            Group {
                SettingRow {
                    label: "Interface size"
                    settingKey: "uiScale"
                    detail: "Scales Slate only (the bar, dock, panels, launcher, title bars and this window), on every display, on top of each display's Scale. "
                        + "Apps stay as they are: to make everything larger or smaller, apps included, change Scale in Displays instead. Changing it restarts Slate"
                    ValueSlider {
                        per: 100
                        from: 75; to: 150; stepSize: 5; suffix: "%"
                        value: Math.round(Config.s.uiScale * 100)
                        onMoved: v => Config.s.uiScale = v / 100
                        onReleased: scaleAsk.restart()
                    }
                    // Once you let go, ask before restarting; Cancel goes back to the size in use
                    Timer {
                        id: scaleAsk
                        interval: 150
                        onTriggered: {
                            if (Math.abs(Config.s.uiScale - Config.uiScale) < 0.001) return;
                            win.ask = {
                                title: "Restart Slate?",
                                body: "Interface size changes to " + Math.round(Config.s.uiScale * 100) + "% when Slate restarts. "
                                    + "Your apps and windows stay open. The bar, dock and Settings step away for a moment, "
                                    + "then Settings opens again right here.",
                                button: "Restart",
                                run: () => Config.uiScaleEdited(),
                                cancel: () => Config.s.uiScale = Config.uiScale
                            };
                        }
                    }
                }
            }
            GroupLabel { text: "Motion" }
            Group {
                DropdownSetting {
                    label: "Animations"
                    settingKey: "animations"
                    detail: "Windows opening, closing and moving, switching workspaces, and Slate's own: panels opening, the bar's groups sliding open, fades and highlights. Faster halves them; Off makes them instant"
                    options: [{ value: "normal", label: "Normal" }, { value: "fast", label: "Faster" }, { value: "off", label: "Off" }]
                    value: Config.s.animations !== "" ? Config.s.animations : "normal"
                    onPicked: v => Config.s.animations = v
                }
            }
            GroupLabel { text: "Other apps" }
            Group {
                SettingRow {
                    label: "App Theming"
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
                    detail: appearancePane.folder.replace(Quickshell.env("HOME"), "~")
                    Row {
                        spacing: 8
                        Button { icon: 0xFAF7; label: "Open"; onClicked: Quickshell.execDetached(["xdg-open", appearancePane.folder]) }
                        Button { icon: 0xEAAD; label: "Change…"; onClicked: appearancePane.choosingFolder ? appearancePane.choosingFolder = false : appearancePane.chooseFolder() }
                        Button { icon: 0xF000; label: "Random"; primary: true; onClicked: { const all = appearancePane.shown.concat(appearancePane.slateShown); if (all.length > 0) appearancePane.setWallpaper(all[Math.floor(Math.random() * all.length)]); } }
                    }
                }
                // Folder browser: go into a folder, then use it
                Column {
                    visible: appearancePane.choosingFolder
                    width: parent.width - 32; x: 16
                    spacing: 8
                    bottomPadding: 14
                    Row {
                        width: parent.width
                        spacing: 6
                        Button {
                            id: upBtn
                            icon: 0xEA25; label: "Up"
                            opacity: appearancePane.browseDir === "/" ? 0.45 : 1
                            onClicked: if (appearancePane.browseDir !== "/") appearancePane.browseDir = appearancePane.browseDir.replace(/\/[^\/]*$/, "") || "/"
                        }
                        Button { id: homeBtn; icon: 0xEAC1; label: "Home"; onClicked: appearancePane.browseDir = Quickshell.env("HOME") }
                        Text {
                            width: parent.width - upBtn.width - homeBtn.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: appearancePane.browseDir.replace(Quickshell.env("HOME"), "~")
                            color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 220
                        radius: 8
                        color: win.well
                        ListView {
                            id: dirList
                            anchors { fill: parent; margins: 4 }
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            SmoothWheel { flick: dirList }
                            model: FolderListModel {
                                id: dirModel
                                folder: appearancePane.choosingFolder ? "file://" + appearancePane.browseDir : ""
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
                                ClickTap { onTapped: appearancePane.browseDir = parent.filePath }
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
                        Button { label: "Cancel"; onClicked: appearancePane.choosingFolder = false }
                        Button {
                            label: "Use this folder"; primary: true
                            onClicked: {
                                const home = Quickshell.env("HOME") + "/Pictures";
                                Config.s.wallpaperFolder = appearancePane.browseDir === home ? "" : appearancePane.browseDir;
                                appearancePane.choosingFolder = false;
                            }
                        }
                    }
                }
                Separator {}
                DropdownSetting {
                    label: "Change wallpaper"
                    settingKey: "wallpaperChange"
                    detail: (Config.s.wallpaperChange === "off"
                            ? "Keep the one you pick"
                            : "Switch to another image from this folder" + (Config.s.wallpaperShowSlate ? " or Slate's own" : "") + ", in a shuffled order")
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
                ToggleSetting {
                    label: "Slate's wallpapers"
                    detail: "Show the wallpapers that come with Slate below your own, and include them in Random and when the wallpaper changes by itself"
                    key: "wallpaperShowSlate"
                }
                Separator {}
                ToggleSetting {
                    label: "Hide small images"
                    detail: "Leave out pictures too small to be wallpapers, like icons, avatars and small screenshots"
                    key: "wallpaperHideSmall"
                }
                Separator { visible: Config.s.wallpaperHideSmall }
                DropdownSetting {
                    visible: Config.s.wallpaperHideSmall
                    label: "Smallest size"
                    settingKey: "wallpaperMinSize"
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
                command: [Quickshell.shellPath("scripts/image-sizes.py"), appearancePane.folder]
                stdout: StdioCollector { onStreamFinished: { try { appearancePane.sizes = JSON.parse(text); } catch (e) {} } }
            }
            // Read the sizes when the page opens and when the folder's contents change. Both happen
            // together as the page opens (the folder's listing arrives just after), so they're
            // gathered into one read rather than starting the script and stopping it straight away.
            Timer { id: sizesSoon; interval: 250; onTriggered: { sizeReader.running = false; sizeReader.running = true; } }
            Connections { target: wallFiles; function onCountChanged() { sizesSoon.restart(); } }
            Component.onCompleted: {
                sizesSoon.restart();
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
                text: appearancePane.shown.length + (appearancePane.shown.length === 1 ? " image" : " images")
                    + (appearancePane.hidden > 0 ? " · " + appearancePane.hidden + " small " + (appearancePane.hidden === 1 ? "one" : "ones") + " hidden" : "")
            }
            FolderListModel {
                id: wallFiles
                folder: "file://" + appearancePane.folder
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG"]
                showDirs: false
                sortField: FolderListModel.Name
            }
            Text {
                visible: wallFiles.count === 0
                text: "No pictures in this folder yet. Pop some in, or choose another folder above"
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
                    delegate: WallTile {
                        tileW: wallGrid.tileW
                        small: appearancePane.tooSmall(fileName)
                        onPicked: appearancePane.setWallpaper(filePath)
                    }
                }
            }
            // The wallpapers that come with Slate (shell/wallpapers, made by tools/make-wallpapers.py),
            // below your own: Settings → Appearance → Slate's wallpapers switches them off
            FolderListModel {
                id: slateFiles
                folder: Config.s.wallpaperShowSlate ? "file://" + Quickshell.shellPath("wallpapers") : ""
                nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
                showDirs: false
                sortField: FolderListModel.Name
            }
            readonly property var slateShown: {
                const out = [];
                if (Config.s.wallpaperShowSlate) for (let i = 0; i < slateFiles.count; i++) out.push(slateFiles.get(i, "filePath"));
                return out;
            }
            GroupLabel { visible: appearancePane.slateShown.length > 0; text: "From Slate" }
            Grid {
                id: slateGrid
                visible: appearancePane.slateShown.length > 0
                width: parent.width
                columns: 3
                spacing: 12
                readonly property real tileW: (width - spacing * (columns - 1)) / columns
                Repeater {
                    model: Config.s.wallpaperShowSlate ? slateFiles : null
                    delegate: WallTile {
                        tileW: slateGrid.tileW
                        // "slate-ember.png" → "Ember"; "slate-ember-plain.png" (without Slate's
                        // mark) → "Ember (plain)"
                        title: fileName.replace(/^slate-/, "").replace(/\.[^.]*$/, "").replace(/-plain$/, " (plain)").replace(/^./, c => c.toUpperCase())
                        onPicked: appearancePane.setWallpaper(filePath)
                    }
                }
            }
        }
    }

    Component {
        id: appThemingPage
        Column {
            spacing: 4
            PageTitle { text: "App Theming" }
            IntroText { text: "Apps you switch on follow Slate's colours, light or dark, and the accent (even one picked from the wallpaper). Slate backs up a config before changing it, and switching an app off puts it back." }
            GroupLabel { text: "Refresh" }
            Group {
                SettingRow {
                    id: themeRefresh
                    label: "Refresh themes"
                    detail: "Puts the themes of the apps you've switched on back in place, if an app update or reset has overwritten one"
                    property bool asked: false       // Refresh was clicked (shows Done when it finishes)
                    property bool done: false
                    Connections {
                        target: Config
                        function onThemesBusyChanged() {
                            if (!Config.themesBusy && themeRefresh.asked) { themeRefresh.asked = false; themeRefresh.done = true; doneTimer.restart(); }
                        }
                    }
                    Timer { id: doneTimer; interval: 2500; onTriggered: themeRefresh.done = false }
                    Button {
                        icon: themeRefresh.done ? 0xEA5E : 0xEB13
                        label: Config.themesBusy && themeRefresh.asked ? "Refreshing…" : themeRefresh.done ? "Done" : "Refresh"
                        onClicked: { if (Config.themesBusy) return; themeRefresh.done = false; themeRefresh.asked = true; Config.refreshThemes(); }
                    }
                }
            }
            GroupLabel { text: "Apps" }
            Group {
                id: appTheming
                // What scripts/apply-theme.py can theme, and which are installed: [{id, label, detail,
                // installed, about, url, packages}] (scripts/slate_apps.py)
                property var apps: []
                Process {
                    id: appsQuery
                    running: true
                    command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--apps"]
                    stdout: StdioCollector { onStreamFinished: { try { appTheming.apps = JSON.parse(text); } catch (e) {} } }
                }
                // Installing one (its Install button, after asking): from the distro's own repositories,
                // with your password (bin/slate-system --install); a notification says how it went
                property string installing: ""          // the app's id, while it installs
                function install(app) {
                    const go = () => {
                        appTheming.installing = app.id;
                        installer.app = app;
                        installer.command = [Quickshell.shellPath("bin/slate-system"), "--install"].concat(app.packages.split(" "));
                        installer.running = true;
                    };
                    const q = {
                        title: "Install " + app.label + "?",
                        body: app.about + ". Slate installs " + app.packages.split(" ").join(", ")
                            + " from your distribution's software, which asks for your password. Once it's in, you can switch on its theme right here.",
                        button: "Install"
                    };
                    // (in Slate's confirmation window, like shutting down or emptying the waste basket)
                    win.ask = Object.assign({ run: go, code: 0xEA96 }, q);
                }
                Process {
                    id: installer
                    property var app: null
                    stderr: StdioCollector { id: installErr }
                    onExited: code => {
                        const a = installer.app;
                        appTheming.installing = "";
                        appsQuery.running = false; appsQuery.running = true;         // installed now?
                        if (!a) return;
                        // 126/127: the password prompt was closed or failed, so it didn't start
                        if (code === 126 || code === 127) return;
                        const icon = Quickshell.shellPath("assets/icon/icon-64.png");
                        const err = (installErr.text || "").trim().split("\n").filter(l => l.trim() !== "").pop() || "";
                        Quickshell.execDetached(["notify-send", "--app-name=Slate", "--icon=" + icon, "--hint=string:x-slate-page:apptheming",
                            code === 0 ? a.label + " is installed" : "Slate couldn't install " + a.label,
                            code === 0 ? "Switch on its theme in Settings → App Theming." : (err || "The package manager stopped with an error.")]);
                    }
                }
                function isOn(id) { return (Config.s.themedApps || []).indexOf(id) >= 0; }
                function setOn(id, on) {
                    const list = (Config.s.themedApps || []).filter(x => x !== id);
                    if (on) list.push(id);
                    Config.s.themedApps = list;
                }
                Repeater {
                    model: appTheming.apps
                    delegate: Column {
                        id: appRow
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 0
                        Separator { visible: appRow.index > 0 }
                        SettingRow {
                            id: appSetting
                            readonly property var app: appRow.modelData
                            readonly property bool usable: app.installed || appTheming.isOn(app.id)
                            // Its app, to open (the first of its desktop entries that's installed)
                            readonly property var entry: {
                                DesktopEntries.applications.values;         // (again as apps come and go)
                                for (const id of (app.desktop || [])) { const e = DesktopEntries.byId(id); if (e) return e; }
                                return null;
                            }
                            label: app.label
                            // What it is, then what Slate does to it
                            detail: (app.about ? app.about + ". " : "") + app.detail
                            // Under the description: its website, and Install when it isn't installed
                            below: [
                                Button {
                                    visible: !!appSetting.app.url
                                    icon: 0xEA99; label: "Website"
                                    onClicked: Qt.openUrlExternally(appSetting.app.url)
                                },
                                // Installed: open it (as the launcher does)
                                Button {
                                    visible: appSetting.app.installed && !!appSetting.entry
                                    primary: true
                                    icon: 0xEFE6          // app window
                                    label: "Open"
                                    onClicked: if (appSetting.entry) appSetting.entry.execute()
                                },
                                // Not installed: install it from the distro's software, where it's there
                                Button {
                                    readonly property var app: appSetting.app
                                    visible: !app.installed && !appTheming.isOn(app.id) && app.packages !== ""
                                    primary: true
                                    icon: 0xEA96
                                    label: appTheming.installing === app.id ? "Installing…" : "Install"
                                    opacity: appTheming.installing !== "" && appTheming.installing !== app.id ? 0.5 : 1
                                    onClicked: if (appTheming.installing === "") appTheming.install(app)
                                }
                            ]
                            // The switch, kept where it sat above the chip (the chip's room left under it)
                            Column {
                                spacing: 8
                                Toggle {
                                    visible: appSetting.usable
                                    checked: appTheming.isOn(appSetting.app.id)
                                    onToggled: v => appTheming.setOn(appSetting.app.id, v)
                                }
                                Item { visible: appSetting.usable; width: 1; height: 24 }
                            }
                            // On the right, level with the buttons: whether it's installed
                            belowRight: [
                                Rectangle {
                                    readonly property bool on: appSetting.app.installed
                                    // Installed: Slate's pastel green when colourful (as Power's), else the accent
                                    readonly property color tone: Config.colourful ? Config.tint("#a6d3a0") : win.accent
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    width: chipRow.implicitWidth + 18; height: 24; radius: 12
                                    color: on ? Qt.rgba(tone.r, tone.g, tone.b, 0.16) : win.control
                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        Text {
                                            visible: parent.parent.on
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: win.glyph(0xEA5E)          // tick
                                            color: parent.parent.tone; font.family: win.bar.iconFont; font.pixelSize: 13
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: parent.parent.on ? "Installed" : "Not installed"
                                            color: parent.parent.on ? parent.parent.tone : win.dim
                                            font.family: win.font; font.pixelSize: 11; font.weight: Font.Medium
                                        }
                                    }
                                }
                            ]
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wifiPage
        Column {
            id: wifiPane
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
            Binding { target: wifiPane.dev; property: "scannerEnabled"; value: true; when: wifiPane.dev !== null && win.visible }

            PageTitle { text: "Wi-Fi" }
            GroupLabel { text: "Status" }
            Group {
                SettingRow {
                    label: "Wi-Fi"
                    detail: !wifiPane.dev ? "No Wi-Fi adapter found"
                        : !Networking.wifiEnabled ? "Off"
                        : wifiPane.current ? "Connected to " + wifiPane.current.name : "Not connected"
                    Toggle { visible: !!wifiPane.dev; checked: Networking.wifiEnabled; onToggled: v => Networking.wifiEnabled = v }
                }
            }
            GroupLabel { visible: Networking.wifiEnabled && !!wifiPane.dev; text: wifiPane.nets.length ? "Networks" : "Searching for networks…" }
            Group {
                visible: Networking.wifiEnabled && wifiPane.nets.length > 0
                Repeater {
                    model: wifiPane.nets
                    delegate: Column {
                        id: netRow
                        required property var modelData
                        required property int index
                        readonly property var n: modelData
                        readonly property bool secure: n.security !== undefined && n.security !== WifiSecurityType.Open
                        width: parent.width
                        Separator { visible: netRow.index > 0 }
                        Item {
                            width: parent.width; height: 60
                            Rectangle {
                                id: netIcon
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                width: 34; height: 34; radius: 9
                                color: netRow.n.connected ? win.accent : win.outline
                                Text {
                                    anchors.centerIn: parent
                                    readonly property real s: netRow.n.signalStrength
                                    text: win.glyph(s > 0.66 ? 0xEB52 : s > 0.33 ? 0xEBA5 : 0xEBA4)
                                    color: netRow.n.connected ? win.accentText : win.text
                                    font.family: win.bar.iconFont; font.pixelSize: 17
                                }
                            }
                            Column {
                                id: netLabels
                                anchors { left: netIcon.right; leftMargin: 12; right: netButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Row {
                                    spacing: 6
                                    // A long name stops short of the buttons (… at the end), leaving
                                    // room for the lock beside it
                                    Text {
                                        width: Math.min(implicitWidth, netLabels.width - (netLock.visible ? netLock.width + 6 : 0))
                                        elide: Text.ElideRight
                                        text: netRow.n.name; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium
                                    }
                                    Text { id: netLock; visible: netRow.secure; anchors.verticalCenter: parent.verticalCenter; text: win.glyph(0xEAE2); color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 12 }
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
                                        else if (n.known || !netRow.secure) { n.connect(); wifiPane.askingFor = ""; }
                                        else wifiPane.askingFor = (wifiPane.askingFor === n.name ? "" : n.name);
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
                            visible: wifiPane.askingFor === netRow.n.name
                            width: parent.width; height: 48
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; leftMargin: 60; rightMargin: 14; top: parent.top }
                                height: 36; radius: 8
                                color: win.control
                                border.width: 1; border.color: win.accent
                                TextInput {
                                    id: psk
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    echoMode: TextInput.Password
                                    color: win.text
                                    font.family: win.font; font.pixelSize: 13
                                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                    onAccepted: { netRow.n.connectWithPsk(text); wifiPane.askingFor = ""; }
                                    Keys.onEscapePressed: wifiPane.askingFor = ""
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
            readonly property var minutes: win.minuteOptions([0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60])
            PageTitle { text: "Lock & Idle" }
            GroupLabel { text: "Locking" }
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
                ToggleSetting {
                    label: "Power menu on the lock screen"
                    detail: "Lets anyone at the keyboard suspend, restart, shut down or log you out without your password"
                    key: "lockScreenPowerMenu"
                }
                Separator {}
                ToggleSetting {
                    label: "Lock before sleep"
                    // (Slate hears that the computer's about to sleep from systemd or elogind)
                    enabled: Config.hasLogind
                    opacity: enabled ? 1 : 0.5
                    detail: Config.hasLogind ? "Lock the screen whenever the computer suspends or hibernates" : Config.noLogindNote
                    key: "lockBeforeSleep"
                }
            }
            GroupLabel { text: "Login screen" }
            Group {
                SettingRow {
                    id: greeterRow
                    // From slate-greeter-sync --status: state (not-installed, outdated, current),
                    // greetd (yes/no), dm (the display manager in use), used (yes/no), backup (yes/no)
                    property var info: ({})
                    property string status: ""
                    readonly property string state: info.state || ""
                    // Installed and switched on: greetd starts it (not switched back since)
                    readonly property bool used: (state === "outdated" || state === "current") && info.used === "yes"
                    readonly property string dm: info.dm || "none"
                    readonly property string enable: info.enable || ""
                    label: "Slate login screen"
                    detail: status !== "" ? status
                        : state === "" ? ""
                        : !used && info.greetd !== "yes" ? "Optional. Replaces your computer's login screen with one that matches Slate. "
                            + "It runs on greetd, which isn't installed: install greetd with your package manager first"
                        : !used ? "Optional. Replaces your computer's login screen with one that matches Slate; "
                            + "until then, your computer keeps its own"
                        // (the command is the one for this computer's init system: bin/slate-init)
                        : dm === "none" ? "Installed, but greetd isn't switched on. "
                            + (enable !== "" ? "To switch it on, in a terminal:  " + enable : "Switch the greetd service on with your init system")
                        : dm !== "greetd" && dm !== "unknown" ? "Installed, but your computer starts " + dm + " instead. "
                            + ((info.switch || "") !== "" ? "To switch, in a terminal:  " + info.switch
                               : "Switch " + dm + " off and greetd on with your init system")
                        : state === "outdated" ? "Its design has changed since it was installed. Update asks for your password"
                        : "Installed; follows your wallpaper and theme automatically"
                    function refresh() { status = ""; greeterCheck.running = true; }
                    Process {
                        id: greeterCheck
                        running: true
                        command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--status"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                const o = {};
                                for (const line of text.split("\n")) { const i = line.indexOf("="); if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim(); }
                                greeterRow.info = o;
                            }
                        }
                    }
                    // Install, update or switch back, asking for your password (pkexec). Says what
                    // went wrong when it fails; cancelling the password prompt changes nothing
                    Process {
                        id: greeterRun
                        property string done: ""
                        property string failed: ""
                        stderr: StdioCollector { id: greeterErr }
                        onExited: code => {
                            const why = greeterErr.text.trim().split("\n").filter(l => l !== "")[0] || "";
                            greeterRow.status = code === 0 ? done
                                : code === 126 || code === 127 ? ""                   // password prompt cancelled
                                : failed + (why !== "" ? ": " + why : "");
                            greeterCheck.running = true;
                        }
                    }
                    function run(args, doing, done, failed) {
                        status = doing;
                        greeterRun.done = done; greeterRun.failed = failed;
                        greeterRun.command = ["pkexec", Quickshell.shellPath("bin/slate-greeter-install")].concat(args);
                        greeterRun.running = true;
                    }
                    Row {
                        spacing: 8
                        Button { label: "Preview"; onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "lock", "preview", "login"]); } }
                        Button {
                            visible: greeterRow.state !== "" && !greeterRow.used
                            enabled: greeterRow.info.greetd === "yes" && !greeterRun.running
                            opacity: enabled ? 1 : 0.4
                            label: "Install"
                            onClicked: win.ask = Object.assign({
                                run: () => greeterRow.run([], "Installing…",
                                    "Installed; shows at your next logout or restart", "Not installed")
                            }, win.loginScreenInstallQuestion)
                        }
                        Button {
                            visible: greeterRow.used && greeterRow.state === "outdated"
                            enabled: !greeterRun.running
                            label: "Update"
                            onClicked: win.ask = Object.assign({
                                run: () => greeterRow.run(["--code-only"], "Updating…",
                                    "Updated; shows at your next logout or restart", "Not updated")
                            }, win.loginScreenUpdateQuestion)
                        }
                        Button {
                            visible: greeterRow.used && greeterRow.info.backup === "yes"
                            enabled: !greeterRun.running
                            label: "Switch back"
                            onClicked: win.ask = {
                                title: "Switch back to your old login screen?",
                                body: "greetd goes back to the login screen it had before Slate's, from your next logout or restart. "
                                    + "You're welcome to install Slate's again at any time.",
                                button: "Switch back", code: 0xEAE2,
                                run: () => greeterRow.run(["--revert"], "Switching back…",
                                    "Switched back; your old login screen shows at your next logout or restart", "Not switched back")
                            }
                        }
                    }
                }
            }
            GroupLabel { text: "When you're away" }
            Group {
                ChoiceSetting {
                    label: "Lock after"
                    settingKey: "idleLockMinutes"
                    options: lockCol.minutes
                    value: Config.s.idleLockMinutes
                    onPicked: v => Config.s.idleLockMinutes = v
                }
                Separator {}
                ChoiceSetting {
                    label: "Turn the screen off after"
                    settingKey: "idleScreenOffMinutes"
                    detail: "Moving the mouse or pressing a key turns it back on"
                    options: lockCol.minutes
                    value: Config.s.idleScreenOffMinutes
                    onPicked: v => Config.s.idleScreenOffMinutes = v
                }
                Separator {}
                ChoiceSetting {
                    label: "Suspend after"
                    enabled: Config.canSuspend
                    opacity: enabled ? 1 : 0.5
                    detail: Config.canSuspend ? "" : Config.noLogindNote
                    settingKey: "idleSuspendMinutes"
                    options: lockCol.minutes
                    value: Config.s.idleSuspendMinutes
                    onPicked: v => Config.s.idleSuspendMinutes = v
                }
                Separator {}
                ToggleSetting {
                    label: "Wait while media plays"
                    detail: "You're not counted as away while a video or app is keeping the screen awake"
                    key: "idleRespectInhibitors"
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
            PageTitle { text: "Hot Corners" }
            IntroText { text: "Rest the pointer in a corner of the screen to run an action." }
            // The screen, with each corner's action; click one to set it below
            property string corner: "TopLeft"
            readonly property string cornerName: ({ TopLeft: "Top left", TopRight: "Top right", BottomLeft: "Bottom left", BottomRight: "Bottom right" })[corner]
            GroupLabel { text: "Corners" }
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
                    settingKey: "hotCornerDelay"
                    detail: "How long to rest in the corner before it triggers"
                    ValueSlider { from: 0; to: 1500; stepSize: 50; suffix: " ms"; value: Config.s.hotCornerDelay; onMoved: v => Config.s.hotCornerDelay = v }
                }
            }
        }
    }

    Component {
        id: bluetoothPage
        Column {
            id: bluetoothPane
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
            GroupLabel { text: "Status" }
            Group {
                SettingRow {
                    label: "Bluetooth"
                    detail: bluetoothPane.adapter ? (bluetoothPane.adapter.enabled ? "On" : "Off") : "No Bluetooth adapter found"
                    Toggle { visible: !!bluetoothPane.adapter; checked: bluetoothPane.adapter ? bluetoothPane.adapter.enabled : false; onToggled: v => { if (bluetoothPane.adapter) bluetoothPane.adapter.enabled = v; } }
                }
                Separator { visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled }
                SettingRow {
                    visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled
                    label: "New devices"
                    detail: bluetoothPane.adapter && bluetoothPane.adapter.discovering ? "Searching… put your device in pairing mode" : "Find nearby devices to pair"
                    Row {
                        spacing: 10
                        Text {
                            visible: bluetoothPane.adapter && bluetoothPane.adapter.discovering
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.glyph(0xF226)
                            color: win.accent
                            font.family: win.bar.iconFont; font.pixelSize: 16
                            RotationAnimation on rotation { running: parent.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                        Button {
                            icon: 0xEA37
                            label: bluetoothPane.adapter && bluetoothPane.adapter.discovering ? "Stop" : "Search"
                            primary: !(bluetoothPane.adapter && bluetoothPane.adapter.discovering)
                            onClicked: if (bluetoothPane.adapter) bluetoothPane.adapter.discovering = !bluetoothPane.adapter.discovering
                        }
                    }
                }
            }
            GroupLabel { visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled; text: "Devices" }
            Group {
                visible: bluetoothPane.adapter && bluetoothPane.adapter.enabled
                Text {
                    visible: bluetoothPane.devices.length === 0
                    x: 16; height: 48; verticalAlignment: Text.AlignVCenter
                    text: "No devices just yet"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
                Repeater {
                    model: bluetoothPane.devices
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property var d: modelData
                        width: parent.width
                        height: 60
                        Separator { visible: index > 0 }
                        Rectangle {
                            id: devIcon
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: 9
                            color: d.connected ? win.accent : win.outline
                            Text {
                                anchors.centerIn: parent
                                text: win.glyph(bluetoothPane.deviceIcon(d))
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

    // ---- Printers & Scanners: CUPS's printers and SANE's scanners (scripts/printers.py) -------
    Component {
        id: printersPage
        Column {
            id: printersPane
            spacing: 4
            readonly property string script: Quickshell.shellPath("scripts/printers.py")
            // From printers.py list: { service: "on"|"off"|"missing", printers: [...], configTool }
            property var state: ({ service: "", printers: [], configTool: "" })
            property var found: []                 // printers that could be added (printers.py find)
            property bool searched: false          // Find printers has run at least once
            property var scan: ({ sane: true, scanners: [], app: null })
            property bool scanLooked: false
            property string note: ""               // how the last action went
            readonly property bool printingOn: state.service === "on"

            function refresh() { listProc.running = false; listProc.running = true; }
            function lookForScanners() { scanProc.running = false; scanProc.running = true; }
            // Run one of printers.py's actions, then show how it went and look again
            function act(args, doing) {
                note = doing;
                actProc.command = [script].concat(args);
                actProc.running = true;
            }
            Process {
                id: listProc
                running: true
                command: [printersPane.script, "list"]
                stdout: StdioCollector { onStreamFinished: { try { printersPane.state = JSON.parse(text); } catch (e) {} } }
            }
            // Printers change by themselves (a job finishes, one goes offline): look again now and
            // then while the page shows (it's let go when Settings closes)
            Timer { interval: 5000; repeat: true; running: !actProc.running; onTriggered: printersPane.refresh() }
            Process {
                id: findProc
                command: [printersPane.script, "find"]
                stdout: StdioCollector { onStreamFinished: { try { printersPane.found = JSON.parse(text); } catch (e) { printersPane.found = []; } printersPane.searched = true; } }
            }
            Process {
                id: scanProc
                running: true
                command: [printersPane.script, "scanners"]
                stdout: StdioCollector { onStreamFinished: { try { printersPane.scan = JSON.parse(text); } catch (e) {} printersPane.scanLooked = true; } }
            }
            Process {
                id: actProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        const line = text.trim();
                        printersPane.note = line === "ok" ? "" : line.startsWith("error ")
                            ? (line === "error cancelled" ? "" : "That didn't work: " + line.slice(6)) : line;
                        printersPane.refresh();
                        // A printer added: it's no longer one to add
                        if (findProc.command && printersPane.searched) { findProc.running = false; findProc.running = true; }
                    }
                }
            }
            // A glyph for a printer, by how it's connected
            function printerIcon(p) { return (p.uri || "").startsWith("usb:") ? 0xF00C : 0xEB0E; }
            function statusText(p) {
                const s = p.status === "printing" ? "Printing" : p.status === "stopped" ? "Stopped" : "Ready";
                const jobs = p.jobs > 0 ? " · " + p.jobs + (p.jobs === 1 ? " job waiting" : " jobs waiting") : "";
                return (p.default ? "Default · " : "") + s + jobs + (p.accepting ? "" : " · not taking jobs");
            }

            PageTitle { text: "Printers & Scanners" }
            IntroText { text: "The printers and scanners this computer can use. Most printers from the last ten years work straight away, over the network or USB, with no driver to install." }

            GroupLabel { visible: printersPane.state.service === "missing" || printersPane.state.service === "off"; text: "Printing service" }
            // The printing service: not installed, or not running
            Group {
                visible: printersPane.state.service === "missing" || printersPane.state.service === "off"
                SettingRow {
                    label: printersPane.state.service === "missing" ? "Printing isn't installed" : "Printing is off"
                    detail: printersPane.state.service === "missing"
                        ? "Install CUPS (the cups package) to print"
                        : (printersPane.state.hint || "") !== ""
                            ? "The printing service (CUPS) isn't running. To switch it on, in a terminal:  " + printersPane.state.hint
                        : "The printing service (CUPS) isn't running. Turning it on asks for your password"
                    Button {
                        // (without systemd Slate shows the command instead: scripts/printers.py)
                        visible: printersPane.state.service === "off" && (printersPane.state.hint || "") === ""
                        label: "Turn on"; primary: true
                        onClicked: printersPane.act(["service-on"], "Turning printing on…")
                    }
                }
            }
            Text {
                visible: printersPane.note !== ""
                width: parent.width; leftPadding: 4; bottomPadding: 4
                text: printersPane.note
                color: printersPane.note.startsWith("That didn't") ? win.danger : win.dim
                font.family: win.font; font.pixelSize: 12; wrapMode: Text.Wrap
            }

            GroupLabel { visible: printersPane.printingOn; text: "Printers" }
            Group {
                visible: printersPane.printingOn
                Text {
                    visible: printersPane.state.printers.length === 0
                    x: 16; height: 48; verticalAlignment: Text.AlignVCenter
                    text: "No printers just yet. Let's find one below"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
                Repeater {
                    model: printersPane.state.printers
                    delegate: Item {
                        id: printerRow
                        required property var modelData
                        required property int index
                        readonly property var printer: modelData
                        width: parent.width
                        height: 60
                        Separator { visible: printerRow.index > 0 }
                        Rectangle {
                            id: printerIcon
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            width: 34; height: 34; radius: 9
                            color: printerRow.printer.default ? win.accent : win.outline
                            Text {
                                anchors.centerIn: parent
                                text: win.glyph(printersPane.printerIcon(printerRow.printer))
                                color: printerRow.printer.default ? win.accentText : win.text
                                font.family: win.bar.iconFont; font.pixelSize: 17
                            }
                        }
                        Column {
                            anchors { left: printerIcon.right; leftMargin: 12; right: printerButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; text: printerRow.printer.info || printerRow.printer.name; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: printersPane.statusText(printerRow.printer)
                                color: printerRow.printer.status === "stopped" ? win.danger : printerRow.printer.default ? win.accent : win.dim
                                font.family: win.font; font.pixelSize: 12
                            }
                        }
                        Row {
                            id: printerButtons
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Button {
                                visible: printerRow.printer.jobs > 0
                                label: "Cancel jobs"
                                onClicked: printersPane.act(["cancel", printerRow.printer.name], "Cancelling…")
                            }
                            Button {
                                visible: !printerRow.printer.default
                                label: "Make default"
                                onClicked: printersPane.act(["default", printerRow.printer.name], "")
                            }
                            Button {
                                label: "Test page"
                                onClicked: printersPane.act(["test", printerRow.printer.name], "Sending a test page…")
                            }
                            Button {
                                label: "Remove"
                                destructive: true
                                onClicked: win.ask = {
                                    title: "Remove " + (printerRow.printer.info || printerRow.printer.name) + "?",
                                    body: "It'll be taken off this computer's printers, along with any jobs still waiting. You can always add it again later. This asks for your password.",
                                    button: "Remove", destructive: true,
                                    run: () => printersPane.act(["remove", printerRow.printer.name], "Removing…")
                                }
                            }
                        }
                    }
                }
            }

            GroupLabel { visible: printersPane.printingOn; text: "Add a printer" }
            Group {
                visible: printersPane.printingOn
                SettingRow {
                    label: "Find printers"
                    detail: findProc.running ? "Looking on your network and USB…"
                        : printersPane.searched && printersPane.found.length === 0 ? "None found that aren't added already. Check it's switched on and on the same network"
                        : "Printers on your network or plugged in by USB that print with no driver"
                    Row {
                        spacing: 10
                        Text {
                            visible: findProc.running
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.glyph(0xF226)
                            color: win.accent
                            font.family: win.bar.iconFont; font.pixelSize: 16
                            RotationAnimation on rotation { running: parent.visible; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                        Button {
                            icon: 0xEB1C
                            label: printersPane.searched ? "Search again" : "Search"
                            primary: !printersPane.searched
                            opacity: findProc.running ? 0.5 : 1
                            onClicked: if (!findProc.running) findProc.running = true
                        }
                    }
                }
                Repeater {
                    model: printersPane.found
                    delegate: Item {
                        id: foundRow
                        required property var modelData
                        width: parent.width
                        height: 56
                        Separator {}
                        Text {
                            id: foundIcon
                            anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                            text: win.glyph(foundRow.modelData.via === "USB" ? 0xF00C : 0xEB0E)
                            color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                        Column {
                            anchors { left: foundIcon.right; leftMargin: 16; right: addButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 2
                            Text { width: parent.width; text: foundRow.modelData.name; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight }
                            Text { text: foundRow.modelData.via === "USB" ? "Plugged in by USB" : "On your network"; color: win.dim; font.family: win.font; font.pixelSize: 12 }
                        }
                        Button {
                            id: addButton
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            label: "Add"; primary: true
                            onClicked: printersPane.act(["add", foundRow.modelData.uri, foundRow.modelData.name], "Adding " + foundRow.modelData.name + "… (this asks for your password)")
                        }
                    }
                }
                Separator {}
                SettingRow {
                    label: "Other printers"
                    detail: "For one that needs a driver of its own, or more settings: " + (printersPane.state.configTool ? "the printer settings app" : "CUPS's settings page, in your browser")
                    Button {
                        icon: 0xEA99
                        label: "Open"
                        onClicked: Quickshell.execDetached(printersPane.state.configTool
                            ? [printersPane.state.configTool] : ["xdg-open", "http://localhost:631/admin"])
                    }
                }
            }

            GroupLabel { text: "Scanners" }
            Group {
                SettingRow {
                    visible: !printersPane.scan.sane
                    label: "Scanning isn't installed"
                    detail: "To scan, you'll need SANE installed (sane-utils or sane-backends, with sane-airscan for network scanners)"
                }
                Text {
                    visible: printersPane.scan.sane && printersPane.scan.scanners.length === 0
                    x: 16; height: 48; verticalAlignment: Text.AlignVCenter
                    text: scanProc.running ? "Looking for scanners…" : "No scanners found"
                    color: win.dim; font.family: win.font; font.pixelSize: 13
                }
                Repeater {
                    model: printersPane.scan.sane ? printersPane.scan.scanners : []
                    delegate: Item {
                        id: scannerRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 56
                        Separator { visible: scannerRow.index > 0 }
                        Text {
                            id: scannerIcon
                            anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                            text: win.glyph(0xEBC8)
                            color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 17
                        }
                        Text {
                            anchors { left: scannerIcon.right; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            text: scannerRow.modelData.name
                            color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight
                        }
                    }
                }
                Separator { visible: printersPane.scan.sane }
                SettingRow {
                    visible: printersPane.scan.sane
                    label: "Scan a document"
                    detail: printersPane.scan.app ? "Opens " + printersPane.scan.app.name
                        : "Install a scanning app, like Document Scanner (simple-scan)"
                    Row {
                        spacing: 8
                        Button {
                            icon: 0xEB13
                            label: "Look again"
                            opacity: scanProc.running ? 0.5 : 1
                            onClicked: if (!scanProc.running) printersPane.lookForScanners()
                        }
                        Button {
                            visible: !!printersPane.scan.app
                            icon: 0xEBC8
                            label: "Scan"; primary: true
                            onClicked: Quickshell.execDetached([printersPane.scan.app.command])
                        }
                    }
                }
            }
        }
    }

    Component {
        id: updatesPage
        Column {
            id: updatesPane
            spacing: 4
            // A second click confirms (updating over files you've changed; going back)
            property bool confirmUpdate: false
            property bool confirmRevert: false
            readonly property var mod: Updates.modified
            readonly property var touched: mod && mod.known ? mod.changed.concat(mod.added) : []
            readonly property string latest: Updates.latest
            function when(iso) { return iso ? Config.dateText(new Date(iso), "full") : ""; }
            function ago(ms) {
                const m = Math.max(0, Math.round((Date.now() - ms) / 60000));
                return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Config.dateText(new Date(ms), "day");
            }
            // "v0.4.2-15-gabc123" (a copy of the code past a release) reads as "v0.4.2 + 15 changes"
            function nice(v) {
                const m = /^(v[\d.]+)-(\d+)-g/.exec(v || "");
                return m ? m[1] + " + " + m[2] + " changes" : v;
            }
            Component.onCompleted: { Updates.check(false); Updates.findModified(); }

            PageTitle { text: "Updates" }
            IntroText { text: "Slate looks for a new version once a day and lets you know with a notification. Updating keeps your settings and your own tweaks (settings.json, hypr/ and user/ in ~/.config/slate), and keeps the version you had, so you can go back to it." }
            GroupLabel { text: "Version" }
            Group {
                SettingRow {
                    label: "Installed version"
                    detail: Updates.installed === "" ? "Unknown: this copy of Slate wasn't installed with a version"
                        : updatesPane.nice(Updates.installed)
                }
                Separator {}
                SettingRow {
                    label: Updates.available ? "Slate " + updatesPane.latest + " is available" : "Latest version"
                    detail: Updates.checking ? "Checking…"
                        : Updates.error !== "" && Updates.status !== "failed" ? Updates.error
                        : updatesPane.latest === "" ? "Not checked yet"
                        : (Updates.available ? "Released " + updatesPane.when(Updates.state.published) : updatesPane.latest + ": you're up to date")
                          + (Updates.checkedAt > 0 ? " · checked " + updatesPane.ago(Updates.checkedAt) : "")
                    Button { label: Updates.checking ? "Checking…" : "Check now"; icon: 0xEB13; onClicked: Updates.check(true) }
                }
                Separator {}
                ToggleSetting {
                    label: "Check for updates"
                    detail: "Once a day, and Slate lets you know when there's a new version"
                    key: "updateCheck"
                }
            }

            // ---- A new version: what's new, and updating ----
            GroupLabel {
                visible: Updates.available || Updates.busy || Updates.status === "failed"
                text: "What's new in " + updatesPane.latest
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
                    visible: updatesPane.touched.length > 0 && !Updates.busy
                    topPadding: 12; bottomPadding: 4
                    text: "You've changed some of Slate's own files, outside settings.json, hypr/ and user/. Updating replaces them; your versions stay in ~/.config/slate.previous:\n"
                        + updatesPane.touched.slice(0, 8).map(f => "  · " + f).join("\n")
                        + (updatesPane.touched.length > 8 ? "\n  · and " + (updatesPane.touched.length - 8) + " more" : "")
                    color: win.danger; font.family: win.font; font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
                SettingRow {
                    label: Updates.status === "downloading" ? "Downloading " + updatesPane.latest + "…"
                        : Updates.status === "installing" ? "Installing " + updatesPane.latest + "…"
                        : Updates.status === "failed" ? "The update didn't finish"
                        : "Update to " + updatesPane.latest
                    detail: Updates.status === "installing" ? "Slate restarts on the new version when it's done"
                        : Updates.status === "failed" ? Updates.error
                        : updatesPane.confirmUpdate ? "Your changed files above will be replaced. Click again to update"
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
                            label: Updates.status === "failed" ? "Try again" : updatesPane.confirmUpdate ? "Update anyway" : "Update now"
                            onClicked: {
                                if (updatesPane.touched.length > 0 && !updatesPane.confirmUpdate) { updatesPane.confirmUpdate = true; return; }
                                updatesPane.confirmUpdate = false;
                                Updates.install();
                            }
                        }
                    }
                }
            }

            GroupLabel { visible: Updates.status === "done" || Updates.status === "reverted"; text: "Latest change" }
            // ---- Just updated, or went back ----
            Group {
                visible: Updates.status === "done" || Updates.status === "reverted"
                SettingRow {
                    label: Updates.status === "done" ? "Updated to " + updatesPane.nice(Updates.installed) : "Back on " + updatesPane.nice(Updates.installed)
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
                    label: "Go back to " + (Updates.previous === "unknown" ? "the previous version" : updatesPane.nice(Updates.previous))
                    detail: updatesPane.confirmRevert ? "Click again to switch. Your settings and tweaks stay as they are now"
                        : "Kept in ~/.config/slate.previous. Your settings and tweaks stay as they are now, and the version you leave is kept instead, so you can switch back"
                    Button {
                        enabled: !Updates.busy
                        label: updatesPane.confirmRevert ? "Go back now" : "Go back"
                        onClicked: {
                            if (!updatesPane.confirmRevert) { updatesPane.confirmRevert = true; return; }
                            updatesPane.confirmRevert = false;
                            Updates.revert();
                        }
                    }
                }
            }
        }
    }

    // ---- Webcam ----------------------------------------------------------------
    // The camera's picture settings, through scripts/webcam.py (v4l2-ctl). Changes apply at
    // once; cameras forget them when unplugged or restarted, so they're remembered and put
    // back at login (Config: webcam.py apply)
    Component {
        id: webcamPage
        Column {
            id: camPane
            spacing: 4
            readonly property string script: Quickshell.shellPath("scripts/webcam.py")
            property var cams: []
            property string error: ""
            property bool looked: false
            property string chosen: ""
            readonly property var cam: cams.find(c => c.device === chosen) || cams[0] || null
            property bool preview: false          // the camera (and its light) only on when asked
            property var usedBy: []
            // Plain words for the camera's own names for its settings: [label, detail]
            readonly property var words: ({
                brightness: ["Brightness", ""],
                contrast: ["Contrast", ""],
                saturation: ["Colour", "How vivid colours are"],
                sharpness: ["Sharpness", ""],
                gain: ["Gain", "Brightens a dim picture, at the cost of more grain"],
                gamma: ["Gamma", "Brightens or darkens the middle tones"],
                white_balance_temperature: ["Colour temperature", "Lower is warmer, higher is cooler"],
                exposure_time_absolute: ["Exposure", "How long each frame gathers light: longer is brighter, but blurs movement"],
                backlight_compensation: ["Backlight compensation", "Brightens you when there's a bright light behind you"]
            })

            function refresh() { listProc.running = false; listProc.running = true; }
            function ctrl(name) { return cam ? cam.controls.find(c => c.name === name) || null : null; }
            // Change a setting: shown at once, sent a moment later (a slider moves many times)
            property var pending: ({})
            function setCtrl(name, value) {
                const copy = JSON.parse(JSON.stringify(cams));
                const c = copy.find(x => x.device === cam.device);
                const k = c ? c.controls.find(x => x.name === name) : null;
                if (k) k.value = Math.round(value);
                cams = copy;
                const p = Object.assign({}, pending);
                p[name] = Math.round(value);
                pending = p;
                sendSoon.restart();
            }
            Timer {
                id: sendSoon
                interval: 120
                onTriggered: {
                    for (const n in camPane.pending)
                        Quickshell.execDetached([camPane.script, "set", camPane.cam.device, n, String(camPane.pending[n])]);
                    camPane.pending = {};
                    readBack.restart();
                }
            }
            // (switching automatic white balance or exposure off makes their manual setting usable)
            Timer { id: readBack; interval: 500; onTriggered: camPane.refresh() }
            Process {
                id: listProc
                running: true
                command: [camPane.script, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const d = JSON.parse(text);
                            if (Array.isArray(d)) { camPane.cams = d; camPane.error = ""; } else camPane.error = d.error || "";
                        } catch (e) { camPane.error = "Slate couldn't read the webcams"; }
                        camPane.looked = true;
                    }
                }
            }
            Process {
                id: resetProc
                onExited: camPane.refresh()
            }
            // Who's using a camera, looked at again now and then while the page shows
            Process {
                id: usersProc
                running: true
                command: [camPane.script, "users"]
                stdout: StdioCollector { onStreamFinished: { try { camPane.usedBy = JSON.parse(text); } catch (e) {} } }
            }
            Timer { interval: 3000; repeat: true; running: win.visible; onTriggered: { usersProc.running = false; usersProc.running = true; } }
            // Restore defaults (the page title's): the camera's own defaults
            readonly property bool changed: !!cam && cam.controls.some(c => c.default !== undefined && c.value !== c.default)
            function reset() { if (cam) { resetProc.command = [script, "reset", cam.device]; resetProc.running = true; } }
            Binding { target: win; property: "pageResetChanged"; value: camPane.changed }
            Component.onCompleted: win.pageResetRun = () => camPane.reset()
            Component.onDestruction: win.pageResetRun = null

            PageTitle { text: "Webcam" }
            IntroText { text: "Your camera's picture. Changes apply straight away, to every app that uses the camera, and are kept when it's unplugged or the computer restarts." }

            GroupLabel { visible: camPane.looked; text: "Camera" }
            // Nothing to show
            Group {
                visible: camPane.looked && (camPane.error !== "" || camPane.cams.length === 0)
                SettingRow {
                    label: camPane.error !== "" ? "Can't reach the camera" : "No webcam found"
                    detail: camPane.error !== "" ? camPane.error : "Plug one in, or check it isn't switched off (some laptops have a key or a slider for it)"
                    Button { label: "Look again"; icon: 0xEB13; onClicked: camPane.refresh() }
                }
            }

            // ---- Preview -------------------------------------------------------------
            Group {
                visible: !!camPane.cam
                Item {
                    width: parent.width
                    height: Math.round(Math.min(width * 9 / 16, 320)) + 16
                    Rectangle {
                        id: previewBox
                        anchors { fill: parent; margins: 8 }
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.35)
                        clip: true
                        Loader {
                            id: previewLoader
                            anchors.fill: parent
                            active: camPane.preview && win.visible && !!camPane.cam
                            source: Qt.resolvedUrl("WebcamPreview.qml")
                            onLoaded: item.device = Qt.binding(() => camPane.cam ? camPane.cam.device : "")
                        }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 40
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: !(previewLoader.item && previewLoader.item.showing)
                            color: win.dim
                            font.pixelSize: 13
                            text: !camPane.preview ? "The preview is off, so the camera isn't on"
                                : previewLoader.status === Loader.Error ? "The preview needs Qt Multimedia (qt6-multimedia)"
                                : previewLoader.item && previewLoader.item.problem !== "" ? "No picture: " + previewLoader.item.problem
                                : "Starting the camera…"
                        }
                    }
                }
                SettingRow {
                    label: "Preview"
                    detail: "Shows the camera here. Its light comes on while it's shown"
                    Toggle { checked: camPane.preview; onToggled: v => camPane.preview = v }
                }
                Separator { visible: camPane.cams.length > 1 }
                DropdownSetting {
                    visible: camPane.cams.length > 1
                    label: "Camera"
                    options: camPane.cams.map(c => ({ value: c.device, label: c.name }))
                    value: camPane.cam ? camPane.cam.device : ""
                    onPicked: v => camPane.chosen = v
                }
                Separator {}
                SettingRow {
                    label: "In use by"
                    detail: camPane.usedBy.length === 0 ? "No app is using the camera"
                        : camPane.usedBy.map(u => u.name).filter((n, i, a) => a.indexOf(n) === i).join(", ")
                }
            }

            // ---- Picture -------------------------------------------------------------
            GroupLabel { visible: !!camPane.cam; text: "Picture" }
            Group {
                visible: !!camPane.cam
                Repeater {
                    model: ["brightness", "contrast", "saturation", "sharpness", "gain", "gamma"].filter(n => !!camPane.ctrl(n))
                    delegate: Column {
                        required property string modelData
                        required property int index
                        width: parent.width
                        readonly property var c: camPane.ctrl(modelData)
                        Separator { visible: index > 0 }
                        SettingRow {
                            label: camPane.words[modelData][0]
                            detail: camPane.words[modelData][1]
                            ValueSlider {
                                from: c ? c.min : 0; to: c ? c.max : 1; stepSize: c ? c.step : 1
                                value: c ? c.value : 0
                                onMoved: v => camPane.setCtrl(modelData, v)
                            }
                        }
                    }
                }
            }

            // ---- Light -------------------------------------------------------------
            GroupLabel { visible: !!camPane.cam; text: "Light" }
            Group {
                visible: !!camPane.cam
                SettingRow {
                    visible: !!camPane.ctrl("white_balance_automatic")
                    label: "Automatic white balance"
                    detail: "Adjusts the colours to the light in the room. Off: set the colour temperature yourself"
                    Toggle {
                        checked: camPane.ctrl("white_balance_automatic") ? camPane.ctrl("white_balance_automatic").value === 1 : true
                        onToggled: v => camPane.setCtrl("white_balance_automatic", v ? 1 : 0)
                    }
                }
                Separator { visible: !!camPane.ctrl("white_balance_temperature") && !!camPane.ctrl("white_balance_automatic") && camPane.ctrl("white_balance_automatic").value === 0 }
                SettingRow {
                    readonly property var c: camPane.ctrl("white_balance_temperature")
                    visible: !!c && !!camPane.ctrl("white_balance_automatic") && camPane.ctrl("white_balance_automatic").value === 0
                    label: camPane.words.white_balance_temperature[0]
                    detail: camPane.words.white_balance_temperature[1]
                    ValueSlider {
                        from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                        suffix: " K"; value: parent.c ? parent.c.value : 0
                        onMoved: v => camPane.setCtrl("white_balance_temperature", v)
                    }
                }
                Separator { visible: !!camPane.ctrl("auto_exposure") }
                SettingRow {
                    readonly property var c: camPane.ctrl("auto_exposure")
                    visible: !!c
                    label: "Automatic exposure"
                    detail: "Adjusts how bright the picture is to the light. Off: set the exposure yourself"
                    Toggle {
                        // (1 is manual on every camera; the automatic one varies: the camera's default)
                        checked: parent.c ? parent.c.value !== 1 : true
                        onToggled: v => camPane.setCtrl("auto_exposure", v ? (parent.c.default !== 1 ? parent.c.default : 3) : 1)
                    }
                }
                Separator { visible: !!camPane.ctrl("exposure_time_absolute") && !!camPane.ctrl("auto_exposure") && camPane.ctrl("auto_exposure").value === 1 }
                SettingRow {
                    readonly property var c: camPane.ctrl("exposure_time_absolute")
                    visible: !!c && !!camPane.ctrl("auto_exposure") && camPane.ctrl("auto_exposure").value === 1
                    label: camPane.words.exposure_time_absolute[0]
                    detail: camPane.words.exposure_time_absolute[1]
                    ValueSlider {
                        from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                        value: parent.c ? parent.c.value : 0
                        onMoved: v => camPane.setCtrl("exposure_time_absolute", v)
                    }
                }
                Separator { visible: !!camPane.ctrl("power_line_frequency") }
                DropdownSetting {
                    readonly property var c: camPane.ctrl("power_line_frequency")
                    visible: !!c
                    label: "Anti-flicker"
                    detail: "Match your mains electricity to stop lights flickering in the picture: 50 Hz in the UK, Europe and most of the world, 60 Hz in North America"
                    options: c ? c.options.map(o => ({ value: o[0], label: o[1] === "Disabled" ? "Off" : o[1] })) : []
                    value: c ? c.value : 0
                    onPicked: v => camPane.setCtrl("power_line_frequency", v)
                }
                Separator { visible: !!camPane.ctrl("backlight_compensation") }
                SettingRow {
                    readonly property var c: camPane.ctrl("backlight_compensation")
                    visible: !!c
                    label: camPane.words.backlight_compensation[0]
                    detail: camPane.words.backlight_compensation[1]
                    ValueSlider {
                        from: parent.c ? parent.c.min : 0; to: parent.c ? parent.c.max : 1; stepSize: parent.c ? parent.c.step : 1
                        zeroText: "Off"; value: parent.c ? parent.c.value : 0
                        onMoved: v => camPane.setCtrl("backlight_compensation", v)
                    }
                }
            }
        }
    }

    // Debug: fixes you shouldn't normally need (a tile on All Settings, not in the sidebar)
    Component {
        id: debugPage
        Column {
            spacing: 4
            PageTitle { text: "Debug" }
            IntroText {
                text: "Fixes for when something hasn't caught up. Slate normally does all of this by itself, so you shouldn't need them."
                leftPadding: 0; bottomPadding: 8
            }
            GroupLabel { text: "Reload" }
            Group {
                SettingRow {
                    label: "Reload everything"
                    detail: "Reloads Hyprland's config and restarts Slate from scratch (the bar, dock, panels and this window), "
                        + "then comes back here. Your apps and windows stay open. For when something looks stuck or out of date"
                    Button { label: "Reload"; icon: 0xEB13; onClicked: Config.reloadEverything() }
                }
            }
            GroupLabel { text: "Login screen" }
            Group {
                SettingRow {
                    id: resyncRow
                    property bool installed: false
                    property string status: ""
                    label: "Resync the login screen"
                    detail: status !== "" ? status
                        : !installed ? "Only for Slate's own login screen, which isn't set up"
                        : "The login screen copies your wallpaper, settings, picture and font whenever you change them in Slate. "
                          + "Use this if you changed one outside Slate (replaced the wallpaper file, changed your picture, name "
                          + "or keyboard layout elsewhere) and the login screen hasn't caught up"
                    Process {
                        running: true
                        command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--check"]
                        stdout: StdioCollector { onStreamFinished: { const t = text.trim(); resyncRow.installed = t === "outdated" || t === "current"; } }
                    }
                    Process {
                        id: resyncRun
                        command: [Quickshell.shellPath("bin/slate-greeter-sync")]
                        onExited: code => resyncRow.status = code === 0 ? "Resynced just now" : "Slate couldn't resync. Is the login screen set up?"
                    }
                    Button {
                        enabled: resyncRow.installed
                        opacity: enabled ? 1 : 0.4
                        label: "Resync"
                        onClicked: { resyncRow.status = "Resyncing…"; resyncRun.running = true; }
                    }
                }
            }
            GroupLabel { text: "Logs" }
            Group {
                DropdownSetting {
                    label: "Log detail"
                    settingKey: "logLevel"
                    detail: "How much Slate writes to its log. Turn it up while tracking down a problem, then back down. Changing it restarts Slate"
                    options: [{ value: "normal", label: "Normal" }, { value: "detailed", label: "Detailed" }, { value: "everything", label: "Everything" }]
                    value: Config.s.logLevel || "normal"
                    // Asks first: changing it restarts Slate
                    onPicked: v => {
                        if (v === (Config.s.logLevel || "normal")) return;
                        const name = ({ normal: "Normal", detailed: "Detailed", everything: "Everything" })[v];
                        win.ask = {
                            title: "Restart Slate?",
                            body: "Log detail changes to " + name + " when Slate restarts. Your apps and windows stay open. "
                                + "The bar, dock and Settings step away for a moment, then Settings opens again right here.",
                            button: "Restart",
                            run: () => { Config.s.logLevel = v; Config.logLevelEdited(); }
                        };
                    }
                }
                Separator {}
                SettingRow {
                    id: exportRow
                    property string saved: ""          // the file, once exported
                    property string status: ""
                    label: "Export recent logs"
                    detail: status !== "" ? status
                        : "Saves Slate's recent log and details about your system to a text file in Downloads, to attach "
                          + "when reporting a problem. Your location is left out; look the file over before sharing it, as "
                          + "the log can name apps, windows and file paths"
                    Process {
                        id: exportRun
                        command: [Quickshell.shellPath("bin/slate-logs")]
                        stdout: StdioCollector { onStreamFinished: exportRow.saved = text.trim() }
                        onExited: code => exportRow.status = code === 0 && exportRow.saved !== ""
                            ? "Saved to " + exportRow.saved.replace(Quickshell.env("HOME"), "~") + ". Look it over before sharing it"
                            : "Slate couldn't save the logs"
                    }
                    Row {
                        spacing: 8
                        Button { visible: exportRow.saved !== ""; label: "Show"; onClicked: Quickshell.execDetached(["xdg-open", exportRow.saved.substring(0, exportRow.saved.lastIndexOf("/"))]) }
                        Button { label: "Export"; onClicked: { exportRow.saved = ""; exportRow.status = "Saving…"; exportRun.running = true; } }
                    }
                }
            }
            GroupLabel { text: "Start over" }
            Group {
                SettingRow {
                    label: "Factory reset"
                    detail: "Puts Slate back as it was when first installed: every setting to its default, and your dock pins, "
                        + "saved Spaces, launcher history, notifications, clipboard history, display layout and app theming "
                        + "forgotten. You'll be asked twice before anything changes, and can choose to clear your own files "
                        + "(~/.config/slate/hypr and user/) as well. Everything is kept in a backup folder "
                        + "(~/.local/share/slate/backups)"
                    Button {
                        label: "Reset…"
                        destructive: true
                        onClicked: win.ask = {
                            title: "Reset Slate?",
                            body: "Every setting goes back to its default, and Slate forgets your dock pins, saved Spaces, launcher "
                                + "history, notifications, clipboard history, display layout and app theming. Your apps and "
                                + "windows stay open.",
                            option: { label: "Also clear my own files",
                                      detail: "Your Hyprland tweaks (~/.config/slate/hypr) and your own QML (user/) go back to the blank versions Slate starts with" },
                            button: "Continue",
                            run: userFiles => win.askAfter({
                                title: userFiles ? "Erase everything, including your own files?" : "Erase all of Slate's settings?",
                                body: "This is the last step. Straight away, Slate forgets every setting, your dock pins, saved Spaces, "
                                    + "launcher and clipboard history, notifications, display layout and app theming"
                                    + (userFiles ? ", and your own files are replaced with blank ones: every keybind, monitor, "
                                        + "window rule and autostart you added in ~/.config/slate/hypr, and your QML in user/" : "")
                                    + ". Slate restarts and the welcome tour opens.\n\nThere's no undo in Settings. The old files are "
                                    + "moved to ~/.local/share/slate/backups, and you'd have to copy them back by hand.",
                                button: userFiles ? "Erase everything" : "Erase and reset",
                                destructive: true,
                                run: () => Quickshell.execDetached(["setsid", "-f", Quickshell.shellPath("bin/slate-factory-reset")]
                                    .concat(userFiles ? ["--user-files"] : []))
                            })
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
            IntroText { text: "Slate is this desktop's shell: the bar, dock, launcher, window and workspace switchers, panels, notifications and these settings. It runs on Quickshell and Hyprland, from ~/.config/slate." }
            // As in LICENSE
            Text {
                text: "© 2026 Dayle Rees · MIT License"
                color: win.dim; font.family: win.font; font.pixelSize: 12
                leftPadding: 4; bottomPadding: 10
            }
            // What Slate is using right now, shown like the battery panel's meters: its memory (of
            // all the memory), how busy it keeps the processor, and the last minute of that as a
            // graph. Read from /proc every 2 s while Settings is open (Slate is one process)
            GroupLabel { text: "What Slate is using" }
            Group {
                id: usage
                property real mem: 0            // MB
                property real memTotal: 0       // MB
                property real cpu: -1           // % of the whole processor
                property var history: []        // the last minute of cpu readings
                property real lastTicks: -1
                property real lastTime: 0
                property int cores: 1
                // Shown values glide from one reading to the next
                property real memShown: memTotal > 0 ? mem / memTotal : 0
                property real cpuShown: Math.max(0, cpu) / 100
                Behavior on memShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
                Behavior on cpuShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
                function mb(v) { return v >= 1024 ? (v / 1024).toFixed(v >= 10240 ? 0 : 1) + " GB" : Math.round(v) + " MB"; }
                Process {
                    id: usageProc
                    // One awk reads all three files; prints Slate's memory (kB), its processor time
                    // (ticks), the number of cores and the total memory (kB), one per line.
                    // $PPID: the shell's parent, Slate itself.
                    command: ["sh", "-c", "awk -v cores=\"$(nproc)\" 'FILENAME ~ /status$/ && /^VmRSS/ { mem = $2 } FILENAME ~ /stat$/ { ticks = $14 + $15 } /^MemTotal/ { total = $2 } END { print mem; print ticks; print cores; print total }' /proc/$PPID/status /proc/$PPID/stat /proc/meminfo"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const l = text.trim().split("\n");
                            if (l.length < 4) return;
                            usage.mem = Number(l[0]) / 1024;
                            usage.cores = Number(l[2]) || 1;
                            usage.memTotal = Number(l[3]) / 1024;
                            const ticks = Number(l[1]), now = Date.now();
                            if (usage.lastTicks >= 0 && now > usage.lastTime) {
                                usage.cpu = Math.max(0, (ticks - usage.lastTicks) / 100 / ((now - usage.lastTime) / 1000) / usage.cores * 100);
                                usage.history = usage.history.concat([usage.cpu]).slice(-30);
                            }
                            usage.lastTicks = ticks; usage.lastTime = now;
                        }
                    }
                }
                Timer {
                    interval: 2000; repeat: true; triggeredOnStart: true
                    running: win.visible
                    onTriggered: { usageProc.running = false; usageProc.running = true; }
                }
                Column {
                    x: 16; width: parent.width - 32
                    topPadding: 14; bottomPadding: 14
                    spacing: 14
                    // Meters, as in the battery panel
                    Repeater {
                        model: ["Memory", "Processor"]
                        delegate: Column {
                            required property string modelData
                            readonly property bool isMem: modelData === "Memory"
                            readonly property real frac: isMem ? usage.memShown : usage.cpuShown
                            width: parent.width
                            spacing: 6
                            Item {
                                width: parent.width; height: meterName.height
                                Text { id: meterName; text: parent.parent.modelData; color: win.text; font.family: win.font; font.pixelSize: 13; font.weight: Font.Medium }
                                Text {
                                    anchors.right: parent.right
                                    text: parent.parent.isMem ? (usage.mem > 0 ? usage.mb(usage.mem) + " of " + usage.mb(usage.memTotal) : "Checking…")
                                        : (usage.cpu < 0 ? "Checking…" : usage.cpu.toFixed(1) + "% of " + usage.cores + " cores")
                                    color: win.dim; font.family: win.font; font.pixelSize: 12
                                }
                            }
                            Rectangle {
                                width: parent.width; height: 6; radius: 3
                                color: win.divider
                                Rectangle {
                                    width: Math.max(height, parent.width * Math.min(1, parent.parent.frac))
                                    height: parent.height; radius: 3
                                    color: parent.parent.frac > 0.8 ? win.danger : win.accent
                                    Behavior on color { ColorAnimation { duration: Config.ms(300) } }
                                }
                            }
                        }
                    }
                    // The processor over the last minute: scaled to its own peak, so the small
                    // ups and downs show
                    // Its room only once there's a graph to draw (two readings), so the card doesn't
                    // sit with a gap under the meters while it waits
                    Item {
                        readonly property bool ready: usage.history.length >= 2
                        width: parent.width; height: ready ? 64 : 0
                        visible: height > 0
                        clip: true
                        Behavior on height { NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }
                        readonly property real realPeak: usage.history.length ? Math.max(...usage.history) : 0
                        readonly property real peak: Math.max(2, realPeak)     // the graph's top (at least 2%, so tiny wobbles stay small)
                        Canvas {
                            id: spark
                            anchors.fill: parent
                            readonly property var data: usage.history
                            readonly property color line: win.accent
                            onDataChanged: requestPaint()
                            onLineChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const d = data, n = 30, w = width, h = height - 2, pk = parent.peak;
                                if (d.length < 2) return;
                                const x = i => w - (d.length - 1 - i) * (w / (n - 1));
                                const y = v => 1 + h - Math.min(1, v / pk) * (h - 2);
                                ctx.beginPath();
                                ctx.moveTo(x(0), y(d[0]));
                                for (let i = 1; i < d.length; i++) ctx.lineTo(x(i), y(d[i]));
                                ctx.lineWidth = 2;
                                ctx.strokeStyle = line;
                                ctx.lineJoin = "round";
                                ctx.stroke();
                                // Soft fill under the line
                                ctx.lineTo(x(d.length - 1), h + 1);
                                ctx.lineTo(x(0), h + 1);
                                ctx.closePath();
                                const g = ctx.createLinearGradient(0, 0, 0, h);
                                g.addColorStop(0, Qt.rgba(line.r, line.g, line.b, 0.28));
                                g.addColorStop(1, Qt.rgba(line.r, line.g, line.b, 0));
                                ctx.fillStyle = g;
                                ctx.fill();
                            }
                        }
                        Text {
                            anchors { left: parent.left; top: parent.top }
                            visible: usage.history.length >= 2
                            text: "Last minute · peak " + parent.realPeak.toFixed(1) + "%"
                            color: win.dim; font.family: win.font; font.pixelSize: 11
                        }
                    }
                }
            }
            GroupLabel { text: "Tools" }
            Group {
                SettingRow {
                    label: "Welcome"
                    detail: "The friendly introduction from Slate's first start, with its recommended choices"
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
                    Button { label: "Restart"; onClicked: Config.restartSlate() }
                }
            }
        }
    }
}
