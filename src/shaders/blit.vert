#version 330 core
const vec2 c_Pos[4] = vec2[4](
    vec2(-1.0f, -1.0f),
    vec2(1.0f, -1.0f),
    vec2(-1.0f, 1.0f),
    vec2(1.0f, 1.0f)
);

const vec2 c_Uv[4] = vec2[4](
    vec2(0.0f, 0.0f),
    vec2(1.0f, 0.0f),
    vec2(0.0f, 1.0f),
    vec2(1.0f, 1.0f)
);

out vec2 v_Uv;

void main()
{
    v_Uv = c_Uv[gl_VertexID];

    gl_Position = vec4(c_Pos[gl_VertexID], 0.0f, 1.0f);
}
