#version 440
// Tray icons: light parts take the theme text colour, dark/coloured parts become transparent.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float threshold;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec3 rgb = c.a > 0.0 ? c.rgb / c.a : vec3(0.0);           // un-premultiply
    float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
    float w = smoothstep(threshold - 0.08, threshold + 0.08, lum);
    float a = c.a * w;
    fragColor = vec4(tint.rgb * a, a) * qt_Opacity;           // premultiplied tint colour
}
