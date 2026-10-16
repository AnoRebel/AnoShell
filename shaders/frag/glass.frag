#version 450

// Glass material (design D7) for a rounded-rect surface: a tint over the
// compositor's blur, a lens-like refraction of the wallpaper near the edges,
// and an edge light. The wallpaper is sampled where it actually sits on
// screen (wallRect maps this item into the wallpaper's UV space).
// Output is premultiplied.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float radius;
    float edgeLight;    // 0..1 rim highlight
    float refraction;   // 0..1 strength; 0 disables wallpaper sampling
    float rimWidth;     // px of the lens band along the edge
    vec4 tint;          // straight rgba: a = tint strength (contrast-adjusted)
    vec4 light;         // straight rgb: edge light colour
    vec4 wallRect;      // this item in wallpaper UV: x, y, w, h
} ubuf;

layout(binding = 1) uniform sampler2D wallpaper;

float sdRoundBox(vec2 p, vec2 hs, float r) {
    r = min(r, min(hs.x, hs.y));
    vec2 q = abs(p) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 px = qt_TexCoord0 * size;
    vec2 c = px - size * 0.5;
    float d = sdRoundBox(c, size * 0.5, ubuf.radius);
    float fw = max(fwidth(d), 1e-4);
    float cov = 1.0 - smoothstep(-fw, fw, d);
    if (cov <= 0.0) { fragColor = vec4(0.0); return; }

    // Lens band: 1 at the edge, 0 inside.
    float band = 1.0 - smoothstep(0.0, ubuf.rimWidth, -d);

    // Base: the tint (the compositor's blur shows through the rest).
    vec3 rgb = ubuf.tint.rgb;
    float a = ubuf.tint.a;

    // Refraction: near the edge, the wallpaper bends inward like a lens.
    if (ubuf.refraction > 0.0) {
        vec2 n = normalize(c / max(size * 0.5, vec2(1.0)) + vec2(1e-5));
        vec2 shift = -n * band * band * ubuf.refraction * 18.0 / size;
        vec2 uv = ubuf.wallRect.xy + (qt_TexCoord0 + shift) * ubuf.wallRect.zw;
        vec3 wall = texture(wallpaper, clamp(uv, 0.0, 1.0)).rgb;
        float k = band * ubuf.refraction * 0.55;
        rgb = mix(rgb, wall, k);
        a = mix(a, 1.0, k * 0.6);
    }

    // Edge light: brightest along the top-left rim, fading inward.
    vec2 uvn = qt_TexCoord0;
    float dirLight = clamp(1.25 - (uvn.x * 0.6 + uvn.y), 0.0, 1.0);
    float rim = (1.0 - smoothstep(0.0, 2.5, -d)) * (0.35 + 0.65 * dirLight);
    float glow = band * 0.25 * dirLight;
    float l = (rim + glow) * ubuf.edgeLight;
    rgb = mix(rgb, ubuf.light.rgb, clamp(l, 0.0, 1.0));
    a = max(a, clamp(l, 0.0, 1.0) * 0.9);

    a *= cov * ubuf.qt_Opacity;
    fragColor = vec4(rgb * a, a);
}
