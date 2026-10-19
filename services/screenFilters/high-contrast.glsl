#version 300 es
// AnoShell screen filter (services/ScreenFilters.qml): high contrast
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 v = clamp((c.rgb - 0.5) * 1.6 + 0.5, 0.0, 1.0);
    fragColor = vec4(v, c.a);
}
