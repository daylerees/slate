// The dock: a macOS-style dock on the focused screen (shell.qml's header says what it does).
// Everything in it is private to this file; shell.qml hands in the few pieces of Slate it
// reaches (the properties just under `id`), and the test suite's hooks are the test… functions
// at the end, which shell.qml's `test` IPC target calls.
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

PanelWindow {
    id: win

    // ---- What the dock reaches in the rest of Slate (set by shell.qml) -------------------
    property var popouts: null             // the bar's panels (the dock closes them when it's used)
    property var notifs: null              // notifications (unread counts, marking an app's as seen)
    property var appLauncher: null         // the launcher (the Apps button)
    property var powerConfirm: null        // Slate's confirmation window
    property var settingsWindow: () => null    // builds the Settings window if need be, and returns it
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
        // (~/.local/state on purpose, not Config.stateHome: it stays where it has always been)
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
    // The icon size asked for: Settings' (Dock → Icon size), or while a divider is dragged the
    // size the drag has reached. The dock is laid out at it as it goes (the window never changes
    // size, so that's only a redraw, as magnifying is); Settings' is saved once, when it's let go.
    // (A scaled picture of the dock was tried: its borders, sheen and shadow grew with it, so it
    // never matched the real dock)
    property real resizeSize: -1                            // -1: no drag
    readonly property bool resizing: resizeSize >= 0
    readonly property real iconSetting: resizing ? resizeSize : Config.s.dockIconSize
    readonly property real iconsLong: {
        let n = 0;
        for (let i = 0; i < count; i++) n += slotWidth(i);
        return n;
    }
    // The most the icons can be where they're fitted in along the edge
    readonly property real fitSize: (roomLength - 48 - padding * 2 - (count - 1) * spacing) / Math.max(1, iconsLong)
    readonly property real base: Math.max(16, Math.min(iconSetting, fitSize))
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
    readonly property real reach: Math.ceil(base * maxScale + padding * 2 + 40)
    // The window is taller still, so an app dragged up far enough to unpin it stays over it (the
    // dock only gets the pointer while it's over its window). Only a drag takes the pointer there.
    // It's sized for the largest icons Settings allows, whatever the size now, so changing the
    // size (a divider drag, the slider) never resizes the window: a resized layer showed one frame
    // with the dock drawn far above the edge (growing) or not at all (shrinking). The empty part
    // is see-through and takes no clicks (the input area is the dock's own, below)
    readonly property real largestIcon: 64                  // (Settings → Dock → Icon size's top)
    readonly property real restThickness: Math.ceil(largestIcon * maxScale + padding * 2 + 40) + Math.ceil(Math.max(120, largestIcon * 2.5)) + 40
    // A divider drag's input area covers all of it, so the press is kept however far the drag
    // goes (the drag's whole range is 36 px)
    readonly property real thickness: restThickness
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
    // (above the wallpaper switcher, which covers the windows: seen, but taking no clicks)
    WlrLayershell.layer: Config.wallpaperSwitching ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Config.wallpaperSwitching ? noInput : dockInput
    readonly property Region dockInput: Region { item: maskBox }
    readonly property Region noInput: Region {}
    // The input area in window coordinates (hitArea is in the turned strip)
    Item {
        id: maskBox
        readonly property var box: {
            win.stripMatrix; hitArea.x; hitArea.y; hitArea.width; hitArea.height;   // re-evaluate on these
            const a = hitArea.mapToItem(win.contentItem, 0, 0), b = hitArea.mapToItem(win.contentItem, hitArea.width, hitArea.height);
            return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) };
        }
        x: box.x; y: box.y; width: box.w; height: box.h
        // (on top of the dock's icons and buttons: a press one of them takes is offered to
        // what's above it first, so beneath them this never saw a press on an icon)
        z: 1000
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
    readonly property real foldFloor: Math.min(24, iconSetting)
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
    // A name for each of those that stays the same while it's the same icon: the app's key, "more",
    // or "divider" and which one it is. The Repeater is keyed by these (see its model)
    function keyOfSlot(x, dividerNo) { return x.kind === "app" ? "app:" + x.item.key : x.kind === "divider" ? "divider:" + dividerNo : x.kind; }
    readonly property var middleKeys: { let d = 0; return middleSlots.map(x => keyOfSlot(x, x.kind === "divider" ? d++ : 0)); }
    function slotByKey(key) { let d = 0; return middleSlots.find(x => keyOfSlot(x, x.kind === "divider" ? d++ : 0) === key) || null; }
    // How many times each icon has been made (the test IPC reads it: it should stay at one)
    property var madeOf: ({})
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
        // The folder's name goes through two readers: the shell that runs the command (so
        // it's in single quotes, a quote of its own written as '\'') and Lua before that
        // (Config.luaString). Dropping its quotes instead opened another folder
        const folder = "'" + downloadsDir.replace(/'/g, "'\\''") + "'";
        Quickshell.execDetached(["hyprctl", "dispatch",
            `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. FILE_MANAGER .. ${Config.luaString(" " + folder)}) end`]);
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
    // (and not while a divider is dragged: the icons hold still, with no previews, as it resizes)
    property real hover: !resizing && ((mouse.containsMouse && shown) || appMenu.visible || dragKey !== "" || fileDrag || testHover) ? 1 : 0
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
    // (resting on a divider or dragging one keeps it shown: the resize area takes the pointer
    // from the dock's own then, and an auto-hiding dock slid away mid-drag and dropped it)
    property bool shown: !movingOut && (!Config.s.dockAutoHide || (!workspaceBusy && !appLauncher.launchingNew) || mouse.containsMouse || resizing || dividerCursor || holdTimer.running || movedHold.running || appMenu.visible || previewPop.visible || dragKey !== "" || fileDrag || Config.wallpaperSwitching)
    Timer { id: holdTimer; interval: win.hideDelay }
    // Moved to another edge: it shows there for a moment (even with auto-hide), so you see
    // where it went. Meanwhile it's kept out of sight until its window has moved: drawn for
    // its new edge while still at the old one, it flickered there
    Timer { id: movedHold; interval: 1500 }
    property bool relocating: false
    Timer { id: relocated; interval: 120; onTriggered: win.relocating = false }
    onEdgeChanged: { relocating = true; relocated.restart(); movedHold.restart(); }
    readonly property real dockHeight: base + padding * 2
    property real offset: shown ? 0 : dockHeight + 4
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
        // The previews' "+N" card, as clicking it does (the app's menu, every window in it)
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
        // The pinned apps' ids, in order, and pinning one (at the end) or unpinning it, as
        // its menu's Pin to Dock does (for assistants: scripts/slate-mcp.py's dock_pin)
        function pinned(): string { return JSON.stringify(win.pinned); }
        function pin(key: string, on: bool): void { if (key && win.pinned.includes(key) !== on) win.setPinned(key, on); }
        // Empty the Waste Basket, as its menu's Empty does once you've said yes (the
        // assistant's waste_basket_empty asks in Slate's words first)
        function emptyTrash(): void { win.emptyTrash(); }
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
        // At most six cards, and never more than fit beside the icon (along the screen for
        // live pictures, from the icon to the screen's far side when the dock's on one; down
        // the screen for titles). An app with more windows than that shows as many as fit
        // with room for one more card, which says how many it has besides and opens the
        // app's menu, where every one of its windows is listed
        readonly property int cap: 6
        readonly property real moreW: 110            // the live "+N" card: narrower than a picture
        readonly property bool live: win.previewMode === "live"
        readonly property real room: live
            ? (win.edge === "left" ? width - atX - 8 : win.edge === "right" ? atX - 8 : width - 16) - 16
            : height - 16 - 12
        readonly property bool capped: wins.length > cap
            || (live ? wins.length * (cardW + 8) - 8 : wins.length * (cardH + 4) - 4) > room
        // How many windows get a card, the "+N" card standing in for the rest
        readonly property int fitCount: !capped ? wins.length
            : Math.max(1, Math.min(cap - 1, live ? Math.floor((room - moreW) / (cardW + 8))
                                                 : Math.floor((room + 4) / (cardH + 4)) - 1))
        // The first ones, in the dock's order, the window you're in always among them
        readonly property var shownWins: {
            if (!capped) return wins;
            const s = wins.slice(0, fitCount);
            const now = wins.find(w => w.activated);
            if (now && !s.includes(now)) s[s.length - 1] = now;
            return s;
        }
        readonly property int moreCount: wins.length - shownWins.length

        Rectangle {
            id: previewBox
            width: previewPop.live ? previewRow.implicitWidth + 16 : previewPop.cardW + 16
            height: previewPop.live ? previewPop.cardH + 16 : titleCol.implicitHeight + 12
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

            // Live: the windows side by side, then "+N" for the rest
            Row {
                id: previewRow
                visible: previewPop.live
                x: 8; y: 8
                spacing: 8
                Repeater {
                    model: previewPop.live ? previewPop.shownWins : []
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
                            textFormat: Text.PlainText        // never markup: the window's title is the app's to choose
                            text: liveCard.modelData.title || ""
                            elide: Text.ElideRight
                            color: liveCard.modelData.activated ? win.activeDotColor : win.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                        }
                        HoverHandler { id: liveHover }
                        ClickTap { hand: false; onTapped: { liveCard.modelData.activate(); win.previewApp = null; } }
                    }
                }
                // The rest: a card of the same shape (no sheen), "+N" where the picture would
                // be, on the dock's own tile colour, and its caption below. Only says how many:
                // not something to click (the app's right-click menu lists every window)
                Rectangle {
                    id: moreCard
                    visible: previewPop.moreCount > 0
                    width: previewPop.moreW; height: previewPop.cardH
                    radius: Config.corner(8)
                    color: "transparent"
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                        height: parent.height - 34
                        radius: Config.corner(6)
                        color: win.tileColor
                        Text {
                            anchors.centerIn: parent
                            text: "+" + previewPop.moreCount
                            color: win.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 22; font.weight: Font.Medium
                        }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8; bottomMargin: 6 }
                        horizontalAlignment: Text.AlignHCenter
                        text: "More windows"
                        elide: Text.ElideRight
                        color: win.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    }
                }
            }

            // Titles: the windows one above another, each with the app's icon, then a row
            // for the rest in the same way
            Column {
                id: titleCol
                visible: !previewPop.live
                x: 6; y: 6
                width: previewBox.width - 12
                spacing: 4
                Repeater {
                    model: !previewPop.live ? previewPop.shownWins : []
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
                            textFormat: Text.PlainText        // never markup: the window's title is the app's to choose
                            text: titleCard.modelData.title || ""
                            elide: Text.ElideRight
                            color: titleCard.modelData.activated ? win.activeDotColor : win.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        HoverHandler { id: titleHover }
                        ClickTap { hand: false; onTapped: { titleCard.modelData.activate(); win.previewApp = null; } }
                    }
                }
                Rectangle {
                    id: moreRow
                    visible: !previewPop.live && previewPop.moreCount > 0
                    width: titleCol.width; height: previewPop.cardH
                    radius: Config.corner(8)
                    color: "transparent"
                    Rectangle {
                        id: moreRowTile
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        radius: Config.corner(6)
                        color: win.tileColor
                        Text {
                            anchors.centerIn: parent
                            text: "+" + previewPop.moreCount
                            color: win.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                    Text {
                        anchors { left: moreRowTile.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "More windows"
                        elide: Text.ElideRight
                        color: win.textColor
                        font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
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
        menuWidth: app && (app.downloadsGrid || app.moreGrid) ? 4 * 88 + 16 + (gridScrolls ? 18 : 0) : 240
        // More's or Downloads' grid with more than its three rows, so it scrolls: the menu
        // widens by the scrollbar's room (an 8 px gap and the bar's 10) while it does, so the
        // cells keep their width and nothing sits under the scrollbar
        readonly property bool gridScrolls: !!app && (app.moreGrid ? moreList.length > 12 : !!app.downloadsGrid && win.recentDownloads.length > 12)
        // The grid sits 8 px in from the menu's rounded edge (DesktopMenu's card: 12), so its
        // shades round their corners to match, the same curve 8 px further in
        readonly property real gridCorner: 12 - 8
        // and, on the menu's dark (the shade's own colour), go deeper and taller than a
        // list's, fading the cells into the menu so they show (light mode: the usual shade)
        readonly property real gridShadeDepth: Config.s.lightMode ? 1 : 2.4
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
        // More's or Downloads' grid while it's open (for the test state): the Flickable,
        // which names its cells, shades and scrollbar
        property Flickable gridFlick: null
        function gridState() {
            const f = gridFlick, r = it => Math.round(it.mapToItem(f, 0, 0).x + it.width);
            return { y: Math.round(f.contentY), height: Math.round(f.height), contentHeight: Math.round(f.contentHeight),
                     menuWidth: menuWidth, cellsRight: r(f.cells), barShown: f.bar.visible,
                     barLeft: Math.round(f.bar.mapToItem(f, 0, 0).x), barRight: r(f.bar),
                     shadeRight: Math.max(r(f.topShade), r(f.bottomShade)),
                     top: Math.round(f.topShade.opacity * 100) / 100, bottom: Math.round(f.bottomShade.opacity * 100) / 100 };
        }

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
            case "settings": win.settingsWindow().goTo(row.target, row.find || ""); break;
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
                readonly property Item cells: moreGridItems
                readonly property Item topShade: moreTopShade
                readonly property Item bottomShade: moreBottomShade
                readonly property Item bar: moreBar
                Component.onCompleted: appMenu.gridFlick = moreScroll
                Component.onDestruction: if (appMenu.gridFlick === moreScroll) appMenu.gridFlick = null
                // (over the cells only, the scrollbar beside them left clear)
                ScrollShade { id: moreTopShade; z: 3; y: moreScroll.contentY; width: moreGridItems.width; cornerRadius: appMenu.gridCorner
                              height: 28; depth: appMenu.gridShadeDepth; distance: moreScroll.contentY }
                ScrollShade { id: moreBottomShade; z: 3; atBottom: true; y: moreScroll.contentY + moreScroll.height - height; width: moreGridItems.width
                              height: 28; depth: appMenu.gridShadeDepth; cornerRadius: appMenu.gridCorner
                              distance: moreScroll.contentHeight - moreScroll.height - moreScroll.contentY }
                ThinScrollbar { id: moreBar; z: 3; flick: moreScroll; color: win.textColor; x: moreScroll.width - width; y: moreScroll.contentY; height: moreScroll.height }
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
                                textFormat: Text.PlainText        // never markup: an app's name
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
                    readonly property Item cells: dlGrid
                    readonly property Item topShade: dlTopShade
                    readonly property Item bottomShade: dlBottomShade
                    readonly property Item bar: dlBar
                    Component.onCompleted: appMenu.gridFlick = dlScroll
                    Component.onDestruction: if (appMenu.gridFlick === dlScroll) appMenu.gridFlick = null
                    // (as More's: over the cells only, the scrollbar beside them left clear)
                    ScrollShade { id: dlTopShade; z: 3; y: dlScroll.contentY; width: dlGrid.width; cornerRadius: appMenu.gridCorner
                                  height: 28; depth: appMenu.gridShadeDepth; distance: dlScroll.contentY }
                    ScrollShade { id: dlBottomShade; z: 3; atBottom: true; y: dlScroll.contentY + dlScroll.height - height; width: dlGrid.width
                                  height: 28; depth: appMenu.gridShadeDepth; cornerRadius: appMenu.gridCorner
                                  distance: dlScroll.contentHeight - dlScroll.height - dlScroll.contentY }
                    ThinScrollbar { id: dlBar; z: 3; flick: dlScroll; color: win.textColor; x: dlScroll.width - width; y: dlScroll.contentY; height: dlScroll.height }
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
                                textFormat: Text.PlainText        // never markup: a file's name
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
        // (a divider dragged from here shows the resize arrow all the same: starting it turns
        // on the resizer above, which has it)
        cursorShape: Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        function stripX(m) { return strip.mapFromItem(mouse, m.x, m.y).x; }
        property point pressedAt
        property bool dragged: false        // moved far enough to be a drag, not a click
        property bool sizing: false         // this press is on a divider: it resizes the dock
        onPressed: m => {
            sizing = m.button === Qt.LeftButton && resizer.overDivider(m);
            if (sizing) { resizer.begin(m); return; }
            pressedAt = Qt.point(m.x, m.y);
            dragged = false;
            const sl = win.slotAt(win.hoveredIndex);
            win.dragCandidate = m.button === Qt.LeftButton && sl && sl.kind === "app" ? sl.item.key : "";
        }
        onPositionChanged: m => {
            if (sizing) { if (pressed) resizer.follow(m); return; }
            win.setPointer(stripX(m));
            if (!pressed) resizer.watch(m);        // (resting on a divider: the resize cursor)
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
        // (sizing is cleared just after a release, once the click that follows it has been
        // skipped, and never left on: while it's on the pointer isn't followed, and the dock
        // stopped magnifying after a resize)
        onReleased: { if (sizing) { win.endResize(); Qt.callLater(() => { sizing = false; }); } else win.endDrag(); }
        onCanceled: { if (sizing) { win.endResize(); sizing = false; } else win.endDrag(); }   // (a drag cut short ends as if let go, never stuck)
        onExited: { holdTimer.restart(); if (!win.dividerCursor) resizer.stopRest(); }
        onClicked: m => {
            if (dragged || sizing) return;  // a drag or a resize, not a click
            win.setPointer(stripX(m));
            win.clickItem(win.hoveredIndex, m.button === Qt.RightButton);
        }
    }
    // The dock's dividers are a handle: drag one away from the screen's edge to make the icons
    // larger, towards it to make them smaller (Settings → Dock → Icon size, saved on letting go).
    // Over one the pointer turns into a resize arrow, once it's rested there a moment. Silent: a
    // drag, not a click. A press anywhere else falls through to `mouse` below
    MouseArea {
        id: resizer
        z: 10.5
        anchors.fill: maskBox
        // Laid over the dock only once the pointer has rested on a divider (or while dragging
        // one). Anything over the whole dock that takes hover, even a passive HoverHandler,
        // keeps the pointer from the dock's own area beneath, and the dock stopped magnifying
        // and sliding. So the dock's own area watches for a rest on a divider (watch(), below),
        // and this switches on just for that, then off again as the pointer leaves it
        enabled: win.dividerCursor || pressed
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: win.dividerCursor ? (win.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor) : Qt.ArrowCursor
        // From the dock's own area as the pointer moves (same box, same coordinates): a rest on a
        // divider shows the resize cursor and lets this take the press
        function watch(m) {
            if (overDivider(m)) rest.restart();             // (still moving: not yet at rest)
            else rest.stop();
        }
        property real startCross: 0
        property real startSize: 0
        // Where the pointer is across the dock, on the screen (moves with the pointer, not the window)
        function cross(m) {
            const p = win.toScreen(resizer.mapToItem(win.contentItem, m.x, m.y));
            return win.vertical ? p.x : p.y;
        }
        // Is the pointer on a divider (a few pixels either side too, to make it easy to grab)?
        function overDivider(m) {
            const p = strip.mapFromItem(resizer, m.x, m.y);
            if (p.y < bg.y || p.y > bg.y + bg.height) return false;
            let start = row.x;
            for (let i = 0; i < win.count; i++) {
                const end = start + win.base * win.slotWidth(i) * win.scaleAt(i);
                const wide = win.isDivider(i) ? 6 : 0;
                if (p.x >= start - wide && p.x <= end + wide) return win.isDivider(i);
                start = end + win.spacing;
            }
            return false;
        }
        Timer { id: rest; interval: 300; onTriggered: win.dividerCursor = true }
        function startRest() { rest.restart(); }
        function stopRest() { rest.stop(); }
        // A drag from a divider, begun here (after a rest) or by the dock's own area (pressed
        // straight away, before the cursor has changed): m in this area's coordinates (the same
        // box as the dock's own)
        function begin(m) {
            startCross = cross(m);
            startSize = Config.s.dockIconSize;
            win.resizeSize = startSize;
            win.dividerCursor = true;
        }
        function follow(m) {
            const grow = win.edge === "bottom" || win.edge === "right" ? startCross - cross(m) : cross(m) - startCross;
            win.resizeSize = Math.max(28, Math.min(64, Math.round(startSize + grow)));
        }
        onPositionChanged: m => {
            if (pressed) follow(m);
            else if (!overDivider(m)) {
                rest.stop();
                win.dividerCursor = false;           // (off again: the dock's own area takes over)
            }
        }
        onExited: { if (!pressed) { rest.stop(); win.dividerCursor = false; } }
        onPressed: m => {
            if (!overDivider(m)) { m.accepted = false; return; }
            begin(m);
        }
        onReleased: win.endResize()
        onCanceled: win.endResize()
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
    property bool dividerCursor: false       // the pointer has rested on a divider (or is dragging it)
    function endResize() {
        if (!resizing) return;
        const size = resizeSize;
        if (size !== Config.s.dockIconSize) Config.s.dockIconSize = size;   // (the same size: no jump)
        resizeSize = -1;
        dividerCursor = false;
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
            // (and while a divider is dragged: the same, so the press is never lost off the dock)
            width: win.dragKey !== "" || win.resizing ? strip.width : Math.max(row.width + win.padding * 2, win.restWidth + win.padding * 2)
            height: !win.shown ? 2 : win.dragKey !== "" || win.resizing ? strip.height : (win.hover > 0 ? win.reach : win.dockHeight)
            y: strip.height - height
        }


        // ---- Drawing -------------------------------------------------------
        Item {
            id: dock
            anchors.fill: parent
            // (slid for hiding)
            transform: Translate { y: win.offset }

            Rectangle {
                id: bg
                width: row.width + win.padding * 2
                height: win.dockHeight
                x: (strip.width - width) / 2
                y: strip.height - height
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
                radius: Config.iconCornerFor(width)
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
                    DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width) }
                    Item {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: width
                        id: launchTile
                        transform: Matrix4x4 { matrix: win.upright(launchTile.width, launchTile.height) }
                        DockGlow {
                            strength: win.glowAt(win.launcherIndex)
                            radius: Config.iconCornerFor(width)
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
                        Gloss { radius: Config.iconCornerFor(parent.width); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
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
                        dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width)
                    }
                    Item {
                        id: mediaWideTile
                        visible: win.mediaWide > 1
                        anchors.bottom: parent.bottom
                        width: parent.width; height: win.base * mediaCell.s
                        readonly property real corner: Config.iconCornerFor(height)
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
                        readonly property real corner: Config.iconCornerFor(width)
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
                    // Keyed by strings, so a window opening or closing, a pin or a drag only adds,
                    // removes or moves the icons that changed instead of making every one again
                    // (a new list of slots each time would, and each would decode its picture again)
                    model: ScriptModel { values: win.middleKeys }
                    delegate: Item {
                        id: cell
                        required property string modelData
                        // This icon's slot, found again by its key whenever the slots are worked out
                        // afresh. Keeps the last one for the moment an icon is on its way out
                        readonly property var found: win.slotByKey(modelData)
                        property var slot: found
                        onFoundChanged: if (found) slot = found
                        readonly property bool isApp: slot.kind === "app"
                        readonly property bool isMore: slot.kind === "more"
                        // The app in this slot ({ key, entry, windows, pinned }; none for a divider;
                        // for More, the windows of the apps in it, so its running dot shows)
                        readonly property var app: isApp ? slot.item
                            : ({ key: "", entry: null, pinned: false,
                                 windows: isMore ? slot.items.reduce((w, it) => w.concat(it.windows), []) : [] })
                        readonly property real s: win.scaleAt(slot.at)
                        opacity: win.fadeAt(slot.at)
                        readonly property var badge: isMore ? win.moreBadge : win.badgeFor(isApp ? app : null)
                        readonly property string tilePath: isApp ? Config.tilePath(app.key) : ""
                        property int version: 0
                        property string tried: ""       // the icon file last drawn for (once per file, so a broken icon isn't retried forever)
                        // Bounces while the app is starting (clicked in the dock): see win.bounceOf
                        readonly property real bounce: win.bounceOf(cell.app.key)
                        readonly property int windowCount: cell.app.windows.length
                        onWindowCountChanged: if (windowCount > 0) win.endLaunch(cell.app.key)
                        Component.onCompleted: {
                            win.madeOf[modelData] = (win.madeOf[modelData] || 0) + 1;
                            if (windowCount > 0) win.endLaunch(cell.app.key);
                        }
                        width: win.base * win.slotWidth(slot.at) * s
                        height: row.height
                        // Moved along to open the gap for an app being dragged in: sliding when the
                        // gap opens, closes or moves past it, at once as the gap grows and shrinks
                        property real past: win.gapAt >= 0 && cell.slot.at >= win.gapAt ? 1 : 0
                        Behavior on past { enabled: !win.settling; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
                        transform: [
                            Matrix4x4 { matrix: win.tiltMatrix(cell.width, cell.height, win.tiltAt(cell.slot.at)) },
                            Translate {
                                x: cell.past * (win.gapWidth + win.spacing); y: -win.liftAt(cell.slot.at)
                                Behavior on y { enabled: win.hoverEffect === "raise"; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
                            }
                        ]

                        // A divider: a faint line across the dock, between the pinned apps and
                        // the others (and before Downloads and the Waste Basket)
                        Rectangle {
                            visible: cell.slot.kind === "divider"
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
                            dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width)
                        }
                        Item {
                            id: moreTile
                            visible: cell.isMore
                            anchors.bottom: parent.bottom
                            width: parent.width; height: width
                            transform: Matrix4x4 { matrix: win.upright(moreTile.width, moreTile.height) }
                            DockGlow {
                                strength: win.glowAt(cell.slot.at)
                                radius: Config.iconCornerFor(width)
                            }
                            IconPlate {
                                anchors.fill: parent
                                drawSize: win.base * win.maxScale
                                shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                                fill: false
                                color: win.tileColor
                                opacity: Config.dockTileOpacity
                            }
                            Gloss { radius: Config.iconCornerFor(parent.width); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
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
                            dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width)
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
                                strength: win.glowAt(cell.slot.at)
                                colour: win.glowColour(cell.tilePath)
                                radius: Config.iconCornerFor(width)
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
                    DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width) }
                    Item {
                        id: downloadsTile
                        anchors.bottom: parent.bottom
                        width: parent.width; height: width
                        transform: Matrix4x4 { matrix: win.upright(downloadsTile.width, downloadsTile.height) }
                        DockGlow {
                            strength: win.glowAt(win.downloadsIndex)
                            radius: Config.iconCornerFor(width)
                        }
                        IconPlate {
                            anchors.fill: parent
                            drawSize: win.base * win.maxScale
                            shape: Config.s.iconShape === "original" ? "tile" : Config.s.iconShape
                            fill: false
                            color: win.tileColor
                            opacity: Config.dockTileOpacity
                        }
                        Gloss { radius: Config.iconCornerFor(parent.width); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
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
                    DockBacking { dockTop: bg.y - row.y; color: win.dockColor; radius: Config.iconCornerFor(width) }
                    Item {
                        id: trashTile
                        anchors.bottom: parent.bottom
                        width: parent.width; height: width
                        transform: Matrix4x4 { matrix: win.upright(trashTile.width, trashTile.height) }
                        DockGlow {
                            strength: win.glowAt(win.trashIndex)
                            radius: Config.iconCornerFor(width)
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
                        Gloss { radius: Config.iconCornerFor(parent.width); glassHint: true; tall: false; opacity: Config.dockTileOpacity }
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
                    textFormat: Text.PlainText        // never markup: an app's name, a window's or a track's title
                    text: label.text.charAt(0).toUpperCase() + label.text.slice(1)   // kitty -> Kitty
                    color: win.textColor
                    font.family: win.fontFamily
                    font.weight: win.fontWeight
                    font.pixelSize: win.fontSize
                }
            }
        }
    }

    // ---- For the test suite (shell.qml's `test` IPC target calls these) ---------------------
    // Less room for the dock's things than its edge has (px; 0: the whole edge)
    function setTestRoom(px) { win.testRoom = px; }
    // The dock's own menu (its empty space): "open", or an item to choose, as barMenu does
    function testMenu(what) {
        if (what === "open") { dockMenu.openHere(); return; }
        const path = what.split("/");
        let row = dockMenu.items.find(i => i.label === path[0]);
        if (row && path.length > 1 && row.submenu) row = row.submenu.find(i => i.label === path[1]);
        dockMenu.close();
        if (row && row.run) row.run();
    }
    // Drag an app as the pointer would: picked up (if it isn't already), held over slot i (as the
    // slots are now), `up` pixels up from the dock's middle
    function testDrag(key, i, up) {
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
    // Drag a divider as the pointer would: `px` pixels away from the screen's edge (negative:
    // towards it), from the icon size Settings has; testDividerDrop lets go (saves)
    function testDividerDrag(px) {
        if (!resizing) resizeSize = Config.s.dockIconSize;
        resizeSize = Math.max(28, Math.min(64, Math.round(Config.s.dockIconSize + px)));
        dividerCursor = true;
    }
    function testDividerDrop() { endResize(); }
    // The pointer resting on a divider (or leaving it): the resize cursor shows after a pause
    function testDividerHover(on) {
        if (!on) { resizer.stopRest(); dividerCursor = false; } else resizer.startRest();
    }
    function testDrop() { win.endDrag(); win.testHover = false; }
    // Drag an app out of More's grid (open: dock more), held over slot i of the dock
    function testDragMore(key, i, up) {
        if (win.dragKey === "") {
            if (!(appMenu.visible && appMenu.app && appMenu.app.moreGrid)) return;
            win.pickFromMore(key);
        }
        const x = (strip.width - win.restWidth) / 2 + win.slotStart(Math.max(0, i)) + (i < 0 ? -win.base * 2 : win.base * 0.25);
        const sp = win.toScreen(strip.mapToItem(win.contentItem, x, bg.y + bg.height / 2 - up));
        win.carryFromMore(sp);
    }
    function testDropMore() { win.dropFromMore(); }
    // Scroll More's or Downloads' grid (open) to y, as far as it goes
    function testScrollGrid(y) {
        const f = appMenu.gridFlick;
        if (f) f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, y));
    }
    // Magnify as if the pointer were over slot i (-1: as if it had left)
    function testHoverSlot(i) {
        win.testHover = i >= 0;
        if (i >= 0) win.setPointer((strip.width - win.restWidth) / 2 + win.slotStart(i) + win.slotWidth(i) * win.base / 2);
    }
    // Whether the dock's input region is its own (not the whole screen's), for state's input.dock
    function testInputOwn() { return win.mask === win.dockInput; }
    // The dock's part of state
    function testState() {
        return {
            pinned: win.pinned, screen: win.screen ? win.screen.name : "",
            dragging: win.dragKey, dropIndex: win.dropIndex, dragAway: win.dragAway, gapAt: win.gapAt,
            dragFromMore: win.dragFromMore, menuLifted: appMenu.lifted, moreGrid: appMenu.moreList.map(it => it.key),
            slots: win.slots.map(x => x.kind === "app"
                ? { kind: "app", key: x.item.key, pinned: x.item.pinned, windows: x.item.windows.length, badge: win.badgeFor(x.item) }
                : { kind: x.kind }),
            menu: appMenu.visible ? (appMenu.app && appMenu.app.key ? appMenu.app.key : appMenu.app && appMenu.app.moreGrid ? "more" : "other") : "",
            preview: previewPop.wanted, previewOnScreen: previewPop.visible, media: win.mediaShown, trash: win.trashCount,
            // The previews: cards shown, the "+N" card's count, the panel's place and the screen's size
            previews: previewPop.wanted ? { cards: previewPop.shownWins.length, more: previewPop.moreCount, mode: win.previewMode,
                                            box: [Math.round(previewBox.x), Math.round(previewBox.y), Math.round(previewBox.width), Math.round(previewBox.height)],
                                            screen: [Math.round(previewPop.width), Math.round(previewPop.height)] } : null,
            base: Math.round(win.base * 100) / 100, length: Math.round(win.restWidth + win.padding * 2), room: Math.round(win.roomLength),
            more: win.moreItems.map(it => it.key), mediaCompact: win.foldPlan.compact,
            moreOpen: appMenu.visible && !!appMenu.app && !!appMenu.app.moreGrid,
            // More's or Downloads' grid as it scrolls: where the cells end and the
            // scrollbar starts (menu coordinates), and how strong each shade is now
            grid: appMenu.gridFlick ? appMenu.gridState() : null,
            hoverEffect: win.hoverEffect, made: win.madeOf,
            shown: win.shown, resizing: win.resizing, windowSize: Math.round(win.thickness),
            inputSize: [Math.round(maskBox.width), Math.round(maskBox.height)], windowBox: [Math.round(win.width), Math.round(win.height)],
            busy: win.workspaceBusy,
            dividerCursor: win.dividerCursor ? (win.vertical ? "horizontal" : "vertical") : "arrow",
            fade: win.slots.map(x => Math.round(win.fadeAt(x.at) * 100) / 100),
            glow: win.slots.map(x => Math.round(win.glowAt(x.at) * 100) / 100),
            lift: win.slots.map(x => Math.round(win.liftAt(x.at))),
            tilt: win.slots.map(x => Math.round(win.tiltAt(x.at))), scale: win.slots.map(x => Math.round(win.scaleAt(x.at) * 100) / 100)
        };
    }
    // The dock's own menu, for state's dockMenu: each item, its submenu's items, and which are
    // ticked (icon 0xEA5E)
    function testMenuState() {
        return { open: dockMenu.visible, items: dockMenu.items.map(i => i.separator ? null
            : { label: i.label, ticked: i.icon === 0xEA5E, sub: i.submenu ? i.submenu.map(j => j.separator ? null : { label: j.label, ticked: j.icon === 0xEA5E }) : null }) };
    }
}
