// An app tray icon's menu, drawn by Slate in the same style as the dock's menus (rather
// than as a platform menu): opens beside the icon, away from the bar, with a pointer to it.
// Submenus open in place, with a row to go back. Click outside or press Escape to close.
//   trayMenu.openFor(item.menu, x, y)   x, y: the icon's centre at the bar's inner edge
//                                       (screen coordinates)

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: tm
    required property var bar

    // Menus being shown: the app's menu, then any submenus opened from it
    property var stack: []
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : null
    property real anchorX: 0
    property real anchorY: 0

    function openFor(menu, x, y) {
        if (!menu) return;
        stack = [menu];
        anchorX = x;
        anchorY = y;
        visible = true;
    }
    function close() { visible = false; stack = []; }
    // Closes as every menu does: going to another workspace, or a launcher or switcher opening
    Connections {
        target: Config
        function onCloseMenus() { if (tm.visible) tm.close(); }
        function onFocusedWorkspaceIdChanged() { if (tm.visible) tm.close(); }
    }
    QsMenuOpener { id: opener; menu: tm.current && !tm.current.pretend ? tm.current : null }
    readonly property var entries: tm.current && tm.current.pretend ? tm.current.rows : opener.children ? opener.children.values : []
    // (the tests: a menu of pretend rows, as an app's would be ({ text, sep, rows: [submenu] }),
    // and what was chosen from it, as the test computer has no app with a menu)
    property string testChosen: ""
    function testOpen(rows, x, y) {
        const make = list => list.map(r => r.sep ? { isSeparator: true, enabled: true, hasChildren: false, text: "", icon: "", buttonType: QsMenuButtonType.None }
            : { text: r.text, icon: "", enabled: r.enabled !== false, isSeparator: false, buttonType: QsMenuButtonType.None,
                hasChildren: !!r.rows, pretend: true, rows: r.rows ? make(r.rows) : [], triggered: () => tm.testChosen = r.text });
        testChosen = "";
        openFor({ pretend: true, rows: make(rows) }, x, y);
    }
    readonly property bool anyIcons: entries.some(e => e && !e.isSeparator && (String(e.icon) !== ""))
    readonly property bool anyChecks: entries.some(e => e && e.buttonType !== QsMenuButtonType.None)

    screen: bar.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "slate-tray-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Clicking anywhere else closes it
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: tm.close() }
    // By keyboard, as Slate's own menus (DesktopMenu.qml): Up and Down (or Tab) move along the
    // rows, Enter or Space chooses (a submenu opens in its place, as a click does), Right opens
    // one too, Left or Backspace goes back, Escape goes back or closes
    property int hot: -1
    onStackChanged: hot = -1
    function usable(i) { const e = entries[i]; return !!e && !e.isSeparator && e.enabled; }
    function nextFrom(i, step) {
        for (let k = 1; k <= entries.length; k++) {
            const j = ((i + step * k) % entries.length + entries.length) % entries.length;
            if (usable(j)) return j;
        }
        return -1;
    }
    function choose(i) {
        if (!usable(i)) return;
        const e = entries[i];
        if (e.hasChildren) { stack = stack.concat([e]); return; }
        e.triggered();
        close();
    }
    function back() { if (stack.length > 1) stack = stack.slice(0, -1); else close(); }
    function key(e) {
        switch (e.key) {
        case Qt.Key_Down: case Qt.Key_Tab: hot = nextFrom(hot < 0 ? -1 : hot, 1); break;
        case Qt.Key_Up: case Qt.Key_Backtab: hot = nextFrom(hot < 0 ? 0 : hot, -1); break;
        case Qt.Key_Home: hot = nextFrom(-1, 1); break;
        case Qt.Key_End: hot = nextFrom(0, -1); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: choose(hot); break;
        case Qt.Key_Right: if (usable(hot) && entries[hot].hasChildren) choose(hot); break;
        case Qt.Key_Left: case Qt.Key_Backspace: if (stack.length > 1) back(); break;
        case Qt.Key_Escape: back(); break;
        default: return;
        }
        e.accepted = true;
    }
    Item { focus: tm.visible; Keys.onPressed: e => tm.key(e) }

    // Look: the menu bar's colors, as Slate's own menus (DesktopMenu.qml) have
    readonly property color bgColor: bar.barColor
    readonly property color rowHover: bar.capsuleColor
    readonly property color textColor: bar.textColor
    readonly property color dimColor: Config.palette.dim
    // (the lines between groups: faint, as DesktopMenu's, so they read over glass too)
    readonly property color sepColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.1)

    Rectangle {
        id: menuBox
        readonly property string edge: tm.bar.side
        readonly property bool sideBar: edge === "left" || edge === "right"
        width: 240
        // As tall as its rows, but never taller than the screen (it scrolls then)
        height: Math.min(menuCol.implicitHeight + 16, tm.height - 16)
        // Opens away from the bar, centred on the icon along it, kept on the screen
        x: Math.max(8, Math.min(tm.width - width - 8,
            edge === "left" ? tm.anchorX + 14 : edge === "right" ? tm.anchorX - width - 14 : tm.anchorX - width / 2))
        y: Math.max(8, Math.min(tm.height - height - 8,
            edge === "top" ? tm.anchorY + 14 : edge === "bottom" ? tm.anchorY - height - 14 : tm.anchorY - height / 2))
        radius: Config.corner(12)
        color: "transparent"     // (drawn by its surface, with its point)
        // The card and its pointer to the icon, on the side facing the bar, as one shape
        MenuSurface {
            id: surface
            edge: menuBox.edge
            along: menuBox.sideBar
                ? Math.max(18, Math.min(menuBox.height - 18, tm.anchorY - menuBox.y))
                : Math.max(18, Math.min(menuBox.width - 18, tm.anchorX - menuBox.x))
            color: tm.bgColor
            radius: menuBox.radius
        }
        Shadow { pointAt: surface.pointAt; pointSize: surface.pointSize }   // raised: Slate's shadow, with glass too
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside don't close

        // The rows, scrolling when the menu is taller than the screen allows (long menus from
        // some apps), otherwise just as they are
        Flickable {
            id: menuScroll
            anchors { fill: parent; margins: 8 }
            contentHeight: menuCol.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            SmoothWheel { flick: menuScroll }
            Column {
                id: menuCol
                width: menuScroll.width - (menuScroll.interactive ? 6 : 0)   // clear of the scrollbar, when there is one
                spacing: 1

                // Back to the menu this one came from
                Item {
                    visible: tm.stack.length > 1
                    width: menuCol.width; height: visible ? 30 : 0
                    Rectangle {
                        anchors.fill: parent; radius: Config.corner(7)
                        color: backHover.hovered ? Config.hover : "transparent"
                        Text {
                            id: backArrow
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: String.fromCodePoint(0xEA60)
                            color: tm.dimColor
                            font.family: tm.bar.iconFont; font.pixelSize: 14
                        }
                        Text {
                            anchors { left: backArrow.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            text: "Back"
                            color: tm.dimColor
                            font.family: tm.bar.fontFamily; font.pixelSize: Config.text(13); font.weight: Font.Medium
                        }
                        HoverHandler { id: backHover }
                        ClickTap { hand: false; onTapped: tm.stack = tm.stack.slice(0, -1) }
                    }
                }
                Rectangle {
                    visible: tm.stack.length > 1
                    width: menuCol.width - 16; x: 8; height: visible ? 1 : 0
                    color: tm.sepColor
                }

                Repeater {
                    model: tm.entries
                    delegate: Item {
                        id: entryRow
                        required property var modelData
                        required property int index
                        // (a screen reader: a menu item, by its words, pressed as a click does)
                        Accessible.role: sep ? Accessible.Separator : Accessible.MenuItem
                        Accessible.name: rowText.text
                        Accessible.onPressAction: tm.choose(index)
                        readonly property var e: modelData
                        readonly property bool sep: !!e && e.isSeparator
                        readonly property bool checkable: !!e && e.buttonType !== QsMenuButtonType.None
                        readonly property bool checked: checkable && e.checkState === Qt.Checked
                        width: menuCol.width
                        height: sep ? 9 : 30
                        Rectangle {
                            visible: entryRow.sep
                            anchors.centerIn: parent
                            width: parent.width - 16; height: 1
                            color: tm.sepColor
                        }
                        Rectangle {
                            visible: !entryRow.sep
                            anchors.fill: parent
                            radius: Config.corner(7)
                            // Under the pointer: the muted hover, flat (the accent is for what stays selected)
                            // (and the row the keys are on)
                            color: (entryHover.hovered || tm.hot === entryRow.index) && !!entryRow.e && entryRow.e.enabled ? Config.hover : "transparent"
                            // Tick for a checked checkbox or radio item
                            Text {
                                visible: entryRow.checked
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                text: String.fromCodePoint(0xEA5E)
                                color: Config.accent
                                font.family: tm.bar.iconFont; font.pixelSize: 14
                            }
                            Image {
                                id: entryIcon
                                visible: tm.anyIcons && String(entryRow.e.icon) !== ""
                                x: tm.anyChecks ? 28 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16
                                sourceSize: Qt.size(32, 32)
                                source: entryRow.e && !entryRow.sep ? entryRow.e.icon : ""
                            }
                            Text {
                                id: rowText
                                x: (tm.anyChecks ? 28 : 10) + (tm.anyIcons ? 24 : 0)
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - 26
                                // Strip the underscore mnemonics some apps put in (e.g. "_Quit")
                                textFormat: Text.PlainText        // never markup: the app's own menu
                                text: entryRow.e && !entryRow.sep ? String(entryRow.e.text).replace(/_(?!_)/g, "").replace(/__/g, "_") : ""
                                color: tm.textColor
                                opacity: entryRow.e && entryRow.e.enabled ? 1 : 0.4
                                font.family: tm.bar.fontFamily; font.pixelSize: Config.text(13); font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            // Opens a submenu
                            Text {
                                visible: !!entryRow.e && entryRow.e.hasChildren
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: String.fromCodePoint(0xEA61)
                                color: tm.dimColor
                                font.family: tm.bar.iconFont; font.pixelSize: 14
                            }
                            HoverHandler { id: entryHover }
                            ClickTap {
                                hand: false              // (menus keep the arrow)
                                onTapped: tm.choose(entryRow.index)
                            }
                        }
                    }
                }
                // Nothing in it (an app that's still loading its menu)
                Text {
                    visible: tm.entries.length === 0
                    width: menuCol.width; height: 30
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    text: "Nothing here just yet"
                    color: tm.dimColor
                    font.family: tm.bar.fontFamily; font.pixelSize: Config.text(13)
                }
            }
        }
        // Shades and scrollbar, for a menu taller than the screen allows (deeper in dark mode,
        // where the menu's as dark as the shade itself, as the dock's More)
        ScrollShade {
            z: 3; anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
            cornerRadius: 11; depth: Config.s.lightMode ? 1 : 2.4
            distance: menuScroll.contentY - menuScroll.originY
        }
        ScrollShade {
            z: 3; atBottom: true; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 1 }
            cornerRadius: 11; depth: Config.s.lightMode ? 1 : 2.4
            distance: menuScroll.originY + menuScroll.contentHeight - menuScroll.height - menuScroll.contentY
        }
        ThinScrollbar {
            z: 3; flick: menuScroll; color: tm.textColor
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: 8; bottomMargin: 8; rightMargin: 0 }
        }
    }
}
