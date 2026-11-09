// Notification server: pop-up toasts (top-right by default; Settings → Notifications),
// a saved history for the bell panel, and Do Not Disturb.
//
// History is kept in ~/.local/state/slate/notifications.json.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications

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
    property bool dnd: false
    property var history: []          // newest first: { key, id, appName, summary, body, entryId, image, appIcon, time, urgency }
    property int unread: 0
    property int nextKey: 1
    property var live: ({})           // key -> Notification still open (for actions)

    function markRead() { unread = 0; save(); }
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
        history = [];
        unread = 0;
        save();
    }
    // Run the notification's main action (if the app is still listening), then dismiss
    function activate(key) {
        const n = live[key];
        if (n) {
            const act = n.actions.find(a => a.identifier === "default");
            if (act) act.invoke();
            n.dismiss();
        }
        dismissToast(key);
    }
    function invokeAction(key, identifier) {
        const n = live[key];
        if (n) {
            const act = n.actions.find(a => a.identifier === identifier);
            if (act) act.invoke();
            n.dismiss();
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
            const item = {
                key: key,
                id: n.id,
                appName: n.appName || "",
                summary: n.summary || "",
                body: n.body || "",
                entryId: notifs.entryFor(n),
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
            if (!notifs.dnd || n.urgency === NotificationUrgency.Critical) {
                notifs.showToast(item, n);
                notifs.chime(n);
            }
        }
    }

    // A soft chime with each pop-up (Settings → Sound): not for low-urgency notices, nor when the
    // app asks for silence (suppress-sound); a burst of notifications chimes once
    property real lastChime: 0
    function chime(n) {
        if (!Config.s.notificationSound || n.urgency === NotificationUrgency.Low) return;
        const h = n.hints || {};
        if (h["suppress-sound"]) return;
        if (Date.now() - lastChime < 1500) return;
        lastChime = Date.now();
        Config.playSound("notification");
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
                notifs.nextKey = Math.max(1, ...notifs.history.map(h => h.key + 1));
            } catch (e) {}
        }
    }
    Timer { id: saveTimer; interval: 500; onTriggered: store.setText(JSON.stringify({ dnd: notifs.dnd, unread: notifs.unread, history: notifs.history }, null, 1)) }
    function save() { saveTimer.restart(); }
    onDndChanged: save()

    // ---- Toasts ------------------------------------------------------------
    ListModel { id: toastModel }
    // A new toast waits until its window is on screen: a window takes a moment to appear,
    // and a toast added before then would be most of the way through fading in (and its
    // first frame drawn rough) by the time it's seen
    property var pendingToasts: []
    function showToast(item, n) {
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
            top: (Config.barEdge === "top" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "top" && side === "center" ? 84 : 8)
            bottom: (Config.barEdge === "bottom" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "bottom" && side === "center" ? 84 : 12)
            left: (Config.barEdge === "left" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "left" ? 84 : 12) - toastWin.shadowPad
            right: (Config.barEdge === "right" ? notifs.bar.barHeight : 0) + (Config.dockEdge === "right" ? 84 : 12) - toastWin.shadowPad
        }
        // Room either side for the cards' shadows
        readonly property real shadowPad: 12
        implicitWidth: notifs.toastWidth + shadowPad * 2
        implicitHeight: 700
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "slate-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region { item: toastList.contentItem }

        ListView {
            id: toastList
            width: parent.width
            height: contentHeight
            y: toastWin.atTop ? 0 : parent.height - height
            // Newest nearest the screen edge
            verticalLayoutDirection: toastWin.atTop ? ListView.TopToBottom : ListView.BottomToTop
            interactive: false
            spacing: 8
            model: toastModel

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; from: toastWin.slideX; to: 0; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: toastWin.side === "center" ? 0.92 : 1; to: 1; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuad }
                    // …and drops a little into place (rises, for pop-ups at the bottom)
                    NumberAnimation { property: "y"; from: ViewTransition.destination.y + (toastWin.atTop ? -12 : 12); to: ViewTransition.destination.y; duration: 320; easing.type: Easing.OutCubic }
                }
            }
            displaced: Transition { NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic } }

            delegate: Item {
                id: toast
                required property int key
                required property bool leaving
                // Going away: fade out where it is (from the start), then leave the list
                onLeavingChanged: if (leaving) leaveAnim.start()
                SequentialAnimation {
                    id: leaveAnim
                    NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
                    ScriptAction { script: notifs.removeToastNow(toast.key) }
                }
                readonly property var item: notifs.itemFor(key)
                readonly property var notif: notifs.live[key] ?? null
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
                    onFinished: { if (toast.notif) toast.notif.expire(); notifs.dismissToast(toast.key); }
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
                    onClosed: { if (toast.notif) toast.notif.dismiss(); notifs.dismissToast(toast.key); }
                    onAction: id => notifs.invokeAction(toast.key, id)
                }
            }
        }
    }
}
