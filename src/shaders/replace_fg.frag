#version 330 core
in vec3 v_FgColor;
in vec3 v_Uv;

uniform sampler2DArray u_Font;
uniform sampler2D u_BgColor;

layout (location = 0) out vec3 o_Color;

void main()
{
    vec3 BgColor = texelFetch(u_BgColor, ivec2(gl_FragCoord.xy), 0).rgb;
    o_Color = mix(BgColor, v_FgColor, texture(u_Font, v_Uv).r);
}
