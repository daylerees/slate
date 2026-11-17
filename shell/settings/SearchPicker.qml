import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A choice from a long list (keyboard layouts, time zones, apps): a button that opens a
// search box and list under the row. options: [{ value, label, detail? }]
Column {
    readonly property var win: SettingsHost.win
    id: searchPicker
    property string label
    property string detail: ""
    property string buttonLabel: "Choose…"
    property int buttonIcon: 0
    property var options: []
    property bool open: false
    signal picked(var value)
    width: parent ? parent.width : 0
    readonly property var shown: {
        const q = findBox.text.toLowerCase().trim();
        const list = q === "" ? options : options.filter(o => (o.label + " " + (o.detail || "") + " " + o.value).toLowerCase().includes(q));
        return list.slice(0, 400);
    }
    SettingRow {
        label: searchPicker.label
        detail: searchPicker.detail
        Button {
            icon: searchPicker.open ? 0 : searchPicker.buttonIcon
            label: searchPicker.open ? "Cancel" : searchPicker.buttonLabel
            onClicked: {
                searchPicker.open = !searchPicker.open;
                findBox.text = "";
                if (searchPicker.open) Qt.callLater(() => findBox.forceActiveFocus());
            }
        }
    }
    Column {
        visible: searchPicker.open
        width: parent.width - 32; x: 16
        spacing: 6
        bottomPadding: 14
        Rectangle {
            width: parent.width; height: 34; radius: Config.corner(8)
            color: win.well
            border.width: findBox.activeFocus ? 1 : 0; border.color: win.accent
            Text {
                id: findGlass
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: win.glyph(0xEB1C); color: win.dim
                font.family: win.bar.iconFont; font.pixelSize: 15
            }
            TextInput {
                id: findBox
                anchors { left: findGlass.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                color: win.text; font.family: win.font; font.pixelSize: Config.text(13)
                selectionColor: win.accent; selectedTextColor: win.accentText
                clip: true
                Keys.onReturnPressed: if (searchPicker.shown.length > 0) { searchPicker.picked(searchPicker.shown[0].value); searchPicker.open = false; }
                Keys.onEscapePressed: event => { searchPicker.open = false; event.accepted = true; }
                Text { visible: findBox.text === ""; text: "Search"; color: win.dim; font: findBox.font; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Rectangle {
            width: parent.width; height: Math.min(220, Math.max(40, pickList.contentHeight + 8)); radius: Config.corner(8)
            color: win.well
            ListView {
                id: pickList
                anchors { fill: parent; margins: 4 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                SmoothWheel { flick: pickList }
                model: searchPicker.shown
                delegate: Rectangle {
                    required property var modelData
                    width: pickList.width - (pickList.contentHeight > pickList.height ? 12 : 0); height: pickDetail.visible ? 42 : 32; radius: Config.corner(6)
                    color: pickHover.hovered ? Config.hover : "transparent"
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        Text { width: parent.width; textFormat: Text.PlainText; text: parent.parent.modelData.label; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); elide: Text.ElideRight }
                        Text { id: pickDetail; width: parent.width; visible: !!parent.parent.modelData.detail; textFormat: Text.PlainText; text: parent.parent.modelData.detail || ""; color: win.dim; font.family: win.font; font.pixelSize: Config.text(11); elide: Text.ElideRight }
                    }
                    HoverHandler { id: pickHover }
                    ClickTap { onTapped: { searchPicker.picked(parent.modelData.value); searchPicker.open = false; } }
                }
                Text {
                    anchors.centerIn: parent
                    visible: pickList.count === 0
                    text: "Nothing matches"
                    color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
                }
            }
            ScrollShade {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 3; cornerRadius: 8
                distance: pickList.contentY - pickList.originY
            }
            ScrollShade {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                z: 3; atBottom: true; cornerRadius: 8
                distance: pickList.originY + pickList.contentHeight - pickList.height - pickList.contentY
            }
            ThinScrollbar {
                z: 3; flick: pickList; color: win.text
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: 4; bottomMargin: 4; rightMargin: 2 }
            }
        }
    }
}
