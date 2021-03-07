#version 330 core
in vec3 v_FgColor;
in vec3 v_Uv;

uniform sampler2DArray u_Font;
uniform sampler2D u_BgColor;

layout (location = 0) out vec3 o_Color;
layout (location = 1) out vec4 o_FgColor;

void main()
{
    float Mask = texture(u_Font, v_Uv).r;
    vec3 BgColor = texelFetch(u_BgColor, ivec2(gl_FragCoord.xy), 0).rgb;
    o_FgColor = vec4(v_FgColor, Mask);
    o_Color = mix(BgColor, v_FgColor, Mask);
}
