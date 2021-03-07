#version 330 core
in vec3 v_FgColor;
in vec3 v_Uv;

uniform sampler2DArray u_Font;

layout (location = 0) out vec4 o_FgColor;

void main()
{
    float Mask = texture(u_Font, v_Uv).r;
    o_FgColor = vec4(v_FgColor, Mask);
}
