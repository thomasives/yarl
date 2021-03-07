#version 330 core
in vec2 v_Uv;

uniform sampler2D u_Console;

layout (location = 0) out vec4 o_Color;

void main()
{
    o_Color = vec4(texture(u_Console, v_Uv).rgb, 1.0);
}
