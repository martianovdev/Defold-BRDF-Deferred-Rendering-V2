#version 140

// =====================================================================================
// Forward Model Fragment Shader
// Forward rendering shader with Eevee-like lighting, tiled light culling, and tonemapping.
// Supports PBR materials with albedo, normal, roughness, and emissive maps.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 var_texcoord0;

uniform sampler2D tileLightMap;
uniform sampler2D shadowMap;
uniform sampler2D albedoMap;
uniform sampler2D normalMap;
uniform sampler2D roughnessMap;
uniform sampler2D emissiveMap;

// Optional LUT for precise AGX (if not set, AGX Approx will be used)
uniform sampler3D agxLut;

out vec4 out_color;

uniform fs_uniforms {
    vec4 tint;
    vec4 size; // xy = screen size in pixels
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

#include "/src/Assets/Materials/Deferred/Modules/lighting_shadow.glsl"

uniform light_data {
    uniform vec4 light_count;
    uniform mat4 light_transform_array[64];
    uniform vec4 light_color_array[64];
    uniform vec4 light_properties_array[64];
};

// Tonemapping and output parameters
// tonemapMode: 0 none, 1 ACES, 2 AGX_APPROX, 3 AGX_LUT
float exposureEV = 1.0;       // EV, multiplier 2^EV
int   tonemapMode = 2;      // see above
float gammaOut = 1.5;         // usually 2.2
float agxSaturation = 0.8;    // additional saturation control AGX approx [0..1], 1 by default

// Default value if uniform tonemapMode == 0
#ifndef TONEMAP_DEFAULT_MODE
#define TONEMAP_DEFAULT_MODE 2 // AGX_APPROX
#endif

// ========================================
// Types
// ========================================
struct LightParams {
    int   type;             // 0 = point, 1 = spot
    vec3  pos;              // world
    vec3  dir;              // world, normalized
    vec3  color;            // RGB
    float powerW;           // radiometric power/scale
    float radiusSurface;    // reserved
    bool  shadows;
    float specularScale;
    float diffuseScale;
    float spotInnerCos;     // cos(inner half-angle)
    float spotOuterCos;     // cos(outer half-angle)
};

// ========================================
// Utilities
// ========================================
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec3  saturate(vec3 v)  { return clamp(v, 0.0, 1.0); }

// de Bruijn for 32 bits
uint ctz32(uint m) {
    const uint DEBRUIJN32 = 0x077CB531u;
    const uint debruijnIdx32[32] = uint[32](
        0u, 1u, 28u, 2u, 29u, 14u, 24u, 3u,
        30u, 22u, 20u, 15u, 25u, 17u, 4u, 8u,
        31u, 27u, 13u, 23u, 21u, 19u, 16u, 7u,
        26u, 12u, 18u, 6u, 11u, 5u, 10u, 9u
    );
    uint lsb = m & (~m + 1u);
    return debruijnIdx32[(lsb * DEBRUIJN32) >> 27];
}

vec3 buildWorldNormal(vec3 normalSample, vec3 T, vec3 B, vec3 Nw) {
    vec3 Nt = normalize(normalSample * 2.0 - 1.0);
    mat3 TBN = mat3(normalize(T), normalize(B), normalize(Nw));
    return normalize(TBN * Nt);
}

// ========================================
// Tile masks
// ========================================
uint readTileMaskAt(sampler2D tileLM, ivec2 tc, vec2 tiledTexSizeF) {
    ivec2 clamped = clamp(tc, ivec2(0), ivec2(tiledTexSizeF) - ivec2(1));
    vec2 uvTile = (vec2(clamped) + 0.5) / tiledTexSizeF;
    float packedMask = texture(tileLM, uvTile).r;
    return uint(floor(packedMask + 0.5)) & 0xFFFFFFu;
}

uint gatherCombinedMask3x3(sampler2D tileLM, ivec2 tileCoord, vec2 tiledTexSizeF) {
    uint combined = 0u;
    for (int oy = -1; oy <= 1; ++oy)
    for (int ox = -1; ox <= 1; ++ox)
    combined |= readTileMaskAt(tileLM, tileCoord + ivec2(ox, oy), tiledTexSizeF);
    return combined & 0xFFFFFFu;
}

// ========================================
// Light source decoder
// ========================================
LightParams readLightParams(
    int idx,
    mat4 lta[64],
    vec4 lca[64],
    vec4 lpa[64]
){
    LightParams L;
    L.type          = int(lpa[idx].x + 0.5);
    L.pos           = lta[idx][3].xyz;
    L.dir           = normalize(-lta[idx][2].xyz); // forward = -Z
    L.color         = lca[idx].xyz;
    L.powerW        = max(lca[idx].w, 0.0);
    L.radiusSurface = max(lpa[idx].y, 0.0);
    L.shadows       = bool(lpa[idx].w);
    L.specularScale = 1.0; // PBR path is energy-conserving by itself
    L.diffuseScale  = 1.0;

    L.spotOuterCos  = cos(radians(45.0));
    L.spotInnerCos  = cos(radians(20.0));
    return L;
}

// ========================================
// Eevee-like BRDF: GGX + Smith + Schlick + Burley
// ========================================
const float PI = 3.14159265359;

float roughPerceptualToAlpha(float r) {
    float a = clamp(r, 0.0, 1.0);
    return max(a * a, 1e-4); // GGX alpha
}

float D_GGX(float NdotH, float a) {
    float a2 = a * a;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d + 1e-7);
}

