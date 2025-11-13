#version 140

// =====================================================================================
// Screen-Space Ambient Occlusion (SSAO) Fragment Shader
// Dual-radius geometry-aware SSAO implementation using spiral sampling pattern.
// Combines large and small kernels to capture both soft wide occlusion and sharp creases.
// Uses plane-based bias and concavity-driven evaluation for quality and performance.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// ------------------------------------------------------------
// SSAO configuration constants (tweak as needed for your scene)
// ------------------------------------------------------------

// Number of sample pairs (each iteration does 2 fetches: big+small radius).
// Total depth lookups = 2 * SSAO_SAMPLES.
const int   SSAO_SAMPLES          = 16;

// Occlusion radii in world units (view-space meters).
const float SSAO_RADIUS_BIG       = 1.50;
const float SSAO_RADIUS_SMALL     = 0.60;

// Effect strength multiplier (applied before gamma/contrast).
const float SSAO_INTENSITY        = 1.00;

// Gamma/contrast adjustment (e.g. pow(ao, 4.0) for stronger contrast).
const float SSAO_CONTRAST_POW     = 6.00;

// Spiral distribution parameters (relative radius [0..1]).
const float SSAO_SPIRAL_RMIN      = 0.15;
const float SSAO_SPIRAL_RMAX      = 1.00;

// Bias to avoid self-occlusion. Proportional to radius in world units.
const float SSAO_BIAS_SCALE       = 0.02;
const float SSAO_BIAS_MIN         = 0.0005;

// Thickness falloff exponent. Higher → smoother fade, lower → sharper.
const float SSAO_THICKNESS_EXP    = 1.50;

// Distance falloff parameter: 1/(1 + (k*dist)^2). Larger k → stronger suppression.
const float SSAO_DISTANCE_K       = 1.0;

// Plane epsilon: how much under-plane depth counts as occlusion.
// Removes micro-noise on flat surfaces.
const float SSAO_PLANE_EPS        = 0.0005;

// Concavity gain multiplier: >1.0 emphasizes creases/cavities.
const float SSAO_CONCAVITY_GAIN   = 1.15;

// Spiral rotation randomization per pixel (1.0 = enabled).
const float SSAO_ROTATE_PER_PIXEL = 1.0;

// ------------------------------------------------------------
// Inputs
// ------------------------------------------------------------
uniform sampler2D texture_normal;
uniform sampler2D texture_depth;

uniform canvas_uniforms {
    vec4 size; // xy = render target resolution (width, height)
};

uniform camera {
    uniform mat4 mtx_camera_projection;     // Projection matrix
    uniform mat4 mtx_camera_projection_inv; // Inverse projection matrix
    uniform mat4 mtx_camera_view;           // View matrix
};

#include "/src/Assets/Materials/Deferred/Modules/NormalCoder.glsl"

// ------------------------------------------------------------
// Helper functions
// ------------------------------------------------------------

// Reconstruct view-space depth from device depth
float reconstructViewZ(float deviceDepth) {
    const float EPS = 1e-5;
    float ndcZ = deviceDepth * 2.0 - 1.0;
    vec4 clip = vec4(0.0, 0.0, ndcZ, 1.0);
    vec4 view = mtx_camera_projection_inv * clip;
    return view.z / max(view.w, EPS);
}

// Reconstruct full view-space position from depth
vec3 reconstructViewPos(vec2 uv, float deviceDepth) {
    const float EPS = 1e-5;
    vec2 ndcXY = uv * 2.0 - 1.0;
    float ndcZ = deviceDepth * 2.0 - 1.0;
    vec4 clipPos = vec4(ndcXY, ndcZ, 1.0);
    vec4 viewPos = mtx_camera_projection_inv * clipPos;
    return viewPos.xyz / max(viewPos.w, EPS);
}

