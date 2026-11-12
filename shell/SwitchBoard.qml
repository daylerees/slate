// Settings → Control Centre: choosing the control centre's quick switches. A small picture of
// the panel, with its eight switches where they'll be; beside them on the left, any that aren't
// in it (the rest of the picture fades away behind those, so they sit right next to the
// switches they'd swap with). The
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
    property string label: ""       // (what Settings' search calls it: settings-index.py reads it)
    signal picked(var ids)

    // Settings' colours and fonts
    property color card
    property color well
    property color tile
    property color outline
    property color text
    property color dim
    property color accent           // the switches in the panel: lit, as an on switch is there
    property color accentText
    property string font
    property string iconFont

    // ---- The panel's own measures (Popouts.qml, the control centre) ------------------------
    // (a narrow window: smaller)
    readonly property real k: side ? Math.max(0.6, Math.min(1, (width - 12 - (12 + 2 * trayPad + poolW + trayGap)) / (rightW + 12)))
                                   : Math.min(1, (width - 24) / (panelW + 24))
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
    // The ones waiting go beside the panel's switches, on the left (with none, the picture's alone)
    readonly property bool side: waiting
    readonly property real poolW: pool.columns * (pool.tileW + gap) - gap
    // They sit in a tray of their own (outlined, not the panel's colour), apart from the picture
    readonly property real trayPad: 10
    readonly property real trayGap: 28          // from the tray to the panel's switches
    // The picture is gone behind the tray and fades back in across the gap: from nothing
    // (fadeFrom) to full (fadeTo), across the board
    readonly property real fadeFrom: 12 + 2 * trayPad + poolW + 2
    readonly property real fadeTo: grid.x0 - 12 * k

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

    implicitHeight: waiting && !side ? spareCard.y + spareCard.height : panelCard.y + panelCard.height
    height: implicitHeight

    component Heading: Text {
        color: board.dim
        font.family: board.font; font.pixelSize: 12; font.weight: Font.Medium
        topPadding: 14; bottomPadding: 6; leftPadding: 4
    }
    // A shape in the picture, faded away towards the left behind the switches waiting there
    // (`fill` is its colour; full wherever the picture isn't shared)
    component Fading: Rectangle {
        id: fr
        property color fill
        readonly property real bx: picture.x + (fr.parent === picture ? x : 0)    // its left, on the board
        function alphaAt(p) {
            const t = Math.max(0, Math.min(1, (bx + p * width - board.fadeFrom) / Math.max(1, board.fadeTo - board.fadeFrom)));
            return Qt.rgba(fill.r, fill.g, fill.b, fill.a * t * t * (3 - 2 * t));
        }
        readonly property real s0: Math.max(0, Math.min(1, (board.fadeFrom - bx) / Math.max(1, width)))
        readonly property real s1: Math.max(0, Math.min(1, (board.fadeTo - bx) / Math.max(1, width)))
        color: fill
        gradient: board.side ? fade : null
        Gradient {
            id: fade
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: fr.alphaAt(0) }
            GradientStop { position: fr.s0; color: fr.alphaAt(fr.s0) }
            GradientStop { position: (fr.s0 + fr.s1) / 2; color: fr.alphaAt((fr.s0 + fr.s1) / 2) }
            GradientStop { position: fr.s1; color: fr.alphaAt(fr.s1) }
            GradientStop { position: 1; color: fr.alphaAt(1) }
        }
    }
    // Part of the panel that isn't a switch: there to show where the switches sit
    component Ghost: Fading {
        radius: Config.corner(12 * board.k)
        fill: board.outline
        opacity: 0.55
    }

    // ---- In the control centre ----------------------------------------------------------------
    // (beside them: over the switches' column, with the ones waiting headed on the left)
    Heading { id: inHead; x: board.side ? Math.max(spareSide.width + 8, grid.x0 - 4) : 0; text: "In the control centre" }
    Heading { id: spareSide; visible: board.side; x: 12; text: "More switches" }
    Rectangle {
        id: panelCard
        y: inHead.height
        width: parent.width
        height: board.side ? Math.max(picture.height + 28, grid.y0 - y + pool.rows * (pool.tileH + board.gap) - board.gap + board.trayPad + 12)
                           : picture.height + 28
        radius: Config.corner(12)
        color: board.card
        Gloss { radius: parent.radius }
    }
    // (the picture, where it reaches past the card's left edge behind the ones waiting)
    Item {
        id: pictureClip
        y: panelCard.y; width: board.width; height: panelCard.height
        clip: true
    // The panel in small: your picture and name along the top; under it the clock and what's
    // playing on the left, and the switches on the right
    Fading {
        id: picture
        parent: pictureClip
        x: board.side ? grid.x0 - (12 + board.leftW + 12) * board.k : Math.round((board.width - width) / 2)
        y: 14
        width: (board.panelW + 24) * board.k
        height: (12 + 80 + 12 + board.bodyH + 12) * board.k
        radius: Config.corner(16 * board.k)
        fill: board.well
        Ghost { x: 12 * board.k; y: 12 * board.k; width: board.panelW * board.k; height: 80 * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12) * board.k; width: board.leftW * board.k; height: (board.bodyH - 104 - 12) * board.k }
        Ghost { x: 12 * board.k; y: (12 + 80 + 12 + board.bodyH - 104) * board.k; width: board.leftW * board.k; height: 104 * board.k }
    }
    }
    QtObject {
        id: grid
        readonly property real x0: board.side ? 12 + 2 * board.trayPad + board.poolW + board.trayGap : picture.x + (12 + board.leftW + 12) * board.k
        readonly property real y0: panelCard.y + picture.y + (12 + 80 + 12) * board.k
    }

    // ---- The ones that aren't in it (none, while there are only eight) ----------------------
    // (only when they're not beside the picture)
    Heading { id: spareHead; visible: board.waiting && !board.side; y: panelCard.y + panelCard.height; text: "More switches" }
    Rectangle {
        id: spareCard
        visible: board.waiting && !board.side
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
        readonly property int spare: board.line.length - board.order.length
        // Beside the picture: as many columns as leave the switches' column its full size (at
        // least one), no more than there are switches to fill
        readonly property int columns: board.side
            ? Math.max(1, Math.min(Math.max(1, spare), Math.floor((board.width - 12 - 2 * board.trayPad - board.trayGap - (board.rightW + 12) - 12 + board.gap) / (tileW + board.gap))))
            : Math.max(1, Math.floor((board.width - 24 + board.gap) / (tileW + board.gap)))
        readonly property int rows: Math.ceil(spare / columns)
        readonly property real x0: board.side ? 12 + board.trayPad : 12
        readonly property real y0: board.side ? grid.y0 : spareCard.y + 12
    }

    // The tray the ones waiting sit in, beside the picture
    Rectangle {
        visible: board.side
        x: pool.x0 - board.trayPad; y: pool.y0 - board.trayPad
        width: board.poolW + 2 * board.trayPad
        height: pool.rows * (pool.tileH + board.gap) - board.gap + 2 * board.trayPad
        radius: Config.corner(16)
        color: "transparent"
        border.width: 1
        border.color: board.outline
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
            // In the panel (where it is now, or would land if let go): in the accent, lighter
            // when pointed at or carried, as an on switch in the panel is when pointed at
            readonly property bool inPanel: board.shown.indexOf(modelData.id) < board.order.length
            readonly property bool lit: (grab.containsMouse && board.held === "") || target || carried
            readonly property color fg: inPanel ? board.accentText : board.text
            x: carried ? board.holdX : home.x
            y: carried ? board.holdY : home.y
            width: home.width; height: home.height
            z: carried ? 3 : target ? 2 : 1
            radius: Config.corner(12)
            color: inPanel ? (lit ? Config.accentLit : board.accent) : lit ? Config.hover : board.tile
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
                    color: sw.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    font.family: board.iconFont; font.pixelSize: 18
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: sw.modelData.label
                    color: sw.fg
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
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
