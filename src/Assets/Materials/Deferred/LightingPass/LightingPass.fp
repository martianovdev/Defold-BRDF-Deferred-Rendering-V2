#version 140

// =====================================================================================
// Deferred Lighting Pass Fragment Shader
// Performs lighting calculations using G-buffer data and applies volumetric lighting.
// Uses Eevee-like BRDF with shadow mapping and tonemapping for final output.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// ============ I/O & UNIFORMS ============
// New albedo sampler - must be first
uniform sampler2D texture_albedo;

uniform sampler2D texture_normal;
uniform sampler2D texture_shadowmap;
uniform sampler2D texture_depth_full;
uniform sampler2D texture_tiled_lighting;

uniform data { uniform vec4 size; };

uniform camera {
    uniform mediump mat4 mtx_camera_projection;
    uniform mediump mat4 mtx_camera_projection_inv;
    uniform mediump mat4 mtx_camera_view;
    uniform mediump mat4 mtx_camera_view_inv;
};

uniform light_data {
    uniform vec4 light_count;
    uniform mat4 light_transform_array[64];
    uniform vec4 light_color_array[64];
    uniform vec4 light_properties_array[64];
};

uniform eevee_settings { uniform vec4 scene_env; };

vec3 worldColor = vec3(1.0);

out vec4 out_color;
out vec4 out_depth;

// Include shadows and lighting module
#include "/src/Assets/Materials/Deferred/Modules/eevee_lighting.glsl"

// ============ POSITION RECON ============
vec3 ReconstructView(vec2 uv, float deviceDepth){
    vec2 ndc = uv*2.0 - 1.0;
    vec4 clip = vec4(ndc, deviceDepth*2.0 - 1.0, 1.0);
    vec4 view = mtx_camera_projection_inv * clip;
    return (view / max(view.w, 1e-6)).xyz;
}
vec3 ReconstructWorld(vec2 uv, float deviceDepth){
    return (mtx_camera_view_inv * vec4(ReconstructView(uv, deviceDepth),1.0)).xyz;
}

// ============ MATERIAL ============
vec3 AlbedoTex(vec2 uv){ return texture(texture_albedo, uv).rgb; }



#include "/src/Assets/Materials/Deferred/Modules/volumetric.glsl"
#include "/src/Assets/Materials/Deferred/Modules/tonemap.glsl"

void main(){
    vec2 uv = (gl_FragCoord.xy + 0.5) / size.xy;

    vec4 gbNRER = texture(texture_normal, uv); if(gbNRER.r > 100.0){ discard; }
    float deviceDepth = texture(texture_depth_full, uv).x; if(deviceDepth > 100.0){ discard; }

    vec3 baseColor = AlbedoTex(uv) * worldColor;
    float roughness = clamp(gbNRER.w, 0.0, 1.0);
    float metallic  = 0.5;
    float specular  = 2.5;
    vec3  N         = normalize(gbNRER.xyz * 2.0 - 1.0);

    vec3 P      = ReconstructWorld(uv, deviceDepth);
    vec3 camPos = (mtx_camera_view_inv[3]).xyz;
    vec3 V      = normalize(camPos - P);

    // Single module call. It handles tiles and shadows itself.
    vec3 lit = EEVEE_Shade_eval(
        P, N, V,
        baseColor, roughness, metallic, specular,
        worldColor, scene_env,
        size,
        texture_tiled_lighting, texture_shadowmap
    );

    vec3 volumtric = volumetric(P, camPos, texture_depth_full);

    // Tonemapping and output parameters
    // tonemapMode: 0 none, 1 ACES, 2 AGX_APPROX, 3 AGX_LUT
    float exposureEV = 2.0;       // EV, multiplier 2^EV
    float gammaOut = 1.5;         // usually 2.2
    float agxSaturation = 1.0;    // additional saturation control AGX approx [0..1], 1 by default
    vec3 ldr = tonemap(lit+volumtric/4, max(gammaOut, 1e-6), saturate(agxSaturation));

    out_color = vec4(ldr, 1.0);
}
