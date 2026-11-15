//@ pragma AppId slate-settings
//@ pragma UseQApplication
// (AppId: the app id Slate's own windows get, so the Settings window has Slate's icon: see
// data/slate-settings.desktop and assets/icon/settings-*.png. UseQApplication: lets app tray
// menus, which are "platform menus", open when a tray icon is right-clicked.)
// Slate: a desktop shell for Hyprland (bar, dock, launcher, switchers, panels,
// notifications, settings). Run with:  slate
// Settings: settings.json here; saved state: ~/.local/state/slate; cache: ~/.cache/slate
//
// This file wires the other parts together (the dock is Dock.qml). The dock:
// - Icons magnify near the pointer with a smooth falloff, so neighbours rise in an
//   arc and the dock widens to make room.
// - App icons are "phone app" tiles drawn by scripts/appicon.py --tile
//   and cached in ~/.cache/slate/tiles/ (a folder per icon style, Config.tileDir).
// - Hides while the workspace has windows; push the pointer to the bottom edge to
//   bring it back.

import QtQuick
import Qt.labs.folderlistmodel
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "NotificationText.js" as NotificationText

ShellRoot {
    id: root
    // Logging in: every screen starts black and fades in with the welcome sound.
    // First, so its windows open before the wallpaper and bar
    Variants {
        model: Config.welcoming ? Quickshell.screens : []
        FadeIn { required property var modelData; screen: modelData }
    }
    // Slate's own title bar on the focused floating window (Settings → Windows → Title bars)
    // Each workspace's window mode (the menu bar's workspace indicator; Spaces saves and restores it)
    IpcHandler {
        target: "workspacemode"
        function set(id: int, mode: string): void { Config.setWorkspaceMode(id, mode); }
        function get(id: int): string { return Config.workspaceModes[String(id)] || ""; }
        // Change the default mode (as Settings → Windows does): tidy moves every workspace to it,
        // otherwise the ones in use keep the mode they have, as their own
        function setDefault(mode: string, tidy: bool): void { Config.setDefaultMode(mode, tidy); }
        // The workspaces a change of default to this mode would rearrange (with windows, in another)
        function notIn(mode: string): string { return Config.workspacesNotIn(mode).join(","); }
    }
    // Each workspace's own name (the pencil on the window mode panel; Spaces saves and restores it)
    IpcHandler {
        target: "workspacename"
        function set(id: int, name: string): void { Config.setWorkspaceName(id, name); }
        function get(id: int): string { return Config.workspaceName(id); }
        function label(id: int): string { return Config.workspaceLabel(id); }
    }
    IpcHandler {
        target: "titlebar"
        // Maximise or restore a window, leaving room for its bar (Super+D, binds.lua)
        function maximise(address: string): void { Config.titleBarMaximise(address); }
    }
    // (one look at Hyprland's windows for every screen's bar, and only while one floats)
    TitleBarWindows { id: titleBarWindows; bars: titleBars.instances; lock: lockScreen }
    Variants {
        id: titleBars
        model: Config.anyFloating && Config.slateTitleBars ? Quickshell.screens : []
        TitleBar { required property var modelData; screen: modelData; windows: titleBarWindows }
    }
    // Only one of the launcher, window switcher and workspace overview shows at a
    // time: opening one closes the others
    Launcher {
        id: appLauncher
        notifs: root.dockNotifs              // (not `notifs: notifs`: that reads the launcher's own property)
        onShownChanged: if (shown) { Config.closeMenus(); winSwitcher.cancel(); wallpaperLayer.switcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    // Nova, the assistant's window (Super+K): a real window, as Settings is, so the launcher and
    // the other overlays leave it open; opening it closes them, so it has the keyboard
    Assistant {
        id: nova
        voice: novaVoice
        onOpened: { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wallpaperLayer.switcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    // Clipboard history (Super+V) and emoji picker (Super+.)
    Picker {
        id: picker
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wallpaperLayer.switcher.cancel(); wsOverview.close(); popouts.close(); }
    }
    // Records clipboard history for the picker (scripts/clipstore.py); exits with Slate
    Process {
        id: clipWatch
        // Settings → General → Clipboard history: off stops recording (what's kept stays until cleared)
        running: Config.s.clipboardHistory
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", "python3", Quickshell.shellPath("scripts/clipstore.py"), "store"]
        onRunningChanged: if (!running && Config.s.clipboardHistory) clipRestart.restart()
    }
    Timer { id: clipRestart; interval: 2000; onTriggered: if (Config.s.clipboardHistory) clipWatch.running = true }
    // A bar on every screen. The main display's (topBar, Settings → Displays) is the main one: other pieces take
    // its look and sizes, and it answers `slate ipc call bar …` (passing it to the focused
    // screen's bar). The panels open on whichever screen's bar opened them.
    Bar { id: topBar; screen: Config.primaryScreen; popouts: popouts; notifs: notifs }
    Variants {
        model: Quickshell.screens.filter(s => s !== Config.primaryScreen)
        // (topBar's: inside the Bar, plain `popouts` and `notifs` are its own empty properties,
        // so the bars on other screens had no panels and no notifications)
        Bar { required property var modelData; screen: modelData; primary: false; popouts: topBar.popouts; notifs: topBar.notifs }
    }
    Popouts { id: popouts; bar: topBar; notifs: notifs; powerConfirm: powerConfirm; dock: win }
    PowerConfirm { id: powerConfirm }
    // slate restart / stop (bin/slate): reload in place rather than restarting the process,
    // since Quickshell can crash while shutting down and then relaunch itself
    IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(true); }
    }

    // ---- For the test suite (tests/, with SLATE_TEST=1) ---------------------------------
    // $XDG_RUNTIME_DIR/slate-ready once Slate has loaded: tests wait for it rather than guess,
    // and so does `slate restart`, to take its "Reloading Slate" cover down
    Component.onCompleted: {
        Quickshell.execDetached(["setsid", "-f", Quickshell.shellPath("scripts/tray-watcher.py")]);     // the tray's register (below)
        Qt.callLater(() => Qt.callLater(() => readyMark.running = true));
    }
    Process { id: readyMark; command: ["sh", "-c", ': > "$0/slate-ready"', Config.runtimeDir] }
    // What's on screen, as JSON, for tests to check rather than reading pixels:
    //   slate ipc call test state
    IpcHandler {
        target: "test"
        enabled: Config.testMode
        // Hyprbars (HyprbarsWatch.qml), as Settings → Windows asks for it: check, choose, rebuild,
        // reload, remove. And answering the question that's showing in the confirmation window
        // Arranging the menu bar without a pointer: what a drag, a click on the bar or a button
        // on the panel comes to (Config's bar… functions)
        function arrange(what: string, a: string, b: string, c: string): void {
            const n = v => parseInt(v);
            if (what === "start") Config.barArranging = true;
            else if (what === "done") Config.barArranging = false;
            else if (what === "reset") Config.barReset();
            // (an arrangement as saved, JSON: one from an older Slate, say)
            else if (what === "load") Config.s.barLayout = JSON.parse(a);
            else if (what === "moveItem") Config.barMoveItem(a, n(b), n(c));
            else if (what === "moveEntry") Config.barMoveEntry(n(a), n(b));
            else if (what === "moveTuck") Config.barMoveTuck(n(a), n(b), n(c));
            else if (what === "addSpace") Config.barAddSpace(n(a));
            else if (what === "addBox") Config.barAddBox(n(a));
            else if (what === "remove") Config.barRemoveEntry(n(a));
            else if (what === "split") Config.barSplit(n(a));
            else if (what === "tuck") Config.barSetTuck(n(a), b === "" ? undefined : b === "true", c === "" ? undefined : c);
            else if (what === "tuckFrom") Config.barSetTuck(n(a), undefined, undefined, b);
            else if (what === "shown") Config.barSetShown(a, b === "true");
            else if (what === "pick") Config.barPick(n(a), b);
            // (a chip from the pool held over the bar at a place on the desktop: the gap opens)
            else if (what === "hover") {
                const at = c.split(",");
                Config.barFloat = { kind: a, icons: [{ code: (Config.barItem(b) || { icon: 0xEAD5 }).icon, item: b, text: topBar.exampleOf(b) }] };
                Config.barCarry = { kind: a, id: b };
                Config.barCarryAt = Qt.point(Number(at[0]), Number(at[1]));
                Config.barFloatAt = Config.barCarryAt;
            }
            else if (what === "drag") { const p = c.split(","); topBar.testDrag(n(a), n(b), Number(p[0]), Number(p[1])); }
            else if (what === "squeeze") topBar.squeeze = Number(a);
            // (a container's collapse button clicked: open, or closed again)
            else if (what === "open") topBar.testOpenBox(n(a), b !== "false");
            else if (what === "collapse") Config.barSetCollapse(n(a), b);
            else if (what === "overflow") Config.barSetOverflow(a === "" ? [] : a.split(","), b === "" ? [] : b.split(","));
            else if (what === "stay") Config.barSetStay(a, b === "true");
            else if (what === "preview") Config.barPreview = Number(a);
            // (menu item priority: its window, and a row moved to a place in its list; and the
            // "Try it shorter" dropdown: its menu opened or closed, a length chosen from it)
            else if (what === "length") { if (!barEditor.item) return; if (a === "pick") barEditor.item.lengthPick(Number(b)); else barEditor.item.lengthMenu(a === "open"); }
            else if (what === "priority") { if (a === "move") { if (barEditor.item) barEditor.item.priorityMove(b, n(c)); } else if (a === "scroll") { if (barEditor.item) barEditor.item.priorityScroll(Number(b)); } else Config.barPrioritising = a === "open"; }
            else if (what === "scroll") topBar.scrollBy(Number(a));
            else if (what === "more") topBar.moreClick({ id: a, tray: null }, b === "right");
            else if (what === "carry") { Config.barCarry = { kind: a, id: b }; Config.barCarryTarget = JSON.parse(c); Config.barDrop(); }
        }
        // Hot corners: is this point (Hyprland's pixels, as `hyprctl cursorpos` says) in that
        // corner ("topLeft", "bottomRight"…) of the main display? (what unlocking asks)
        function hotCorner(corner: string, x: real, y: real): bool { return hotCorners.pointIn(corner, x, y); }
        // Slate's title bar that's showing: where it's drawn (Slate's units on its screen), as
        // JSON, after a pretend pointer on it if asked ("press", "move", "release"…: TitleBar.qml's
        // testPointer; "" only looks)
        function titleBar(what: string, x: real, y: real): string {
            const t = titleBars.instances.find(t => t.shown);
            if (t && what !== "") t.testPointer(what, x, y);
            return JSON.stringify(t ? t.testState() : null);
        }
        // Arranging the bar: a chip in the pool pressed with the pointer at x, y (Hyprland's
        // pixels, as `hyprctl cursorpos` says): where that is on the desktop, as the bar counts it
        function barPointer(x: real, y: real): string {
            const e = barEditor.item;
            if (!e) return JSON.stringify({ x: 0, y: 0 });       // (only means something while the bar's being arranged)
            e.pointer = Qt.point(0, 0);
            e.locate(x, y);
            return JSON.stringify({ x: e.origin.x, y: e.origin.y });
        }
        // Weather for the clock panel and control centre, as if it had been fetched for a place
        // (tests have no network): mild rain now, then four days
        // The control centre's quick switches: their order (ids, comma-separated; "" for none
        // chosen), a press on one by id (the panel open), and which this computer can't use
        function controlSwitches(ids: string): void { Config.s.controlSwitches = ids === "" ? [] : ids.split(","); }
        function pressSwitch(id: string): void { popouts.pressSwitchAsked(id); }
        // The Wi-Fi panel with pretend networks, {"Home": 0.9, …} (their signals changed when
        // they're there already; "": none again), and one's password field opened, as a click
        // on its row does
        function wifi(nets: string): void { popouts.pretendWifi(nets); }
        function wifiPassword(name: string): void { popouts.askForPassword(name); }
        // Settings' page scrolled by a mouse wheel turned this many notches quickly (+ = down), as
        // its SmoothWheel takes them
        function settingsWheel(notches: int): void {
            const w = root.settingsWindow();
            for (let i = 0; i < Math.abs(notches); i++) w.scrollWheel.wheelBy(notches > 0 ? -120 : 120);
        }
        // The notifications panel's list scrolled to a place (px from its top)
        function listScroll(y: real): void { popouts.scrollList(y); }
        // ...and one of them closed, as its card's close button does (0: the newest)
        function removeNotification(i: int): void { const h = notifs.history[i]; if (h) notifs.remove(h.key); }
        // ...or its main action run, as a click on its card does (0: the newest)
        function activateNotification(i: int): void { const h = notifs.history[i]; if (h) notifs.activate(h.key); }
        // Settings → Printers and Network: what their next looks find, as printers.py list and
        // netinfo.sh would print it ("": the real thing again), and a look now
        function settingsPoll(what: string, text: string): void { if (settingsLoader.item) settingsLoader.item.pretendPoll(what, text); }
        function newSpace(): void { popouts.newSpaceAsked(); }
        // Less room for the dock's things than its edge has (px; 0: the whole edge), to fill it
        // with a few windows rather than dozens
        function dockRoom(px: real): void { win.setTestRoom(px); }
        // Settings → Displays → Brightness's slider without a pointer: moved to a percentage, and
        // let go (or not: still dragging)
        function brightnessSlide(display: string, percent: int, letGo: bool): void {
            DisplayBrightness.set(display, percent);
            if (letGo) DisplayBrightness.settle();
        }
        function switchMissing(ids: string): void { Config.controlSwitchMissing = ids === "" ? [] : ids.split(","); }
        // Hardware the tests' computer hasn't got, pretended there or not: what = "wifi" or "audio"
        function hardware(what: string, on: bool): void {
            if (what === "wifi") Config.pretendWifi = on; else if (what === "audio") Config.pretendAudio = on;
        }
        function weather(on: bool): void {
            Config.s.locationName = on ? "Bristol" : "";
            popouts.weather = on ? { temperature_2m: 14.2, apparent_temperature: 12.8, weather_code: 61 } : null;
            popouts.forecast = on ? { time: ["2026-01-05", "2026-01-06", "2026-01-07", "2026-01-08", "2026-01-09"],
                                      weather_code: [61, 3, 0, 71, 2],
                                      temperature_2m_max: [15, 12, 9, 3, 7], temperature_2m_min: [8, 6, 1, -2, 2] } : null;
        }
        // A reply from the weather service, as if a fetch had just brought it: the panels keep
        // what they had unless it's a forecast. Returns whether it was taken.
        function weatherReply(text: string): bool { return popouts.takeWeather(text); }
        // The bar's right-click menu: "open", or an item to choose ("Position/Bottom": one in a
        // submenu); menuKey sends a key to it, as pressing it there does (Up, Down, Enter, Space,
        // Left, Right, Home, End, Escape)
        function barMenu(what: string): void {
            if (what === "open") { topBar.openMenuFrom(600, 20); return; }   // (as a right-click there would)
            const path = what.split("/");
            let row = topBar.menu.items.find(i => i.label === path[0]);
            if (row && path.length > 1 && row.submenu) row = row.submenu.find(i => i.label === path[1]);
            topBar.menu.close();
            if (row && row.run) row.run();
        }
        // ...opened from any point, towards any side (top, bottom, left, right), as the desktop's
        // and the bar's open it; where its card landed is state's barMenu.at
        function barMenuAt(x: real, y: real, edge: string): void { topBar.menu.openFrom(x, y, edge, 14); }
        // The camera in use, as camera-watch.py would say (the test machine has none)
        function camera(on: bool, apps: string): void {
            Config.cameraApps = apps === "" ? [] : apps.split(",");
            Config.cameraOn = on;
        }
        // The dock's own menu (its empty space): "open", or an item to choose, as barMenu
        function dockMenu(what: string): void { win.testMenu(what); }
        // A pretend pointer on the menu bar at x, y (in the bar window's own coordinates; the bar's
        // band is state's bar.band): "hover" there, "leave", or "click" there. What it's over, as
        // JSON: {thing, dot, lit}
        function barPoint(x: real, y: real, what: string): string { return JSON.stringify(topBar.testPoint(x, y, what)); }
        // ...at the middle of one of the bar's things, by its name in the arrangement ("": away)
        function barHover(name: string): string {
            const t = topBar.lineState()[name];
            if (!t || !t.visible) return JSON.stringify(topBar.testPoint(-1, -1, "leave"));
            return JSON.stringify(topBar.testPoint(t.x + t.w / 2, t.y + t.h / 2, "hover"));
        }
        // What the label off the bar would call a tray icon with this id, title and tooltip title
        // (Config.trayName: the tidying of a raw id)
        function trayName(id: string, title: string, tooltip: string): string { return Config.trayName({ id: id, title: title, tooltipTitle: tooltip }); }
        // What a notification's card makes of a message before drawing it, and whether it would
        // open a link in one (NotificationText.js)
        function safeBody(body: string): string { return NotificationText.safeBody(body); }
        function opensLink(link: string): bool { return NotificationText.openable(link); }
        // The pointer on the bar menu's item `index` (its row's top at y), as hovering it does
        function menuPoint(index: int, y: real): void { topBar.menu.want(index, y); }
        function menuKey(key: string): void {
            const k = ({ Up: Qt.Key_Up, Down: Qt.Key_Down, Enter: Qt.Key_Return, Space: Qt.Key_Space, Left: Qt.Key_Left,
                         Right: Qt.Key_Right, Home: Qt.Key_Home, End: Qt.Key_End, Escape: Qt.Key_Escape })[key];
            if (k !== undefined) topBar.menu.key({ key: k, accepted: false });
        }
        function hyprbars(what: string): void {
            if (what === "choose") Config.hyprbarsChoose();
            else if (what === "rebuild") Config.hyprbarsRebuild();
            else if (what === "reload") Config.hyprbarsReload();
            else if (what === "remove") Config.hyprbarsRemove();
            else if (what === "unreleased") Config.hyprbarsBuildUnreleased();    // the yes to "build the newest unreleased version?"
            else if (what === "unset") Config.titleBarStyleUnset = true;      // as if the settings were from before the choice
            else Config.hyprbarsCheck();
        }
        // A piece of text as Slate writes it into Lua for Hyprland (Config.luaString)
        function luaString(text: string): string { return Config.luaString(text); }
        // As if this computer had no systemd or elogind (what bin/slate-init info would say), or
        // had them again ("")
        function system(logind: string): void {
            const have = logind !== "none";
            Config.system = { init: have ? "systemd" : "openrc", logind: logind || "systemd", suspend: have ? "yes" : "no",
                              power: have ? "yes" : "no", inhibit: have ? "yes" : "no", timedate: have ? "yes" : "no" };
        }
        function answer(yes: bool): void { if (yes) powerConfirm.confirm(); else powerConfirm.cancel(); }
        // Type into the question's text field (naming a workspace), and what's in it now
        function type(text: string): void { powerConfirm.inputText = text; }
        function typed(): string { return powerConfirm.inputText; }
        // As the pencil on the window mode panel's title does, for the workspace you're on
        function renameWorkspace(): void { popouts.renameWorkspace(Config.focusedWorkspaceId); }
        // Magnify the dock as if the pointer were over slot i (-1: as if it had left): the
        // test session has no pointer device to hover with
        // Drag an app on the dock as the pointer would: picked up (if it isn't already), held
        // over slot i (as the slots are now), `up` pixels up from the dock's middle; then let go
        function dockDrag(key: string, i: int, up: real): void { win.testDrag(key, i, up); }
        // The login fade's cover (FadeIn.qml), which tests never see otherwise: shown and held,
        // faded away as at login, or taken away at once
        function fadeIn(): void { Config.welcomeFading = false; Config.welcoming = true; }
        function fadeInEnd(): void { Config.welcomeFading = true; }
        function fadeInClose(): void { Config.welcoming = false; Config.welcomeFading = false; }
        // Settings asking something (as its Reset does, with a switch): it asks in Slate's
        // confirmation window (power: custom)
        function settingsAsk(): void {
            const w = settingsLoader.item;
            if (w) w.ask = { title: "Test question?", body: "From the tests", button: "Yes",
                             option: { label: "Also this", detail: "A switch" }, run: v => {}, cancel: () => {} };
        }
        // The page title's Restore defaults, as clicking it does: it asks in Slate's confirmation
        // window first (answered with answer())
        function settingsRestoreDefaults(): void {
            const w = settingsLoader.item;
            if (w) w.askRestoreDefaults();
        }
        // What Settings' search and the launcher find for some words (SettingsIndex.search), best
        // first: [{ label, page, row }], row false for a heading or a whole page. "" until
        // Settings' own rows have been read
        function settingsSearch(text: string): string {
            if (SettingsIndex.rows.length === 0) return "";
            return JSON.stringify(SettingsIndex.search(text, 8).map(e => ({ label: e.label, page: e.page, row: e.row })));
        }
        // A greyed-out setting's "Needs …" line, as clicking it does: off to the setting it needs
        function settingsFollowNeeds(label: string): void {
            const w = settingsLoader.item;
            if (w) w.followNeeds(label);
        }
        // Settings → Displays: the chosen display turned (0 to 3, as Rotation's choices), as
        // picking it does: applied straight away, and waiting to be kept
        function settingsRotateDisplay(transform: int): void {
            const w = settingsLoader.item;
            if (w) w.displayChange("transform", transform);
        }
        // Settings → Assistant's switch and its "Read the risks again", as clicking them does
        function assistant(what: string): void {
            const w = settingsLoader.item;
            if (!w) return;
            if (what === "risks") w.assistantReadRisks();
            else w.assistantSwitch(what === "on");
        }
        // Settings → Assistant → Voice's switch, as clicking it does (on asks to download the model first)
        function voiceSwitch(on: bool): void {
            const w = settingsLoader.item;
            if (w) w.voiceSwitch(on);
        }
        // Look again for whisper.cpp and the speech model (VoiceModel.qml), as Slate does when it starts
        function voiceCheck(): void { voiceModel.check(); }
        // As saying yes to an agent that keeps its own tools (Settings → Assistant) leaves it
        function assistantAccepted(id: string): void { Config.s.assistantAgentsAccepted = id === "" ? [] : [id]; }
        // The prompt window as a run would leave it: {asked, answer, working, actions, error}
        // How quick an answer counts as straight back (no sound), in ms (Nova's quickAnswer)
        function novaQuickAnswer(ms: int): void { nova.quickAnswer = ms; }
        function nova(json: string): void {
            const st = JSON.parse(json);
            // (history: earlier exchanges, shown above this one)
            // (at / doneAt: when asked and answered, ms; left out, no time is shown)
            // (blocks: the answer as the runner reads it, scripts/safe_markdown.py; left out, it's plain text)
            const turn = h => ({ asked: h.asked || "", answer: h.answer || "", blocks: nova.cleanBlocks(h.blocks), actions: (h.actions || []).map(a => nova.keptAction(a)), error: h.error || null, at: h.at || 0, doneAt: h.doneAt || 0 });
            nova.turns = (st.history || []).map(turn).concat(st.asked ? [turn(st)] : []);
            nova.working = !!st.working;
            if (st.session !== undefined) nova.session = st.session;      // (the agent's thread, as a past answer left it)
            if (st.agents) { nova.agents = st.agents; nova.looked = true; }
        }
        // Forget the sounds noted so far (state().sounds: what would have played, Config.testSounds)
        function sounds(): void { Config.testSounds = []; }
        // A code box's Copy in the latest answer, as clicking it does (block: its place among the blocks)
        // One line from the agent's runner, as it arrives ({"type": "text" | "blocks", …}): to stream an answer
        function novaStream(json: string): void { nova.handle(JSON.parse(json)); }
        function novaCopyCode(block: int): void { nova.copyCode(nova.turns.length - 1, block); }
        // Undo on a row of what the latest answer did, as clicking it does (action: its place in the list)
        function novaUndo(action: int): void { nova.undo(nova.turns.length - 1, action); }
        // Nova's window back to the size it comes at (Hyprland resizes it; this forgets the size kept)
        function novaSizeReset(): void { nova.sizeAsItComes(); }
        // Scroll the launcher's list steadily from where it is to the bottom, over ms
        function launcherScroll(ms: int): void { appLauncher.testScroll(ms); }
        function dockDrop(): void { win.testDrop(); }
        function dockDividerDrag(px: real): void { win.testDividerDrag(px); }
        function dockDividerDrop(): void { win.testDividerDrop(); }
        function dockDividerHover(on: bool): void { win.testDividerHover(on); }
        // Drag an app out of More's grid (open: dock more) as the pointer would, held over slot i
        // of the dock (as the slots are now; -1: off its start), `up` pixels up from its middle:
        // handed to the grid's own carrying (win.carryFromMore) as a place on the screen (the
        // menu's window covers it), as the grid's tile does. Then let go, as releasing the tile does
        function dockMoreDrag(key: string, i: int, up: real): void { win.testDragMore(key, i, up); }
        function dockMoreDrop(): void { win.testDropMore(); }
        // Scroll More's or Downloads' grid (open) to y, as far as it goes
        function dockGridScroll(y: real): void { win.testScrollGrid(y); }
        function dockHover(i: int): void { win.testHoverSlot(i); }
        function state(): string {
            const settings = settingsLoader.item;
            const opt = v => v === undefined || v === null ? null : v;
            return JSON.stringify({
                screens: Quickshell.screens.map(s => ({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height })),
                // With more than one screen: the focused one and the main display (Settings → Displays),
                // each screen's bar, and where the panels and the dock are
                focusedScreen: Config.focusedScreen ? Config.focusedScreen.name : "",
                mainScreen: Config.primaryScreen ? Config.primaryScreen.name : "",
                bars: Config.bars.map(b => ({ screen: b.screen ? b.screen.name : "", primary: b.primary, dimmed: b.dimmed,
                                              popoutHere: b.popoutHere, width: Math.round(b.width), height: Math.round(b.height),
                                              dots: b.dotsState, bell: b.bellText })),
                popout: popouts.current,
                popoutScreen: popouts.screen ? popouts.screen.name : "", popoutAnchor: Math.round(popouts.anchorX),
                popoutBox: popouts.panelBox,
                settings: { built: !!settings, open: !!settings && settings.visible, section: settings ? settings.section : "",
                            changed: settings ? settings.changedHere : 0,
                            scroll: settings ? settings.scrolledTo : 0, viewHeight: settings ? Math.round(settings.scrollView.height) : 0,
                            thumbsLoading: settings ? settings.thumbsLoading + (settings.wallsListing ? 1 : 0) : 0,
                            checking: settings ? settings.checking : 0,
                            // Settings greyed out for another one, with what each says it needs
                            // (SettingRow's needs), and the setting last gone to (goTo)
                            waiting: settings && settings.visible ? settings.waitingRows().map(r => ({ label: r.label, needs: r.needs })) : [],
                            // (a heading it went to has no label: its text)
                            found: settings && settings.foundItem ? String(settings.foundItem.label || settings.foundItem.text || "") : "",
                            // (the agents Settings → Assistant offers, once it's looked)
                            agents: settings ? settings.assistantAgentsSeen : [] },
                launcher: { open: appLauncher.shown, visible: appLauncher.visible, screen: appLauncher.screen ? appLauncher.screen.name : "", query: appLauncher.query, mode: appLauncher.mode, current: appLauncher.currentIndex,
                            results: (appLauncher.results || []).slice(0, 30).map(r => opt(r.name) || opt(r.title) || opt(r.id) || ""),
                            // How it opened and scrolled (launcherScroll): frame times, the time spent moving
                            // the list, the app rows seen, those whose tile was there when they were, and
                            // rows drawn out of place
                            frames: appLauncher.testFrames, work: appLauncher.testWork, scrolled: appLauncher.testScrolled(),
                            openMs: appLauncher.testOpenMs, scrolling: appLauncher.testScrolling,
                            // What it has done so far: its rows put in step with the results, and its
                            // list of recent files read (neither while it's closed)
                            syncs: appLauncher.testSyncs, recentReads: appLauncher.testRecentReads,
                            apps: (appLauncher.results || []).filter(r => !r.kind && !r.calc && !r.setting && !r.action).length,
                            tileVersion: Config.tileVersion },
                // App icons: still being drawn or their colours noted (busy), and how many colours are known
                icons: { busy: Config.iconsBusy, colours: Object.keys(Config.iconColours).length },
                picker: { open: picker.shown, mode: picker.mode },
                osd: { shown: osdPop.shown, mode: osdPop.mode, label: osdPop.label },
                weather: { now: popouts.weather ? opt(popouts.weather.temperature_2m) : null, days: popouts.forecast ? popouts.forecast.time.length : 0 },
                control: { switches: Config.controlSwitches, caffeine: Config.caffeine, missing: Config.controlSwitchMissing,
                           rects: Config.controlSwitchRects(Config.controlSwitches.length, 200, 300).map(q => [q.x, q.y, q.width, q.height]) },
                barMenu: { open: topBar.menu.visible, hot: topBar.menu.hot, sub: topBar.menu.subIndex,
                           at: [topBar.menu.cardAt.x, topBar.menu.cardAt.y], pixelRatio: topBar.menu.screen ? topBar.menu.screen.devicePixelRatio : 1,
                           inSub: topBar.menu.inSub, subHot: topBar.menu.subHot, subRowY: topBar.menu.subRowY,
                           items: topBar.menu.items.map(i => i.separator ? "-" : i.label),
                           edge: topBar.menu.edge, atY: topBar.menu.atY, gap: topBar.menu.gap, barHeight: topBar.barHeight },
                switcher: { open: winSwitcher.shown, windows: winSwitcher.windows.length, previews: winSwitcher.previewsReady(),
                            fade: Math.round(winSwitcher.fade * 100) / 100, animate: winSwitcher.animate },
                // The wallpaper switcher: the wallpapers it shows, the one chosen, the one on screen
                // and the one saved; the updates held back while it's open, and whether App theming
                // has been given the theme in use
                wallpaperSwitcher: { open: wallpaperLayer.switcher.shown, switching: Config.wallpaperSwitching,
                                     fade: Math.round(wallpaperLayer.switcher.fade * 100) / 100,
                                     listing: wallpaperLayer.switcher.listing, walls: wallpaperLayer.switcher.walls,
                                     index: wallpaperLayer.switcher.index, selected: wallpaperLayer.switcher.selected,
                                     cover: wallpaperLayer.switcher.coverShowing, ahead: wallpaperLayer.switcher.ahead,
                                     colours: Object.keys(Config.wallpaperColourMemo).length, standing: wallpaperLayer.switcher.standing, thumbsDone: wallpaperLayer.switcher.thumbsDone, desktop: wallpaperLayer.desktopShowing, spinning: wallpaperLayer.switcher.spinning,
                                     screen: wallpaperLayer.switcher.screenOn ? wallpaperLayer.switcher.screenOn.name : "",
                                     shown: Config.wallpaper, saved: Config.s.wallpaper, accent: "" + Config.accent,
                                     held: updateHold.heldUpdates.length, themeApplied: appTheming.themeApplied === appTheming.themeJson,
                                     input: { bar: topBar.mask === topBar.barInput, dock: win.testInputOwn() } },
                // Every window Hyprland has, with where it is (address: Hyprland's, without the 0x)
                windows: Hyprland.toplevels.values.map(t => ({ title: t.title || "", workspace: t.workspace ? t.workspace.id : -1,
                                                              address: (t.address || "").replace(/^0x/, "") })),
                overview: { open: wsOverview.shown, screen: wsOverview.screen ? wsOverview.screen.name : "", selected: wsOverview.selected, grid: wsOverview.isGrid,
                            previews: wsOverview.previewsReady(),
                            fade: Math.round(wsOverview.fade * 100) / 100, animate: wsOverview.animate, strip: Math.round(wsOverview.stripAt() * 10000) / 10000,
                            // (the workspaces Slate knows of now: the overview shows these as it opens)
                            known: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id).sort((a, b) => a - b),
                            workspaces: wsOverview.spaces.map(w => w.id), cards: wsOverview.spaces.length + Object.keys(wsOverview.contents).length + wsOverview.shotAddrs.length,
                            zooming: wsOverview.zooming, leaving: wsOverview.leaving, focused: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1,
                            columns: wsOverview.isGrid ? Math.max(1, Math.min(wsOverview.gridSize, wsOverview.spaces.length)) : 0 },
                lock: { locked: lockScreen.locked, previewing: lockScreen.previewing, busy: lockScreen.busy, message: lockScreen.message, asking: lockScreen.asking, messageIsError: lockScreen.messageIsError,
                        // (what it read from faillock.conf, and what it made of the wrong passwords so far)
                        deny: lockScreen.failDeny, interval: lockScreen.failInterval, unlockTime: lockScreen.unlockTime, lockedOut: lockScreen.lockedOut,
                        failuresShown: lockScreen.failuresShown },
                screensaver: { open: screensaver.shown },
                power: { open: powerConfirm.shown, action: powerConfirm.action, option: powerConfirm.hasOption },
                polkit: { open: polkitAgent.shown },
                welcome: { built: welcome.built, open: welcome.shown, page: welcome.page, pages: welcome.pages, inApps: welcome.inApps },
                fadeIn: { open: Config.welcoming, fading: Config.welcomeFading },
                notifications: { history: notifs.history.length, unread: notifs.unread, dnd: notifs.dnd, toasts: notifs.toastsShowing,
                                 latest: notifs.history.length > 0 ? notifs.history[0].summary : "", toast: notifs.toastLook() },
                dock: win.testState(),
                tray: SystemTray.items.values.map(i => i.id),
                // The lists that keep their rows: rows made in each so far, the tray's icons made and
                // measured, and the open bar panel's list (Popouts.listState)
                lists: { tray: topBar.trayTest, panel: popouts.listState(), settings: settings ? settings.rowsMade : {} },
                gameMode: Config.gameMode,
                titleBar: Config.titleBarOn, titleBarAway: Config.titleBarAway,
                titleBarLooks: Config.titleBarLooks, titleBarSeen: Config.titleBarSeen,
                titleBars: Config.slateTitleBars ? "slate" : "hyprbars", titleBarStyle: Config.s.titleBarStyle,
                hyprbars: Config.hyprbarsState, hyprbarsFallback: Config.hyprbarsFallback,
                system: Config.system,
                workspaceNames: Config.workspaceNames,
                // (the screens where the note saying the secret workspace is empty shows)
                secretEmpty: Quickshell.screens.filter(s => Config.secretEmpty(s.name)).map(s => s.name),
                // The sounds that would have played, oldest first (the tests' Slate plays none)
                sounds: Config.testSounds,
                asking: powerConfirm.shown && powerConfirm.custom ? powerConfirm.custom.title : "",
                askingBody: powerConfirm.shown && powerConfirm.custom ? powerConfirm.custom.body : "",
                // Talking to Nova: listening or not, why it didn't, and what's there for it
                novaVoice: { phase: novaVoice.phase, note: novaVoice.note, on: novaVoice.on, mic: nova.micShown,
                             whisper: voiceModel.whisper !== "", model: voiceModel.model, ready: voiceModel.ready,
                             downloading: voiceModel.downloading, progress: voiceModel.progress, error: voiceModel.error, checks: voiceModel.checks },
                // Background work that should be idle when nothing needs it: Night light's schedule
                // timer, Private Mode's portal watch, and the theme check for updated apps
                // Automatic brightness (AutoBrightness.qml): what the computer has, and what it's doing
                autoBrightness: AutoBrightness.testState(),
                // Each display's brightness (DisplayBrightness.qml): what Slate found it can set, and how bright
                displayBrightness: DisplayBrightness.testState(),
                idle: { nightTimer: nightLight.timerRunning, captureWatch: privateMode.watching, themeStaleWatch: appTheming.staleWatching },
                assistant: { open: nova.shown, working: nova.working, stopShown: nova.stopShown, keysSeen: nova.keysSeen, turns: nova.turns.length, asked: nova.asked, answer: nova.answer, actions: nova.actions,
                             error: nova.error ? nova.error.kind : "", errorText: nova.error ? nova.error.message : "", agent: nova.agent ? nova.agent.id : "", session: nova.session,
                             // (the answer's blocks, the markup each of its words items is given, and what was just copied)
                             blocks: nova.cur ? nova.cur.blocks || [] : [], blocksMade: nova.blocksMade, rich: nova.richNow(), copied: nova.copied,
                             // (its window, in Slate's units: whether it's been built, Hyprland has it and it
                             // has the keyboard, its size, the size it opened at and kept, and the conversation's height.
                             // Where it is comes from Hyprland: hyprctl clients)
                             window: { built: !!nova.win, mapped: !!nova.top, focused: nova.focused, w: nova.win ? nova.win.width : 0, h: nova.win ? nova.win.height : 0,
                                       openW: nova.openW, openH: nova.openH, wantW: nova.wantW, wantH: nova.wantH, minW: nova.minW, minH: nova.minH, talk: nova.talkHeight },
                             // (whether the lists of your windows have it, as each works it out: the
                             // switcher's, the overview's while it's open, and the bar's title)
                             listed: nova.top ? { switcher: winSwitcher.currentWindows().includes(nova.top),
                                                  overview: Object.values(wsOverview.contents || {}).some(l => l.includes(nova.top.address)),
                                                  title: !!topBar.shownTop && Config.isNova(topBar.shownTop) } : null,
                             // (whether each row of what it did offers Undo just now)
                             undo: nova.actions.map(a => nova.undoable(a)),
                             button: Config.s.barShowAssistant && Config.assistantOn,
                             enabled: Config.assistantOn, risksChanged: Config.assistantRisksChanged, waiting: Object.keys(assistantGate.answers).length },
                // Slate's settings reaching Hyprland (Config.testHypr)
                hypr: Config.testHypr(),
                // Live previews held as windows closed, and stopped as their own did (PreviewHold.qml)
                previews: { holds: PreviewHold.testHolds, stopped: PreviewHold.testStopped, held: PreviewHold.held },
                // The menu bar's arrangement, and arranging it (BarEditor.qml)
                bar: { arranging: Config.barArranging, layout: Config.barLayout, isDefault: Config.barIsDefault,
                       picked: Config.barSelected, pickedItem: Config.barSelectedItem, editor: !!barEditor.item && barEditor.item.shown, editorBuilt: !!barEditor.item, edge: popouts.edge,
                       line: topBar.lineState(), span: topBar.lineSpan, gives: topBar.gives, opened: topBar.openBoxes(), clock: topBar.clockText, titleWidth: Math.round(topBar.titleWidth), overflowed: topBar.overflowed, scroll: topBar.scrollState, order: Config.barOverflowOrder, priority: barEditor.item ? barEditor.item.priorityState : { open: false, list: [], scroll: 0, scrollMax: 0, lengthMenu: false, length: "" }, stay: Config.barStay, more: topBar.moreRows().map(r => [r.label, r.value]), menu: topBar.menu.visible ? topBar.menu.items.map(i => i.label) : [], dots: topBar.dotsState, band: topBar.band,
                       // (the label off the bar saying what the pointer's over: BarLabel.qml)
                       label: topBar.label.testState },
                barEdge: Config.barEdge, dockEdge: Config.dockEdge,
                // (where each screen's bar takes the pointer: the click catchers leave it out)
                barRects: Config.barRects,
                // (each item, its submenu's items, and which are ticked: icon 0xEA5E)
                dockMenu: win.testMenuState()
            });
        }
    }
    // The tray's register, apart from Slate so it outlives Slate's restarts (apps that sign
    // their icons up only once would lose them): started here too for sessions that didn't
    // (another copy just exits), detached so it keeps going
    // (started in Component.onCompleted, with the test suite's ready mark, above)
    // Geist ships with Slate (fonts/, SIL OFL), so it's there even if not installed system-wide
    Variants {
        model: ["Geist-Variable.ttf", "Geist-Italic-Variable.ttf", "GeistMono-Variable.ttf", "GeistMono-Italic-Variable.ttf"]
        FontLoader { required property var modelData; source: "file://" + Quickshell.shellPath("fonts/" + modelData) }
    }
    Wallpaper { id: wallpaperLayer; bar: topBar }
    // The wallpaper switcher (Super+Alt+W, in Wallpaper.qml): one of the things only one of shows at a time
    Connections {
        target: wallpaperLayer.switcher
        function onShownChanged() {
            if (wallpaperLayer.switcher.shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
        }
    }
    NightLight { id: nightLight }
    // Automatic brightness: a singleton, made here so it starts with Slate when it's switched on
    readonly property bool autoBrightnessRunning: AutoBrightness.running
    AirplaneMode {}
    Radios {}                                 // Wi-Fi and Bluetooth through IPC, for assistants
    PrivateMode { id: privateMode; confirm: powerConfirm }
    SwitchHardware {}
    PolkitAgent { id: polkitAgent }          // password prompts for apps (pkexec, system settings…)
    Notifications { id: notifs; bar: topBar }
    // Settings, built the first time it's wanted (an IPC call, the dock's menu, or being open when
    // Slate reloaded) rather than at every start: it's the biggest window Slate has, and most
    // sessions only open it now and then. Once built it stays, and is built afresh whenever it's
    // closed from outside Slate (Super+Q, a title bar's close button): after that the window
    // couldn't be shown again until Slate reloaded
    LazyLoader {
        id: settingsLoader
        active: false
        SettingsWindow {
            bar: topBar; notifs: notifs
            confirmer: powerConfirm       // (asks in the same window as shutting down: app installs)
            voice: voiceModel             // (Assistant → Voice: the speech model)
            placeFile: root.settingsPlaceFile
            onClosed: { forgetPlace(); settingsRebuild.restart(); }
        }
    }
    // The Settings window, built if it isn't yet (a LazyLoader builds the moment it's switched on)
    function settingsWindow() {
        settingsLoader.active = true;
        return settingsLoader.item;
    }
    // Where Settings keeps its page while it's open (see SettingsWindow.qml), named for this
    // Hyprland session: logging in again never opens it
    readonly property string settingsPlaceFile: Config.runtimeDir + "/slate/settings-open-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none") + ".json"
    // Open when Slate reloaded or restarted: build Settings now, and it reopens as it was
    FileView {
        path: root.settingsPlaceFile
        blockLoading: true
        printErrors: false
        onLoaded: {
            let p = null;
            try { p = JSON.parse(text() || "{}"); } catch (e) {}
            if (p && p.section) Qt.callLater(() => root.settingsWindow());
        }
    }
    // `slate ipc call settings …` (open, toggle, page, find…): out here so it works before the
    // window exists, building it when there's something to show
    IpcHandler {
        target: "settings"
        // (open behind another window, or with the keyboard elsewhere, toggle brings it to the front
        // rather than closing it; it's closed when it's the window you're in)
        function toggle(): void { const w = root.settingsWindow(); if (w.visible && !w.isFocused()) w.show(); else w.visible = !w.visible; }
        function open(): void { root.settingsWindow().show(); }
        // (nothing to close if it was never built)
        function close(): void { if (settingsLoader.item) settingsLoader.item.visible = false; }
        // Old page names still work: switchers → windows
        function page(name: string): void {
            const w = root.settingsWindow();
            w.keepSection = !w.visible;
            w.section = ({ switchers: "windows" })[name] ?? name;
            w.show();
        }
        // Open a page scrolled to one setting (or heading), lit up for a moment, e.g.
        //   slate ipc call settings find appearance "Interface size"
        function find(page: string, label: string): void { root.settingsWindow().goTo(page, label); }
        // Search, as typing into the search box showing (All Settings', or the one above any
        // other page) does: slate ipc call settings search "dock"
        function search(text: string): void { const w = root.settingsWindow(); w.show(); w.searchFor(text); }
        // Open General with the account picture chooser showing (the control centre's avatar)
        function avatar(): void { const w = root.settingsWindow(); w.keepSection = !w.visible; w.section = "general"; w.avatarPicking = true; w.show(); }
        // For the assistant (slate mcp): how many settings on a page differ from their defaults
        // (-1: a page with nothing Restore defaults puts back), whether putting them back
        // restarts Slate, and doing it, as the page title's Restore defaults does
        function changed(page: string): string {
            const w = root.settingsWindow();
            const keys = w.pageKeys[page];
            return JSON.stringify(keys ? { changed: Config.changedCount(keys), restarts: w.restartsFor(keys) } : { changed: -1, restarts: false });
        }
        function restore(page: string): void { const w = root.settingsWindow(); if (w.pageKeys[page]) { w.restorePage(page); w.countChanged(); } }
    }
    // Out here, not in the window: it has to outlive the window it replaces. Drops the old window;
    // the next time Settings is wanted, it's built afresh
    Timer {
        id: settingsRebuild
        interval: 0
        onTriggered: settingsLoader.active = false
    }
    Variants {
        model: Quickshell.screens
        ScreenCorners { required property var modelData; screen: modelData; bar: topBar }
    }
    // Logging out, restarting, shutting down: every screen fades to black with the goodbye sound
    Variants {
        model: Config.leaving ? Quickshell.screens : []
        FadeOut { required property var modelData; screen: modelData }
    }
    OSD { id: osdPop; bar: topBar; popouts: popouts }
    // The panel by the bar while it's being arranged (Settings → Menu Bar → Edit layout): built
    // when arranging starts, and let go a moment after it ends (it fades out first)
    LazyLoader {
        id: barEditor
        active: Config.barArranging || barEditorLinger.running
        BarEditor { bar: topBar; confirmer: powerConfirm }
    }
    Timer { id: barEditorLinger; interval: 500 }
    Connections {
        target: Config
        function onBarArrangingChanged() { if (!Config.barArranging) barEditorLinger.restart(); }
    }
    // The secret workspace showing with nothing on it: a note saying so, on that screen
    Variants {
        model: Quickshell.screens
        SecretEmpty { required property var modelData; screen: modelData; bar: topBar }
    }
    LockScreen { id: lockScreen }
    // Talking to Nova (Settings → Assistant → Voice): what's there for it, and the listening
    // itself, only while the key or the microphone is held
    VoiceModel { id: voiceModel }
    NovaVoice { id: novaVoice; window: nova; model: voiceModel; locked: lockScreen.locked }
    AssistantGate { id: assistantGate; powerConfirm: powerConfirm; lockScreen: lockScreen; window: nova }     // what AI agents may do (slate mcp)
    // The screen locks: the prompt window closes and a run stops
    Connections { target: lockScreen; function onLockedChanged() { if (lockScreen.locked) { nova.closeWindow(); nova.stop(); wallpaperLayer.switcher.cancel(); } } }
    Screensaver { id: screensaver; lock: lockScreen }
    HotCorners { id: hotCorners; lock: lockScreen }

    Switcher {
        id: winSwitcher
        bar: topBar
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); wallpaperLayer.switcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    WorkspaceOverview {
        id: wsOverview
        bar: topBar
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wallpaperLayer.switcher.cancel(); popouts.close(); picker.close(); }
    }
    // Your own tweaks: the hypr/*.lua files and user/shell.qml (made with instructions in them
    // if missing; saving one reloads Hyprland's config or Slate)
    UserFiles { id: userFiles }
    // Held back while the wallpaper switcher looks (see UpdateHold.qml), then the parts that use it
    UpdateHold { id: updateHold }
    GreeterSync { hold: updateHold }
    HyprlandLook { hold: updateHold; userFiles: userFiles }
    AppTheming { id: appTheming; hold: updateHold }
    ReloadNotices {}
    // The welcome: the first time Slate starts, and from Settings → About
    Welcome { id: welcome; bar: topBar; confirmer: powerConfirm }
    // Hyprbars (the optional title-bar plugin): notices when it needs rebuilding, and asks
    HyprbarsWatch { confirm: powerConfirm; welcome: welcome }
    // New releases: checked daily, a notification when one's out (Settings → Updates)
    // Nothing reads this, but keep it: it's what creates the Updates singleton at start (its
    // daily check and the "updates" IPC), as singletons are only made when first used
    readonly property bool updateAvailable: Updates.available
    // A space's colour and icon on the windows it opened (Settings → Menu Bar → Mark windows from a space)
    SpaceBadges { bar: topBar; suppressed: appLauncher.shown || winSwitcher.shown || wsOverview.shown || picker.shown || popouts.shown || wallpaperLayer.switcher.shown }

    // The dock (Dock.qml). It reaches only these parts of Slate
    // (handed over through the root: inside `Dock { }`, `popouts: popouts` would read the
    // dock's own new property and hand it null, which froze an auto-hiding dock)
    readonly property var dockPopouts: popouts
    readonly property var dockNotifs: notifs
    readonly property var dockLauncher: appLauncher
    readonly property var dockConfirm: powerConfirm
    Dock {
        id: win
        popouts: root.dockPopouts
        notifs: root.dockNotifs
        appLauncher: root.dockLauncher
        powerConfirm: root.dockConfirm
        settingsWindow: () => root.settingsWindow()
    }
}
