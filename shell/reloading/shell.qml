// The cover shown while Slate restarts (bin/slate restart): every screen fades to Slate's dark
// slate with its mark, "Reloading Slate" and a spinner, the old Slate goes and the new one
// starts underneath, and the cover fades away again once the new one says it's ready.
// A small Quickshell setup of its own, so it outlives the Slate it covers for:
//   qs -p <slate>/reloading                          show it
//   qs -p <slate>/reloading ipc call cover done      fade it out and quit
// It reads only what it needs from Slate's settings (animations, game mode) and the theme's
// colours as Slate last noted them, uses Slate's fonts and icon, and quits by itself after a while, so it can never be left over a screen.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property string slate: Quickshell.shellPath("..")

    property bool shown: false
    property bool leaving: false
    Component.onCompleted: shown = true
    IpcHandler {
        target: "cover"
        function done(): void { root.leaving = true; if (!root.animate) Qt.quit(); }
    }
    Timer { running: true; interval: 20000; onTriggered: Qt.quit() }      // never left up

    // Settings → Appearance → Animations (and game mode): none, or faster, as everywhere
    property real scale: 1
    readonly property bool animate: scale > 0
    function ms(t) { return Math.round(t * scale); }
    FileView {
        path: root.slate + "/settings.json"
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.scale = s.gameMode || s.animations === "off" ? 0 : s.animations === "fast" ? 0.5 : 1;
            } catch (e) {}
        }
    }
    // The theme's colours, as Slate last noted them (Config.coverColours → ~/.cache/slate/
    // cover.json): light or dark, the wallpaper's tint, the accent. Slate's dark slate until
    // (or if never) that's read
    property color background: "#0f1216"
    property color text: "#eef1f5"
    property color dim: "#8b94a3"
    property color accent: "#8fb3e8"
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/slate/cover.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const ok = v => typeof v === "string" && /^#[0-9a-f]{6,8}$/i.test(v);
                if (ok(c.background)) root.background = c.background;
                if (ok(c.text)) root.text = c.text;
                if (ok(c.dim)) root.dim = c.dim;
                if (ok(c.accent)) root.accent = c.accent;
            } catch (e) {}
        }
    }
    FontLoader { id: geist; source: "file://" + root.slate + "/fonts/Geist-Variable.ttf" }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-reloading"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: root.background
                opacity: root.leaving ? 0 : root.shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.ms(260); easing.type: Easing.InOutQuad
                        onRunningChanged: if (!running && root.leaving) Qt.quit()
                    }
                }
                MouseArea { anchors.fill: parent }      // (nothing under it is clicked meanwhile)

                Column {
                    anchors.centerIn: parent
                    spacing: 18
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 84; height: 84
                        sourceSize: Qt.size(256, 256)
                        source: "file://" + root.slate + "/assets/icon/icon-256.png"
                        smooth: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Reloading Slate"
                        color: root.text
                        font.family: geist.name; font.pixelSize: 20; font.weight: Font.Medium
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Your apps and windows stay open"
                        color: root.dim
                        font.family: geist.name; font.pixelSize: 13
                    }
                    // A ring with a gap, turning (still, with animations off)
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 26; height: 26
                        Canvas {
                            id: ring
                            anchors.fill: parent
                            readonly property color ink: root.accent
                            onInkChanged: requestPaint()
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                ctx.lineWidth = 2.5; ctx.lineCap = "round";
                                ctx.strokeStyle = root.accent;
                                ctx.beginPath();
                                ctx.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 1.5);
                                ctx.stroke();
                            }
                            RotationAnimation on rotation { running: root.animate; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                }
            }
        }
    }
}
