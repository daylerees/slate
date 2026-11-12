#version 440
// The shadow under anything raised (Shadow.qml): a soft, dark shape the size of the surface,
// dropped a little, with the surface's own shape cut out of it. Worked out per pixel from the
// distance to a rounded rectangle, so there's no blur pass and no extra layer, and nothing
// lies under the surface itself: on glass a shadow there would show through it.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;          // the shadow's colour; its alpha is how dark it is at its darkest
    vec4 box;           // the surface within this item: x, y, width, height (px)
    vec4 radii;         // its corners: top left, top right, bottom right, bottom left (px)
    vec2 size;          // this item's size (px)
    vec2 drop;          // how far the shadow sits from the surface (px)
    float blur;         // how far it reaches before it's gone (px)
    vec4 hole;          // a rounded rectangle taken out of the surface (x, y, width, height; none
    float holeRadius;   // if its width is 0): the menu bar's flared corners are made this way
    vec4 fade;          // no shadow near one edge of the surface (a panel's, where it joins the bar):
                        // x, y: which way in from that edge (0, 0: none); z: nothing for this far
                        // from it; w: then growing to full over this far (px)
    vec4 point;         // a menu's pointer, part of the surface: a square turned 45°, centred
                        // on the surface's edge (x, y: its centre; z: its side; none if 0). So
                        // the shadow follows it, and none lies under it to show through
    float spread;       // how far the shadow's full darkness reaches past the surface (px)
    vec4 edge;          // cast from one straight edge alone, not the whole shape (x, y: the way it
                        // falls; z: where the edge is along that way; none if x and y are 0): the
                        // menu bar's inner edge, as if it carried on past the screen's sides, so the
                        // shadow tucks under its curved corners rather than wrapping round them
    vec4 joinA;         // up to two curved joins added to the surface (a panel's, where it leaves
    vec4 joinB;         // the bar): each a square (x, y, width, height; none if its width is 0)
    vec4 joinC;         // less a disk of radius joinR at (joinC.xy) for A, (joinC.zw) for B
    float joinR;
    vec4 under;         // another shadow already under this one, with the same look, cast from one
                        // straight edge (x, y: the way it falls; z: where the edge is; w: how dark
                        // it is; none if x and y are 0): the menu bar's, under a panel's. Only what
                        // this one adds over it is drawn, so where they meet it's as dark as the
                        // darker of the two, not both
};

// Distance to a rounded rectangle centred on the origin (negative inside)
float roundBox(vec2 p, vec2 halfSize, vec4 r) {
    float rad = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
    vec2 q = abs(p) - halfSize + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

float segment(vec2 p, vec2 a, vec2 b) {
    vec2 v = b - a;
    return length(p - a - v * clamp(dot(p - a, v) / dot(v, v), 0.0, 1.0));
}

// One curved join: a square less a disk centred on one of its corners. Inside the square, the
// distance is the square's or the disk's; outside it, the nearest part is one of the join's two
// straight edges (the curve's inside the square), measured to them (the square less the disk
// there drew the disk's outline as a ring of shadow)
float join(vec2 q, vec4 sq, vec2 c) {
    float s = roundBox(q - (sq.xy + sq.zw * 0.5), sq.zw * 0.5, vec4(0.0));
    if (s > 0.0) {
        vec2 o = vec2(abs(c.x - sq.x) < 0.5 ? sq.x + sq.z : sq.x, abs(c.y - sq.y) < 0.5 ? sq.y + sq.w : sq.y);
        return min(segment(q, o, vec2(c.x, o.y)), segment(q, o, vec2(o.x, c.y)));
    }
    return max(s, -(length(q - c) - joinR));
}

// Distance to the surface: its box (with a menu's pointer and a panel's joins), less the hole
float shape(vec2 q) {
    float d = roundBox(q - (box.xy + box.zw * 0.5), box.zw * 0.5, radii);
    if (joinA.z > 0.0) d = min(d, join(q, joinA, joinC.xy));
    if (joinB.z > 0.0) d = min(d, join(q, joinB, joinC.zw));
    if (point.z > 0.0) {
        vec2 p = q - point.xy;
        vec2 t = abs(vec2(p.x + p.y, p.y - p.x) * 0.70710678) - vec2(point.z * 0.5);
        d = min(d, length(max(t, 0.0)) + min(max(t.x, t.y), 0.0));
    }
    if (hole.z > 0.0)
        d = max(d, -roundBox(q - (hole.xy + hole.zw * 0.5), hole.zw * 0.5, vec4(holeRadius)));
    return d;
}

void main() {
    vec2 q = qt_TexCoord0 * size;
    float surface = shape(q);
    float shade = (edge.x != 0.0 || edge.y != 0.0 ? dot(q - drop, edge.xy) - edge.z : shape(q - drop)) - spread;
    // Darkest just inside the shadow's own edge, about half at the edge, gone at `blur`
    float soft = max(blur, 0.5);                    // (no softness at all: still a smooth edge)
    float t = clamp((shade + soft * 0.4) / (soft * 1.4), 0.0, 1.0);
    float a = (1.0 - t) * (1.0 - t);
    // Nothing under the surface itself, fading in just inside its edge: full strength from the
    // first pixel outside it (centred on the edge instead, that pixel got a little less, which
    // showed as a light line between a surface and a hard shadow, under the menu bar most)
    a *= smoothstep(-1.0, 0.0, surface);
    if (fade.x != 0.0 || fade.y != 0.0) {
        float d = fade.x > 0.0 ? q.x - box.x : fade.x < 0.0 ? box.x + box.z - q.x
                : fade.y > 0.0 ? q.y - box.y : box.y + box.w - q.y;
        a *= smoothstep(fade.z, fade.z + max(fade.w, 0.001), d);
    }
    float alpha = tint.a * a * qt_Opacity;
    if (under.x != 0.0 || under.y != 0.0) {
        float us = dot(q, under.xy) - under.z - spread;
        float ut = clamp((us + soft * 0.4) / (soft * 1.4), 0.0, 1.0);
        float ua = (1.0 - ut) * (1.0 - ut) * under.w;
        alpha = max(0.0, (alpha - ua) / max(0.001, 1.0 - ua));
    }
    fragColor = vec4(tint.rgb, 1.0) * alpha;
}
