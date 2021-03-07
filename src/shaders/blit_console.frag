#version 330 core
in vec2 v_Uv;

uniform sampler2D u_FgColor;
uniform sampler2D u_BgColor;

layout (location = 0) out vec4 o_Color;

void main()
{
    vec3 BgColor = texture(u_BgColor, v_Uv).rgb;
    vec4 FgColor = texture(u_FgColor, v_Uv);
    float Mask = FgColor.a;
    o_Color = vec4(mix(BgColor, FgColor.rgb, Mask), 1.0);
}
