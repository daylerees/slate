#version 440
// The glass sheen's bright edge and glossy band (Gloss.qml), worked out per pixel from the
// shape's outline, so there are no offscreen layers to keep (they used to be made for every
// sheen, and again every frame on the dock's magnifying icons). It draws the same two things
// as the layers did:
//   rim:  the shape's 1 px rounded outline (in light mode a darker one, with a bright one just
//         inside it), faded out a little way down the sides by a vertical gradient
//   band: a bold shine over the top of the shape, whose lower edge is the bottom of a wide
//         ellipse, kept inside the shape's rounded corners
// Edges are smoothed over one pixel, as Qt draws a rounded rectangle's.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 rimColour;     // the outline's colour (straight alpha; none if its alpha is 0)
    vec4 rimColour2;    // the second outline, one pixel inside the first (light mode; none if alpha 0)
    vec4 radii;         // the shape's corners: top left, top right, bottom right, bottom left (px)
    vec4 radii2;        // the inner outline's corners
    vec4 bandColour;    // the band's colour at full strength (none if its alpha is 0)
    vec4 bandShape;     // the band's ellipse: x: its width, y: its height, z: where the shape's
                        // top falls down it (0 to 1), w: where its lowest point is in the shape (px)
    vec2 size;          // this item's size (px)
    float fadeTo;       // the outline is solid to 45% of this far down (0 to 1 of the height),
                        // gone at it
    float rimOn;        // 1: draw the outline; 0: not
    float bandRound;    // the band's circle's radius before it's squashed (0: a rectangle, with Rounded UI elements off)
};

// Distance to a rounded rectangle centred on the origin (negative inside). A corner's radius
// can't be more than half the shape's smaller side, as Qt's own rectangles do
float roundBox(vec2 p, vec2 halfSize, vec4 r) {
    float rad = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
    rad = min(rad, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

// How much of the pixel a shape covers, from its distance
float cover(float d) {
    return clamp(0.5 - d, 0.0, 1.0);
}

// A colour laid over another, both premultiplied
vec4 over(vec4 top, vec4 under) {
    return top + under * (1.0 - top.a);
}

// The outline: a ring one pixel wide inside the shape's edge
vec4 ring(vec2 p, vec2 centre, vec2 halfSize, vec4 r, vec4 colour) {
    float d = roundBox(p - centre, halfSize, r);
    float c = cover(d) * clamp(d + 1.5, 0.0, 1.0);
    float a = colour.a * c;
    return vec4(colour.rgb * a, a);
}

// The sheen at one point of the shape (premultiplied)
vec4 sheen(vec2 p) {
    vec2 centre = size * 0.5;
    vec4 outc = vec4(0.0);

    if (bandColour.a > 0.0) {
        // The ellipse is a circle squashed from its top (as it is drawn): its pixels are worked
        // out in the circle's own, so its edge is smoothed as the circle's was
        float across = bandShape.x;
        float down = bandShape.y;
        float top = bandShape.w - down;                     // where the ellipse starts, in y
        vec2 c = vec2(size.x * 0.5, top + down * 0.5);
        vec2 q = vec2(p.x - c.x, (p.y - c.y) * across / max(down, 0.001));
        vec2 hs = vec2(across * 0.5);
        float d = roundBox(q, hs, vec4(bandRound));
        float t = (p.y - top) / max(down, 0.001);
        float k = t < bandShape.z ? 1.0 : mix(1.0, 0.25, (t - bandShape.z) / max(1.0 - bandShape.z, 0.001));
        float a = bandColour.a * k * cover(d);
        // Kept inside the shape
        a *= cover(roundBox(p - centre, centre, radii));
        outc = vec4(bandColour.rgb * a, a);
    }

    if (rimOn > 0.5) {
        vec4 rim = ring(p, centre, centre, radii, rimColour);
        if (rimColour2.a > 0.0)
            rim = over(ring(p, centre, centre - vec2(1.0), radii2, rimColour2), rim);
        // Solid across the top and round the corners, gone by just past them
        float f = p.y / max(size.y, 1.0);
        float a = f <= max(0.01, fadeTo * 0.45) ? 1.0 : 1.0 - clamp((f - max(0.01, fadeTo * 0.45)) / max(fadeTo - max(0.01, fadeTo * 0.45), 0.0001), 0.0, 1.0);
        // (the same curve the mask had: smoothstep over its alpha)
        a = a * a * (3.0 - 2.0 * a);
        outc = over(rim * a, outc);
    }

    return outc;
}

void main() {
    // The layers this replaces were drawn a texel to a pixel, then laid over the screen with
    // smoothing, so where the shape sits between two pixels its edge is spread over both. The
    // same here: the four texels round this pixel, mixed the same way (the edge texel repeated
    // past the border)
    vec2 q = qt_TexCoord0 * size - 0.5;
    vec2 i = floor(q);
    vec2 f = q - i;
    vec2 lo = clamp(i + 0.5, vec2(0.5), size - 0.5);
    vec2 hi = clamp(i + 1.5, vec2(0.5), size - 0.5);
    vec4 top = mix(sheen(lo), sheen(vec2(hi.x, lo.y)), f.x);
    vec4 bottom = mix(sheen(vec2(lo.x, hi.y)), sheen(hi), f.x);
    fragColor = mix(top, bottom, f.y) * qt_Opacity;
}
