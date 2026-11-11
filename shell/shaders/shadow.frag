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
};

// Distance to a rounded rectangle centred on the origin (negative inside)
float roundBox(vec2 p, vec2 halfSize, vec4 r) {
    float rad = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
    vec2 q = abs(p) - halfSize + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

// Distance to the surface: its box, less the hole
float shape(vec2 q) {
    float d = roundBox(q - (box.xy + box.zw * 0.5), box.zw * 0.5, radii);
    if (hole.z > 0.0)
        d = max(d, -roundBox(q - (hole.xy + hole.zw * 0.5), hole.zw * 0.5, vec4(holeRadius)));
    return d;
}

void main() {
    vec2 q = qt_TexCoord0 * size;
    float surface = shape(q);
    float shade = shape(q - drop);
    // Darkest just inside the shadow's own edge, about half at the edge, gone at `blur`
    float t = clamp((shade + blur * 0.4) / (blur * 1.4), 0.0, 1.0);
    float a = (1.0 - t) * (1.0 - t);
    a *= smoothstep(-0.75, 0.75, surface);          // nothing under the surface itself
    fragColor = vec4(tint.rgb, 1.0) * (tint.a * a * qt_Opacity);
}
