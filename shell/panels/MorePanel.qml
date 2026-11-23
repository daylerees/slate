import QtQuick
import qs

Column {
    required property var pop
    id: moreView
    width: 300
    spacing: 10
    readonly property var rows: pop.moreBar ? (pop.moreBar.overflowed, pop.moreBar.moreRows()) : []
    PanelTitle { text: "More"; height: textHeight }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        color: pop.dim; font.weight: Font.Normal
        text: moreView.rows.length > 0 ? "There isn't room for these on the bar just now. They'll be back when there is"
                                       : "Everything's on the bar. What doesn't fit will wait here"
    }
    // The rows, scrolling once there are more than fit (a long list at a large Interface
    // size, or on a short screen): at most 480 tall, less on a short screen, so the panel
    // never runs off it. Shades, a scrollbar and smooth wheel, as every list has
    Item {
        id: moreList
        width: parent.width
        visible: moreView.rows.length > 0
        height: Math.min(moreRowsCol.implicitHeight, 480, Math.max(160, pop.height - 220))
        readonly property bool overflowing: moreRowsCol.implicitHeight > height + 0.5
        Flickable {
            id: moreFlick
            anchors.fill: parent
            contentHeight: moreRowsCol.implicitHeight
            clip: true
            interactive: moreList.overflowing
            boundsBehavior: Flickable.StopAtBounds
            SmoothWheel { flick: moreFlick }
            Column {
                id: moreRowsCol
                width: moreList.width - (moreList.overflowing ? 18 : 0)   // room for the scrollbar and a gap before it
                spacing: 4
                Repeater {
                    model: moreView.rows
                    delegate: RowButton {
                        id: moreRow
                        required property var modelData
                        width: parent.width
                        onClicked: pop.moreBar.moreClick(modelData, false)
                        onMenuAsked: pop.moreBar.moreClick(modelData, true)
                        ClickTap { acceptedButtons: Qt.RightButton; onTapped: pop.moreBar.moreClick(moreRow.modelData, true) }
                        WheelHandler { onWheel: e => pop.moreBar.moreWheel(moreRow.modelData, e.angleDelta.y) }
                        Icon {
                            id: moreIcon
                            visible: moreRow.modelData.image === ""
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            code: moreRow.modelData.icon
                            color: moreRow.modelData.id === "power" ? pop.danger : Config.statusColour(moreRow.modelData.id, pop.text)
                        }
                        Image {
                            visible: moreRow.modelData.image !== ""
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 18; height: 18
                            sourceSize: Qt.size(36, 36)
                            source: moreRow.modelData.image
                        }
                        Label {
                            id: moreName
                            anchors { left: parent.left; leftMargin: 38; verticalCenter: parent.verticalCenter }
                            text: moreRow.modelData.label
                            width: Math.min(implicitWidth, parent.width - 38 - 10 - (moreValue.visible ? moreValue.width + 10 : 0))
                            elide: Text.ElideRight
                        }
                        Label {
                            id: moreValue
                            visible: text !== ""
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: Math.min(implicitWidth, parent.width * 0.5)
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            color: pop.dim; font.weight: Font.Normal
                            text: moreRow.modelData.value
                        }
                    }
                }
            }
        }
        // (deeper in dark mode, where the panel's as dark as the shade itself, as the dock's More)
        ScrollShade { z: 3; y: 0; width: moreRowsCol.width; height: 28; cornerRadius: 8; depth: Config.s.lightMode ? 1 : 2.4
                      distance: moreFlick.contentY }
        ScrollShade { z: 3; atBottom: true; y: moreList.height - height; width: moreRowsCol.width; height: 28; cornerRadius: 8
                      depth: Config.s.lightMode ? 1 : 2.4
                      distance: moreFlick.contentHeight - moreFlick.height - moreFlick.contentY }
        ThinScrollbar { z: 3; flick: moreFlick; color: pop.text; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
    }
    Divider {}
    LinkRow {
        code: 0xEB20; text: "Menu Bar settings"
        onClicked: pop.openSettingsPage("bar")
    }
}
