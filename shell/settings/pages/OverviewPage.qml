import QtQuick
import "../.."
import ".."

// ---- Pages -------------------------------------------------------------
// Overview: tiles for the pages that aren't in the sidebar
Column {
    readonly property var win: SettingsHost.win
    id: ovPage
    spacing: 4
    PageTitle { text: "All Settings" }
    // ---- Search every setting (SettingsIndex) ----------------------------------
    readonly property var found: SettingsIndex.search(findField.text, 30)
    property int pick: 0
    onFoundChanged: pick = 0
    function open(e) { if (e) win.goTo(e.page, e.label); }
    Rectangle {
        width: parent.width; height: 44
        radius: Config.corner(12)
        color: win.card          // (flat, as Slate's other text boxes: no sheen)
        border.width: findField.activeFocus ? 1 : 0; border.color: win.accent
        Text {
            id: findIcon
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: Config.glyph(0xEB1C)
            color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 18
        }
        TextInput {
            activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
            id: findField
            anchors { left: findIcon.right; leftMargin: 10; right: clearFind.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            color: win.text; font.family: win.font; font.pixelSize: Config.text(14)
            selectionColor: win.accent; selectedTextColor: win.accentText
            clip: true
            // Ready to type whenever All Settings shows: when the page loads and each time
            // the window opens (after the window's own focus has settled), starting afresh
            function ready() { Qt.callLater(() => Qt.callLater(() => { if (win.visible && win.section === "overview") findField.forceActiveFocus(); })); }
            Component.onCompleted: ready()
            Connections {
                target: win
                function onVisibleChanged() { if (win.visible) { findField.text = ""; findField.ready(); } }
                function onSearchFor(t) { if (win.section === "overview") { findField.forceActiveFocus(); findField.text = t; } }
            }
            // ...and when the window gets the keyboard (Hyprland focuses it a moment after it shows)
            readonly property bool windowActive: Window.active
            onWindowActiveChanged: if (windowActive && text === "") ready()
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Down) { ovPage.pick = Math.min(ovPage.found.length - 1, ovPage.pick + 1); e.accepted = true; }
                else if (e.key === Qt.Key_Up) { ovPage.pick = Math.max(0, ovPage.pick - 1); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { ovPage.open(ovPage.found[ovPage.pick]); e.accepted = true; }
                else if (e.key === Qt.Key_Escape && text !== "") { text = ""; e.accepted = true; }
            }
            Text {
                visible: findField.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Search settings"
                color: win.dim; font: findField.font
            }
        }
        Text {
            id: clearFind
            visible: findField.text !== ""
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: Config.glyph(0xEB55)
            color: clearHover.hovered ? win.text : win.dim
            // (with the fill behind it, not ahead of it)
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            font.family: win.bar.iconFont; font.pixelSize: 16
            HoverHandler { id: clearHover }
            ClickTap { onTapped: { findField.text = ""; findField.forceActiveFocus(); } }
        }
    }
    Item { width: 1; height: 6 }
    // What's under the search box scrolls by itself (the results, or the tiles), so the
    // box stays where it is: the page as a whole is made to fit, and never scrolls
    Item {
        width: parent.width
        height: Math.max(160, win.scrollView.height - 80)
        Flickable {
            id: ovScroll
            anchors { fill: parent; rightMargin: contentHeight > height ? 18 : 0 }
            contentHeight: ovInner.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            SmoothWheel { flick: ovScroll }
            Column {
                id: ovInner
                width: ovScroll.width
                spacing: 4
                // Results, while searching
                Text {
                    visible: findField.text.trim().length >= 2 && ovPage.found.length === 0
                    topPadding: 8; leftPadding: 4
                    text: "No settings match “" + findField.text.trim() + "”"
                    color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
                }
                Group {
                    visible: ovPage.found.length > 0
                    Repeater {
                        model: ovPage.found
                        delegate: Rectangle {
                            id: hitRow
                            required property var modelData
                            required property int index
                            readonly property bool chosen: index === ovPage.pick
                            width: parent.width; height: hitCol.implicitHeight + 18
                            radius: Config.corner(9)
                            color: chosen ? win.accent : hitHover.hovered ? Config.hover : "transparent"
                            Text {
                                id: hitIcon
                                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                                text: Config.glyph(SettingsIndex.pageIcons[hitRow.modelData.page] || 0xEB20)
                                color: hitRow.chosen ? win.accentText : win.dim
                                font.family: win.bar.iconFont; font.pixelSize: 17
                            }
                            Column {
                                id: hitCol
                                anchors { left: hitIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: hitRow.modelData.label
                                    color: hitRow.chosen ? win.accentText : win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: (SettingsIndex.pageNames[hitRow.modelData.page] || "")
                                        + (hitRow.modelData.group && hitRow.modelData.group !== hitRow.modelData.label ? " → " + hitRow.modelData.group : "")
                                        + (hitRow.modelData.detail ? " · " + hitRow.modelData.detail : "")
                                    color: hitRow.chosen ? Qt.rgba(win.accentText.r, win.accentText.g, win.accentText.b, 0.72) : win.dim; font.family: win.font; font.pixelSize: Config.text(11)
                                    elide: Text.ElideRight
                                }
                            }
                            HoverHandler { id: hitHover }
                            ClickTap { onTapped: ovPage.open(hitRow.modelData) }
                        }
                    }
                }
                Flow {
                    id: tiles
                    visible: findField.text.trim().length < 2
                    width: parent.width
                    spacing: 10
                    // Two or three across, filling the width
                    readonly property int across: width >= 560 ? 3 : width >= 340 ? 2 : 1
                    readonly property real tileW: (width - spacing * (across - 1)) / across
                    Repeater {
                        model: win.sections
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            width: tiles.tileW
                            height: 112
                            radius: Config.corner(12)
                            color: "transparent"
                            HoverFill { base: win.card; hovered: tileHover.hovered; radius: parent.radius }
                            Rectangle {
                                x: 14; y: 14
                                width: 34; height: 34; radius: Config.corner(10)
                                // The page's own colour when colourful, else the accent
                                readonly property color pc: Config.pageColour(tile.modelData.id)
                                color: Qt.rgba(pc.r, pc.g, pc.b, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: Config.glyph(tile.modelData.icon)
                                    color: parent.pc
                                    font.family: win.bar.iconFont; font.pixelSize: 18
                                }
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 58 }
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: tile.modelData.label
                                    color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: tile.modelData.about
                                    color: win.dim; font.family: win.font; font.pixelSize: Config.text(11)
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                }
                            }
                            HoverHandler { id: tileHover }
                            ClickTap { onTapped: win.section = tile.modelData.id }
                        }
                    }
                }
            }
        }
        ThinScrollbar {
            flick: ovScroll
            color: win.text
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right; bottomMargin: 8 }
        }
        ScrollShade {
            anchors { top: parent.top; left: parent.left; right: ovScroll.right }
            distance: ovScroll.contentY
        }
        ScrollShade {
            atBottom: true
            anchors { bottom: parent.bottom; left: parent.left; right: ovScroll.right }
            distance: ovScroll.contentHeight - ovScroll.height - ovScroll.contentY
        }
    }
}
