// Screensaver (Settings → Screensaver): after a while with no input it covers every screen,
// before the lock and screen-off timers in Lock & idle (which carry on as before). Any key,
// click or pointer move puts it away; the key or click goes no further. Apps that keep the
// screen awake (video) hold it off, as they do the lock, when Lock & idle says so. With
// "Lock on wake", waking it locks the screen first, and it goes once the lock is up, so the
// desktop never shows unlocked (not for a preview).
// Three styles:
//   drift      your wallpaper, dimmed and slowly drifting, with a clock and the date
//   slideshow  the pictures in your wallpaper folder, cross-fading, with a clock if wanted
//   black      a clock and the date on black, moving now and then so nothing burns in
//   slate ipc call screensaver start     (a preview: any input puts it away)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    // LockScreen.qml: the screensaver steps aside once the screen locks
    property var lock: null
    readonly property bool locked: !!lock && lock.locked

    readonly property int minutes: Config.s.screensaverMinutes
    readonly property string style: Config.s.screensaverStyle
    property bool shown: false
    property bool fromIdle: false     // started by being idle (not a preview)
    property bool locking: false      // woken with Lock on wake: waiting for the lock

    function start(idle) {
        if (locked || shown) return;
        fromIdle = !!idle;
        shown = true;
    }
    // Any input: put it away, locking first if that's wanted
    function wake() {
        if (!shown || locking) return;
        if (fromIdle && Config.s.screensaverLock && lock && !locked) {
            locking = true;
            lock.lockNow();
            lockFallback.restart();
            return;
        }
        stop();
    }
    function stop() { shown = false; locking = false; fromIdle = false; }
    onLockedChanged: if (locked) stop()
    // Locking didn't happen (it can be refused): don't stay up forever
    Timer { id: lockFallback; interval: 3000; onTriggered: if (root.locking) root.stop() }

    IdleMonitor {
        enabled: root.minutes > 0 && !root.locked
        timeout: root.minutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: if (isIdle) root.start(true); else root.wake()
    }
    IpcHandler {
        target: "screensaver"
        function start(): void { root.start(false); }
        function stop(): void { root.stop(); }
    }

    // ---- The slideshow's pictures: the wallpaper folder, shuffled ----------------------
    readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
    property var pictures: []
    Process {
        id: pictureList
        command: ["sh", "-c", "find \"$0\" -maxdepth 2 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) 2>/dev/null | shuf",
                  root.folder]
        stdout: StdioCollector { onStreamFinished: root.pictures = text.split("\n").filter(x => x !== "") }
    }
    onShownChanged: if (shown && style === "slideshow") { pictureList.running = false; pictureList.running = true; }

    // Fades in slowly, away quickly
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(root.shown ? 1500 : 180); easing.type: Easing.InOutQuad } }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.fade > 0
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "slate-screensaver"
            WlrLayershell.layer: WlrLayer.Overlay
            // Holds the keyboard so the key that puts it away doesn't reach an app
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Item {
                id: face
                anchors.fill: parent
                opacity: root.fade
                focus: root.shown
                Keys.onPressed: e => { root.wake(); e.accepted = true; }

                Rectangle { anchors.fill: parent; color: "black" }
                Loader {
                    anchors.fill: parent
                    active: root.fade > 0
                    sourceComponent: root.style === "slideshow" ? slideshow : root.style === "black" ? onBlack : drift
                }

                // A click, scroll or real pointer move puts it away (a nudge of a few pixels
                // doesn't: sensitive mice and desks)
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    property point first: Qt.point(-1, -1)
                    onPositionChanged: m => {
                        if (first.x < 0) { first = Qt.point(m.x, m.y); return; }
                        if (Math.abs(m.x - first.x) + Math.abs(m.y - first.y) > 16) root.wake();
                    }
                    onPressed: root.wake()
                    onWheel: root.wake()
                }
                // Each time it shows: take the keys, and forget where the pointer was
                Connections {
                    target: root
                    function onShownChanged() {
                        pointer.first = Qt.point(-1, -1);
                        if (root.shown) face.forceActiveFocus();
                    }
                }
            }
        }
    }

    // ---- The clock and date ----------------------------------------------------------
    component ClockFace: Column {
        spacing: 4
        SystemClock { id: clock; precision: SystemClock.Minutes }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, Config.s.barClockFormat === "24h" ? "HH:mm" : "h:mm")
            color: "white"
            font.family: Config.s.fontFamily; font.pixelSize: 112; font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd d MMMM")
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: Config.s.fontFamily; font.pixelSize: 22
        }
    }

    // A picture filling the screen, drifting and zooming very slowly
    component Drifting: Image {
        id: img
        anchors.centerIn: parent
        width: parent.width * 1.12; height: parent.height * 1.12
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        transform: [
            Translate { id: shift },
            Scale { id: zoom; origin.x: img.width / 2; origin.y: img.height / 2 }
        ]
        SequentialAnimation {
            running: true; loops: Animation.Infinite
            NumberAnimation { target: shift; property: "x"; from: -36; to: 36; duration: 41000; easing.type: Easing.InOutSine }
            NumberAnimation { target: shift; property: "x"; from: 36; to: -36; duration: 41000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: true; loops: Animation.Infinite
            NumberAnimation { target: shift; property: "y"; from: 24; to: -24; duration: 29000; easing.type: Easing.InOutSine }
            NumberAnimation { target: shift; property: "y"; from: -24; to: 24; duration: 29000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            running: true; loops: Animation.Infinite
            NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 1.0; to: 1.06; duration: 53000; easing.type: Easing.InOutSine }
            NumberAnimation { target: zoom; properties: "xScale,yScale"; from: 1.06; to: 1.0; duration: 53000; easing.type: Easing.InOutSine }
        }
    }

    Component {
        id: drift
        Item {
            Drifting { source: Config.wallpaper ? "file://" + Config.wallpaper : "" }
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.38 }
            ClockFace { visible: Config.s.screensaverClock; anchors.centerIn: parent; anchors.verticalCenterOffset: -parent.height * 0.06 }
        }
    }

    Component {
        id: slideshow
        Item {
            id: show
            // Two pictures: the next loads in the hidden one, then they cross-fade
            readonly property var list: root.pictures.length ? root.pictures : (Config.wallpaper ? [Config.wallpaper] : [])
            property int next: 0
            property bool onA: true
            function advance() {
                if (!list.length) return;
                const target = onA ? b : a;
                const src = "file://" + list[next % list.length];
                next++;
                if (target.source.toString() === src) { onA = !onA; return; }
                target.source = src;
            }
            Drifting { id: a; opacity: show.onA ? 1 : 0; Behavior on opacity { NumberAnimation { duration: Config.ms(1800); easing.type: Easing.InOutQuad } }
                onStatusChanged: if (status === Image.Ready && !show.onA) show.onA = true }
            Drifting { id: b; opacity: show.onA ? 0 : 1; Behavior on opacity { NumberAnimation { duration: Config.ms(1800); easing.type: Easing.InOutQuad } }
                onStatusChanged: if (status === Image.Ready && show.onA) show.onA = false }
            onListChanged: if (a.source.toString() === "" && list.length) { a.source = "file://" + list[0]; next = 1; }
            Component.onCompleted: if (list.length) { a.source = "file://" + list[0]; next = 1; }
            Timer { interval: Math.max(5, Config.s.screensaverSlideSeconds) * 1000; running: true; repeat: true; onTriggered: show.advance() }
            Rectangle { anchors.fill: parent; color: "black"; opacity: 0.25 }
            ClockFace { visible: Config.s.screensaverClock; anchors.centerIn: parent; anchors.verticalCenterOffset: -parent.height * 0.06 }
        }
    }

    Component {
        id: onBlack
        Item {
            id: blk
            // Somewhere new every minute, fading out and back in
            ClockFace {
                id: blkClock
                x: (blk.width - width) * blk.px
                y: (blk.height - height) * blk.py
                opacity: blk.lit ? 0.85 : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutQuad } }
            }
            property real px: 0.5
            property real py: 0.45
            property bool lit: true
            Timer {
                interval: 60000; running: true; repeat: true
                onTriggered: { blk.lit = false; moveLater.restart(); }
            }
            Timer {
                id: moveLater
                interval: 950
                onTriggered: { blk.px = 0.1 + Math.random() * 0.8; blk.py = 0.1 + Math.random() * 0.8; blk.lit = true; }
            }
        }
    }
}
