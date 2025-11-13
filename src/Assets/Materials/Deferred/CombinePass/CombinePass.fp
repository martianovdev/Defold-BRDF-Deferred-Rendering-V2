#version 140

// =====================================================================================
// Combine Pass Fragment Shader
// Combines lighting, glass, and SSAO buffers into final rendered image.
// Applies ambient occlusion with brightness-aware blending to preserve highlights.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

uniform sampler2D u_albedo;     
uniform sampler2D u_glass; 
uniform sampler2D u_ssao;

// size.xy = output framebuffer resolution
uniform data {
    uniform vec4 size;
};

out vec4 fragColor;


void main(){
    vec2 uv = gl_FragCoord.xy / size.xy;

    vec4 albedo = texture(u_albedo, uv);
    vec4 glass = texture(u_glass, uv);
    float ssao = texture(u_ssao, uv).r; // SSAO value (0 = fully occluded, 1 = no occlusion)

    vec3 color = albedo.rgb;
    if(glass.a > 0.0){
        color = glass.rgb;
    }
    
    // Apply SSAO only to darker areas (ambient component)
    // Preserve bright areas (direct lighting and volumetric lighting)
    // SSAO value: 0 = fully occluded, 1 = no occlusion
    float brightness = max(max(color.r, color.g), color.b);
    float ssaoInfluence = mix(0.3, 1.0, brightness); // Less SSAO effect on bright areas
    float ssaoFactor = mix(0.6, 1.0, ssao);
    color *= mix(1.0, ssaoFactor, ssaoInfluence);
    
    fragColor = vec4(color, 1.0);
}
