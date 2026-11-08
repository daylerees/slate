// An app tray icon's menu, drawn by Slate in the same style as the dock's menus (rather
// than as a platform menu): opens beside the icon, away from the bar, with a pointer to it.
// Submenus open in place, with a row to go back. Click outside or press Escape to close.
//   trayMenu.openFor(item.menu, x, y)   x, y: the icon's centre at the bar's inner edge
//                                       (screen coordinates)
//   trayMenu.openList(list, x, y)       Slate's own menu (the Slate button's), a list of
//       { text, glyph (icon font code), action: function, checked: bool (optional) } or
//       { separator: true }

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
    function close() { visible = false; stack = []; list = null; }
    // Slate's own menu: shaped like an app's menu entries, so the rows below draw it the same
    property var list: null
    function openList(items, x, y) {
        list = items.map(i => i.separator ? { isSeparator: true } : {
            isSeparator: false, text: i.text, glyph: i.glyph || 0, icon: "", enabled: true, hasChildren: false,
            buttonType: i.checked === undefined ? QsMenuButtonType.None : QsMenuButtonType.CheckBox,
            checkState: i.checked ? Qt.Checked : Qt.Unchecked, triggered: i.action
        });
        stack = [];
        anchorX = x;
        anchorY = y;
        visible = true;
    }

    QsMenuOpener { id: opener; menu: tm.list ? null : tm.current }
    readonly property var entries: tm.list ? tm.list : opener.children ? opener.children.values : []
    readonly property bool anyIcons: entries.some(e => e && !e.isSeparator && (String(e.icon) !== "" || !!e.glyph))
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
    Item {
        focus: tm.visible
        Keys.onEscapePressed: tm.stack.length > 1 ? tm.stack = tm.stack.slice(0, -1) : tm.close()
    }

    // Look: the dock menu's
    readonly property color bgColor: bar.barColor
    readonly property color rowHover: bar.capsuleColor
    readonly property color textColor: bar.textColor
    readonly property color dimColor: Config.tint("#8b94a3")

    Rectangle {
        id: menuBox
        readonly property string edge: tm.bar.side
        readonly property bool sideBar: edge === "left" || edge === "right"
        width: 240
        height: menuCol.implicitHeight + 16
        // Opens away from the bar, centred on the icon along it, kept on the screen
        x: Math.max(8, Math.min(tm.width - width - 8,
            edge === "left" ? tm.anchorX + 14 : edge === "right" ? tm.anchorX - width - 14 : tm.anchorX - width / 2))
        y: Math.max(8, Math.min(tm.height - height - 8,
            edge === "top" ? tm.anchorY + 14 : edge === "bottom" ? tm.anchorY - height - 14 : tm.anchorY - height / 2))
        radius: 12
        color: tm.bgColor
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside don't close

        // Pointer to the icon, on the side facing the bar (as on the dock's menus)
        Rectangle {
            readonly property real along: menuBox.sideBar
                ? Math.max(18, Math.min(parent.height - 18, tm.anchorY - parent.y))
                : Math.max(18, Math.min(parent.width - 18, tm.anchorX - parent.x))
            z: -1
            width: 14; height: 14
            rotation: 45
            color: parent.color
            x: menuBox.edge === "left" ? -width / 2 : menuBox.edge === "right" ? parent.width - width / 2 : along - width / 2
            y: menuBox.edge === "top" ? -height / 2 : menuBox.edge === "bottom" ? parent.height - height / 2 : along - height / 2
        }

        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 1

            // Back to the menu this one came from
            Item {
                visible: tm.stack.length > 1
                width: menuCol.width; height: visible ? 30 : 0
                Rectangle {
                    anchors.fill: parent; radius: 7
                    color: backHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (backHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
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
                        font.family: tm.bar.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    HoverHandler { id: backHover }
                    TapHandler { onTapped: tm.stack = tm.stack.slice(0, -1) }
                }
            }
            Rectangle {
                visible: tm.stack.length > 1
                width: menuCol.width - 16; x: 8; height: visible ? 1 : 0
                color: tm.rowHover
            }

            Repeater {
                model: tm.entries
                delegate: Item {
                    id: entryRow
                    required property var modelData
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
                        color: tm.rowHover
                    }
                    Rectangle {
                        visible: !entryRow.sep
                        anchors.fill: parent
                        radius: 7
                        color: entryHover.hovered && entryRow.e.enabled ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (entryHover.hovered && entryRow.e.enabled) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Behavior on color { ColorAnimation { duration: 90 } }
                        // Tick for a checked checkbox or radio item
                        Text {
                            visible: entryRow.checked
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            text: String.fromCodePoint(0xEA5E)
                            color: Config.accent
                            font.family: tm.bar.iconFont; font.pixelSize: 14
                        }
                        // Slate's own entries: an icon from the icon font
                        Text {
                            visible: !!entryRow.e && !entryRow.sep && !!entryRow.e.glyph
                            x: tm.anyChecks ? 28 : 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            horizontalAlignment: Text.AlignHCenter
                            text: visible ? String.fromCodePoint(entryRow.e.glyph) : ""
                            color: tm.dimColor
                            font.family: tm.bar.iconFont; font.pixelSize: 15
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
                            text: entryRow.e && !entryRow.sep ? String(entryRow.e.text).replace(/_(?!_)/g, "").replace(/__/g, "_") : ""
                            color: tm.textColor
                            opacity: entryRow.e && entryRow.e.enabled ? 1 : 0.4
                            font.family: tm.bar.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
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
                        TapHandler {
                            onTapped: {
                                const e = entryRow.e;
                                if (!e || !e.enabled) return;
                                if (e.hasChildren) { tm.stack = tm.stack.concat([e]); return; }
                                e.triggered();
                                tm.close();
                            }
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
                text: "No menu items"
                color: tm.dimColor
                font.family: tm.bar.fontFamily; font.pixelSize: 13
            }
        }
    }
}
