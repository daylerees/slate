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
// Take one of an area, a window or the screen (scripts/screenshot.sh); the panel closes
// first so it isn't in the picture
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
    PanelTitle { text: "Screenshot"; height: textHeight }
    Row {
        width: parent.width
        spacing: 8
        Repeater {
            model: [{ mode: "region", label: "Area", code: 0xEEAE },
                    { mode: "window", label: "Window", code: 0xEFE6 },
                    { mode: "screen", label: "Screen", code: 0xEA89 }]
            delegate: Rectangle {
                id: shotTile
                required property var modelData
                width: (shotView.width - 16) / 3; height: 76
                radius: Config.corner(10)
                color: "transparent"
                HoverFill { base: pop.card; hovered: shotHover.hovered; radius: parent.radius }
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; code: shotTile.modelData.code; font.pixelSize: 22; color: pop.text }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: shotTile.modelData.label; font.weight: Font.Normal }
                }
                HoverHandler { id: shotHover }
                ClickTap { onTapped: shotView.take(shotTile.modelData.mode) }
            }
        }
    }
    Label {
        width: parent.width
        text: "Saved to " + shotView.folder.replace(Quickshell.env("HOME"), "~") + " and copied"
        color: pop.dim; font.weight: Font.Normal; font.pixelSize: 12; elide: Text.ElideMiddle
    }
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
