#version 450

// Fan switcher body: the cards' rounded rects and a stem to the pill, melted
// into one silhouette with a smooth minimum (liquid joins between neighbours).
// Rects are in item px (x, y, w, h); w <= 0 means unused.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float radius;      // card corner radius
    float k;           // join softness in px
    vec4 color;        // straight rgba
    vec4 r0; vec4 r1; vec4 r2; vec4 r3;
    vec4 r4; vec4 r5; vec4 r6; vec4 r7;
} ubuf;

float sdRoundBox(vec2 p, vec4 r, float rad) {
    vec2 hs = r.zw * 0.5;
    rad = min(rad, min(hs.x, hs.y));
    vec2 q = abs(p - (r.xy + hs)) - hs + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

// Polynomial smooth minimum.
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float add(float d, vec2 p, vec4 r) {
    if (r.z <= 0.0) return d;
    return smin(d, sdRoundBox(p, r, ubuf.radius), ubuf.k);
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(ubuf.widthPx, ubuf.heightPx);
    float d = 1e5;
    d = add(d, p, ubuf.r0); d = add(d, p, ubuf.r1); d = add(d, p, ubuf.r2); d = add(d, p, ubuf.r3);
    d = add(d, p, ubuf.r4); d = add(d, p, ubuf.r5); d = add(d, p, ubuf.r6); d = add(d, p, ubuf.r7);
    float fw = max(fwidth(d), 1e-4);
    float a = (1.0 - smoothstep(-fw, fw, d)) * ubuf.color.a * ubuf.qt_Opacity;
    fragColor = vec4(ubuf.color.rgb * a, a);
}
