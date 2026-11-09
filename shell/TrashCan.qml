// The dock's waste basket, drawn: a modern angular bin (smooth satin metal, wider at the top than
// the base, with a lighter lip and a dark opening across its top), tinted towards
// the theme's accent; with crumpled paper sticking up out of it when there's something in it.
// Drawn once at drawSize (the dock's magnified size) and scaled, so magnifying doesn't redraw
// it; it follows light and dark and the wallpaper's tint through Config.tint.
//   TrashCan { anchors.fill: parent; full: count > 0; drawSize: … }

import QtQuick

Item {
    id: bin
    property bool full: false
    property real drawSize: 0               // 0: drawn at its own size
    // The metal: a cool grey, a quarter of the way to the accent
    readonly property color metal: {
        const g = Config.tint(Config.s.lightMode ? "#8e97a4" : "#b4bcc8");
        const a = Config.accent;
        return Qt.rgba(g.r * 0.75 + a.r * 0.25, g.g * 0.75 + a.g * 0.25, g.b * 0.75 + a.b * 0.25, 1);
    }
    onMetalChanged: canvas.requestPaint()
    onFullChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        width: bin.drawSize > 0 ? bin.drawSize : bin.width
        height: bin.drawSize > 0 ? bin.drawSize : bin.height
        transform: Scale {
            xScale: bin.width / Math.max(1, canvas.width)
            yScale: bin.height / Math.max(1, canvas.height)
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onAvailableChanged: if (available) requestPaint()

        // A colour lighter (k > 0) or darker (k < 0) than the metal
        function shade(k, alpha) {
            const c = bin.metal;
            const f = k >= 0 ? (v => v + (1 - v) * k) : (v => v * (1 + k));
            return Qt.rgba(f(c.r), f(c.g), f(c.b), alpha === undefined ? 1 : alpha);
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height, cx = w / 2;
            // An angular bin, wider at the top than the base, its corners slightly rounded, seen
            // from just above: its lip and opening across the top, the body below
            const left = w * 0.20, right = w * 0.80, top = h * 0.31, bottom = h * 0.85;
            const footL = w * 0.31, footR = w * 0.69;       // the base, narrower
            // The body's outline: straight sides, the bottom corners rounded
            function bodyPath() {
                ctx.beginPath();
                ctx.moveTo(left, top);
                ctx.lineTo(right, top);
                ctx.lineTo(footR + (right - footR) * 0.08, bottom - h * 0.04);
                ctx.quadraticCurveTo(footR, bottom, footR - w * 0.035, bottom);
                ctx.lineTo(footL + w * 0.035, bottom);
                ctx.quadraticCurveTo(footL, bottom, footL - (footL - left) * 0.08, bottom - h * 0.04);
                ctx.closePath();
            }
            const r = w * 0.06;
            const lipL = w * 0.175, lipR = w * 0.825, lipT = h * 0.255, lipB = h * 0.335;

            // A soft shadow under it
            const sh = ctx.createRadialGradient(cx, bottom, 0, cx, bottom, w * 0.32);
            sh.addColorStop(0, Qt.rgba(0, 0, 0, 0.32));
            sh.addColorStop(1, Qt.rgba(0, 0, 0, 0));
            ctx.fillStyle = sh;
            ctx.beginPath(); ctx.ellipse(cx - w * 0.32, bottom - h * 0.035, w * 0.64, h * 0.08); ctx.fill();

            // The body: smooth satin metal, lit from the left
            const body = ctx.createLinearGradient(left, 0, right, 0);
            body.addColorStop(0.00, shade(0.18));
            body.addColorStop(0.35, shade(0.30));
            body.addColorStop(0.75, shade(-0.05));
            body.addColorStop(1.00, shade(-0.32));
            ctx.fillStyle = body;
            bodyPath(); ctx.fill();
            // and a little darker towards its foot
            const foot = ctx.createLinearGradient(0, top, 0, bottom);
            foot.addColorStop(0.6, Qt.rgba(0, 0, 0, 0));
            foot.addColorStop(1.0, Qt.rgba(0, 0, 0, 0.18));
            ctx.fillStyle = foot;
            bodyPath(); ctx.fill();
            // A soft highlight down its lit side, sloping with it
            const hi = ctx.createLinearGradient(left + w * 0.06, 0, left + w * 0.16, 0);
            hi.addColorStop(0, Qt.rgba(1, 1, 1, 0));
            hi.addColorStop(0.5, Qt.rgba(1, 1, 1, 0.18));
            hi.addColorStop(1, Qt.rgba(1, 1, 1, 0));
            ctx.fillStyle = hi;
            ctx.beginPath();
            ctx.moveTo(left + w * 0.05, top + h * 0.04);
            ctx.lineTo(left + w * 0.13, top + h * 0.04);
            ctx.lineTo(footL + w * 0.07, bottom - h * 0.05);
            ctx.lineTo(footL + w * 0.01, bottom - h * 0.05);
            ctx.closePath(); ctx.fill();

            // The lip round the top, a shade lighter, with the opening dark inside it
            const lip = ctx.createLinearGradient(0, lipT, 0, lipB);
            lip.addColorStop(0, shade(0.55));
            lip.addColorStop(1, shade(0.05));
            ctx.fillStyle = lip;
            ctx.beginPath(); ctx.roundedRect(lipL, lipT, lipR - lipL, lipB - lipT, r * 0.9, r * 0.9); ctx.fill();
            const inset = w * 0.025;
            ctx.fillStyle = shade(-0.78);
            ctx.beginPath(); ctx.roundedRect(lipL + inset, lipT + inset * 0.8, (lipR - lipL) - inset * 2, (lipB - lipT) - inset * 1.6, r * 0.6, r * 0.6); ctx.fill();

            // Paper, crumpled, sticking up out of it
            if (bin.full) {
                const paper = [[0.40, 0.24, 0.10], [0.57, 0.21, 0.115], [0.49, 0.17, 0.085], [0.65, 0.26, 0.075]];
                for (const p of paper) {
                    const px = w * p[0], py = h * p[1], pr = w * p[2];
                    const g = ctx.createRadialGradient(px - pr * 0.35, py - pr * 0.4, pr * 0.1, px, py, pr);
                    g.addColorStop(0, "#ffffff");
                    g.addColorStop(1, "#c6cad1");
                    ctx.fillStyle = g;
                    ctx.beginPath(); ctx.arc(px, py, pr, 0, Math.PI * 2); ctx.fill();
                    ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.12); ctx.lineWidth = Math.max(1, w * 0.008);
                    ctx.beginPath(); ctx.moveTo(px - pr * 0.5, py - pr * 0.1); ctx.lineTo(px + pr * 0.1, py + pr * 0.3); ctx.lineTo(px + pr * 0.5, py - pr * 0.2); ctx.stroke();
                }
                // the lip's front edge, back over the paper's foot
                ctx.fillStyle = shade(0.2);
                ctx.beginPath(); ctx.roundedRect(lipL, lipB - h * 0.025, lipR - lipL, h * 0.025, r * 0.4, r * 0.4); ctx.fill();
            }
        }
    }
}
