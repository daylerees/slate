// The slim scrollbar used across Slate (launcher, picker, notifications, Settings): a faint
// rounded track with a rounded thumb in the accent colour, shown only when the view overflows. Hover widens the
// thumb; drag it, or click the track, to scroll.
//   ThinScrollbar { flick: myList; color: theme text colour; anchors { top: …; bottom: …; right: … } }
// It's 10 px wide in the layout, the track and thumb centred in that, and can be grabbed a
// little beyond it (reach: 4 px each side, 18 px in all), in the gap views leave beside it.
// That wider strip only takes presses and drags (and hover, to show the bar); a wheel over it
// still scrolls the list.
// Views give it room only while it shows: when everything fits, rows use the full width
// and an 8 px gap before it (e.g. rightMargin: flick.contentHeight <= flick.height ? 14 : 28,
// scrollbar leftMargin: 8; or content width - 18 with the scrollbar at the right edge).

import QtQuick

Item {
    id: sb
    required property Flickable flick
    property color color: "#eef1f5"

    visible: !!flick && flick.contentHeight > flick.height
    width: 10
    readonly property real range: flick ? flick.contentHeight - flick.height : 0
    readonly property bool active: hover.hovered || drag.pressed
    property real reach: 4              // how far past each side it can still be grabbed (px)

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 3; height: parent.height
        radius: Config.corner(width / 2)
        color: sb.color; opacity: 0.08
    }
    Rectangle {
        id: thumb
        anchors.horizontalCenter: parent.horizontalCenter
        width: sb.active ? 6 : 4
        radius: Config.corner(width / 2)
        // The handle in the accent colour (the track behind it stays the faint neutral)
        color: Config.accent
        opacity: sb.active ? 1 : 0.7
        height: Math.max(24, sb.height * (sb.flick ? sb.flick.visibleArea.heightRatio : 1))
        y: sb.range > 0 ? (sb.height - height) * Math.max(0, Math.min(1, (sb.flick.contentY - sb.flick.originY) / sb.range)) : 0
        Behavior on width { NumberAnimation { duration: Config.ms(100) } }
        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
    }
    MouseArea {
        id: drag
        property bool keyboardExempt: true      // (a drag: the keyboard scrolls the page itself)
        anchors { fill: parent; leftMargin: -sb.reach; rightMargin: -sb.reach }
        HoverHandler { id: hover }
        preventStealing: true           // keep the drag once started, even if the pointer drifts off
        property real grab: 0           // where on the thumb it was picked up
        function scrollTo(my) {
            const travel = sb.height - thumb.height;
            if (travel <= 0) return;
            sb.flick.contentY = sb.flick.originY + Math.max(0, Math.min(sb.range, (my - grab) / travel * sb.range));
        }
        onPressed: m => {
            // On the thumb: keep the grab point; on the track: centre the thumb there
            grab = (m.y >= thumb.y && m.y <= thumb.y + thumb.height) ? m.y - thumb.y : thumb.height / 2;
            scrollTo(m.y);
        }
        onPositionChanged: m => { if (pressed) scrollTo(m.y); }
    }
}
