import QtQuick
import Quickshell
import qs

// ---- Arranging: dragging things about on the bar itself --------------------------
// While the bar's being arranged (Config.barArranging: Settings → Menu Bar → Edit layout), one area lies over the whole
// line, so nothing under it does its usual thing: a press picks something up. An item
// inside a container is picked up by itself; a container by its gripper, and a
// flexible space or the title anywhere, as a whole. Dropped on a container (not at its
// very ends) an item joins it there; dropped anywhere else, whatever it is goes into the
// gap, an item in a container of its own. A press without a drag picks the container,
// for its options in the panel. It works by where things are along the line, and tells
// Config what moved (barMoveItem, barMoveEntry), which redraws the line. Silent while
// dragging, a click on the drop, as everywhere.
MouseArea {
    id: arranger
    // The bar this is for, its line (the BarLine things sit on) and the area that holds the line
    required property var win
    required property Item line
    required property Item area
    anchors.fill: parent
    visible: Config.barArranging
    z: 5
    preventStealing: true
    property var held: null            // { kind: "item" | "entry", name, index, obj, box }
    property bool moved: false
    property real from: 0
    property real at: 0                // where the pointer is, along the line
    property var target: null          // { join, to, slot, at }
    // The gap that's open for what's carried (from here, or from the panel's pool): the
    // slot it is (slotComp), and how long
    property real gapLen: 0
    readonly property var gap: {
        const t = target || carryTarget;
        return t ? { to: t.to, slot: t.join ? t.slot : -1, len: gapLen } : null;
    }
    // The open slot's own place along the line, or null
    function openSlot() {
        const g = gap;
        if (!g) return null;
        let it = null;
        for (const c of line.children) {
            if (g.slot < 0 && c.isSlot && c.to === g.to) it = c;
            else if (g.slot >= 0 && c.isBox && c.index === g.to)
                for (const d of c.row.children) if (d.isSlot && d.slot === g.slot) it = d;
        }
        if (!it || it.len < 2) return null;
        const p = it.mapToItem(line, 0, 0), a = win.vert ? p.y : p.x;
        return { a0: a, a1: a + (win.vert ? it.height : it.width) };
    }
    // What's drawn under the pointer for the thing picked up (BarEditor.qml draws it, over
    // everything): its icons, as they are on the bar
    function floatOf(h) {
        const e = Config.barLayout[h.index];
        const icon = id => { const it = Config.barItem(id), t = line.things[id]; return { code: it ? it.icon : 0, item: id, text: id === "windowtitle" ? "Window" : t && !win.vert ? (t.shownLabel || "") : "" }; };
        if (h.kind === "item" && h.name === "tuck") return { kind: "tuck", icons: [{ code: h.obj.iconCode, item: "" }] };
        if (h.kind === "item") return { kind: "item", icons: [icon(h.name)] };
        if (e === "space") return { kind: "space", icons: [{ code: win.vert ? 0xEB5B : 0xEB59, item: "" }] };
        return { kind: "box", icons: e.items.filter(id => id !== "tuck" && Config.barShown(id)).map(icon) };
    }
    function carry(h, on) {
        if (!h) return;
        if (h.obj) h.obj.carried = on;
    }
    function drop() {
        held = null; target = null; moved = false; leaving = false; edge = -1;
        Config.barLeaving = false; Config.barFloat = null;
    }
    function along(p) { return win.vert ? p.y : p.x; }
    // What's showing on the line, in order, with where each starts and ends along it
    function onLine() {
        const out = [];
        for (const c of line.children) {
            if (!c.visible) continue;
            const a = win.vert ? c.y : c.x, b = a + (win.vert ? c.height : c.width);
            if (c.isSpace) out.push({ kind: "space", obj: c, index: c.index, a0: a, a1: b });
            else if (c.isBox) out.push({ kind: "box", obj: c, index: c.index, a0: a, a1: b });
        }
        return out;
    }
    // A container's showing items, the same way
    function cellsOf(box) {
        const out = [];
        for (const c of box.row.children) {
            if (!c.visible || !c.name) continue;
            const p = c.mapToItem(line, 0, 0), a = win.vert ? p.y : p.x;
            out.push({ cell: c, a0: a, a1: a + (win.vert ? c.height : c.width) });
        }
        return out;
    }
    function pick(a) {
        for (const e of onLine()) {
            if (a < e.a0 || a > e.a1) continue;
            if (e.kind !== "box") return { kind: "entry", index: e.index, obj: e.obj, box: false };
            if (a - e.a0 > e.obj.grip + 1)
                for (const c of cellsOf(e.obj))
                    if (a >= c.a0 && a <= c.a1) return { kind: "item", name: c.cell.name, index: e.index, obj: c.cell, box: true };
            return { kind: "entry", index: e.index, obj: e.obj, box: true };
        }
        return null;
    }
    // Where something would land at `a` along the line: `joins` for what can go inside a
    // container (an item, a collapse button), which lands there when it's over one
    function aim(a, joins) {
        // (over the gap that's already open: there it stays. The rest have moved to make
        // it, and going by where they are now would send it back and forth)
        const now = openSlot();
        if (now && a >= now.a0 - 2 && a <= now.a1 + 2) return target || carryTarget;
        const line = onLine();
        if (joins) {
            for (const e of line) {
                if (e.kind !== "box" || a < e.a0 + 7 || a > e.a1 - 7) continue;
                const cells = cellsOf(e.obj), items = Config.barLayout[e.index].items;
                const k = cells.findIndex(c => (c.a0 + c.a1) / 2 > a);
                const last = cells.length > 0 ? cells[cells.length - 1] : null;
                return k >= 0 ? { join: true, to: e.index, slot: items.indexOf(cells[k].cell.name), at: cells[k].a0 }
                    : { join: true, to: e.index, slot: last ? items.indexOf(last.cell.name) + 1 : items.length, at: last ? last.a1 : e.a1 };
            }
        }
        const k = line.findIndex(e => (e.a0 + e.a1) / 2 > a);
        if (k >= 0) return { join: false, to: line[k].index, slot: -1, at: line[k].a0 - win.gap / 2 };
        const end = line.length > 0 ? line[line.length - 1] : null;
        return { join: false, to: Config.barLayout.length, slot: -1, at: end ? end.a1 + win.gap / 2 : 0 };
    }
    // (press, move and let go as functions of their own, so a test can drag without a pointer)
    onPressed: m => press(m.x, m.y)
    onPositionChanged: m => { last = Qt.point(m.x, m.y); move(m.x, m.y); }
    onReleased: release()
    // The wheel slides a line that's too long to show whole (either way of scrolling)
    onWheel: w => { const d = Math.abs(w.angleDelta.x) > Math.abs(w.angleDelta.y) ? w.angleDelta.x : w.angleDelta.y; win.scrollBy(-d * 0.6); }
    // ...and so does carrying something to either end, faster the nearer the edge: `edge`
    // is where what's carried is along the bar itself (below 0: nothing's carried here)
    property point last
    property real edge: -1
    Timer {
        running: arranger.edge >= 0 && win.scrollMax > 0
        interval: 16; repeat: true
        onTriggered: {
            const zone = 70, far = win.lineLength + 2 * win.sidePadding, a = arranger.edge;
            const push = a < zone ? -(zone - a) : a > far - zone ? a - (far - zone) : 0;
            if (push === 0) return;
            const was = win.scroll;
            win.scrollBy(push * 0.22);
            if (win.scroll === was) return;
            // (the line has moved under what's carried: where it would land is worked out again)
            if (arranger.held && arranger.moved) arranger.move(arranger.last.x, arranger.last.y);
            else arranger.carried();
        }
    }
    function press(x, y) {
        const m = Qt.point(x, y);
        const a = along(mapToItem(line, m.x, m.y));
        held = pick(a); from = a; at = a; moved = false; target = null;
    }
    function move(x, y) {
        const m = Qt.point(x, y);
        if (!held) return;
        at = along(mapToItem(line, m.x, m.y));
        if (!moved && Math.abs(at - from) > 5) {
            // Picked up: it leaves the line (the rest close up, then part where it would
            // land) and comes with the pointer
            moved = true;
            gapLen = win.vert ? held.obj.height : held.obj.width;
            Config.barFloat = floatOf(held);
            carry(held, true);
        }
        if (!moved) return;
        edge = along(mapToItem(area, m.x, m.y));
        const w = mapToItem(null, m.x, m.y), sc = win.screen;
        Config.barFloatAt = Qt.point((sc ? sc.x : 0) + win.windowX + w.x, (sc ? sc.y : 0) + win.windowY + w.y);
        // Well off the bar: let go there and it's back in the pool
        const p = mapToItem(line, m.x, m.y), across = win.vert ? p.x : p.y;
        leaving = across < -40 || across > win.capsuleHeight + 40;
        Config.barLeaving = leaving;
        target = leaving ? null : aim(at, held.kind === "item");
    }
    function release() {
        const h = held, t = target, dragged = moved, off = leaving;
        drop();
        // (it stays off the line until the line's laid again with it in its new place; if
        // nothing came of the drag, it goes back where it was)
        if (dragged && !(off || t)) carry(h, false);
        else if (dragged) back.restart();
        if (!h) { Config.barSelected = -1; return; }
        if (!dragged) {              // a press, not a drag: pick it (or let go of it), for its options in the panel
            Config.barPick(h.index, h.kind === "item" ? h.name : "");
            Config.click();
            return;
        }
        if (off) {
            if (h.kind === "item" && h.name === "tuck") Config.barMoveTuck(h.index, -1, 0);
            else if (h.kind === "item") Config.barSetShown(h.name, false);
            else Config.barRemoveEntry(h.index);
            Config.click();
            return;
        }
        if (!t) return;
        if (h.kind === "item" && h.name === "tuck") Config.barMoveTuck(h.index, t.join ? t.to : -1, t.slot);
        else if (h.kind === "item") Config.barMoveItem(h.name, t.to, t.join ? t.slot : -1);
        else Config.barMoveEntry(h.index, t.to);
        Config.click();
    }
    onCanceled: { carry(held, false); drop(); }
    // (should a drop change nothing, so the line isn't laid again: back on it)
    Timer { id: back; interval: 300; onTriggered: { for (const n in line.things) line.things[n].carried = false; for (const c of line.children) { if (c.isBox) c.settle(); else if (c.carried) c.carried = false; } } }

    // Something carried here from the pool in the panel beside the bar (BarEditor.qml; Config.barCarry): the
    // page says where the pointer is on the desktop; when that's on or near this bar,
    // this bar says where it would land (and shows the line there). The page drops it
    property bool leaving: false
    property var carryTarget: null
    function carried() {
        const c = Config.barCarry, sc = win.screen;
        let t = null;
        if (c && sc && Config.barArranging) {
            // (this bar's window on the desktop: against its edge of its screen)
            const ox = sc.x + win.windowX, oy = sc.y + win.windowY;
            const g = Config.barCarryAt;
            const here = g.x >= sc.x && g.x < sc.x + sc.width && g.y >= sc.y && g.y < sc.y + sc.height;
            const p = line.mapFromItem(null, g.x - ox, g.y - oy);
            const across = win.vert ? p.x : p.y;
            if (here && across > -30 && across < win.capsuleHeight + 30) {
                if (!held) edge = along(area.mapFromItem(null, g.x - ox, g.y - oy));
                const joins = c.kind === "item" || c.kind === "tuck";
                t = aim(along(p), joins);
                if (c.kind === "tuck" && !t.join) t = null;      // (a collapse button only goes in a container)
            }
        }
        if (t && !held) gapLen = c.kind === "space" ? 30 : c.kind === "box" ? 44 : win.capsuleHeight + 8;
        if (!t && !held) edge = -1;
        carryTarget = t;
        if (t) Config.barCarryTarget = { join: t.join, to: t.to, slot: t.slot, bar: win };
        else if (Config.barCarryTarget && Config.barCarryTarget.bar === win) Config.barCarryTarget = null;
    }
    Connections {
        target: Config
        function onBarCarryAtChanged() { arranger.carried(); }
        function onBarCarryChanged() { arranger.carried(); }
    }
}
