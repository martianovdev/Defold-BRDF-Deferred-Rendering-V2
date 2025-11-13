#version 140

// =====================================================================================
// Deferred G-Buffer Fragment Shader
// Writes geometry buffer (albedo, normal, depth, roughness) for deferred rendering pipeline.
// Outputs three render targets: albedo (RGBA), normal+roughness (RGBA), and depth (R).
// Supports distance-based normal map blur to reduce aliasing at depth.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec4 var_position;
in vec3 var_T;
in vec3 var_B;
in vec3 var_N;
in vec2 var_texcoord0;

uniform sampler2D albedoMap;
uniform sampler2D normalMap;   // tangent-space normal map
uniform sampler2D roughnessMap;

// Distance-based normal blur parameters (tune per project)
float normalBlurStartZ = 0.1;   // begin biasing MIP at this depth (non-linear 0..1)
float normalBlurEndZ   = 2.0;   // reach max bias by this depth (non-linear 0..1)
float normalBlurMaxMip = 4.0;   // maximum intended MIP bias in levels

out vec4 fragColor0;
out vec4 fragColor1;
out float fragColor2;

// ======================== include modules ========================
// Encoders/decoders for packing normals (oct, etc.)
#include "/src/Assets/Materials/Deferred/Modules/NormalCoder.glsl"

// Decode normal from RGB normal map (tangent-space)
vec3 decodeNormalRGB(vec3 n_rgb, float strength, bool flipGreen)
{
    vec3 n = n_rgb * 2.0 - 1.0;   // [0..1] -> [-1..1]
    if (flipGreen) n.g = -n.g;    // some content has inverted G (OpenGL vs D3D)
    n.xy *= strength;             // optional intensity
    n.z = sqrt(max(0.0, 1.0 - dot(n.xy, n.xy)));
    return normalize(n);
}

// Decode normal from BC5/RG normal map (tangent-space)
vec3 decodeNormalRG(vec2 n_rg, float strength, bool flipGreen)
{
    vec2 xy = n_rg * 2.0 - 1.0;   // [0..1] -> [-1..1]
    if (flipGreen) xy.y = -xy.y;
    xy *= strength;
    float z = sqrt(max(0.0, 1.0 - dot(xy, xy)));
    return normalize(vec3(xy, z));
}

// Version without packHalf2x16/unpackHalf2x16.
// Uses almost full R16F capacity in [0..1] (~15360 levels) via index to cell center.

// Quantization parameters. Can be changed, but keep product ≤ 15360.
const int NY = 192;  // brightness levels (perceptual)
const int NH = 16;   // hue levels
const int NS = 5;    // saturation levels
const int TOTAL = NY * NH * NS;

const float EPS = 1e-6;

