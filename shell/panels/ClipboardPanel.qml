import QtQuick
import Quickshell
import Quickshell.Io
import qs

// ---- Clipboard history ------------------------------------------------
// The latest things copied (scripts/clipstore.py); click one to copy it again. Super+V
// (Show all) has the full, searchable list.
Column {
    required property var pop
    id: clipView
    width: 320
    spacing: 10
    readonly property string script: Quickshell.shellPath("scripts/clipstore.py")
    readonly property string dir: Config.clipIndex.replace(/\/index\.json$/, "")
    property var entries: []
    FileView {
        path: Config.clipIndex
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { clipView.entries = JSON.parse(text()).entries || []; } catch (e) { clipView.entries = []; } }
        onLoadFailed: clipView.entries = []
    }

    PanelTitle {
        text: "Clipboard"
        height: 22
        Label {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            visible: Config.s.clipboardHistory
            text: clipView.entries.length === 1 ? "1 item" : clipView.entries.length + " items"
            color: pop.dim; font.weight: Font.Normal
        }
    }
    Label {
        width: parent.width
        visible: !Config.s.clipboardHistory || clipView.entries.length === 0
        text: !Config.s.clipboardHistory ? "Clipboard history is off, so nothing you copy is kept"
            : "Nothing here yet. Things you copy will show up here"
        color: pop.dim; font.weight: Font.Normal; wrapMode: Text.Wrap
    }
    Column {
        width: parent.width
        spacing: 6
        visible: Config.s.clipboardHistory && clipView.entries.length > 0
        Repeater {
            model: clipView.entries.slice(0, 8)
            delegate: RowButton {
                id: clipRow
                required property var modelData
                width: parent.width
                height: modelData.kind === "image" ? 52 : 36
                onClicked: { Quickshell.execDetached(["python3", clipView.script, "copy", modelData.id]); pop.close(); }
                Image {
                    id: clipThumb
                    visible: clipRow.modelData.kind === "image"
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    width: visible ? 56 : 0; height: 40
                    source: visible ? "file://" + clipView.dir + "/" + clipRow.modelData.file : ""
                    sourceSize: Qt.size(112, 80)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Icon {
                    id: clipIcon
                    visible: clipRow.modelData.kind !== "image"
                    code: 0xF089; font.pixelSize: 16; color: pop.dim
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                }
                Label {
                    anchors {
                        left: clipRow.modelData.kind === "image" ? clipThumb.right : clipIcon.right; leftMargin: 10
                        right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter
                    }
                    text: clipRow.modelData.kind === "image"
                        ? "Image" + (clipRow.modelData.w ? " · " + clipRow.modelData.w + " × " + clipRow.modelData.h : "")
                        : (clipRow.modelData.text || "").replace(/\s+/g, " ").trim()
                    font.weight: Font.Normal
                    elide: Text.ElideRight
                }
            }
        }
    }
    Divider {}
    LinkRow {
        visible: Config.s.clipboardHistory
        code: 0xEA6D; text: "Show all and search (Super+V)"
        onClicked: { pop.close(); pop.slate(["picker", "clipboard"]); }
    }
    LinkRow {
        visible: Config.s.clipboardHistory && clipView.entries.length > 0
        code: 0xEB41; text: "Clear history"
        iconColor: pop.danger; textColor: pop.danger; danger: true
        // (the panel closes and Slate's confirmation window asks first, as the picker's Clear all does)
        onClicked: {
            pop.close();
            pop.powerConfirm.confirmWith(Config.clearClipsQuestion, () => {
                clipView.entries = [];
                Quickshell.execDetached(["python3", clipView.script, "clear"]);
            });
        }
    }
    LinkRow {
        code: 0xEB20; text: "Clipboard settings"
        onClicked: { pop.close(); pop.slate(["settings", "find", "general", "Clipboard history"]); }
    }
}
