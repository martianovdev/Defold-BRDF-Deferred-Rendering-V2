#version 140

// =====================================================================================
// Render Root Fragment Shader
// Root rendering pass fragment shader for UI and overlay rendering.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 var_texcoord0;
in vec3 u_local_position;
in vec4 var_color;

uniform sampler2D texture_sampler;

uniform base_uniforms{
    uniform vec4 tint;
    uniform vec4 surface_size;
};


out vec4 fragColor0;

void main()
{
    vec2 uv = u_local_position.xy/surface_size.xy + 0.5;
  
    vec4 tint_pm = vec4(tint.xyz * tint.w, tint.w);
    vec4 tex = texture(texture_sampler, uv) * tint_pm;

    vec4 finalColor = tex;

    fragColor0 = finalColor;
}
