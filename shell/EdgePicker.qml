// A small screen to pick an edge for the menu bar or dock (Settings → Menu bar / Dock):
// click an edge. The chosen one is in the accent; the other (the dock, picking for the bar,
// and the other way round) shows as a thin faint line inside its edge, for reference. bar: true draws the edges
// as full-length bars, false as short dock-like pills.

import QtQuick

Rectangle {
    id: ep
    property bool bar: true
    property string edge: "top"
    property string other: "bottom"      // where the other one is
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

    // The other one, for reference: a thin, faint line of its length, just inside its edge
    // (beside the spots there, so it's never covered and never in the way of a click)
    Rectangle {
        readonly property rect r: ep.place(ep.other, !ep.bar)
        readonly property bool along: ep.other === "top" || ep.other === "bottom"
        readonly property real thin: 3
        readonly property real inset: ep.gap + ep.thick + 3
        x: along ? r.x : ep.other === "left" ? inset : ep.width - inset - thin
        y: along ? (ep.other === "top" ? inset : ep.height - inset - thin) : r.y
        width: along ? r.width : thin
        height: along ? thin : r.height
        radius: thin / 2
        color: Config.tint("#4a5360")
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
            color: current ? ep.accent : spotHover.hovered ? Config.hoverOn(Config.tint("#262c35")) : Config.tint("#262c35")
            Behavior on color { ColorAnimation { duration: 100 } }
            HoverHandler { id: spotHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ep.picked(spot.modelData) }
        }
    }
}
