#version 440

// The Bubble Monitor's reveal: the monitor shows inside a circle that grows from the button that opened it, its
// edge a rippling bright rim. A layer.effect on the monitor, only while `progress` < 1.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 → 1
    float widthPx;
    float heightPx;
    float cx;         // origin, px
    float cy;
    vec4 rim;         // straight rgba
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 p = qt_TexCoord0 * size;
    vec2 o = vec2(ubuf.cx, ubuf.cy);
    // Far enough to reach the furthest corner.
    float far = length(max(abs(o), abs(size - o)));
    float t = ubuf.progress;
    float e = t * t * (3.0 - 2.0 * t);
    float ang = atan(p.y - o.y, p.x - o.x);
    float wobble = 10.0 * sin(ang * 7.0 + t * 9.0) * (1.0 - t);
    float radius = e * (far + 40.0) + wobble;
    float d = length(p - o) - radius;
    float inside = clamp(0.5 - d, 0.0, 1.0);
    vec4 c = texture(source, qt_TexCoord0) * inside;
    float ring = exp(-abs(d) / 6.0) * (1.0 - t);
    fragColor = (c + vec4(ubuf.rim.rgb, 1.0) * ubuf.rim.a * ring) * ubuf.qt_Opacity;
}
