#version 450

// Lock intros (modules/lock/LockIntro.qml), drawn over the lock screen while the session locks.
//   mode 0, waves: three coloured wave bands sweep over a still of the desktop along `dir` from `origin`
//           (down from the top, or diagonally from a corner) and leave the lock screen behind them;
//   mode 1, portal: a spinning dashed ring grows from the centre, the lock screen inside it, the still outside.
// Where the result is transparent the lock screen under it shows.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0 → 1
    float mode;       // 0 waves, 1 portal
    float widthPx;
    float heightPx;
    vec2 origin;      // waves: where they start, in px
    vec2 dir;         // waves: unit direction they travel
    float hasStill;
    vec4 c1;
    vec4 c2;
    vec4 c3;
} ubuf;

layout(binding = 1) uniform sampler2D still;

void main() {
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 px = qt_TexCoord0 * size;
    vec4 s = ubuf.hasStill > 0.5 ? texture(still, qt_TexCoord0) : vec4(0.0);
    float p = ubuf.progress;

    if (ubuf.mode < 0.5) {
        // Distance along the sweep (0 at the origin, 1 at the far side) and across it.
        vec2 rel = px - ubuf.origin;
        float span = abs(dot(size, abs(ubuf.dir)));
        float d = dot(rel, ubuf.dir) / span;
        float q = dot(rel, vec2(-ubuf.dir.y, ubuf.dir.x)) / max(size.x, size.y);
        float amp = 0.035, gap = 0.09, aa = 1.5 / span;
        float lead = mix(-amp - 0.02, 1.0 + 3.0 * gap + amp, p);
        float e0 = lead + amp * sin(q * 9.0 + p * 7.0);
        float e1 = lead - gap + amp * sin(q * 7.0 + 1.7 + p * 6.0);
        float e2 = lead - 2.0 * gap + amp * sin(q * 11.0 + 3.1 + p * 5.0);
        float e3 = lead - 3.0 * gap + amp * sin(q * 8.0 + 4.4 + p * 8.0);
        float m0 = 1.0 - smoothstep(e0 - aa, e0 + aa, d);
        float m1 = 1.0 - smoothstep(e1 - aa, e1 + aa, d);
        float m2 = 1.0 - smoothstep(e2 - aa, e2 + aa, d);
        float m3 = 1.0 - smoothstep(e3 - aa, e3 + aa, d);
        vec4 col = mix(s, ubuf.c1, m0);
        col = mix(col, ubuf.c2, m1);
        col = mix(col, ubuf.c3, m2);
        fragColor = col * (1.0 - m3) * ubuf.qt_Opacity;
    } else {
        vec2 c = size * 0.5;
        vec2 rel = px - c;
        float r = length(rel) / (0.5 * length(size));
        float R = p * 1.12, w = 0.045, aa = 1.5 / (0.5 * length(size));
        float inside = 1.0 - smoothstep(R - w - aa, R - w + aa, r);   // the lock shows
        float outside = smoothstep(R - aa, R + aa, r);                 // the still shows
        float a = atan(rel.y, rel.x) / 6.2831853;
        float dash = step(0.5, fract(a * 18.0 + p * 2.5));
        vec4 ring = mix(ubuf.c1, ubuf.c2, dash);
        vec4 col = mix(ring, s, outside);
        fragColor = col * (1.0 - inside) * ubuf.qt_Opacity;
    }
}
