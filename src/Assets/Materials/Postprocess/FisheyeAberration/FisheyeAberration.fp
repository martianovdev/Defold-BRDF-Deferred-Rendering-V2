#version 140

// =====================================================================================
// Fisheye and Chromatic Aberration Fragment Shader
// Post-processing effects: fisheye distortion with auto-cropping and radial chromatic aberration.
// Applies convex lens effect and per-channel color separation with safe edge handling.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 var_texcoord0;

uniform sampler2D u_texture; // Input texture (from previous pass, sRGB 0..1)

// size.xy = viewport (framebuffer) size
uniform data {
    uniform vec4 size;
};

out vec4 fragColor;

// =====================================================================================
// Parameters
// =====================================================================================

// Fisheye (convex lens with auto-cropping)
const float FISHEYE_STRENGTH = 0.20; // >0 = bulging center
const float FISHEYE_POWER    = 2.0;  // curve growth toward edges

// Chromatic Aberration (radial)
const float CA_STRENGTH = 0.020; // max UV shift at edge
const float CA_POWER    = 2.0;   // growth toward edge
const float CA_RED      =  1.0;  // red channel shifted outward
const float CA_GREEN    =  0.0;  // green stays at center
const float CA_BLUE     = -1.0;  // blue channel shifted inward

// CA edge handling
const float CA_EDGE_FADE  = 0.02; // fade-out near edges
const float CA_EDGE_GUARD = 1e-3; // safety margin from border

// =====================================================================================
// maxShiftToEdge: Compute maximum allowed shift in given direction before hitting edge
// =====================================================================================
float maxShiftToEdge(vec2 uv, vec2 dir) {
    const float INF = 1e9;
    vec2 tMax = vec2(INF);

    if (dir.x >  1e-6) tMax.x = (1.0 - uv.x) / dir.x;
    if (dir.x < -1e-6) tMax.x = (0.0 - uv.x) / dir.x;
    if (dir.y >  1e-6) tMax.y = (1.0 - uv.y) / dir.y;
    if (dir.y < -1e-6) tMax.y = (0.0 - uv.y) / dir.y;

    float t = min(tMax.x, tMax.y);
    return max(0.0, t);
}

// =====================================================================================
// applySafeShift: Safely apply chromatic aberration shift with edge fade-out
// =====================================================================================
vec2 applySafeShift(vec2 uv, vec2 dirNorm, float shift, float edgeFade) {
    if (abs(shift) < 1e-8 || (abs(dirNorm.x) + abs(dirNorm.y)) < 1e-8) 
    return uv;

    vec2 d = (shift >= 0.0) ? dirNorm : -dirNorm;
    float maxAllow = maxShiftToEdge(uv, d);
    float req = min(abs(shift) * edgeFade, max(0.0, maxAllow - CA_EDGE_GUARD));
    return uv + d * req;
}

// =====================================================================================
// applyFisheyeCrop: Apply fisheye distortion with automatic pre-scaling
// so that image corners remain inside the viewport after distortion
// =====================================================================================
vec2 applyFisheyeCrop(vec2 uv) {
    vec2 center = vec2(0.5);
    float aspect = size.x / max(size.y, 1.0);

    // Shift UV into [-0.5..0.5], scale X by aspect ratio
    vec2 p = uv - center;
    vec2 q = vec2(p.x * aspect, p.y);

    // Radius of corner in adjusted space
    float rCorner = 0.5 * sqrt(aspect * aspect + 1.0);

    // Distortion factor at corner
    float kCorner = 1.0 + FISHEYE_STRENGTH * pow(rCorner, FISHEYE_POWER);

    // Pre-scale so corners map exactly to edges after distortion
    float preScale = 1.0 / kCorner;
    q *= preScale;

    // Apply fisheye distortion
    float r = length(q);
    float k = 1.0 + FISHEYE_STRENGTH * pow(r, FISHEYE_POWER);
    q *= k;

    // Back to UV space
    vec2 p2 = vec2(q.x / aspect, q.y);
    return center + p2;
}

// =====================================================================================
// Main
// =====================================================================================
void main() {
    vec2 uv0 = gl_FragCoord.xy / size.xy;

    // Fisheye distortion with auto-crop
    vec2 uv = applyFisheyeCrop(uv0);

    // Circular chromatic aberration
    vec2 center = vec2(0.5);
    vec2 toUV   = uv - center;
    float r     = length(toUV);
    vec2 dir    = (r > 1e-6) ? (toUV / r) : vec2(0.0);

    float amt      = CA_STRENGTH * pow(clamp(r, 0.0, 1.0), CA_POWER);
    float edgeFade = 1.0 - smoothstep(1.0 - CA_EDGE_FADE, 1.0, r);

    // Apply per-channel shifts
    vec2 uvR = applySafeShift(uv, dir,  amt * CA_RED,   edgeFade);
    vec2 uvG = applySafeShift(uv, dir,  amt * CA_GREEN, edgeFade);
    vec2 uvB = applySafeShift(uv, dir,  amt * CA_BLUE,  edgeFade);

    // Sample channels separately
    vec3 colR = texture(u_texture, uvR).rgb;
    vec3 colG = texture(u_texture, uvG).rgb;
    vec3 colB = texture(u_texture, uvB).rgb;

    // Recombine into RGB
    vec3 caColor = vec3(colR.r, colG.g, colB.b);
    fragColor = vec4(caColor, 1.0);
}
