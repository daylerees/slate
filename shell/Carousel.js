.pragma library
// What the window switcher and the workspace overview work out the same way for their strips.

// How many times the strip's items are repeated round the loop: enough to fill `filled` pixels
// (cards `slotW` wide), and for the fancier movement styles far enough round that the strip's
// ends are never seen. A single item isn't repeated.
function reps(count, filled, slotW, moveAnim) {
    if (count < 2) return 1;
    return Math.max(1, Math.ceil(filled / (count * slotW)),
                    Math.ceil(({ tilt: 9, orbit: 10, deck: 6, fan: 12 })[moveAnim] / count) || 1);
}

// The live capture (an item of the repeater that draws them) whose `prop` is `key`.
// (count: re-run as they're made)
function shotFor(repeater, prop, key) {
    for (let i = 0; i < repeater.count; i++) {
        const it = repeater.itemAt(i);
        if (it && it[prop] === key) return it;
    }
    return null;
}

// How many of the live captures have a picture yet (the test IPC's state)
function previewsReady(repeater) {
    let n = 0;
    for (let i = 0; i < repeater.count; i++) {
        const it = repeater.itemAt(i);
        if (it && it.hasContent) n++;
    }
    return n;
}
