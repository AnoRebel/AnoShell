#version 450

// Ink-bleed reveal (Ink look's `transition: "ink_bleed"`): the card soaks in
// from its top centre with a noisy, fibrous edge that is a touch darker where
// the ink is still wet. Runs as a layer.effect only while `progress` < 1.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 → 1
    float widthPx;
    float heightPx;
} ubuf;

layout(binding = 1) uniform sampler2D source;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

void main() {
    vec4 src = texture(source, qt_TexCoord0);
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 px = qt_TexCoord0 * size;
    // Distance from the top centre, normalised so 1.0 reaches the far corner.
    vec2 origin = vec2(size.x * 0.5, 0.0);
    float maxd = length(vec2(size.x * 0.5, size.y));
    float d = length(px - origin) / max(maxd, 1.0);
    // Fibrous edge: noise on a ~40 px scale, plus fine grain.
    float edge = d + (fbm(px / 40.0) - 0.5) * 0.35 + (hash(floor(px)) - 0.5) * 0.03;
    float front = ubuf.progress * 1.35;            // overshoots so the corners fill
    float a = 1.0 - smoothstep(front - 0.06, front, edge);
    // Wet edge: slightly darker just inside the front.
    float wet = smoothstep(front - 0.14, front - 0.04, edge) * a * (1.0 - ubuf.progress);
    vec3 rgb = src.rgb * (1.0 - 0.35 * wet);
    fragColor = vec4(rgb, src.a) * a * ubuf.qt_Opacity;
}
