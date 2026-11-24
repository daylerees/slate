// Accessibility → Trailing pointer: a short trail of fading dots behind the pointer as it moves,
// to keep track of it. Never takes a click; off in game mode.
//
// Hyprland has no event for the pointer moving, so while it's on (and only then) Slate asks
// where the pointer is about 60 times a second, over Hyprland's own socket (no process each
// time). Positions are Hyprland's pixels, made Slate's on their screen by Config.screenPoint.
// The window is only there while there's a trail to draw: a still pointer leaves nothing.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    readonly property bool on: Config.s.pointerTrail && !Config.gameMode && !Config.isLoginScreen
    readonly property int count: 12         // dots in a full trail
    readonly property int life: 260         // ms a dot lasts
    property var target: null               // the screen the pointer is on
    property var dots: []                   // [{x, y, t}], newest last, in Slate's units on target
    property real now: 0
    property string last: ""
    property int moves: 0                   // (the tests: positions taken that moved it)

    function heard(data) {
        const m = /"x"\s*:\s*(-?[\d.]+)[\s\S]*"y"\s*:\s*(-?[\d.]+)/.exec(data);
        if (!m) return;
        const key = m[1] + "," + m[2];
        if (key === last) return;
        last = key;
        const p = Config.screenPoint(+m[1], +m[2]);
        if (!p) return;
        if (p.screen !== target) { target = p.screen; dots = []; }
        moves++;
        dots = dots.concat([{ x: p.x, y: p.y, t: Date.now() }]).slice(-count);
    }

    Socket {
        id: ask
        // (Hyprland's request socket, in the runtime folder: Hyprland needs $XDG_RUNTIME_DIR)
        path: Config.runtimeDir + "/hypr/" + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") + "/.socket.sock"
        onConnectedChanged: if (connected) { write("j/cursorpos"); flush(); }
        // (Hyprland's answer, {"x": …, "y": …}, ends with its "}" and no new line; closed from
        // this end once read, before Hyprland closes it, which would log a warning each time)
        parser: SplitParser {
            splitMarker: "}"
            onRead: data => { ask.connected = false; root.heard(data); }
        }
    }
    // (the input that makes it worth running: the setting, on, outside game mode)
    Timer {
        running: root.on
        interval: 16
        repeat: true
        onTriggered: {
            root.now = Date.now();
            if (root.dots.length && root.now - root.dots[0].t > root.life)
                root.dots = root.dots.filter(d => root.now - d.t <= root.life);
            if (!ask.connected) ask.connected = true;
        }
    }
    onOnChanged: if (!on) { dots = []; ask.connected = false; }

    LazyLoader {
        active: root.on && root.dots.length > 1 && !!root.target
        PanelWindow {
            screen: root.target
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "slate-pointer-trail"
            mask: Region {}                 // never takes the pointer
            // (a fixed set of dots, each reading its own place in the trail: the newest is
            // where the pointer is, so it's left out, under the pointer itself)
            Repeater {
                model: root.count
                delegate: Rectangle {
                    required property int index
                    readonly property var d: index < root.dots.length - 1 ? root.dots[index] : null
                    readonly property real age: d ? Math.min(1, (root.now - d.t) / root.life) : 1
                    visible: !!d && age < 1
                    width: 4 + 8 * (1 - age); height: width
                    radius: width / 2
                    x: d ? d.x - width / 2 : 0; y: d ? d.y - width / 2 : 0
                    color: Config.accent
                    border.width: 1
                    border.color: Config.palette.accentText
                    opacity: 0.85 * (1 - age)
                }
            }
        }
    }
}
