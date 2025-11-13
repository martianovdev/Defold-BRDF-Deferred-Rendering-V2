#version 140

// =====================================================================================
// Depth Pass Fragment Shader
// Renders scene depth for shadow map generation. Outputs linear distance from origin.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec4 var_position;       
in vec4 var_position_clip; 
in vec3 var_normal;
in vec2 var_texcoord0;

out vec4 fragColor0;

void main(){
    fragColor0 = vec4(vec3(length(var_position.xyz)), 1.0);
}