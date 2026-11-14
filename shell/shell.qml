//@ pragma AppId slate-settings
//@ pragma UseQApplication
// (AppId: the app id Slate's own windows get, so the Settings window has Slate's icon: see
// data/slate-settings.desktop and assets/icon/settings-*.png. UseQApplication: lets app tray
// menus, which are "platform menus", open when a tray icon is right-clicked.)
// Slate: a desktop shell for Hyprland (bar, dock, launcher, switchers, panels,
// notifications, settings). Run with:  slate
// Settings: settings.json here; saved state: ~/.local/state/slate; cache: ~/.cache/slate
//
// This file holds the dock (a macOS-style dock) and wires the other parts together:
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
    Variants {
        model: Config.anyFloating && Config.slateTitleBars ? Quickshell.screens : []
        TitleBar { required property var modelData; screen: modelData }
    }
    // Only one of the launcher, window switcher and workspace overview shows at a
    // time: opening one closes the others
    Launcher {
        id: appLauncher
        notifs: notifs
        onShownChanged: if (shown) { Config.closeMenus(); winSwitcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); nova.closeWindow(); }
    }
    // Nova, the assistant's prompt window (Super+K): one of the things only one of shows at a time
    Assistant {
        id: nova
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wsOverview.close(); popouts.close(); picker.close(); }
    }
    // Clipboard history (Super+V) and emoji picker (Super+.)
    Picker {
        id: picker
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); wsOverview.close(); popouts.close(); nova.closeWindow(); }
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
    Process { id: readyMark; command: ["sh", "-c", ': > "${XDG_RUNTIME_DIR:-/tmp}/slate-ready"'] }
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
                Config.barFloat = { kind: a, icons: [{ code: (Config.barItem(b) || { icon: 0xEAD5 }).icon, item: b, text: topBar.exampleOf(b) }], label: "" };
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
            else if (what === "length") { if (a === "pick") barEditor.lengthPick(Number(b)); else barEditor.lengthMenu(a === "open"); }
            else if (what === "priority") { if (a === "move") barEditor.priorityMove(b, n(c)); else if (a === "scroll") barEditor.priorityScroll(Number(b)); else Config.barPrioritising = a === "open"; }
            else if (what === "scroll") topBar.scrollBy(Number(a));
            else if (what === "more") topBar.moreClick({ id: a, tray: null }, b === "right");
            else if (what === "unhover") { Config.barFloat = null; Config.barCarry = null; Config.barCarryTarget = null; }
            else if (what === "carry") { Config.barCarry = { kind: a, id: b }; Config.barCarryTarget = JSON.parse(c); Config.barDrop(); }
        }
        // Hot corners: is this point (Hyprland's pixels, as `hyprctl cursorpos` says) in that
        // corner ("topLeft", "bottomRight"…) of the main display? (what unlocking asks)
        function hotCorner(corner: string, x: real, y: real): bool { return hotCorners.pointIn(corner, x, y); }
        // Arranging the bar: a chip in the pool pressed with the pointer at x, y (Hyprland's
        // pixels, as `hyprctl cursorpos` says): where that is on the desktop, as the bar counts it
        function barPointer(x: real, y: real): string {
            barEditor.pointer = Qt.point(0, 0);
            barEditor.locate(x, y);
            return JSON.stringify({ x: barEditor.origin.x, y: barEditor.origin.y });
        }
        // The speakers or the microphone in use, or neither, as if PipeWire had said so:
        // what = "output", "input", "both" or "none" (the volume panel's sliders show it)
        function audioBusy(what: string): void { popouts.pretendAudioBusy(what); }
        // Weather for the clock panel and control centre, as if it had been fetched for a place
        // (tests have no network): mild rain now, then four days
        // The control centre's quick switches: their order (ids, comma-separated; "" for none
        // chosen), a press on one by id (the panel open), and which this computer can't use
        function controlSwitches(ids: string): void { Config.s.controlSwitches = ids === "" ? [] : ids.split(","); }
        function pressSwitch(id: string): void { popouts.pressSwitchAsked(id); }
        function newSpace(): void { popouts.newSpaceAsked(); }
        // Less room for the dock's things than its edge has (px; 0: the whole edge), to fill it
        // with a few windows rather than dozens
        function dockRoom(px: real): void { win.testRoom = px; }
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
            if (what === "open") { topBar.menu.openAt(600, 20); return; }
            const path = what.split("/");
            let row = topBar.menu.items.find(i => i.label === path[0]);
            if (row && path.length > 1 && row.submenu) row = row.submenu.find(i => i.label === path[1]);
            topBar.menu.close();
            if (row && row.run) row.run();
        }
        // The camera in use, as camera-watch.py would say (the test machine has none)
        function camera(on: bool, apps: string): void {
            Config.cameraApps = apps === "" ? [] : apps.split(",");
            Config.cameraOn = on;
        }
        // The dock's own menu (its empty space): "open", or an item to choose, as barMenu
        function dockMenu(what: string): void {
            if (what === "open") { dockMenu.openHere(); return; }
            const path = what.split("/");
            let row = dockMenu.items.find(i => i.label === path[0]);
            if (row && path.length > 1 && row.submenu) row = row.submenu.find(i => i.label === path[1]);
            dockMenu.close();
            if (row && row.run) row.run();
        }
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
            else if (what === "unset") Config.titleBarStyleUnset = true;      // as if the settings were from before the choice
            else Config.hyprbarsCheck();
        }
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
        function dockDrag(key: string, i: int, up: real): void {
            // (the last drop still gliding into place: landed at once, so this is a new drag)
            if (win.landing) { land.stop(); dragPop.landed(); }
            if (win.dragKey === "") win.startDrag(key);
            const x = (strip.width - win.restWidth) / 2 + win.slotStart(Math.max(0, i)) + (i < 0 ? -win.base * 2 : win.base * 0.25);
            win.testHover = true;
            win.setPointer(x);
            const pt = Qt.point(x, bg.y + bg.height / 2 - up);
            win.dragScreen = win.toScreen(strip.mapToItem(win.contentItem, pt.x, pt.y));
            win.dragTo(pt);
        }
        // The login fade's cover (FadeIn.qml), which tests never see otherwise: shown and held,
        // faded away as at login, or taken away at once
        function fadeIn(): void { Config.welcomeFading = false; Config.welcoming = true; }
        function fadeInEnd(): void { Config.welcomeFading = true; }
        function fadeInClose(): void { Config.welcoming = false; Config.welcomeFading = false; }
        // Settings asking something (as its Reset does, with a switch): it should ask in Slate's
        // confirmation window (power: custom), not a card of its own
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
        // A greyed-out setting's "Needs …" line, as clicking it does: off to the setting it needs
        function settingsFollowNeeds(label: string): void {
            const w = settingsLoader.item;
            if (w) w.followNeeds(label);
        }
        // Settings → Assistant's switch and its "Read the risks again", as clicking them does
        function assistant(what: string): void {
            const w = settingsLoader.item;
            if (!w) return;
            if (what === "risks") w.assistantReadRisks();
            else w.assistantSwitch(what === "on");
        }
        // As saying yes to an agent that keeps its own tools (Settings → Assistant) leaves it
        function assistantAccepted(id: string): void { Config.s.assistantAgentsAccepted = id === "" ? [] : [id]; }
        // The prompt window as a run would leave it: {asked, answer, working, actions, error}
        function nova(json: string): void {
            const st = JSON.parse(json);
            // (history: earlier exchanges, shown above this one)
            // (at / doneAt: when asked and answered, ms; left out, no time is shown)
            // (blocks: the answer as the runner reads it, scripts/safe_markdown.py; left out, it's plain text)
            const turn = h => ({ asked: h.asked || "", answer: h.answer || "", blocks: nova.cleanBlocks(h.blocks), actions: h.actions || [], error: h.error || null, at: h.at || 0, doneAt: h.doneAt || 0 });
            nova.turns = (st.history || []).map(turn).concat(st.asked ? [turn(st)] : []);
            nova.working = !!st.working;
            if (st.session !== undefined) nova.session = st.session;      // (the agent's thread, as a past answer left it)
            if (st.agents) { nova.agents = st.agents; nova.looked = true; }
        }
        // Forget the sounds noted so far (state().sounds: what would have played, Config.testSounds)
        function sounds(): void { Config.testSounds = []; }
        // A code box's Copy in the latest answer, as clicking it does (block: its place among the blocks)
        function novaCopyCode(block: int): void { nova.copyCode(nova.turns.length - 1, block); }
        // Scroll the launcher's list steadily from where it is to the bottom, over ms
        function launcherScroll(ms: int): void { appLauncher.testScroll(ms); }
        function dockDrop(): void { win.endDrag(); win.testHover = false; }
        // Drag an app out of More's grid (open: dock more) as the pointer would, held over slot i
        // of the dock (as the slots are now; -1: off its start), `up` pixels up from its middle:
        // handed to the grid's own carrying (win.carryFromMore) as a place on the screen (the
        // menu's window covers it), as the grid's tile does. Then let go, as releasing the tile does
        function dockMoreDrag(key: string, i: int, up: real): void {
            if (win.dragKey === "") {
                if (!(appMenu.visible && appMenu.app && appMenu.app.moreGrid)) return;
                win.pickFromMore(key);
            }
            const x = (strip.width - win.restWidth) / 2 + win.slotStart(Math.max(0, i)) + (i < 0 ? -win.base * 2 : win.base * 0.25);
            const sp = win.toScreen(strip.mapToItem(win.contentItem, x, bg.y + bg.height / 2 - up));
            win.carryFromMore(sp);
        }
        function dockMoreDrop(): void { win.dropFromMore(); }
        function dockHover(i: int): void {
            win.testHover = i >= 0;
            if (i >= 0) win.setPointer((strip.width - win.restWidth) / 2 + win.slotStart(i) + win.slotWidth(i) * win.base / 2);
        }
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
                settings: { open: !!settings && settings.visible, section: settings ? settings.section : "",
                            ownCard: !!settings && settings.confirming,
                            changed: settings ? settings.changedHere : 0,
                            scroll: settings ? settings.scrolledTo : 0, thumbsLoading: settings ? settings.thumbsLoading + (settings.wallsListing ? 1 : 0) : 0,
                            checking: settings ? settings.checking : 0,
                            // Settings greyed out for another one, with what each says it needs
                            // (SettingRow's needs), and the setting last gone to (goTo)
                            waiting: settings && settings.visible ? settings.waitingRows().map(r => ({ label: r.label, needs: r.needs })) : [],
                            found: settings && settings.foundItem ? String(settings.foundItem.label || "") : "" },
                launcher: { open: appLauncher.shown, visible: appLauncher.visible, screen: appLauncher.screen ? appLauncher.screen.name : "", query: appLauncher.query, mode: appLauncher.mode, current: appLauncher.currentIndex,
                            results: (appLauncher.results || []).slice(0, 30).map(r => opt(r.name) || opt(r.title) || opt(r.id) || ""),
                            // How it opened and scrolled (launcherScroll): frame times, the time spent moving
                            // the list, the app rows seen, those whose tile was there when they were, and
                            // rows drawn out of place
                            frames: appLauncher.testFrames, work: appLauncher.testWork, scrolled: appLauncher.testScrolled(),
                            openMs: appLauncher.testOpenMs, scrolling: appLauncher.testScrolling,
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
                           inSub: topBar.menu.inSub, subHot: topBar.menu.subHot, subRowY: topBar.menu.subRowY,
                           items: topBar.menu.items.map(i => i.separator ? "-" : i.label) },
                switcher: { open: winSwitcher.shown, windows: winSwitcher.windows.length, previews: winSwitcher.previewsReady(),
                            fade: Math.round(winSwitcher.fade * 100) / 100, animate: winSwitcher.animate },
                // Every window Hyprland has, with where it is (address: Hyprland's, without the 0x)
                windows: Hyprland.toplevels.values.map(t => ({ title: t.title || "", workspace: t.workspace ? t.workspace.id : -1,
                                                              address: (t.address || "").replace(/^0x/, "") })),
                overview: { open: wsOverview.shown, screen: wsOverview.screen ? wsOverview.screen.name : "", selected: wsOverview.selected, grid: wsOverview.isGrid,
                            previews: wsOverview.previewsReady(),
                            fade: Math.round(wsOverview.fade * 100) / 100, animate: wsOverview.animate, strip: Math.round(wsOverview.stripAt() * 10000) / 10000,
                            // (the workspaces Slate knows of now: the overview shows these as it opens)
                            known: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id).sort((a, b) => a - b),
                            workspaces: wsOverview.spaces.map(w => w.id), pending: wsOverview.pendingId, arrived: wsOverview.arrived,
                            zooming: wsOverview.zooming, leaving: wsOverview.leaving, focused: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1,
                            columns: wsOverview.isGrid ? Math.max(1, Math.min(wsOverview.gridSize, wsOverview.spaces.length)) : 0 },
                lock: { locked: lockScreen.locked, previewing: lockScreen.previewing },
                screensaver: { open: screensaver.shown },
                power: { open: powerConfirm.shown, action: powerConfirm.action, option: powerConfirm.hasOption },
                polkit: { open: polkitAgent.shown },
                welcome: { open: welcome.shown, page: welcome.page, pages: welcome.pages },
                fadeIn: { open: Config.welcoming, fading: Config.welcomeFading },
                notifications: { history: notifs.history.length, unread: notifs.unread, dnd: notifs.dnd, toasts: notifs.toastsShowing,
                                 latest: notifs.history.length > 0 ? notifs.history[0].summary : "" },
                dock: {
                    pinned: win.pinned, screen: win.screen ? win.screen.name : "",
                    dragging: win.dragKey, dropIndex: win.dropIndex, dragAway: win.dragAway, gapAt: win.gapAt,
                    dragFromMore: win.dragFromMore, menuLifted: appMenu.lifted, moreGrid: appMenu.moreList.map(it => it.key),
                    slots: win.slots.map(x => x.kind === "app"
                        ? { kind: "app", key: x.item.key, pinned: x.item.pinned, windows: x.item.windows.length, badge: win.badgeFor(x.item) }
                        : { kind: x.kind }),
                    menu: appMenu.visible ? (appMenu.app && appMenu.app.key ? appMenu.app.key : appMenu.app && appMenu.app.moreGrid ? "more" : "other") : "",
                    preview: previewPop.wanted, previewOnScreen: previewPop.visible, media: win.mediaShown, trash: win.trashCount,
                    base: Math.round(win.base * 100) / 100, length: Math.round(win.restWidth + win.padding * 2), room: Math.round(win.roomLength),
                    more: win.moreItems.map(it => it.key), mediaCompact: win.foldPlan.compact,
                    moreOpen: appMenu.visible && !!appMenu.app && !!appMenu.app.moreGrid,
                    hoverEffect: win.hoverEffect,
                    fade: win.slots.map(x => Math.round(win.fadeAt(x.at) * 100) / 100),
                    glow: win.slots.map(x => Math.round(win.glowAt(x.at) * 100) / 100),
                    lift: win.slots.map(x => Math.round(win.liftAt(x.at))),
                    tilt: win.slots.map(x => Math.round(win.tiltAt(x.at))), scale: win.slots.map(x => Math.round(win.scaleAt(x.at) * 100) / 100)
                },
                tray: SystemTray.items.values.map(i => i.id),
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
                assistant: { open: nova.shown, working: nova.working, stopShown: nova.stopShown, turns: nova.turns.length, asked: nova.asked, answer: nova.answer, actions: nova.actions,
                             error: nova.error ? nova.error.kind : "", errorText: nova.error ? nova.error.message : "", agent: nova.agent ? nova.agent.id : "", session: nova.session,
                             // (the answer's blocks, the markup each of its words items is given, and what was just copied)
                             blocks: nova.cur ? nova.cur.blocks || [] : [], rich: nova.richNow(), copied: nova.copied,
                             button: Config.s.barShowAssistant && Config.assistantOn,
                             enabled: Config.assistantOn, risksChanged: Config.assistantRisksChanged, waiting: Object.keys(assistantGate.answers).length },
                // Slate's settings reaching Hyprland (Config.testHypr)
                hypr: Config.testHypr(),
                // The menu bar's arrangement, and arranging it (BarEditor.qml)
                bar: { arranging: Config.barArranging, layout: Config.barLayout, isDefault: Config.barIsDefault,
                       picked: Config.barSelected, pickedItem: Config.barSelectedItem, editor: barEditor.shown, edge: popouts.edge,
                       line: topBar.lineState(), span: topBar.lineSpan, gives: topBar.gives, opened: topBar.openBoxes(), clock: topBar.clockText, overflowed: topBar.overflowed, scroll: topBar.scrollState, order: Config.barOverflowOrder, priority: barEditor.priorityState, stay: Config.barStay, more: topBar.moreRows().map(r => [r.label, r.value]), menu: topBar.menu.visible ? topBar.menu.items.map(i => i.label) : [], dots: topBar.dotsState, band: topBar.band,
                       // (the label off the bar saying what the pointer's over: BarLabel.qml)
                       label: topBar.label.testState },
                barEdge: Config.barEdge, dockEdge: Config.dockEdge,
                // (each item, its submenu's items, and which are ticked: icon 0xEA5E)
                dockMenu: { open: dockMenu.visible, items: dockMenu.items.map(i => i.separator ? null
                    : { label: i.label, ticked: i.icon === 0xEA5E, sub: i.submenu ? i.submenu.map(j => j.separator ? null : { label: j.label, ticked: j.icon === 0xEA5E }) : null }) }
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
    Wallpaper {}
    NightLight {}
    AirplaneMode {}
    PrivateMode { id: privateMode; confirm: powerConfirm }
    SwitchHardware {}
    PolkitAgent { id: polkitAgent }          // password prompts for apps (pkexec, system settings…)
    Notifications { id: notifs; bar: topBar }
    // Settings, built afresh whenever it's closed from outside Slate (Super+Q, a title bar's close
    // button): after that the window couldn't be shown again until Slate reloaded
    LazyLoader {
        id: settingsLoader
        active: true
        SettingsWindow {
            bar: topBar; notifs: notifs
            confirmer: powerConfirm       // (asks in the same window as shutting down: app installs)
            onClosed: settingsRebuild.restart()
        }
    }
    // Out here, not in the window: it has to outlive the window it replaces. Runs twice: the first
    // time drops the old window, the second builds the new one
    Timer {
        id: settingsRebuild
        interval: 0
        onTriggered: {
            if (settingsLoader.active) { settingsLoader.active = false; restart(); }
            else settingsLoader.active = true;
        }
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
    BarEditor { id: barEditor; bar: topBar; confirmer: powerConfirm }       // the panel by the bar while it's being arranged (Settings → Menu Bar → Edit layout)
    // The secret workspace showing with nothing on it: a note saying so, on that screen
    Variants {
        model: Quickshell.screens
        SecretEmpty { required property var modelData; screen: modelData; bar: topBar }
    }
    LockScreen { id: lockScreen }
    AssistantGate { id: assistantGate; powerConfirm: powerConfirm; lockScreen: lockScreen; window: nova }     // what AI agents may do (slate mcp)
    // A bar panel opening takes the prompt window's place, like the other overlays
    Connections { target: popouts; function onCurrentChanged() { if (popouts.current !== "") nova.closeWindow(); } }
    // The screen locks: the prompt window closes and a run stops
    Connections { target: lockScreen; function onLockedChanged() { if (lockScreen.locked) { nova.closeWindow(); nova.stop(); } } }
    Screensaver { id: screensaver; lock: lockScreen }
    HotCorners { id: hotCorners; lock: lockScreen }

    // Keep the login screen (/var/lib/slate-greeter) in step with the wallpaper and
    // settings. Does nothing until it's been set up with: sudo slate-greeter-install
    Timer { id: greeterSync; interval: 3000; onTriggered: greeterSyncRun.running = !Config.testMode }
    Process {
        id: greeterSyncRun
        command: ["sh", "-c", "[ -w /var/lib/slate-greeter ] && exec \"$0\" || true", Quickshell.shellPath("bin/slate-greeter-sync")]
    }
    Connections { target: Config; function onWallpaperChanged() { greeterSync.restart(); } function onSaved() { greeterSync.restart(); } function onAvatarVersionChanged() { greeterSync.restart(); } }

    // Window borders follow the theme (and the width set in Settings): accent on the active window, the bar's colour on
    // the others (60% and 85%; Hyprland cannot blur behind borders), plus dimming and gaps. Hyprland's config
    // (colors.lua) has fallbacks; these replace them, and again after a config reload.
    readonly property string borderCmd: {
        const rgba = (c, a) => "rgba(" + c.toString().slice(1, 7) + Math.round(a * 255).toString(16).padStart(2, "0") + ")";
        const active = rgba(Config.accent, 0.6), inactive = rgba(Config.tint("#0f1216"), 0.85);
        // Glass (with its gloss): a sheen on the borders, as Hyprland can draw one. Its gradients
        // spread their colours evenly, so the light is the first of several: a bright catch on
        // the top left corner, fading within the first sixth or so into the colour itself, a
        // touch deeper at the far corner (how strong follows Glass → Gloss). Hyprland's angles
        // put the first colour at the left for 0°, the top for 90°: 45° is the top left.
        // Without glass (or in game mode), flat
        const toWhite = (c, k) => Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1);
        const g = Config.glassGloss ? Math.min(1, Config.glossAmount) : 0;
        const sheen = (base, a, light, soft, deep) => [rgba(toWhite(base, light * g), Math.min(1, a + 0.3 * g)), rgba(toWhite(base, soft * g), a),
            rgba(base, a), rgba(base, a), rgba(base, a), rgba(base, a), rgba(Qt.darker(base, 1 + deep * g), a)].map(c => `"${c}"`).join(", ");
        const activeColors = g > 0 ? sheen(Config.accent, 0.6, 0.75, 0.3, 0.2) : `"${active}"`;
        const inactiveBorder = g > 0
            ? `{ colors = { ${sheen(Config.tint("#0f1216"), 0.85, 0.3, 0.1, 0)} }, angle = 45 }`
            : `"${inactive}"`;
        const size = Math.max(0, Math.min(12, Config.s.windowBorderSize));   // Settings → Windows
        const dim = Math.max(0, Math.min(80, Config.s.inactiveDim)) / 100;   // Settings → Windows
        // Spacing: gaps_in is added on each side of a window, so half the gap between two;
        // the screen edges get a little more. Lone windows stay gapless (workspaces.lua)
        const gap = Math.max(0, Math.min(32, Config.s.windowGap));
        const gapIn = Math.round(gap / 2), gapOut = gap > 0 ? gap + 2 : 0;
        // A window alone on its workspace: no gaps unless set (re-sending a rule replaces it).
        // Maximised and full-screen apps always fill the screen.
        const solo = Math.max(0, Math.min(32, Config.s.soloWindowGap));
        // ...with square corners only while it fills the screen (rule in windowrules.lua)
        const solos = `hl.workspace_rule({ workspace = "w[tv1]", gaps_out = ${solo}, gaps_in = 0 }); `
            + `if SOLO_SQUARE_RULE then SOLO_SQUARE_RULE:set_enabled(${solo === 0}) end; `;
        // Window mode: Hyprland's layout, and the float-all rule on or off (windowrules.lua); converting open
        // windows happens only when the setting changes (below)
        const mode = `hl.config({ general = { layout = "${Config.hyprLayout}" } }); WINDOW_MODE = "${Config.windowMode}"; `
            + `SLATE_TITLEBARS = ${Config.slateTitleBars}; SLATE_TITLEBAR_HEIGHT = ${Math.round(13 * 2.6 * Config.uiScale)}; WORKSPACE_MODES = ${Config.workspaceModesLua}; `
            + `if setWindowMode then setWindowMode(${Config.windowMode === "floating"}, false) end; `
            + `if setSpareWorkspace then setSpareWorkspace(${Config.s.keepEmptyWorkspace}) end; `;
        // Floating windows' title bars (hyprbars, when built): Slate's bar colour, text, font and button colours
        const bars = `if HYPRBARS_LOADED then pcall(hl.config, { plugin = { hyprbars = { bar_color = "${rgba(Config.tint("#0f1216"), 1)}", `
            + `col = { text = "${rgba(Config.tint("#eef1f5"), 1)}" }, inactive_button_color = "${rgba(Config.tint("#3a424e"), 1)}", `
            + `bar_text_font = [==[${Config.s.fontFamily}]==], bar_text_size = ${Math.round(13 * Config.uiScale)}, bar_height = ${Math.round(13 * 2.6 * Config.uiScale)}, `
            + `bar_buttons_alignment = "${Config.s.titleButtons === "left" ? "left" : "right"}" } } }); `
            + `if HYPRBARS_IDLE then pcall(hl.config, { plugin = { hyprbars = { idle_button_color = "${rgba(Config.tint("#5a6372"), 1)}" } } }) end end; `;
        return solos + mode + bars + `ACTIVE_BORDER = { colors = { ${activeColors} }${g > 0 ? ", angle = 45" : ""} }; INACTIVE_BORDER = ${inactiveBorder}; BORDER_SIZE = ${size}; `
            + `hl.config({ general = { border_size = BORDER_SIZE, gaps_in = ${gapIn}, gaps_out = ${gapOut}, col = { active_border = ACTIVE_BORDER, inactive_border = INACTIVE_BORDER } }, `
            + `decoration = { dim_inactive = ${dim > 0}, dim_strength = ${dim.toFixed(2)} } })`;
    }
    onBorderCmdChanged: borderPush.restart()
    // Title bar button colours and size (hyprbars.lua reads them when Hyprland's config loads, as
    // hyprbars can't recolour buttons later): written here, then Hyprland reloads, only when
    // they've changed and title bars are showing (floating mode). In tiling mode there are none to
    // recolour, so the reload waits until floating mode comes on: a reload makes the screen
    // flicker, and the accent changes with every theme preset and, from the wallpaper, with it
    readonly property string barButtonsLua: {
        const rgb = c => "rgb(" + c.toString().slice(1, 7) + ")";
        return `return { accent = "${rgb(Config.accent)}", accent_text = "${rgb(Config.tint("#12151a"))}", `
            + `button_size = ${Math.round(13 * 1.25 * Config.uiScale)} }\n`;
    }
    onBarButtonsLuaChanged: barButtonsSync.restart()
    FileView {
        id: barButtonsFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate/hyprbars.lua"
        blockLoading: true
        printErrors: false
    }
    Timer {
        id: barButtonsSync
        interval: 1500; running: true
        onTriggered: {
            if (barButtonsFile.text() === root.barButtonsLua) return;
            barButtonsFile.setText(root.barButtonsLua);
            if (Config.anyFloating && !Config.slateTitleBars) barButtonsReload.restart();
            else root.barButtonsStale = true;
        }
    }
    // Written while there were no title bars; Hyprland hasn't read them yet
    property bool barButtonsStale: false
    Connections {
        target: Config
        function onAnyFloatingChanged() { if (Config.anyFloating && !Config.slateTitleBars && root.barButtonsStale) barButtonsReload.restart(); }
    }
    Timer { id: barButtonsReload; interval: 300; onTriggered: { root.barButtonsStale = false; Config.reloadHyprland(); } }
    // Switching window mode also floats (or re-tiles) the windows already open. Only when
    // the setting changes: title bars turning up or going away just changes new windows
    Connections {
        target: Config.s
        function onWindowModeChanged() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() WINDOW_MODE = "${Config.windowMode}"; WORKSPACE_MODES = ${Config.workspaceModesLua}; if setWindowMode then setWindowMode(${Config.windowMode === "floating"}, true) end end`]);
        }
    }
    Timer { id: borderPush; interval: 300; running: true; onTriggered: Quickshell.execDetached(["hyprctl", "eval", root.borderCmd]) }
    Connections {
        target: Config
        // Hyprland reloaded: borders go back (and see whether Hyprbars is loaded now: it may
        // have been rebuilt), and check the config for errors
        function onHyprConfigReloaded() {
            borderPush.restart();
            Config.checkTitleBars();
            root.barButtonsStale = false;
            hyprErrors.running = false; hyprErrors.running = true;
        }
    }
    Connections {
        target: Hyprland
        // A window closed: GTK apps waiting to pick up new colours may now restart
        function onRawEvent(event) { if (event.name === "closewindow") gtkRefresh.restart(); }
    }
    Timer { id: gtkRefresh; interval: 1500; onTriggered: Quickshell.execDetached([Quickshell.shellPath("scripts/refresh-gtk-apps.sh")]) }

    // File managers' folder colour (Settings → Appearance): Papirus's folder icons in a chosen
    // colour, or the one nearest the wallpaper's (scripts/folder-colour.py)
    readonly property var folderArgs: Config.s.folderColour === "auto"
        ? (Config.wallpaperAccent !== "" ? ["--auto", Config.wallpaperAccent] : [])
        : (Config.s.folderColour !== "" ? [Config.s.folderColour] : [])
    onFolderArgsChanged: folderTimer.restart()
    Timer {
        id: folderTimer
        interval: 1200; running: true
        onTriggered: if (root.folderArgs.length) { folderRun.command = [Quickshell.shellPath("scripts/folder-colour.py")].concat(root.folderArgs); folderRun.running = true; }
    }
    Process { id: folderRun }

    // The icon theme (Settings → Icons → Icon theme): set for GTK, Qt and KDE apps, then the
    // folder colour made again on top of it (it's built on whichever theme is in use; a theme
    // that isn't Papirus has no coloured folders, so that does nothing). Slate's own tiles
    // follow by themselves (Config.tileDir has the theme in it)
    // ("" goes back to the theme this computer had before one was chosen, Config.s.iconThemeBefore)
    readonly property string iconThemeWanted: Config.iconThemeChosen !== "" ? Config.iconThemeChosen
        : (/^[\w.+-]+$/.test(Config.s.iconThemeBefore) ? Config.s.iconThemeBefore : "")
    onIconThemeWantedChanged: iconThemeTimer.restart()
    Timer { id: iconThemeTimer; interval: 800; onTriggered: if (root.iconThemeWanted !== "" && !Config.testMode) { iconThemeRun.running = false; iconThemeRun.running = true; } }
    Process {
        id: iconThemeRun
        command: [Quickshell.shellPath("scripts/folder-colour.py"), "--icon-theme", root.iconThemeWanted]
        onExited: folderTimer.restart()
    }

    // Apps switched on in Settings → Appearance → App Theming follow Slate's theme:
    // scripts/apply-theme.py writes their themes from these colours, a moment after a change
    readonly property string themeJson: JSON.stringify({
        accent: Config.accent.toString(), accentText: Config.tint("#12151a").toString(),
        bg: Config.tint("#0f1216").toString(), surface: Config.tint("#1d222a").toString(),
        surfaceHigh: Config.tint("#262c35").toString(), text: Config.tint("#eef1f5").toString(),
        dim: Config.tint("#8b94a3").toString(), error: Config.tint("#f28b8b").toString(),
        light: Config.s.lightMode,
        codeFont: Config.s.codeFontFamily,
        // The cursor size set in Settings (0 = not set): Slate's own environment still has the
        // size from when it started, so apps would get the old one back without this
        cursorSize: Config.s.cursorSize,
        // ...and its theme (Settings → Input → Pointer style; "" = as the session set it)
        cursorTheme: Config.s.cursorTheme,
        on: Config.s.themedApps || []
    })
    onThemeJsonChanged: themeApply.restart()
    Timer { id: themeApply; interval: 1500; running: true; onTriggered: root.applyThemes() }
    function applyThemes() {
        themeProc.running = false;
        themeProc.command = ["python3", Quickshell.shellPath("scripts/apply-theme.py"), root.themeJson];
        themeProc.running = true;
    }
    Process {
        id: themeProc
        // What it says about themes an app's update had undone (Spotify's by Spicetify, Discord's
        // by Vencord): "restored <id> <name>" where it put one back, "lost <id> <name>" where
        // it couldn't. Passed on as a notification
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const m = line.match(/^(restored|lost) (\S+) (.+)$/);
                    if (m) root.themeNotice(m[1], m[2], m[3]);
                }
            }
        }
    }
    function themeNotice(kind, id, name) {
        const base = ["notify-send", "--app-name=Slate", "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"), "--hint=string:x-slate-page:apptheming"];
        if (kind === "restored") {
            if (id === "spotify") {
                spotifyNote.command = base.concat(["--action=restart=Restart Spotify", name + "'s theme is back",
                    name + " was updated, which took Slate's theme with it. Slate has put it back for you: restart " + name + " to see it."]);
                spotifyNote.running = false; spotifyNote.running = true;
            } else Quickshell.execDetached(base.concat([name + "'s theme is back",
                name + " was updated, which took Slate's theme with it. Slate has put it back for you: restart " + name + " to see it."]));
        } else Quickshell.execDetached(base.concat([name + " lost its theme",
            id === "discord" ? name + " was updated, which removed Vencord. Once you've installed Vencord again, Slate's theme will come back with it."
                             : name + " was updated, and Slate couldn't patch the new version just yet. Refresh in Settings → App Theming is worth a try a little later."]));
    }
    Process {
        id: spotifyNote
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "restart")
                Quickshell.execDetached(["sh", "-c", 'exec "$(command -v spicetify || echo "$HOME/.spicetify/spicetify")" restart'])
        }
    }
    // An update of Spotify or Discord takes Slate's theme out of it (it's patched in). Looked
    // for every few minutes while either is themed; applying the themes again puts it back
    Timer {
        interval: 300000
        repeat: true
        running: !Config.testMode && (Config.s.themedApps || []).some(a => a === "spotify" || a === "discord")
        onTriggered: if (!themeProc.running && !themeStale.running) themeStale.running = true
    }
    Process {
        id: themeStale
        command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--stale", root.themeJson]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") root.applyThemes() }
    }
    // Settings → App Theming → Refresh: write every switched-on app's theme again now
    Binding { target: Config; property: "themesBusy"; value: themeProc.running }
    Connections { target: Config; function onRefreshThemes() { themeApply.stop(); root.applyThemes(); } }

    // When the login screen's code has changed, offer to install it (a notification
    // with an Update button, then a password prompt). Checked 20 s after Slate starts
    // (it reloads whenever its own code is edited) and after the greeter-only files
    // change, so a run of edits gives one prompt.
    Timer { id: greeterCodeCheck; interval: 20000; running: !Config.testMode; onTriggered: greeterPrompt.running = !Config.testMode }
    Process { id: greeterPrompt; command: [Quickshell.shellPath("bin/slate-greeter-sync"), "--prompt"] }
    // When this version of Slate needs packages you don't have, or changes the login session,
    // offer to install them (a notification with an Install button, then a password prompt).
    // Updates from Settings do this as they install; this catches the rest (a copy put in place
    // by hand, a package removed since). Checked once, 25 s after Slate starts.
    Timer { interval: 25000; running: !Config.testMode; onTriggered: systemPrompt.running = true }
    Process { id: systemPrompt; command: [Quickshell.shellPath("bin/slate-system"), "--prompt"] }
    Variants {
        model: ["greeter/files", "greeter/shell.qml", "greeter/LoginWindow.qml", "greeter/run-greeter.sh", "greeter/fonts.conf",
            "greeter/hyprland.lua", "greeter/emergency/shell.qml", "greeter/emergency/Window.qml", "greeter/emergency/Box.qml",
            "scripts/wallpaper-accent.py"]
        FileView {
            required property var modelData
            path: Quickshell.shellPath(modelData)
            watchChanges: true
            onFileChanged: { reload(); greeterCodeCheck.restart(); }
        }
    }
    Switcher {
        id: winSwitcher
        bar: topBar
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); wsOverview.close(); popouts.close(); picker.close(); nova.closeWindow(); }
    }
    WorkspaceOverview {
        id: wsOverview
        bar: topBar
        onShownChanged: if (shown) { Config.closeMenus(); appLauncher.closeLauncher(); winSwitcher.cancel(); popouts.close(); picker.close(); nova.closeWindow(); }
    }
    // Your own tweaks: the hypr/*.lua files and user/shell.qml (made with instructions in them
    // if missing; saving one reloads Hyprland's config or Slate)
    UserFiles {}
    // No "Configuration reloaded" popup when Slate reloads (after an update or a setting that
    // needs it, or a code change): it covered the top of the screen and got in the way of the
    // panels. Slate's own notice instead (a notification, kept in history like any other), for
    // a reload that worked and one that failed, and one when Hyprland reloads its config, with
    // any errors in it
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); reloadNotice.restart(); }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup(); root.reloadFailedNotice(errorString); }
    }
    // A failed reload leaves this (the previous) Slate running, so it can say so straight away.
    // Quickshell's error is a chain of "caused by @File.qml[line:col]: …"; the last link is
    // where the mistake is, so that leads
    property string lastReloadError: ""
    property var brokenFiles: []            // the files in the failed reload's error
    function reloadFailedNotice(error) {
        if (String(error) === lastReloadError) return;      // Quickshell reports a failure twice
        lastReloadError = String(error);
        const lines = String(error).split("\n").map(l => l.trim()).filter(l => l !== "");
        const links = lines.map(l => l.match(/@([^\[\]]+)\[(-?\d+):-?\d+\]:\s*(.*)$/)).filter(m => m);
        let body;
        if (links.length) {
            const cause = links[links.length - 1];
            const where = cause[1] + (parseInt(cause[2]) > 0 ? ", line " + cause[2] : "");
            const via = links.length > 1 ? links[links.length - 2][1] : "";
            body = cause[3] + " (" + where + (via ? ", used by " + via : "") + ").";
        } else {
            body = lines.slice(0, 3).join(" ");
        }
        brokenFiles = [...new Set(links.map(m => m[1]))];
        Quickshell.execDetached(["notify-send", "--app-name=Slate", "--urgency=critical", "--hint=string:x-slate-page:about",
            "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"),
            "Slate couldn't reload", body + " Nothing's lost: the previous version is still running, and Slate will reload as soon as you save the fix."]);
    }
    // After a failed reload Quickshell stops reloading when files change, until it's restarted.
    // So watch the files the error names, and reload as soon as one is saved
    Variants {
        model: root.brokenFiles
        FileView {
            required property string modelData
            path: Quickshell.shellPath(modelData)
            watchChanges: true
            printErrors: false
            onFileChanged: { root.brokenFiles = []; root.lastReloadError = ""; Config.restartSlate(); }
        }
    }
    Timer {
        id: reloadNotice
        interval: 600          // once the new Slate (and its notification server) is up
        onTriggered: Quickshell.execDetached(["notify-send", "--app-name=Slate", "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"), "--hint=string:x-slate-page:about",
            "Slate reloaded", "All fresh: Slate is running on its updated files and settings."])
    }
    // (hyprErrors runs again whenever Hyprland reloads: see onHyprConfigReloaded above)
    Process {
        id: hyprErrors
        command: ["hyprctl", "-j", "configerrors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let errs = [];
                try { errs = JSON.parse(text).filter(e => e && String(e).trim() !== ""); } catch (e) {}
                const icon = "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png");
                // No news when Slate reloaded it itself (to apply a setting); errors always show
                if (errs.length === 0 && Config.ownHyprReload()) return;
                if (errs.length === 0)
                    Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--hint=string:x-slate-page:windows", "Hyprland settings reloaded", "Hyprland has read its config again, and all is well."]);
                else
                    Quickshell.execDetached(["notify-send", "--app-name=Slate", icon, "--hint=string:x-slate-page:windows", "Hyprland settings have errors",
                        errs.join("\n").split("\n").slice(0, 6).join("\n")]);
            }
        }
    }
    // The welcome: the first time Slate starts, and from Settings → About
    Welcome { id: welcome; bar: topBar }
    // Hyprbars (the optional title-bar plugin): notices when it needs rebuilding, and asks
    HyprbarsWatch { confirm: powerConfirm; welcome: welcome }
    // New releases: checked daily, a notification when one's out (Settings → Updates)
    // Nothing reads this, but keep it: it's what creates the Updates singleton at start (its
    // daily check and the "updates" IPC), as singletons are only made when first used
    readonly property bool updateAvailable: Updates.available
    // A space's colour and icon on the windows it opened (Settings → Menu Bar → Mark windows from a space)
    SpaceBadges { bar: topBar; suppressed: appLauncher.shown || winSwitcher.shown || wsOverview.shown || picker.shown || popouts.shown }

    PanelWindow {
        id: win
        // The dock is on the focused screen
        screen: Config.focusedScreen

        // ---- Settings ------------------------------------------------------
        // Pinned apps (changed from the right-click menu; saved to dock.json). On first run
        // the dock pins whichever of these common apps are installed.
        property var pinned: []
        readonly property var firstRunApps: [
            "firefox", "org.mozilla.firefox", "chromium", "google-chrome", "brave-browser",
            "kitty", "com.mitchellh.ghostty", "org.gnome.Console", "org.kde.konsole", "Alacritty", "foot",
            "org.gnome.Nautilus", "org.kde.dolphin", "thunar", "nemo",
            "code", "code-oss", "org.gnome.TextEditor", "org.kde.kate",
            "spotify", "spotify-launcher", "steam", "org.gnome.Settings"
        ]
        FileView {
            id: dockState
            path: Quickshell.env("HOME") + "/.local/state/slate/dock.json"
            blockLoading: true
            onLoaded: { try { const d = JSON.parse(text()); if (Array.isArray(d.pinned)) win.pinned = d.pinned; } catch (e) {} }
            onLoadFailed: firstRun.start()
        }
        // App entries load in the background; give them a moment before choosing
        Timer {
            id: firstRun
            interval: 1500
            onTriggered: {
                const seen = new Set();
                win.pinned = win.firstRunApps.filter(id => {
                    const e = DesktopEntries.byId(id);
                    if (!e || seen.has(e.id)) return false;
                    seen.add(e.id);
                    return true;
                }).slice(0, 8);
                win.savePinned();
            }
        }
        function savePinned() { dockState.setText(JSON.stringify({ pinned: pinned }, null, 1)); }
        function setPinned(key, on) {
            const list = pinned.filter(k => k !== key);
            if (on) list.push(key);
            pinned = list;
            savePinned();
        }
        // Icon size at rest (logical px): as set in Settings, shrunk only when that many icons
        // wouldn't fit along the screen's edge (a short screen, a side dock, lots of apps open),
        // with room left at the ends for the dock's padding and the magnified icons. Each slot
        // counts at its real width in icons (what's playing is several, a divider a fraction)
        readonly property real iconsLong: {
            let n = 0;
            for (let i = 0; i < count; i++) n += slotWidth(i);
            return n;
        }
        readonly property real base: Math.max(16, Math.min(Config.s.dockIconSize,
            (roomLength - 48 - padding * 2 - (count - 1) * spacing) / Math.max(1, iconsLong)))
        // What pointing at the dock does (Settings → Dock → Hover effect): magnify, tilt, both
        // ("both": magnify and tilt), fade, fade and magnify ("fademagnify"), glow, glow and
        // magnify ("glowmagnify"), or none
        readonly property string hoverEffect: ["magnify", "tilt", "both", "fade", "fademagnify", "glow", "glowmagnify", "raise", "none"].includes(Config.s.dockHoverEffect) ? Config.s.dockHoverEffect : "magnify"
        // Raise: just the icon under the pointer lifts a little (none of the others), sliding up
        // and back down (each cell's lift animates in this mode). Nothing grows, so the slots
        // are where they rest
        readonly property int raisedIndex: {
            if (hoverEffect !== "raise" || hover < 0.5) return -1;
            for (let i = 0; i < count; i++) {
                const start = slotStart(i), end = start + slotWidth(i) * base;
                if (pointerX >= start - spacing / 2 && pointerX < end + spacing / 2) return isDivider(i) ? -1 : i;
            }
            return -1;
        }
        readonly property bool magnifies: ["magnify", "both", "fademagnify", "glowmagnify"].includes(hoverEffect)
        readonly property bool glows: hoverEffect === "glow" || hoverEffect === "glowmagnify"
        // (Raise: the comment above; the lift is liftAt's)
        // Glow: a ring and a glow round the icon under the pointer (DockGlow.qml), its near
        // neighbours a little, in the icon's colour (the accent for the Apps button, Downloads
        // and the Waste Basket, and icons whose colour isn't known yet)
        function glowAt(i) {
            if (!glows || i < 0 || isDivider(i)) return 0;
            const t = Math.abs(pointerX - (slotStart(i) + slotWidth(i) * base / 2)) / (base * Math.max(1, spread) * 0.6);
            const near = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return near * near * hover;
        }
        function glowColour(tilePath) {
            const name = String(tilePath || "").split("/").pop().replace(/\.png$/, "");
            const hex = name ? Config.iconColours[name] : "";
            if (!hex) { if (name) Config.askIconColour(name); return Config.accent; }
            return Qt.lighter(hex, Config.s.lightMode ? 1.0 : 1.15);
        }
        readonly property bool tilts: hoverEffect === "tilt" || hoverEffect === "both"
        readonly property bool fades: hoverEffect === "fade" || hoverEffect === "fademagnify"
        // Fade: with the pointer on the dock, the icons away from it fade (to a third), the ones
        // near it clear, over the same spread as magnifying; all clear once it leaves
        function fadeAt(i) {
            if (!fades || i < 0 || isDivider(i)) return 1;
            const t = Math.abs(pointerX - (slotStart(i) + slotWidth(i) * base / 2)) / (base * spread);
            const near = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return 1 - (1 - (0.35 + 0.65 * near)) * hover;
        }
        readonly property real maxScale: magnifies ? Config.s.dockMagnification : 1  // size of the icon under the pointer
        readonly property real spread: Config.s.dockSpread           // how many icons either side grow
        readonly property real spacing: 8
        readonly property real padding: 8        // inside the dock background
        // How rounded the icons' corners are (Settings → Icons → App icons), for the dock's own corners
        readonly property real iconCorner: {
            const shape = Config.s.iconShape;
            return shape === "circle" ? base / 2 : shape === "square" ? 0 : shape === "squircle" ? base * 0.3 : base * 0.225;
        }
        readonly property real bottomGap: 0      // gap between dock and screen edge
        readonly property int hideDelay: 700     // ms after the pointer leaves
        readonly property color bgColor: Config.surface(Config.tint("#0f1216"))      // same as the top bar
        // What's drawn on the dock's own buttons (the Apps bars, the Downloads and bin symbols, the
        // media controls) is laid out once, at the size of a fully magnified tile, and scaled to
        // the tile as it grows and shrinks. Sized afresh at every step instead, a symbol's size
        // went in whole pixels and its place snapped to them, so it wobbled inside a tile that
        // moved smoothly
        readonly property real symbolRef: Math.max(1, base * maxScale)
        readonly property color dockColor: Config.dockSurface(Config.tint("#0f1216"))    // the dock's own background: clearer with glass
        // Slate's own tiles (Apps, media, Downloads, the Waste Basket). Dark without glass: a little
        // lighter, as they were hard to tell from the dock
        readonly property color tileColor: Config.frostedTile(Config.tint(!Config.glass && !Config.s.lightMode ? "#29303a" : "#1d222a"))
        readonly property color textColor: Config.tint("#eef1f5")
        readonly property color dotColor: Config.tint("#c5ccd6")
        readonly property color activeDotColor: Config.accent
        readonly property string fontFamily: Config.s.fontFamily   // Settings → Appearance → Fonts
        readonly property int fontWeight: Font.Medium   // bar font weight 500
        readonly property real fontSize: 13             // matches the bar text

        // ---- Window --------------------------------------------------------
        // Which screen edge (Settings → Dock → Position; bottom becomes top when the bar is at
        // the bottom). The dock is laid out as a horizontal strip whose bottom edge meets the
        // screen; for other edges that strip is turned (stripMatrix) and each icon, label and
        // symbol is turned back (upright()), so all the layout and magnification maths stays
        // the same.
        // The edge it's on: the setting's, once it's slid out of sight at the old one (then it
        // slides in at the new), rather than Hyprland sliding the window across the screen
        // (bound to start with, so it starts on the right edge; on a change, put straight back,
        // before anything's drawn, until it's slid out: settledEdge is where it was)
        property string edge: Config.dockEdge
        property string settledEdge: ""
        property bool movingOut: false
        Component.onCompleted: settledEdge = edge
        Connections {
            target: Config
            function onDockEdgeChanged() {
                if (win.settledEdge === "" || Config.dockEdge === win.settledEdge) return;
                win.edge = win.settledEdge;
                win.movingOut = true;
                dockMove.restart();
            }
        }
        Timer {
            id: dockMove; interval: Config.ms(260) + 20
            onTriggered: { win.edge = Config.dockEdge; win.settledEdge = win.edge; win.movingOut = false; }
        }
        readonly property bool vertical: edge === "left" || edge === "right"
        // How far the dock reaches out from its edge: magnified icons and room for their labels
        readonly property real reach: Math.ceil(base * maxScale + padding * 2 + bottomGap + 40)
        // The window is taller still, so an app dragged up far enough to unpin it stays over it (the
        // dock only gets the pointer while it's over its window). Only a drag takes the pointer there
        readonly property real thickness: reach + Math.ceil(Math.max(120, base * 2.5)) + 40
        anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
        implicitHeight: vertical ? 0 : thickness
        implicitWidth: vertical ? thickness : 0
        readonly property real stripLength: vertical ? height : width
        // The room the dock's things have to fit in: the edge's length, or less in tests
        // (test dockRoom), so a few windows are enough to see what happens when it's full
        property real testRoom: 0
        readonly property real roomLength: testRoom > 0 ? Math.min(testRoom, stripLength) : stripLength
        // strip coordinates → window coordinates
        readonly property matrix4x4 stripMatrix: {
            const T = thickness;
            if (edge === "top") return Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, T,  0, 0, 1, 0,  0, 0, 0, 1);   // mirrored
            if (edge === "left") return Qt.matrix4x4(0, -1, 0, T,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1);  // turned 90°
            if (edge === "right") return Qt.matrix4x4(0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1);  // turned + mirrored
            return Qt.matrix4x4();
        }
        // Undoes stripMatrix for an item of size w × h (about its centre), keeping it upright
        function upright(w, h) {
            const cx = w / 2, cy = h / 2;
            if (edge === "top") return Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, h,  0, 0, 1, 0,  0, 0, 0, 1);
            if (edge === "left") return Qt.matrix4x4(0, 1, 0, cx - cy,  -1, 0, 0, cy + cx,  0, 0, 1, 0,  0, 0, 0, 1);
            if (edge === "right") return Qt.matrix4x4(0, 1, 0, cx - cy,  1, 0, 0, cy - cx,  0, 0, 1, 0,  0, 0, 0, 1);
            return Qt.matrix4x4();
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "slate-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region { item: maskBox }
        // The input area in window coordinates (hitArea is in the turned strip)
        Item {
            id: maskBox
            readonly property var box: {
                win.stripMatrix; hitArea.x; hitArea.y; hitArea.width; hitArea.height;   // re-evaluate on these
                const a = hitArea.mapToItem(win.contentItem, 0, 0), b = hitArea.mapToItem(win.contentItem, hitArea.width, hitArea.height);
                return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) };
            }
            x: box.x; y: box.y; width: box.w; height: box.h
            // A press on the dock closes an open bar panel, as a press anywhere else outside it
            // does (the panel leaves the dock to take the pointer: Popouts.qml). Only watches:
            // the press still goes on to what's under it
            PointHandler {
                acceptedButtons: Qt.AllButtons
                onActiveChanged: if (active && popouts.engaged) popouts.close()
            }
        }
        // The same, for the bar's panels to leave a hole for
        readonly property rect inputRect: Qt.rect(maskBox.x, maskBox.y, maskBox.width, maskBox.height)

        // ---- Apps: pinned first, then anything else that's running ---------
        function belongsTo(t, id, e) {
            const a = (t.appId || "").toLowerCase();
            if (a === id.toLowerCase()) return true;
            if (!e) return false;
            if (a === (e.startupClass || "").toLowerCase() || a === (e.id || "").toLowerCase()) return true;
            const h = Config.appEntry(t.appId);
            return h !== null && h.id === e.id;
        }
        property var items: {
            DesktopEntries.applications.values;   // rebuild once app entries have loaded
            const tops = ToplevelManager.toplevels.values;
            const out = [];
            const claimed = new Set();
            for (const id of pinned) {
                const e = Config.appEntry(id);
                const wins = tops.filter(t => !claimed.has(t) && belongsTo(t, id, e));
                if (!e && wins.length === 0) continue;   // pinned app that's no longer installed
                wins.forEach(t => claimed.add(t));
                out.push({ key: id, entry: e, windows: wins, pinned: true });
            }
            for (const t of tops) {
                if (claimed.has(t)) continue;
                const e = Config.appEntry(t.appId);
                const key = e ? e.id : t.appId;
                const existing = out.find(o => o.key === key);
                if (existing) existing.windows.push(t);
                else out.push({ key: key, entry: e, windows: [t], pinned: false });
            }
            return out;
        }

        // ---- Magnification -------------------------------------------------
        // ---- The dock's slots, in order ---------------------------------------------
        // The Apps button, what's playing (while something is) and a divider, the pinned apps, a
        // divider, the other running apps, a divider, Downloads and the Waste Basket. Each slot knows its
        // place (at); everything that finds or places one goes through this list
        readonly property var slots: slotsFor(foldPlan.folded)
        // The slots with the apps named in `folded` (keys) gathered into More, after the other apps
        function slotsFor(folded) {
            const s = [];
            const add = o => { o.at = s.length; s.push(o); };
            if (Config.s.dockShowLauncher) add({ kind: "launcher" });
            if (mediaShown) add({ kind: "media" });
            const dividers = Config.s.dockDivider;
            // (the app being dragged is held by the pointer, not in the dock, until it's let go)
            const all = items.filter(it => it.key !== dragKey);
            const away = new Set(folded);
            const shown = all.filter(it => !away.has(it.key));
            const more = all.filter(it => away.has(it.key));
            // after the Apps button and what's playing (while either is there)
            if (dividers && s.length > 0 && all.length > 0) add({ kind: "divider" });
            shown.forEach((it, i) => {
                // between the pinned apps and the others (when there are both)
                if (dividers && i > 0 && !it.pinned && shown[i - 1].pinned) add({ kind: "divider" });
                add({ kind: "app", item: it });
            });
            if (more.length > 0) add({ kind: "more", items: more });
            if (dividers && all.length > 0 && (downloadsShown || trashShown)) add({ kind: "divider" });
            if (downloadsShown) add({ kind: "downloads" });
            if (trashShown) add({ kind: "trash" });
            return s;
        }

        // ---- When the dock doesn't fit ----------------------------------------------------
        // The icons shrink to fit the edge (base), but no smaller than foldFloor: 24 px, the
        // smallest a thing you click should be (WCAG 2.2, 2.5.8), or your own size if that's
        // smaller. Past that, things fold away, least wanted first, until it fits: what's
        // playing goes to one icon, then the apps you haven't pinned go into More (the oldest
        // first: the dock lists them in the order they opened), and only then, as a last
        // resort, your pinned apps (the first pinned first). The Apps button, Downloads and the
        // Waste Basket stay. Worked out from the apps and the room, never from base or slots
        readonly property real foldFloor: Math.min(24, Config.s.dockIconSize)
        function iconsIn(list, compact) {
            let n = 0;
            for (const o of list) n += o.kind === "media" ? (vertical || compact ? 1 : mediaArt ? 3.2 : 2.4) : o.kind === "divider" ? dividerWide : 1;
            return n;
        }
        function sizeFor(list, compact) {
            return (roomLength - 48 - padding * 2 - (list.length - 1) * spacing) / Math.max(1, iconsIn(list, compact));
        }
        readonly property var foldPlan: {
            if (roomLength <= 0) return { compact: false, folded: [] };
            const fits = (compact, folded) => sizeFor(slotsFor(folded), compact) >= foldFloor;
            if (fits(false, [])) return { compact: false, folded: [] };
            const compact = mediaShown && !vertical;
            if (fits(compact, [])) return { compact: compact, folded: [] };
            const all = items.filter(it => it.key !== dragKey);
            const order = all.filter(it => !it.pinned).concat(all.filter(it => it.pinned));
            const folded = [];
            for (const it of order) {
                folded.push(it.key);
                if (fits(compact, folded)) break;
            }
            return { compact: compact, folded: folded };
        }
        readonly property var moreItems: { const m = slots.find(o => o.kind === "more"); return m ? m.items : []; }
        readonly property int moreIndex: indexOfKind("more")
        // More's badge: the folded apps' counts added up ("!" if any asks for attention)
        readonly property var moreBadge: {
            let count = 0, urgent = false;
            for (const it of moreItems) { const b = badgeFor(it); count += b.count; urgent = urgent || b.urgent; }
            return { count: count, progress: -1, urgent: urgent };
        }
        // The slots drawn by the apps' Repeater: the apps and the dividers between them
        readonly property var middleSlots: slots.filter(x => x.kind === "app" || x.kind === "divider" || x.kind === "more")
        function slotAt(i) { return i >= 0 && i < slots.length ? slots[i] : null; }
        function indexOfKind(kind) { const x = slots.find(o => o.kind === kind); return x ? x.at : -1; }
        readonly property int count: slots.length
        readonly property real dividerWide: 0.35     // a divider's width, in icons

        // ---- Badges and progress (Settings → Dock → Badges and progress) -------------
        // What apps publish for their icons (an unread count, how far a download or copy has
        // got, a call for attention: scripts/launcher-entries.py), and for apps that don't, how
        // many of their notifications are unread
        property var launcherEntries: ({})       // app id (lower case) → its latest state
        Process {
            running: Config.s.dockBadges
            command: [Quickshell.shellPath("scripts/launcher-entries.py")]
            stdout: SplitParser {
                onRead: line => {
                    try {
                        const e = JSON.parse(line);
                        const m = Object.assign({}, win.launcherEntries);
                        m[e.app.toLowerCase()] = e;
                        win.launcherEntries = m;
                    } catch (err) {}
                }
            }
        }
        // The app you're in: its notifications count as seen as you look at it (the one you
        // leave and the one you go to are both marked), so its badge clears and stays clear
        readonly property string focusedAppId: {
            const t = ToplevelManager.activeToplevel;
            const it = t ? items.find(o => o.windows.includes(t)) : null;
            return it ? (it.entry ? it.entry.id : it.key) : "";
        }
        property string lastFocusedAppId: ""
        onFocusedAppIdChanged: { notifs.markAppSeen(lastFocusedAppId); notifs.markAppSeen(focusedAppId); lastFocusedAppId = focusedAppId; }
        // An app's badge: { count (0: none), progress (0…1, or -1: none), urgent }
        function badgeFor(app) {
            if (!Config.s.dockBadges || !app || !app.key) return { count: 0, progress: -1, urgent: false };
            const id = app.entry ? app.entry.id : app.key;
            const le = launcherEntries[id.toLowerCase()] || launcherEntries[app.key.toLowerCase()] || null;
            const published = le && le.countVisible && le.count > 0 ? le.count : 0;
            const unread = id === focusedAppId ? 0 : notifs.unreadByApp[id] || 0;
            return { count: published || unread, progress: le && le.progressVisible ? Math.max(0, Math.min(1, le.progress || 0)) : -1, urgent: !!(le && le.urgent) };
        }

        // ---- Downloads (Settings → Dock → Downloads) -------------------------------
        // A stack before the Waste Basket: click for a grid of the newest downloads (pictures
        // as thumbnails), right-click to open the folder. The folder is the desktop's own
        // (xdg-user-dir DOWNLOAD), else ~/Downloads
        readonly property bool downloadsShown: Config.s.dockShowDownloads && downloadsDir !== ""
        property string downloadsDir: ""
        Process {
            running: Config.s.dockShowDownloads && win.downloadsDir === ""
            command: ["sh", "-c", "d=$(xdg-user-dir DOWNLOAD 2>/dev/null); [ -n \"$d\" ] && [ \"$d\" != \"$HOME\" ] && echo \"$d\" || echo \"$HOME/Downloads\""]
            stdout: StdioCollector { onStreamFinished: win.downloadsDir = text.trim() }
        }
        FolderListModel {
            id: downloadsFiles
            folder: win.downloadsShown ? "file://" + win.downloadsDir : ""
            showDirs: true; showHidden: false; showDotAndDotDot: false
            sortField: FolderListModel.Time          // newest first
        }
        // The newest 24, without downloads still arriving (.part, .crdownload…). However big the
        // folder (it's read in the background), only these are ever looked at; the grid shows
        // three rows and scrolls for the rest, and Open Downloads is there for everything
        readonly property var recentDownloads: {
            const out = [];
            for (let i = 0; i < downloadsFiles.count && out.length < 24; i++) {
                const name = downloadsFiles.get(i, "fileName");
                if (/\.(part|crdownload|download|tmp)$/i.test(name)) continue;
                out.push({ name: name, path: downloadsFiles.get(i, "filePath"), dir: downloadsFiles.get(i, "fileIsDir") });
            }
            return out;
        }
        // How a download is shown: pictures as themselves, the rest as a glyph for their kind
        function downloadKind(d) {
            if (d.dir) return { glyph: 0xEAAD };
            const ext = (d.name.split(".").pop() || "").toLowerCase();
            if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "svg"].includes(ext)) return { image: true };
            if (ext === "pdf") return { glyph: 0xFB10 };
            if (["zip", "tar", "gz", "xz", "bz2", "zst", "7z", "rar", "deb", "rpm", "appimage", "iso"].includes(ext)) return { glyph: 0xED4E };
            if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"].includes(ext)) return { glyph: 0xEAFC };
            if (["mp4", "mkv", "webm", "mov", "avi", "m4v"].includes(ext)) return { glyph: 0xEAFA };
            if (["sh", "py", "js", "ts", "json", "lua", "c", "cpp", "h", "rs", "go", "qml", "html", "css"].includes(ext)) return { glyph: 0xEBD0 };
            if (["txt", "md", "log", "csv", "doc", "docx", "odt", "rtf"].includes(ext)) return { glyph: 0xEAA2 };
            return { glyph: 0xEAA4 };
        }
        function openDownloads() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. FILE_MANAGER .. " '${downloadsDir.replace(/'/g, "")}'") end`]);
        }

        // ---- Media (Settings → Dock → Media controls) ----------------------------------
        // What's playing, right after the launcher button, while a media app has a track: its
        // album art, with Previous / Play-Pause / Next across it under the pointer
        readonly property var player: Mpris.players.values.find(p => p.isPlaying)
            ?? Mpris.players.values.find(p => (p.trackTitle || "") !== "") ?? null
        readonly property bool mediaShown: Config.s.dockShowMedia && !!player && (player.trackTitle || "") !== ""
        readonly property int mediaIndex: indexOfKind("media")
        // How many icons wide it is: along a bottom or top dock, a rectangle with the album art
        // and the controls beside it; on a side dock, one icon (the controls show over the art
        // under the pointer), as a wide tile doesn't fit there
        readonly property bool mediaArt: Config.s.dockMediaArt     // Settings → Dock → Album art
        // (one icon, too, when the dock is too long for the edge: foldPlan)
        readonly property real mediaWide: vertical || foldPlan.compact ? 1 : mediaArt ? 3.2 : 2.4
        // Where the track is (for the progress bar): players don't announce it as it moves, so
        // it's asked for each second while the bar can be seen
        Timer {
            interval: 1000; repeat: true
            running: win.mediaShown && win.shown && !!win.player && win.player.isPlaying && win.mediaWide > 1
            onTriggered: win.player.positionChanged()
        }
        // A click on it. Wide: the art goes to the app playing, then Previous / Play-Pause /
        // Next in thirds of the rest. One icon: Previous on its left third, Next on its right
        // Which part of it the pointer's on: "art" (wide), "previous", "toggle" or "next"
        function mediaControlAt() {
            // 0 … 1 across it, as it's drawn
            const along = (pointerStripX - row.x - cellX(mediaIndex)) / Math.max(1, base * mediaWide * scaleAt(mediaIndex));
            if (mediaWide > 1) {
                const art = mediaArt ? 1 / mediaWide : 0;        // the art: a square at the start
                if (along <= art) return "art";
                const third = (along - art) / (1 - art);
                return third < 1 / 3 ? "previous" : third > 2 / 3 ? "next" : "toggle";
            }
            return along < 1 / 3 ? "previous" : along > 2 / 3 ? "next" : "toggle";
        }
        // Go to the app that's playing: its window if one's open (by the app the player names),
        // else asking the player to show itself
        function showPlayer() {
            const p = player;
            if (!p) return;
            const id = (p.desktopEntry || "").toLowerCase(), name = (p.identity || "").toLowerCase();
            const app = items.find(it => it.windows.length > 0 && (
                (id !== "" && (it.key.toLowerCase() === id || (it.entry && it.entry.id.toLowerCase() === id)))
                || (name !== "" && it.entry && (it.entry.name || "").toLowerCase() === name)));
            if (app) app.windows[0].activate();
            else if (p.canRaise) p.raise();
        }
        function mediaClick() {
            const p = player;
            if (!p) return;
            const control = mediaControlAt();
            if (control === "art") { showPlayer(); return; }
            if (control === "previous") { if (p.canGoPrevious) p.previous(); }
            else if (control === "next") { if (p.canGoNext) p.next(); }
            else if (p.canTogglePlaying) p.togglePlaying();
        }

        // ---- Waste Basket (Settings → Dock → Waste Basket) ----------------------------
        // The bin after the apps: click to open it in the file manager, right-click to empty
        // it. The desktop's own (freedesktop) trash, so it's the same bin the file managers use
        readonly property bool trashShown: Config.s.dockShowTrash
        readonly property int trashIndex: indexOfKind("trash")         // always last
        readonly property int downloadsIndex: indexOfKind("downloads")
        readonly property int launcherIndex: indexOfKind("launcher")       // (-1: switched off)
        readonly property string trashDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"
        // What's in it, watched (the folder made first if nothing's been thrown away yet, so
        // there's something to watch)
        property bool trashReady: false
        Process {
            running: win.trashShown && !win.trashReady
            command: ["mkdir", "-p", win.trashDir]
            onExited: win.trashReady = true
        }
        FolderListModel {
            id: trashFiles
            folder: win.trashShown && win.trashReady ? "file://" + win.trashDir : ""
            showDirs: true; showHidden: true; showDotAndDotDot: false
        }
        readonly property int trashCount: trashShown ? trashFiles.count : 0
        // Opened in the file manager the shortcuts use (FILE_MANAGER, Hyprland's variable)
        function openTrash() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. FILE_MANAGER .. " trash:///") end`]);
        }
        function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]); }
        // Slots along the dock: each an icon wide, except what's playing (mediaWide). Where one
        // starts at rest, and how wide it is in icons
        function slotWidth(i) {
            const k = slotAt(i) ? slotAt(i).kind : "";
            return k === "media" ? mediaWide : k === "divider" ? dividerWide : 1;
        }
        // Where each slot starts at rest (worked out once per change of the slots)
        readonly property var slotStarts: {
            const out = [];
            let x = 0;
            for (let i = 0; i < slots.length; i++) { out.push(x); x += slotWidth(i) * base + spacing; }
            out.push(x - spacing);                   // the end
            return out;
        }
        function slotStart(i) { return slotStarts[Math.max(0, Math.min(i, slotStarts.length - 1))]; }
        readonly property real restWidth: Math.max(0, slotStarts[slotStarts.length - 1])
        property real pointerX: -1000                          // in rest-layout coordinates (for magnifying)
        // Where the pointer is along the strip itself: what's under it is worked out from where
        // the slots are actually drawn (magnified), so a wide slot (what's playing) answers over
        // all of it, not just over the space it would take at rest
        property real pointerStripX: -1000
        // The pointer's moved to sx along the strip
        function setPointer(sx) {
            pointerStripX = sx;
            pointerX = sx - (strip.width - restWidth) / 2;
        }
        // Magnification stays frozen while the right-click menu is open
        property real hover: (mouse.containsMouse && shown) || appMenu.visible || dragKey !== "" || fileDrag || testHover ? 1 : 0
        property bool testHover: false      // the test suite pointing at a slot (ipc call test dockHover <slot>)
        Behavior on hover { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }

        function scaleAt(i) {
            const w = slotWidth(i);
            const centre = slotStart(i) + w * base / 2;
            // (from its nearest edge, for a wide slot: it grows as soon as the pointer's on it)
            const t = Math.max(0, Math.abs(pointerX - centre) - (w - 1) * base / 2) / (base * spread);
            const f = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return 1 + (maxScale - 1) * f * hover;
        }
        // Tilt: with the pointer on the dock, the icons turn in 3D towards it, the ones near it
        // straightening up to face you (fully under it, over the same spread as magnifying); all
        // upright once it leaves. With tilt alone, the one under the pointer lifts a little
        // instead of growing
        function tiltOffset(i) {
            const w = slotWidth(i);
            const centre = slotStart(i) + w * base / 2;
            return (pointerX - centre) / (base * spread);
        }
        readonly property real tiltMax: 40           // degrees, for the icons away from the pointer
        // Towards a point (rest-layout x), straightening up close to it
        function tiltTowards(i, x) {
            const d = (x - (slotStart(i) + slotWidth(i) * base / 2)) / (base * spread);
            const near = Math.abs(d) >= 1 ? 0 : (Math.cos(Math.PI * d) + 1) / 2;
            return tiltMax * Math.sign(d) * (1 - near);
        }
        // Dividers keep still whatever the effect (no lift, tilt, fade or glow)
        function isDivider(i) { const sl = slotAt(i); return !!sl && sl.kind === "divider"; }
        function tiltAt(i) {
            if (!tilts || i < 0 || isDivider(i)) return 0;
            return tiltTowards(i, pointerX) * hover;        // (upright while the pointer's away)
        }
        // The tilt as a 3D turn with real perspective: turned about the icon's middle, seen from
        // close by (a couple of icons away), so the edge turned away is clearly shorter and the
        // near one taller. (Qt's own Rotation looks from much further, so small icons barely change)
        function tiltMatrix(w, h, deg) {
            const a = deg * Math.PI / 180, c = Math.cos(a), sn = Math.sin(a);
            // (about the middle of the icon's tile, which sits at the bottom of its slot)
            const d = Math.max(1, base * 2.2), ox = w / 2, oy = h - Math.min(w, h) / 2, k = sn / d;
            return Qt.matrix4x4(c + ox * k, 0, 0, ox * (1 - k * ox) - c * ox,
                                oy * k,     1, 0, oy * (1 - k * ox) - oy,
                                0,          0, 1, 0,
                                k,          0, 0, 1 - k * ox);
        }
        function liftAt(i) {
            if (i < 0 || isDivider(i)) return 0;
            if (hoverEffect === "raise") return i === raisedIndex ? base * 0.28 : 0;
            if (hoverEffect !== "tilt") return 0;
            const t = Math.abs(tiltOffset(i));
            return t >= 1 ? 0 : base * 0.16 * (Math.cos(Math.PI * t) + 1) / 2 * hover;
        }
        function cellX(i) {
            let x = 0;
            for (let j = 0; j < i; j++) x += base * slotWidth(j) * scaleAt(j) + spacing;
            return x;
        }
        readonly property int hoveredIndex: {
            if (hover <= 0) return -1;
            const x = pointerStripX - row.x;                   // along the drawn row
            let start = 0;
            for (let i = 0; i < count; i++) {
                const end = start + base * slotWidth(i) * scaleAt(i);
                if (x < end + spacing / 2) return x >= start - spacing / 2 ? i : -1;
                start = end + spacing;
            }
            return -1;
        }

        // ---- Auto-hide -----------------------------------------------------
        // Something on the workspace the dock would cover: a tiled window. Floating ones don't
        // count (the dock stays open over a workspace of just floating windows), except in
        // floating windows mode, where every window floats. A window whose details Hyprland
        // hasn't given yet (one just opened) doesn't count until they come, a moment later:
        // counted as tiled, a new floating window briefly hid the dock
        readonly property bool workspaceBusy: {
            const tops = Hyprland.focusedWorkspace?.toplevels?.values ?? [];
            if (Config.floatingWindows) return tops.length > 0;
            return tops.some(t => t.lastIpcObject && t.lastIpcObject.floating === false);
        }
        // Which windows float comes from Hyprland's window details: fetched again when a window
        // opens, moves or changes floating (only while that matters to the dock)
        Connections {
            target: Hyprland
            enabled: Config.s.dockAutoHide && !Config.floatingWindows
            function onRawEvent(event) {
                switch (event.name) {
                case "openwindow": case "changefloatingmode": case "movewindow": case "movewindowv2":
                    floatCheck.restart();
                }
            }
        }
        // (and once at start, so the windows already open have their details)
        Timer { id: floatCheck; interval: 30; running: true; onTriggered: Hyprland.refreshToplevels() }
        property bool shown: !movingOut && (!Config.s.dockAutoHide || (!workspaceBusy && !appLauncher.launchingNew) || mouse.containsMouse || holdTimer.running || movedHold.running || appMenu.visible || previewPop.visible || dragKey !== "" || fileDrag)
        Timer { id: holdTimer; interval: win.hideDelay }
        // Moved to another edge: it shows there for a moment (even with auto-hide), so you see
        // where it went. Meanwhile it's kept out of sight until its window has moved: drawn for
        // its new edge while still at the old one, it flickered there
        Timer { id: movedHold; interval: 1500 }
        property bool relocating: false
        Timer { id: relocated; interval: 120; onTriggered: win.relocating = false }
        onEdgeChanged: { relocating = true; relocated.restart(); movedHold.restart(); }
        readonly property real dockHeight: base + padding * 2
        property real offset: shown ? 0 : dockHeight + bottomGap + 4
        Behavior on offset { NumberAnimation { duration: Config.ms(260); easing.type: Easing.OutCubic } }

        // Open an app's menu by its key, e.g.  slate ipc call dock menu firefox
        IpcHandler {
            target: "dock"
            function menu(key: string): void {
                const sl = win.slots.find(o => o.kind === "app" && o.item.key === key);
                if (!sl) return;
                const x = (strip.width - win.restWidth) / 2 + win.slotStart(sl.at) + win.base / 2;
                appMenu.openFor(sl.item, x);
            }
            function closeMenu(): void { appMenu.closeMenu(); }
            // An app's window previews, as pausing on it does:  slate ipc call dock preview firefox
            function preview(key: string): void {
                const sl = win.slots.find(o => o.kind === "app" && o.item.key === key);
                if (!sl || sl.item.windows.length === 0 || win.previewMode === "off") return;
                win.previewApp = sl.item;
                const x = (strip.width - win.restWidth) / 2 + win.slotStart(sl.at) + win.base / 2;
                const p = strip.mapToItem(win.contentItem, x, win.previewEdge(sl.at));
                const sw = win.screen ? win.screen.width : 0, sh = win.screen ? win.screen.height : 0;
                previewPop.atX = p.x + (win.edge === "right" ? sw - win.width : 0);
                previewPop.atY = p.y + (win.edge === "bottom" ? sh - win.height : 0);
            }
            function closePreview(): void { win.previewApp = null; }
            // The Downloads stack's grid, as clicking it does:  slate ipc call dock downloads
            function downloads(): void {
                if (!win.downloadsShown) return;
                const i = win.downloadsIndex;
                appMenu.openFor({ downloadsGrid: true, key: "", windows: [] }, (strip.width - win.restWidth) / 2 + win.slotStart(i) + win.base / 2);
            }
            // More's grid (the apps that don't fit), as clicking it does:  slate ipc call dock more
            function more(): void {
                const i = win.moreIndex;
                if (i < 0) return;
                appMenu.openFor({ moreGrid: true, key: "", windows: [] }, (strip.width - win.restWidth) / 2 + win.slotStart(i) + win.base / 2);
            }
        }

        // ---- Right-click menu ----------------------------------------------
        // A full-screen invisible layer while open: clicking anywhere outside the menu
        // (or pressing Escape) closes it
        // ---- Dragging --------------------------------------------------------------
        // An app picked up from the dock leaves its place and follows the pointer (dragPop, a
        // layer of its own). Over the pinned apps, they part to show where it'll go (a gap with
        // a faint tile in it); let go there and it glides in, pinned at that place: a running
        // app that wasn't pinned is pinned by it. Pulled well up off the dock, a pinned app is
        // let go of to unpin it (it stays with the running apps while it's open). Anywhere else,
        // a running app goes back where it was. Files dragged in from a file manager: onto the
        // Waste Basket to bin them, onto an app to open them in it
        property string dragCandidate: ""        // the app pressed on (dragging once it moves)
        property string dragKey: ""              // the app being dragged (not in the slots meanwhile)
        property bool dragPinned: false          // it was pinned when picked up
        property bool dragAway: false            // pulled well off the dock: letting go unpins it
        readonly property bool dragRunning: dragKey !== "" && (items.find(o => o.key === dragKey)?.windows.length ?? 0) > 0
        property int dropIndex: -1               // where it'd go among the pinned apps (-1: nowhere)
        property point dragScreen: Qt.point(0, 0)   // the pointer, in screen coordinates
        property bool landing: false             // let go: gliding into its place
        property bool settling: false            // the gap appearing or closing at once, not animated
        property bool fileDrag: false            // files being dragged over the dock
        // How far up off the dock (the pointer, past its top) before letting go unpins
        readonly property real removeDistance: Math.max(120, base * 2.5)
        // The pinned apps' slots as they are now (the dragged one isn't among them)
        readonly property var pinnedSlots: slots.filter(o => o.kind === "app" && o.item.pinned)
        // The slot the gap opens before (every slot from it on moves along), or -1
        readonly property int gapAt: {
            if (dragKey === "" || dropIndex < 0) return -1;
            if (pinnedSlots.length === 0) {
                // None pinned: where the apps begin (with none running either, the dividers go too:
                // just after the Apps button)
                const first = slots.find(o => o.kind === "app" || o.kind === "divider");
                if (first) return first.at;
                const apps = slots.find(o => o.kind === "launcher");
                return apps ? apps.at + 1 : 0;
            }
            return dropIndex < pinnedSlots.length ? pinnedSlots[dropIndex].at : pinnedSlots[pinnedSlots.length - 1].at + 1;
        }
        // The gap grows with the pointer as the icons do (where it sits at rest: between the
        // slots either side of it); opening, closing and moving it slide (gapOpen, each cell's own)
        readonly property real gapScale: {
            if (gapAt < 0) return 1;
            const t = Math.abs(pointerX - (slotStart(gapAt) - spacing / 2)) / (base * spread);
            const f = t >= 1 ? 0 : (Math.cos(Math.PI * t) + 1) / 2;
            return 1 + (maxScale - 1) * f * hover;
        }
        readonly property real gapWidth: base * gapScale
        property real gapOpen: gapAt >= 0 ? 1 : 0
        Behavior on gapOpen { enabled: !win.settling; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
        // Where the gap's tile is, as a slot index that slides between whole ones when it moves
        property real gapPos: 0
        onGapAtChanged: if (gapAt >= 0) gapPos = gapAt
        Behavior on gapPos { enabled: !win.settling && win.gapOpen > 0.01; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
        // A window point (the dock's own window) as a point on the screen
        // Where a menu points from, for something at x along the dock (strip coordinates): just
        // past the icon under the pointer, magnified as it is (or the dock's inner side, for its
        // empty space), leaving room for the menu's pointer (screen coordinates)
        function menuPoint(x) {
            const icon = hoveredIndex >= 0 && slotAt(hoveredIndex) && slotAt(hoveredIndex).kind !== "divider" ? base * scaleAt(hoveredIndex) : 0;
            return toScreen(strip.mapToItem(win.contentItem, x, Math.min(bg.y - 16, row.y + row.height - icon - 14)));
        }
        function toScreen(pt) {
            const sw = screen ? screen.width : 0, sh = screen ? screen.height : 0;
            return Qt.point(pt.x + (edge === "right" ? sw - width : 0), pt.y + (edge === "bottom" ? sh - height : 0));
        }
        function startDrag(key) {
            const it = items.find(o => o.key === key);
            if (!it) return;
            settling = true;                     // the gap opens where it was, at once
            dragPinned = it.pinned;
            dragKey = key;
            previewApp = null;
            // nothing else open over the dock while dragging (More's grid stays, out of sight:
            // the drag began in it)
            if (!dragFromMore) appMenu.closeMenu();
            Qt.callLater(() => { settling = false; });
        }
        // An app dragged out of More's grid (appMenu) onto the dock: the grid's window keeps the
        // pointer (it was pressed there), so the grid hands the dock the pointer's place (on the
        // screen, in Slate's units: the menu covers the screen) and the dock's own drag does the
        // rest, the gap opening where it'd land. Let go over the dock: pinned at that place;
        // anywhere else, nothing changes and it stays in More. The menu stays open (its cards
        // faded away, appMenu.lifted) until it's let go, or the pointer would go with it
        property bool dragFromMore: false
        readonly property real dragThreshold: 8      // how far the pointer moves before a press is a drag
        function pickFromMore(key) {
            if (dragKey !== "" || !moreItems.some(it => it.key === key)) return;
            dragFromMore = true;
            appMenu.lifted = true;
            startDrag(key);
        }
        // The pointer at sp (in the menu's window: the screen, in Slate's units)
        function carryFromMore(sp) {
            if (!dragFromMore || landing) return;
            dragScreen = sp;
            const sw = screen ? screen.width : 0, sh = screen ? screen.height : 0;
            const p = win.contentItem.mapToItem(strip, sp.x - (edge === "right" ? sw - width : 0), sp.y - (edge === "bottom" ? sh - height : 0));
            setPointer(p.x);
            dragTo(p);
        }
        function dropFromMore() {
            if (!dragFromMore) return;
            dragFromMore = false;
            endDrag();
            appMenu.closeMenu();
        }
        function dragTo(stripPoint) {
            if (dragFromMore) {
                // Over the dock (its icons as they'd grow, and not off either end), it'd be pinned
                // at the place among the pinned apps it's nearest; anywhere else, nowhere
                dragAway = false;
                const x = stripPoint.x - (strip.width - restWidth) / 2;
                const over = stripPoint.y >= bg.y - base * maxScale && x >= -base && x <= restWidth + base;
                const ps = pinnedSlots;
                let i = 0;
                while (i < ps.length && x > slotStart(ps[i].at) + base / 2) i++;
                dropIndex = over ? i : -1;
                return;
            }
            dragAway = dragPinned && stripPoint.y < bg.y - removeDistance;
            const offDock = stripPoint.y < bg.y - base * maxScale;
            if (dragAway || (!dragPinned && offDock)) { dropIndex = -1; return; }
            // Which pinned apps it's past (at rest, so the place doesn't jitter as icons part)
            const x = stripPoint.x - (strip.width - restWidth) / 2;
            const ps = pinnedSlots;
            let i = 0;
            while (i < ps.length && x > slotStart(ps[i].at) + base / 2) i++;
            // Where the pinned apps end and the running ones begin (with none pinned: where the
            // apps begin)
            const firstApp = slots.find(o => o.kind === "app");
            const pinnedEnd = ps.length ? slotStart(ps[ps.length - 1].at) + base
                : firstApp ? slotStart(firstApp.at) : restWidth;
            // A pinned app stays among the pinned ones (pulled off the dock to unpin); a running one
            // only goes in among them, else back where it was
            // (a running app off either end of the dock isn't over it at all)
            const beside = x < -base || x > restWidth + base;
            dropIndex = dragPinned || (x < pinnedEnd + base * 0.5 && !beside) ? i : -1;
        }
        function endDrag() {
            if (dragKey === "") { dragCandidate = ""; return; }
            if (dragAway) finishDrag();         // unpinned: back among the running apps if it's open
            else if (dropIndex >= 0) {
                // Glide into the gap, at its size, then take its place
                const c = dragGap.mapToItem(win.contentItem, dragGap.width / 2, dragGap.height / 2);
                const t = toScreen(c);
                dragPop.landAt(t.x, t.y, dragGap.width);
            } else finishDrag();                // back where it was
        }
        function finishDrag() {
            settling = true;
            if (dragAway) setPinned(dragKey, false);
            else if (dropIndex >= 0) {
                const list = pinned.filter(k => k !== dragKey);
                list.splice(dropIndex, 0, dragKey);
                pinned = list;
                savePinned();
            }
            dragKey = ""; dragCandidate = ""; dragAway = false; dropIndex = -1; landing = false;
            Qt.callLater(() => { settling = false; });
        }
        // Files let go of over slot i
        function dropFiles(i, urls) {
            const sl = slotAt(i);
            const paths = urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(p => p.startsWith("/"));
            if (!sl || paths.length === 0) return false;
            if (sl.kind === "trash") { Quickshell.execDetached(["gio", "trash"].concat(paths)); return true; }
            if (sl.kind === "app" && sl.item.entry) {
                Quickshell.execDetached([Quickshell.shellPath("scripts/open-with.sh"), sl.item.entry.id].concat(paths));
                return true;
            }
            return false;
        }

        // ---- Window previews (Settings → Dock → Window previews) -----------------------
        // Pause on an app with windows open (for Settings' number of seconds; 0: at once) and a
        // panel shows a card for each: a live picture of it, or in game mode (no live pictures)
        // its title and the app's icon; click one to go to it. It stays while the pointer moves
        // onto it
        readonly property string previewMode: !Config.s.dockPreviews ? "off" : Config.gameMode ? "titles" : "live"
        property var previewApp: null            // the app being previewed ({ key, entry, windows })
        property bool previewHeld: false         // the pointer's on the panel
        Timer { id: previewDwell; interval: Math.max(1, Config.s.dockPreviewDelay * 1000); onTriggered: win.showPreview() }
        Timer { id: previewLeave; interval: 300; onTriggered: if (!win.previewHeld && !win.pointedApp) win.previewApp = null }
        // The app under the pointer, while it has windows (null otherwise)
        readonly property var pointedApp: {
            const sl = hover > 0.5 && !appMenu.visible ? slotAt(hoveredIndex) : null;
            return sl && sl.kind === "app" && sl.item.windows.length > 0 ? sl.item : null;
        }
        onPointedAppChanged: {
            if (previewMode === "off") return;
            if (pointedApp && previewApp) showPreview();       // already showing: switch at once
            else if (pointedApp) previewDwell.restart();
            else { previewDwell.stop(); previewLeave.restart(); }
        }
        // Where window previews sit (strip coordinates) for the icon in slot `at`: a little above
        // the highest point of its name label (which sits above the icon, as big as the icon is
        // just now), or above the dock when that's higher still. With no label showing (opened
        // by `dock preview`), where one would be
        function previewEdge(at) {
            const icon = base * scaleAt(at);
            const reach = hoveredIndex === at && label.text !== "" ? label.across : label.height;     // the label, away from the icon
            return Math.min(bg.y - 16, row.y + row.height - icon - 8 - reach - 8);
        }
        function showPreview() {
            if (dragKey !== "" || mouse.pressed) return;     // not while an app's being dragged
            const sl = slots.find(o => o.kind === "app" && pointedApp && o.item.key === pointedApp.key);
            if (!sl) return;
            previewApp = sl.item;
            const p = strip.mapToItem(win.contentItem, row.x + cellX(sl.at) + base * scaleAt(sl.at) / 2, win.previewEdge(sl.at));
            const sw = win.screen ? win.screen.width : 0, sh = win.screen ? win.screen.height : 0;
            previewPop.atX = p.x + (win.edge === "right" ? sw - win.width : 0);
            previewPop.atY = p.y + (win.edge === "bottom" ? sh - win.height : 0);
        }
        Connections {
            target: appMenu
            function onVisibleChanged() {
                if (appMenu.visible) win.previewApp = null;
                // (More's grid closed mid-drag, by Escape or going to another workspace: let go
                // where it isn't over the dock, so nothing changes)
                else if (win.dragFromMore) { win.dropIndex = -1; win.dropFromMore(); }
            }
        }

        PanelWindow {
            id: dragPop
            screen: win.screen
            visible: win.dragKey !== ""
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "slate-dock-drag"
            WlrLayershell.layer: WlrLayer.Overlay
            mask: Region {}                             // the pointer goes straight through it
            // Held at its magnified size; lands at the gap's
            readonly property real liftSize: win.base * win.maxScale
            // Let go over the gap: glide to (x, y) (screen coordinates, its centre) at size s, then
            // take its place
            // Landed: it takes its place, and the floater goes back to following the pointer
            function landed() {
                win.finishDrag();
                floater.width = Qt.binding(() => dragPop.liftSize);
                floater.x = Qt.binding(() => win.dragScreen.x - floater.width / 2);
                floater.y = Qt.binding(() => win.dragScreen.y - floater.height / 2);
            }
            function landAt(x, y, s) {
                win.landing = true;
                landX.to = x - s / 2; landY.to = y - s / 2; landW.to = s;
                land.restart();
            }
            Item {
                id: floater
                width: dragPop.liftSize; height: width
                x: win.dragScreen.x - width / 2
                y: win.dragScreen.y - height / 2
                // Pulled far enough off the dock to unpin: fading, as it's about to go
                opacity: win.dragAway ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                Image {
                    anchors.fill: parent
                    source: win.dragKey ? "file://" + Config.tilePath(win.dragKey) + "?v=" + Config.tileVersion : ""
                    sourceSize: Qt.size(192, 192)
                    smooth: true; mipmap: true
                    layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                    IconPlate { anchors.fill: parent; z: -1; drawSize: win.base * win.maxScale }
                    IconGloss {}
                }
            }
            // Pulled far enough to unpin it: says so, above it, as a warning (the theme's soft red)
            Rectangle {
                id: removeTip
                readonly property color warn: Config.tint("#f28b8b")
                visible: win.dragAway
                anchors { horizontalCenter: floater.horizontalCenter; bottom: floater.top; bottomMargin: 8 }
                width: removeRow.implicitWidth + 20
                height: removeRow.implicitHeight + 10
                radius: Config.corner(7)
                // The warning red over the dock's own colour (solid without glass)
                color: Qt.tint(win.bgColor, Qt.rgba(warn.r, warn.g, warn.b, Config.glass ? 0.32 : 0.22))
                border.width: 1
                border.color: Qt.rgba(warn.r, warn.g, warn.b, 0.7)
                Gloss { radius: parent.radius }
                Row {
                    id: removeRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // (it stays in the dock, with the running apps, while it's open: just unpinned)
                        text: String.fromCodePoint(win.dragRunning ? 0xED5F : 0xEB41)     // pinned-off / trash
                        color: removeTip.warn
                        font.family: "slate-tabler-icons"
                        font.pixelSize: 15
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.dragRunning ? "Unpin" : "Remove from Dock"
                        color: removeTip.warn
                        font.family: Config.s.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
            }
            ParallelAnimation {
                id: land
                NumberAnimation { id: landX; target: floater; property: "x"; duration: Config.ms(180); easing.type: Easing.OutCubic }
                NumberAnimation { id: landY; target: floater; property: "y"; duration: Config.ms(180); easing.type: Easing.OutCubic }
                NumberAnimation { id: landW; target: floater; property: "width"; duration: Config.ms(180); easing.type: Easing.OutCubic }
                onFinished: dragPop.landed()
            }
        }

        PanelWindow {
            id: previewPop
            screen: win.screen
            property real atX: 0          // by the icon, just off the dock (screen coordinates)
            property real atY: 0
            // Open for this app; fading in and out (the last app's windows stay on it while it fades)
            readonly property bool wanted: !!win.previewApp && win.previewApp.windows.length > 0 && win.dragKey === ""
            property var shownApp: null
            onWantedChanged: if (wanted) shownApp = win.previewApp
            Connections { target: win; function onPreviewAppChanged() { if (previewPop.wanted) previewPop.shownApp = win.previewApp; } }
            readonly property var wins: shownApp ? shownApp.windows : []
            property real fade: wanted ? 1 : 0
            Behavior on fade { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            onFadeChanged: if (fade === 0 && !wanted) shownApp = null
            visible: wanted || fade > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "slate-dock-previews"
            WlrLayershell.layer: WlrLayer.Overlay
            // Only the panel takes the pointer, and nothing once it's going
            mask: wanted ? boxRegion : noRegion
            Region { id: boxRegion; item: previewBox }
            Region { id: noRegion }

            // A card's size: live pictures are wider than title-only cards
            readonly property real cardW: win.previewMode === "live" ? 220 : 200
            readonly property real cardH: win.previewMode === "live" ? 160 : 48

            Rectangle {
                id: previewBox
                readonly property real wanted: previewPop.wins.length * (previewPop.cardW + 8) + 8
                width: Math.min(wanted, previewPop.width - 32)
                height: win.previewMode === "live" ? previewPop.cardH + 16 : Math.min(previewPop.wins.length * (previewPop.cardH + 4) + 12, previewPop.height - 32)
                x: Math.max(8, Math.min(previewPop.width - width - 8,
                    win.edge === "left" ? previewPop.atX : win.edge === "right" ? previewPop.atX - width : previewPop.atX - width / 2))
                y: Math.max(8, Math.min(previewPop.height - height - 8,
                    win.edge === "bottom" ? previewPop.atY - height : win.edge === "top" ? previewPop.atY : previewPop.atY - height / 2))
                radius: Config.corner(12)
                color: win.bgColor
                opacity: previewPop.fade
                Shadow {}                // raised: Slate's shadow, with glass too
                // Grows out of the icon as it fades in, and back into it as it fades out
                transform: Scale {
                    origin.x: Math.max(0, Math.min(previewBox.width, previewPop.atX - previewBox.x))
                    origin.y: Math.max(0, Math.min(previewBox.height, previewPop.atY - previewBox.y))
                    xScale: 0.82 + 0.18 * previewPop.fade
                    yScale: xScale
                }
                Gloss { radius: parent.radius }   // glass: a sheen
                HoverHandler {
                    onHoveredChanged: { win.previewHeld = hovered; if (!hovered) previewLeave.restart(); }
                }

                // Live: the windows side by side (scrolling sideways when there are many)
                Flickable {
                    id: previewScroll
                    visible: win.previewMode === "live"
                    anchors { fill: parent; margins: 8 }
                    contentWidth: previewRow.width
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    // More windows than fit: the wheel or a swipe scrolls sideways
                    SmoothWheel { flick: previewScroll; horizontal: true }
                    Row {
                        id: previewRow
                        spacing: 8
                        Repeater {
                            model: win.previewMode === "live" ? previewPop.wins : []
                            delegate: Rectangle {
                                id: liveCard
                                required property var modelData
                                width: previewPop.cardW; height: previewPop.cardH
                                radius: Config.corner(8)
                                color: liveHover.hovered ? Config.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                Gloss { radius: parent.radius; opacity: liveHover.hovered ? 1 : 0 }
                                WindowPreview {
                                    id: liveShot
                                    readonly property real ratio: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 6 }
                                    width: Math.min(parent.width - 12, (parent.height - 34) * ratio)
                                    height: width / ratio
                                    window: previewPop.visible ? liveCard.modelData : null
                                    running: previewPop.wanted          // (still while it fades out)
                                    // Rounded, and brightened back if Hyprland dims it (it isn't focused)
                                    layer.enabled: true
                                    layer.effect: PreviewShape { radius: Config.corner(6); gain: Config.undimGain(liveCard.modelData.activated, liveCard.modelData.appId) }
                                }
                                Text {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                                    horizontalAlignment: Text.AlignHCenter
                                    text: liveCard.modelData.title || ""
                                    elide: Text.ElideRight
                                    color: liveCard.modelData.activated ? win.activeDotColor : win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                HoverHandler { id: liveHover }
                                ClickTap { hand: false; onTapped: { liveCard.modelData.activate(); win.previewApp = null; } }
                            }
                        }
                    }
                }
                // While there are more windows than fit: a soft shadow at the side that has more,
                // fading in as it's scrolled (as Settings' long pages and menus do)
                Repeater {
                    model: win.previewMode === "live" ? [0, 1] : []
                    Rectangle {
                        required property int modelData
                        readonly property bool atRight: modelData === 1
                        readonly property real more: atRight ? previewScroll.contentWidth - previewScroll.width - previewScroll.contentX
                                                           : previewScroll.contentX
                        width: 22
                        anchors { top: parent.top; bottom: parent.bottom }
                        x: atRight ? parent.width - width : 0
                        topLeftRadius: Config.corner(atRight ? 0 : previewBox.radius); bottomLeftRadius: Config.corner(atRight ? 0 : previewBox.radius)
                        topRightRadius: Config.corner(atRight ? previewBox.radius : 0); bottomRightRadius: Config.corner(atRight ? previewBox.radius : 0)
                        opacity: Math.max(0, Math.min(1, more / 24))
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: atRight ? "transparent" : Config.shade(Config.s.lightMode ? 0.14 : 0.38) }
                            GradientStop { position: 1; color: atRight ? Config.shade(Config.s.lightMode ? 0.14 : 0.38) : "transparent" }
                        }
                    }
                }

                // Titles: the windows one above another, each with the app's icon
                Flickable {
                    id: titleScroll
                    visible: win.previewMode === "titles"
                    anchors { fill: parent; margins: 6 }
                    contentHeight: titleCol.height
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    SmoothWheel { flick: titleScroll }
                    Column {
                        id: titleCol
                        width: parent.width
                        spacing: 4
                        Repeater {
                            model: win.previewMode === "titles" ? previewPop.wins : []
                            delegate: Rectangle {
                                id: titleCard
                                required property var modelData
                                width: titleCol.width; height: previewPop.cardH
                                radius: Config.corner(8)
                                color: titleHover.hovered ? Config.hover : "transparent"
                                Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                Gloss { radius: parent.radius; opacity: titleHover.hovered ? 1 : 0 }
                                AppTile {
                                    id: titleIcon
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    width: 28; height: 28
                                    app: win.previewApp ? (win.previewApp.entry ? win.previewApp.entry.id : win.previewApp.key) : ""
                                }
                                Text {
                                    anchors { left: titleIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    text: titleCard.modelData.title || ""
                                    elide: Text.ElideRight
                                    color: titleCard.modelData.activated ? win.activeDotColor : win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                                }
                                HoverHandler { id: titleHover }
                                ClickTap { hand: false; onTapped: { titleCard.modelData.activate(); win.previewApp = null; } }
                            }
                        }
                    }
                }
            }
        }

        DesktopMenu {
            id: appMenu
            screen: win.screen          // with the dock (which follows the focused screen)
            // Slate's menu (DesktopMenu.qml), pointing at the icon from just off the dock: its
            // rows as the menu's items, and Downloads' grid above them
            items: rows.map(r => r.kind === "sep" ? { separator: true }
                : { label: r.label, danger: !!r.danger, active: !!r.active, run: () => appMenu.run(r) })
            menuWidth: app && (app.downloadsGrid || app.moreGrid) ? 4 * 88 + 16 : 240
            extra: app && app.downloadsGrid ? downloadsGrid : app && app.moreGrid ? moreGrid : null
            property var app: null
            property real alongX: 0     // where it was opened from along the dock (strip coordinates)
            property real menuX: 0      // just inside the dock's inner edge, by the icon (screen coordinates)
            property real menuY: 0
            readonly property var entry: app ? app.entry : null
            readonly property var wins: app ? app.windows : []
            readonly property bool isPinned: app && app.key ? win.pinned.includes(app.key) : false
            // More's grid: the apps in it, held as they are while one's dragged out of it (the
            // dock's list changes as it goes, and a new list would remake the tiles, the one
            // being dragged among them, dropping the pointer)
            // (set, never bound: a binding would follow the dock's list mid-drag too)
            property var moreList: []
            Component.onCompleted: moreList = win.moreItems
            Connections {
                target: win
                function onMoreItemsChanged() { if (!win.dragFromMore) appMenu.moreList = win.moreItems; }
                function onDragFromMoreChanged() { if (!win.dragFromMore) appMenu.moreList = win.moreItems; }
            }

            // x: the icon's centre along the dock (strip coordinates)
            function openFor(a, x) {
                app = a;
                alongX = x;
                const p = win.menuPoint(x);
                menuX = p.x; menuY = p.y;
                openFrom(p.x, p.y, win.edge, 0);
            }
            function closeMenu() { close(); }

            // Rows: open windows, the app's own actions, then New Window / Pin / Quit. For the
            // launcher button: Settings and a few of the places most often wanted in it
            readonly property var rows: {
                if (!app) return [];
                const r = [];
                if (app.mediaMenu) {
                    const p = win.player;
                    if (!p) return r;
                    r.push({ label: p.isPlaying ? "Pause" : "Play", kind: "media-toggle" });
                    if (p.canGoNext) r.push({ label: "Next", kind: "media-next" });
                    if (p.canGoPrevious) r.push({ label: "Previous", kind: "media-previous" });
                    {
                        r.push({ kind: "sep" });
                        r.push({ label: "Show " + (p.identity || "the player"), kind: "media-raise" });
                    }
                    return r;
                }
                if (app.moreGrid) return r;                  // (the grid is all there is)
                if (app.downloadsGrid || app.downloadsMenu) {
                    r.push({ label: "Open Downloads", kind: "downloads-open" });
                    return r;
                }
                if (app.trashMenu) {
                    r.push({ label: "Open", kind: "trash-open" });
                    if (win.trashCount > 0) {
                        r.push({ kind: "sep" });
                        r.push({ label: "Empty Waste Basket…", kind: "trash-empty", danger: true });
                    }
                    return r;
                }
                if (app.settingsMenu) {
                    r.push({ label: "Settings", kind: "settings", target: "overview" });
                    r.push({ kind: "sep" });
                    r.push({ label: "Appearance", kind: "settings", target: "appearance" });
                    r.push({ label: "Wallpaper", kind: "settings", target: "wallpaper" });
                    r.push({ label: "Displays", kind: "settings", target: "displays" });
                    r.push({ label: "Wi-Fi", kind: "settings", target: "wifi" });
                    r.push({ label: "Bluetooth", kind: "settings", target: "bluetooth" });
                    return r;
                }
                if (wins.length > 0) {
                    for (const w of wins) r.push({ label: w.title || app.key, kind: "window", target: w, active: w.activated });
                    r.push({ kind: "sep" });
                }
                if (entry) {
                    for (const act of entry.actions) r.push({ label: act.name, kind: "action", target: act });
                    // Only add our own "New Window" if the app doesn't provide one
                    if (!entry.actions.some(a => (a.name || "").toLowerCase() === "new window"))
                        r.push({ label: "New Window", kind: "new" });
                    r.push({ kind: "sep" });
                }
                r.push({ label: isPinned ? "Unpin from Dock" : "Pin to Dock", kind: "pin" });
                // Closes every window the app has open, whether one or several
                if (wins.length > 0) r.push({ label: wins.length === 1 ? "Close Window" : "Close " + wins.length + " Windows", kind: "quit", danger: true });
                // Kills the app outright, for one that's stopped responding to Close
                if (wins.length > 0) r.push({ label: "Force Quit", kind: "kill", danger: true });
                return r;
            }
            // Hyprland's window addresses for these windows; scripts/force-quit.sh kills their processes
            function forceQuit(list) {
                const addrs = Hyprland.toplevels.values.filter(t => t.wayland && list.includes(t.wayland)).map(t => t.address.startsWith("0x") ? t.address : "0x" + t.address);
                if (addrs.length > 0) Quickshell.execDetached([Quickshell.shellPath("scripts/force-quit.sh")].concat(addrs));
            }
            function run(row) {
                switch (row.kind) {
                case "window": row.target.activate(); break;
                case "action": row.target.execute(); break;
                case "new": entry.execute(); break;
                case "pin": win.setPinned(app.key, !isPinned); break;
                case "quit": for (const w of wins) w.close(); break;
                case "kill": forceQuit(wins); break;
                case "settings": if (settingsLoader.item) settingsLoader.item.goTo(row.target, row.find || ""); break;
                case "trash-open": win.openTrash(); break;
                case "downloads-open": win.openDownloads(); break;
                case "media-toggle": if (win.player) win.player.togglePlaying(); break;
                case "media-next": if (win.player) win.player.next(); break;
                case "media-previous": if (win.player) win.player.previous(); break;
                case "media-raise": win.showPlayer(); break;
                case "trash-empty": {
                    // Asks first, in the same confirmation window as shutting down and the rest
                    const n = win.trashCount;
                    powerConfirm.confirmWith({
                        title: "Empty the waste basket?",
                        body: (n === 1 ? "The item in it will be" : "The " + n + " items in it will be") + " deleted for good. Just so you know, this can't be undone.",
                        button: "Empty", code: 0xEB41, danger: true
                    }, () => win.emptyTrash());
                    break;
                }
                }
                closeMenu();
            }
            // More: the apps that don't fit on the dock (win.foldPlan), four across as Downloads'
            // grid is, three rows and then it scrolls. Click one to go to it (or start it), as on
            // the dock; right-click for its own menu (Pin, Quit and the rest); drag one onto the
            // dock to pin it there (win.pickFromMore)
            Component {
                id: moreGrid
                Flickable {
                    id: moreScroll
                    width: appMenu.menuWidth - 16
                    height: Math.min(moreGridItems.height, 3 * 92)
                    contentHeight: moreGridItems.height
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    SmoothWheel { flick: moreScroll }
                    ScrollShade { z: 3; y: moreScroll.contentY; width: moreScroll.width; cornerRadius: 8; distance: moreScroll.contentY }
                    ScrollShade { z: 3; atBottom: true; y: moreScroll.contentY + moreScroll.height - height; width: moreScroll.width; cornerRadius: 8
                                  distance: moreScroll.contentHeight - moreScroll.height - moreScroll.contentY }
                    ThinScrollbar { z: 3; flick: moreScroll; color: win.textColor; x: moreScroll.width - width; y: moreScroll.contentY; height: moreScroll.height }
                    Grid {
                        id: moreGridItems
                        columns: 4
                        Repeater {
                            model: appMenu.moreList
                            delegate: Item {
                                id: moreApp
                                required property var modelData
                                width: 88; height: 92
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Config.corner(8)
                                    color: moreHover.hovered ? Config.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                }
                                AppTile {
                                    id: moreIcon
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8; width: 52; height: 52
                                    app: moreApp.modelData.key
                                }
                                // Its count, as on the dock
                                Rectangle {
                                    readonly property var badge: win.badgeFor(moreApp.modelData)
                                    readonly property string text: badge.count > 99 ? "99+" : badge.count > 0 ? String(badge.count) : badge.urgent ? "!" : ""
                                    visible: text !== ""
                                    height: 18; width: Math.max(height, moreAppBadge.implicitWidth + 9)
                                    radius: Config.corner(height / 2)
                                    x: moreIcon.x + moreIcon.width - width * 0.75; y: moreIcon.y - height * 0.25
                                    color: win.activeDotColor
                                    Text {
                                        id: moreAppBadge
                                        anchors.centerIn: parent
                                        text: parent.text
                                        color: Config.tint("#12151a")
                                        font.family: Config.s.fontFamily; font.weight: Font.DemiBold; font.pixelSize: 11
                                    }
                                }
                                Text {
                                    id: moreName
                                    anchors { top: moreIcon.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
                                    horizontalAlignment: Text.AlignHCenter
                                    text: moreApp.modelData.entry?.name ?? moreApp.modelData.key
                                    elide: Text.ElideRight
                                    color: win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 11
                                }
                                // Running: the dock's short bar under the name (the accent for the one you're in)
                                Rectangle {
                                    readonly property bool focusedApp: moreApp.modelData.windows.some(w => w.activated)
                                    visible: moreApp.modelData.windows.length > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height - 6
                                    width: 12; height: 3; radius: Config.corner(1.5)
                                    color: focusedApp ? win.activeDotColor : win.dotColor
                                }
                                HoverHandler { id: moreHover }
                                // A click opens it; moved as far as starts a drag on the dock, it's
                                // the dock's drag from then on. (A MouseArea, as the bar's pool
                                // chips are: the click plays for a click, never at the end of a drag)
                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true          // (the grid doesn't scroll instead)
                                    property point pressedAt
                                    property bool dragged: false
                                    onPressed: m => { pressedAt = Qt.point(m.x, m.y); dragged = false; }
                                    onPositionChanged: m => {
                                        if (!dragged && Math.hypot(m.x - pressedAt.x, m.y - pressedAt.y) > win.dragThreshold) {
                                            dragged = true;
                                            win.pickFromMore(moreApp.modelData.key);
                                        }
                                        if (dragged) win.carryFromMore(mapToItem(null, m.x, m.y));
                                    }
                                    onReleased: if (dragged) win.dropFromMore()
                                    onCanceled: if (dragged) win.dropFromMore()
                                    onClicked: {
                                        if (dragged) return;
                                        const it = moreApp.modelData;
                                        Config.click();
                                        appMenu.closeMenu();
                                        win.openApp(it);
                                    }
                                }
                                ClickTap {
                                    hand: false
                                    acceptedButtons: Qt.RightButton
                                    onTapped: { const it = moreApp.modelData, x = appMenu.alongX; appMenu.closeMenu(); appMenu.openFor(it, x); }
                                }
                            }
                        }
                    }
                }
            }
            Component {
                id: downloadsGrid
                Column {
                    id: dlCol
                    width: appMenu.menuWidth - 16
                    spacing: 1
                    // Downloads: the newest, four across; click one to open it
                    Text {
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid && win.recentDownloads.length === 0
                        width: dlCol.width; height: 40
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: "No downloads just yet"
                        color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                        font.family: Config.s.fontFamily; font.pixelSize: 13
                    }
                    Flickable {
                        id: dlScroll
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid && win.recentDownloads.length > 0
                        width: dlCol.width
                        height: Math.min(dlGrid.height, 3 * 92)        // three rows; the rest scroll
                        contentHeight: dlGrid.height
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        SmoothWheel { flick: dlScroll }
                        ScrollShade { z: 3; y: dlScroll.contentY; width: dlScroll.width; cornerRadius: 8; distance: dlScroll.contentY }
                        ScrollShade { z: 3; atBottom: true; y: dlScroll.contentY + dlScroll.height - height; width: dlScroll.width; cornerRadius: 8
                                      distance: dlScroll.contentHeight - dlScroll.height - dlScroll.contentY }
                        ThinScrollbar { z: 3; flick: dlScroll; color: win.textColor; x: dlScroll.width - width; y: dlScroll.contentY; height: dlScroll.height }
                        Grid {
                        id: dlGrid
                        columns: 4
                        Repeater {
                            model: appMenu.app && appMenu.app.downloadsGrid ? win.recentDownloads : []
                            delegate: Item {
                                id: dl
                                required property var modelData
                                readonly property var kind: win.downloadKind(modelData)
                                width: 88; height: 92
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Config.corner(8)
                                    // Under the pointer: the muted hover, flat
                                    color: dlHover.hovered ? Config.hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                                }
                                // The file: a picture as itself, anything else as its kind on a tile
                                Item {
                                    id: dlIcon
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8; width: 52; height: 52
                                    Rectangle {
                                        anchors.fill: parent
                                        visible: !dl.kind.image || dlThumb.status !== Image.Ready
                                        radius: Config.corner(10)
                                        color: win.tileColor
                                        Gloss { radius: parent.radius; glassHint: true }
                                        Text {
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(dl.kind.glyph || 0xEB0A)
                                            color: win.textColor
                                            font.family: "slate-tabler-icons"; font.pixelSize: 24
                                        }
                                    }
                                    Image {
                                        id: dlThumb
                                        anchors.fill: parent
                                        visible: !!dl.kind.image && status === Image.Ready
                                        source: dl.kind.image ? "file://" + dl.modelData.path : ""
                                        sourceSize: Qt.size(128, 128)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        layer.enabled: visible
                                        layer.effect: MultiEffect { maskEnabled: true; maskSource: dlThumbMask }
                                    }
                                    Item {
                                        id: dlThumbMask
                                        anchors.fill: parent
                                        visible: false
                                        layer.enabled: true
                                        Rectangle { anchors.fill: parent; radius: Config.corner(8) }
                                    }
                                }
                                Text {
                                    anchors { top: dlIcon.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
                                    horizontalAlignment: Text.AlignHCenter
                                    text: dl.modelData.name
                                    elide: Text.ElideMiddle
                                    color: win.textColor
                                    font.family: Config.s.fontFamily; font.pixelSize: 11
                                }
                                HoverHandler { id: dlHover }
                                ClickTap {
                                    hand: false
                                    onTapped: { Qt.openUrlExternally("file://" + dl.modelData.path); appMenu.closeMenu(); }
                                }
                            }
                        }
                        }
                    }
                    Rectangle {
                        visible: !!appMenu.app && !!appMenu.app.downloadsGrid
                        width: dlCol.width; height: 9; color: "transparent"
                        Rectangle { anchors.centerIn: parent; width: parent.width - 16; height: 1; color: appMenu.sepColor }
                    }

                }
            }
        }

        // ---- Pointer input --------------------------------------------------
        // Kept outside the turned strip: Qt mixes transformed and untransformed coordinates
        // for hover under a mirroring/rotating transform, so a pointer area inside the strip
        // thinks the pointer has left when it hasn't (top and side docks). This one sits
        // over the dock in window coordinates and maps the pointer into the strip itself.
        ClickArea {
            id: mouse
            z: 10
            anchors.fill: maskBox
            hoverEnabled: true
            // The arrow over the dock, icons and widgets alike, as over the desktop (its click
            // sound stays); the hand is for buttons in panels and menus
            cursorShape: Qt.ArrowCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            function stripX(m) { return strip.mapFromItem(mouse, m.x, m.y).x; }
            property point pressedAt
            property bool dragged: false        // moved far enough to be a drag, not a click
            onPressed: m => {
                pressedAt = Qt.point(m.x, m.y);
                dragged = false;
                const sl = win.slotAt(win.hoveredIndex);
                win.dragCandidate = m.button === Qt.LeftButton && sl && sl.kind === "app" ? sl.item.key : "";
            }
            onPositionChanged: m => {
                win.setPointer(stripX(m));
                if (!pressed || win.dragCandidate === "" || win.landing) return;
                if (!dragged && Math.hypot(m.x - pressedAt.x, m.y - pressedAt.y) > win.dragThreshold) {
                    dragged = true;
                    win.startDrag(win.dragCandidate);
                }
                if (dragged) {
                    win.dragScreen = win.toScreen(mouse.mapToItem(win.contentItem, m.x, m.y));
                    win.dragTo(strip.mapFromItem(mouse, m.x, m.y));
                }
            }
            onReleased: win.endDrag()
            onCanceled: win.endDrag()           // (a drag cut short ends as if let go, never stuck)
            onExited: holdTimer.restart()
            onClicked: m => {
                if (dragged) return;            // a drag, not a click
                win.setPointer(stripX(m));
                win.clickItem(win.hoveredIndex, m.button === Qt.RightButton);
            }
        }
        // Files dragged over the dock (from a file manager): it shows and magnifies as for the
        // pointer, and they're dropped on the slot under them (see win.dropFiles)
        DropArea {
            z: 11
            anchors.fill: maskBox
            onEntered: d => {
                win.fileDrag = d.hasUrls;
                if (!d.hasUrls) d.accepted = false;
            }
            onPositionChanged: d => win.setPointer(strip.mapFromItem(this, d.x, d.y).x)
            onExited: { win.fileDrag = false; holdTimer.restart(); }
            onDropped: d => {
                win.setPointer(strip.mapFromItem(this, d.x, d.y).x);
                if (d.hasUrls && win.dropFiles(win.hoveredIndex, d.urls)) d.acceptProposedAction();
                win.fileDrag = false;
            }
        }
        // Click on dock item i (0 = the apps button)
        // ---- Launching: the icon bounces until the app's first window shows -----
        // Kept here by app key, not in the icons: the dock rebuilds its icons whenever a window
        // opens, which would cut a hop off mid-air. Each hop: up, down, a short rest.
        readonly property int hopUp: 260
        readonly property int hopDown: 260
        readonly property int hopRest: 180
        readonly property int hopCycle: hopUp + hopDown + hopRest
        readonly property int launchTimeoutMs: 12000      // give up on apps that never open a window
        // app key → { start, until }: hopping from start; until (once the app is up, or it timed
        // out) is the end of the hop in progress, so it lands before stopping
        property var launching: ({})
        property real clock: Date.now()
        FrameAnimation {
            running: Object.keys(win.launching).length > 0
            onTriggered: {
                win.clock = Date.now();
                let changed = false;
                const l = Object.assign({}, win.launching);
                for (const k in l) {
                    if (!l[k].until && win.clock - l[k].start > win.launchTimeoutMs) { win.endLaunch(k); return; }
                    if (l[k].until && win.clock >= l[k].until) { delete l[k]; changed = true; }
                }
                if (changed) win.launching = l;
            }
        }
        function startLaunch(key) {
            const l = Object.assign({}, launching);
            l[key] = { start: Date.now(), until: 0 };
            launching = l;
        }
        // The app is up: finish the hop in progress (stop now if it's resting on the dock)
        function endLaunch(key) {
            const b = launching[key];
            if (!b || b.until) return;
            const now = Date.now(), phase = (now - b.start) % hopCycle;
            const l = Object.assign({}, launching);
            l[key] = { start: b.start, until: phase < hopUp + hopDown ? now + (hopUp + hopDown - phase) : now };
            launching = l;
        }
        // How high an app's icon is now: 0 on the dock, 1 at the top of a hop
        function bounceOf(key) {
            const b = launching[key];
            if (!b || !Config.animate) return 0;       // Animations off (or game mode): no hop
            const phase = (clock - b.start) % hopCycle;
            if (phase < hopUp) { const p = phase / hopUp; return 1 - (1 - p) * (1 - p); }              // rising, slowing
            if (phase < hopUp + hopDown) { const q = (phase - hopUp) / hopDown; return 1 - q * q; }   // falling, speeding up
            return 0;
        }

        function clickItem(i, right) {
            if (dragKey !== "") return;                     // (a right-click mid-drag opens no menu)
            // The dock's empty space (its ends, between icons, a divider): right-click for the
            // dock's own menu
            if (i < 0 || (slotAt(i) && slotAt(i).kind === "divider")) { if (right) dockMenu.openHere(); return; }
            if (i === launcherIndex) {
                // The launcher button: opens the launcher; right-click for shortcuts to Settings pages
                if (right) appMenu.openFor({ settingsMenu: true, key: "", windows: [] }, row.x + cellX(i) + base * scaleAt(i) / 2);
                else appLauncher.shown ? appLauncher.closeLauncher() : appLauncher.openLauncher();
                return;
            }
            if (mediaShown && i === mediaIndex) {
                // What's playing: the control under the pointer; right-click for them all
                if (right) appMenu.openFor({ mediaMenu: true, key: "", windows: [] }, row.x + cellX(i) + base * slotWidth(i) * scaleAt(i) / 2);
                else mediaClick();
                return;
            }
            if (downloadsShown && i === downloadsIndex) {
                // Downloads: the grid of the newest; right-click just to open the folder
                appMenu.openFor(right ? { downloadsMenu: true, key: "", windows: [] } : { downloadsGrid: true, key: "", windows: [] },
                    row.x + cellX(i) + base * scaleAt(i) / 2);
                return;
            }
            if (trashShown && i === trashIndex) {
                // The waste basket: opens it; right-click to empty it
                if (right) appMenu.openFor({ trashMenu: true, key: "", windows: [] }, row.x + cellX(i) + base * scaleAt(i) / 2);
                else openTrash();
                return;
            }
            if (moreIndex >= 0 && i === moreIndex) {
                // More: the grid of the apps that don't fit, either button
                appMenu.openFor({ moreGrid: true, key: "", windows: [] }, row.x + cellX(i) + base * scaleAt(i) / 2);
                return;
            }
            const sl = slotAt(i);
            if (!sl || sl.kind !== "app") return;          // (a divider does nothing)
            const item = sl.item;
            if (right) {   // menu by the icon's centre along the dock
                appMenu.openFor(item, row.x + cellX(i) + base * scaleAt(i) / 2);
                return;
            }
            openApp(item);
        }
        // An app's click on the dock (or in More): its next window, or start it
        function openApp(item) {
            const wins = item.windows;
            if (wins.length === 0) { if (item.entry) { startLaunch(item.key); item.entry.execute(); } return; }
            const cur = wins.findIndex(w => w.activated);
            wins[(cur + 1) % wins.length].activate();
        }

        // The dock's own menu, for a right-click on its empty space
        DesktopMenu {
            id: dockMenu
            screen: win.screen
            items: [
                { label: "Auto-hide", icon: Config.s.dockAutoHide ? 0xEA5E : 0, run: () => Config.s.dockAutoHide = !Config.s.dockAutoHide },
                { label: "Position", icon: 0xF22F, submenu: Config.edgeMenu(Config.dockEdge, e => Config.moveDock(e)) },
                // (Settings → Dock's names and order)
                { label: "Hover effect", icon: 0xF6D7, submenu: Config.choiceMenu("dockHoverEffect", [
                    ["magnify", "Magnify"], ["tilt", "Tilt"], ["both", "Magnify and tilt"], ["fade", "Fade"],
                    ["fademagnify", "Fade and magnify"], ["glow", "Glow"], ["glowmagnify", "Glow and magnify"],
                    ["raise", "Raise"], ["none", "None"]], "magnify") },
                { label: "Icon size", icon: 0xF6B1, submenu: Config.choiceMenu("dockIconSize", [[32, "Small"], [40, "Medium"], [52, "Large"]], -1) },
                { label: "Show", icon: 0xEA9A, submenu: [
                    Config.tickItem("Apps button", "dockShowLauncher"), Config.tickItem("What's playing", "dockShowMedia"),
                    Config.tickItem("Downloads", "dockShowDownloads"), Config.tickItem("Waste Basket", "dockShowTrash")] },
                { separator: true },
                { label: "Dock settings", icon: 0xEB20, run: () => Config.slateCall("settings", "page", "dock") }
            ]
            // Pointing at the dock where it was clicked, from just off it, as its apps' menus do
            function openHere() {
                const p = win.menuPoint(strip.mapFromItem(mouse, mouse.mouseX, mouse.mouseY).x);
                openFrom(p.x, p.y, win.edge, 0);
            }
        }

        // ---- The strip: dock, pointer area and label, turned to face the dock's edge ----
        Item {
            id: strip
            // (hidden while the dock moves to another edge, then faded in there: see relocating)
            opacity: win.relocating ? 0 : 1
            Behavior on opacity { enabled: !win.relocating; NumberAnimation { duration: Config.ms(160) } }
            width: win.stripLength
            height: win.thickness
            transform: Matrix4x4 { matrix: win.stripMatrix }

            // Area that takes pointer input: the dock (plus room above it while magnified),
            // or a thin strip at the screen edge while hidden
            Item {
                id: hitArea
                x: (strip.width - width) / 2
                // (while dragging: the whole window, so the app can be carried anywhere above the dock)
                width: win.dragKey !== "" ? strip.width : Math.max(row.width + win.padding * 2, win.restWidth + win.padding * 2)
                height: !win.shown ? 2 : win.dragKey !== "" ? strip.height : (win.hover > 0 ? win.reach : win.dockHeight + win.bottomGap)
                y: strip.height - height
            }


            // ---- Drawing -------------------------------------------------------
            Item {
                id: dock
                anchors.fill: parent
                transform: Translate { y: win.offset }

                Rectangle {
                    id: bg
                    width: row.width + win.padding * 2
                    height: win.dockHeight
                    x: (strip.width - width) / 2
                    y: strip.height - height - win.bottomGap
                    // Corners that follow the icons': the icons' own corner plus half the gap around
                    // them (a fully concentric corner looks too round); a pill for circles
                    // (square with Rounded UI elements off, whatever the icons' shape)
                    radius: Config.corner(Config.s.iconShape === "circle" ? height / 2 : Math.min(height / 2, win.iconCorner + win.padding / 2))
                    bottomLeftRadius: 0     // flush with the screen edge
                    bottomRightRadius: 0
                    color: win.dockColor
                    Gloss { radius: parent.radius; opacity: Math.min(1, win.dockColor.a / 0.05) }   // glass: a sheen (gone with the background)
                }

                // Where a dragged app will go: a faint tile in the gap the others make for it
                Rectangle {
                    id: dragGap
                    visible: win.dragKey !== "" && win.gapOpen > 0.02
                    opacity: win.gapOpen
                    width: win.gapWidth; height: width
                    // (between the slots either side, as gapPos slides from one to the next)
                    x: {
                        const a = Math.floor(win.gapPos), b = Math.ceil(win.gapPos), f = win.gapPos - a;
                        return row.x + win.cellX(a) * (1 - f) + win.cellX(b) * f;
                    }
                    y: row.y + row.height - height
                    radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                    // Without glass: the theme's own shades (Config.tint: light or dark, and the
                    // wallpaper's tint), a slot a shade off the dock with an edge past the tiles'.
                    // With glass: frosted, like the tiles
                    color: Config.glass ? Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.07) : Config.tint("#181c22")
                    // The edge: solid on glass, dashed when flat (edgeColor, drawn below)
                    readonly property color edgeColor: Config.glass ? Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.3) : Config.tint("#3d4553")
                    border.width: Config.glass ? 1.5 : 0
                    border.color: edgeColor
                    Shape {
                        visible: !Config.glass
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: dragGap.edgeColor
                            strokeWidth: 1.5
                            strokeStyle: ShapePath.DashLine
                            dashPattern: [3, 2.5]
                            fillColor: "transparent"
                            PathRectangle {
                                x: 0.75; y: 0.75
                                width: dragGap.width - 1.5; height: dragGap.height - 1.5
                                radius: Config.corner(Math.max(0, dragGap.radius - 0.75))
                            }
                        }
                    }
                    // A faint "drop here", in the edge's colour
                    Text {
                        id: dropGlyph
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEB88)      // drag-drop-2
                        color: dragGap.edgeColor
                        font.family: "slate-tabler-icons"
                        font.pixelSize: Math.round(dragGap.width * 0.45)
                        // Upright for the dock's edge, as its icons are
                        transform: Matrix4x4 { matrix: win.upright(dropGlyph.width, dropGlyph.height) }
                    }
                }

                Row {
                    id: row
                    spacing: win.spacing
                    x: (strip.width - width) / 2
                    y: bg.y + bg.height - win.padding - height
                    height: win.base * win.maxScale

                    // Launcher button (Settings → Dock → Apps button)
                    Item {
                        id: launcherCell
                        opacity: win.fadeAt(win.launcherIndex)
                        visible: win.launcherIndex >= 0
                        readonly property real s: win.scaleAt(win.launcherIndex)
                        width: win.base * s
                        height: row.height
                        transform: [
                            Matrix4x4 { matrix: win.tiltMatrix(launcherCell.width, launcherCell.height, win.tiltAt(win.launcherIndex)) },
                            Translate { y: -win.liftAt(win.launcherIndex); Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }}
                        ]
                        DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base) }
                        Item {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            id: launchTile
                            transform: Matrix4x4 { matrix: win.upright(launchTile.width, launchTile.height) }
                            DockGlow {
                                strength: win.glowAt(win.launcherIndex)
                                radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                            }
                            // The same shape as the app icons (a tile when they're shown as they come)
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale      // drawn once, magnified size
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
                            // Three soft rounded bars, as on the bar's Apps button, scaled with the tile
                            Column {
                                id: burger
                                opacity: Config.dockIconOpacity
                                anchors.centerIn: parent
                                anchors.alignWhenCentered: false
                                readonly property real w: win.symbolRef
                                scale: parent.width / w
                                spacing: w * 0.075
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        width: burger.w * 0.42; height: burger.w * 0.07
                                        radius: Config.corner(height / 2)
                                        color: win.textColor
                                    }
                                }
                            }
                        }
                    }

                    // What's playing (see win.mediaShown): the album art cut to the icons' shape (or the
                    // theme's tile with a note when there's none), a sheen with glass, and under the
                    // pointer Previous / Play-Pause / Next across it on a dark wash
                    Item {
                        id: mediaCell
                        opacity: win.fadeAt(win.mediaIndex)
                        visible: win.mediaShown
                        readonly property real s: win.scaleAt(win.mediaIndex)
                        readonly property bool pointed: win.hoveredIndex === win.mediaIndex && win.hover > 0.5 && !appMenu.visible
                        readonly property string under: pointed ? win.mediaControlAt() : ""
                        width: win.base * win.mediaWide * s
                        height: row.height
                        transform: [
                            Matrix4x4 { matrix: win.tiltMatrix(mediaCell.width, mediaCell.height, win.tiltAt(win.mediaIndex)) },
                            Translate { y: -win.liftAt(win.mediaIndex); Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }}
                        ]

                        // Along a bottom or top dock: a rectangle, the album art at its start and the
                        // controls beside it (the one under the pointer brighter)
                        DockBacking {
                            visible: win.mediaWide > 1 && Config.glass
                            tileHeight: win.base * mediaCell.s
                            radius: Config.corner(mediaWideTile.corner)
                            dockTop: bg.y - row.y; color: win.dockColor
                        }
                        DockBacking {
                            visible: win.mediaWide === 1 && Config.glass
                            dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                        }
                        Item {
                            id: mediaWideTile
                            visible: win.mediaWide > 1
                            anchors.bottom: parent.bottom
                            width: parent.width; height: win.base * mediaCell.s
                            readonly property real corner: Config.s.iconShape === "circle" ? height / 2
                                : height * win.iconCorner / Math.max(1, win.base)
                            readonly property bool hasArt: wideArt.status === Image.Ready
                            // The art sits inside the tile, this far in from its edges. Album covers are
                            // square, so it's rounded a little (as music apps show them), whatever the
                            // icon shape: following the tile's own curve cut too far into the artwork
                            readonly property real inset: Math.round(height * 0.12)
                            readonly property real artCorner: Math.max(3, Math.round((height - inset * 2) * 0.16))
                            Rectangle {
                                anchors.fill: parent
                                radius: Config.corner(mediaWideTile.corner)
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                                Gloss { radius: parent.radius; glassHint: true; tall: false }   // glass: a sheen
                            }
                            // The art, cut to the tile's corners; a note on a faint square without it
                            Item {
                                id: wideArtBox
                                visible: win.mediaArt
                                opacity: Config.dockIconOpacity
                                x: mediaWideTile.inset; y: mediaWideTile.inset
                                width: win.mediaArt ? height : 0; height: parent.height - mediaWideTile.inset * 2
                                layer.enabled: true
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: wideArtMask }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: !mediaWideTile.hasArt
                                    color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.06)
                                    Text {
                                        anchors.centerIn: parent
                                        text: String.fromCodePoint(0xEAFC)      // music
                                        color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                                        font.family: "slate-tabler-icons"
                                        font.pixelSize: Math.round(win.symbolRef * 0.5)
                                        scale: parent.height / win.symbolRef
                                        anchors.alignWhenCentered: false
                                    }
                                }
                                Image {
                                    id: wideArt
                                    anchors.fill: parent
                                    source: win.player ? (win.player.trackArtUrl || "") : ""
                                    sourceSize: Qt.size(192, 192)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true; mipmap: true
                                }
                            }
                            Item {
                                id: wideArtMask
                                anchors.fill: wideArtBox
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: Config.corner(mediaWideTile.artCorner) }
                            }
                            // A faint edge round the art, so a dark cover still stands off the tile
                            Rectangle {
                                anchors.fill: wideArtBox
                                visible: win.mediaArt && mediaWideTile.hasArt
                                radius: Config.corner(mediaWideTile.artCorner)
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.12)
                            }
                            // Previous, Play/Pause, Next: evenly across the rest of the tile (a little above
                            // the middle, to leave room for the progress bar beneath)
                            Row {
                                id: mediaControls
                                opacity: Config.dockIconOpacity
                                anchors { left: wideArtBox.right; right: parent.right; rightMargin: mediaWideTile.inset; leftMargin: win.mediaArt ? 0 : mediaWideTile.inset }
                                y: (parent.height - height) / 2 - parent.height * 0.08
                                Repeater {
                                    model: [
                                        { id: "previous", code: 0xF693, size: 0.34, on: !!win.player && win.player.canGoPrevious },
                                        { id: "toggle", code: win.player && win.player.isPlaying ? 0xF690 : 0xF691, size: 0.42, on: !!win.player && win.player.canTogglePlaying },
                                        { id: "next", code: 0xF694, size: 0.34, on: !!win.player && win.player.canGoNext }
                                    ]
                                    delegate: Item {
                                        id: mediaButton
                                        required property var modelData
                                        width: parent.width / 3; height: mediaWideTile.height * 0.62
                                        // A soft circle behind the one under the pointer
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.height; height: width; radius: Config.corner(width / 2)
                                            readonly property bool lit: mediaCell.under === mediaButton.modelData.id && mediaButton.modelData.on
                                            color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, lit ? 0.14 : 0)
                                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                                            // Glass: a sheen on it while it shows (fading with it)
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(parent.modelData.code)
                                            color: win.textColor
                                            opacity: !parent.modelData.on ? 0.3 : mediaCell.under === parent.modelData.id ? 1 : 0.75
                                            Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                                            font.family: "slate-tabler-icons"
                                            font.pixelSize: Math.round(win.symbolRef * parent.modelData.size)
                                            scale: mediaWideTile.height / win.symbolRef
                                            anchors.alignWhenCentered: false
                                        }
                                    }
                                }
                            }
                            // How far through the track: a slim bar under the controls (only for
                            // players that say how long the track is)
                            Rectangle {
                                opacity: Config.dockIconOpacity
                                readonly property bool known: !!win.player && win.player.lengthSupported && win.player.length > 0
                                visible: known
                                x: mediaControls.x + parent.height * 0.12
                                width: mediaControls.width - parent.height * 0.24
                                y: parent.height - mediaWideTile.inset - height - parent.height * 0.04
                                height: Math.max(2, Math.round(parent.height * 0.05)); radius: Config.corner(height / 2)
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.15)
                                Rectangle {
                                    // (win.player itself: known can lag a moment behind the player going away)
                                    width: parent.known && win.player ? parent.width * Math.max(0, Math.min(1, win.player.position / win.player.length)) : 0
                                    height: parent.height; radius: parent.radius
                                    color: win.activeDotColor
                                }
                            }
                        }

                        // On a side dock: one icon, the controls over the art under the pointer
                        Item {
                            id: mediaTile
                            visible: win.mediaWide === 1
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(mediaTile.width, mediaTile.height) }
                            readonly property real corner: Config.s.iconShape === "circle" ? width / 2
                                : width * win.iconCorner / Math.max(1, win.base)
                            readonly property bool hasArt: win.mediaArt && mediaArt.status === Image.Ready
                            // No art: the tile the launcher button has, with a note on it
                            IconPlate {
                                anchors.fill: parent
                                visible: !mediaTile.hasArt
                                drawSize: win.base * win.maxScale
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                            }
                            Text {
                                visible: !mediaTile.hasArt && !mediaCell.pointed
                                opacity: Config.dockIconOpacity
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xEAFC)          // music
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.6)
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(win.symbolRef * 0.5)
                                scale: parent.width / win.symbolRef
                                anchors.alignWhenCentered: false
                            }
                            // The art, cut to the icons' shape
                            Item {
                                anchors.fill: parent
                                visible: mediaTile.hasArt
                                opacity: Config.dockIconOpacity
                                layer.enabled: visible
                                layer.effect: MultiEffect { maskEnabled: true; maskSource: mediaMask }
                                Image {
                                    id: mediaArt
                                    anchors.fill: parent
                                    source: win.player ? (win.player.trackArtUrl || "") : ""
                                    sourceSize: Qt.size(192, 192)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true; mipmap: true
                                }
                            }
                            Item {
                                id: mediaMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle { anchors.fill: parent; radius: Config.corner(mediaTile.corner) }
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: Config.corner(mediaTile.corner); glassHint: true; tall: false }
                            // Under the pointer: the controls on a dark wash (over art or tile alike,
                            // so they read the same in light and dark)
                            Rectangle {
                                anchors.fill: parent
                                radius: Config.corner(mediaTile.corner)
                                color: "black"
                                opacity: mediaCell.pointed ? 0.5 : 0
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                            }
                            Row {
                                anchors.centerIn: parent
                                anchors.alignWhenCentered: false
                                scale: mediaTile.width / win.symbolRef
                                spacing: win.symbolRef * 0.04
                                opacity: (mediaCell.pointed ? 1 : 0) * Config.dockIconOpacity
                                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
                                Repeater {
                                    model: [
                                        { code: 0xF693, size: 0.22, on: !!win.player && win.player.canGoPrevious },
                                        { code: win.player && win.player.isPlaying ? 0xF690 : 0xF691, size: 0.3, on: !!win.player && win.player.canTogglePlaying },
                                        { code: 0xF694, size: 0.22, on: !!win.player && win.player.canGoNext }
                                    ]
                                    delegate: Text {
                                        required property var modelData
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(modelData.code)
                                        color: "white"
                                        opacity: modelData.on ? 1 : 0.35
                                        font.family: "slate-tabler-icons"
                                        font.pixelSize: Math.round(win.symbolRef * modelData.size)
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: win.middleSlots
                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property bool isApp: modelData.kind === "app"
                            readonly property bool isMore: modelData.kind === "more"
                            // The app in this slot ({ key, entry, windows, pinned }; none for a divider;
                            // for More, the windows of the apps in it, so its running dot shows)
                            readonly property var app: isApp ? modelData.item
                                : ({ key: "", entry: null, pinned: false,
                                     windows: isMore ? modelData.items.reduce((w, it) => w.concat(it.windows), []) : [] })
                            readonly property real s: win.scaleAt(modelData.at)
                            opacity: win.fadeAt(modelData.at)
                            readonly property var badge: isMore ? win.moreBadge : win.badgeFor(isApp ? app : null)
                            readonly property string tilePath: isApp ? Config.tilePath(app.key) : ""
                            property int version: 0
                            property string tried: ""       // the icon file last drawn for (once per file, so a broken icon isn't retried forever)
                            // Bounces while the app is starting (clicked in the dock): see win.bounceOf
                            readonly property real bounce: win.bounceOf(cell.app.key)
                            readonly property int windowCount: cell.app.windows.length
                            onWindowCountChanged: if (windowCount > 0) win.endLaunch(cell.app.key)
                            Component.onCompleted: if (windowCount > 0) win.endLaunch(cell.app.key)
                            width: win.base * win.slotWidth(modelData.at) * s
                            height: row.height
                            // Moved along to open the gap for an app being dragged in: sliding when the
                            // gap opens, closes or moves past it, at once as the gap grows and shrinks
                            property real past: win.gapAt >= 0 && cell.modelData.at >= win.gapAt ? 1 : 0
                            Behavior on past { enabled: !win.settling; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
                            transform: [
                                Matrix4x4 { matrix: win.tiltMatrix(cell.width, cell.height, win.tiltAt(cell.modelData.at)) },
                                Translate {
                                    x: cell.past * (win.gapWidth + win.spacing); y: -win.liftAt(cell.modelData.at)
                                    Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
                                }
                            ]

                            // A divider: a faint line across the dock, between the pinned apps and
                            // the others (and before Downloads and the Waste Basket)
                            Rectangle {
                                visible: cell.modelData.kind === "divider"
                                opacity: Config.dockIconOpacity
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: win.base * 0.12
                                width: 1; height: win.base * 0.76
                                color: Qt.rgba(win.textColor.r, win.textColor.g, win.textColor.b, 0.2)
                            }

                            // More: the apps that don't fit (foldPlan), as a stack like Downloads',
                            // with three dots on it, as the menu bar's More has; a badge when any app
                            // in it has one
                            DockBacking {
                                visible: cell.isMore
                                dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                            }
                            Item {
                                id: moreTile
                                visible: cell.isMore
                                anchors.bottom: parent.bottom
                                width: parent.width; height: width
                                transform: Matrix4x4 { matrix: win.upright(moreTile.width, moreTile.height) }
                                DockGlow {
                                    strength: win.glowAt(cell.modelData.at)
                                    radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                                }
                                IconPlate {
                                    anchors.fill: parent
                                    drawSize: win.base * win.maxScale
                                    shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                    fill: false
                                    color: win.tileColor
                                    opacity: Config.dockTileOpacity
                                }
                                Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
                                Text {
                                    opacity: Config.dockIconOpacity
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xEA95)       // dots
                                    color: win.textColor
                                    font.family: "slate-tabler-icons"
                                    font.pixelSize: Math.round(win.symbolRef * 0.5)
                                    scale: parent.width / win.symbolRef
                                    anchors.alignWhenCentered: false
                                }
                                Rectangle {
                                    readonly property string text: cell.badge.count > 99 ? "99+" : cell.badge.count > 0 ? String(cell.badge.count)
                                        : cell.badge.urgent ? "!" : ""
                                    visible: cell.isMore && text !== ""
                                    z: 2
                                    height: Math.round(parent.height * 0.38)
                                    width: Math.max(height, moreBadgeText.implicitWidth + height * 0.5)
                                    radius: Config.corner(height / 2)
                                    x: parent.width - width * 0.75; y: -height * 0.25
                                    color: win.activeDotColor
                                    Gloss { radius: parent.radius }
                                    Text {
                                        id: moreBadgeText
                                        anchors.centerIn: parent
                                        text: parent.text
                                        color: Config.tint("#12151a")
                                        font.family: Config.s.fontFamily; font.weight: Font.DemiBold
                                        font.pixelSize: Math.round(parent.height * 0.62)
                                    }
                                }
                            }

                            DockBacking {
                                visible: cell.isApp && !Config.s.iconFill && Config.s.iconShape !== "original" && Config.glass
                                tileWidth: cell.width; lift: cell.bounce * win.base * 0.4
                                dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                            }
                            // Glow (Settings → Dock → Hover effect), behind the icon and moving with its bounce.
                            // Kept out of the icon's Image: inside it, the icon wasn't drawn until the dock
                            // next repainted (only its tile showed)
                            Item {
                                visible: cell.isApp
                                anchors.bottom: parent.bottom
                                width: parent.width; height: width
                                transform: Translate { y: -cell.bounce * win.base * 0.4 }
                                DockGlow {
                                    strength: win.glowAt(cell.modelData.at)
                                    colour: win.glowColour(cell.tilePath)
                                    radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                                }
                            }
                            // The tile behind the icon, in the theme's colour: drawn once at its magnified
                            // size and shrunk, not redrawn on every frame as the dock magnifies. Beside the
                            // icon, not in it, so each has an opacity of its own (Settings → Dock → Glass)
                            Item {
                                id: tileBack
                                visible: cell.isApp
                                readonly property url source: tileImg.source     // (the plate reads whose tile it is from here)
                                anchors.bottom: parent.bottom
                                width: parent.width; height: width
                                transform: [
                                    Matrix4x4 { matrix: win.upright(tileBack.width, tileBack.height) },
                                    Translate { y: -cell.bounce * win.base * 0.4 }
                                ]
                                opacity: tileImg.away * Config.dockTileOpacity
                                IconPlate { anchors.fill: parent; drawSize: win.base * win.maxScale }
                            }
                            Image {
                                visible: cell.isApp
                                // Being dragged off the dock to unpin it: faded, as it's about to go
                                property real away: win.dragAway && cell.app.key === win.dragKey ? 0.35 : 1
                                Behavior on away { NumberAnimation { duration: Config.ms(120) } }
                                opacity: away * Config.dockIconOpacity
                                anchors.bottom: parent.bottom
                                id: tileImg
                                width: parent.width; height: width
                                // Upright for the dock's edge, then the launch bounce (away from the edge)
                                transform: [
                                    Matrix4x4 { matrix: win.upright(tileImg.width, tileImg.height) },
                                    Translate { y: -cell.bounce * win.base * 0.4 }
                                ]
                                source: cell.isApp ? "file://" + cell.tilePath + "?v=" + cell.version + "." + Config.tileVersion : ""
                                sourceSize: Qt.size(192, 192)
                                smooth: true
                                mipmap: true
                                cache: false
                                layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                                onStatusChanged: if (cell.isApp && status === Image.Error && !gen.running && cell.tried !== cell.tilePath) { cell.tried = cell.tilePath; gen.running = true; }
                                // Glass: a sheen, rounded like the icon tiles (not on icons shown as
                                // they come, which have no tile to follow)
                                IconGloss { opacity: Config.dockTileOpacity }
                                // How far a download or copy has got: a slim bar near the icon's foot
                                Rectangle {
                                    visible: cell.badge.progress >= 0
                                    z: 2
                                    x: parent.width * 0.15; width: parent.width * 0.7
                                    y: parent.height * 0.8; height: Math.max(3, parent.height * 0.08); radius: Config.corner(height / 2)
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                    Rectangle {
                                        width: Math.max(parent.height, parent.width * cell.badge.progress)
                                        height: parent.height; radius: parent.radius
                                        color: win.activeDotColor
                                    }
                                }
                                // An unread count (or "!" when the app asks for attention): a pill on the
                                // icon's top corner, in the accent, with glass's sheen
                                Rectangle {
                                    readonly property string text: cell.badge.count > 99 ? "99+" : cell.badge.count > 0 ? String(cell.badge.count)
                                        : cell.badge.urgent ? "!" : ""
                                    visible: text !== ""
                                    z: 2
                                    height: Math.round(parent.height * 0.38)
                                    width: Math.max(height, badgeText.implicitWidth + height * 0.5)
                                    radius: Config.corner(height / 2)
                                    x: parent.width - width * 0.75; y: -height * 0.25
                                    color: win.activeDotColor
                                    Gloss { radius: parent.radius }
                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: parent.text
                                        color: Config.tint("#12151a")
                                        font.family: Config.s.fontFamily; font.weight: Font.DemiBold
                                        font.pixelSize: Math.round(parent.height * 0.62)
                                    }
                                }
                            }

                            // Draw the tile the first time this app shows up
                            Process {
                                id: gen
                                command: Config.tileCommand(cell.app.entry ? cell.app.entry.id : cell.app.key, cell.tilePath)
                                onExited: cell.version++
                            }

                            // Running indicator: a short rounded bar (accent for the focused app)
                            Rectangle {
                                readonly property bool focusedApp: cell.app.windows.some(w => w.activated)
                                visible: cell.app.windows.length > 0
                                opacity: Config.dockIconOpacity
                                width: 12; height: 3; radius: Config.corner(1.5)
                                color: focusedApp ? win.activeDotColor : win.dotColor
                                // Snapped to whole device pixels: the icons move by fractions of a
                                // pixel while magnifying, which would make the bar shimmer and look
                                // like it changes length
                                readonly property real dpr: win.screen ? win.screen.devicePixelRatio : 1
                                x: Math.round((cell.x + (cell.width - width) / 2) * dpr) / dpr - cell.x
                                y: Math.round((parent.height + (win.padding - height) / 2) * dpr) / dpr
                            }

                        }
                    }
                    // Room for the gap (the apps after it have moved along into this)
                    Item {
                        width: win.gapOpen * win.gapWidth
                        height: 1
                        visible: win.dragKey !== ""
                    }
                    // Downloads: a stack, the folder-and-arrow on a tile like the launcher button's
                    Item {
                        id: downloadsCell
                        opacity: win.fadeAt(win.downloadsIndex)
                        visible: win.downloadsShown
                        readonly property real s: win.scaleAt(win.downloadsIndex)
                        width: win.base * s
                        height: row.height
                        transform: [
                            Matrix4x4 { matrix: win.tiltMatrix(downloadsCell.width, downloadsCell.height, win.tiltAt(win.downloadsIndex)) },
                            Translate { y: -win.liftAt(win.downloadsIndex); Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }}
                        ]
                        DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base) }
                        Item {
                            id: downloadsTile
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(downloadsTile.width, downloadsTile.height) }
                            DockGlow {
                                strength: win.glowAt(win.downloadsIndex)
                                radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                            }
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                            }
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
                            Text {
                                opacity: Config.dockIconOpacity
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF912)       // folder-down
                                color: win.textColor
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(win.symbolRef * 0.5)
                                scale: parent.width / win.symbolRef
                                anchors.alignWhenCentered: false
                            }
                        }
                    }

                    // The waste basket: the bin on a tile like the launcher button's (and Downloads'),
                    // outlined while empty and filled once something's in it
                    Item {
                        id: trashCell
                        opacity: win.fadeAt(win.trashIndex)
                        visible: win.trashShown
                        readonly property real s: win.scaleAt(win.trashIndex)
                        width: win.base * s
                        height: row.height
                        transform: [
                            Matrix4x4 { matrix: win.tiltMatrix(trashCell.width, trashCell.height, win.tiltAt(win.trashIndex)) },
                            Translate { y: -win.liftAt(win.trashIndex); Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }}
                        ]
                        DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base) }
                        Item {
                            id: trashTile
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(trashTile.width, trashTile.height) }
                            DockGlow {
                                strength: win.glowAt(win.trashIndex)
                                radius: Config.s.iconShape === "circle" ? width / 2 : width * win.iconCorner / Math.max(1, win.base)
                            }
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale      // drawn once, magnified size
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                            }
                            // Glass: a sheen, rounded like the tile
                            Gloss { radius: parent.width * win.iconCorner / Math.max(1, win.base); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
                            // The bin, as Downloads' folder is drawn: outlined while it's empty, filled
                            // once there's something in it
                            Text {
                                opacity: Config.dockIconOpacity
                                anchors.centerIn: parent
                                text: String.fromCodePoint(win.trashCount > 0 ? 0xF783 : 0xEB41)     // trash-filled / trash
                                color: win.textColor
                                font.family: "slate-tabler-icons"
                                font.pixelSize: Math.round(win.symbolRef * 0.5)
                                scale: parent.width / win.symbolRef
                                anchors.alignWhenCentered: false
                            }
                        }
                    }
                }

                // App name above the icon under the pointer
                Rectangle {
                    id: label
                    readonly property string text: win.hoveredIndex >= 0 && win.hoveredIndex === win.launcherIndex ? "Apps"
                        : win.downloadsShown && win.hoveredIndex === win.downloadsIndex ? "Downloads"
                        : win.moreIndex >= 0 && win.hoveredIndex === win.moreIndex
                            ? "More · " + win.moreItems.length + (win.moreItems.length === 1 ? " app" : " apps")
                        : win.trashShown && win.hoveredIndex === win.trashIndex
                            ? (win.trashCount > 0 ? "Waste Basket · " + win.trashCount + (win.trashCount === 1 ? " item" : " items") : "Waste Basket")
                        : win.mediaShown && win.hoveredIndex === win.mediaIndex
                            ? win.player.trackTitle + (win.player.trackArtist ? " · " + win.player.trackArtist : "")
                        : (win.slotAt(win.hoveredIndex) && win.slotAt(win.hoveredIndex).kind === "app"
                            ? (win.slotAt(win.hoveredIndex).item.entry?.name ?? win.slotAt(win.hoveredIndex).item.key) : "")
                    readonly property real iconSize: win.hoveredIndex >= 0 ? win.base * win.scaleAt(win.hoveredIndex) : 0
                    readonly property real slotLength: win.hoveredIndex >= 0 ? iconSize * win.slotWidth(win.hoveredIndex) : 0
                    // (not while dragging: the dragged app says so itself, dragPop)
                    visible: win.hoveredIndex >= 0 && win.hover > 0.9 && text !== "" && !appMenu.visible && win.dragKey === ""
                    width: labelText.implicitWidth + 16
                    height: labelText.implicitHeight + 8
                    radius: Config.corner(6)
                    color: win.bgColor
                    Gloss { radius: parent.radius }   // glass: a sheen
                    x: row.x + win.cellX(Math.max(0, win.hoveredIndex)) + slotLength / 2 - width / 2
                    // On a side dock the label is turned upright, so its width runs across the strip
                    readonly property real across: win.vertical ? width : height
                    y: row.y + row.height - iconSize - 8 - across / 2 - height / 2
                    transform: Matrix4x4 { matrix: win.upright(label.width, label.height) }
                    Text {
                        id: labelText
                        anchors.centerIn: parent
                        text: label.text.charAt(0).toUpperCase() + label.text.slice(1)   // kitty -> Kitty
                        color: win.textColor
                        font.family: win.fontFamily
                        font.weight: win.fontWeight
                        font.pixelSize: win.fontSize
                    }
                }
            }
        }
    }
}
