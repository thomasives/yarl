#version 330 core
in vec3 v_BgColor;

layout (location = 0) out vec3 o_BgColor;

void main()
{
    o_BgColor = v_BgColor;
}
