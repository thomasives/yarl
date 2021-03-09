#version 330 core
layout (location = 0) in vec2 a_CellOffset;
layout (location = 1) in vec3 a_Color;

layout (std140) uniform Console {
    vec2 u_CellScale;
    vec2 u_Offset;
};

const vec2 c_Pos[4] = vec2[4](
    vec2(0.0f, 0.0f),
    vec2(1.0f, 0.0f),
    vec2(0.0f, 1.0f),
    vec2(1.0f, 1.0f)
);

const vec2 c_Uv[4] = vec2[4](
    vec2(0.0f, 0.0f),
    vec2(1.0f, 0.0f),
    vec2(0.0f, 1.0f),
    vec2(1.0f, 1.0f)
);

out vec3 v_BgColor;

void main()
{
    v_BgColor = a_Color;

    vec2 Pos = a_CellOffset + c_Pos[gl_VertexID];
    gl_Position = vec4(u_CellScale * (Pos + u_Offset) + vec2(-1.0, -1.0), 0.0f, 1.0f);
}
