pragma Singleton
// The menu bar's arrangement: what's on it and in what order, the things that can be (Bar.qml
// draws them; Settings → Menu Bar and the arranging panel, BarEditor.qml, change it), and the
// whole arrangement at once for the assistant. Split from Config.qml, which keeps barArranging
// (the bar's glass and shadow follow it) and the setting itself (Config.s.barLayout).
import QtQuick
import Quickshell

Singleton {
    id: root

    // ---- The menu bar's arrangement (Bar.qml draws it; Settings → Menu Bar changes it) -------
    // Slate's own: the control centre; Apps with Nova; Spaces with the window mode and the
    // workspace dots; the active window; a flexible space; then the tray, the status icons,
    // More, the clock and the power button
    readonly property var barStatusItems: ["notifications", "clipboard", "screenshot", "camera", "drink", "focus", "gamemode", "keyboard", "bluetooth", "volume", "wifi", "battery"]
    readonly property var barLayoutDefault: [
        barBox(["control"]), barBox(["apps", "nova"]),
        barBox(["spaces", "windowmode", "workspaces", "workspacename"]),
        barBox(["windowicon", "windowtitle"]), "space",
        barBox(["tray"]), barBox(barStatusItems, { tuck: Config.s.barStatusCollapsed }), barBox(["more"]), barBox(["clock"]), barBox(["power"])
    ]
    // Everything that can be in a container: its name in the arrangement, what it's called, its
    // icon (for the pool on Settings → Menu Bar), and the setting that says whether it shows
    readonly property var barItems: [
        { id: "control", label: "Control Center", icon: 0xEAD7, key: "barShowControl" },
        { id: "apps", label: "Apps", icon: 0xEC42, key: "barShowApps" },
        { id: "spaces", label: "Spaces", icon: 0xEDBA, key: "barShowSpaces" },
        { id: "nova", label: "Nova", icon: 0xF014, key: "barShowAssistant" },
        { id: "windowmode", label: "Window mode", icon: 0xEFE6, key: "barShowWindowMode" },
        { id: "workspaces", label: "Workspaces", icon: 0xEA95, key: "barShowWorkspaces" },
        { id: "workspacename", label: "Workspace name", icon: 0xFF38, key: "barShowWorkspaceName" },
        { id: "windowicon", label: "Window icon", icon: 0xEFE6, key: "barShowTitleIcon" },
        { id: "windowtitle", label: "Window title", icon: 0xEBC5, key: "barShowTitle" },
        { id: "tray", label: "Tray", icon: 0xEA61, key: "barShowTray" },
        { id: "notifications", label: "Notifications", icon: 0xEA35, key: "barShowNotifications" },
        { id: "clipboard", label: "Clipboard", icon: 0xEA6F, key: "barShowClipboard" },
        { id: "screenshot", label: "Screenshot", icon: 0xF201, key: "barShowScreenshot" },
        { id: "camera", label: "Camera", icon: 0xEA9A, key: "barShowCamera" },
        { id: "drink", label: "Drink reminder", icon: 0xEA97, key: "barShowDrink" },
        { id: "focus", label: "Focus timer", icon: 0xEA70, key: "barShowFocus" },
        { id: "gamemode", label: "Game Mode", icon: 0xF1D2, key: "barShowGameMode" },
        { id: "keyboard", label: "Keyboard layout", icon: 0xEBD6, key: "barShowKeyboard" },
        { id: "bluetooth", label: "Bluetooth", icon: 0xEA37, key: "barShowBluetooth" },
        { id: "volume", label: "Volume", icon: 0xEB51, key: "barShowVolume" },
        { id: "wifi", label: "Wi-Fi", icon: 0xEB52, key: "barShowWifi" },
        { id: "battery", label: "Battery", icon: 0xEA30, key: "barShowBattery" },
        { id: "clock", label: "Clock", icon: 0xEA70, key: "barShowClock" },
        { id: "power", label: "Power", icon: 0xEB0D, key: "barShowPower" },
        // (what holds whatever there isn't room for: always on the bar, placed like the rest,
        // but never taken off it. No switch of its own, so no key)
        { id: "more", label: "More", icon: 0xEA95, key: "" }
    ]
    function barItem(id) { return barItems.find(i => i.id === id) || null; }
    // What a tray icon is called (the label off the bar says it): the app's title for it, or its
    // tooltip's title, or else its id; tidied, so a raw id reads as a name
    function trayName(item) {
        if (!item) return "";
        for (const n of [item.title, item.tooltipTitle, item.id]) { const t = trayTidy(n); if (t !== "") return t; }
        return "";
    }
    // Words are left as they are ("Fake tray app"). One with no spaces is an id: its last part
    // if it's dotted (org.kde.kdeconnect), split at _, - and camelCase, with numbers and words
    // that only say it's a tray icon (status, icon, tray, indicator…) left out, and a capital
    // first: "chrome_status_icon_1" → "Chrome", "nm-applet" → "Nm", "steam" → "Steam". Nothing left
    // ("StatusNotifierItem-1234-1", Qt's own made-up id): "", and no label
    function trayTidy(raw) {
        const t = String(raw || "").trim();
        if (t === "" || /\s/.test(t)) return t;
        const word = t.split(".").filter(p => p !== "").pop() || t;
        const parts = word.replace(/([a-z])([A-Z])/g, "$1 $2").split(/[\s_\-]+/).filter(p => p !== "" && !/^\d+$/.test(p));
        const filler = ["status", "icon", "tray", "indicator", "notifier", "notification", "item", "sni", "applet", "appindicator", "systray"];
        const kept = parts.filter(p => filler.indexOf(p.toLowerCase()) < 0);
        if (kept.length === 0) return "";
        const out = kept.join(" ");
        return out.charAt(0).toUpperCase() + out.slice(1);
    }
    // A saved name for something on the bar, as it's called now: Nova's button was "chalk"
    // (its old name) in arrangements and orders saved before it was renamed (Migration, kept until 2027-06)
    function barId(id) { return id === "chalk" ? "nova" : String(id); }
    // A fixed space in the arrangement: "fixed:<n>px", or "fixed:<n>%" of the screen's width (its
    // height on a side bar): { n, unit } for one, null for anything else. Kept as a word like the
    // flexible space ("space"), so whatever passes over spaces passes over these too
    function barFixed(e) {
        const m = typeof e === "string" ? /^fixed:(\d{1,4})(px|%)$/.exec(e) : null;
        return m ? { n: Number(m[1]), unit: m[2] } : null;
    }
    // (sizes kept sensible: 1 to 1000 pixels, 1 to 50% of the screen)
    function barFixedEntry(n, unit) {
        const u = unit === "%" ? "%" : "px";
        const v = Math.round(Math.max(1, Math.min(u === "%" ? 50 : 1000, Number(n) || 0)));
        return "fixed:" + v + u;
    }
    // The arrangement in use: the saved one, tidied (only things Slate knows, each once; a
    // container with nothing left in it dropped; anything it leaves out given a container of
    // its own at the end, so nothing can be lost), or Slate's own when there's none
    readonly property var barLayout: {
        const saved = Config.s.barLayout;
        if (!saved || saved.length === undefined || saved.length === 0) return barLayoutDefault;
        const known = barItems.map(i => i.id);
        const seen = {}, out = [];
        let spaces = 0;
        for (let i = 0; i < saved.length; i++) {
            const e = saved[i];
            if (e === "space") { spaces++; out.push("space"); }
            else if (barFixed(e)) { const f = barFixed(e); out.push(barFixedEntry(f.n, f.unit)); }
            // (from when the window's icon and title were one thing of its own on the line)
            else if (e === "title") {
                const items = ["windowicon", "windowtitle"].filter(id => !seen[id]);
                for (const id of items) seen[id] = true;
                if (items.length > 0) out.push(barBox(items, null));
            }
            else if (e && e.items && e.items.length !== undefined) {
                const items = [];
                for (let j = 0; j < e.items.length; j++) {
                    const id = barId(e.items[j]);
                    if (known.indexOf(id) >= 0 && !seen[id]) { seen[id] = true; items.push(id); }
                }
                // (an empty one stays only while it's fresh from the pool, waiting for its first thing)
                if (items.length > 0) out.push(barBox(items, e));
                else if (e.keep) { const b = barBox(items, null); b.keep = true; out.push(b); }
            }
        }
        // (there's always one flexible space: without one nothing takes up the spare room)
        if (spaces === 0) out.splice(out.findIndex(e => typeof e !== "string" && e.items.indexOf("windowtitle") >= 0) + 1 || out.length, 0, "space");
        // (a saved arrangement from before there was a More: it goes just before the clock)
        if (!seen["more"]) {
            seen["more"] = true;
            const at = out.findIndex(e => typeof e !== "string" && e.items.indexOf("clock") >= 0);
            out.splice(at >= 0 ? at : out.length, 0, barBox(["more"], null));
        }
        // (anything new since it was saved: a status icon joins the other status icons, the rest
        // a container of its own at the end)
        for (const id of known) {
            if (seen[id]) continue;
            const box = barStatusItems.indexOf(id) >= 0
                ? out.find(e => typeof e !== "string" && e.items.some(x => x !== id && barStatusItems.indexOf(x) >= 0)) : null;
            if (box) {
                const t = box.items.indexOf("tuck");
                if (t >= 0 && t === box.items.length - 1) box.items.splice(t, 0, id); else box.items.push(id);
            } else out.push(barBox([id], null));
        }
        return out;
    }
    // A container as the bar wants it, from its real items and how it was saved. Its collapse
    // button is one of the things in it, "tuck" (at most one, at its start or its end: that's
    // which end the button sits at, the rest sliding out from it): `tuck` and `tuckFrom` say
    // the same for the bar. Saved the old way (tuck: true), the button goes at the end
    function barBox(items, saved) {
        // How it collapses: "never", "always" (tucked behind its button
        // until that's clicked) or "needed" (only when the bar's short of room), which is how
        // a container starts. From before there were modes: one with a button is "always"
        const legacy = !!saved && ((saved.items && saved.items.indexOf("tuck") >= 0) || !!saved.tuck);
        const mode = saved && ["never", "always", "needed"].indexOf(saved.collapse) >= 0 ? saved.collapse : legacy ? "always" : "needed";
        const first = !!saved && ((saved.items && saved.items[0] === "tuck") || saved.tuckFrom === "start");
        const has = mode === "always";
        const all = !has ? items : first ? ["tuck"].concat(items) : items.concat(["tuck"]);
        return { items: all, tuck: has, collapse: mode, tuckIcon: String((saved && saved.tuckIcon) || ""), tuckFrom: first ? "start" : "end" };
    }

    // ---- Arranging it (Settings → Menu Bar → Edit layout; BarEditor.qml, the panel by the bar) ----
    property int barSelected: -1               // what's picked on the bar, by its place in the arrangement...
    property string barSelectedItem: ""        // ...and, when it's one thing in a container, its name ("tuck": the collapse button)
    onBarSelectedChanged: if (barSelected < 0) barSelectedItem = ""
    // Pick something (a container or a flexible space: item ""); again lets go of it
    function barPick(at, item) {
        if (barSelected === at && barSelectedItem === (item || "")) { barSelected = -1; return; }
        barSelectedItem = item || "";
        barSelected = at;
    }
    // The setting that says whether an item's text shows beside its icon ("" if it has none)
    readonly property var barTextKeys: ({ clipboard: "barValueClipboard", gamemode: "barValueGameMode",
        drink: "barValueDrink", focus: "barValueFocus", wifi: "barValueWifi",
        keyboard: "barValueKeyboard", bluetooth: "barValueBluetooth", volume: "barValueVolume", battery: "barValueBattery" })
    // (should Slate have gone away mid-arranging, its keys would have stayed: the usual ones back)
    Timer { running: !Config.isLoginScreen; interval: 0; onTriggered: Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.submap("reset"))`]) }
    Connections { target: Config; function onBarArrangingChanged() { root.arrangingChanged(); } }
    function arrangingChanged() {
        // While it's arranged, Hyprland's shortcuts stand down (no switching workspace, no
        // moving or closing windows under it): a set of keys with only Escape in it, which
        // ends the arranging. Back to the usual ones after
        Quickshell.execDetached(["hyprctl", "eval", Config.barArranging
            ? `if not SLATE_ARRANGING then SLATE_ARRANGING = true; hl.define_submap("slate-arranging", function() `
              + `hl.bind("Escape", hl.dsp.exec_cmd("${Config.slateCommand} ipc call bar edit done")) end) end; hl.dispatch(hl.dsp.submap("slate-arranging"))`
            : `hl.dispatch(hl.dsp.submap("reset"))`]);
        barPrioritising = false;
        if (Config.barArranging) return;
        barSelected = -1; barCarry = null; barCarryTarget = null; barLeaving = false; barFloat = null; barLanding = false; barPreview = 0;
        // (a container put on the bar and never given anything goes)
        if (barLayout.some(e => typeof e !== "string" && e.keep)) barSave(barCopy().filter(e => typeof e === "string" || !e.keep));
    }
    // Something carried from the pool in the panel (BarEditor.qml) towards the bar: what it is
    // ({ kind: "item" | "space" | "box", id }), where the pointer is on the
    // desktop, and, from the bar under it, where it would land ({ join, to, slot, bar })
    property var barCarry: null
    property point barCarryAt: Qt.point(0, 0)
    property var barCarryTarget: null
    // ...and the other way: something on the bar dragged off it (let go, it's back in the pool)
    property bool barLeaving: false
    // What's being dragged, from the bar or the pool, drawn under the pointer over everything
    // (BarEditor.qml): { kind, icons: [{ code, item }], label }, and where on the desktop
    property var barFloat: null
    property point barFloatAt: Qt.point(0, 0)
    // ...gliding into the gap it was let go over, before it's moved there (BarArranger.qml)
    property bool barLanding: false
    // Let go of what's carried: onto the bar where it was aimed (true), or nowhere (false)
    function barDrop() {
        const c = barCarry, t = barCarryTarget;
        barCarry = null; barCarryTarget = null;
        if (!c || !t) return false;
        if (c.kind === "item") { barSetShown(c.id, true); barMoveItem(c.id, t.to, t.join ? t.slot : -1); }
        else if (c.kind === "space") barAddSpace(t.to);
        else if (c.kind === "fixed") barAddFixed(t.to);
        else if (c.kind === "box") barAddBox(t.to);
        else if (c.kind === "tuck") {
            if (!t.join) return false;
            barSetTuck(t.to, true, undefined, t.slot <= barLayout[t.to].items.length / 2 ? "start" : "end");
        }
        return true;
    }
    // A copy of the arrangement to change and save: each container's real items (its collapse
    // button apart, as tuck / tuckFrom). Every change goes through barSave, which puts the
    // button back among the items and drops containers left empty
    function barCopy() {
        return barLayout.map(e => typeof e === "string" ? e
            : { items: e.items.filter(id => id !== "tuck"), collapse: e.collapse || "needed", tuckFrom: e.tuckFrom || "end", tuckIcon: e.tuckIcon || "", keep: !!e.keep });
    }
    function barSave(list) {
        Config.s.barLayout = list.filter(e => typeof e === "string" || (e.items && (e.items.length > 0 || e.keep)))
            .map(e => typeof e === "string" ? e
                : e.items.length === 0 ? { items: [], keep: true }
                : { items: e.items, collapse: e.collapse || "needed", tuckFrom: e.tuckFrom === "start" ? "start" : "end", tuckIcon: e.tuckIcon || "" });
    }
    // The bar counts a container's things with its collapse button among them: the same place
    // among its real items
    function barSlot(at, slot) {
        const e = barLayout[at];
        return e && typeof e !== "string" && e.items[0] === "tuck" ? Math.max(0, slot - 1) : slot;
    }
    function barWhere(list, id) {
        for (let i = 0; i < list.length; i++) {
            if (typeof list[i] === "string") continue;
            const j = list[i].items.indexOf(id);
            if (j >= 0) return { box: i, slot: j };
        }
        return null;
    }
    // Move an item: into the container at place `to` (before its item number `slot`), or, with
    // slot < 0, into a container of its own before whatever is at place `to` (to = how many
    // things there are: at the end)
    function barMoveItem(id, to, slot) {
        const list = barCopy();
        const from = barWhere(list, id);
        if (!from) return;
        if (slot < 0) {
            const marker = { items: [], collapse: "needed", tuckFrom: "end", tuckIcon: "" };
            list.splice(Math.max(0, Math.min(list.length, to)), 0, marker);
            const now = barWhere(list, id);
            list[now.box].items.splice(now.slot, 1);
            marker.items = [id];
        } else {
            const target = list[to];
            if (!target || typeof target === "string") return;
            const at = Math.max(0, Math.min(target.items.length, barSlot(to, slot)));
            if (target === list[from.box]) {
                target.items.splice(from.slot, 1);
                target.items.splice(from.slot < at ? at - 1 : at, 0, id);
            } else {
                list[from.box].items.splice(from.slot, 1);
                target.items.splice(at, 0, id);
            }
        }
        barSelected = -1;
        barSave(list);
    }
    // Move a container's collapse button: to the container at `to`, at its start or its end
    // (whichever `slot`, counted as the bar does, is nearer; one that already has a button
    // keeps its own), or, with to < 0 (dropped outside any container), off the bar: that
    // container no longer tucks
    function barMoveTuck(from, to, slot) {
        const list = barCopy();
        const src = list[from];
        if (!src || typeof src === "string" || src.collapse !== "always") return;
        const dst = to >= 0 ? list[to] : null;
        if (dst && typeof dst === "string") return;
        if (dst && dst !== src && dst.collapse === "always") return;
        const icon = src.tuckIcon;
        src.collapse = "never";
        if (dst) {
            dst.collapse = "always";
            dst.tuckFrom = slot <= barLayout[to].items.length / 2 ? "start" : "end";
            dst.tuckIcon = icon;
        }
        barSelected = -1;
        barSave(list);
    }
    // Move a whole thing (a container, a flexible space) to before what's at `to`
    function barMoveEntry(from, to) {
        const list = barCopy();
        if (from < 0 || from >= list.length) return;
        const e = list[from];
        list.splice(Math.max(0, Math.min(list.length, to)), 0, e);
        list.splice(from < to ? from : from + 1, 1);
        barSelected = -1;
        barSave(list);
    }
    // Slate's own arrangement again: its order and containers, and everything it starts with
    // on the bar (what each thing shows, like its text, is left as it is)
    // (an arrangement that's been changed and put back by hand is the default again too)
    readonly property bool barIsDefault: (!Config.s.barLayout || Config.s.barLayout.length === 0 || JSON.stringify(barLayout) === JSON.stringify(barLayoutDefault))
        && !Config.s.barStatusCollapsed
        && barItems.every(i => i.key === "" || Config.sameValue(Config.s[i.key], Config.defaultOf(i.key)))
        && (!Config.s.barOverflow || Config.s.barOverflow.length === 0) && Config.sameValue(Config.s.barStay, Config.defaultOf("barStay"))
    signal barRedraw()          // (the bar lays its line again, drawing everything afresh)
    function barReset() {
        barSelected = -1;
        barRedraw();
        for (const i of barItems) if (i.key !== "") Config.s[i.key] = Config.defaultOf(i.key);
        Config.s.barStatusCollapsed = Config.defaultOf("barStatusCollapsed");
        Config.s.barLayout = [];
        Config.s.barOverflow = [];
        Config.s.barStay = Config.defaultOf("barStay");
    }
    // An empty container, to drag things into (it goes again if it's left empty)
    function barAddBox(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, { items: [], keep: true });
        barSave(list);
    }
    readonly property int barSpaces: barLayout.filter(e => e === "space").length
    function barAddSpace(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, "space");
        barSave(list);
    }
    // A fixed space, 32 pixels to start with (its options change it)
    function barAddFixed(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, barFixedEntry(32, "px"));
        barSave(list);
    }
    // A fixed space's size: n pixels, or n% of the screen
    function barSetFixed(at, n, unit) {
        const list = barCopy();
        if (!barFixed(list[at])) return;
        list[at] = barFixedEntry(n, unit);
        barSave(list);
    }
    // Take a flexible space away; for a container, put its items back in the pool (they keep
    // their place, for when they're put back)
    function barRemoveEntry(at) {
        const list = barCopy();
        const e = list[at];
        if (e === "space") { if (barSpaces < 2) return; list.splice(at, 1); barSave(list); }      // (the last one stays)
        else if (barFixed(e)) { list.splice(at, 1); barSave(list); }
        else if (e && e.items.length === 0) { list.splice(at, 1); barSave(list); }      // (an empty one, fresh from the pool)
        else if (e) for (const id of e.items) barSetShown(id, false);
        barSelected = -1;
    }
    // Each of a container's items into a container of its own, where it was
    function barSplit(at) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string" || e.items.length < 2) return;
        list.splice(at, 1, ...e.items.map(id => ({ items: [id], collapse: "needed", tuckFrom: "end", tuckIcon: "" })));
        barSelected = -1;
        barSave(list);
    }
    // Give the container at `at` a collapse button or take it away; choose the button's icon
    // (a Tabler codepoint, as hex; "" for Slate's own) and which end it sits at ("start" / "end").
    // Leave any of them undefined to keep it as it is
    function barSetTuck(at, tuck, icon, from) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string") return;
        if (tuck !== undefined) e.collapse = tuck ? "always" : "never";
        if (from !== undefined) e.tuckFrom = from === "start" ? "start" : "end";
        if (icon !== undefined) e.tuckIcon = String(icon || "");
        barSave(list);
    }
    // How the container at `at` collapses: "never", "always" or "needed"
    function barSetCollapse(at, mode) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string" || ["never", "always", "needed"].indexOf(mode) < 0) return;
        e.collapse = mode;
        barSave(list);
    }
    // The order things leave a bar that's short of room, first to go first (Slate's own; the
    // last three stay)
    readonly property var barOverflowDefault: ["tray", "clipboard", "screenshot", "camera", "drink", "focus", "gamemode", "keyboard", "bluetooth", "workspacename", "windowtitle", "windowicon",
        "nova", "spaces", "apps", "notifications", "battery", "wifi", "volume", "windowmode", "workspaces"]
    // The order in use: yours (Settings → Menu Bar → Edit layout → If it doesn't fit), with
    // anything it leaves out put in from Slate's own, so every thing has a place; and the
    // things that stay on the bar whatever happens. More isn't one of them: it's what the
    // rest leave for
    readonly property var barStay: {
        const known = barItems.map(i => i.id);
        return (Config.s.barStay && Config.s.barStay.length !== undefined ? Array.from(Config.s.barStay) : []).map(barId).filter((id, i, a) => known.indexOf(id) >= 0 && id !== "more" && a.indexOf(id) === i);
    }
    readonly property var barOverflowOrder: {
        const known = barItems.map(i => i.id).filter(id => id !== "more");
        const saved = (Config.s.barOverflow && Config.s.barOverflow.length !== undefined ? Array.from(Config.s.barOverflow) : []).map(barId);
        const out = saved.filter((id, i, a) => known.indexOf(id) >= 0 && a.indexOf(id) === i);
        const own = barOverflowDefault.concat(["control", "clock", "power"]);
        for (const id of own.concat(known)) if (out.indexOf(id) < 0 && known.indexOf(id) >= 0) out.push(id);
        return out;
    }
    function barOverflowRank(id) { const i = barOverflowOrder.indexOf(id); return i < 0 ? 1000 : i; }
    function barStays(id) { return barStay.indexOf(id) >= 0; }
    // Set the order and what stays together (the arranging panel's list, after a drag)
    function barSetOverflow(order, stay) { Config.s.barOverflow = order.concat(stay.filter(id => order.indexOf(id) < 0)); Config.s.barStay = stay; }
    function barSetStay(id, on) {
        const stay = barStay.filter(x => x !== id);
        if (on) stay.push(id);
        Config.s.barStay = stay;
    }
    // ---- The whole arrangement at once (the assistant's bar_arrange, over `slate ipc call bar …`) ----
    // As it is: containers with what's on the bar in them (things in the pool left out), how
    // each collapses and which end its button sits at, what's in the pool, the order things
    // leave a bar short of room and what always stays. Nova's button is the person's own: an
    // assistant isn't told whether it's on, and never switches it
    function barArrangement() {
        return {
            layout: barLayout.map(e => typeof e === "string" ? e
                : { items: e.items.filter(id => id !== "tuck" && (id === "more" || barShown(id))),
                    collapse: e.collapse || "needed", collapseAt: e.tuckFrom || "end" })
                .filter(e => typeof e === "string" || e.items.length > 0),
            offBar: barItems.filter(i => i.key !== "" && i.id !== "nova" && !barShown(i.id)).map(i => i.id),
            leaveFirst: barOverflowOrder.filter(id => !barStays(id)),
            alwaysStay: barStay,
            slatesOwn: barIsDefault
        };
    }
    // Set it: { reset } puts Slate's own back; otherwise any of { layout, leaveFirst, alwaysStay }.
    // A layout says everything that's on the bar: what it leaves out goes to the pool (keeping
    // its place for later), except Nova's button, which keeps its place and its switch. The
    // server checks the names first; the tidying of barLayout drops anything else
    function barArrange(spec) {
        if (spec.reset) { barReset(); return; }
        if (spec.layout) {
            const old = barCopy();
            const list = spec.layout.map(e => e === "space" ? "space" : barFixed(e) ? barFixedEntry(barFixed(e).n, barFixed(e).unit)
                : { items: e.items.map(barId), collapse: ["never", "always", "needed"].indexOf(e.collapse) >= 0 ? e.collapse : "needed",
                    tuckFrom: e.collapseAt === "start" ? "start" : "end", tuckIcon: "" });
            // (a container keeps the icon its collapse button had, found by its first thing)
            for (const e of list) {
                if (typeof e === "string" || e.items.length === 0) continue;
                const was = barWhere(old, e.items[0]);
                if (was && old[was.box].tuckIcon) e.tuckIcon = old[was.box].tuckIcon;
            }
            const on = {};
            for (const e of list) if (typeof e !== "string") for (const id of e.items) on[id] = true;
            if (!on["nova"]) {
                // Nova's button where it was: beside the thing it was next to, else in a container
                // of its own at the same place
                const was = barWhere(old, "nova");
                const box = was ? old[was.box].items : [];
                const near = was ? (box[was.slot - 1] || box[was.slot + 1]) : "";
                const at = near ? barWhere(list, near) : null;
                if (at) list[at.box].items.splice(box[was.slot - 1] === near ? at.slot + 1 : at.slot, 0, "nova");
                else list.splice(was ? Math.min(was.box, list.length) : list.length, 0, { items: ["nova"], collapse: "needed", tuckFrom: "end", tuckIcon: "" });
            }
            for (const i of barItems) if (i.key !== "" && i.id !== "nova" && !!on[i.id] !== barShown(i.id)) barSetShown(i.id, !!on[i.id]);
            barSelected = -1;
            barSave(list);
        }
        if (spec.leaveFirst || spec.alwaysStay) {
            const stay = (spec.alwaysStay || barStay).map(barId);
            const order = (spec.leaveFirst || barOverflowOrder).map(barId).filter(id => stay.indexOf(id) < 0);
            barSetOverflow(order, stay);
        }
    }

    // Trying the bar shorter while it's arranged (the panel's "Try it shorter"): the share of its
    // length taken off, 0 for none. While it's tried, the bar slims, tucks and overflows as it
    // would; otherwise, arranged, everything's there to be picked up
    // (menu item priority has its window up, in place of the arranging panel: BarEditor.qml)
    property bool barPrioritising: false
    property real barPreview: 0
    readonly property bool barShowAll: Config.barArranging && barPreview <= 0
    // On the bar, or back in the pool: an item's own switch (Settings → Menu Bar)
    function barShown(id) { const it = barItem(id); return !!it && (it.key === "" || !!Config.s[it.key]); }
    // (Put back on the bar, a thing has its text on again: it comes as it first was, whatever
    // it was set to before it went to the pool)
    function barSetShown(id, on) {
        const it = barItem(id);
        if (!it || it.key === "") return;          // (More has no switch: it's never off the bar)
        if (on && !Config.s[it.key] && barTextKeys[id]) Config.s[barTextKeys[id]] = true;
        Config.s[it.key] = !!on;
    }
}
