#version 140

// =====================================================================================
// Billboard Fragment Shader
// Renders billboard sprites with alpha testing for point light visualization.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 v_uv;
out vec4 out_fragColor;

uniform sampler2D tex0;

void main()
{
    vec4 color = texture(tex0, v_uv);
    if(color.a == 0.0){
        discard;
    }
    out_fragColor = color;
}