float G_SchlickSmith(float NdotX, float a) {
    // UE4 variant
    float k = (a * a) * 0.5;
    return NdotX / (NdotX * (1.0 - k) + k + 1e-7);
}

vec3  F_Schlick(vec3 F0, float VdotH) {
    float f = pow(1.0 - VdotH, 5.0);
    return F0 + (1.0 - F0) * f;
}

float Fd_Burley(float NdotL, float NdotV, float LdotH, float a) {
    float a2   = a * a;
    float Fd90 = 0.5 + 2.0 * LdotH * LdotH * a2;
    float FL   = 1.0 + (Fd90 - 1.0) * pow(1.0 - NdotL, 5.0);
    float FV   = 1.0 + (Fd90 - 1.0) * pow(1.0 - NdotV, 5.0);
    return FL * FV;
}

// ========================================
// Eevee-like lighting
// ========================================
vec3 computeLightingEeveeLike(
    vec3 baseAlbedo,                 // linear RGB base color
    float roughnessVal,              // perceptual roughness [0..1]
    vec3 emissiveRGB,                // linear RGB emission
    vec3 worldPos,                   // P
    vec3 N,                          // normal (normalized)
    vec3 V,                          // view dir (normalized)
    uint combinedMask24,             // 24-bit active lights mask
    sampler2D smap,                  // shadow map
    mat4 lta[64],                    // light transforms
    vec4 lca[64],                    // light colors
    vec4 lpa[64]                     // light props
){
    // Default dielectric as in Principled: F0 ~ 0.04 (IOR ~ 1.5)
    vec3 F0 = vec3(0.04);

    float a = roughPerceptualToAlpha(roughnessVal);

    vec3 accum = vec3(0.0);

    uint m = combinedMask24 & 0xFFFFFFu;
    while (m != 0u) {
        uint i = ctz32(m);
        m ^= (1u << i);

        LightParams Lp = readLightParams(int(i), lta, lca, lpa);
        if (Lp.type != 0 && Lp.type != 1) continue;

        // Geometry
        vec3  Lvec = worldPos - Lp.pos; // light -> P
        float d2   = max(dot(Lvec, Lvec), 1e-6);
        float d    = sqrt(d2);
        vec3  L    = -Lvec / d;

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL <= 0.0) continue;

        float NdotV = max(dot(N, V), 0.0);

        // Inverse-square with physical normalization 1/(4π d²)
        float attPhys = 1.0 / (4.0 * PI * d2);

        // Spot cone with smooth edge
        float spot = 1.0;
        if (Lp.type == 1) {
            float cosAng = dot(-L, normalize(Lp.dir));
            float t = saturate((cosAng - Lp.spotOuterCos) / max(Lp.spotInnerCos - Lp.spotOuterCos, 1e-4));
            spot = t * t * (3.0 - 2.0 * t);
        }

        // Shadows
        float visible = 1.0;
        if (Lp.shadows) {
            visible = shadow_computeSoft(worldPos, N, Lp.pos, smap, int(i));
        }

        // Light intensity
        vec3 lightI = Lp.color * (Lp.powerW * attPhys * spot * visible);

        // BRDF
        vec3  H     = normalize(L + V);
        float NdotH = max(dot(N, H), 0.0);
        float VdotH = max(dot(V, H), 0.0);
        float LdotH = max(dot(L, H), 0.0);

        float  D  = D_GGX(NdotH, a);
        float  G  = G_SchlickSmith(NdotV, a) * G_SchlickSmith(NdotL, a);
        vec3   F  = F_Schlick(F0, VdotH);

        vec3  spec = (D * G) * F / max(4.0 * NdotL * NdotV, 1e-6);

        // Energy-conserving blending
        vec3  kd   = (vec3(1.0) - F);
        float Fd   = Fd_Burley(NdotL, NdotV, LdotH, a);
        vec3  diff = (kd * baseAlbedo) * (Fd * NdotL / PI);

        // Sum
        accum += (diff + spec) * lightI;
    }

    return accum + emissiveRGB;
}

