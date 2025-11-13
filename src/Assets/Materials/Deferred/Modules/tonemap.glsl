#ifndef TONEMAP_GLSL
#define TONEMAP_GLSL

// =====================================================================================
// Tonemapping Module
// HDR to LDR color mapping functions: ACES and AGX Approx implementations.
// Provides exposure and gamma correction for final display output.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2  saturate(vec2 v)  { return clamp(v, 0.0, 1.0); }
vec3  saturate(vec3 v)  { return clamp(v, 0.0, 1.0); }

// ACES fitted (Narkowicz)
vec3 tonemapACES(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
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

vec3 tonemap(vec3 hdrColor, float gamma, float sat) {
    vec3 tm = tonemapAGXApprox(hdrColor, sat);
    return pow(tm, vec3(1.0 / max(gamma, 1e-6)));

}

#endif // TONEMAP_GLSL