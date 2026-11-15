import QtQuick
import qs

// Horizontal slider, 0..1
Item {
    readonly property var pop: PanelHost.pop
    id: sl
    property real value: 0
    property bool muted: false
    property bool busy: false          // in use just now (sound playing, or being listened to)
    signal moved(real v)
    implicitHeight: 22
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: Config.corner(3)
        color: pop.card
        Rectangle {
            id: slFill
            width: Math.max(6, track.width * Math.min(1, sl.value)); height: parent.height; radius: Config.corner(3)
            // Switched off (a muted volume): a much darker accent, with diagonal stripes in the
            // red of its muted indicator across it, so it reads as there but not in use
            color: sl.muted ? Qt.darker(pop.accent, 2.4) : pop.accent
            Behavior on color { ColorAnimation { duration: Config.ms(320) } }
            clip: mutedStripes.visible || busyStripes.visible
            // Both sets of stripes are the same size, in the same places, and drift as one, so
            // going between them only the colour changes
            property real drift: 0
            NumberAnimation on drift {
                running: sl.busy && (mutedStripes.visible || busyStripes.visible) && Config.animate && !Config.gameMode
                from: 0; to: 9; duration: 700; loops: Animation.Infinite
            }
            // In use (sound playing through it, or something listening to it): stripes of a
            // darker accent drifting along it, fading in as it starts and out as it stops.
            // They hold still with animations off and in game mode
            Item {
                id: busyStripes
                anchors.fill: parent
                opacity: sl.busy && !sl.muted ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(320) } }
                visible: opacity > 0
                Repeater {
                    model: busyStripes.visible ? Math.ceil(slFill.width / 9) + 3 : 0
                    Rectangle {
                        required property int index
                        x: -14 + index * 9 + slFill.drift; y: (slFill.height - height) / 2
                        width: 3; height: slFill.height * 3
                        rotation: 40
                        antialiasing: true
                        color: Qt.darker(pop.accent, 1.45)
                    }
                }
            }
            // Muted: the red stripes, fading in and out as it's muted and unmuted (across to
            // the in-use stripes, or to none). They drift too while it's in use: sound is
            // playing, unheard
            Item {
                id: mutedStripes
                anchors.fill: parent
                opacity: sl.muted ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(320) } }
                visible: opacity > 0
                Repeater {
                    model: mutedStripes.visible ? Math.ceil(slFill.width / 9) + 3 : 0
                    Rectangle {
                        required property int index
                        // (leaning: taller than the bar and turned, cut off by the bar's own edges)
                        x: -14 + index * 9 + slFill.drift; y: (slFill.height - height) / 2
                        width: 3; height: slFill.height * 3
                        rotation: 40
                        antialiasing: true
                        color: pop.danger          // (the red of the muted speaker beside it)
                    }
                }
            }
        }
    }
    Rectangle {
        width: 16; height: 16; radius: Config.corner(8)
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(1, sl.value) * (sl.width - width)
        color: pop.text
        Gloss { radius: parent.radius; strength: 0.6 }   // glass: a sheen
    }
    MouseArea {
        preventStealing: true      // keep the drag once started, even if the pointer drifts off
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor      // (a hand over it, as over what's clicked)
        function set(mx) { sl.moved(Math.max(0, Math.min(1, mx / width))); }
        onPressed: m => set(m.x)
        onPositionChanged: m => { if (pressed) set(m.x); }
        onWheel: w => sl.moved(Math.max(0, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
