// =====================================================================================
// Lighting Utilities Module
// Common helper functions for lighting calculations: saturation, normalization,
// luminance, and soft clamping utilities used across lighting shaders.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

const float PI = 3.14159265359;
const float EPS = 1e-5;
const float MAX_FLOAT = 3.4028235e38;

// Clamp helpers
float util_saturateFloat(float x) { return clamp(x, 0.0, 1.0); }
vec2  util_saturateVec2(vec2 v)   { return clamp(v, 0.0, 1.0); }
vec3  util_saturateVec3(vec3 v)   { return clamp(v, 0.0, 1.0); }

// Fast x^5
float util_pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

// Luminance (Rec.709)
float util_luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Safe normalize
vec3 util_safeNormalize(vec3 v) {
    float m2 = max(dot(v, v), EPS);
    return v * inversesqrt(m2);
}

// Soft knee (may be useful in post; inside lighting Eevee doesn't clip)
float util_softKnee(float x, float cap, float knee){
    if (x <= cap) return x;
    float t = (x - cap) / max(knee, 1e-3);
    return cap + knee * (1.0 - exp(-t));
}

vec3 util_softLumaClamp(vec3 c, float cap, float knee){
    float Y = util_luma(c);
    float Yc = util_softKnee(Y, cap, knee);
    float s = (Y > 0.0) ? (Yc / Y) : 1.0;
    return c * s;
}
