#version 440
// The dock's Glow hover effect (DockGlow.qml): a thin ring round an icon's tile, and a soft glow
// off it, worked out per pixel from the distance to the ring's rounded rectangle (no blur pass).
//
// Hyprland blurs behind the dock wherever anything at all is drawn on it (Config.dockGlassCut),
// so with the dock's glass blurring, a glow drawn the usual way made its whole soft falloff a
// patch of blurred glass, with a hard edge where the falloff ended. Then (`light` 1) the glow is
// drawn as light added to what's behind it: its colour with no coverage at all, which Hyprland
// leaves clear, and which still shows, as both Qt and Hyprland blend premultiplied colour. The
// ring itself stays solid (a thin line hides the blur behind it).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;          // the glow's colour; its alpha is how strong the glow is at its brightest
    vec4 box;           // the ring's outer edge within this item: x, y, width, height (px)
    vec2 size;          // this item's size (px)
    float radius;       // the ring's outer corners (px)
    float line;         // the ring's width (px)
    float reach;        // how far the glow reaches past the ring before it's gone (px)
    float spread;       // how far its full strength reaches past the ring (px)
    float light;        // 1: the glow as added light (see above); 0: drawn as usual
};

// Distance to a rounded rectangle centred on the origin (negative inside)
float roundBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 q = qt_TexCoord0 * size;
    float d = roundBox(q - (box.xy + box.zw * 0.5), box.zw * 0.5, min(radius, min(box.z, box.w) * 0.5));
    // The ring: inside its outer edge and outside its inner one (smoothed over a pixel)
    float ring = clamp(0.5 - d, 0.0, 1.0) * clamp(d + line + 0.5, 0.0, 1.0);
    // The glow: full strength out to the spread, then fading softly to nothing at the reach
    float t = clamp((d - spread) / max(reach, 1.0), 0.0, 1.0);
    float glow = tint.a * (1.0 - t) * (1.0 - t) * (1.0 - t);
    float cover = ring + glow * (1.0 - ring);
    fragColor = vec4(tint.rgb * cover, mix(cover, ring, light)) * qt_Opacity;
}
