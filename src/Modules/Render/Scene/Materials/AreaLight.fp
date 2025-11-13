#version 140

// =====================================================================================
// Area Light Fragment Shader
// Renders area light quads with alpha testing for area light visualization.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 v_uv;
out vec4 out_fragColor;

uniform sampler2D albedo;

void main()
{
    vec4 color = texture(albedo, v_uv);
    if(color.a == 0.0){
        discard;
    }
    out_fragColor = color;
}
