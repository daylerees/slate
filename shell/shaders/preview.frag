#version 440
// Live window previews (switcher, overview, the dock, the Spaces panel): rounded corners, and
// an inactive window's colours scaled back up by gain. Hyprland dims windows without focus
// (Settings → Windows → Dim inactive windows) and the live pictures of them come out dimmed
// too, which made previews look greyed out; gain is 1 / (1 - dim) for those, 1 for the rest.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float gain;        // how much to brighten (1: as it is)
    float radius;      // corner radius, in the item's pixels
    vec2 size;         // the item's size, in its pixels
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    c.rgb = min(c.rgb * gain, vec3(c.a));                    // premultiplied: never past its alpha
    // Rounded corners: distance outside the rounded rectangle, smoothed over a pixel
    vec2 p = qt_TexCoord0 * size;
    vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    fragColor = c * clamp(0.5 - d, 0.0, 1.0) * qt_Opacity;
}
