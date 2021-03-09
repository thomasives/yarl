#version 330 core
layout (location = 0) in vec2 a_CellOffset;
layout (location = 1) in float a_Depth;
layout (location = 2) in vec3 a_Color;
layout (location = 3) in int a_CodePoint;
layout (location = 4) in int a_FontId;

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

out vec3 v_FgColor;
out vec3 v_Uv;

void main()
{
    v_FgColor = a_Color;
    vec2 Uv = c_Uv[gl_VertexID] + vec2(
            a_CodePoint & 0x0F, 
            15.0 - float(a_CodePoint >> 4));
    v_Uv = vec3((1.0 / 16.0) * Uv, float(a_FontId));

    vec2 Pos = a_CellOffset + c_Pos[gl_VertexID];
    gl_Position = vec4(u_CellScale * (Pos + u_Offset) + vec2(-1.0, -1.0), a_Depth, 1.0f);
}
