#version 440

// Water filled to `level` inside a rounded rect, with two rolling waves (the back one paler) on its surface.
// Used by the system monitor's Graphs cards. The waves flatten near empty and full so a full card doesn't slosh.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float level;      // 0..1
    float phase;      // radians, advanced by the item
    float widthPx;
    float heightPx;
    float radiusPx;
    float amp;        // wave height in px
    vec4 front;       // straight rgba
    vec4 back;        // straight rgba
} ubuf;

void main() {
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 p = qt_TexCoord0 * size;

    // Rounded-rect coverage.
    float r = min(ubuf.radiusPx, 0.5 * min(size.x, size.y));
    vec2 q = abs(p - 0.5 * size) - (0.5 * size - r);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    float inside = clamp(0.5 - d, 0.0, 1.0);

    float lv = clamp(ubuf.level, 0.0, 1.0);
    float a = ubuf.amp * clamp(min(lv, 1.0 - lv) * 12.0, 0.0, 1.0);
    float surface = size.y * (1.0 - lv);
    float x = p.x / max(size.x, 1.0) * 6.2831853;
    float s1 = surface + a * sin(x * 1.3 + ubuf.phase);
    float s2 = surface + a * 0.8 * sin(x * 0.9 - ubuf.phase * 1.3 + 1.7) - a * 0.6;
    float f1 = clamp(p.y - s1 + 0.5, 0.0, 1.0);
    float f2 = clamp(p.y - s2 + 0.5, 0.0, 1.0);

    // Front over back, premultiplied.
    float aB = ubuf.back.a * f2;
    float aF = ubuf.front.a * f1;
    vec3 rgb = ubuf.front.rgb * aF + ubuf.back.rgb * aB * (1.0 - aF);
    float alpha = aF + aB * (1.0 - aF);
    fragColor = vec4(rgb, alpha) * inside * ubuf.qt_Opacity;
}
