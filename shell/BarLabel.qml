// The small label just off the menu bar saying what the pointer's over: "Wi-Fi", "Clock", a
// tray app's name, which workspace a dot is. One per bar, in a window of its own along the
// bar's inner edge (the bar's window covers only the bar), which never takes the pointer or
// the keyboard.
//
// What it says comes from the bar: each thing's Reach (Bar.qml) has a `tip`, and the innermost
// one under the pointer with something to say is `bar.tipSource`. It shows after a short rest,
// at once when going straight from one thing to the next while one's showing (or just was),
// and fades through Config.ms. Never while a panel or menu from the bar is open, while the
// bar's being arranged or something's carried to it, or while the bar's hidden. A press on
// the bar puts it away quickly, and it stays away for that thing until the pointer leaves it
// and comes back.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: lw
    required property var bar

    // ---- What it says, and when ------------------------------------------------------------
    // The Reach the pointer's on that has something to say, and what that is (a dot's label
    // changes as the pointer goes from dot to dot within the one Reach)
    readonly property var source: bar.tipSource
    readonly property string sourceTip: source ? source.tip : ""
    readonly property var sourceAt: source ? (source.tipAt || source) : null
    readonly property bool held: Config.barArranging || bar.popoutsOpen || bar.menuOpen
        || Config.barCarry !== null || Config.barFloat !== null || bar.reveal < 0.99 || bar.movingOut
    // Showing (or fading in), and what it says and where
    property bool shown: false
    property string says: ""
    property point at: Qt.point(0, 0)           // the thing's centre at the bar's inner edge, on the screen
    // Put away by a press: not again for this until the pointer's left it
    property var blockedAt: null
    property string blockedTip: ""
    property int fadeMs: 140
    property var lastAt: null
    property string lastTip: ""

    onSourceAtChanged: update()
    onSourceTipChanged: update()
    onHeldChanged: update()
    function update() {
        const at = sourceAt, tip = sourceTip;
        // (the pointer's moved on from what was put away: it can show for that again)
        const moved = at !== lastAt || tip !== lastTip;
        if (moved) {
            if (at !== blockedAt || tip !== blockedTip) { blockedAt = null; blockedTip = ""; }
            lastAt = at; lastTip = tip;
        }
        const ok = !!at && tip !== "" && !held && !(at === blockedAt && tip === blockedTip);
        if (!ok) { rest.stop(); hide(120); return; }
        // Already showing, or only just put away: straight to the next one. Otherwise once the
        // pointer has rested on one thing
        if (shown || warm.running) show();
        else if (moved || !rest.running) rest.restart();
    }
    function show() {
        rest.stop(); warm.stop();
        if (!sourceAt || sourceTip === "" || held) return;
        at = bar.menuAnchor(sourceAt);
        says = sourceTip;
        fadeMs = 140;
        shown = true;
    }
    function hide(ms) {
        if (!shown) return;
        fadeMs = ms;
        shown = false;
        warm.restart();
    }
    // A press on the bar (anywhere on its things, any button, or the tests' pretend click): a
    // quick fade, and not back for this thing until the pointer leaves it and returns
    function dismiss() {
        rest.stop();
        blockedAt = sourceAt; blockedTip = sourceTip;
        if (shown) { fadeMs = 80; shown = false; }
        warm.stop();
    }
    Timer { id: rest; interval: 500; onTriggered: lw.show() }
    Timer { id: warm; interval: 400 }

    // ---- Window: a strip along the bar's inner edge -------------------------------------------
    readonly property string side: bar.side
    readonly property bool vert: side === "left" || side === "right"
    readonly property real gap: 6                     // off the bar's edge
    readonly property real room: 28                   // for the shadow round it
    readonly property real maxWidth: 260
    readonly property real ends: 8                    // kept this far in from the screen's ends
    screen: bar.screen
    anchors { top: side !== "bottom"; bottom: side !== "top"; left: side !== "right"; right: side !== "left" }
    margins {
        top: side === "top" ? bar.barHeight : 0
        bottom: side === "bottom" ? bar.barHeight : 0
        left: side === "left" ? bar.barHeight : 0
        right: side === "right" ? bar.barHeight : 0
    }
    implicitHeight: vert ? 0 : gap + box.height + room
    implicitWidth: vert ? gap + maxWidth + room : 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}                                   // never takes the pointer
    WlrLayershell.namespace: "slate-bar-label"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: shown || box.opacity > 0.001

    // ---- Look: a small capsule in the bar's colours ------------------------------------------
    // (the bar's capsule colour laid on its own surface colour, as one fill: glass shows through,
    // and Hyprland blurs behind it as behind the OSD)
    function over(t, b) {
        const a = t.a + b.a * (1 - t.a);
        if (a <= 0) return Qt.rgba(0, 0, 0, 0);
        const mix = (x, y) => (x * t.a + y * b.a * (1 - t.a)) / a;
        return Qt.rgba(mix(t.r, b.r), mix(t.g, b.g), mix(t.b, b.b), a);
    }
    Rectangle {
        id: box
        width: Math.min(lw.maxWidth, words.implicitWidth + 18)
        height: words.implicitHeight + 8
        x: !lw.vert ? Math.max(lw.ends, Math.min(lw.width - width - lw.ends, lw.at.x - width / 2))
            : lw.side === "left" ? lw.gap : lw.width - lw.gap - width
        y: lw.vert ? Math.max(lw.ends, Math.min(lw.height - height - lw.ends, lw.at.y - height / 2))
            : lw.side === "top" ? lw.gap : lw.height - lw.gap - height
        radius: Config.corner(lw.bar.capsuleRadius)
        color: lw.over(lw.bar.capsuleColor, lw.bar.barColor)
        opacity: lw.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(lw.fadeMs); easing.type: Easing.OutCubic } }
        Shadow {}                                     // raised: Slate's shadow
        Text {
            id: words
            anchors.centerIn: parent
            width: Math.min(implicitWidth, lw.maxWidth - 18)
            elide: Text.ElideRight
            text: lw.says
            color: lw.bar.textColor
            font.family: lw.bar.fontFamily
            font.pixelSize: 12
            font.weight: Font.Normal
        }
    }

    // (tests) Where it is on its screen, what it says, and whether it's showing
    readonly property var testState: {
        const sw = screen ? screen.width : 0, sh = screen ? screen.height : 0;
        const ox = side === "right" ? sw - bar.barHeight - width : side === "left" ? bar.barHeight : 0;
        const oy = side === "bottom" ? sh - bar.barHeight - height : side === "top" ? bar.barHeight : 0;
        return { shown: shown, text: says, opacity: box.opacity, visible: visible,
                 x: Math.round(ox + box.x), y: Math.round(oy + box.y), w: Math.round(box.width), h: Math.round(box.height) };
    }
}
