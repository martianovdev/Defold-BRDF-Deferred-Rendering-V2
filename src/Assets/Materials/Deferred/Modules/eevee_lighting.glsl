// =====================================================================================
// Eevee-like Lighting Module
// Blender Eevee-style PBR lighting implementation with GGX BRDF, shadow mapping,
// and tiled light culling. Supports point and spot lights with physical attenuation.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// Requires that the following are already declared in the including shader:
// - uniform vec4 size;                             // from data block
// - sampler2D texture_tiled_lighting;
// - sampler2D texture_shadowmap;
// - uniform vec4 scene_env;                        // from eevee_settings
// - light buffers: light_count, light_transform_array, light_color_array, light_properties_array
// - #include "/src/Assets/Materials/Deferred/Modules/lighting_shadow.glsl" (or below - already included here)

// ============ SHADOWS ============
#include "/src/Assets/Materials/Deferred/Modules/lighting_shadow.glsl"

// ============ HELPERS ============
float EEVEE_sat1(float x){ return clamp(x, 0.0, 1.0); }
vec3  EEVEE_sat3(vec3  x){ return clamp(x, 0.0, 1.0); }

const float EEVEE_PI = 3.14159265359;

// de Bruijn for 24-bit masks
const uint EEVEE_DEBRUIJN32 = 0x077CB531u;
const uint EEVEE_debruijnIdx32[32] = uint[32](
    0u, 1u, 28u, 2u, 29u, 14u, 24u, 3u,
    30u, 22u, 20u, 15u, 25u, 17u, 4u, 8u,
    31u, 27u, 13u, 23u, 21u, 19u, 16u, 7u,
    26u, 12u, 18u, 6u, 11u, 5u, 10u, 9u
);
uint EEVEE_ctz32(uint m){
    uint lsb = m & (~m + 1u);
    return EEVEE_debruijnIdx32[(lsb * EEVEE_DEBRUIJN32) >> 27];
}

// ============ LIGHT DATA ============
struct EEVEE_LightParams {
    int   type;             // 0 point, 1 spot
    vec3  pos;
    vec3  dir;
    vec3  color;
    float powerW;
    float radiusSurface;
    bool  shadows;
    float specularScale;
    float diffuseScale;
    float spotInnerCos;
    float spotOuterCos;
};

struct EEVEE_LightSample {
    vec3  L;
    float NdotL;
    float attenuation;
    float distance;
};

EEVEE_LightParams EEVEE_Light_read(int idx){
    EEVEE_LightParams L;
    L.type          = int(light_properties_array[idx].x + 0.5);
    L.pos           = light_transform_array[idx][3].xyz;
    L.dir           = normalize(-light_transform_array[idx][2].xyz);
    L.color         = light_color_array[idx].xyz;
    L.powerW        = max(light_color_array[idx].w, 0.0);
    L.radiusSurface = max(light_properties_array[idx].y, 0.0);
    L.shadows       = bool(light_properties_array[idx].w);
    L.specularScale = 3.0;
    L.diffuseScale  = 1.0;
    L.spotOuterCos  = cos(radians(45.0));
    L.spotInnerCos  = cos(radians(20.0));
    return L;
}

EEVEE_LightSample EEVEE_Light_samplePoint(vec3 P, vec3 N, EEVEE_LightParams Lp){
    EEVEE_LightSample s;
    vec3 toL = Lp.pos - P;
    float d  = length(toL);
    vec3 L   = (d > 0.0) ? toL / d : vec3(0.0,0.0,1.0);
    float rEff = max(d, Lp.radiusSurface);
    s.L = L;
    s.distance = d;
    s.NdotL = max(dot(N, L), 0.0);
    s.attenuation = 1.0 / max(rEff * rEff, 1e-6);
    return s;
}

