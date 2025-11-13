#version 140

// =====================================================================================
// Sphere Debug Material Fragment Shader
// Simple unlit shader for rendering light source visualization spheres.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in highp vec4 var_position;
in mediump vec3 var_normal;
in mediump vec2 var_texcoord0;
in mediump vec4 var_light;

out vec4 out_fragColor;


uniform fs_uniforms
{
    mediump vec4 tint;
};

void main()
{
    out_fragColor = vec4(1.0);
}

