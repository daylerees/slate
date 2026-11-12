// Settings → Control Centre: choosing the control centre's quick switches. A small picture of
// the panel, with its switches where they'll be; under it, the ones left over. Drag one in,
// out, or to another place. The tiles in the picture are laid out by the same sums as the
// panel's (Config.controlSwitchRects: the first two wide, the rest two to a row), so what you
// see is how it'll look.

import QtQuick

Item {
    id: board
    property var all: []            // every switch there is: [{ id, label, icon }]
    property var chosen: []         // the ids in the panel, in order
    property int most: 8
    signal picked(var ids)

    // Settings' colours and fonts
    property color card
    property color well
    property color tile
    property color outline
    property color text
    property color dim
    property string font
    property string iconFont

    // ---- The panel's own measures (Popouts.qml, the control centre) ------------------------
    readonly property real k: Math.min(1, (width - 24) / (panelW + 24))     // (a narrow window: smaller)
    readonly property real panelW: 470
    readonly property real rightW: 208          // the switches' column
    readonly property real leftW: panelW - rightW - 12
    readonly property real gap: 8
    // (as tall as the switches need, and no shorter than the clock and what's playing)
    readonly property real bodyH: Math.max(248, Config.controlSwitchesHeight(showing.length))

    readonly property var known: all.map(s => s.id)
    readonly property var order: (chosen || []).filter((id, i, a) => known.indexOf(id) >= 0 && a.indexOf(id) === i).slice(0, most)

    // ---- Dragging ---------------------------------------------------------------------------
    property string held: ""        // the switch being dragged
    property int slot: -1           // where it would land in the panel (-1: with the ones left over)
    property real holdX: 0          // its corner, as it's carried
    property real holdY: 0
    // What the panel would show if you let go now
    readonly property var showing: {
        const list = order.filter(id => id !== held);
        if (held !== "" && slot >= 0) list.splice(Math.min(slot, list.length), 0, held);
        return list;
    }
    readonly property var spare: known.filter(id => showing.indexOf(id) < 0)
    readonly property var rects: Config.controlSwitchRects(showing.length, rightW, bodyH)
    readonly property bool full: order.filter(id => id !== held).length >= most

    // Where the middle of the carried tile is: over the picture, the nearest place in it as
    // it would be with this one in
    function aim(cx, cy) {
        const inside = cx >= picture.x && cx <= picture.x + picture.width && cy >= panelCard.y && cy <= panelCard.y + panelCard.height;
        if (!inside || full) { slot = -1; return; }
        const n = order.filter(id => id !== held).length + 1;
        const places = Config.controlSwitchRects(n, rightW, Math.max(248, Config.controlSwitchesHeight(n)));
        let best = 0, bestD = 1e12;
        for (let i = 0; i < places.length; i++) {
            const r = places[i];
            const dx = cx - (grid.x0 + (r.x + r.width / 2) * k), dy = cy - (grid.y0 + (r.y + r.height / 2) * k);
            const d = dx * dx + dy * dy;
            if (d < bestD) { bestD = d; best = i; }
        }
        slot = best;
    }
    function drop() {
        const next = showing.slice();
        held = ""; slot = -1;
        if (JSON.stringify(next) !== JSON.stringify(order)) picked(next);
    }
    // A tile's place: in the picture, or among the ones left over
    function place(id) {
        const i = showing.indexOf(id);
        if (i >= 0 && rects[i]) { const r = rects[i]; return Qt.rect(grid.x0 + r.x * k, grid.y0 + r.y * k, r.width * k, r.height * k); }
        const j = Math.max(0, spare.indexOf(id));
        return Qt.rect(pool.x0 + (j % pool.columns) * (pool.tileW + gap), pool.y0 + Math.floor(j / pool.columns) * (pool.tileH + gap), pool.tileW, pool.tileH);
    }

    implicitHeight: spareCard.y + spareCard.height
    height: implicitHeight

    component Heading: Text {
        color: board.dim
        font.family: board.font; font.pixelSize: 12; font.weight: Font.Medium
        topPadding: 14; bottomPadding: 6; leftPadding: 4
    }
    // Part of the panel that isn't a switch: there to show where the switches sit
    component Ghost: Rectangle {
        radius: Config.corner(12 * board.k)
        color: board.outline
        opacity: 0.55
    }

    // ---- In the control centre ----------------------------------------------------------------
    Heading { id: inHead; text: "In the control centre" }
    Rectangle {
        id: panelCard
        y: inHead.height
        width: parent.width; height: picture.height + 28
        radius: Config.corner(12)
        color: board.card
        Gloss { radius: parent.radius }
    }
    // The panel in small: your picture and name along the top; under it the clock and what's
    // playing on the left, and the switches on the right
    Rectangle {
        id: picture
        x: Math.round((board.width - width) / 2); y: panelCard.y + 14
        width: (board.panelW + 24) * board.k
        height: (12 + 80 + 12 + board.bodyH + 12) * board.k
        radius: Config.corner(16 * board.k)
        color: board.well
        Behavior on height { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
        Ghost { x: 12 * board.k; y: 12 * board.k; width: board.panelW * board.k; height: 80 * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12) * board.k; width: board.leftW * board.k; height: (board.bodyH - 104 - 12) * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12 + board.bodyH - 104) * board.k; width: board.leftW * board.k; height: 104 * board.k }
        Text {
            visible: board.showing.length === 0
            x: grid.x0 - picture.x; y: grid.y0 - picture.y
            width: board.rightW * board.k; height: board.bodyH * board.k
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            text: "No switches yet. Drag one here"
            color: board.dim; font.family: board.font; font.pixelSize: 12
        }
    }
    QtObject {
        id: grid
        readonly property real x0: picture.x + (12 + board.leftW + 12) * board.k
        readonly property real y0: picture.y + (12 + 80 + 12) * board.k
    }

    // ---- The ones left over -------------------------------------------------------------------
    Heading { id: spareHead; y: panelCard.y + panelCard.height; text: "More switches" }
    Rectangle {
        id: spareCard
        y: spareHead.y + spareHead.height
        width: parent.width
        height: 24 + Math.max(1, pool.rows) * (pool.tileH + board.gap) - board.gap
        radius: Config.corner(12)
        color: board.card
        Gloss { radius: parent.radius }
        Text {
            visible: board.spare.length === 0 || (board.spare.length === 1 && board.spare[0] === board.held)
            anchors.centerIn: parent
            text: "Every switch is in the control centre. Drag one here to take it out"
            color: board.dim; font.family: board.font; font.pixelSize: 12
        }
    }
    QtObject {
        id: pool
        readonly property real tileW: 100
        readonly property real tileH: 56
        readonly property int columns: Math.max(1, Math.floor((board.width - 24 + board.gap) / (tileW + board.gap)))
        readonly property int rows: Math.ceil(board.spare.length / columns)
        readonly property real x0: 12
        readonly property real y0: spareCard.y + 12
    }

    // ---- The switches themselves, each wherever it belongs right now ------------------------
    Repeater {
        model: board.all
        delegate: Rectangle {
            id: sw
            required property var modelData
            readonly property bool carried: board.held === modelData.id
            readonly property rect home: board.place(modelData.id)
            // (a wide place in the panel: the icon beside the name, as it is there)
            readonly property bool wide: board.showing.indexOf(modelData.id) >= 0 && home.width > board.rightW * board.k * 0.75
            x: carried ? board.holdX : home.x
            y: carried ? board.holdY : home.y
            width: home.width; height: home.height
            z: carried ? 3 : 1
            radius: Config.corner(12)
            color: grab.containsMouse && !carried && board.held === "" ? Config.hover : board.tile
            scale: carried ? 1.05 : 1
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            Behavior on scale { NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutCubic } }
            Behavior on x { enabled: !sw.carried; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !sw.carried; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Shadow { visible: sw.carried; blur: 14; dropY: 3 }
            Row {
                visible: sw.wide
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(sw.modelData.icon)
                    color: board.text
                    font.family: board.iconFont; font.pixelSize: 20
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sw.modelData.label
                    color: board.text
                    font.family: board.font; font.pixelSize: 13; font.weight: Font.Medium
                }
            }
            Column {
                visible: !sw.wide
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 3
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: String.fromCodePoint(sw.modelData.icon)
                    color: board.text
                    font.family: board.iconFont; font.pixelSize: 18
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: sw.modelData.label
                    color: board.text
                    font.family: board.font; font.pixelSize: 11; font.weight: Font.Medium
                }
            }
            MouseArea {
                id: grab
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true          // (the page scrolls: the drag stays ours once begun)
                cursorShape: Config.handCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                property real offX: 0
                property real offY: 0
                property bool moved: false
                onPressed: m => { offX = m.x; offY = m.y; moved = false; }
                onPositionChanged: m => {
                    if (!pressed) return;
                    const p = mapToItem(board, m.x, m.y);
                    if (!moved) {
                        if (Math.abs(m.x - offX) + Math.abs(m.y - offY) < 5) return;
                        moved = true;
                        board.holdX = sw.x; board.holdY = sw.y;
                        board.slot = board.order.indexOf(sw.modelData.id);
                        board.held = sw.modelData.id;
                    }
                    // (carried by its middle: its size changes with where it would land)
                    board.aim(p.x, p.y);
                    board.holdX = p.x - sw.width / 2; board.holdY = p.y - sw.height / 2;
                }
                onReleased: if (moved) board.drop()
                onCanceled: { board.held = ""; board.slot = -1; }
            }
        }
    }
}
