#version 330 core
in vec3 v_FgColor;
in vec3 v_BgColor;
in vec3 v_Uv;

uniform sampler2DArray u_Font;

out vec4 o_Color;

void main()
{
    o_Color = vec4(mix(v_BgColor, v_FgColor, texture(u_Font, v_Uv).r), 1.0);
}
