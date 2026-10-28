#version 450

// Connected frame silhouette: frame ring + chrome bodies as one SDF with elevation shadow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float cutoutRadius;
    vec4 cutout;        // inner cutout edges in px: x=left y=top z=right w=bottom
    vec4 surfaceColor;  // straight (non-premultiplied) rgba
    vec4 shadowColor;   // straight rgba; a = 0 disables both shadow terms
    vec4 shadowParam;   // key: x = blur px, y = spread px, z,w = offset px
    vec4 ambientParam;  // ambient: x = blur px, y = spread px, z = alpha
    // Eight chrome slots, one mat4 each (ShaderEffect has no array uniforms).
    // Columns: [0] rect = x,y,w,h px; [1] corner = per-corner radii; [2] k =
    // per-corner junction fillet radii (both topLeft, topRight, bottomRight,
    // bottomLeft; a corner is sharp exactly where its k > 0); [3] x = active,
    // y = jelly offset px (the free edge's give, 0 at rest), z = axis (0 x,
    // 1 y), w = the anchored (frame-side) edge in px.
    mat4 slot0;
    mat4 slot1;
    mat4 slot2;
    mat4 slot3;
    mat4 slot4;
    mat4 slot5;
    mat4 slot6;
    mat4 slot7;
    // Look texture (looks/schema.md), as in look_texture.frag; static here.
    // texMode: 0 none, 1 caustics, 2 paper grain, 3 grid, 4 clay light.
    float texMode;
    float texStrength;
    float texParam;
    vec4 texTint;       // straight rgb
    vec4 texShade;      // straight rgb
    vec4 glassEdge;     // glass edge light: rgb, a = strength (0 off)
} ubuf;

float texHash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float texCaustics(vec2 uv) {
    vec2 p = uv * 6.0;
    float c = 0.0;
    for (int i = 1; i <= 3; i++) {
        float fi = float(i);
        p += vec2(sin(p.y * 0.9), cos(p.x * 1.1)) * (0.6 / fi);
        c += abs(sin(p.x + p.y) * cos(p.x - p.y * 0.7));
    }
    return pow(clamp(1.0 - c / 3.0, 0.0, 1.0), 6.0);
}

// Straight-rgb layer + alpha for pixel px at scene distance d (< 0 inside).
vec4 lookTexture(vec2 px, float d) {
    int m = int(ubuf.texMode + 0.5);
    float k = ubuf.texStrength;
    if (m == 1) return vec4(ubuf.texTint.rgb, texCaustics(px / 220.0) * k * 0.3);
    if (m == 2) {
        float g = texHash(floor(px)) - 0.5;
        return g > 0.0 ? vec4(ubuf.texTint.rgb, g * k * 0.5) : vec4(ubuf.texShade.rgb, -g * k * 0.5);
    }
    if (m == 3) {
        float s = max(ubuf.texParam, 4.0);
        vec2 g = abs(fract(px / s - 0.5) - 0.5) * s;
        return vec4(ubuf.texTint.rgb, (1.0 - smoothstep(0.0, 1.0, min(g.x, g.y))) * 0.6 * k);
    }
    if (m == 4) {
        float rim = 1.0 - clamp(-d / 18.0, 0.0, 1.0);
        return vec4(ubuf.texTint.rgb, rim * k * 0.6);
    }
    return vec4(0.0);
}

float sdBox(vec2 p, vec2 c, vec2 hs) {
    vec2 q = abs(p - c) - hs;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0)));
}

