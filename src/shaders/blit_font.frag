#version 330 core
in vec2 v_Uv;

uniform sampler2D u_Font;

layout (location = 0) out float o_Color;

void main()
{
    o_Color = texture(u_Font, v_Uv).g;
}
