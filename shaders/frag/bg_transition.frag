#version 450

// Shell-drawn wallpaper transition: the incoming image (source) is masked in
// over the current one by `progress`. mode: 0 fade, 1 wipe (left→right),
// 2 grow (a circle from the centre). A soft edge for wipe/grow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    float aspect;   // width / height
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    float p = clamp(ubuf.progress, 0.0, 1.0);
    float a;
    int m = int(ubuf.mode + 0.5);
    if (m == 1) {
        float edge = p * 1.2 - 0.1;
        a = 1.0 - smoothstep(edge - 0.08, edge + 0.08, qt_TexCoord0.x);
    } else if (m == 2) {
        vec2 d = (qt_TexCoord0 - 0.5) * vec2(ubuf.aspect, 1.0);
        float r = p * length(vec2(ubuf.aspect, 1.0)) * 0.55;
        a = 1.0 - smoothstep(r - 0.06, r + 0.02, length(d));
    } else {
        a = p;
    }
    fragColor = c * a * ubuf.qt_Opacity;
}
