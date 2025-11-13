#version 140

// =====================================================================================
// FidelityFX FSR RCAS Fragment Shader
// Robust Contrast-Adaptive Sharpening for post-processing pipeline.
// Applies adaptive sharpening that boosts detail contrast while avoiding oversharpening.
// Optional noise suppression can be enabled for cleaner results.
//
// Author: AMD
// =====================================================================================

in vec2 var_texcoord0;

uniform sampler2D u_texture; // Input texture (already upscaled or base image)

// size.xy = output framebuffer size
// size.zw = input texture size
uniform data {
    uniform vec4 size;
};

// Control parameters
float sharpness = 0.0;       // 0.0 = maximum sharpness .. 2.0 = minimum
bool rcas_denoise = false;   // Enable/disable noise suppression

out vec4 fragColor;

/***** RCAS core defines *****/
#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

// =====================================================================================
// FsrRcasLoadF: Load pixel from texture (p = pixel coordinate in framebuffer space)
// Normalizes pixel coordinates into [0,1] range before sampling
// =====================================================================================
vec4 FsrRcasLoadF(vec2 p) {
    return texture(u_texture, p / size.xy);
}

// =====================================================================================
// FsrRcasCon: Compute sharpening constant based on user sharpness setting
// =====================================================================================
void FsrRcasCon(out float con, float sharpness_) {
    con = exp2(-sharpness_);
}

// =====================================================================================
// FsrRcasF: Main RCAS filter
// - ip: pixel coordinate (in framebuffer pixels)
// - con: sharpening constant
// =====================================================================================
vec3 FsrRcasF(vec2 ip, float con) {
    vec2 sp = vec2(ip);

    // Fetch neighborhood pixels
    vec3 b = FsrRcasLoadF(sp + vec2( 0,-1)).rgb; // top
    vec3 d = FsrRcasLoadF(sp + vec2(-1, 0)).rgb; // left
    vec3 e = FsrRcasLoadF(sp).rgb;               // center
    vec3 f = FsrRcasLoadF(sp + vec2( 1, 0)).rgb; // right
    vec3 h = FsrRcasLoadF(sp + vec2( 0, 1)).rgb; // bottom

    // Approximate luma (green + half of red+blue)
    float bL = b.g + 0.5 * (b.b + b.r);
    float dL = d.g + 0.5 * (d.b + d.r);
    float eL = e.g + 0.5 * (e.b + e.r);
    float fL = f.g + 0.5 * (f.b + f.r);
    float hL = h.g + 0.5 * (h.b + h.r);

    // Noise detection factor
    float nz = 0.25 * (bL + dL + fL + hL) - eL;
    nz = clamp(
        abs(nz) / (
            max(max(bL, dL), max(eL, max(fL, hL))) -
            min(min(bL, dL), min(eL, min(fL, hL)))
        ),
        0.0, 1.0
    );
    nz = 1.0 - 0.5 * nz;

    // Min/max among 4-neighborhood
    vec3 mn4 = min(b, min(f, h));
    vec3 mx4 = max(b, max(f, h));

    // Compute sharpening lobe (contrast adaptive factor)
    vec2 peakC = vec2(1.0, -4.0);
    vec3 hitMin = mn4 / (4.0 * mx4);
    vec3 hitMax = (peakC.x - mx4) / (4.0 * mn4 + peakC.y);
    vec3 lobeRGB = max(-hitMin, hitMax);

    float lobe = max(
        -FSR_RCAS_LIMIT,
        min(max(lobeRGB.r, max(lobeRGB.g, lobeRGB.b)), 0.0)
    ) * con;

    // Optional noise suppression
    if (rcas_denoise) lobe *= nz;

    // Final sharpened pixel
    return (lobe * (b + d + h + f) + e) / (4.0 * lobe + 1.0);
}

// =====================================================================================
// Main entry point
// =====================================================================================
void main() {
    vec2 fragCoord = gl_FragCoord.xy;

    float con;
    FsrRcasCon(con, sharpness);

    vec3 col = FsrRcasF(fragCoord, con);

    fragColor = vec4(col, 1.0);
}
