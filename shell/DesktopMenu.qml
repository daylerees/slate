// The desktop's right-click menu (Wallpaper.qml), in the same style as the dock's and the
// tray's menus. Opens where you click, kept on the screen. Click outside or press Escape
// to close.   menu.openAt(x, y)   (in the screen's own coordinates)
//   items: [{ label, icon, run: function }] with { separator: true } between groups

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dm
    property var items: []
    property real atX: 0
    property real atY: 0

    function openAt(x, y) { atX = x; atY = y; visible = true; }
    function close() { visible = false; }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false
    WlrLayershell.namespace: "slate-desktop-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: dm.close() }
    Item { focus: dm.visible; Keys.onEscapePressed: dm.close() }

    // Look: the dock menu's
    readonly property color bgColor: Config.surface(Config.tint("#0f1216"))
    readonly property color rowHover: Config.tint("#1d222a")
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimColor: Config.tint("#8b94a3")
    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    Rectangle {
        width: 230
        height: menuCol.implicitHeight + 16
        // At the pointer, or to its left / above it when it would run off the screen
        x: dm.atX + width + 8 > dm.width ? Math.max(8, dm.atX - width) : dm.atX
        y: dm.atY + height + 8 > dm.height ? Math.max(8, dm.atY - height) : dm.atY
        radius: 12
        color: dm.bgColor
        Shadow { blur: 18 }                // raised: Slate's shadow, with glass too
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside don't close

        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 1
            Repeater {
                model: dm.items
                delegate: Item {
                    id: row
                    required property var modelData
                    width: menuCol.width
                    height: modelData.separator ? 9 : 30
                    Rectangle {
                        visible: !!row.modelData.separator
                        anchors.centerIn: parent
                        width: parent.width - 16; height: 1
                        color: dm.rowHover
                    }
                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: 7
                        color: itemHover.hovered ? Config.hover : "transparent"
                        Gloss { radius: parent.radius; opacity: (itemHover.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
                        Behavior on color { ColorAnimation { duration: Config.ms(90) } }
                        Text {
                            id: rowIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: row.modelData.icon ? String.fromCodePoint(row.modelData.icon) : ""
                            color: dm.dimColor
                            font.family: tabler.name; font.pixelSize: 16
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: row.modelData.label || ""
                            color: dm.textColor
                            font.family: Config.s.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        HoverHandler { id: itemHover }
                        ClickTap {
                            onTapped: {
                                const run = row.modelData.run;
                                dm.close();
                                if (run) run();
                            }
                        }
                    }
                }
            }
        }
    }
}
