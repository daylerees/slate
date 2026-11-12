// A row of workspace dots with the accent marker gliding over the one in use: on the menu bar,
// under the window switcher, in the overview and on Super+Left/Right's on-screen display.
//
// At most `maxVisible` dots show (6 on the bar, 10 elsewhere). With more workspaces than that,
// the row scrolls smoothly to hold the one in use in the middle until it reaches either end
// (then the marker moves on to the end dots), and at an end with more beyond it the dots
// shrink and fade away, the last one smallest, like a phone's page dots: so you can see
// there's more that way. Round
// dots or square ones alike (Config.dotRadius), and down a side bar (`vertical`).
//
//   WorkspaceDots { spaces: …; activeIndex: …; dot: 14; gap: 5; maxVisible: 6; accent: … }
//   marker: the WorkspaceMarker, for a caller that moves it itself (the OSD's prime())

import QtQuick

Item {
    id: wd
    property var spaces: []                 // the workspaces, in order
    property int activeIndex: 0             // the one the marker sits on
    property real dot: 14
    property real gap: 5
    property int maxVisible: 6
    property bool vertical: false
    property color accent: Config.accent
    property bool animate: true             // the marker's glide and the scroll (else they jump)
    property bool markerAnimate: animate    // the marker's own glide when activeIndex changes
    property bool markerFollows: true       // false: the caller moves the marker itself (marker.go)
    // Each dot's look: occupied (has windows) or empty
    property var occupied: ws => (ws && ws.toplevels && ws.toplevels.values ? ws.toplevels.values.length : 0) > 0
    // On the bar: a hover highlight behind each dot, and a click to go there
    property bool interactive: false
    property color hoverFill: "transparent"
    property real hoverStrength: 1
    readonly property alias marker: mk

    readonly property real step: dot + gap
    readonly property int count: spaces ? spaces.length : 0
    readonly property int shown: Math.max(1, Math.min(count, maxVisible))
    readonly property bool overflows: count > maxVisible
    readonly property real span: Math.max(dot, shown * step - gap)
    width: vertical ? dot : span
    height: vertical ? span : dot

    // ---- Scrolling: the first dot in view (a whole number to aim for; `first` glides to it) --
    // The one in use is held in the middle, the row scrolling past it, until the row reaches
    // either end: then the row stops and the marker carries on to the end dots
    property int firstWanted: 0
    function aim() {
        if (!overflows) { firstWanted = 0; return; }
        const f = activeIndex - Math.floor((shown - 1) / 2);
        firstWanted = Math.max(0, Math.min(count - shown, f));
    }
    onActiveIndexChanged: aim()
    onCountChanged: aim()
    onMaxVisibleChanged: aim()
    // (bound, never set: setting it would cut it loose from firstWanted, and the row would stop
    // following the workspace in use. No glide as it first appears, only once it's shown)
    property bool settled: false
    Component.onCompleted: { aim(); settled = true; }
    property real first: firstWanted
    Behavior on first {
        enabled: wd.settled && wd.animate && Config.animate
        NumberAnimation { duration: Config.ms(380); easing.type: Easing.OutCubic }
    }

    // How much there is beyond each end (0 … 1, so the shrinking eases in and out as it scrolls)
    readonly property real moreBefore: Math.max(0, Math.min(1, first))
    readonly property real moreAfter: Math.max(0, Math.min(1, count - shown - first))
    // A dot's size at a distance from an end (in dots, from its centre): the end one about half,
    // the next four fifths, then full; weighed by how much there is beyond that end
    function fade(e) {
        const t = Math.max(0, Math.min(1, e / 2.4));
        return 0.42 + 0.58 * t * t * (3 - 2 * t);
    }
    function sizeAt(r) {
        const before = 1 - moreBefore * (1 - fade(r + 0.5));
        const after = 1 - moreAfter * (1 - fade(shown - 0.5 - r));
        return Math.min(before, after);
    }
    // ...and whether it's in view at all: fading out over its last slot past either end
    function inView(r) { return Math.max(0, Math.min(1, Math.min(r + 1, shown - r))); }

    // ---- The dots ------------------------------------------------------------------------
    Repeater {
        model: wd.spaces
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property real r: index - wd.first               // its place in view, in dots
            readonly property real along: r * wd.step
            readonly property real size: wd.sizeAt(r)
            readonly property real seen: wd.inView(r)
            readonly property bool full: wd.occupied(modelData)
            x: wd.vertical ? 0 : along
            y: wd.vertical ? along : 0
            width: wd.dot; height: wd.dot
            visible: seen > 0.01
            opacity: seen * Math.min(1, 0.25 + 0.75 * (size - 0.42) / 0.58)
            // Hover: the status icons' highlight, in the dot's shape, behind it (the bar)
            Rectangle {
                visible: wd.interactive
                anchors.centerIn: parent
                readonly property real s: wd.dot + 10
                width: s; height: s
                radius: Config.dotRadius(s)
                color: wd.hoverFill
                opacity: dotHover.hovered ? wd.hoverStrength : 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
            }
            Rectangle {
                anchors.centerIn: parent
                width: wd.dot; height: wd.dot
                radius: Config.dotRadius(wd.dot)
                scale: cell.size
                // Inactive workspaces dimmed a little (the marker shows the one in use);
                // brighter under the pointer
                color: dotHover.hovered ? (cell.full ? Config.tint("#eef1f5") : Config.tint("#8b94a3"))
                    : cell.full ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                Behavior on color { ColorAnimation { duration: Config.ms(150) } }
            }
            HoverHandler { id: dotHover; enabled: wd.interactive }
            ClickArea {
                anchors.fill: parent
                enabled: wd.interactive && cell.seen > 0.5
                onClicked: cell.modelData.activate()
            }
        }
    }

    // ---- The accent marker, over the dots and scrolling with them ---------------------------
    Item {
        x: wd.vertical ? 0 : -wd.first * wd.step
        y: wd.vertical ? -wd.first * wd.step : 0
        width: wd.vertical ? wd.dot : Math.max(wd.dot, wd.count * wd.step - wd.gap)
        height: wd.vertical ? Math.max(wd.dot, wd.count * wd.step - wd.gap) : wd.dot
        WorkspaceMarker {
            id: mk
            anchors.fill: parent
            dot: wd.dot; step: wd.step
            index: wd.markerFollows ? wd.activeIndex : 0
            vertical: wd.vertical
            animate: wd.markerAnimate
            color: wd.accent
        }
    }
}
