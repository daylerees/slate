// Slate's right-click menu, one look everywhere: the desktop's (Wallpaper.qml), the menu bar's
// (Bar.qml), and the dock's, for its apps and its empty space (shell.qml). Click outside or
// press Escape to close. The keys work it too: Up/Down (Home/End) move along the items, Enter
// or Space chooses one, Right (or Enter) goes into a submenu and Left or Escape back out.
//
//   menu.openFrom(x, y, edge)   point at (x, y) (in the screen's own coordinates) from the
//                               menu's `edge` side ("top": the menu hangs below the point;
//                               "bottom", "left", "right" likewise), with a little pointer on
//                               that side; flipped to the other side when there's no room, and
//                               slid along to stay on the screen, the pointer staying on (x, y)
//   menu.openAt(x, y)           at a click: the pointer's tip at the cursor (below it, or above
//                               when there's no room)
//   (gap: how far the menu's side is from (x, y); the pointer reaches most of it)
//
//   items: [{ label, icon, run }] with { separator: true } between groups. Also:
//     danger: true    red when pointed at (Force Quit, Empty Waste Basket)
//     active: true    a dot before it (the window you're in)
//     submenu: [items] a menu of its own beside it, with an arrow at its end: pointing at it
//                     (or clicking it) opens it to the side (the right, or the left where
//                     there's no room), and it closes with the menu. Pointing at another item
//                     closes it again, after a moment, so the pointer can cross to it
//   extra: a Component shown above the items (the dock's Downloads grid); menuWidth: wider for it

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dm
    property var items: []
    property Component extra: null
    property real menuWidth: 230

    // Where it points, and from which of its sides
    property real atX: 0
    property real atY: 0
    property string edge: "top"
    property real gap: 0

    // The submenu showing: the index of its item in `items` (-1: none), and the one the
    // pointer is asking for, taken up after a moment (subWait)
    property int subIndex: -1
    property int subWanted: -1
    readonly property var subItems: subIndex >= 0 && items[subIndex] && items[subIndex].submenu ? items[subIndex].submenu : []
    property real subRowY: 0              // the item's top, in the main menu
    // The item lit in each card (-1: none), by the pointer or the keys, and whether the keys
    // are in the submenu
    property int hot: -1
    property int subHot: -1
    property bool inSub: false
    onSubIndexChanged: if (subIndex < 0) { inSub = false; subHot = -1; }

    // ---- The keys ---------------------------------------------------------------------------
    function chooseable(list, i) { return i >= 0 && i < list.length && list[i] && !list[i].separator; }
    // The next item that isn't a separator, from `from` in direction `dir`, round the ends
    function nextIn(list, from, dir) {
        const n = list.length;
        if (!n) return -1;
        let i = from;
        for (let k = 0; k < n; k++) {
            i = from < 0 && k === 0 ? (dir > 0 ? 0 : n - 1) : (i + dir + n) % n;
            if (chooseable(list, i)) return i;
        }
        return -1;
    }
    function enterSub(index) {
        subWait.stop();
        hot = index; subWanted = index; subIndex = index;
        const r = main.rowY(index);
        if (r >= 0) subRowY = r;
        inSub = true;
        subHot = nextIn(subItems, -1, 1);
    }
    function choose(list, i, isSub) {
        if (!chooseable(list, i)) return;
        const it = list[i];
        if (!isSub && it.submenu) { enterSub(i); return; }
        const run = it.run;
        close();
        if (run) run();
    }
    function key(e) {
        const sub = inSub && subItems.length > 0;
        const list = sub ? subItems : items;
        const at = sub ? subHot : hot;
        const move = i => {
            if (sub) { subHot = i; return; }
            hot = i;
            if (subIndex >= 0 && subIndex !== i) { subWait.stop(); subIndex = -1; subWanted = -1; }
        };
        switch (e.key) {
        case Qt.Key_Down: case Qt.Key_Tab: move(nextIn(list, at, 1)); break;
        case Qt.Key_Up: case Qt.Key_Backtab: move(nextIn(list, at, -1)); break;
        case Qt.Key_Home: case Qt.Key_PageUp: move(nextIn(list, -1, 1)); break;
        case Qt.Key_End: case Qt.Key_PageDown: move(nextIn(list, -1, -1)); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: choose(list, at, sub); break;
        case Qt.Key_Right:
            if (!sub && chooseable(items, hot) && items[hot].submenu) enterSub(hot);
            break;
        case Qt.Key_Left:
            if (sub) { subWait.stop(); subIndex = -1; subWanted = -1; }
            break;
        case Qt.Key_Escape:
            if (sub) { subWait.stop(); subIndex = -1; subWanted = -1; } else close();
            break;
        default: return;
        }
        e.accepted = true;
    }

    function openFrom(x, y, side, off) {
        subIndex = -1; subWanted = -1; hot = -1; subHot = -1; inSub = false;
        atX = x; atY = y; edge = side || "top"; gap = off || 0;
        visible = true;
    }
    function openAt(x, y) { openFrom(x, y, "top", 10); }
    function close() { visible = false; subIndex = -1; subWanted = -1; hot = -1; subHot = -1; subWait.stop(); }
    // The pointer on an item: its submenu (or none) wanted; opening one when none shows is
    // quick, changing or closing one waits a little longer
    function want(index, rowY) {
        subWanted = index;
        if (index >= 0) subRowY = rowY;
        if (subWanted === subIndex) { subWait.stop(); return; }
        subWait.interval = subIndex < 0 ? 120 : 300;
        subWait.restart();
    }
    Timer { id: subWait; onTriggered: dm.subIndex = dm.subWanted }
    // Going to another workspace, or opening the launcher, Nova, a picker or a switcher
    // (Config.closeMenus), closes it
    Connections {
        target: Config
        function onCloseMenus() { if (dm.visible) dm.close(); }
        function onFocusedWorkspaceIdChanged() { if (dm.visible) dm.close(); }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "slate-desktop-menu"   // (every menu: the dock's were slate-dock-menu)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: dm.close() }
    Item { focus: dm.visible; Keys.onPressed: e => dm.key(e) }

    // Look: the dock's
    readonly property color bgColor: Config.surface(Config.tint("#0f1216"))
    // Separators: a faint line of the text's colour, so they're as subtle over glass (where a
    // solid dark line all but vanished) as on a solid menu, and in light mode
    readonly property color sepColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.1)
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimColor: Config.tint("#8b94a3")
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    // A menu's card and its rows: the menu, and a submenu beside it
    component MenuCard: Rectangle {
        id: card
        property var list: []
        property bool sub: false
        default property alias above: aboveSlot.data
        // (room for icons only when some item has one)
        readonly property bool icons: list.some(i => i && i.icon !== undefined)
        // A row's top (for the submenu beside it), -1 if there's no such row
        function rowY(i) { const it = rows.itemAt(i); return it ? it.y : -1; }
        width: dm.menuWidth
        height: col.implicitHeight + 16
        radius: Config.corner(12)
        color: dm.bgColor
        // (its pointer, if it has one: part of its shape, for the shadow; centre and side)
        property point pointAt: Qt.point(0, 0)
        property real pointSize: 0
        Shadow { pointAt: card.pointAt; pointSize: card.pointSize }   // raised: Slate's shadow, with glass too
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside don't close
        // (the pointer reaching the submenu keeps it open)
        HoverHandler { onHoveredChanged: if (hovered && card.sub) dm.want(dm.subIndex, dm.subRowY) }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 1
            Column { id: aboveSlot; width: parent.width }
            Repeater {
                id: rows
                model: card.list
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool opens: !card.sub && !!modelData.submenu
                    readonly property bool open: opens && dm.subIndex === index
                    readonly property bool lit: (card.sub ? dm.subHot : dm.hot) === index
                    width: col.width
                    height: modelData.separator ? 9 : 30
                    Rectangle {
                        visible: !!row.modelData.separator
                        anchors.centerIn: parent
                        width: parent.width - 16; height: 1
                        color: dm.sepColor
                    }
                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: Config.corner(7)
                        // Under the pointer, or its submenu open and still wanted (the pointer on
                        // it or in the submenu: pointing at another item drops it at once, while
                        // the submenu waits a moment to close): the muted hover, flat (the accent
                        // is for what stays selected); red for what's destructive
                        // (lit: the pointer on it, or the keys)
                        color: row.lit || (row.open && dm.subWanted === row.index) ? (row.modelData.danger ? Config.hoverDanger : Config.hover) : "transparent"
                        Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                        Rectangle {
                            visible: !!row.modelData.active
                            width: 5; height: 5; radius: Config.corner(2.5)
                            color: Config.accent
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        }
                        Text {
                            visible: card.icons
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: row.modelData.icon ? String.fromCodePoint(row.modelData.icon) : ""
                            color: dm.dimColor
                            font.family: tabler.name; font.pixelSize: 16
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: card.icons ? 36 : 20; right: parent.right; rightMargin: row.opens ? 30 : 10; verticalCenter: parent.verticalCenter }
                            text: row.modelData.label || ""
                            color: row.modelData.danger ? Config.tint("#f28b8b") : dm.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        // A submenu's arrow
                        Text {
                            visible: row.opens
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: String.fromCodePoint(0xEA61)          // chevron right
                            color: row.open && dm.subWanted === row.index ? dm.textColor : dm.dimColor
                            font.family: tabler.name; font.pixelSize: 15
                        }
                        HoverHandler {
                            id: itemHover
                            onHoveredChanged: {
                                if (!hovered) {
                                    if (row.lit) { if (card.sub) dm.subHot = -1; else dm.hot = -1; }
                                    return;
                                }
                                if (card.sub) { dm.subHot = row.index; dm.inSub = true; return; }
                                dm.hot = row.index; dm.inSub = false;
                                dm.want(row.opens ? row.index : -1, row.y);
                            }
                        }
                        ClickTap {
                            hand: false              // (menus keep the arrow)
                            onTapped: {
                                // (an item with a submenu opens it straight away)
                                if (row.opens) { dm.subWanted = row.index; dm.subRowY = row.y; dm.subIndex = row.index; subWait.stop(); return; }
                                dm.choose(card.list, row.index, card.sub);
                            }
                        }
                    }
                }
            }
        }
    }

    MenuCard {
        id: main
        list: dm.items
        Loader { active: !!dm.extra && dm.visible; sourceComponent: dm.extra; width: parent.width }
        // Away from its edge; the other way when there's no room that side
        readonly property string side: {
            const e = dm.edge;
            if (e === "top" && dm.atY + dm.gap + height + 8 > dm.height) return "bottom";
            if (e === "bottom" && dm.atY - dm.gap - height < 8) return "top";
            if (e === "left" && dm.atX + dm.gap + width + 8 > dm.width) return "right";
            if (e === "right" && dm.atX - dm.gap - width < 8) return "left";
            return e;
        }
        readonly property bool across: side === "top" || side === "bottom"
        x: Math.max(8, Math.min(dm.width - width - 8,
            side === "left" ? dm.atX + dm.gap : side === "right" ? dm.atX - dm.gap - width : dm.atX - width / 2))
        y: Math.max(8, Math.min(dm.height - height - 8,
            side === "top" ? dm.atY + dm.gap : side === "bottom" ? dm.atY - dm.gap - height : dm.atY - height / 2))
        // The pointer: on the side facing the point, at it (sliding along the side to stay on
        // it when the menu is held in from the screen's edge), clear of the rounded corners
        pointSize: pointer.size
        pointAt: pointer.edge === "top" ? Qt.point(pointer.along, 0) : pointer.edge === "bottom" ? Qt.point(pointer.along, height)
               : pointer.edge === "left" ? Qt.point(0, pointer.along) : Qt.point(width, pointer.along)
        MenuPointer {
            id: pointer
            parent: main                  // (on the card's edge, not among what's shown above the items)
            edge: main.side
            along: main.across ? Math.max(18, Math.min(main.width - 18, dm.atX - main.x))
                               : Math.max(18, Math.min(main.height - 18, dm.atY - main.y))
            color: main.color
        }
    }
    // The submenu: beside its item, its first row level with it; on the left when there's no
    // room on the right; kept on the screen
    MenuCard {
        id: subCard
        sub: true
        list: dm.subItems
        visible: dm.subItems.length > 0
        readonly property bool roomRight: main.x + main.width + 4 + width + 8 <= dm.width
        x: roomRight ? main.x + main.width + 4 : Math.max(8, main.x - width - 4)
        y: Math.max(8, Math.min(dm.height - height - 8, main.y + dm.subRowY))
    }
}
