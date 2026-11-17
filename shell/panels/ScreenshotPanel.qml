import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects
import qs

// ---- Screenshots ------------------------------------------------------
// Take one of an area, a window or the screen (scripts/screenshot.sh), or record one
// (scripts/record.sh); the panel closes first so it isn't in the picture
Column {
    required property var pop
    id: shotView
    width: 300
    spacing: 10
    readonly property string folder: Config.s.screenshotFolder !== "" ? Config.s.screenshotFolder
        : Quickshell.env("HOME") + "/Pictures/Screenshots"
    function take(mode) {
        pop.close();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$0\" \"$1\"", Quickshell.shellPath("scripts/screenshot.sh"), mode]);
    }
    // (through Slate, a moment after the panel has closed, so it isn't in the recording)
    function record(mode) {
        pop.close();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$0\" ipc call record start \"$1\"", Quickshell.shellPath("bin/slate"), mode]);
    }
    readonly property var modes: [{ mode: "region", label: "Area", code: 0xEEAE },
                                  { mode: "window", label: "Window", code: 0xEFE6 },
                                  { mode: "screen", label: "Screen", code: 0xEA89 }]
    // A sound to record with it: an icon, its name and a switch
    component SoundSwitch: Item {
        id: sw
        property int code
        property string text
        property string key
        width: shotView.width; height: 30
        Icon {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            code: sw.code; font.pixelSize: 16; color: pop.dim
        }
        Label {
            anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
            text: sw.text; font.weight: Font.Normal
        }
        Switch {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: !!Config.s[sw.key]
            onToggled: Config.s[sw.key] = !Config.s[sw.key]
            Accessible.name: sw.text
        }
    }
    // An Area / Window / Screen tile
    component Tile: Rectangle {
        id: tile
        property int code
        property string text
        signal picked()
        width: (shotView.width - 16) / 3; height: 76
        radius: Config.corner(10)
        color: "transparent"
        Accessible.role: Accessible.Button
        Accessible.name: tile.text
        Accessible.onPressAction: tile.picked()
        HoverFill { base: pop.card; hovered: tileHover.hovered; radius: parent.radius }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; code: tile.code; font.pixelSize: 22; color: pop.text }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: tile.text; font.weight: Font.Normal }
        }
        HoverHandler { id: tileHover }
        ClickTap { onTapped: tile.picked() }
    }
    PanelTitle { text: "Screenshot"; height: textHeight }
    Row {
        width: parent.width
        spacing: 8
        Repeater {
            model: shotView.modes
            delegate: Tile { required property var modelData; code: modelData.code; text: modelData.label; onPicked: shotView.take(modelData.mode) }
        }
    }
    Label {
        width: parent.width
        text: "Saved to " + shotView.folder.replace(Quickshell.env("HOME"), "~") + " and copied"
        color: pop.dim; font.weight: Font.Normal; font.pixelSize: Config.text(12); elide: Text.ElideMiddle
    }
    // Recording the screen (ScreenRecorder.qml, scripts/record.sh): the same three, or Stop
    // while one's going
    Divider {}
    Heading { text: "Record the screen" }
    Row {
        visible: !Config.recording
        width: parent.width
        spacing: 8
        Repeater {
            model: shotView.modes
            delegate: Tile { required property var modelData; code: modelData.code; text: modelData.label; onPicked: shotView.record(modelData.mode) }
        }
    }
    RowButton {
        visible: Config.recording
        width: parent.width
        danger: true
        onClicked: { pop.close(); Quickshell.execDetached([Quickshell.shellPath("scripts/record.sh"), "stop"]); }
        Icon {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            code: 0xF695; font.pixelSize: 16; color: Config.tint("#f28b8b")
        }
        Label {
            anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
            text: "Stop recording · " + Config.recordingTime(); font.weight: Font.Normal; color: Config.tint("#f28b8b")
        }
    }
    // What's recorded with it: either, both (mixed) or neither
    SoundSwitch { visible: !Config.recording; code: 0xEB51; text: "Computer sound"; key: "recordComputerSound" }
    SoundSwitch { visible: !Config.recording; code: 0xEAF0; text: "Microphone"; key: "recordMicrophone" }
    Divider {}
    LinkRow {
        code: 0xEAAD; text: "Open screenshots folder"
        onClicked: { pop.close(); Quickshell.execDetached(["sh", "-c", "mkdir -p \"$0\" && exec xdg-open \"$0\"", shotView.folder]); }
    }
    LinkRow {
        code: 0xEB20; text: "Screenshot settings"
        onClicked: pop.openSettingsPage("screenshots")
    }
}