EEVEE_LightSample EEVEE_Light_sampleSpot(vec3 P, vec3 N, EEVEE_LightParams Lp){
    EEVEE_LightSample s = EEVEE_Light_samplePoint(P, N, Lp);
    vec3  L_lightSpace = normalize(P - Lp.pos);
    float cosTheta = dot(L_lightSpace, Lp.dir);
    float spotFactor = EEVEE_sat1((cosTheta - Lp.spotOuterCos) / max(Lp.spotInnerCos - Lp.spotOuterCos, 1e-6));
    spotFactor *= spotFactor;
    s.attenuation *= spotFactor;
    return s;
}

// ============ BRDF ============
float  EEVEE_BRDF_ggx_D(float a, float NdotH){
    float a2 = a*a;
    float d  = (NdotH*NdotH)*(a2-1.0)+1.0;
    return a2 / max(EEVEE_PI * d * d, 1e-7);
}
float  EEVEE_BRDF_smithG(float a, float NdotV, float NdotL){
    float a2 = a*a;
    float gv = NdotL * sqrt(max(NdotV*NdotV*(1.0-a2)+a2, 1e-7));
    float gl = NdotV * sqrt(max(NdotL*NdotL*(1.0-a2)+a2, 1e-7));
    float g  = gv + gl;
    return (g > 0.0) ? (2.0 * NdotL * NdotV / g) : 0.0;
}
vec3   EEVEE_BRDF_fresnel(vec3 F0, float VdotH){
    float f = pow(1.0 - VdotH, 5.0);
    return F0 + (1.0 - F0) * f;
}
vec3   EEVEE_BRDF_energyComp(vec3 F0, float roughness){
    float k = 1.0 + 0.25 * roughness;
    float m = max(max(F0.r,F0.g),F0.b);
    return mix(vec3(1.0), vec3(k), EEVEE_sat1(m));
}
// Burley diffuse (Disney principled diffuse)
float  EEVEE_BRDF_burley_diffuse(float NdotV, float NdotL, float LdotH, float roughness){
    float FD90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
    float FdV = 1.0 + (FD90 - 1.0) * pow(1.0 - NdotV, 5.0);
    float FdL = 1.0 + (FD90 - 1.0) * pow(1.0 - NdotL, 5.0);
    return FdV * FdL / EEVEE_PI;
}
vec3   EEVEE_BRDF_eval(
    vec3 N, vec3 V, float NdotV,
    float a, vec3 F0, vec3 baseColorDiff,
    vec3 L, float NdotL,
    vec3 radiance,
    float specularScale, float diffuseScale)
{
    vec3  H     = normalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);
    float LdotH = max(dot(L, H), 0.0);

    float D = EEVEE_BRDF_ggx_D(a, NdotH);
    float G = EEVEE_BRDF_smithG(a, NdotV, NdotL);
    vec3  F = EEVEE_BRDF_fresnel(F0, VdotH);

    vec3  specBRDF = (D * G) * F / max(4.0 * NdotV * NdotL, 1e-6);
    specBRDF *= EEVEE_BRDF_energyComp(F0, a > 0.0 ? sqrt(a) : 0.0);

    // Burley diffuse instead of simple Lambertian
    float roughness = a > 0.0 ? sqrt(a) : 0.0;
    float burleyDiff = EEVEE_BRDF_burley_diffuse(NdotV, NdotL, LdotH, roughness);
    vec3  diffBRDF = baseColorDiff * burleyDiff;
    
    vec3  diffuse   = diffBRDF * (radiance * NdotL) * diffuseScale;
    vec3  specularL = specBRDF * (radiance * NdotL) * specularScale;
    return diffuse + specularL;
}

// ============ TILED ============
uint EEVEE_Tiled_readMask(ivec2 tc, vec2 tiledTexSizeF, sampler2D tiledTex){
    tc = clamp(tc, ivec2(0), ivec2(tiledTexSizeF) - ivec2(1));
    vec2 uvTile = (vec2(tc) + 0.5) / tiledTexSizeF;
    float packedMask = texture(tiledTex, uvTile).r;
    return uint(floor(packedMask + 0.5)) & 0xFFFFFFu;
}

