// The accent marker on a row of workspace dots (bar, switcher, overview, on-screen
// display). Switching makes it glide to the new workspace: it leaves quickly and eases
// in to rest, dipping slightly in size on the way, with a faint echo trailing behind
// that catches up and fades. Lay it over the row of dots (same position and size); set
// `index` to the active dot and it moves there.

import QtQuick

Item {
    id: m
    property real dot: 14
    property real step: dot + 5            // dot plus the gap to the next one
    property int index: 0
    property bool vertical: false          // a column of dots (a side bar)
    property bool animate: true            // false: moves straight there
    property color color: "white"

    // ---- The glide: p runs 0 → 1 (linear in time); positions follow eased curves of it
    property real from: index * step
    property real to: index * step
    property real p: 1
    readonly property real lead: 1 - Math.pow(1 - p, 5)      // the marker: fast out, long soft landing
    readonly property real trail: 1 - Math.pow(1 - p, 2.2)    // the echo: a little behind
    readonly property real along: from + (to - from) * lead
    readonly property real trailAlong: from + (to - from) * trail
    // Slightly smaller while moving fast; full size at rest
    readonly property real size: dot * (1 - 0.18 * Math.sin(Math.PI * lead) * Math.min(1, Math.abs(to - from) / step))

    // Go to dot i: a glide, or straight there
    function go(i, animated) {
        const target = i * step;
        if (!animated) { jump(i); return; }
        if (target === to && p === 1) return;
        const cur = along;
        glide.stop();
        from = cur; to = target; p = 0;
        glide.duration = 380 + Math.min(Math.abs(target - cur) / step, 6) * 30;
        glide.start();
    }
    function jump(i) {
        glide.stop();
        from = i * step; to = i * step; p = 1;
    }
    onIndexChanged: go(index, animate)
    onStepChanged: jump(index)

    NumberAnimation { id: glide; target: m; property: "p"; from: 0; to: 1 }

    // The echo (fading as it catches up), then the marker itself
    Repeater {
        model: 2
        delegate: Rectangle {
            required property int index
            readonly property bool echo: index === 0
            readonly property real pos: echo ? m.trailAlong : m.along
            readonly property real across: (m.dot - m.size) / 2
            width: m.size; height: m.size
            x: m.vertical ? across : pos + across
            y: m.vertical ? pos + across : across
            radius: Config.dotRadius(m.size)
            color: m.color
            opacity: echo ? 0.35 * (1 - m.p) : 1
            visible: opacity > 0.01
        }
    }
}
