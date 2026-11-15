// Smooth wheel and touchpad scrolling for a Flickable/ListView (Qt's own is stiff and steppy).
//  - Mouse wheel: each notch sets where the list is heading and it eases there: a quarter of
//    what shows (100 to 240 px, so a tall page doesn't crawl beside a touchpad), and
//    quick notches go further.
//  - Touchpad: follows the fingers closely, then glides on when they lift, slowing gradually.
// The list is moved once per drawn frame, easing towards where it's heading, so uneven input
// (a touchpad reports at its own rate, not the screen's) comes out as even motion. Anything
// else that moves the list (keys, the scrollbar, a drag) takes over at once.
// Use inside the list:  SmoothWheel { flick: myList }
// A list that scrolls sideways: SmoothWheel { flick: myRow; horizontal: true } (the wheel, or a
// touchpad's sideways or up/down swipe, moves it left and right)

import QtQuick

WheelHandler {
    id: wh
    required property Flickable flick
    property bool horizontal: false
    // How far one mouse-wheel notch goes (px): a quarter of the view, 100 px at least (a small
    // menu still moves a few rows) and 240 at most. (Once 110 px everywhere, which felt slow
    // beside a touchpad on a tall page.) Hyprland has no mouse scroll speed of its own to follow
    // (input:scroll_factor reaches us already, in angleDelta); touchpads' (Settings → Input →
    // Touchpad → Scroll speed) comes in the same way, in pixelDelta.
    property real notch: Math.max(100, Math.min(240, (horizontal ? flick.width : flick.height) * 0.25))
    property real burstGap: 120          // ms: notches closer than this are a quick spin…
    property real burstGrowth: 1.3       // …each whole notch going this much further than the last…
    property real burstMax: 3.5          // …up to this many notches' worth
    property real touchpadSpeed: 1.6     // the list moves this many times as far as the fingers
    property real wheelEase: 0.075       // seconds: how softly a notch eases in (time constant)
    property real fingerEase: 0.022      // seconds: touchpad, just evens out its reports
    property real glide: 0.33            // seconds: how long the glide lasts after the fingers lift
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    target: null

    // Dragging the list (touch screens, or the mouse) still flings the usual way
    Component.onCompleted: {
        flick.flickDeceleration = 2600;
        flick.maximumFlickVelocity = 12000;
    }

    readonly property real minY: horizontal ? flick.originX : flick.originY
    readonly property real maxY: horizontal ? flick.originX + Math.max(0, flick.contentWidth - flick.width)
                                            : flick.originY + Math.max(0, flick.contentHeight - flick.height)
    // Where the list is along the way it scrolls
    function at() { return horizontal ? flick.contentX : flick.contentY; }
    function moveTo(v) { if (horizontal) flick.contentX = v; else flick.contentY = v; }
    // A wheel event's movement along it (sideways lists take either direction)
    function along(d) { return horizontal ? (d.x !== 0 ? d.x : d.y) : d.y; }
    function clamp(y) { return Math.max(minY, Math.min(maxY, y)); }

    property real goal: 0          // where the list is heading
    property real pos: 0           // where it is (exactly; what was last given to contentY)
    property real velocity: 0      // touchpad: the fingers' speed, then the glide's (px/s, + = down)
    property bool fingers: false   // a touchpad scroll is going on
    property bool gliding: false
    property real lastEvent: 0
    property real lastNotch: 0
    property real burst: 1         // quick notches build up to going further
    property real spun: 0          // how far this quick spin has turned (angleDelta, one way)

    // Start from where the list is, unless this is carrying on from our own movement
    function sync() {
        if (anim.running && Math.abs(at() - pos) < 1) return;
        pos = goal = at();
        velocity = 0;
        gliding = false;
    }

    onWheel: e => {
        e.accepted = true;
        const now = Date.now();
        // Fingers lifted (sent on its own, with no movement)
        const pd = along(e.pixelDelta), ad = along(e.angleDelta);
        if (e.phase === Qt.ScrollEnd && pd === 0 && ad === 0) {
            if (fingers) release();
            return;
        }
        sync();
        if (flick.flicking) flick.cancelFlick();
        if (pd !== 0) {
            // Touchpad: head where the fingers say, and keep track of their speed
            const step = -pd * touchpadSpeed;
            const dt = now - lastEvent;
            const inst = step / Math.max(4, dt) * 1000;
            velocity = !fingers || dt > 100 ? inst : 0.55 * inst + 0.45 * velocity;
            lastEvent = now;
            fingers = true;
            gliding = false;
            goal = clamp(goal + step);
            if (e.phase === Qt.ScrollEnd) release();
            else if (e.phase === Qt.NoScrollPhase) lift.restart();   // no end reported: a pause counts
        } else if (ad !== 0) {
            wheelBy(ad, now);
            return;
        }
        anim.start();
    }

    // Mouse wheel: each notch (120 of angleDelta; a high-resolution wheel sends parts of one)
    // moves where it's heading. (Tests call it too, as a wheel would: the test IPC's wheel.)
    function wheelBy(ad, now) {
        if (now === undefined) { now = Date.now(); sync(); if (flick.flicking) flick.cancelFlick(); }
        // (counted in whole notches, so a high-resolution wheel's parts of one don't build it up;
        // turning back starts again)
        if (now - lastNotch >= burstGap || (spun !== 0 && Math.sign(ad) !== Math.sign(spun))) spun = 0;
        burst = Math.min(burstMax, Math.pow(burstGrowth, Math.floor(Math.abs(spun) / 120)));
        spun += ad;
        lastNotch = now;
        fingers = gliding = false;
        velocity = 0;
        goal = clamp(goal - ad / 120 * notch * burst);
        anim.start();
    }

    // The fingers lifted: glide on at their speed (if they were still moving), slowing down
    function release() {
        lift.stop();
        fingers = false;
        gliding = Date.now() - lastEvent < 90 && Math.abs(velocity) > 120;
        if (!gliding) velocity = 0;
        anim.start();
    }
    property Timer lift: Timer { interval: 120; onTriggered: if (wh.fingers) wh.release() }

    property FrameAnimation anim: FrameAnimation {
        onTriggered: {
            // Touchpad events stopped without the fingers' lift being reported (the list hid
            // mid-scroll, say): a second of nothing counts as lifted, so this doesn't tick forever
            if (wh.fingers && Date.now() - wh.lastEvent > 1000) wh.release();
            // Moved by something else (keys, the scrollbar, a drag): let it
            if (Math.abs(wh.at() - wh.pos) > 1 || wh.flick.dragging) { stop(); wh.gliding = false; wh.velocity = 0; return; }
            const dt = Math.min(0.05, Math.max(0.001, frameTime));
            if (wh.gliding) {
                wh.goal = wh.clamp(wh.goal + wh.velocity * dt);
                wh.velocity *= Math.exp(-dt / wh.glide);
                if (Math.abs(wh.velocity) < 12 || wh.goal <= wh.minY || wh.goal >= wh.maxY) { wh.gliding = false; wh.velocity = 0; }
            }
            const ease = wh.fingers || wh.gliding ? wh.fingerEase : wh.wheelEase;
            wh.pos += (wh.goal - wh.pos) * (1 - Math.exp(-dt / ease));
            if (!wh.gliding && !wh.fingers && Math.abs(wh.goal - wh.pos) < 0.25) { wh.pos = wh.goal; stop(); }
            wh.moveTo(wh.pos);
            wh.pos = wh.at();                // as the list took it
        }
    }
}
