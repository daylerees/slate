// The tile behind an app icon when icons don't fill their shape (Settings → Appearance →
// App icons → Fill the shape off): the shape in the theme's colour (or, with Tiles in the icon's
// colour, a deep shade of the icon's own: Config.iconTileFor), drawn here rather than
// into the icon files, so it follows light/dark and the wallpaper tint straight away.
// Put it inside the icon's Image:  IconPlate { anchors.fill: parent; z: -1 }
// (z -1 draws it behind the image, and it moves with any transform on the image).

import QtQuick

Canvas {
    id: plate
    property string shape: Config.s.iconShape
    property bool fill: Config.s.iconFill
    // Which app's icon it's behind, from the tile image it sits in (for tiles in the icon's colour)
    readonly property string app: {
        const src = parent && parent.source !== undefined ? String(parent.source) : "";
        if (src.indexOf("/tiles/") < 0) return "";
        return src.split("?")[0].split("/").pop().replace(/\.png$/, "");
    }
    // The theme's tile, or with Settings → App icons → Tiles in the icon's colour, a shade of the icon's
    property color color: Config.iconTileFor(app, Config.iconPlateColor)
    // In the icon's colour: a soft gradient, a touch lighter at the top left and darker at the
    // bottom right (the theme's tile, and a space's, stay flat)
    property bool shaded: Config.iconTileShade(app) !== null
    visible: !fill && shape !== "original"

    onShapeChanged: requestPaint()
    onColorChanged: requestPaint()
    onShadedChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()

    // The same outlines scripts/appicon.py cuts the filled icons to
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (!visible) return;
        const w = width, h = height;
        if (shaded) {
            const c = plate.color, l = c.hslLightness;
            // Mostly top to bottom, tilted a little: lightest towards the top left
            const g = ctx.createLinearGradient(w * 0.3, 0, w * 0.7, h);
            g.addColorStop(0, Qt.hsla(c.hslHue, c.hslSaturation, Math.min(1, l + 0.08), c.a));
            g.addColorStop(1, Qt.hsla(c.hslHue, c.hslSaturation, Math.max(0, l - 0.08), c.a));
            ctx.fillStyle = g;
        } else ctx.fillStyle = plate.color;
        ctx.beginPath();
        if (shape === "circle") {
            ctx.arc(w / 2, h / 2, Math.min(w, h) / 2, 0, 2 * Math.PI);
        } else if (shape === "square") {
            ctx.rect(0, 0, w, h);
        } else if (shape === "squircle") {
            // Superellipse |x|^n + |y|^n = 1
            const n = 4.5, steps = 180;
            for (let i = 0; i <= steps; i++) {
                const t = 2 * Math.PI * i / steps, c = Math.cos(t), s = Math.sin(t);
                const x = w / 2 + w / 2 * Math.sign(c) * Math.pow(Math.abs(c), 2 / n);
                const y = h / 2 + h / 2 * Math.sign(s) * Math.pow(Math.abs(s), 2 / n);
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
        } else {
            ctx.roundedRect(0, 0, w, h, w * 0.225, h * 0.225);    // tile: a rounded square
        }
        ctx.closePath();
        ctx.fill();
    }
}
