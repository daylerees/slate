// A small note in the middle of the screen while the secret workspace is showing with nothing
// on it: otherwise it's just the dimmed desktop, and it's not clear anything happened. One for
// each screen (each shows its secret workspace on its own). Never takes the pointer or the
// keyboard, and goes as soon as a window is there. In the menu bar's colours, so it follows the
// theme, the tint and glass (it shares the OSD's layer name, which is blurred on glass).

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: note
    required property var bar
    // The secret workspace is showing on this screen, with nothing on it
    readonly property bool shown: !!screen && Config.secretEmpty(screen.name) && !Config.isLoginScreen

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(note.shown ? 260 : 120); easing.type: Easing.OutCubic } }
    visible: fade > 0
    implicitWidth: card.width + 80
    implicitHeight: card.height + 80
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-osd"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                   // never blocks the pointer

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.max(280, words.implicitWidth + 56)
        height: words.implicitHeight + 44
        radius: Config.corner(18)
        color: note.bar.barColor
        opacity: note.fade
        scale: 0.96 + 0.04 * note.fade
        Gloss { radius: parent.radius }   // glass: a sheen (with its own bright edge)
        Shadow { blur: 16; dropY: 3 }      // raised: Slate's shadow, with glass too

        Column {
            id: words
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String.fromCodePoint(0xECF0)          // eye-off
                color: note.bar.accent
                font.family: note.bar.iconFont; font.pixelSize: 26
                bottomPadding: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Your secret workspace is empty"
                color: note.bar.textColor
                font.family: note.bar.fontFamily; font.pixelSize: 15; font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "A quiet spot for anything you'd like kept out of the way.\nOpen an app here, or send a window over with Super+Shift+S."
                color: note.bar.dimColor
                font.family: note.bar.fontFamily; font.pixelSize: 12; font.weight: Font.Normal
                lineHeight: 1.25
            }
        }
    }
}
