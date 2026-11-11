// A small screen to pick an edge for the menu bar or dock (Settings → Menu Bar / Dock):
// click an edge; the chosen one is in the accent. bar: true draws the edges as full-length
// bars, false as short dock-like pills.

import QtQuick

Rectangle {
    id: ep
    property bool bar: true
    property string edge: "top"
    property color accent: Config.accent
    signal picked(string edge)

    width: 168; height: 104; radius: 10
    color: Config.tint("#151920")
    border.width: 1; border.color: Config.tint("#323a46")

    readonly property real gap: 6         // from the screen's edge
    readonly property real thick: 10
    // Where a bar (full length) or dock (short, centred) sits on an edge. Side bars stop short
    // of the top and bottom ones so the edges don't overlap
    function place(e, isBar) {
        const along = e === "top" || e === "bottom";
        const len = isBar ? (along ? width - 2 * gap : height - 2 * gap - 2 * (thick + 4)) : (along ? 64 : 40);
        const x = along ? (width - len) / 2 : (e === "left" ? gap : width - gap - thick);
        const y = along ? (e === "top" ? gap : height - gap - thick) : (height - len) / 2;
        return along ? Qt.rect(x, y, len, thick) : Qt.rect(x, y, thick, len);
    }

    Repeater {
        model: ["top", "bottom", "left", "right"]
        delegate: Rectangle {
            id: spot
            required property string modelData
            readonly property rect r: ep.place(modelData, ep.bar)
            readonly property bool current: ep.edge === modelData
            x: r.x; y: r.y; width: r.width; height: r.height
            radius: 3
            color: current ? ep.accent : "transparent"
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            HoverFill { base: Config.tint("#262c35"); hovered: ep.over === spot.modelData; gone: spot.current; radius: spot.radius }
        }
    }
    // Which edge the pointer's on, worked out here for the whole picture: the edges are thin, so
    // each reacts a little way beyond what's drawn (`reach`), and the one whose middle is nearest
    // wins where two reach the same place. One area for hovering and clicking alike
    readonly property real reach: 7
    property string over: ""
    function edgeAt(px, py) {
        let best = "", bestD = 1e9;
        for (const e of ["top", "bottom", "left", "right"]) {
            const r = place(e, bar);
            if (px < r.x - reach || px > r.x + r.width + reach || py < r.y - reach || py > r.y + r.height + reach) continue;
            // (how far from the edge's own strip: 0 on it)
            const dx = Math.max(r.x - px, 0, px - (r.x + r.width)), dy = Math.max(r.y - py, 0, py - (r.y + r.height));
            const d = Math.max(dx, dy);
            if (d < bestD) { bestD = d; best = e; }
        }
        return best;
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Config.handCursor && ep.over !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: m => ep.over = ep.edgeAt(m.x, m.y)
        onEntered: ep.over = ep.edgeAt(mouseX, mouseY)
        onExited: ep.over = ""
        onClicked: m => { const e = ep.edgeAt(m.x, m.y); if (e !== "") { Config.click(); ep.picked(e); } }
    }
}
