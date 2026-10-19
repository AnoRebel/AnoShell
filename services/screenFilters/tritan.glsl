#version 300 es
// AnoShell screen filter (services/ScreenFilters.qml): tritanopia correction
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
const mat3 SIM = mat3(1.0, 0.0, -0.395913, 0.0, 1.0, 0.801109, 0.0, 0.0, 0.0);
const mat3 RGB2LMS = mat3(17.8824, 3.45565, 0.0299566, 43.5161, 27.1554, 0.184309, 4.11935, 3.86714, 1.46709);
const mat3 LMS2RGB = mat3(0.0809444479, -0.0102485335, -0.000365296938, -0.130504409, 0.0540193266, -0.00412161469, 0.116721066, -0.113614708, 0.693511405);
void main() {
    vec4 c = texture(tex, v_texcoord);
    vec3 lms = RGB2LMS * c.rgb;
    vec3 sim = SIM * lms;
    vec3 err = c.rgb - LMS2RGB * sim;
    vec3 shift = vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
    fragColor = vec4(clamp(c.rgb + shift, 0.0, 1.0), c.a);
}
