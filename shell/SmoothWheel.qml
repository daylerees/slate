// Wheel and touchpad scrolling with momentum for a Flickable/ListView (Qt's
// default is slow and stiff).
//  - Mouse wheel: each notch pushes the list; quick notches build up speed, and
//    it slides to a stop.
//  - Touchpad: follows the fingers, then keeps gliding when they lift, slowing
//    down gradually.
// Use inside the list:  SmoothWheel { flick: myList }

import QtQuick

WheelHandler {
    id: wh
    required property Flickable flick
    property real notch: 120             // roughly how far one mouse-wheel notch travels (px)
    property real deceleration: 2600     // how quickly the slide slows (px/s²); lower = longer glide
    property real touchpadSpeed: 2.2     // list moves this many times as far as the fingers
    property real touchpadGlide: 1.6     // extra push given to the slide when the fingers lift
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null

    Component.onCompleted: {
        flick.flickDeceleration = deceleration;
        flick.maximumFlickVelocity = 12000;
    }

    readonly property real minY: flick.originY
    readonly property real maxY: flick.originY + Math.max(0, flick.contentHeight - flick.height)
    function clamp(y) { return Math.max(minY, Math.min(maxY, y)); }

    // Touchpad speed, smoothed over the last few events (px/s; + = towards the top)
    property real velocity: 0
    property real lastTime: 0

    onWheel: e => {
        e.accepted = true;
        const now = Date.now();
        if (e.pixelDelta.y !== 0) {
            // Touchpad: move with the fingers and measure their speed
            if (flick.flicking) flick.cancelFlick();
            const dt = Math.max(1, now - lastTime);
            const step = e.pixelDelta.y * touchpadSpeed;
            const inst = step / dt * 1000;
            velocity = dt > 80 ? inst : 0.6 * inst + 0.4 * velocity;
            lastTime = now;
            flick.contentY = clamp(flick.contentY - step);
            if (e.phase === Qt.ScrollEnd) release();
            else lift.restart();            // no "fingers lifted" signal: treat a pause as one
        } else if (e.angleDelta.y !== 0) {
            // Mouse wheel: push in the notch's direction, adding to any slide already going.
            // Speed that travels `notch` px before stopping: v = sqrt(2 * a * d)
            const push = Math.sqrt(2 * deceleration * notch) * (e.angleDelta.y / 120);
            const current = flick.flicking ? -flick.verticalVelocity : 0;
            const sameWay = current * push > 0;
            flick.flick(0, (sameWay ? current : 0) + push);
        }
    }

    function release() {
        lift.stop();
        if (Math.abs(velocity) > 200) flick.flick(0, velocity * touchpadGlide);
        velocity = 0;
    }
    property Timer lift: Timer { interval: 60; onTriggered: wh.release() }
}
