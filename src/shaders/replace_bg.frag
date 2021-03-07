#version 330 core
in vec3 v_BgColor;

uniform sampler2D u_FgColor;

layout (location = 0) out vec3 o_Color;
layout (location = 1) out vec3 o_BgColor;

void main()
{
    vec4 FgColor = texelFetch(u_FgColor, ivec2(gl_FragCoord.xy), 0);
    float Mask = FgColor.a;
    o_BgColor = v_BgColor;
    o_Color = mix(o_BgColor, FgColor.rgb, Mask);
}