float sdRoundBox(vec2 p, vec2 c, vec2 hs, float r) {
    r = min(r, min(hs.x, hs.y));
    vec2 q = abs(p - c) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float sdRoundBox4(vec2 p, vec2 c, vec2 hs, vec4 r) {
    p -= c;
    float rr = (p.x >= 0.0) ? (p.y >= 0.0 ? r.z : r.y) : (p.y >= 0.0 ? r.w : r.x);
    rr = min(rr, min(hs.x, hs.y));
    vec2 q = abs(p) - hs + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rr;
}

float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

// Jelly: stretch along the depth axis about the anchored edge, so the body
// stays joined to the band and only its free edge gives. Applied once per
// slot, before both the distance and the fillet pick.
vec2 jelly(vec2 px, mat4 s) {
    if (s[3].y == 0.0)
        return px;
    vec4 rect = s[0];
    int ax = int(s[3].z + 0.5);
    float depth = max(ax == 1 ? rect.w : rect.z, 1.0);
    float k = depth / max(depth + s[3].y, 1.0);
    if (ax == 1)
        px.y = s[3].w + (px.y - s[3].w) * k;
    else
        px.x = s[3].w + (px.x - s[3].w) * k;
    return px;
}

float chromeDist(vec2 px, mat4 s) {
    vec4 rect = s[0];
    vec2 c = rect.xy + rect.zw * 0.5;
    return sdRoundBox4(px, c, rect.zw * 0.5, s[1]);
}

float chromeK(vec2 px, vec4 rect, vec4 ks) {
    vec2 p = px - (rect.xy + rect.zw * 0.5);
    return (p.x >= 0.0) ? (p.y >= 0.0 ? ks.z : ks.y) : (p.y >= 0.0 ? ks.w : ks.x);
}

// Smooth-union one slot into d (no-op when inactive).
float addSlot(float d, vec2 px, mat4 s) {
    if (s[3].x < 0.5)
        return d;
    vec2 q = jelly(px, s);
    return smin(d, chromeDist(q, s), chromeK(q, s[0], s[2]));
}

float addChrome(float d, vec2 px, mat4 s) {
    if (s[3].x < 0.5)
        return d;
    return min(d, chromeDist(jelly(px, s), s));
}

float sceneDist(vec2 px) {
    vec2 sc = vec2(ubuf.widthPx, ubuf.heightPx) * 0.5;
    float dOuter = sdBox(px, sc, sc);
    vec2 cutC = vec2((ubuf.cutout.x + ubuf.cutout.z) * 0.5, (ubuf.cutout.y + ubuf.cutout.w) * 0.5);
    vec2 cutH = vec2((ubuf.cutout.z - ubuf.cutout.x) * 0.5, (ubuf.cutout.w - ubuf.cutout.y) * 0.5);
    float dCut = sdRoundBox(px, cutC, cutH, ubuf.cutoutRadius);
    float d = max(dOuter, -dCut);
    d = addSlot(d, px, ubuf.slot0);
    d = addSlot(d, px, ubuf.slot1);
    d = addSlot(d, px, ubuf.slot2);
    d = addSlot(d, px, ubuf.slot3);
    d = addSlot(d, px, ubuf.slot4);
    d = addSlot(d, px, ubuf.slot5);
    d = addSlot(d, px, ubuf.slot6);
    d = addSlot(d, px, ubuf.slot7);
    return d;
}

// Distance to the CHROME surfaces only (bar, sidebars, …) — the frame ring is
// excluded. The shadow is derived from this rather than from sceneDist(): the
// ring is the outermost surface, so nothing sits above the desktop for it to cast
// onto, and a ring-derived shadow just bleeds inward across the screen edge and
// darkens whatever window is underneath. Large positive when no chrome is active.
float chromeOnlyDist(vec2 px) {
    float d = 1.0e6;
    d = addChrome(d, px, ubuf.slot0);
    d = addChrome(d, px, ubuf.slot1);
    d = addChrome(d, px, ubuf.slot2);
    d = addChrome(d, px, ubuf.slot3);
    d = addChrome(d, px, ubuf.slot4);
    d = addChrome(d, px, ubuf.slot5);
    d = addChrome(d, px, ubuf.slot6);
    d = addChrome(d, px, ubuf.slot7);
    return d;
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(ubuf.widthPx, ubuf.heightPx);
    float d = sceneDist(px);
    float fw = max(fwidth(d), 1e-4);
    float cov = 1.0 - smoothstep(-fw, fw, d);
    vec3 fill = ubuf.surfaceColor.rgb;
    if (ubuf.texMode > 0.5) {
        vec4 t = lookTexture(px, d);
        fill = mix(fill, t.rgb, clamp(t.a, 0.0, 1.0));
    }
    // Glass: a light rim along the silhouette's edge, brightest top-left.
    float rimA = 0.0;
    if (ubuf.glassEdge.a > 0.0) {
        vec2 uvn = px / vec2(ubuf.widthPx, ubuf.heightPx);
        float dirLight = clamp(1.25 - (uvn.x * 0.6 + uvn.y), 0.0, 1.0);
        rimA = (1.0 - smoothstep(0.0, 2.5, -d)) * (0.35 + 0.65 * dirLight) * ubuf.glassEdge.a;
        fill = mix(fill, ubuf.glassEdge.rgb, clamp(rimA, 0.0, 1.0));
    }
    vec4 col = vec4(fill, 1.0) * cov;
    if (ubuf.shadowColor.a > 0.0) {
        // Shadow comes from the chrome surfaces ONLY — see chromeOnlyDist().
        float ds = chromeOnlyDist(px);
        float dk = chromeOnlyDist(px - ubuf.shadowParam.zw) - ubuf.shadowParam.y;
        float bk = max(ubuf.shadowParam.x, fw);
        float covK = 1.0 - smoothstep(-bk, bk, dk);
        float ba = max(ubuf.ambientParam.x, fw);
        float covA = 1.0 - smoothstep(-ba, ba, ds - ubuf.ambientParam.y);
        float sh = 1.0 - (1.0 - covK * ubuf.shadowColor.a) * (1.0 - covA * ubuf.ambientParam.z);
        col += vec4(ubuf.shadowColor.rgb, 1.0) * (sh * (1.0 - col.a));
    }
    fragColor = col * (ubuf.surfaceColor.a * ubuf.qt_Opacity);
}
