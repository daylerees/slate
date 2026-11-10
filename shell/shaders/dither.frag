#version 440
// Slate's own wallpapers (Wallpaper.qml): the picture scaled to the screen here, on the GPU,
// then rounded to the screen's colours with a little fine noise. Colour that smooth changes by
// less than one step in 256 over many pixels; rounded plainly, each step shows as a band. The
// files are dithered against that, but scaling one to the screen's size and rounding again
// undid it. The noise is a step either way, more often small than large, and different for
// red, green and blue, so every patch averages out to the colour in between.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 crop;          // the part of the picture that's shown: x, y, width, height (0…1)
};
layout(binding = 1) uniform sampler2D source;

float noise(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void main() {
    vec3 c = texture(source, crop.xy + qt_TexCoord0 * crop.zw).rgb;
    vec2 p = gl_FragCoord.xy;
    vec3 n = vec3(noise(p) + noise(p + vec2(47.0, 17.0)),
                  noise(p + vec2(13.0, 71.0)) + noise(p + vec2(89.0, 29.0)),
                  noise(p + vec2(61.0, 5.0)) + noise(p + vec2(23.0, 97.0))) - 1.0;
    fragColor = vec4(c + n / 255.0, 1.0) * qt_Opacity;
}
