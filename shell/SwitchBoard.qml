// Settings → Control Centre: choosing the control centre's quick switches. A small picture of
// the panel, with its eight switches where they'll be; under it, any that aren't in it. The
// panel always has eight, so nothing is added or taken away: drag one switch onto another and
// the two change places, whether both are in the panel or one's waiting below. The tiles in
// the picture are laid out by the same sums as the panel's (Config.controlSwitchRects), so
// what you see is how it'll look.

import QtQuick

Item {
    id: board
    property var all: []            // every switch there is: [{ id, label, icon }]
    property var chosen: []         // the ids in the panel, in order (Config.controlSwitches: always full)
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
    readonly property real bodyH: 248

    readonly property var known: all.map(s => s.id)
    readonly property var order: (chosen || []).filter((id, i, a) => known.indexOf(id) >= 0 && a.indexOf(id) === i).slice(0, most)
    // Every switch in a line: the panel's first, then the ones waiting
    readonly property var line: order.concat(known.filter(id => order.indexOf(id) < 0))
    readonly property bool waiting: line.length > order.length          // (are there any that aren't in the panel?)

    // ---- Dragging ---------------------------------------------------------------------------
    property string held: ""        // the switch being dragged
    property string over: ""        // the one it's over, which it would change places with
    property real holdX: 0          // its corner, as it's carried
    property real holdY: 0
    // The line as it would be if you let go now: those two swapped
    readonly property var shown: {
        const l = line.slice(), a = l.indexOf(held), b = l.indexOf(over);
        if (held !== "" && over !== "" && a >= 0 && b >= 0) { l[a] = over; l[b] = held; }
        return l;
    }
    readonly property var rects: Config.controlSwitchRects(order.length, rightW, bodyH)

    // The i-th place in the line: in the picture, or among the ones waiting
    function placeAt(i) {
        if (i < order.length && rects[i]) { const r = rects[i]; return Qt.rect(grid.x0 + r.x * k, grid.y0 + r.y * k, r.width * k, r.height * k); }
        const j = Math.max(0, i - order.length);
        return Qt.rect(pool.x0 + (j % pool.columns) * (pool.tileW + gap), pool.y0 + Math.floor(j / pool.columns) * (pool.tileH + gap), pool.tileW, pool.tileH);
    }
    function place(id) { return placeAt(Math.max(0, shown.indexOf(id))); }
    // Which switch's place is under (x, y): places reach half a gap beyond their edges, so
    // there's no dead space between neighbours. Two waiting switches don't swap (nothing changes)
    function aim(x, y) {
        const from = line.indexOf(held);
        let hit = "";
        for (let i = 0; i < line.length; i++) {
            const r = placeAt(i), g = gap / 2;
            if (x >= r.x - g && x <= r.x + r.width + g && y >= r.y - g && y <= r.y + r.height + g) {
                if (i !== from && (i < order.length || from < order.length)) hit = line[i];
                break;
            }
        }
        over = hit;
    }
    function drop() {
        const next = shown.slice(0, order.length);
        held = ""; over = "";
        if (JSON.stringify(next) !== JSON.stringify(order)) picked(next);
    }

    implicitHeight: waiting ? spareCard.y + spareCard.height : panelCard.y + panelCard.height
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
        Ghost { x: 12 * board.k; y: 12 * board.k; width: board.panelW * board.k; height: 80 * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12) * board.k; width: board.leftW * board.k; height: (board.bodyH - 104 - 12) * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12 + board.bodyH - 104) * board.k; width: board.leftW * board.k; height: 104 * board.k }
    }
    QtObject {
        id: grid
        readonly property real x0: picture.x + (12 + board.leftW + 12) * board.k
        readonly property real y0: picture.y + (12 + 80 + 12) * board.k
    }

    // ---- The ones that aren't in it (none, while there are only eight) ----------------------
    Heading { id: spareHead; visible: board.waiting; y: panelCard.y + panelCard.height; text: "More switches" }
    Rectangle {
        id: spareCard
        visible: board.waiting
        y: spareHead.y + spareHead.height
        width: parent.width
        height: 24 + Math.max(1, pool.rows) * (pool.tileH + board.gap) - board.gap
        radius: Config.corner(12)
        color: board.card
        Gloss { radius: parent.radius }
    }
    QtObject {
        id: pool
        readonly property real tileW: 100
        readonly property real tileH: 56
        readonly property int columns: Math.max(1, Math.floor((board.width - 24 + board.gap) / (tileW + board.gap)))
        readonly property int rows: Math.ceil((board.line.length - board.order.length) / columns)
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
            readonly property bool target: board.over === modelData.id        // (the one the carried switch would swap with)
            readonly property rect home: board.place(modelData.id)
            x: carried ? board.holdX : home.x
            y: carried ? board.holdY : home.y
            width: home.width; height: home.height
            z: carried ? 3 : target ? 2 : 1
            radius: Config.corner(12)
            color: (grab.containsMouse && board.held === "") || target ? Config.hover : board.tile
            scale: carried ? 1.05 : 1
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            Behavior on scale { NumberAnimation { duration: Config.ms(120); easing.type: Easing.OutCubic } }
            Behavior on x { enabled: !sw.carried; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !sw.carried; NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Config.ms(180); easing.type: Easing.OutCubic } }
            Shadow { visible: Config.shadowsOn && sw.carried }
            Column {
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
                        board.over = "";
                        board.holdX = p.x - sw.width / 2; board.holdY = p.y - sw.height / 2;
                        board.held = sw.modelData.id;
                    }
                    // (carried by its middle: its size changes with where it would land)
                    board.aim(p.x, p.y);
                    board.holdX = p.x - sw.width / 2; board.holdY = p.y - sw.height / 2;
                }
                onReleased: if (moved) board.drop()
                onCanceled: { board.held = ""; board.over = ""; }
            }
        }
    }
}
