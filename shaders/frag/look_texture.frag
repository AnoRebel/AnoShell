#version 450

// Look texture overlay (looks/schema.md `texture`), masked to a rounded rect.
// mode: 1 caustics, 2 paper_grain, 3 grid_scan, 4 clay_soft. Output is a
// premultiplied tint layered over the surface fill; `time` only advances while
// the surface is interacted with, so an idle surface costs one static frame.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float radius;
    float mode;
    float strength;
    float param;     // grid spacing px (grid_scan)
    float time;      // seconds
    vec4 tint;       // straight rgba: the light colour
    vec4 shade;      // straight rgba: the dark colour
} ubuf;

float sdRoundBox(vec2 p, vec2 hs, float r) {
    r = min(r, min(hs.x, hs.y));
    vec2 q = abs(p) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Water caustics: a few warped sine layers, sharpened into bright filaments.
float caustics(vec2 uv, float t) {
    vec2 p = uv * 6.0;
    float c = 0.0;
    for (int i = 1; i <= 3; i++) {
        float fi = float(i);
        p += vec2(sin(p.y * 0.9 + t * 0.6 * fi), cos(p.x * 1.1 - t * 0.5 * fi)) * (0.6 / fi);
        c += abs(sin(p.x + p.y) * cos(p.x - p.y * 0.7));
    }
    c = 1.0 - c / 3.0;
    return pow(clamp(c, 0.0, 1.0), 6.0);
}

void main() {
    vec2 size = vec2(ubuf.widthPx, ubuf.heightPx);
    vec2 px = qt_TexCoord0 * size;
    float d = sdRoundBox(px - size * 0.5, size * 0.5, ubuf.radius);
    float fw = max(fwidth(d), 1e-4);
    float cov = 1.0 - smoothstep(-fw, fw, d);
    if (cov <= 0.0) { fragColor = vec4(0.0); return; }

    int m = int(ubuf.mode + 0.5);
    vec4 col = vec4(0.0);  // straight rgb, a = layer alpha
    if (m == 1) {
        float c = caustics(px / 220.0, ubuf.time);
        col = vec4(ubuf.tint.rgb, c * ubuf.strength * 0.3);
    } else if (m == 2) {
        // Static paper grain: fine noise, light and dark specks around zero.
        float g = hash(floor(px)) - 0.5;
        col = g > 0.0 ? vec4(ubuf.tint.rgb, g * ubuf.strength * 0.5)
                      : vec4(ubuf.shade.rgb, -g * ubuf.strength * 0.5);
    } else if (m == 3) {
        float s = max(ubuf.param, 4.0);
        vec2 g = abs(fract(px / s - 0.5) - 0.5) * s;   // px to the nearest line
        float line = 1.0 - smoothstep(0.0, 1.0, min(g.x, g.y));
        // A soft scan band sweeps down only while time moves.
        float band = exp(-pow((px.y - mod(ubuf.time * 120.0, size.y + 160.0) + 80.0) / 40.0, 2.0));
        col = vec4(ubuf.tint.rgb, (line * 0.6 + band * 0.35) * ubuf.strength);
    } else if (m == 4) {
        // Soft inner light from the top-left, inner shade toward the bottom edge.
        float inner = clamp(-d / 18.0, 0.0, 1.0);
        vec2 uv = px / size;
        float light = (1.0 - inner) * clamp(1.2 - (uv.x + uv.y), 0.0, 1.0);
        float shade = (1.0 - inner) * clamp(uv.y * 1.4 - 0.4, 0.0, 1.0);
        col = light >= shade ? vec4(ubuf.tint.rgb, light * ubuf.strength)
                             : vec4(ubuf.shade.rgb, shade * ubuf.strength);
    }
    float a = clamp(col.a, 0.0, 1.0) * cov * ubuf.qt_Opacity;
    fragColor = vec4(col.rgb * a, a);
}
