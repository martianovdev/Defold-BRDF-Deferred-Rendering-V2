#version 140

// =====================================================================================
// Glass Material Fragment Shader
// Physically-based glass rendering with screen-space refraction, Fresnel reflections,
// and IOR-based transmission. Supports refractive distortion and tinting.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 var_texcoord0;

uniform sampler2D _backgroundMap;
uniform sampler2D _depthMap;
uniform sampler2D albedoMap;
uniform sampler2D normalMap;
uniform sampler2D roughnessMap;
uniform sampler2D emissiveMap;

uniform fs_uniforms {
    vec4 size;
};
uniform eevee_settings { 
    vec4 scene_env; 
};

uniform camera {
    mat4 mtx_camera_projection;
    mat4 mtx_camera_projection_inv;
    mat4 mtx_camera_view;
    mat4 mtx_camera_view_inv;
};

in vec3 vWorldPos;
in vec3 vWorldNormal;
in vec3 vT;
in vec3 vB;
in vec4 var_position;

uniform light_data {
    vec4 light_count;
    mat4 light_transform_array[64];
    vec4 light_color_array[64];
    vec4 light_properties_array[64];
};

// ---------------------------
// Glass material parameters
// ---------------------------
float u_Transmission = 0.1;      // 0..1, model transparency, e.g. 0.6
float u_IOR = 1.45;               // index of refraction, 1.0..2.0, e.g. 1.45
float u_RefractionStrength = 0.03;// background sample offset strength, e.g. 0.015
float u_FresnelPower = 5.0;      // Fresnel power, e.g. 5.0
float u_RefractionTint = 1.0;    // how much to mix albedo into refraction 0..1

vec3 buildWorldNormal(vec3 normalSample, vec3 T, vec3 B, vec3 Nw) {
    vec3 Nt = normalize(normalSample * 2.0 - 1.0);
    mat3 TBN = mat3(normalize(T), normalize(B), normalize(Nw));
    return normalize(TBN * Nt);
}


float fresnel_schlick(float cosTheta, float F0, float powerMul) {
    // classic Schlick approximation with additional enhancement
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, max(1.0, powerMul));
}

#include "/src/Assets/Materials/Deferred/Modules/tonemap.glsl"

out vec4 out_color;
out vec3 out_color1;

void main() {
    vec2 screen_uv = gl_FragCoord.xy / size.xy;

    vec4 background = texture(_backgroundMap, screen_uv);
    vec4 depth      = texture(_depthMap,     screen_uv);
    vec4 albedo     = texture(albedoMap,     var_texcoord0);
    vec4 normalTex  = texture(normalMap,     var_texcoord0);
    vec4 roughness  = texture(roughnessMap,  var_texcoord0);
    vec4 emissive   = texture(emissiveMap,   var_texcoord0);

    // depth culling as before
    if (gl_FragCoord.z > depth.r) {
        discard;
        return;
    }

    #ifdef EDITOR
    out_color = vec4((background.rgb+depth.rgb)*0.01+albedo.rgb, 1.0);
    return;
    #else
    // Camera
    vec3 camPos = mtx_camera_view_inv[3].xyz;

    // Geometry and basic PBR
    vec3 P = vWorldPos.xyz;
    vec3 N = buildWorldNormal(normalTex.xyz, vT, vB, vWorldNormal);
    vec3 V = normalize(camPos - vWorldPos);

    vec3 worldColor = vec3(1.0);
    float metallic  = 0.0; // glass is not metal
    float specular  = 2.5;



    // ---------------------------
    // Cheap screen-space refraction
    // ---------------------------
    // closer to camera, less offset to prevent geometry "swimming"
    float viewDepth = max(-var_position.z, 1e-3);

    // offset strength from normal
    // use only N.xy in screen space
    float eta = 1.0 / max(u_IOR, 1e-3);
    vec2 refrOffset = N.xy * u_RefractionStrength * eta / viewDepth;

    // sample background with offset
    vec2 refrUV = saturate(screen_uv + refrOffset);
    vec3 refractedCol = texture(_backgroundMap, refrUV).rgb;

    // light refraction tint with material color
    refractedCol = mix(refractedCol, refractedCol * albedo.rgb, saturate(u_RefractionTint));

    // Fresnel for mixing reflection/refraction
    // F0 can be approximated via IOR: F0 = ((ior - 1)/(ior + 1))^2
    float F0 = pow((u_IOR - 1.0) / (u_IOR + 1.0), 2.0);
    float cosNV = saturate(dot(normalize(N), normalize(V)));
    float fres  = fresnel_schlick(cosNV, F0, u_FresnelPower);

    // final linear color: some reflection (lit), some refraction
    vec3 combined = mix(refractedCol, refractedCol, fres);

    // Tonemapping
    float exposureEV = 2.0;
    float gammaOut = 1.5;
    float agxSaturation = 1.0;

    // can add weak emissive on top
    combined += emissive.rgb;

    vec3 ldr = tonemap(combined, max(gammaOut, 1e-6), saturate(agxSaturation));

    // Alpha controls transparency. Keep control from uniform.
    float alphaOut = saturate(u_Transmission);

    out_color = vec4(ldr, alphaOut);
    out_color1 = vec3(1.0);
    #endif
}