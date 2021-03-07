#version 330 core
in vec3 v_FgColor;
in vec3 v_BgColor;
in vec3 v_Uv;

uniform sampler2DArray u_Font;

layout (location = 0) out vec3 o_Color;
layout (location = 1) out vec3 o_BgColor;


void main()
{
    o_BgColor = v_BgColor;
    o_Color = mix(v_BgColor, v_FgColor, texture(u_Font, v_Uv).r);
}