vec3 EEVEE_Lighting_accumulate(
    vec3 P, vec3 N, vec3 V, float NdotV,
    float a, vec3 F0, vec3 baseColorDiff,
    sampler2D tiledLightingTex, sampler2D shadowMap,
    vec4 sceneEnv, vec2 viewportSize)
{
    // Define tile grid ourselves, user doesn't need to think about it
    vec2  tiledTexSizeF = viewportSize / 10.0;
    ivec2 tileCoord = ivec2(floor(gl_FragCoord.xy * tiledTexSizeF / viewportSize));
    tileCoord = clamp(tileCoord, ivec2(0), ivec2(tiledTexSizeF) - ivec2(1));

    vec3 Lo = vec3(0.0);

    // Gather 3x3 mask
    uint combinedMask = 0u;
    for (int oy = -1; oy <= 1; ++oy){
        for (int ox = -1; ox <= 1; ++ox){
            combinedMask |= EEVEE_Tiled_readMask(tileCoord + ivec2(ox, oy), tiledTexSizeF, tiledLightingTex);
        }
    }
    uint m = combinedMask & 0xFFFFFFu;

    // Iterate over bits
    while (m != 0u){
        uint i = EEVEE_ctz32(m);
        m ^= (1u << i);

        EEVEE_LightParams Lp = EEVEE_Light_read(int(i));
        if (Lp.type != 0 && Lp.type != 1) continue;

        EEVEE_LightSample s = (Lp.type == 0)
            ? EEVEE_Light_samplePoint(P, N, Lp)
            : EEVEE_Light_sampleSpot(P, N, Lp);
        if (s.NdotL <= 0.0) continue;

        float shadow = 1.0;
        if (Lp.shadows){
            shadow = shadow_computeSoft(P, N, Lp.pos, shadowMap, int(i));
            if (shadow <= 0.0) continue;
            shadow = EEVEE_sat1(shadow);
        }

        vec3 radiance = Lp.color * Lp.powerW * sceneEnv.z * s.attenuation;
        float luma = dot(radiance, vec3(0.2126, 0.7152, 0.0722));
        if (luma < sceneEnv.y) continue;

        Lo += EEVEE_BRDF_eval(
            N, V, NdotV, a, F0, baseColorDiff,
            s.L, s.NdotL, radiance, Lp.specularScale, Lp.diffuseScale
        ) * shadow;
    }

    return Lo;
}

// ============ PUBLIC API ============
// Single entry point. Calculates tiles, shadows, etc. itself.
vec3 EEVEE_Shade_eval(
    vec3 P,                  // world pos
    vec3 N,                  // normal (unit)
    vec3 V,                  // view dir to camera (unit)
    vec3 baseColor,          // linear albedo
    float roughness,         // [0..1]
    float metallic,          // [0..1]
    float specular,          // ~[0..8]
    vec3 worldColorArg,      // ambient base
    vec4 sceneEnvArg,        // scene_env copy
    vec4 viewportSizeArg,    // size uniform, pass as is (xy = viewport)
    sampler2D tiledLightingTex,
    sampler2D shadowMapTex
){
    float NdotV = max(dot(N, V), 0.0);

    vec3  F0_dielectric = vec3(0.04) * specular * 2.0;
    vec3  F0            = mix(F0_dielectric, baseColor, metallic);
    vec3  baseColorDiff = baseColor * (1.0 - metallic);
    float a             = max(0.001, roughness * roughness);

    vec3 Lo = EEVEE_Lighting_accumulate(
        P, N, V, NdotV, a, F0, baseColorDiff,
        tiledLightingTex, shadowMapTex,
        sceneEnvArg, viewportSizeArg.xy
    );

    vec3 ambient = worldColorArg * sceneEnvArg.w;
    
    // Burley diffuse for ambient with averaged value (NdotL ~ 0.5, LdotH ~ 0.7 for diffuse lighting)
    float ambientBurley = EEVEE_BRDF_burley_diffuse(NdotV, 0.5, 0.7, roughness);
    vec3 diffuseAmbient = baseColorDiff * ambientBurley * ambient;

    float sceneExposure = exp2(sceneEnvArg.x);

    return (Lo + diffuseAmbient) * sceneExposure;
}
