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
import "NotificationText.js" as NotificationText
import "settings"
import "settings/pages"

FloatingWindow {
    id: win
    // Wallpaper thumbnails still loading (the tests wait for none before a picture)
    property int thumbsLoading: 0
    property bool wallsListing: false
    // A page's first looks at the system still running (printing, the webcam, the login
    // screen…: FirstLook), for the same reason
    property int checking: 0
    required property var bar
    property var notifs: null
    // Slate's confirmation window (PowerConfirm: confirmWith), for questions asked as the rest
    // of Slate asks them (installing an app)
    property var confirmer: null
    // Talking to Nova: whisper.cpp and the speech model (VoiceModel.qml, kept by shell.qml so a
    // download carries on with Settings closed)
    property var voice: null

    // The building blocks and pages in settings/ reach this window as SettingsHost.win, and the
    // shared dropdown layer and the scrolling page by these names
    readonly property alias drop: dropLayer
    readonly property alias scrollView: scroller
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
    property bool wasVisible: false
    color: bar.barColor
    onVisibleChanged: {
        const a = Bluetooth.defaultAdapter;
        if (!visible && a && a.discovering) a.discovering = false;
        if (!visible) dropLayer.owner = null; // and closes an open dropdown (its page is let go)
        // Only as it opens: showing the window can report "visible" again a moment later (longer
        // on a busy machine), and that would otherwise send a page asked for in between back
        // to All Settings
        const opening = visible && !wasVisible;
        wasVisible = visible;
        if (opening && !keepSection) section = "overview";
        // Cleared a moment later, not now
        if (visible) keepClear.restart(); else keepSection = false;
        placeSave.restart();                  // open: where it is; closed: forgotten
    }

    // (`slate ipc call settings …` is in shell.qml, so it works before this window is built)

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
    // The theme's greys, named for what they're used for (each worked out once, not per item)
    readonly property color well: Config.tint("#151920")           // sunken areas: the content pane, search wells, segmented tracks
    readonly property color divider: Config.tint("#262c35")        // separators, chosen rows, meter tracks
    readonly property color outline: Config.tint("#2a313c")        // borders, idle icon tiles
    readonly property color popupFill: Config.tint("#1d222a")      // dropdown menus and other pop-ups
    readonly property color controlHoverSolid: Config.tint("#323a46")  // a button under the pointer (without glass)
    readonly property color ring: Config.tint("#3a424e")           // the outline round a swatch or picture
    readonly property color faint: Qt.rgba(text.r, text.g, text.b, 0.06)   // a whisper of the text colour, for flat fills
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
    signal searchFor(string text)          // (the settings IPC's search: the search box showing takes it)
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
    // (the file's name comes from shell.qml, which also reads it to build this window at start)
    required property string placeFile
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
    // Closed from outside Slate and about to be dropped: forget the place now, as the timer
    // below would go with the window
    function forgetPlace() { if (placeReady) placeView.setText("{}"); }
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
    Component.onCompleted: { SettingsHost.win = win; if (placeView.loaded) restoreFromFile(); }
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
    // For the tests: the settings on this page greyed out for another one (SettingRow's needs),
    // and following one's line to what it needs, as clicking it does
    function waitingRows() {
        const out = [];
        const walk = it => {
            if (!it || !it.visible) return;
            if (it.waiting === true && it.needs !== undefined) out.push(it);
            for (const c of it.children) walk(c);
        };
        walk(pageLoader.item);
        return out;
    }
    // For the tests: one thing about the chosen display changed, as its row on the Displays
    // page does (it applies at once, and waits to be kept)
    function displayChange(field, value) {
        if (section === "displays" && pageLoader.item) pageLoader.item.change(field, value);
    }
    function followNeeds(label) {
        const row = waitingRows().find(r => r.label === label);
        if (row && row.needsPage !== "") goTo(row.needsPage, row.needsLabel);
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
    // The settings each page can restore to their defaults. Left out on purpose: your
    // location and night light on/off (General), and the chosen wallpaper (Appearance)
    readonly property var pageKeys: ({
        datetime: ["dateFormat", "weekStart", "temperatureUnit"],
        general: ["clipboardHistory", "nightLightTemperature", "nightLightSchedule", "nightLightFrom", "nightLightTo"],
        appearance: ["themeMode", "lightMode", "colourStyle", "accentFromWallpaper", "accentBoldness", "accent", "toneFromWallpaper", "toneBoldness", "roundedScreenCorners", "roundedElements",
            "animations", "glass", "glassOpacity", "glassBlur", "glassGloss", "glassGlossTint", "fastBlur", "blurPasses", "shadows", "shadowDarkness", "shadowSoftness", "shadowSpread", "shadowDistance", "shadowDirection", "fontFamily", "codeFontFamily", "codeFontInApps", "uiScale"],
        wallpaper: ["wallpaperFolder", "wallpaperChange", "wallpaperHideSmall", "wallpaperMinSize", "wallpaperShowSlate"],
        icons: ["iconTheme", "folderColour", "iconShape", "iconFill", "iconTileColour", "tintIcons", "iconTintStrength"],
        bar: ["barPosition", "barLayout", "barOverflow", "barStay", "barBlur", "barOpacity", "barPanelBlur", "barPanelOpacity", "barItemOpacity", "barItemHoverOpacity", "barAutoHide", "barShowControl", "barShowClock", "barShowApps", "barShowSpaces", "barShowAssistant", "barShowWorkspaces", "barShowWorkspaceName", "barShowWindowMode", "barShowTitle", "barShowTitleIcon",
            "barShowTray", "barTrayMono", "barShowNotifications", "barShowClipboard", "barShowScreenshot", "barShowCamera", "barShowGameMode", "barShowWifi", "barShowKeyboard", "barShowBluetooth", "barShowVolume", "barShowBattery", "barValueClipboard", "barValueGameMode", "barValueWifi", "barValueKeyboard", "barValueBluetooth", "barValueVolume", "barValueBattery", "barTrayCollapsed", "barStatusCollapsed",
            "barShowPower", "barClockFormat", "barClockSeconds", "barClockDate"],
        control: ["controlSwitches"],
        dock: ["dockPosition", "dockAutoHide", "dockShowLauncher", "dockPreviews", "dockPreviewDelay", "dockBadges", "dockDivider", "dockShowMedia", "dockMediaArt", "dockShowDownloads", "dockShowTrash", "dockIconSize", "dockHoverEffect", "dockMagnification", "dockSpread", "dockBlur", "dockOpacity", "dockTileOpacity", "dockIconOpacity"],
        launcher: ["launcherBlur", "launcherOpacity", "launcherLayout", "launcherColumns", "launcherRows", "launcherDescriptions", "launcherSortByUsage",
            "launcherWrap", "launcherRecent", "launcherFuzzy", "launcherWindows", "launcherActions", "launcherToggles", "launcherFiles",
            "launcherConvert", "launcherCommands", "launcherEmoji", "launcherWeb", "launcherSearchEngine"],
        debug: ["logLevel"],
        displays: ["mainDisplay"],
        input: ["kbLayouts", "kbVariants", "kbSwitch", "capsLock", "keyRepeatDelay", "keyRepeatRate", "mouseSpeed", "mouseAccel",
            "mouseNaturalScroll", "cursorTheme", "cursorSize", "pointerInApps", "touchpadScrollSpeed", "touchpadNaturalScroll", "touchpadTapToClick",
            "touchpadIgnoreWhileTyping"],
        sound: ["tickVolume", "notificationVolume", "clickVolume", "swishVolume", "welcomeVolume", "goodbyeVolume", "attentionVolume", "answeredVolume",
            "volumeSound", "notificationSound", "clickSound", "swishSound", "welcomeSound", "goodbyeSound", "soundEffectsVolume"],
        power: ["lidAction", "powerKeyAction", "profileOnBattery", "profileOnAC", "reopenAppsAfterRestart"],
        apps: ["defaultTerminal", "defaultBrowser", "defaultFileManager", "defaultEditor", "defaultCalculator"],
        startup: ["startupApps"],
        screenshots: ["screenshotAfter", "screenshotFolder", "screenshotName"],
        windows: ["windowMode", "focusFollowsMouse", "titleBarStyle", "titleButtons", "windowBorderSize", "windowGap", "soloWindowGap", "inactiveDim", "switcherPreviews", "switcherAppIcons",
                  "switcherMoveAnimation", "switcherPickAnimation"],
        workspaces: ["workspaceAnimation", "workspaceSwitchName", "wrapWorkspaces", "keepEmptyWorkspace", "workspaceShape", "overviewCardWidth", "overviewPreviews", "overviewAppIcons",
                     "overviewMoveAnimation", "overviewPickAnimation", "overviewGridSize"],
        spaces: ["spaceBarTint", "spaceBorders", "spaceBadges", "spaceSwitcherBadges"],
        hotcorners: ["hotCornerTopLeft", "hotCornerTopRight", "hotCornerBottomLeft", "hotCornerBottomRight", "hotCornerDelay"],
        notifications: ["notificationPosition", "notificationSeconds", "notificationMaxToasts", "notificationBlur", "notificationOpacity", "notificationHoverOpacity"],
        screensaver: ["screensaverMinutes", "screensaverStyle", "screensaverVideoQuality", "screensaverClock", "screensaverSlideSeconds", "screensaverLock"],
        shortcuts: ["keyset"],
        updates: ["updateCheck"],
        assistant: ["assistantBlur", "assistantOpacity", "assistantEnabled", "assistantRisksAccepted", "assistantAgent", "assistantModel", "assistantLocalModel", "assistantCommand", "assistantCommandBare", "assistantAgentsAccepted", "assistantKeepChat", "assistantAskChanges", "assistantSeeTitles", "assistantSeeNotifications", "assistantVoice"],
        lock: ["lockBeforeSleep", "lockScreenPowerMenu", "idleLockMinutes", "idleScreenOffMinutes", "idleSuspendMinutes",
            "idleRespectInhibitors"]
    })
    readonly property var currentKeys: pageKeys[section] || []
    // Settings on this page that differ from their defaults (re-read whenever settings change)
    property int changedHere: 0
    // (the test hooks for the pages' lists. rowsMade: how many rows each list has made and how
    // many times each page has looked, by name, so a test can tell a row that was kept from one
    // made again. pretendPolls: what Printers' and Network's looks find, in place of what
    // printers.py list and netinfo.sh say: { printers: "…", network: "…" })
    property var rowsMade: ({})
    function rowMade(list) { if (Config.testMode) rowsMade[list] = (rowsMade[list] || 0) + 1; }
    property var pretendPolls: ({})
    function pretendPoll(what, text) { const p = Object.assign({}, pretendPolls); if (text === "") delete p[what]; else p[what] = text; pretendPolls = p; }
    function countChanged() { changedHere = Config.changedCount(currentKeys); }
    onCurrentKeysChanged: countChanged()
    Connections { target: Config; function onSaved() { win.countChanged(); } }
    // A page whose settings aren't Slate's own (Webcam: the camera's) hooks its reset into the
    // title's Restore defaults: whether anything's changed, and what puts it back
    property bool pageResetChanged: false
    property var pageResetRun: null
    // Any other question, asked in Slate's confirmation window: { title, body, button, run,
    // cancel (optional), cancelLabel (optional: the other button's label, when it's a choice
    // rather than backing out), destructive (optional: a red button Enter doesn't press),
    // option (optional: { label, detail }, a switch in the question, off to start; run gets
    // whether it's on) }. Setting this asks it, and it's cleared again at once
    property var ask: null
    onAskChanged: {
        if (!ask) return;
        const q = ask; ask = null; askInConfirmer(q);
    }
    // A question { title, body, button, destructive?, code?, option?, run(optionOn), cancel? }
    function askInConfirmer(q) {
        confirmer.confirmWith({ title: q.title, body: q.body, button: q.button,
                                code: q.code || (q.destructive ? 0xEB41 : 0xEB13), danger: !!q.destructive, option: q.option || null,
                                cancelLabel: q.cancelLabel || "" },
                              v => { if (q.run) q.run(v); }, q.cancel || null);
    }
    // Settings → Security → Slate login screen. It's optional (nothing installs it unless you
    // ask), so installing says plainly what can go wrong and what keeping it working takes
    readonly property var loginScreenInstallQuestion: ({
        title: "Install Slate's login screen?",
        body: "This replaces your computer's login screen, which lives outside Slate, so it needs your password. "
            + "If it breaks, it can stop you logging in: Slate tests every copy before installing it and keeps a basic "
            + "fallback, and you can always press Ctrl+Alt+F3, log in as text and run "
            + "sudo /usr/local/libexec/slate/slate-greeter-install --revert. "
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
    property var assistantAgentsSeen: []      // (the agents Settings → Assistant found: for the tests)
    // Settings → Assistant → Let assistants use Slate. Switching on doesn't switch it on: it
    // shows the risks first, in plain words, and only "Switch on" does it, recording which
    // version of them was accepted (Config.assistantOn needs both). Best efforts, said as such
    readonly property string assistantDocs: "https://github.com/daylerees/slate/blob/master/docs/ASSISTANT.md#before-you-switch-it-on"
    readonly property string assistantRisks: (Config.assistantRisksChanged ? "Something's changed about the assistant since you switched it on, so here it is again.<br><br>" : "Before you do, here's what it means.<br><br>")
        + "<b>What leaves your computer.</b> What you type, and what Slate tells the assistant about your desktop "
        + "(your settings, your open windows and their titles), goes to the service behind the agent you choose, under your own account with them. "
        + "With Ollama, a model on this computer answers, and nothing leaves it.<br><br>"
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
                                button: "Switch on", code: 0xF014, danger: false }, () => assistantAccept());
    }
    // Assistant → Voice → Talk to Nova. On, it needs the speech model: Slate asks before
    // downloading it (its size, and where from), and only a yes turns it on
    function voiceSwitch(on) {
        if (!on) { Config.s.assistantVoice = false; return; }
        if (voice && voice.model) { Config.s.assistantVoice = true; return; }
        voiceDownload(() => { Config.s.assistantVoice = true; });
    }
    function voiceDownload(then) {
        if (!confirmer || !voice) return;
        confirmer.confirmWith({
            title: "Download the speech model?",
            body: "To turn what you say into text on this computer, Slate needs whisper's speech model: " + voice.sizeText
                + ", downloaded once from Hugging Face into ~/.local/share/slate/whisper. You can delete it here at any time.\n\n"
                + "What you say never leaves your computer: Slate only listens while you hold the key or the microphone, "
                + "and the recording is deleted as soon as it's written down.",
            long: true, button: "Download", code: 0xEAF0, danger: false
        }, () => { if (then) then(); voice.download(); });
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
            button: "Use it", code: 0xF014, danger: false
        }, () => { Config.s.assistantAgentsAccepted = accepted.concat([id]); Config.s.assistantAgent = id; });
    }
    // Read the risks again, while it's on: the same words, and the chance to think again
    function assistantReadRisks() {
        if (!confirmer) return;
        confirmer.confirmWith({ title: "What using the assistant means", body: assistantRisks.replace("Before you do, here's what it means.<br><br>", ""), long: true,
                                button: "Keep it on", cancelLabel: "Switch off", code: 0xF014, danger: false },
                              () => {}, () => { Config.s.assistantEnabled = false; });
    }
    // Restore defaults (the title button): asks first
    function askRestoreDefaults() {
        if (!confirmer) return;
        confirmer.confirmWith({
            title: "Restore " + pageTitle + " defaults?",
            body: changedHere + (changedHere === 1 ? " setting on this page goes" : " settings on this page go")
                + " back to how Slate starts out. Your other pages are left just as they are."
                + (resetRestarts ? " Slate restarts to apply them; your apps and windows stay open." : ""),
            button: "Restore defaults", code: 0xEB13, danger: false
        }, () => { restoreDefaults(); countChanged(); });
    }
    // A follow-up question (asking again, more seriously): asked a moment later, so it's clearly
    // a new one, with its own attention sound
    property var nextAsk: null
    function askAfter(q) { nextAsk = q; nextAskTimer.restart(); }
    Timer { id: nextAskTimer; interval: 260; onTriggered: { win.ask = win.nextAsk; win.nextAsk = null; } }
    // Restoring defaults that restarts Slate to apply them (Interface size, Log detail)
    readonly property bool resetRestarts: restartsFor(currentKeys)
    function restartsFor(keys) {
        return (keys.includes("uiScale") && Math.abs(Config.s.uiScale - 1) > 0.001)
            || (keys.includes("logLevel") && (Config.s.logLevel || "normal") !== "normal");
    }
    onSectionChanged: {
        if (section !== "general") avatarPicking = false;
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
        restorePage(section);
    }
    // ...or on any page by its id (the assistant's settings_restore_defaults), showing or not
    function restorePage(page) {
        Config.resetKeys(pageKeys[page] || []);
        if (page !== "appearance") return;
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
    // The page this one belongs to (Wallpaper, Icons and App Theming: Appearance), or ""
    readonly property string parentSection: (sections.find(x => x.id === section) || {}).parent || ""
    readonly property bool onMorePage: parentSection === "" && moreSections.some(x => x.id === section)

    Item {
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: { if (dropLayer.owner) dropLayer.owner = null; else win.visible = false; }

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
                            readonly property bool current: win.section === modelData.id || win.parentSection === modelData.id || (modelData.id === "overview" && win.onMorePage)
                            width: parent.width; height: 38; radius: Config.corner(9)
                            // The page you're on fades in; the muted hover is there at once (HoverFill)
                            color: current ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0)
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            HoverFill { hovered: navHover.hovered; gone: parent.current; radius: parent.radius }
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
            // Shades and scrollbar for when the pages don't all fit (a short screen)
            ScrollShade {
                z: 3
                anchors { top: parent.top; left: parent.left; right: parent.right }
                distance: sideScroll.contentY - sideScroll.originY
            }
            ScrollShade {
                z: 3
                atBottom: true
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                distance: sideScroll.originY + sideScroll.contentHeight - sideScroll.height - sideScroll.contentY
            }
            ThinScrollbar {
                z: 3
                flick: sideScroll
                color: win.text
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: 14; bottomMargin: 14; rightMargin: 2 }
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
                    height: 36; radius: Config.corner(10)
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
                        function onSearchFor(t) { if (pageSearch.visible) { pageFind.forceActiveFocus(); pageFind.text = t; } }
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
                    // Back: to the page this one belongs to (Wallpaper and Icons: Appearance), else to
                    // All Settings (which itself has nowhere to go back to)
                    IconButton {
                        id: backBtn
                        visible: win.section !== "overview"
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: 3 }
                        icon: 0xEA19
                        onClicked: win.section = win.parentSection || "overview"
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
                radius: Config.corner(12)
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
                            radius: Config.corner(9)
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
                radius: Config.corner(10)
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
                    sourceComponent: ({ overview: overviewPage, general: generalPage, appearance: appearancePage, bar: barPage, control: controlPage, dock: dockPage, launcher: launcherPage, spaces: spacesPage,
                        displays: displaysPage, input: inputPage, sound: soundPage, power: powerPage, shortcuts: shortcutsPage,
                        apps: appsPage, startup: startupPage, datetime: timePage, screenshots: shotsPage, windows: windowsPage, notifications: notificationsPage, bluetooth: bluetoothPage, printers: printersPage, about: aboutPage, wifi: wifiPage, hotcorners: hotCornersPage, debug: debugPage, webcam: webcamPage, lock: lockPage, screensaver: screensaverPage, updates: updatesPage, workspaces: workspacesPage, apptheming: appThemingPage, wallpaper: wallpaperPage, icons: iconsPage, assistant: assistantPage })[win.section]
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
            radius: Config.corner(12)
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
                height: 32; radius: Config.corner(8)
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
                    width: menuList.width - (menuList.contentHeight > menuList.height ? 8 : 0); height: dropLayer.rowH; radius: Config.corner(8)
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
                        textFormat: Text.PlainText        // never markup: an option can be a device's, an app's or a file's name
                        text: parent.modelData.label
                        color: parent.picked ? win.accentText : parent.current ? win.accent : win.text
                        // (an option can name a typeface to be written in: the font settings' do)
                        font.family: parent.modelData.font || win.font; font.pixelSize: 13; font.weight: Font.Medium
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
            // while there's more below (like Settings' pages), and the usual scrollbar
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
            ThinScrollbar {
                flick: menuList
                color: win.text
                anchors { top: menuList.top; bottom: menuList.bottom; right: parent.right; rightMargin: 2 }
            }
        }
    }


    Component { id: overviewPage; OverviewPage {} }
    Component { id: generalPage; GeneralPage {} }

    Component { id: barPage; BarPage {} }

    Component { id: dockPage; DockPage {} }

    Component { id: spacesPage; SpacesPage {} }

    Component { id: screensaverPage; ScreensaverPage {} }

    Component { id: controlPage; ControlPage {} }

    Component { id: launcherPage; LauncherPage {} }

    Component { id: displaysPage; DisplaysPage {} }

    Component { id: inputPage; InputPage {} }

    Component { id: soundPage; SoundPage {} }

    Component { id: powerPage; PowerPage {} }

    Component { id: shortcutsPage; ShortcutsPage {} }

    Component { id: appsPage; AppsPage {} }

    Component { id: startupPage; StartupPage {} }

    Component { id: timePage; DateTimePage {} }

    Component { id: shotsPage; ScreenshotsPage {} }

    Component { id: assistantPage; AssistantPage {} }

    Component { id: windowsPage; WindowsPage {} }

    Component { id: workspacesPage; WorkspacesPage {} }

    Component { id: notificationsPage; NotificationsPage {} }


    Component { id: appearancePage; AppearancePage {} }

    Component { id: wallpaperPage; WallpaperPage {} }

    Component { id: iconsPage; IconsPage {} }

    Component { id: appThemingPage; AppThemingPage {} }

    Component { id: wifiPage; WifiPage {} }

    Component { id: lockPage; LockPage {} }

    Component { id: hotCornersPage; HotCornersPage {} }

    Component { id: bluetoothPage; BluetoothPage {} }

    Component { id: printersPage; PrintersPage {} }

    Component { id: updatesPage; UpdatesPage {} }

    Component { id: webcamPage; WebcamPage {} }

    Component { id: debugPage; DebugPage {} }
    Component { id: aboutPage; AboutPage {} }
}
