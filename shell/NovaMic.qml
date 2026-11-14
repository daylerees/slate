// The microphone at the end of Nova's box (Settings → Assistant → Voice): hold it and talk,
// let go to send (NovaVoice.qml). While it listens it wears the active colour with a soft
// ring breathing round it, so it's plain that Slate is listening; while your words are turned
// into text, Slate's spinner. Flat (no sheen); the ring and the spinner keep their own timing
// (they're indicators, not transitions) and keep still with animations off or in game mode.

import QtQuick

Rectangle {
    id: mic
    property var voice: null
    property string iconFont: ""
    property color ink: Config.tint("#8b94a3")       // the icon at rest (the window's dim text)
    property color accent: Config.accent
    property color accentText: Config.tint("#12151a")
    readonly property string phase: voice ? voice.phase : ""
    readonly property bool lit: phase === "listening" || phase === "starting"
    readonly property bool moving: visible && Config.animate && !Config.gameMode
    width: 30; height: 30; radius: Config.corner(15)
    color: lit ? accent : "transparent"
    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
    HoverFill { base: "transparent"; hovered: micHover.hovered; gone: mic.lit; radius: parent.radius }

    // Listening: a ring of the accent, breathing out from the button
    Rectangle {
        id: ring
        visible: mic.lit
        anchors.centerIn: parent
        width: parent.width; height: parent.height; radius: Config.corner(width / 2)
        color: "transparent"
        border.width: 2; border.color: mic.accent
        opacity: mic.moving ? 0 : 0.45
        scale: 1.25
        SequentialAnimation {
            running: mic.lit && mic.moving
            loops: Animation.Infinite
            onRunningChanged: if (!running) { ring.scale = 1.25; ring.opacity = Qt.binding(() => mic.moving ? 0 : 0.45); }
            ParallelAnimation {
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.5; duration: 1100; easing.type: Easing.OutSine }
                NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: 1100; easing.type: Easing.OutSine }
            }
        }
    }
    Text {
        id: glyph
        anchors.centerIn: parent
        text: String.fromCodePoint(mic.phase === "transcribing" ? 0xF226 : 0xEAF0)      // spinner, microphone
        color: mic.lit ? mic.accentText : mic.phase === "transcribing" ? mic.accent : mic.ink
        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
        font.family: mic.iconFont; font.pixelSize: 16
        RotationAnimation on rotation {
            running: mic.phase === "transcribing" && mic.moving
            from: 0; to: 360; duration: 900; loops: Animation.Infinite
            onRunningChanged: if (!running) glyph.rotation = 0
        }
    }
    HoverHandler { id: micHover }
    // Held, it listens; let go, and what you said is sent. (No click on a tap: listening
    // starting plays it, so a short press doesn't click twice)
    ClickTap {
        sound: false
        onPressedChanged: {
            if (!mic.voice) return;
            if (pressed) mic.voice.hold();
            else mic.voice.release();
        }
    }
}