// Simple 2D hash for noise/random rotation
float hash12(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Convert world-space radius to pixel radius at depth = viewZ
float worldRadiusToPixels(float radiusWorld, float viewZ) {
    // Camera looks down -Z axis, so take |Z|
    float projScale   = mtx_camera_projection[1][1];
    float pxPerMeter  = (size.y * 0.5) * projScale / max(-viewZ, 1e-3);
    return radiusWorld * pxPerMeter;
}

bool outside01(vec2 uv) {
    return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
}

// Spiral sample direction (golden angle)
vec2 spiralDir(int i, float rot) {
    const float GOLDEN_ANGLE = 2.39996323; // radians
    float a = rot + GOLDEN_ANGLE * float(i);
    return vec2(cos(a), sin(a));
}

// ------------------------------------------------------------
// Geometry-aware AO contribution
//
// Instead of just comparing depth, compute relative "height" of sample S
// above the plane defined by point P with normal N. This makes AO less
// sensitive to micro-noise on flat surfaces.
// ------------------------------------------------------------
float aoContribution(vec3 P, vec3 N, vec3 S, float radiusVS, float bias) {
    vec3  v     = S - P;
    float dist  = length(v);
    if (dist <= 1e-4) return 0.0;

    // Height relative to reference plane
    float h = dot(v, N) - bias;

    // Below or on plane → no occlusion
    if (h <= SSAO_PLANE_EPS) return 0.0;

    // Concavity term: how far under the plane, normalized by distance
    float concavity = clamp((h / dist) * SSAO_CONCAVITY_GAIN, 0.0, 1.0);

    // Cosine weighting along normal
    float NoV = max(dot(N, v / dist), 0.0);

    // Thickness fade (towards kernel edge)
    float t      = clamp(dist / (radiusVS + 1e-6), 0.0, 1.0);
    float thick  = pow(1.0 - t, SSAO_THICKNESS_EXP);

    // Distance falloff
    float fall   = 1.0 / (1.0 + (SSAO_DISTANCE_K * dist) * (SSAO_DISTANCE_K * dist));

    // Final contribution
    return concavity * NoV * thick * fall;
}

// ------------------------------------------------------------
// Main SSAO computation (dual-radius kernel)
// ------------------------------------------------------------
float computeSSAO_Dual(vec2 uv, float radiusWorldBig, float radiusWorldSmall) {
    // Center sample
    float depthC = texture(texture_depth, uv).x;
    vec3  P      = reconstructViewPos(uv, depthC);

    // View-space normal (decode from normal buffer)
    vec3 Nw = texture(texture_normal, uv).xyz * 2.0 - 1.0;
    vec3 N  = normalize(mat3(mtx_camera_view) * Nw);

    // Radii in view-space and in pixels
    float rVS_big = radiusWorldBig;
    float rVS_sml = radiusWorldSmall;

    float rPx_big = worldRadiusToPixels(rVS_big, P.z);
    float rPx_sml = worldRadiusToPixels(rVS_sml, P.z);

    // Bias per radius
    float bias_big = max(SSAO_BIAS_MIN, SSAO_BIAS_SCALE * rVS_big);
    float bias_sml = max(SSAO_BIAS_MIN, SSAO_BIAS_SCALE * rVS_sml);

    // Per-pixel random spiral rotation
    float rot = (SSAO_ROTATE_PER_PIXEL > 0.5)
    ? hash12(gl_FragCoord.xy) * 6.28318530718
    : 0.0;

    float occ_big = 0.0;
    float occ_sml = 0.0;

    // Spiral sampling loop
    for (int i = 0; i < SSAO_SAMPLES; ++i) {
        vec2 dir = spiralDir(i, rot);

        float t    = (float(i) + 0.5) / float(SSAO_SAMPLES);
        float t2   = t * t; // concentrate more near the center

        float radPxBig = mix(SSAO_SPIRAL_RMIN, SSAO_SPIRAL_RMAX, t2) * rPx_big;
        float radPxSml = mix(SSAO_SPIRAL_RMIN, SSAO_SPIRAL_RMAX, t2) * rPx_sml;

        // Big radius
        vec2 uvOffB = uv + (dir * radPxBig) / size.xy;
        if (!outside01(uvOffB)) {
            float SdB = texture(texture_depth, uvOffB).x;
            vec3  SB  = reconstructViewPos(uvOffB, SdB);
            occ_big  += aoContribution(P, N, SB, rVS_big, bias_big);
        }

        // Small radius
        vec2 uvOffS = uv + (dir * radPxSml) / size.xy;
        if (!outside01(uvOffS)) {
            float SdS = texture(texture_depth, uvOffS).x;
            vec3  SS  = reconstructViewPos(uvOffS, SdS);
            occ_sml  += aoContribution(P, N, SS, rVS_sml, bias_sml);
        }
    }

    float norm   = float(SSAO_SAMPLES);
    float ao_big = 1.0 - clamp(occ_big / norm, 0.0, 1.0);
    float ao_sml = 1.0 - clamp(occ_sml / norm, 0.0, 1.0);

    // Preserve sharpness by combining both scales (min keeps detail)
    float ao = min(pow(ao_big, 1.15), pow(ao_sml, 1.0));

    // Apply intensity and final contrast curve
    ao = clamp(ao * SSAO_INTENSITY, 0.0, 1.0);
    ao = pow(ao, SSAO_CONTRAST_POW);

    return clamp(ao, 0.0, 1.0);
}

// ------------------------------------------------------------
// Main entry point
// ------------------------------------------------------------
void main() {
    vec2 uv = gl_FragCoord.xy / size.xy;

    float ao = computeSSAO_Dual(uv, SSAO_RADIUS_BIG, SSAO_RADIUS_SMALL);

    gl_FragColor = vec4(vec3(ao), 1.0);
}