// ========================================
// Tonemapping
// ========================================

// ACES fitted (Narkowicz)
vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Simple 3D LUT sampler for AGX (expects linear HDR after exposure, normalized to 0..1 LUT range)
vec3 sampleAgxLUT(sampler3D lut, vec3 color) {
    return texture(lut, saturate(color)).rgb;
}

// AGX Approx without LUT: soft highlight clipping and delicate shoulder desaturation
// This is not 1:1 with official AgX, but very similar response without external data.
vec3 tonemapAGXApprox(vec3 c, float saturation) {
    // Luma for hue-preserving desaturation in shoulders
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));

    // Soft shoulder based on Reinhard + parametric curve
    vec3 reinhard = c / (1.0 + c);
    float shoulder = luma / (1.0 + luma);

    // Smooth desaturation to neutral when burning out
    float t = smoothstep(0.75, 1.0, shoulder);
    vec3  neutral = vec3(luma);
    vec3  mixed = mix(neutral, reinhard, mix(1.0, saturation, 1.0 - t));

    // Light contrast S-curve in mid range
    mixed = pow(saturate(mixed), vec3(1.0 / 1.08));
    return saturate(mixed);
}

vec3 applyTonemap(vec3 hdrColor, int mode, float gamma, float sat, sampler3D lut) {
    // Exposure should already be applied before call
    if (mode == 1) {
        // ACES
        vec3 tm = tonemapACES(hdrColor);
        return pow(tm, vec3(1.0 / max(gamma, 1e-6)));
    } else if (mode == 3) {
        // AGX via LUT
        vec3 tm = sampleAgxLUT(lut, hdrColor);
        return pow(saturate(tm), vec3(1.0 / max(gamma, 1e-6)));
    } else {
        // AGX Approx by default
        vec3 tm = tonemapAGXApprox(hdrColor, sat);
        return pow(tm, vec3(1.0 / max(gamma, 1e-6)));
    }
}

// ========================================
// main
// ========================================
void main() {
    // vec2 screen_uv = gl_FragCoord.xy / size.xy;
    // vec4 tile_Light    = texture(tileLightMap, screen_uv);
    // if(-var_position.z > tile_Light.y+0.1){
    //     discard;
    //     return;
    // }
    
    vec4 albedo    = texture(albedoMap,    var_texcoord0);
    vec4 normalTex = texture(normalMap,    var_texcoord0);
    vec4 roughness = texture(roughnessMap, var_texcoord0);
    vec4 emissive  = texture(emissiveMap,  var_texcoord0);

    #ifdef EDITOR
    out_color = vec4(albedo.rgb, 1.0);
    return;
    #else
    // Camera
    vec3 camPos = mtx_camera_view_inv[3].xyz;

    // Geometry
    vec3 N = buildWorldNormal(normalTex.xyz, vT, vB, vWorldNormal);
    vec3 V = normalize(camPos - vWorldPos);

    // Tile grid and light source mask
    vec2  tiledTexSizeF = size.xy / 10.0;
    ivec2 tiledTexSize  = ivec2(tiledTexSizeF);
    ivec2 tileCoord     = ivec2(floor(gl_FragCoord.xy * tiledTexSizeF / size.xy));
    tileCoord           = clamp(tileCoord, ivec2(0), tiledTexSize - ivec2(1));
    uint combinedMask   = gatherCombinedMask3x3(tileLightMap, tileCoord, tiledTexSizeF);

    // Eevee-like lighting
    vec3 hdrColor = computeLightingEeveeLike(
        albedo.rgb,
        roughness.r,
        emissive.rgb,
        vWorldPos,
        N,
        V,
        combinedMask,
        shadowMap,
        light_transform_array,
        light_color_array,
        light_properties_array
    );

    // Exposure
    float exposureMul = exp2(exposureEV);
    hdrColor *= exposureMul;

    // Tonemapping
    int mode = tonemapMode;
    if (mode == 0) mode = TONEMAP_DEFAULT_MODE;

    //vec3 ldr = applyTonemap(hdrColor, mode, max(gammaOut, 1e-6), saturate(agxSaturation), agxLut);

    out_color = vec4(hdrColor*0.01+albedo.rgb, 1.0);
    #endif
}
