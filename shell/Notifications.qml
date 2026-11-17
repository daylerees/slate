// Notification server: pop-up toasts (top-right by default; Settings → Notifications),
// a saved history for the bell panel, and Do Not Disturb.
//
// History is kept in ~/.local/state/slate/notifications.json.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Hyprland

Scope {
    id: notifs
    required property var bar

    // ---- Settings ----------------------------------------------------------
    readonly property int defaultTimeout: Config.s.notificationSeconds * 1000   // ms, when the app doesn't set one
    readonly property int maxToasts: Config.s.notificationMaxToasts
    readonly property int maxHistory: 100
    readonly property real toastWidth: 360
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/slate/notifications.json"

    // ---- State -------------------------------------------------------------
    property bool dnd: false                // Do Not Disturb by hand (the switch; saved)

    // ---- Quiet by itself (Settings → Notifications → Do Not Disturb) --------------------------
    // On a schedule, while a window is full screen, and during calls (an app using a
    // microphone). Turning Do Not Disturb off by hand while one of these has it on lets
    // notifications through until that changes (the schedule's end, the window leaving full
    // screen, the call ending); everything else uses `quiet`, never `dnd`.
    readonly property string autoWhy: Config.s.dndSchedule && quietHours ? "schedule"
        : Config.s.dndFullscreen && fullscreenNow ? "fullscreen"
        : Config.s.dndCalls && onCall ? "call"
        : Timers.focusQuiet ? "focus" : ""
    property string letThrough: ""          // the automatic reason turned off by hand
    onAutoWhyChanged: letThrough = ""
    readonly property bool quiet: dnd || (autoWhy !== "" && letThrough !== autoWhy)
    // Why it's on, in words for the bell and the panels ("" when it's off, or on by hand)
    readonly property string quietWhy: !quiet || dnd ? "" : ({
        schedule: "until " + Config.clockText(clockAt(Config.s.dndTo)),
        fullscreen: "while a window is full screen",
        call: "while you're on a call",
        focus: "while you focus" })[autoWhy] || ""
    function setQuiet(on) {
        if (on) { dnd = true; return; }
        dnd = false;
        if (autoWhy !== "") letThrough = autoWhy;
    }
    // The schedule: from dndFrom to dndTo (past midnight too), on the days chosen. Checked every
    // half a minute while it's on (the input that makes it worth running)
    property bool quietHours: false
    function minutes(text) { const m = /^(\d{1,2}):(\d{2})$/.exec(text || ""); return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : 0; }
    function clockAt(text) { const d = new Date(); d.setHours(Math.floor(minutes(text) / 60), minutes(text) % 60, 0, 0); return d; }
    function quietAt(now) {
        const t = now.getHours() * 60 + now.getMinutes();
        const from = minutes(Config.s.dndFrom), to = minutes(Config.s.dndTo);
        const inside = from <= to ? (t >= from && t < to) : (t >= from || t < to);
        if (!inside) return false;
        // (the day it began: after midnight, a night that started yesterday)
        const began = new Date(now);
        if (from > to && t < to) began.setDate(began.getDate() - 1);
        const weekend = began.getDay() === 0 || began.getDay() === 6;
        return Config.s.dndDays === "weekdays" ? !weekend : Config.s.dndDays === "weekends" ? weekend : true;
    }
    function checkQuietHours() { quietHours = Config.s.dndSchedule && quietAt(new Date()); }
    Timer { running: Config.s.dndSchedule; interval: 30000; repeat: true; triggeredOnStart: true; onTriggered: notifs.checkQuietHours() }
    Connections {
        target: Config.s
        function onDndScheduleChanged() { notifs.checkQuietHours(); }
        function onDndFromChanged() { notifs.checkQuietHours(); }
        function onDndToChanged() { notifs.checkQuietHours(); }
        function onDndDaysChanged() { notifs.checkQuietHours(); }
    }
    // Full screen: the workspace you're on has a full-screen window
    property bool testFullscreen: false     // (the tests: as if it had)
    readonly property bool fullscreenNow: testFullscreen || (!!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen)
    // A call: an app's stream taking sound from a microphone (an audio source that isn't a stream)
    property bool testOnCall: false         // (the tests: as if there were one)
    readonly property bool onCall: testOnCall || (Config.s.dndCalls && Pipewire.linkGroups.values.some(g =>
        !!g.source && !!g.target && g.source.audio && !g.source.isSink && !g.source.isStream && g.target.isStream))
    // Apps that still pop up while it's quiet (Settings: dndAllowed, by the name they give)
    function allowedThrough(appName) { return (Config.s.dndAllowed || []).indexOf(appName) >= 0; }
    // Newest first: { key, id, appName, summary, body, entryId, image, appIcon, time, urgency,
    // page } (page: the Settings page Slate's own notices open, from their x-slate-page hint)
    property var history: []
    property int unread: 0
    property int nextKey: 1
    // The newest notification seen in the panel (its key): any newer ones are unread (the
    // bell's count)
    property int readUpTo: 0
    // The dock's badges (unreadByApp: entry id → count): each app's notifications since you
    // last went to that app (the dock marks it, markAppSeen), not since the panel was opened,
    // so a mail or chat app's badge stays until you look at it. appSeen: entry id → the newest
    // key seen there; appSeenBase for apps not gone to since this began
    property var appSeen: ({})
    property int appSeenBase: 0
    readonly property var unreadByApp: {
        const out = {};
        for (const h of history)
            if (h.entryId && h.key > (appSeen[h.entryId] ?? appSeenBase)) out[h.entryId] = (out[h.entryId] || 0) + 1;
        return out;
    }
    function markAppSeen(id) {
        if (!id || appSeen[id] === nextKey - 1) return;
        const m = Object.assign({}, appSeen);
        m[id] = nextKey - 1;
        appSeen = m;
        save();
    }
    property var live: ({})           // key -> Notification still open (for actions)

    // The notification still open under this key, or null once its app (or we) closed it.
    // Asked at the moment of closing, never kept: a pop-up's own copy goes stale when the app
    // closes the notification first, and closing a destroyed one is an error in the log.
    function liveFor(key) { return live[key] ?? null; }

    function markRead() { unread = 0; readUpTo = nextKey - 1; save(); }
    function remove(key) {
        const n = live[key];
        if (n) n.dismiss();
        delete live[key];
        history = history.filter(h => h.key !== key);
        save();
    }
    function clearAll() {
        for (const k in live) live[k].dismiss();
        live = {};
        // ...and their pop-ups go too, fading out as usual (left, each showed as an empty card
        // until its time ran out: its words were in the history being cleared)
        pendingToasts = [];
        for (let i = 0; i < toastModel.count; i++) toastModel.setProperty(i, "leaving", true);
        history = [];
        unread = 0;
        readUpTo = nextKey - 1;
        save();
    }
    // Run the notification's main action (if the app is still listening), then dismiss
    function activate(key) { invokeAction(key, "default"); }
    // Run one of its actions (its buttons) by identifier, then dismiss
    function invokeAction(key, identifier) {
        const n = live[key];
        if (n) {
            const act = n.actions.find(a => a.identifier === identifier);
            if (act) act.invoke();
            // (invoking an action closes the notification itself unless the app marked it
            // resident, so ask again before closing: closing it twice is an error in the log)
            const still = liveFor(key);
            if (still) still.dismiss();
        }
        dismissToast(key);
    }

    // Best matching app entry, used for the tile icon
    function entryFor(n) {
        const tries = [n.desktopEntry, n.appName, (n.appName || "").toLowerCase().replace(/\s+/g, "-")];
        for (const t of tries) {
            if (!t) continue;
            const e = DesktopEntries.byId(t) ?? DesktopEntries.heuristicLookup(t);
            if (e) return e.id;
        }
        return "";
    }

    // An app that sends no name of its own (some do) goes by its launcher's name
    function nameFor(appName, entryId) {
        if (appName) return appName;
        const e = entryId ? DesktopEntries.byId(entryId) : null;
        return e && e.name ? e.name : "";
    }

    // ---- Server ------------------------------------------------------------
    NotificationServer {
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            // Kept from before Slate reloaded (keepOnReload): Quickshell hands it over again,
            // but it's not new. Link it back to its history entry (so its actions and closing
            // it still work) without another pop-up, history entry or unread
            if (n.lastGeneration) {
                const old = notifs.history.find(h => h.id === n.id && h.summary === (n.summary || ""));
                if (old) {
                    notifs.live[old.key] = n;
                    n.closed.connect(() => { delete notifs.live[old.key]; });
                }
                return;
            }
            const key = notifs.nextKey++;
            notifs.live[key] = n;
            n.closed.connect(() => { delete notifs.live[key]; });
            const entry = notifs.entryFor(n);
            const item = {
                key: key,
                id: n.id,
                appName: notifs.nameFor(n.appName || "", entry),
                summary: n.summary || "",
                body: n.body || "",
                entryId: entry,
                image: n.image || "",
                appIcon: n.appIcon || "",
                // Slate's own notices name the Settings page they're about (x-slate-page), for
                // their colour in Colourful mode
                page: String((n.hints && n.hints["x-slate-page"]) || ""),
                time: Date.now(),
                urgency: n.urgency
            };
            notifs.history = [item].concat(notifs.history).slice(0, notifs.maxHistory);
            notifs.unread++;
            notifs.save();
            // Do Not Disturb (by hand or by itself) holds back all but urgent ones and the apps
            // allowed through; game mode holds back every one (they
            // still go to the history, and the bell counts them)
            if (!Config.gameMode && (!notifs.quiet || n.urgency === NotificationUrgency.Critical || notifs.allowedThrough(n.appName))) {
                notifs.showToast(item);
                notifs.chime(n);
            }
        }
    }

    // A soft chime with each pop-up (Settings → Sound): not for low-urgency notices, nor when the
    // app asks for silence (suppress-sound); a burst of notifications chimes once. Critical ones
    // (warnings) ask for attention instead
    property real lastChime: 0
    function chime(n) {
        const h = n.hints || {};
        if (h["suppress-sound"] || n.urgency === NotificationUrgency.Low) return;
        if (n.urgency === NotificationUrgency.Critical) { Config.attention(); return; }
        if (Config.soundVolume("notification") <= 0) return;
        if (Date.now() - lastChime < 1500) return;
        lastChime = Date.now();
        Config.playSound("notification", "notification");
    }

    // ---- Saving / loading --------------------------------------------------
    FileView {
        id: store
        path: notifs.stateFile
        blockLoading: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                notifs.history = (d.history || []).map(h => Object.assign({}, h, {
                    image: "",
                    entryId: h.entryId || notifs.entryFor({ desktopEntry: "", appName: h.appName })
                }));
                notifs.dnd = !!d.dnd;
                notifs.unread = d.unread || 0;
                // (kept, so keys never start again below what's been seen, after Clear all)
                notifs.nextKey = Math.max(1, d.nextKey || 1, ...notifs.history.map(h => h.key + 1));
                // (saved by older versions without it: the newest "unread" of the history are unread)
                notifs.readUpTo = d.readUpTo !== undefined ? d.readUpTo
                    : (notifs.history[notifs.unread] ? notifs.history[notifs.unread].key : 0);
                notifs.appSeen = d.appSeen || {};
                // (from before per-app badges: what had been seen in the panel counts as seen)
                notifs.appSeenBase = d.appSeenBase !== undefined ? d.appSeenBase : notifs.readUpTo;
            } catch (e) {}
        }
    }
    Timer { id: saveTimer; interval: 500; onTriggered: stateDir.running = true }
    // What notifications say can be private (a one-time code), so only you can read the
    // history: Slate's state folder is made yours alone before each save, and the file after it
    Process {
        id: stateDir
        command: ["sh", "-c", 'mkdir -p "${0%/*}" && chmod 700 "${0%/*}"', notifs.stateFile]
        onExited: {
            store.setText(JSON.stringify({ dnd: notifs.dnd, unread: notifs.unread, readUpTo: notifs.readUpTo,
                nextKey: notifs.nextKey, appSeen: notifs.appSeen, appSeenBase: notifs.appSeenBase, history: notifs.history }, null, 1));
            Quickshell.execDetached(["chmod", "600", notifs.stateFile]);
        }
    }
    function save() { saveTimer.restart(); }
    //   slate ipc call notifications dnd true      Do Not Disturb on (false: off)
    IpcHandler {
        target: "notifications"
        function dnd(on: bool): void { notifs.setQuiet(on); }
        function dndGet(): string { return String(notifs.quiet); }
        // Would the schedule have it on at this time ("HH:MM") on this day (0 Sunday … 6 Saturday)?
        function quietAt(time: string, day: int): string {
            const m = notifs.minutes(time);
            return String(Config.s.dndSchedule && notifs.quietAt(new Date(2026, 0, 4 + day, Math.floor(m / 60), m % 60)));
        }
        // (the tests: as if a window were full screen, or a call going)
        function testRule(what: string, on: bool): void {
            if (!Config.testMode) return;
            if (what === "fullscreen") notifs.testFullscreen = on;
            if (what === "call") notifs.testOnCall = on;
        }
        // The latest ones, newest first: [{"app", "summary", "body", "time"}]
        function list(): string {
            return JSON.stringify(notifs.history.slice(0, 20).map(h => ({ app: h.appName || "", summary: h.summary || "", body: h.body || "", time: h.time || 0 })));
        }
        function clear(): void { notifs.clearAll(); }
    }
    onDndChanged: save()

    // ---- Toasts ------------------------------------------------------------
    ListModel { id: toastModel }
    readonly property int toastsShowing: { toastModel.count; let n = 0; for (let i = 0; i < toastModel.count; i++) if (!toastModel.get(i).leaving) n++; return n; }
    // A new toast waits until its window is on screen: a window takes a moment to appear,
    // and a toast added before then would be most of the way through fading in (and its
    // first frame drawn rough) by the time it's seen
    property var pendingToasts: []
    function showToast(item) {
        if (toastWin.ready) { addToast(item.key); return; }
        pendingToasts = pendingToasts.concat([item.key]);
        toastWin.showing = true;
        readyFallback.restart();
    }
    function addToast(key) {
        toastModel.insert(0, { key: key, leaving: false });
        // Too many: the oldest still showing go (fading out like any other)
        let showing = 0;
        for (let i = 0; i < toastModel.count; i++) {
            if (toastModel.get(i).leaving) continue;
            if (++showing > maxToasts) toastModel.setProperty(i, "leaving", true);
        }
    }
    function flushToasts() {
        const keys = pendingToasts;
        pendingToasts = [];
        for (const k of keys) addToast(k);
    }
    // In case the window's first frame is never reported
    Timer { id: readyFallback; interval: 200; onTriggered: if (!toastWin.ready && toastWin.showing) { toastWin.ready = true; notifs.flushToasts(); } }
    // A pop-up going away fades out where it is first (its delegate does that), then comes
    // out of the list, and the others close up. (The list's own remove animation was
    // skipped for all but the last pop-up, so they vanished.)
    function dismissToast(key) {
        for (let i = 0; i < toastModel.count; i++)
            if (toastModel.get(i).key === key) { toastModel.setProperty(i, "leaving", true); return; }
    }
    function removeToastNow(key) {
        for (let i = 0; i < toastModel.count; i++)
            if (toastModel.get(i).key === key) { toastModel.remove(i); return; }
    }
    function itemFor(key) { return history.find(h => h.key === key) ?? null; }
    // (tests) The newest pop-up as its card draws it: its title's width and its message's text
    function toastLook() {
        const t = toastList.count > 0 ? toastList.itemAtIndex(0) : null;
        return t ? { titleWidth: Math.round(t.shownCard.titleWidth), body: t.shownCard.shownBody } : null;
    }

    PanelWindow {
        id: toastWin
        // On the main display (Settings → Displays), with the main bar
        screen: Config.primaryScreen
        // Shows when a toast arrives and stays up a moment after the last one goes, so it can
        // fade out rather than vanish. Set here rather than bound to the counts: a binding
        // looped (the list's count follows the window) and hid the window at once
        property bool showing: false
        visible: showing
        // On screen: its first frame has been drawn since it was shown
        property bool ready: false
        onShowingChanged: if (!showing) ready = false
        Connections {
            target: toastList.Window.window
            function onFrameSwapped() {
                if (toastWin.showing && !toastWin.ready) { toastWin.ready = true; notifs.flushToasts(); }
            }
        }
        Timer { id: lingerAfterLast; interval: 500; onTriggered: toastWin.showing = toastModel.count > 0 || notifs.pendingToasts.length > 0 }
        Connections {
            target: toastModel
            function onCountChanged() {
                if (toastModel.count > 0) { lingerAfterLast.stop(); toastWin.showing = true; }
                else lingerAfterLast.restart();
            }
        }
        // Where pop-ups go (Settings → Notifications)
        readonly property bool atTop: !Config.s.notificationPosition.startsWith("bottom")
        readonly property string side: Config.s.notificationPosition.split("-")[1] || "right"
        // Fade in drifting a little from the nearest side edge; centred ones fade and grow
        readonly property real slideX: side === "right" ? 16 : side === "left" ? -16 : 0
        anchors { top: atTop; bottom: !atTop; left: side === "left"; right: side === "right" }
        // Clear of the bar, and of the dock when it's on the same edge
        margins {
            top: (Config.barEdge === "top" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "top" && side === "center" ? 84 : 8) - toastWin.shadowPad
            bottom: (Config.barEdge === "bottom" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "bottom" && side === "center" ? 84 : 12) - toastWin.shadowPad
            left: (Config.barEdge === "left" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "left" ? 84 : 12) - toastWin.shadowPad
            right: (Config.barEdge === "right" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "right" ? 84 : 12) - toastWin.shadowPad
        }
        // Room all round for the cards' shadows (the margins above are less by as much)
        readonly property real shadowPad: 18
        implicitWidth: notifs.toastWidth + shadowPad * 2
        // Room for a column of pop-ups, but never taller than the screen
        implicitHeight: toastWin.screen ? Math.min(700, toastWin.screen.height - 120) : 700
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "slate-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region { item: toastList.contentItem }

        ListView {
            id: toastList
            width: parent.width
            height: contentHeight
            y: toastWin.atTop ? toastWin.shadowPad : parent.height - height - toastWin.shadowPad
            // Newest nearest the screen edge
            verticalLayoutDirection: toastWin.atTop ? ListView.TopToBottom : ListView.BottomToTop
            interactive: false
            spacing: 8
            model: toastModel

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; from: toastWin.slideX; to: 0; duration: Config.ms(320); easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: toastWin.side === "center" ? 0.92 : 1; to: 1; duration: Config.ms(320); easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Config.ms(320); easing.type: Easing.OutQuad }
                    // …and drops a little into place (rises, for pop-ups at the bottom)
                    NumberAnimation { property: "y"; from: ViewTransition.destination.y + (toastWin.atTop ? -12 : 12); to: ViewTransition.destination.y; duration: Config.ms(320); easing.type: Easing.OutCubic }
                }
            }
            displaced: Transition { NumberAnimation { property: "y"; duration: Config.ms(220); easing.type: Easing.OutCubic } }

            delegate: Item {
                id: toast
                required property int key
                required property bool leaving
                // Going away: fade out where it is (from the start), then leave the list
                onLeavingChanged: if (leaving) leaveAnim.start()
                SequentialAnimation {
                    id: leaveAnim
                    NumberAnimation { target: toast; property: "opacity"; to: 0; duration: Config.ms(380); easing.type: Easing.OutQuad }
                    ScriptAction { script: notifs.removeToastNow(toast.key) }
                }
                readonly property var item: notifs.itemFor(key)
                readonly property var notif: notifs.live[key] ?? null
                readonly property alias shownCard: card      // (tests: toastLook)
                readonly property bool critical: item && item.urgency === NotificationUrgency.Critical
                width: ListView.view.width
                height: card.height + 6                // a little room for the shadow below

                // Auto-dismiss: counts down (shown as the card's timeout bar), paused while
                // hovered; critical ones stay until dismissed
                readonly property int timeout: toast.notif && toast.notif.expireTimeout > 0 ? toast.notif.expireTimeout : notifs.defaultTimeout
                property real timeLeft: 1
                NumberAnimation on timeLeft {
                    id: countdown
                    running: !toast.critical
                    paused: running && toastHover.hovered
                    from: 1; to: 0
                    duration: toast.timeout
                    onFinished: { const n = notifs.liveFor(toast.key); if (n) n.expire(); notifs.dismissToast(toast.key); }
                }
                HoverHandler { id: toastHover }

                NotificationCard {
                    id: card
                    x: toastWin.shadowPad
                    width: parent.width - toastWin.shadowPad * 2
                    progress: toast.critical ? -1 : toast.timeLeft
                    fresh: true
                    entry: toast.item
                    notif: toast.notif
                    bar: notifs.bar
                    critical: toast.critical
                    onActivated: notifs.activate(toast.key)
                    onClosed: { const n = notifs.liveFor(toast.key); if (n) n.dismiss(); notifs.dismissToast(toast.key); }
                    onAction: id => notifs.invokeAction(toast.key, id)
                }
            }
        }
    }
}
