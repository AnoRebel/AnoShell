#version 450

// Shell-drawn wallpaper transition: the incoming image (source) is masked in
// over the current one by `progress`. mode: 0 fade, 1 wipe (left→right),
// 2 grow (a circle from the centre), 3 paint (blobs that start at different
// times in a jittered grid and grow until they cover it). A soft edge for all
// but fade.

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

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Paint: each cell of a 7-row grid holds a blob at a random spot with a random
// start; blobs grow (with a wobbly edge) until every pixel is covered at p = 1.
float paint(vec2 uv, float p) {
    vec2 g = uv * vec2(ubuf.aspect, 1.0) * 7.0;
    vec2 cell = floor(g);
    float a = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 c = cell + vec2(x, y);
            vec2 h = hash2(c);
            vec2 centre = c + 0.2 + 0.6 * h;
            float start = h.x * 0.6;                    // when this blob begins
            float t = clamp((p - start) / (1.0 - start), 0.0, 1.0);
            t = t * t * (3.0 - 2.0 * t);                // eases in and out
            vec2 d = g - centre;
            float ang = atan(d.y, d.x);
            float wobble = 0.08 * sin(ang * 5.0 + h.y * 6.2831) * t;
            float r = t * 1.45 + wobble;                // reaches the far corners of its cell
            a = max(a, 1.0 - smoothstep(r - 0.12, r + 0.04, length(d)));
        }
    }
    return p >= 1.0 ? 1.0 : a;
}

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
    } else if (m == 3) {
        a = paint(qt_TexCoord0, p);
    } else {
        a = p;
    }
    fragColor = c * a * ubuf.qt_Opacity;
}
