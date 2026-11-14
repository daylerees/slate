import QtQuick

// How one card of the switcher's or the overview's strip moves for each of the movement styles
// (Settings → Windows / Workspaces): hop, tilt, orbit, deck and fan. The maths is the same in
// both windows and only the distances differ, so they're given (the lifts below). A card reads
// the results into its own scale, opacity and transform:
//   scale, opacity, tiltAngle, fanAngle, shiftX, shiftY, plus fanPivot (for the fan's Rotation)
// `moving` false (the overview's lifted or swapping card) leaves the card as it is.
QtObject {
    id: m
    property string fx: "slide"
    property real side: 0                // pixels along the strip from the middle
    property real slotW: 1               // one card's share of the strip
    property real cardW: 1
    property real cardHeight: 1          // the card's own height (the fan's pivot is below it)
    property real orbitR: 0
    property real offset: 0              // the PathView's offset, for the hop
    property bool moving: true
    // How far each style lifts or spreads the cards, in pixels
    property real hopLift: 26
    property real orbitLift: 45
    property real deckX: 26
    property real deckYAhead: 16
    property real deckYBehind: 10
    property real fanLift: 22

    readonly property real t: side / slotW
    // Hop: every card rises and falls once for each step the strip moves
    readonly property real hop: fx === "hop" ? Math.sin(Math.PI * Math.abs(offset - Math.round(offset))) : 0
    // Tilt: the others turned away, packed closer the further out they are, and fading out
    // before the strip's ends
    readonly property bool tilted: fx === "tilt" && moving
    readonly property real packed: Math.sign(t) * (Math.min(Math.abs(t), 1) * 0.7 + Math.max(Math.abs(t) - 1, 0) * 0.28) * slotW
    // Orbit: round a flat ring seen from above the front, the far side small, dim and higher
    readonly property real th: t * 0.7
    // Fan: turned about a point well below, like a hand of cards; the chosen one lifted
    readonly property real fanPivot: cardHeight + cardHeight * 2.2
    readonly property real fanStep: (cardW * 0.45 / fanPivot) * 180 / Math.PI

    readonly property real scale: !moving ? 1 : fx === "orbit" ? 0.45 + 0.55 * (Math.cos(th) + 1) / 2
        : fx === "deck" && t > 0 ? Math.max(0.5, 1 - 0.07 * t) : 1
    readonly property real opacity: !moving ? 1
        : tilted ? Math.max(0, Math.min(1, 3.2 - Math.abs(t)))
        // (orbit: the far side dim, and gone before the strip's ends meet behind)
        : fx === "orbit" ? (0.35 + 0.65 * (Math.cos(th) + 1) / 2) * Math.max(0, Math.min(1, (Math.PI - Math.abs(th)) * 1.5))
        // (deck: the cards dealt away fade as they go; the pile shows four deep)
        : fx === "deck" ? (t < 0 ? Math.max(0, 1 + t * 1.2) : Math.max(0, Math.min(1, 4.5 - t)))
        : fx === "fan" ? Math.max(0, Math.min(1, 5.5 - Math.abs(t))) : 1
    readonly property real tiltAngle: tilted ? -Math.max(-1, Math.min(1, t)) * 55 : 0
    readonly property real fanAngle: fx === "fan" && moving ? t * fanStep : 0
    readonly property real shiftX: !moving ? 0 : tilted ? packed - side
        : fx === "orbit" ? orbitR * Math.sin(th) - side
        : fx === "deck" ? (t > 0 ? t * deckX - side : side * 0.6)
        : fx === "fan" ? -side : 0
    readonly property real shiftY: -hop * hopLift - (!moving ? 0
        : fx === "orbit" ? (1 - Math.cos(th)) * orbitLift
        : fx === "deck" ? (t > 0 ? t * deckYAhead : t * deckYBehind)
        : fx === "fan" ? fanLift * Math.max(0, 1 - Math.abs(t)) : 0)
}