// ===== utils =====
float luma_srgb(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

vec3 rgb2hsv_safe(vec3 c) {
    vec3 rgb = clamp(c, 0.0, 1.0);
    float M = max(max(rgb.r, rgb.g), rgb.b);
    float m = min(min(rgb.r, rgb.g), rgb.b);
    float C = M - m;
    float H = 0.0;
    if (C > 0.0) {
        if (M == rgb.r)       H = (rgb.g - rgb.b) / (C + EPS);
        else if (M == rgb.g)  H = (rgb.b - rgb.r) / (C + EPS) + 2.0;
        else                  H = (rgb.r - rgb.g) / (C + EPS) + 4.0;
        H = fract(H / 6.0);
    }
    float V = M;
    float S = (V > 0.0) ? (C / (V + EPS)) : 0.0;
    return vec3(H, S, V);
}

vec3 hsv2rgb_fast(vec3 c) {
    float H = c.x * 6.0;
    float S = c.y;
    float V = c.z;

    float i = floor(H);
    float f = H - i;

    float p = V * (1.0 - S);
    float q = V * (1.0 - S * f);
    float t = V * (1.0 - S * (1.0 - f));

    if (i < 1.0) return vec3(V, t, p);
    if (i < 2.0) return vec3(q, V, p);
    if (i < 3.0) return vec3(p, V, t);
    if (i < 4.0) return vec3(p, q, V);
    if (i < 5.0) return vec3(t, p, V);
    return vec3(V, p, q);
}

// ===== pack =====
// RGB (0..1) -> one float (0..1) for R16F
float packRGB_to_R16F(vec3 rgb) {
    rgb = clamp(rgb, 0.0, 1.0);

    // features
    vec3 hsv = rgb2hsv_safe(rgb);
    float Y  = luma_srgb(rgb);  // perceptual brightness
    float H  = hsv.x;
    float S  = hsv.y;

    // light brightness compression for smoothness in shadows
    float Yc = pow(Y, 0.5);

    // quantization (cell centers)
    float yqf = clamp(float(NY) * Yc, 0.0, float(NY) - 1e-6);
    float hqf = clamp(float(NH) * H,  0.0, float(NH) - 1e-6);
    float sqf = clamp(float(NS) * S,  0.0, float(NS) - 1e-6);

    int yq = int(floor(yqf + 0.5)); // brightness - nearest
    int hq = int(floor(hqf));       // hue - by sector
    int sq = int(floor(sqf + 0.5)); // saturation - nearest

    yq = clamp(yq, 0, NY - 1);
    hq = clamp(hq, 0, NH - 1);
    sq = clamp(sq, 0, NS - 1);

    // index and cell center
    int idx = (yq * NH + hq) * NS + sq;
    float v = (float(idx) + 0.5) / float(TOTAL);

    // Without f16 rounding. Just return center.
    return v;
}

// ===== unpack =====
// float (0..1) -> approximate RGB (0..1)
vec3 unpackRGB_from_R16F(float v_in) {
    // protection from right boundary
    float v = clamp(v_in, 0.0, 1.0 - (1.0 / float(TOTAL)));

    // nearest index (cell center -> floor)
    int idx = int(floor(v * float(TOTAL)));
    idx = clamp(idx, 0, TOTAL - 1);

    // index decomposition by axes
    int yq = idx / (NH * NS);
    int rem = idx - yq * (NH * NS);
    int hq = rem / NS;
    int sq = rem - hq * NS;

    // restore cell centers
    float Yc = (float(yq) + 0.5) / float(NY);
    float H  = (float(hq) + 0.5) / float(NH);
    float S  = (NS > 1) ? (float(sq) + 0.5) / float(NS) : 0.0;

    // brightness decompression
    float Y = pow(Yc, 2.0);

    // back to RGB via HSV with V≈Y
    vec3 rgb = hsv2rgb_fast(vec3(H, S, Y));

    // soft perceptual brightness adjustment
    float Yr = luma_srgb(rgb);
    if (Yr > EPS) rgb *= clamp(Y / Yr, 0.0, 2.0);

    return clamp(rgb, 0.0, 1.0);
}



void main()
{
    // Non-linear device-space depth as a simple proxy for distance (0..1)
    float z = gl_FragCoord.z;

    // Robust range handling (min/max can be swapped by mistake)
    float zMin = min(normalBlurStartZ, normalBlurEndZ);
    float zMax = max(normalBlurStartZ, normalBlurEndZ);

    // Interpolation factor t over [zMin..zMax]
    float t = 0.0;
    if (zMax > zMin + 1e-6)
    t = clamp((z - zMin) / (zMax - zMin), 0.0, 1.0);

    // Convert desired MIP bias to derivative scale:
    // increasing derivatives by 2^bias roughly climbs `bias` mip levels
    float lodBias    = t * max(normalBlurMaxMip, 0.0);
    float derivScale = exp2(lodBias);

    // Scaled UV derivatives for textureGrad sampling
    vec2 du = dFdx(var_texcoord0) * derivScale;
    vec2 dv = dFdy(var_texcoord0) * derivScale;

    // Fetch base material inputs
    vec4  albedo = texture(albedoMap,   var_texcoord0);
    float rough  = texture(roughnessMap, var_texcoord0).r;

    // Pipeline expects pre-multiplied alpha
    albedo.rgb *= albedo.a;

    // Build TBN matrix from interpolated tangents/bitangents/normals
    mat3 TBN = mat3(normalize(var_T), normalize(var_B), normalize(var_N));

    // --- Normal map sampling ---
    // Option A (recommended with distance-based blur): use textureGrad with scaled derivatives
    // vec3 n_tex = textureGrad(normalMap, var_texcoord0, du, dv).xyz;

    // Option B (no explicit LOD control): regular sampling
    vec3 n_tex = texture(normalMap, var_texcoord0).xyz;

    // Choose your normal format decoder:
    // If your normal map is RGB:
    const float normalStrength = 1.5;
    const bool  flipGreen      = false; // set true if green channel is inverted
    vec3 n_tangent = decodeNormalRGB(n_tex, normalStrength, flipGreen);

    // If your normal map is BC5/RG, use:
    // vec3 n_tangent = decodeNormalRG(textureGrad(normalMap, var_texcoord0, du, dv).rg, normalStrength, flipGreen);

    // Transform to world space
    vec3 world_normal = normalize(TBN * n_tangent);

    // Optional: encode world normal (oct, etc.) via your NormalCoder
    // vec2 enc_world_normal = normalCoder_octEncode(world_normal);
    if(albedo.a < 0.01){
        discard;
    }
    fragColor0 = albedo.rgba;
    fragColor1 = vec4(world_normal * 0.5 + 0.5, rough);
    fragColor2 = gl_FragCoord.z;
    // --- Outputs ---
//     fragColor0 = vec4(
//         packRGB_to_R16F(albedo.rgb), 
//         packRGB_to_R16F(world_normal * 0.5 + 0.5),
//         packRGB_to_R16F(vec3(rough, 0.0, 0.0)), 
//         1.0
//     );
// 



}
