// A glossy sheen for glass (Settings → Appearance → Glass → Gloss): light catching the top of
// a shape, fading out towards its middle, with a faint bright line along the top edge. Put it
// inside a rounded shape, over its fill and under its contents:
//   Gloss { radius: parent.radius }
// It only shows with glass on (and Gloss switched on).

import QtQuick
import QtQuick.Effects

Rectangle {
    id: g
    property real strength: 1
    // Take the wallpaper's colour hint as on glass, for a shape whose fill isn't its parent's
    // colour (an app icon's tile)
    property bool glassHint: false
    anchors.fill: parent
    // Present whenever gloss is on (faded out at 0 opacity when not shown, which Qt skips
    // drawing), so its effect isn't rebuilt each time it shows
    visible: Config.glassGloss
    color: "transparent"
    // Hover highlights set opacity to show it while pointed at: it fades in and out in step
    // with their colour (appearing at once, the top half showed before the rest)
    Behavior on opacity { NumberAnimation { duration: 100 } }
    // Stronger on light colours (an accent-filled selection), where a faint white sheen
    // barely shows; as it is on dark ones
    readonly property real boost: {
        const c = parent ? parent.color : undefined;
        if (c === undefined || c.a < 0.5) return 1;
        return 1 + 6 * Math.max(0, c.hslLightness - 0.4);
    }
    readonly property real a: Math.min(0.85, (Config.s.lightMode ? 0.35 : 0.13) * strength * Config.glossAmount * boost * tinted * (onFill ? 2 : 1))
    // A coloured sheen is a little stronger, so its colour shows rather than reading as grey
    readonly property real tinted: hintAmount > 0 ? 1.35 : 1
    // The sheen's colour: light, with a hint of what it's on. A coloured fill (an accent-filled
    // selection, a space's colour) lends its colour; on see-through glass, the wallpaper's
    // overall colour (the scene showing through); otherwise plain white
    readonly property color hint: {
        const c = parent ? parent.color : undefined;
        if (c !== undefined && c.a >= 0.5 && c.hslSaturation > 0.2) return c;
        if (glassHint || (c !== undefined && c.a < 0.95)) {
            // The wallpaper's vivid colour (the one an accent from the wallpaper uses); its
            // overall tone averages the whole picture and came out too grey
            const t = Config.wallpaperAccent || Config.wallpaperTone;
            if (t) return Qt.color(t);
        }
        return "white";
    }
    // Settings → Glass → Gloss colour. On a coloured fill at most 40% of it, so the sheen stays
    // a lighter tint of the fill (at full strength it was the fill's own colour, and vanished)
    readonly property bool onFill: { const c = parent ? parent.color : undefined; return !glassHint && c !== undefined && c.a >= 0.5 && c.hslSaturation > 0.2; }
    // Light frosted glass (light mode, not on a coloured fill): the sheen stays close to white,
    // since a sheen in the wallpaper's colour vanished into the tinted surface beneath it
    readonly property bool lightFrost: Config.s.lightMode && !onFill
    readonly property real hintAmount: hint.hslSaturation > 0.05 ? Config.glossTint * (onFill ? 0.4 : lightFrost ? 0.25 : 1) : 0
    readonly property color sheen: Qt.rgba(1 - hintAmount + hint.r * hintAmount, 1 - hintAmount + hint.g * hintAmount,
                                           1 - hintAmount + hint.b * hintAmount, 1)
    // Taller than a bar capsule (a quick toggle, say): the shine and shade there are softer and
    // blend smoothly into each other, rather than the short shapes' crisper bands
    readonly property bool tall: height > 32
    gradient: Gradient {
        // Tall shapes: a gentler shine fading smoothly over the top half, with no band edge (a
        // bright band, a flat middle and a dark band made them look like three-tone tubes)
        GradientStop { position: 0.0; color: Qt.rgba(g.sheen.r, g.sheen.g, g.sheen.b, g.a * (g.tall ? 0.75 : 1)) }
        GradientStop { position: g.tall ? 0.18 : 0.5; color: Qt.rgba(g.sheen.r, g.sheen.g, g.sheen.b, g.a * (g.tall ? 0.3 : 0.25)) }
        GradientStop { position: g.tall ? 0.5 : 0.55; color: "transparent" }
        GradientStop { position: 1.0; color: "transparent" }
    }
    // On a coloured fill, a soft shade along the bottom too: with the shine on top it reads as a
    // rounded, glossy surface rather than a flat one (Gloss sets how strong). Light frosted glass
    // gets a fainter one, for the same depth
    Rectangle {
        anchors.fill: parent
        radius: g.radius
        visible: g.onFill || g.lightFrost
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            // Tall shapes: from just past the middle, and softer, to meet the shine with no flat band
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, (g.tall ? 0.7 : 1) * (g.onFill ? Math.min(0.35, 0.3 * Config.glossAmount) : Math.min(0.14, 0.18 * Config.glossAmount))) }
        }
    }
    // The bright edge: the shape's own rounded outline, so it bends around the top corners,
    // fading out a little way down the sides
    Item {
        anchors.fill: parent
        // Set up once (while gloss is on), not each time the gloss shows: on hover-only gloss
        // that rebuilt the effect every time the pointer crossed an item, and moving the mouse
        // over a row of them was choppy
        layer.enabled: Config.glassGloss
        layer.effect: MultiEffect { maskEnabled: true; maskSource: rimFade; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        Rectangle {
            anchors.fill: parent
            radius: g.radius
            color: "transparent"
            border.width: 1
            // Light mode: the outermost line is a darker one, so the shape's top edge is defined
            // rather than its sheen running off into the light background (the bright line
            // moves just inside it)
            // (faint on frosted glass, a little stronger on coloured fills)
            border.color: Config.s.lightMode ? Qt.rgba(0, 0, 0, g.onFill ? Math.min(0.13, 0.15 * Config.glossAmount) : Math.min(0.055, 0.07 * Config.glossAmount))
                // Crisper on light frosted glass, where a faint white edge didn't show
                : Qt.rgba(g.sheen.r, g.sheen.g, g.sheen.b, Math.min(1, g.a * 1.6))
        }
        Rectangle {
            visible: Config.s.lightMode
            anchors { fill: parent; margins: 1 }
            radius: Math.max(0, g.radius - 1)
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(g.sheen.r, g.sheen.g, g.sheen.b, Math.min(1, g.a * (g.lightFrost ? 3 : 1.6)))
        }
    }
    Item {
        id: rimFade
        anchors.fill: parent
        visible: false
        layer.enabled: Config.glassGloss
        Rectangle {
            id: rimGrad
            anchors.fill: parent
            // Solid across the top and round the corners, gone by just past them
            readonly property real fadeTo: Math.min(0.6, (Math.max(g.radius, 4) + 6) / Math.max(1, g.height))
            gradient: Gradient {
                GradientStop { position: 0.0; color: "white" }
                GradientStop { position: Math.max(0.01, rimGrad.fadeTo * 0.45); color: "white" }
                GradientStop { position: rimGrad.fadeTo; color: "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
